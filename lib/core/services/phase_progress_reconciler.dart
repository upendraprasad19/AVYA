import 'dart:async';

import 'package:flutter/foundation.dart';

import 'error_telemetry.dart';
import 'hive_service.dart';
import 'workout_schedule_read_service.dart';
import '../../shared/repositories/user_repository.dart';
import '../../shared/services/pro_phase_advance.dart';

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
  /// c8f3d1 / Unit 3c — runs under the SHARED [withPhaseAdvanceLock], with a
  /// bounded retry.
  ///
  /// **Why the lock:** this heal derives `completedBlocks` from
  /// [WorkoutScheduleReadService.pastPhaseBlocks] — the `schedule_*` rows that a
  /// concurrent phase advance is at that moment rewriting, along with
  /// `plan_start`, which is what decides "past" vs "current". Bucketing a
  /// half-written window can over-count blocks, and [reconciledPhase]'s own
  /// header says a monotonic over-advance is unrecoverable.
  ///
  /// **Why the retry, and not a bare skip:** [withPhaseAdvanceLock] is a
  /// TRY-lock — it returns `ifBusy` immediately rather than queueing. A single
  /// attempt would mean a contended boot silently drops the heal, and this
  /// method's only callers are on the restore path (`restoring_screen.dart`),
  /// which may not run again for months. Idempotence makes *re-running* safe;
  /// it does not make *skipping* safe. Round-2 review caught exactly that in
  /// round-1's own remediation. Three attempts, 1.5s apart, cover the realistic
  /// contention (a plan generation is tens-to-hundreds of ms); the delay is
  /// paid ONLY when contended, and in that case the user is already waiting on
  /// the advance that holds the lock.
  ///
  /// **Worst-case added latency is 2 s, and it lands on a foreground path.**
  /// `restoring_screen.dart:384` awaits this so the corrected counter is in
  /// place before /home reads `currentPlanProvider` (its own comment says so),
  /// so the retry budget is deliberately small: 3 attempts with 2 gaps of 1 s,
  /// not more. B-pass review flagged the latency and quoted ~4.5 s for the
  /// original 1.5 s gap; the arithmetic is 2 gaps, not 3, so that was 3 s — and
  /// it is 2 s now. Bounded in any case by the restore screen's documented 15 s
  /// CONTINUE escape hatch.
  static const int _lockAttempts = 3;
  static const Duration _lockRetryGap = Duration(seconds: 1);

  static Future<void> reconcile(
      WorkoutScheduleReadService scheduleService) async {
    for (var attempt = 1; attempt <= _lockAttempts; attempt++) {
      final ran = await withPhaseAdvanceLock<bool>(
        () async {
          await _reconcileLocked(scheduleService);
          return true;
        },
        ifBusy: false,
      );
      if (ran) return;
      if (attempt < _lockAttempts) await Future<void>.delayed(_lockRetryGap);
    }
    // Never a silent drop — the whole point of this batch is that a phase
    // conflict stops being invisible.
    unawaited(ErrorTelemetry.logEvent('phase_reconcile_skipped_advance_busy',
        message: 'attempts=$_lockAttempts'));
  }

  static Future<void> _reconcileLocked(
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
