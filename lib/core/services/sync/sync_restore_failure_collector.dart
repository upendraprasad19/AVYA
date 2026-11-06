part of '../sync_service.dart';

// diagnose b4e7a1 — which streak-critical restore ops REPORTED a failure during
// ONE `restoreFromCloudForUser` call.
//
// WHY A ZONE, AND WHY AT THE FUNNEL. Every `_restoreXxx` op catches its own
// error, calls `_reportSyncFailure(opType: 'restore_<x>')` and RETURNS NORMALLY;
// only the 45 s per-op ceiling in `_safeRestoreOp` ever reaches that wrapper's
// own catch. A "failed critical op" set read from `_safeRestoreOp` is therefore
// blind to nearly every real failure. `_reportSyncFailure` is the single funnel
// (in-op swallow AND the ceiling), so the collector hooks it. The sink is a ZONE
// VALUE, not a field: a concurrent `restoreLightweightAlways` or a push sweep
// runs in another zone and neither pollutes nor clears it, and two overlapping
// restores keep separate sinks. Dart zone values propagate across `Future.wait`,
// `timeout`, timers, streams and microtasks (probed in plan review round 2).
//
// WHAT "SETTLED" MEANS. The restore set no failure among the ops below — NOT
// that every row was fetched (see plan §3 U1.8: empty-answer blind spots, the
// edge function's silent row caps, the A->B->A residual).

/// Op types whose failure means the streak walk's INPUT (schedule rows, the
/// completion ledger, the plan, the profile's onboarding anchor, the freeze
/// state, the deleted-template filter) may be incomplete. An EXACT list, never a
/// `restore_` prefix: `weeklyFullSync` pushes through `_safeRestoreOp('sync_*')`,
/// which produces `restore_sync_*` op types that say nothing about the walk.
///
/// `restore_deleted_template_ids` is the one entry that is NOT emitted through
/// `_reportSyncFailure`: `_deletedTemplateCloudIds` fails EMPTY by design (the
/// safe direction for its deletion filters), but inside a "successful" plan or
/// scheduled-workouts restore an empty answer lets ghost days back in as past
/// `planned` rows, so its catch notes the collector directly.
const Set<String> kStreakCriticalRestoreOpTypes = <String>{
  'restore_workout_plan',
  'restore_workout_logs',
  'restore_schedule_completions',
  'restore_scheduled_workouts',
  'restore_user_progress',
  'restore_user_profile',
  'restore_freezes',
  'restore_deleted_template_ids',
};

/// True when a restore recorded no streak-critical failure.
bool restoreSettlesStreak(Set<String> failures) => failures.isEmpty;

abstract final class RestoreFailureCollector {
  static final Object _zoneKey = Object();

  /// Runs [body] in a zone carrying [sink]; [note] records into it.
  static Future<T> run<T>(Set<String> sink, Future<T> Function() body) =>
      runZoned(body, zoneValues: <Object?, Object?>{_zoneKey: sink});

  /// Records [opType] iff a collector zone is active AND it is on the
  /// streak-critical allowlist. TOTAL: `_reportSyncFailure` is the app-wide
  /// failure funnel and must never throw because of this addition.
  static void note(String opType) {
    try {
      final sink = Zone.current[_zoneKey];
      if (sink is Set<String> && kStreakCriticalRestoreOpTypes.contains(opType)) {
        sink.add(opType);
      }
    } catch (_) {}
  }

  /// Empties the ACTIVE zone's sink (a no-op outside a collector zone). Called
  /// when the single-call attempt FAULTED and the caller runs the verbatim
  /// legacy fan-out: that fan-out re-runs every op and reports its own failures,
  /// so a failure the aborted attempt recorded for an op the legacy path then
  /// restored fine must not hold the marker closed. Only the zone's OWN sink is
  /// touched; a concurrent restore in another zone keeps its failures. TOTAL,
  /// like [note].
  static void clear() {
    try {
      final sink = Zone.current[_zoneKey];
      if (sink is Set<String>) sink.clear();
    } catch (_) {}
  }
}
