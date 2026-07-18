import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

/// Shared PRO next-phase advance — REG-1 fix (a4e2d9).
///
/// A single code path used by BOTH:
///   - the splash silent auto-path (`_autoGenerateNextPhaseForPro`, fired
///     unawaited on app launch), and
///   - the Home/Train `PhaseGeneratingCard` retry CTA — the PRO user's recourse
///     when that silent pass failed or raced (it is fire-and-forget, so a slow
///     or errored generation used to strand a paying user on the FREE
///     `PlanExpiredCard` "go PRO" upsell).
///
/// Reads goal / equipment / days / experience / injuries from the Hive profile
/// (the same inputs onboarding used for Phase 1), generates the next phase IFF
/// the PRO user's current phase has expired, then bumps `user_progress`. Returns
/// `true` iff a new phase was generated (the caller refreshes its providers on
/// `true`).
///
/// This function NEVER swallows errors — it lets them propagate so each caller
/// applies its own handling (splash → `ErrorTelemetry.recordNonFatal`; the card
/// → a retry snackbar + telemetry). The `isPro` / `isPhaseExpired` guards below
/// make it safe to call redundantly: once a phase has been generated,
/// `isPhaseExpired()` is false, so a second call returns `false` without
/// generating again. And the [_advanceInFlight] mutex closes the narrow
/// concurrency window where the splash's unawaited pass and a card tap could
/// BOTH pass the expiry gate before either writes → a double-generate.
bool _advanceInFlight = false;

Future<bool> advanceProPhaseIfExpired(WidgetRef ref) async {
  // Single-isolate mutex: the check+set is atomic (no await between them), so a
  // concurrent splash-pass + card-tap can never both proceed to generation.
  if (_advanceInFlight) return false;
  _advanceInFlight = true;
  try {
    return await _advanceProPhaseIfExpired(ref);
  } finally {
    _advanceInFlight = false;
  }
}

Future<bool> _advanceProPhaseIfExpired(WidgetRef ref) async {
  // C-7 (audit-2026-05-11) — defensive HiveUserSession bootstrap. The splash
  // fires this before `_ensureLocalUser` has opened the per-user namespaced
  // boxes; without this the profile/progress reads below throw
  // `HiveUserSession not opened`.
  final uid = await HiveUserSession.ensureOpenedForCurrentSession();
  if (uid == null) return false;

  // A7 / B5 D9-D10 — canonical provider path (imperative isPro() gate is a
  // point-in-time check inside an action; the UI RENDER guard uses the reactive
  // subscriptionInfoProvider instead — H-1).
  if (!ref.read(subscriptionServiceProvider).isPro()) return false;
  if (!ref.read(workoutScheduleServiceProvider).isPhaseExpired()) return false;

  final profile = UserRepository.instance.getProfile() ?? {};
  final progress = UserRepository.instance.getProgress() ?? {};

  final goal = (profile['primary_goal'] as String?) ?? 'general_fitness';
  final equipment = (profile['equipment_access'] as String?) ?? 'bodyweight';
  final daysPerWeek = (profile['days_per_week'] as num?)?.toInt() ?? 4;
  final experience =
      (profile['fitness_experience'] as String?) ?? 'intermediate';
  final currentPhase = (progress['current_phase'] as int?) ?? 1;
  final rawInjuries = profile['injuries'];
  final injuries = rawInjuries is List
      ? rawInjuries.map((e) => e.toString()).toList()
      : const <String>[];
  final sessionDuration =
      (profile['session_duration_minutes'] as num?)?.toInt();

  final generated = await ref
      .read(workoutScheduleServiceProvider)
      .autoGenerateNextPhaseIfNeeded(
        goal: goal,
        equipment: equipment,
        daysPerWeek: daysPerWeek,
        experienceLevel: experience,
        currentPhase: currentPhase,
        injuries: injuries,
        sessionDuration: sessionDuration,
      );

  if (generated) {
    // Bump user_progress.current_phase + plan_generated_at (monotonic advance).
    final updated = Map<String, dynamic>.from(progress);
    updated['current_phase'] = currentPhase + 1;
    updated['current_week'] = 1;
    updated['plan_generated_at'] = DateTime.now().toIso8601String();
    updated['phase_started_at'] = DateTime.now().toIso8601String();
    await UserRepository.instance.saveProgress(updated);
    // Fire-and-forget snapshot push so the AI coach sees the new Phase.
    unawaited(ref.read(syncServiceProvider).pushSnapshot());
  }
  return generated;
}
