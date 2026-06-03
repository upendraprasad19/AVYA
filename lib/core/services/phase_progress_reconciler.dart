import 'dart:async';

import 'package:flutter/foundation.dart';

import 'error_telemetry.dart';
import 'hive_service.dart';
import 'workout_schedule_read_service.dart';
import '../../shared/repositories/user_repository.dart';

/// Heals + maintains the phase-progress invariant:
///
///   `current_phase >= (completed past phase blocks) + 1`
///
/// **Root cause it closes** (two-Phase-1 bug, diagnose 2026-06-02): a phase was
/// completed but `current_phase` never advanced — e.g. a regeneration wrote a
/// fresh *same-numbered* plan instead of advancing — leaving the Train screen
/// rendering a completed "PHASE I (DONE)" next to a current "PHASE I", and the
/// counter stuck. The fix is the founder-chosen **"advance, keep progress"**:
/// advance the counter to match the number of phases the user has moved past,
/// WITHOUT touching the in-progress plan (streak + weeks-done preserved) and
/// WITHOUT deleting or rewriting any schedule row.
///
/// Properties:
///  - **Monotonic** — only ever *increases* `current_phase` (never demotes;
///    mirrors `feedback_monotonic_field_recompute_demotion.md`).
///    `deployments_complete` is then stamped by `UserRepository.saveProgress`
///    (`= max(prior, current_phase-1)`).
///  - **Idempotent** — a no-op once consistent, so it is safe to run on EVERY
///    boot. This also self-heals any *future* duplicate regardless of which
///    code path created it (the recurrence guard). Free users (always Phase 1,
///    zero completed blocks) are always a no-op.
///  - **Block count is the shared SoT** —
///    [WorkoutScheduleReadService.pastPhaseBlocks], the same bucketing the week
///    selector renders, so the counter and the display can't drift.
///  - **Kill-switch** — skips when `configBox['disable_phase_reconciler']` is
///    `true` (§4.6 — a risky-change escape hatch without a rebuild).
class PhaseProgressReconciler {
  PhaseProgressReconciler._();

  /// Hive `configBox` flag; set `true` to disable the reconciler at runtime.
  static const String killSwitchKey = 'disable_phase_reconciler';

  /// Pure decision (visible for testing): the phase to advance to, or `null`
  /// when already consistent. MONOTONIC — only ever returns a value greater than
  /// [currentPhase]; returns `null` (no-op) when the counter already covers the
  /// completed blocks, so a free/new user (0 blocks) or an already-advanced user
  /// is never touched and a counter is NEVER demoted.
  @visibleForTesting
  static int? reconciledPhase(int currentPhase, int completedBlocks) {
    final expected = completedBlocks + 1;
    if (currentPhase >= expected) return null; // consistent / never demote
    // Defensive bound (Hermes d4b8e2 follow-up): an implausibly large jump
    // (>12 phases ≈ a year of back-to-back completion) signals corrupted /
    // overlapping schedule data, not a real advance. A monotonic over-advance
    // is unrecoverable, so refuse it — the kill-switch + a manual heal cover the
    // (extremely rare) legitimate case. Normal advances are +1, occasionally +2.
    if (expected - currentPhase > 12) return null;
    return expected;
  }

  /// Reconcile the current user's phase counter against their completed phase
  /// blocks. [scheduleService] is injected so this is callable from the boot
  /// path (via the Riverpod provider) and from tests (via a ProviderContainer)
  /// without the deprecated singleton.
  static Future<void> reconcile(
      WorkoutScheduleReadService scheduleService) async {
    try {
      if (HiveService.instance.configBox.get(killSwitchKey) == true) return;

      // Without a known plan window we cannot classify "past" vs "current"
      // schedule rows → skip rather than risk over-counting (every row would
      // otherwise read as "past"). A reconcilable user always has a plan_start.
      if (scheduleService.getPlanStartDate() == null) return;

      final progress = UserRepository.instance.getProgress();
      if (progress == null) return; // pre-onboarding — nothing to reconcile

      final currentPhase = (progress['current_phase'] as int?) ?? 1;
      final completedBlocks = scheduleService.pastPhaseBlocks().length;

      final target = reconciledPhase(currentPhase, completedBlocks);
      if (target == null) return; // already consistent — monotonic no-op

      // updateProgress merges the field, stamps deployments_complete from
      // current_phase (monotonic), and fires syncProgressNow() to cloud.
      await UserRepository.instance.updateProgress({'current_phase': target});

      unawaited(ErrorTelemetry.logEvent(
        'phase_progress_reconciled',
        message: 'from=$currentPhase to=$target blocks=$completedBlocks',
      ));
    } catch (e, st) {
      // Non-fatal — never block boot on a reconciliation hiccup.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'phase_progress_reconciler'));
    }
  }
}
