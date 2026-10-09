import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/streak_progress_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/profile/services/profile_write_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

/// Result of [UserRepository.clearAllData]. Test #10.1 — surfaces
/// per-box failures so callers (signOut, cross-account guard) can detect
/// silent partial-clear and escalate (force-signOut + sign-in screen).
class ClearResult {
  final Map<String, Object> failures;
  const ClearResult(this.failures);

  bool get isClean => failures.isEmpty;
  bool get hasFailures => failures.isNotEmpty;
  bool failedFor(String box) => failures.containsKey(box);

  @override
  String toString() => isClean
      ? 'ClearResult(clean)'
      : 'ClearResult(failures=${failures.keys.join(", ")})';
}

/// One monotonic field a cloud restore tried to LOWER and was refused
/// (OI-83). Carried out of the pure [UserRepository.mergeCloudProgress] so the
/// callers can emit `progress_restore_demotion_declined` without the merge
/// itself touching telemetry.
class ProgressDemotion {
  final String field;
  final int localValue;
  final int cloudValue;
  const ProgressDemotion({
    required this.field,
    required this.localValue,
    required this.cloudValue,
  });

  @override
  String toString() => '$field local=$localValue cloud=$cloudValue';
}

/// One ISO-date field (`last_workout_date`) a cloud restore tried to move
/// BACKWARDS and was refused (diagnose of Slice C1). The date twin of
/// [ProgressDemotion], whose fields are `int`, so a date needs its own type.
class DateDecline {
  final String field;
  final String localValue;
  final String cloudValue;
  const DateDecline({
    required this.field,
    required this.localValue,
    required this.cloudValue,
  });

  @override
  String toString() => '$field local=$localValue cloud=$cloudValue';
}

/// What [laterIsoDate] decided for one date field.
///
/// [write] is true only when the merged map must take [value] (the cloud date
/// won, or repaired a malformed local one); false means LOCAL stands as it is.
class IsoDateMerge {
  final String? value;
  final bool write;
  final bool declined;
  final bool malformed;
  const IsoDateMerge({
    this.value,
    this.write = false,
    this.declined = false,
    this.malformed = false,
  });
}

/// The calendar day AFTER [isoDay] (`YYYY-MM-DD`), or null when [isoDay] is not
/// a real calendar date.
String? _isoDayPlusOne(String isoDay) {
  final d = _parseIsoDay(isoDay);
  if (d == null) return null;
  // d is UTC midnight; +1 day lands at 05:30 IST on the SAME calendar day, so the
  // IST formatter returns the day after [isoDay] without hand-rolling a key.
  return istDateStr(d.add(const Duration(days: 1)));
}

final RegExp _isoDayShape = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// A real calendar date in UTC, or null: rejects a wrong shape and a shape that
/// does not round-trip (`2026-09-99`, `2026-02-30`).
DateTime? _parseIsoDay(String s) {
  if (!_isoDayShape.hasMatch(s)) return null;
  final y = int.parse(s.substring(0, 4));
  final m = int.parse(s.substring(5, 7));
  final d = int.parse(s.substring(8, 10));
  final t = DateTime.utc(y, m, d);
  if (t.year != y || t.month != m || t.day != d) return null;
  return t;
}

/// PURE latest-wins merge of one ISO-date field for a cloud restore.
///
/// A value is WELL-FORMED only if it is a String of the shape `YYYY-MM-DD`
/// that is a real calendar date and is not later than [istToday] + 1 day (the
/// same ceiling the server clamps to, so a device with its clock set ahead
/// cannot restore a FUTURE date that nothing could ever lower).
///
/// Takes `Object?` because both sides have been through JSON: the file's own
/// `as num?` crash precedent is the comment above `monotonicProgressFields`'s
/// loop in [UserRepository.mergeCloudProgress].
///
/// Rows (L = local, C = cloud; "ok" = well-formed):
/// - L ok, C ok: later wins; C earlier is a DECLINE (local kept).
/// - L absent, C ok: cloud (the reinstall row; NOT malformed).
/// - L malformed, C ok: cloud repairs it, reported malformed.
/// - L ok / absent / malformed, C malformed: local kept, reported malformed.
/// - C absent: the caller never asks (cloud null never wins).
IsoDateMerge laterIsoDate(Object? local, Object? cloud,
    {required String istToday}) {
  final ceiling = _isoDayPlusOne(istToday);
  bool ok(Object? v) =>
      v is String &&
      _parseIsoDay(v) != null &&
      (ceiling == null || v.compareTo(ceiling) <= 0);

  if (cloud is! String || !ok(cloud)) {
    // Garbage (or a future date) never wins. Report it only if it is present.
    return IsoDateMerge(malformed: cloud != null);
  }
  final c = cloud;
  if (local == null) return IsoDateMerge(value: c, write: true);
  if (local is! String || !ok(local)) {
    return IsoDateMerge(value: c, write: true, malformed: true);
  }
  final l = local;
  final cmp = c.compareTo(l);
  if (cmp > 0) return IsoDateMerge(value: c, write: true);
  if (cmp < 0) return const IsoDateMerge(declined: true);
  return const IsoDateMerge();
}

/// Result of [UserRepository.mergeCloudProgress] — the map to persist plus the
/// demotions that were refused. Mirrors the shape of
/// `StreakProgressService.mergeFreezeProgress`'s result, the existing
/// pure-merge-helper precedent for this same Hive map.
class ProgressMergeResult {
  final Map<String, dynamic> merged;
  final List<ProgressDemotion> declinedFields;

  /// Monotonic fields where one side was non-numeric, so the comparison could
  /// not be made and the LOCAL value was kept. Reported separately from
  /// [declinedFields] because "we refused a demotion" and "we could not tell"
  /// are different facts and only the second indicates corrupt data.
  final List<String> malformedFields;

  /// Phase-delta companions (`current_week`, `phase_started_at`,
  /// `plan_generated_at`) kept from local because the merge kept local's
  /// `current_phase` AND cloud's value differed (OI-150).
  ///
  /// A value-IDENTICAL refusal is deliberately not recorded: it changes
  /// nothing, and it would otherwise fire on every counter-only advance made
  /// by `PhaseProgressReconciler`, which is a correct and routine operation.
  final List<String> refusedPhaseDeltaFields;

  /// True when the merged freeze state is AHEAD of (or differs from) the cloud
  /// row the merge read, so the caller must push it with `syncFreezes()` AFTER
  /// it has written [merged] (diagnose c9d2f6). A separate field — not
  /// [declinedFields], whose length and event count are asserted by the OI-83
  /// tests. Computed against the ORIGINAL cloud values, never a carry-adjusted
  /// one, so identical local and cloud state is always `false` (the only
  /// anti-push-storm protection).
  final bool scheduleFreezeSyncUp;

  /// ISO-date fields (`last_workout_date`) where local was LATER than the cloud
  /// row and the restore kept local (Slice C1). Kept apart from
  /// [declinedFields], whose entries are `int` pairs.
  final List<DateDecline> declinedDateFields;

  const ProgressMergeResult({
    required this.merged,
    required this.declinedFields,
    this.malformedFields = const <String>[],
    this.refusedPhaseDeltaFields = const <String>[],
    this.scheduleFreezeSyncUp = false,
    this.declinedDateFields = const <DateDecline>[],
  });

  bool get hasDeclined =>
      declinedFields.isNotEmpty || declinedDateFields.isNotEmpty;
}

/// SHARED telemetry emitter for a refused restore demotion (OI-83). Both
/// restore writers call this rather than each rolling its own `logEvent`, so
/// the event name and payload cannot drift between them — the same reason
/// `markPhaseRepeatNudgePending` exists as one writer for two advance paths.
///
/// One event PER declined field, not one per restore: a restore that would
/// have lowered both `current_phase` and `total_workouts_done` is two distinct
/// facts, and collapsing them would hide the second.
void reportProgressDemotionsDeclined(
  ProgressMergeResult result, {
  required String source,
}) {
  for (final d in result.declinedFields) {
    unawaited(ErrorTelemetry.logEvent(
      'progress_restore_demotion_declined',
      message: 'source=$source field=${d.field} '
          'local=${d.localValue} cloud=${d.cloudValue}',
    ));
  }
  // Slice C1: the date twin, under the SAME event name (already high priority
  // in error_telemetry.dart and its twin log-client-error/index.ts).
  for (final d in result.declinedDateFields) {
    unawaited(ErrorTelemetry.logEvent(
      'progress_restore_demotion_declined',
      message: 'source=$source field=${d.field} '
          'local=${d.localValue} cloud=${d.cloudValue}',
    ));
  }
  for (final f in result.malformedFields) {
    unawaited(ErrorTelemetry.logEvent(
      'progress_restore_field_malformed',
      message: 'source=$source field=$f',
    ));
  }
  // OI-150 / N2. Without this the coupling fires invisibly: nobody could tell
  // from `client_errors` whether the fix ever engages, which is the silent
  // half of the very bug it closes.
  for (final f in result.refusedPhaseDeltaFields) {
    unawaited(ErrorTelemetry.logEvent(
      'progress_restore_phase_delta_refused',
      message: 'source=$source field=$f',
    ));
  }
  // diagnose c9d2f6: the freeze merge kept local ahead of a stale cloud row.
  // LOW priority and best-effort — a LOW event is dropped under the client
  // cooldown, so its ABSENCE proves nothing; the push itself is the observable.
  // Per-process latch so a lightweight restore on every cold start cannot flood.
  if (result.scheduleFreezeSyncUp && !_freezeMergeEngagedReported) {
    _freezeMergeEngagedReported = true;
    unawaited(ErrorTelemetry.logEvent(
      'progress_restore_freeze_merge_engaged',
      message: 'source=$source',
    ));
  }
}

bool _freezeMergeEngagedReported = false;

/// Test seam for the per-process latch above.
@visibleForTesting
void resetFreezeMergeEngagedLatchForTest() => _freezeMergeEngagedReported = false;

/// User CRUD operations via Hive userBox (offline-first).
///
/// All reads/writes go to Hive. Supabase sync is handled separately
/// by [SyncService].
class UserRepository {
  UserRepository._();
  static final UserRepository _instance = UserRepository._();
  static UserRepository get instance => _instance;

  final HiveService _hive = HiveService.instance;

  // ── Profile ─────────────────────────────────────────────────

  /// Returns the user profile map, or null if not yet created.
  Map<String, dynamic>? getProfile() {
    final raw = _hive.userBox.get('profile');
    if (raw == null) return null;
    return Map<String, dynamic>.from(raw as Map);
  }

  /// Saves/updates the user profile.
  ///
  /// Routes through [ProfileWriteService] per audit 2026-05-20 A4 so
  /// the canonical write chokepoint stamps `updated_at` and fires
  /// `SyncService.syncProfileNow` for upstream propagation.
  Future<void> saveProfile(Map<String, dynamic> profile) async {
    await ProfileWriteService.instance.updateProfile(profile);
  }

  /// Updates individual profile fields without overwriting others.
  ///
  /// Routes through [ProfileWriteService.patchProfile] so the merge
  /// happens under the service's mutex (preventing read-modify-write
  /// races with concurrent goal/weight writers).
  Future<void> updateProfileFields(Map<String, dynamic> fields) async {
    await ProfileWriteService.instance.patchProfile(fields);
  }

  // ── Progress ────────────────────────────────────────────────

  /// Returns the user progress map (phase, week, streak, etc.).
  Map<String, dynamic>? getProgress() {
    final raw = _hive.userBox.get('progress');
    if (raw == null) return null;
    return Map<String, dynamic>.from(raw as Map);
  }

  /// Saves/replaces the user progress map.
  ///
  /// ⚠ REPLACE, not merge — this OVERWRITES the whole `progress` key with
  /// exactly the map passed in. B-pass review, Unit 3a: if this races a
  /// concurrent [updateProgress] delta call and lands second, it silently
  /// drops whatever field the delta call had just merged in (confirmed
  /// empirically, not theoretical — see the "REPLACE semantics dropping a
  /// field" test in `user_repository_progress_stale_snapshot_test.dart`).
  /// Only call this when you hold the COMPLETE authoritative state you want
  /// written (e.g. a one-shot reset, or the very first write to a brand-new
  /// account) — never a partial map, and never in a flow where something
  /// else might concurrently be merging a delta via [updateProgress]. If you
  /// only have a delta, call [updateProgress] instead — it merges onto a
  /// fresh read rather than replacing. Today's only 2 real callers
  /// (`simulation_service.dart`'s dev-only `resetJourney`,
  /// `onboarding_provider.dart`'s first-ever write to a new account) satisfy
  /// this by construction, which is why this isn't locked — see below.
  ///
  /// NO LOCK (OI-45 finding 2 / Unit 3a, diagnose TBD) — a `Completer`-based
  /// mutex mirroring `ProfileWriteService._withLock` was tried and REMOVED
  /// after empirical testing, not skipped on assumption. Two findings, both
  /// verified directly (temporarily added/disabled the lock, re-ran the
  /// suite each way — same discipline as the usage-counter-race batch):
  /// (1) it provided NO correctness benefit — every concurrent
  /// updateProgress/saveProgress pairing tested via `Future.wait` landed
  /// correctly with or without it (same structural-safety class as
  /// `UsageCounterService.increment()`: Hive's `Box.put()` lands its
  /// in-memory mutation synchronously, and `Future.wait([a(), b()])` runs
  /// `a()` to its own first suspend point before `b()` is even invoked); (2)
  /// it actively BROKE 2 existing tests
  /// (`streak_decay_reckon_permanent_ledger_test.dart`) by serializing what
  /// were previously two independently-landing UNAWAITED fire-and-forget
  /// calls (`StreakProgressService.commitConsume` and
  /// `WorkoutRepository._persistCurrentStreakDays` both fire un-awaited
  /// `updateProgress` calls within one `reckonStreakDecayAndPersist()` flow)
  /// into a genuine queue — the second call now had to suspend waiting for
  /// the first to release the lock, a real timing change neither caller nor
  /// the pre-existing tests expected. Net: no proven benefit, one concrete
  /// regression — removed. The genuine fix for the real bug (see
  /// [updateProgress]'s doc comment) does not depend on a lock.
  ///
  /// Deployment counter (F18 wiring, 2026-05-31 diagnose b9f4d2): 1 deployment
  /// = 1 completed phase, so deployments_complete = current_phase - 1. Stamped
  /// HERE — the lowest-level progress writer that EVERY phase-advance path
  /// funnels through (updateProgress, splash auto-gen, sim driver, graduation,
  /// onboarding) — so the count is recorded exactly once per advance without
  /// each callsite remembering. MONOTONIC / only-increment: a lifetime "earned"
  /// field (per feedback_monotonic_field_recompute_demotion.md) — never let a
  /// current_phase that moved backwards demote the count. Drives the
  /// PO(>=2)/CPO(>=3) gates in RankService._readEvaluationState and syncs to
  /// user_progress.deployments_complete for the server cron.
  Future<void> saveProgress(Map<String, dynamic> progress) async {
    final phase = (progress['current_phase'] as int?) ?? 1;
    final derivedDeployments = phase > 1 ? phase - 1 : 0;
    final priorDeployments = (progress['deployments_complete'] as int?) ?? 0;
    progress['deployments_complete'] =
        derivedDeployments > priorDeployments ? derivedDeployments : priorDeployments;
    await _hive.userBox.put('progress', progress);
  }

  /// The ISO timestamp the CURRENT phase started, or null when absent.
  ///
  /// A typed accessor rather than callers hand-reading
  /// `getProgress()?['phase_started_at']`, for two reasons. It is the
  /// repository-pattern read rule 4 asks for; and a raw `['phase_started_at']`
  /// literal inside a file that ALSO walks `schedule_*` Hive maps trips Gate 19
  /// (`check_hive_map_field_drift.dart`), whose reader heuristic is file-wide —
  /// it cannot tell which map a bracket access belongs to. Reaching for that
  /// gate's `_alwaysOk` escape hatch would have silenced the field everywhere,
  /// including a REAL future drift of it into a schedule row; keeping the read
  /// in this file (which walks no `schedule_*` map) keeps the gate at full
  /// strength. Introduced by diagnose b7f1c8's tripwire, which needs this value
  /// purely as diagnostic context.
  String? getPhaseStartedAtIso() =>
      getProgress()?['phase_started_at'] as String?;

  /// The progress-map fields that are MONOTONIC — a lifetime/earned counter or
  /// the phase index — where a cloud→Hive restore must never lower the local
  /// value. Founder decision 2026-08-03: **local-max-wins**, with telemetry.
  ///
  /// IN this set since 2026-10-06 (founder decision "A now", after the streak
  /// review): `current_streak_weeks`. Its only production writer
  /// (`train_provider.dart` `completeWorkout`) only INCREMENTS it (+1 per week
  /// that reaches 80% of the planned sessions) and nothing ever resets it, so it
  /// is a lifetime count of good weeks, and a stale cloud row must not lower it
  /// (badges, the coach's streak-risk nudge and the streak-guardian push all
  /// read it). ⚠ If a "reset the weeks when the daily streak breaks" feature is
  /// ever built, REMOVE it from this list in the same change: a local reset to 0
  /// followed by a restore from an older, higher cloud row would otherwise bring
  /// the old number back.
  ///
  /// Deliberately NOT in this set, each for a reason:
  ///   - `current_streak_days` — a streak legitimately RESETS to 0 (the live
  ///     daily walk re-stamps it). Max-wins would make a genuinely broken streak
  ///     un-resettable from the cloud, which is a worse bug than the one this
  ///     list fixes.
  ///   - the `streak_freezes_*` family — merged by the ONE dedicated rule,
  ///     `StreakProgressService.mergeFreezeProgress`, which
  ///     [mergeCloudProgress] now runs as a post-pass (diagnose c9d2f6; it used
  ///     to be cloud-non-null-wins here, so a stale cloud row overwrote a
  ///     fresher local freeze count and `_restoreFreezes`, which runs AFTER
  ///     `_restoreUserProgress`, could not repair it —
  ///     `_restoreFreezes` and `_retrySyncFreezesOnceAfterConflict` in
  ///     `sync_restore_completeness.dart` are the other callers).
  ///     Two merge rules over one field is how writer/reader drift starts.
  ///   - `streak_progress_version` — cloud-ALWAYS-wins is deliberate (Unit 3b,
  ///     `e6b9c4`): it is a server-owned optimistic-lock counter the client
  ///     only ever adopts, and adopting a stale-but-higher local value would
  ///     make the next RPC write fail its version check.
  ///   - `longest_gap_days` — **removed by round-1 review**, and OI-83 had
  ///     listed it. It looks monotonic ("longest ever") but it is INVERTED:
  ///     higher is WORSE, and it gates a rank
  ///     (`rank_service.dart:506` — `s.longestGapDays > gate.maxGapDays` fails
  ///     the rung, and a failed rung blocks every rung above it). No client
  ///     writer populates it — `grep -rn longest_gap_days lib/` finds one
  ///     reader (`rank_service.dart:448`) and two cloud pushes
  ///     (`sync_profile.dart:115,320`), no Hive writer — and migration 115
  ///     already GREATESTs it server-side. So local-max-wins here could only
  ///     ever REFUSE a server correction, permanently pinning a bad value and
  ///     blocking the rank ladder. Max-wins on a field where the maximum is
  ///     the bad outcome is a guard pointed the wrong way.
  @visibleForTesting
  static const List<String> monotonicProgressFields = <String>[
    'current_phase',
    'deployments_complete',
    'total_workouts_done',
    'current_streak_weeks',
    // C2 (diagnose a3c8f1): the calendar week last COUNTED. A calendar-week
    // key only moves forward, so local-max-wins is the right direction.
    'last_counted_week_key',
  ];

  /// The three fields `commitPhaseAdvance` writes ATOMICALLY alongside
  /// `current_phase` (`pro_phase_advance.dart:343-348`, fields at `:344-347`).
  ///
  /// NOT monotonic, and they must never be added to [monotonicProgressFields]:
  /// two are ISO dates and one is a reset-to-1 counter, so max-wins on any of
  /// them is a guard pointed the wrong way — the `longest_gap_days` mistake
  /// documented at :257-266.
  ///
  /// Applied as a POST-PASS over the merged map rather than inside the loop,
  /// which is what makes it order-independent: the cloud row's key order comes
  /// from PostgREST's JSON and is not ours to control, so a decision made
  /// mid-loop could see a companion before it has seen the phase. The loop
  /// itself is untouched, so `current_phase`'s existing demotion and malformed
  /// telemetry keep working exactly as OI-83 shipped them.
  ///
  /// NOT carried by `phase_progress_reconciler.dart:138`, which advances the
  /// counter alone by design (`:20-22` — "WITHOUT touching the in-progress
  /// plan"). Keeping local's companions after a counter-only advance is
  /// correct BY THAT WRITER'S OWN CONTRACT — not because the values happen to
  /// match cloud's. They need not: cloud's companions are last-writer-wins
  /// from any device (`sync_profile.dart:344`), and
  /// `sync_service.dart:1279-1282` can push a `?? DateTime.now()` this device
  /// never held.
  @visibleForTesting
  static const List<String> phaseDeltaCompanionFields = <String>[
    'current_week',
    'phase_started_at',
    'plan_generated_at',
  ];

  @visibleForTesting
  static const String kDisableProgressPhaseDeltaCouplingKey =
      'disable_progress_phase_delta_coupling';

  /// §4.6 kill-switch for the companion coupling, deliberately INDEPENDENT of
  /// [kDisableProgressRestoreMonotonicMergeKey]: rolling this back must not
  /// also disable the shipped OI-83 monotonic guard.
  ///
  /// Reads through `HiveService.instance`, not the instance field `_hive`,
  /// because this is a static member — matching [_monotonicMergeDisabled]
  /// at :340. Fails CLOSED (coupling stays active) when the box is not open.
  static bool get _phaseDeltaCouplingDisabled {
    try {
      return HiveService.instance.configBox
              .get(kDisableProgressPhaseDeltaCouplingKey) ==
          true;
    } catch (_) {
      return false;
    }
  }

  /// §4.6 / the `platform`-tier `feature_flag` requirement in
  /// `docs/blast_radius.yaml:25`. Set `true` in `configBox` to make
  /// [mergeCloudProgress] return the pre-OI-83 expression verbatim.
  ///
  /// A kill-switch IS warranted here, unlike the pure `phaseAdvanceTarget`
  /// guard whose doc argues one would only re-enable a defect. The difference:
  /// that guard is a total order on one field, while this is a per-field
  /// JUDGEMENT LIST, and round-1 review proved the list can be wrong — it
  /// caught `longest_gap_days` pointing the guard backwards. A wrong entry
  /// needs a runtime escape hatch, not a rebuild.
  static const String kDisableProgressRestoreMonotonicMergeKey =
      'disable_progress_restore_monotonic_merge';

  static bool get _monotonicMergeDisabled {
    try {
      return HiveService.instance.configBox
              .get(kDisableProgressRestoreMonotonicMergeKey) ==
          true;
    } catch (_) {
      // Box not open (pre-boot / test) — the guard stays ACTIVE. Failing
      // closed is right: an unopened box must not silently disable a guard.
      return false;
    }
  }

  /// §4.6 kill-switch for the freeze-family post-pass and the control-plane
  /// key skip (diagnose c9d2f6). INDEPENDENT of
  /// [kDisableProgressRestoreMonotonicMergeKey], which stays the WIDER
  /// rollback: when EITHER is set, [mergeCloudProgress] takes the pre-fix
  /// cloud-non-null-wins branch for those keys verbatim.
  @visibleForTesting
  static const String kDisableProgressFreezeMergeKey =
      'disable_progress_freeze_merge';

  /// Fails CLOSED (the new behaviour stays ACTIVE) when the box is not open —
  /// the same shape as [_monotonicMergeDisabled].
  static bool get _freezeMergeDisabled {
    try {
      return HiveService.instance.configBox
              .get(kDisableProgressFreezeMergeKey) ==
          true;
    } catch (_) {
      return false;
    }
  }

  /// §4.6 kill-switch for the `last_workout_date` latest-wins merge (Slice C1).
  /// INDEPENDENT of both neighbours: set = `last_workout_date` takes the
  /// pre-addendum generic cloud-non-null-wins branch, and the wider
  /// [kDisableProgressRestoreMonotonicMergeKey] still copies everything
  /// verbatim. Fails CLOSED (the new behaviour stays ACTIVE) when the box is
  /// not open.
  @visibleForTesting
  static const String kDisableProgressDateMergeKey =
      'disable_progress_date_merge';

  static bool get _dateMergeDisabled {
    try {
      return HiveService.instance.configBox.get(kDisableProgressDateMergeKey) ==
          true;
    } catch (_) {
      return false;
    }
  }

  /// The freeze family that [mergeCloudProgress] merges by the ONE rule
  /// (`StreakProgressService.mergeFreezeProgress`) instead of copying from
  /// cloud. The cloud's plural `used_dates` column is read here and written to
  /// the singular local key by the post-pass; it is never copied under its own
  /// name.
  static const Set<String> _freezeFamilyKeys = <String>{
    'streak_freezes_available',
    'streak_freezes_last_refill',
    'streak_freezes_first_pro_grant_done',
    'streak_freezes_used_dates',
  };

  /// Control-plane columns that have no place in the progress SEMANTIC key set
  /// (`sync_profile.dart`'s own pre-strip, day-swapper Task 20). The
  /// sign-in-hydrate caller (`auth_session_bootstrapper.dart`) passes the RAW
  /// cloud row, so without this it spread the whole `plan_json` blob into
  /// `userBox['progress']`.
  static const Set<String> _controlPlaneKeys = <String>{
    'user_id',
    'plan_json',
    'sync_epoch',
  };

  /// PURE merge for a cloud→Hive `progress` restore (OI-83). No Hive, no
  /// telemetry, no clock — the callers fire the telemetry from [declinedFields]
  /// so this stays testable, mirroring `phaseAdvanceTarget` /
  /// `PhaseProgressReconciler.reconciledPhase`.
  ///
  /// **What was wrong.** Two restore writers —
  /// `sync/sync_profile.dart` `_restoreUserProgress` and
  /// `auth_session_bootstrapper.dart` — built the merged map as
  /// `{...local, for (e in cloud.entries) if (e.value != null) e.key: e.value}`,
  /// i.e. cloud-non-null-wins for EVERY key. A device that advanced locally and
  /// had not yet pushed would have `current_phase` (and the three other
  /// lifetime counters) silently lowered by its own restore — no guard, no
  /// telemetry, no trace. That is the
  /// `feedback_monotonic_field_recompute_demotion` class; siblings `3a7b9f`
  /// (rank demoted after a recompute) and `c8f3d1` (the advance-side guard,
  /// which sits on `commitPhaseAdvance` and these writers never reach).
  ///
  /// **Why a reinstall is unaffected.** The demotion only bites when local is
  /// AHEAD of cloud. On a genuine restore local is empty, so `max` is the cloud
  /// value and this is byte-identical to the old merge.
  ///
  /// Values are read with `(v as num?)?.toInt()` — the CLOUD-payload idiom
  /// (`sync_profile.dart:100,289,301`), because this map has been through JSON.
  /// `commitPhaseAdvance` reads the same field as `as int?` and is also right:
  /// it reads the HIVE side, where the `int4` schema guarantee holds.
  /// A field that is non-numeric on either side falls through to
  /// cloud-non-null-wins rather than throwing — a malformed row must not break
  /// the whole restore.
  ///
  /// NOT `@visibleForTesting`, unlike the same-file `phaseAdvanceTarget`
  /// precedent it otherwise mirrors: this has two PRODUCTION callers in other
  /// libraries, and the annotation would make both an
  /// `invalid_use_of_visible_for_testing_member` warning.
  ///
  /// [istToday] is the IST calendar day (`istDateStr(nowWall())`) both callers
  /// pass; `last_workout_date` is merged latest-wins and a date later than
  /// [istToday] + 1 is treated as malformed (Slice C1, [laterIsoDate]).
  static ProgressMergeResult mergeCloudProgress({
    required Map<String, dynamic> local,
    required Map<String, dynamic> cloud,
    required String istToday,
  }) {
    final merged = <String, dynamic>{...local};
    final declined = <ProgressDemotion>[];
    final declinedDates = <DateDecline>[];
    final malformed = <String>[];
    // OI-150: set by the loop at the two branches where local's `current_phase`
    // survives. Read by the post-pass below, so the companion decision cannot
    // depend on where `current_phase` sits in cloud's key order.
    // N1 (review round 2): local's phase also survives on two paths the loop
    // cannot signal — cloud omitting the key entirely (never visited), and
    // cloud carrying an explicit null (an early `continue`). Both leave local's
    // value standing, so both must couple the companions or the fix leaves the
    // exact split it exists to prevent. Seeded here for the key-absent case.
    // §4.6 kill-switch: verbatim pre-OI-83 behaviour, cloud-non-null-wins for
    // EVERY key including the monotonic ones.
    //
    // ⚠ Computed BEFORE the seed below, and the seed is gated on it. B-pass
    // finding 1: the seed and the cloud-null branch originally ran ahead of
    // this read, so rolling the OI-83 switch left the OI-150 coupling still
    // firing — the switch promises "verbatim pre-OI-83" and pre-OI-83 had no
    // companion coupling at all. The two switches are independent in the sense
    // that rolling the NEW one leaves OI-83 intact; the reverse is not true
    // and must not be, because the older switch is the wider rollback.
    final guardOff = _monotonicMergeDisabled;
    // diagnose c9d2f6: the freeze family and the control-plane keys leave the
    // cloud-copy loop below and are handled by the post-pass. Either switch
    // restores the pre-fix copy for them verbatim.
    final freezeMergeOn = !guardOff && !_freezeMergeDisabled;
    var phaseKeptLocal = !guardOff &&
        local['current_phase'] != null &&
        !cloud.containsKey('current_phase');

    for (final entry in cloud.entries) {
      if (entry.value == null) {
        // N1: cloud null never wins — so if this is the phase, local's value
        // survived and the companions must move with it.
        if (!guardOff &&
            entry.key == 'current_phase' &&
            local[entry.key] != null) {
          phaseKeptLocal = true;
        }
        continue; // unchanged: cloud null never wins
      }
      if (freezeMergeOn &&
          (_freezeFamilyKeys.contains(entry.key) ||
              _controlPlaneKeys.contains(entry.key))) {
        continue; // merged by the post-pass / never copied
      }
      // Slice C1: `last_workout_date` is LATEST-wins, not cloud-wins. The old
      // generic branch let a stale restore move a newer, not-yet-pushed local
      // date backwards, and the next push wrote the regression to the cloud.
      if (!guardOff &&
          entry.key == 'last_workout_date' &&
          !_dateMergeDisabled) {
        final outcome =
            laterIsoDate(local[entry.key], entry.value, istToday: istToday);
        if (outcome.malformed) malformed.add(entry.key);
        if (outcome.declined) {
          declinedDates.add(DateDecline(
            field: entry.key,
            localValue: '${local[entry.key]}',
            cloudValue: '${entry.value}',
          ));
        }
        if (outcome.write) merged[entry.key] = outcome.value;
        continue;
      }
      if (guardOff || !monotonicProgressFields.contains(entry.key)) {
        merged[entry.key] = entry.value;
        continue;
      }
      // `is num` TEST, not an `as num?` cast. The cast form THROWS on a
      // non-numeric value rather than yielding null, so the "malformed row
      // must not break the whole restore" intent below would have been a lie —
      // the first bad row would have thrown out of the merge and aborted the
      // restore. Caught by this unit's own malformed-row test.
      final localRaw = local[entry.key];
      final cloudRaw = entry.value;

      // ⚠ ORDER IS LOAD-BEARING, and both orderings have already been wrong.
      //
      // Cloud non-numeric is checked FIRST (round-2 review P2): when it was
      // checked second, `local absent × cloud garbage` short-circuited into
      // "adopt cloud" and wrote the garbage through reporting nothing — the
      // exact hop-the-crash-downstream case the malformed guard exists to stop.
      if (cloudRaw is! num) {
        malformed.add(entry.key);
        // OI-150: local's phase survived — but only count it as "kept" when
        // local ACTUALLY HAD one. "Kept whatever local had" when local had
        // nothing is not a kept value, and treating it as one would refuse a
        // reinstalling user's companions into absence too.
        if (entry.key == 'current_phase' && localRaw != null) {
          phaseKeptLocal = true;
        }
        continue; // keep whatever local had (possibly nothing)
      }

      // ABSENT local is not malformed — it is the fresh-reinstall case, and the
      // single most common path through this function. Take cloud.
      //
      // ⚠ This branch exists because its absence was a P0, caught by this
      // unit's own reinstall test during round-1 fixes: the first attempt at
      // the malformed-value guard treated `null is! num` as malformed and
      // `continue`d, which DROPPED current_phase / deployments_complete /
      // total_workouts_done from the merged map entirely — a reinstalling user
      // would have restored with no phase at all. The guard against corrupt
      // data must not fire on the ordinary absence of data.
      if (localRaw == null) {
        // The marker is read `as int?` downstream: a cloud double must not
        // be written through.
        merged[entry.key] =
            entry.key == 'last_counted_week_key' ? cloudRaw.toInt() : cloudRaw;
        continue;
      }

      if (localRaw is! num) {
        // LOCAL is present but not numeric, so the comparison cannot be made.
        // Cloud is already known-numeric (checked above), so take it — a good
        // cloud value REPAIRS a corrupt local one — and report the corruption.
        //
        // Round-1 review P3: the earlier version wrote the cloud value through
        // unconditionally and reported nothing, so "a malformed row must not
        // break the restore" was only half true — the merge didn't throw, but
        // every downstream reader does (`pro_phase_advance.dart` and
        // `rank_service.dart:448` both read this family `as int?`, which THROWS
        // on a String rather than yielding null). Persisting garbage silently
        // just moves the crash one hop.
        malformed.add(entry.key);
        merged[entry.key] =
            entry.key == 'last_counted_week_key' ? cloudRaw.toInt() : cloudRaw;
        continue;
      }
      final localValue = localRaw.toInt();
      final cloudValue = cloudRaw.toInt();
      if (cloudValue < localValue) {
        declined.add(ProgressDemotion(
          field: entry.key,
          localValue: localValue,
          cloudValue: cloudValue,
        ));
        merged[entry.key] = localValue; // local-max-wins
        // OI-150: the refused demotion IS the signal that local is ahead.
        if (entry.key == 'current_phase') phaseKeptLocal = true;
      } else {
        merged[entry.key] = cloudValue;
      }
    }

    // ── OI-150: the phase delta moves as one group ──────────────────────────
    //
    // `commitPhaseAdvance` writes current_phase + current_week +
    // phase_started_at + plan_generated_at as ONE atomic delta and its own doc
    // comment (:295-298) says a skip must skip the WHOLE delta. OI-83 guarded
    // only the first, so a stale cloud row split the group and the merged
    // result was written straight back to Hive — leaving local and cloud
    // agreeing on a shape neither ever wrote.
    //
    // A POST-PASS, deliberately: `merged` already starts as `{...local}`, so
    // anything a companion still holds from local needs no action and only a
    // value cloud actually changed is restored. That makes this independent of
    // cloud's key order, which PostgREST decides.
    final refusedPhaseDelta = <String>[];
    if (phaseKeptLocal && !_phaseDeltaCouplingDisabled) {
      for (final key in phaseDeltaCompanionFields) {
        final localValue = local[key];
        // Carve-out: refuse only a companion local ACTUALLY HOLDS. The
        // `updateProgress` seed (:584-590) writes current_phase with no dates,
        // and `PhaseProgressReconciler:138` then advances the phase alone — so
        // a phase-ahead map with no `phase_started_at` is reachable. Refusing
        // an absent key would drop it from the merged map entirely and anchor
        // the next plan regeneration at today.
        if (localValue == null) continue;
        // Cloud did not change it — nothing refused, nothing to report.
        if (merged[key] == localValue) continue;
        refusedPhaseDelta.add(key);
        merged[key] = localValue;
      }
    }

    // ── diagnose c9d2f6: the freeze family is merged by the ONE rule ────────
    //
    // A POST-PASS for the same reason as the OI-150 pass above: PostgREST's key
    // order is not ours, and the rule needs `available`, `last_refill`,
    // `used_dates` and the grant flag TOGETHER.
    final scheduleFreezeSyncUp =
        freezeMergeOn && _mergeFreezeFamily(local, cloud, merged);

    return ProgressMergeResult(
      merged: merged,
      declinedFields: declined,
      malformedFields: malformed,
      refusedPhaseDeltaFields: refusedPhaseDelta,
      scheduleFreezeSyncUp: scheduleFreezeSyncUp,
      declinedDateFields: declinedDates,
    );
  }

  /// The freeze-family post-pass of [mergeCloudProgress]. Writes the merged
  /// freeze state into [merged] BY INDEX ASSIGNMENT only — the sole-writer
  /// contract (`streak_progress_service_concurrency_test.dart`) greps raw
  /// source for a map-literal key, and this file is not on its allowlist.
  ///
  /// Returns whether the merged state must be pushed to the cloud
  /// (see [ProgressMergeResult.scheduleFreezeSyncUp]).
  ///
  /// Inputs are built with `is` tests, never the throwing `as num?` cast (the
  /// `is num` TEST comment in [mergeCloudProgress] records that bug). A cloud
  /// row whose `streak_freezes_available` is absent or non-numeric (the column
  /// is `INTEGER NOT NULL`, so this is defensive) skips the whole post-pass and
  /// leaves LOCAL verbatim — stricter than the pre-fix copy and safe against
  /// the hard `as int?` readers in `workout_repository.dart`.
  static bool _mergeFreezeFamily(
    Map<String, dynamic> local,
    Map<String, dynamic> cloud,
    Map<String, dynamic> merged,
  ) {
    final cloudAvailableRaw = cloud['streak_freezes_available'];
    if (cloudAvailableRaw is! num) return false;
    final cloudAvailable = cloudAvailableRaw.toInt();

    final localAvailableRaw = local['streak_freezes_available'];
    var localAvailable =
        localAvailableRaw is num ? localAvailableRaw.toInt() : cloudAvailable;
    final localAvailableBeforeCarry = localAvailable;

    final cloudGrantRaw = cloud['streak_freezes_first_pro_grant_done'];
    final cloudGrant = cloudGrantRaw == true;
    final localGrant = local['streak_freezes_first_pro_grant_done'] == true;

    final localLastRefillRaw = local['streak_freezes_last_refill'];
    var localLastRefill =
        localLastRefillRaw is String ? localLastRefillRaw : null;
    final cloudLastRefillRaw = cloud['streak_freezes_last_refill'];
    // Postgres `date` arrives as `YYYY-MM-DD`, as `_restoreFreezes` reads it.
    final cloudLastRefill = cloudLastRefillRaw?.toString();

    final localUsedRaw = local['streak_freeze_used_dates'];
    final localUsed = localUsedRaw is List
        ? localUsedRaw.map((e) => e.toString()).toList()
        : const <String>[];
    // The cloud COLUMN is plural; the local key is singular.
    final cloudUsedRaw = cloud['streak_freezes_used_dates'];
    final cloudUsed = cloudUsedRaw is List
        ? cloudUsedRaw.map((e) => e.toString()).toList()
        : const <String>[];

    // Grant carry (ASYMMETRIC only). The cloud already recorded the one-shot
    // first-PRO grant (3) and this device has not: without the carry the
    // same-week LOWER rule would clamp a free-cap local count (1) onto the
    // granted 3 and the flag would then block a re-grant. Two refinements
    // (B-pass, reviewer A F2):
    //  - a consume this device made that the cloud ledger has not seen comes OFF
    //    the carried count, so the carry never refunds one ({0,W,flag F} against
    //    cloud {3,W,flag T} with one unseen local used date is 2, not 3);
    //  - a local week stamp NEWER than the cloud's was seeded by a pre-restore
    //    refill under the FREE cap, so the cloud's older stamp is adopted and
    //    the next `refillIfNewWeek` (which runs after the restore, under the
    //    real cap) tops the week up — exactly what the pre-fix whole-row copy
    //    did. Keeping the newer stamp would silently drop that week's +1.
    // There is deliberately NO symmetric carry (local flag true, cloud not):
    // `_restoreFreezes` and the conflict retry merge with the plain rule and
    // would undo it; the local grant is handled below instead.
    if (cloudGrant && !localGrant && cloudAvailable > localAvailable) {
      final unseenLocalConsumes =
          localUsed.toSet().difference(cloudUsed.toSet()).length;
      final carried = cloudAvailable - unseenLocalConsumes;
      if (carried > localAvailable) localAvailable = carried;
      if (cloudLastRefill != null &&
          localLastRefill != null &&
          cloudLastRefill.compareTo(localLastRefill) < 0) {
        localLastRefill = cloudLastRefill;
      }
    }

    final result = StreakProgressService.mergeFreezeProgress(
      localAvailable: localAvailable,
      localUsed: localUsed,
      localLastRefill: localLastRefill,
      cloudAvailable: cloudAvailable,
      cloudUsed: cloudUsed,
      cloudLastRefill: cloudLastRefill,
    );

    merged['streak_freezes_available'] = result.available;
    // Do not invent an empty ledger on a side that never had one.
    if (result.usedDates.isNotEmpty || localUsedRaw is List) {
      merged['streak_freeze_used_dates'] = result.usedDates;
    }
    if (result.lastRefill != null) {
      merged['streak_freezes_last_refill'] = result.lastRefill;
    }
    // The local grant is AHEAD of the cloud row when this device granted (flag
    // true) and the cloud has not seen it (flag false) — its push is in flight
    // or failed, so the cloud's lower count is the PRE-grant state. The plain
    // rule then clamps the granted 3 onto that count ("EATEN"). An eaten grant
    // must NOT be claimed: writing the flag true next to the lost count blocks
    // `grantFirstProFreezes` for good, while leaving the flag at the cloud's
    // false is the pre-fix outcome in this race and self-heals (that method
    // runs on every PRO boot and re-grants while the flag is unset). A grant
    // that survived the merge is claimed and pushed as before. (B-pass,
    // reviewer A F1.)
    final localGrantAhead = localGrant && !cloudGrant;
    final grantEaten =
        localGrantAhead && result.available < localAvailableBeforeCarry;
    // `local || cloud`: matches `_restoreFreezes`'s own documented intent
    // ("never regress a local true back to cloud false"), except for an eaten
    // grant above. Written when the cloud carried a bool (pre-fix copied it) or
    // local already held true.
    if (cloudGrantRaw is bool || localGrant) {
      merged['streak_freezes_first_pro_grant_done'] =
          grantEaten ? cloudGrant : (localGrant || cloudGrant);
    }

    // Push when the merged state is AHEAD of / differs from the ORIGINAL cloud
    // row (not the carry-adjusted one). `used_dates` is compared as a SET.
    final cloudUsedSet = cloudUsed.toSet();
    final mergedUsedSet = result.usedDates.toSet();
    final usedDiffers = mergedUsedSet.length != cloudUsedSet.length ||
        !mergedUsedSet.containsAll(cloudUsedSet);
    return result.scheduleSyncUp ||
        result.available != cloudAvailable ||
        (result.lastRefill != null && result.lastRefill != cloudLastRefill) ||
        usedDiffers ||
        (localGrantAhead && !grantEaten);
  }

  // ── Pending Promotion (Theme B, diagnose 2026-05-22 9aa2c1) ────
  //
  // One-shot top-level Hive key stamped by RankService when a rank
  // change is detected. Home screen reads + clears on mount/resume
  // and pushes PromotionCelebrationScreen. NOT synced to cloud (no
  // corresponding column in user_progress) — purely client-side
  // celebration state. Survives hot restart because it's durable Hive.

  static const String _pendingPromotionKey = 'pending_promotion_rank_code';

  String? getPendingPromotionRankCode() {
    return _hive.userBox.get(_pendingPromotionKey) as String?;
  }

  Future<void> setPendingPromotionRankCode(String rankCode) async {
    await _hive.userBox.put(_pendingPromotionKey, rankCode);
  }

  Future<void> clearPendingPromotionRankCode() async {
    await _hive.userBox.delete(_pendingPromotionKey);
  }

  /// Updates individual progress fields without overwriting others.
  ///
  /// Bug 2026-05-22 (Theme F-NEW, diagnose ec4d27) — pre-fix, this method
  /// wrote to Hive but did NOT fire syncProgressNow. The only callsite
  /// that pushed user_progress to cloud was train_provider.dart:1485
  /// (post-workout-completion). Every other mutation (phase unlock,
  /// edit profile, etc.) accumulated in Hive without reaching cloud.
  /// Founder's cloud user_progress.updated_at was 20+ days stale despite
  /// active app use.
  ///
  /// Fix: fire-and-forget `unawaited(syncProgressNow())` after the Hive
  /// write — matches the canonical WriteService pattern from
  /// lib/core/services/CLAUDE.md (Hive first → invalidate → sync).
  ///
  /// OI-45 finding 2 / Unit 3a fix (diagnose TBD): [getProgress] is called
  /// fresh, right here, every time this method runs — so a caller passing
  /// just the fields it wants to change (instead of a whole map it read
  /// earlier, across its own real `await`) always merges onto whatever is
  /// in Hive AT THE MOMENT this method is called, never a stale snapshot.
  /// This is what fixed pro_phase_advance.dart and simulation_service.dart,
  /// which used to read `progress`, await real (slow) plan generation, then
  /// write the WHOLE map back from that pre-await snapshot via
  /// [saveProgress] — silently clobbering anything an independent writer
  /// landed during the gap. Converting both to `updateProgress(delta)`
  /// closes that gap, proven directly (not just argued) in
  /// `user_repository_progress_stale_snapshot_test.dart`'s "OLD pattern
  /// documents the bug" / "NEW pattern proves the fix" pair — the same test
  /// file also confirms this fix does NOT depend on any lock (a `Completer`
  /// mutex was tried here and removed; see [saveProgress]'s doc comment for
  /// why).
  Future<void> updateProgress(Map<String, dynamic> fields) async {
    final current = getProgress() ?? {
      'current_phase': 1,
      'current_week': 1,
      'total_workouts_done': 0,
      'current_streak_weeks': 0,
    };
    current.addAll(fields);
    // deployments_complete is stamped inside saveProgress (single source) so
    // it tracks current_phase monotonically across every advance path.
    await saveProgress(current);
    // Fire-and-forget cloud sync — never block the UI. SyncService
    // captures failures via recordNonFatal + _reportSyncFailure.
    unawaited(SyncService.instance.syncProgressNow());
  }

  /// Clears the session-scoped "a freeze was just spent" notice: the flag, the
  /// count of freezes it covers and the `streak_freeze_remaining_after_use`
  /// snapshot, in ONE delta write (never a whole-map replace, see
  /// [updateProgress]). The ONE clearer: Home calls it as it shows the notice,
  /// the cold-start path in `restoring_screen.dart` calls it for a flag a
  /// previous session never showed. The three keys are local-only; the cleared
  /// state reads as "no notice" and the next debit starts counting from one.
  Future<void> clearStreakFreezeNotice() async {
    // No progress map yet means no notice to clear; [updateProgress] would
    // mint a default map just to hold three UI keys.
    if (getProgress() == null) return;
    await updateProgress({
      'streak_freeze_just_used': false,
      'streak_freeze_just_used_count': 0,
      'streak_freeze_remaining_after_use': null,
    });
  }

  // ── Preferences ─────────────────────────────────────────────

  /// Returns the user preferences map.
  Map<String, dynamic>? getPreferences() {
    final raw = _hive.userBox.get('preferences');
    if (raw == null) return null;
    return Map<String, dynamic>.from(raw as Map);
  }

  /// Saves/replaces the user preferences.
  Future<void> savePreferences(Map<String, dynamic> preferences) async {
    await _hive.userBox.put('preferences', preferences);
  }

  // ── Onboarding ──────────────────────────────────────────────

  /// Whether the user has completed onboarding.
  ///
  /// Test #10.1 — Reads via [MigratedKey] so the value sources from the
  /// per-user `userBox` post-migration (preventing cross-account leak),
  /// with `configBox` fallback for installs that haven't yet run the
  /// one-shot migration.
  bool get isOnboarded {
    return MigratedKey.readWithDefault<bool>('onboarding_completed', false);
  }

  /// Marks onboarding as complete.
  Future<void> setOnboarded() async {
    await MigratedKey.write('onboarding_completed', true);
  }

  // ── Detected Experience ─────────────────────────────────────

  /// Returns the AI-detected experience level, or null.
  String? get detectedExperience {
    return _hive.userBox.get('detected_experience') as String?;
  }

  /// Saves the detected experience level.
  Future<void> setDetectedExperience(String level) async {
    await _hive.userBox.put('detected_experience', level);
  }

  // ── Units ─────────────────────────────────────────────────────

  /// Whether the user prefers metric units (default: true).
  bool getUnitsMetric() {
    return (_hive.configBox.get('units_metric', defaultValue: true) as bool?) ??
        true;
  }

  /// Saves the user's unit preference.
  Future<void> setUnitsMetric(bool metric) async {
    await _hive.configBox.put('units_metric', metric);
  }

  // ── Computed Targets ─────────────────────────────────────────

  /// Ensures computed nutrition fields (daily_calories, protein_grams, etc.)
  /// exist in the profile. If missing but BMR/TDEE inputs are available,
  /// recalculates them using BmrCalculator.
  Future<void> ensureComputedTargets() async {
    final profile = getProfile();
    if (profile == null) return;

    // Already has computed targets — nothing to do.
    // OBS-11 dual-name: a RESTORED profile carries only the cloud PLURAL
    // `carbs_grams`; the singular-only check would false-negative → recompute
    // → write-back drifted targets over the canonical. Read both spellings.
    if (profile['daily_calories'] != null &&
        profile['protein_grams'] != null &&
        (profile['carb_grams'] ?? profile['carbs_grams']) != null &&
        profile['fat_grams'] != null) {
      return;
    }

    // Need enough data to recalculate.
    final weightKg = (profile['current_weight_kg'] as num?)?.toDouble();
    final heightCm = (profile['height_cm'] as num?)?.toDouble();
    final gender = profile['gender'] as String?;
    final goal = profile['primary_goal'] as String? ?? 'general_fitness';
    final activityLevel = profile['activity_level'] as String? ?? 'moderate';
    final dob = profile['date_of_birth'] as String?;

    if (weightKg == null ||
        weightKg <= 0 ||
        heightCm == null ||
        heightCm <= 0 ||
        gender == null) {
      return;
    }

    int age = 25; // fallback
    if (dob != null) {
      final birthDate = DateTime.tryParse(dob);
      if (birthDate != null) {
        final now = DateTime.now();
        age = now.year - birthDate.year;
        if (now.month < birthDate.month ||
            (now.month == birthDate.month && now.day < birthDate.day)) {
          age--;
        }
        if (age <= 0) age = 25;
      }
    }

    final bodyFat = (profile['body_fat_percent'] as num?)?.toDouble();
    final targets = BmrCalculator.calculateTargets(
      weightKg: weightKg,
      heightCm: heightCm,
      age: age,
      gender: gender,
      activityLevel: activityLevel,
      goal: goal,
      pacePreference: profile['pace_preference'] as String? ?? 'balanced',
      targetWeightKg: (profile['target_weight_kg'] as num?)?.toDouble(),
      bodyFatPercent: bodyFat,
    );

    await updateProfileFields(targets.toMap());
  }

  // ── Diet Plan ─────────────────────────────────────────────────

  /// Saves a generated diet plan to the per-user `userBox`
  /// (migrated from configBox in Test #11.1).
  Future<void> saveDietPlan(Map<String, dynamic> planData) async {
    await MigratedKey.write('saved_diet_plan', planData);
  }

  /// Returns the saved diet plan, or null if none exists.
  Map<String, dynamic>? getSavedDietPlan() {
    final raw = MigratedKey.read<Map>('saved_diet_plan');
    if (raw == null) return null;
    return Map<String, dynamic>.from(raw);
  }

  // ── Clear All Data (Logout) ───────────────────────────────────

  /// Clears all user-specific Hive boxes (keeps exerciseBox, foodBox,
  /// and migrationBox).
  ///
  /// Test #10.1 — Each box is wrapped in its own try/catch so one
  /// failure (e.g., GuardedBox ownership exception during a
  /// session-state race) does NOT abort subsequent box clears. The
  /// caller can inspect [ClearResult.failures] to detect partial
  /// failure and react (e.g., the cross-account guard force-signs-out
  /// the user instead of letting them into a poisoned home screen).
  ///
  /// Used during sign-out and cross-account guard recovery to wipe
  /// local user data while preserving seeded reference data +
  /// one-shot migration flags.
  Future<ClearResult> clearAllData() async {
    final failures = <String, Object>{};

    Future<void> tryClear(String label, Future<void> Function() op) async {
      try {
        await op();
      } catch (e, st) {
        failures[label] = e;
        // audit-2026-05-11 H-42 — telemetry pair.
        debugPrint('[clearAllData] $label failed: $e');
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'user_repository_clear_all_data'));
      }
    }

    // User-scoped boxes — wrapped by GuardedBox; can throw if session
    // state desyncs. Each independent so a throw doesn't abort the chain.
    await tryClear('userBox',          () async => _hive.userBox.clear());
    await tryClear('workoutBox',       () async => _hive.workoutBox.clear());
    await tryClear('nutritionBox',     () async => _hive.nutritionBox.clear());
    await tryClear('healthBox',        () async => _hive.healthBox.clear());
    await tryClear('coachBox',         () async => _hive.coachBox.clear());
    await tryClear('customBox',        () async => _hive.customBox.clear());
    await tryClear('notificationsBox', () async => _hive.notificationsBox.clear());
    // Shared mutable boxes — must clear so next user doesn't inherit
    // state (until UserConfigMigrator finishes the configBox→userBox move).
    await tryClear('syncBox',          () async => _hive.syncBox.clear());
    await tryClear('configBox',        () async => _hive.configBox.clear());
    // NEVER cleared:
    //   exerciseBox / foodBox — seeded read-only reference data
    //   migrationBox — one-shot device-lifetime flags that MUST survive
    //     sign-out, otherwise migrations re-run and re-leak data.

    return ClearResult(failures);
  }

  // ── Supabase Sync (background, fire-and-forget) ──────────────────

  /// Uploads an image to Supabase Storage and returns the public URL.
  ///
  /// [bucket] — Storage bucket name (e.g. 'avatars', 'banners').
  /// [filePath] — Path within the bucket (e.g. '$userId/avatar.jpg').
  /// [bytes] — Raw image bytes to upload.
  ///
  /// Throws on failure so the caller can handle errors.
  static Future<String> uploadImage({
    required String bucket,
    required String filePath,
    required Uint8List bytes,
  }) async {
    await SupabaseService.instance.client.storage
        .from(bucket)
        .uploadBinary(filePath, bytes, fileOptions: const FileOptions(upsert: true));

    final publicUrl = SupabaseService.instance.client.storage
        .from(bucket)
        .getPublicUrl(filePath);

    return publicUrl;
  }

  /// Updates specific fields in the Supabase `user_profile` table.
  ///
  /// Fire-and-forget: catches all errors and logs them via debugPrint.
  static Future<void> updateSupabaseProfileField({
    required String userId,
    required Map<String, dynamic> fields,
  }) async {
    try {
      await SupabaseService.instance.client.from('user_profile').upsert(
        {'user_id': userId, ...fields},
        onConflict: 'user_id',
      );
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[UserRepository] updateSupabaseProfileField failed: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'user_repository_update_supabase_profile_field'));
    }
  }

  /// Syncs onboarding data to Supabase: users, user_profile, and user_progress.
  ///
  /// Only sends columns that exist in the Supabase tables — the local profile
  /// map contains computed fields (daily_calories, protein_grams, etc.) that
  /// are stored in Hive but do NOT have corresponding Postgres columns.
  ///
  /// Throws on failure so the caller can detect sync gaps.
  static Future<void> syncOnboardingToSupabase({
    required String userId,
    required Map<String, dynamic> userData,
    required Map<String, dynamic> profileData,
    required Map<String, dynamic> progressData,
  }) async {
    final supabase = SupabaseService.instance.client;

    await supabase.from('users').upsert({
      'id': userId,
      ..._sanitize(userData),
    });

    // CRITICAL — both `user_profile` and `user_progress` have `id uuid` as
    // primary key and a separate UNIQUE constraint on `user_id`. Supabase
    // Dart's `.upsert()` defaults to conflict-on-primary-key, so without
    // `onConflict: 'user_id'` the client generates a fresh `id` each call,
    // tries to INSERT, and trips the UNIQUE(user_id) constraint → 23505
    // throws. When that exception fires on user_profile the subsequent
    // user_progress upsert never executes — which is exactly how we ended
    // up with `users.onboarding_completed = true` but an all-null
    // user_profile row and zero rows in user_progress after a fresh
    // sign-up test on 2026-04-17.
    //
    // Second bug fixed in the same 2026-04-17 pass: the caller hands us a
    // profileData map that can contain empty-string values for strict-typed
    // Postgres columns (date_of_birth = "", wake_up_time = "", etc.).
    // PostgREST responds 400 "invalid input syntax for type date" and the
    // entire row is rejected. `_sanitize` drops those entries so the upsert
    // succeeds with whatever the user did provide.
    // a2b-2 (single-owner batch, 2026-09-27): coach_extraction_locked_fields
    // (migration 148) MUST be written ONLY via lockCoachExtractionFields'
    // additive-union RPC — never via this blind spread, which would
    // overwrite it wholesale. `_sanitize` is a denylist (empty
    // strings/non-finite numbers), not a column allowlist, so it would pass
    // this key through unchanged if a future caller ever added it to
    // profileData. Stripped explicitly here as defense-in-depth; today's
    // real onboarding_provider.dart profileData map never includes this key
    // (confirmed by reading it), so this line is currently a no-op guard,
    // not a live fix.
    final sanitizedProfileData = _sanitize(profileData)
      ..remove('coach_extraction_locked_fields');
    await supabase.from('user_profile').upsert({
      'user_id': userId,
      ...sanitizedProfileData,
    }, onConflict: 'user_id');

    // Lock `injuries` when onboarding actually collected a real injury
    // selection — matches the Details-screen convention
    // (`_injuries.isEmpty` seeds `['none']`, the "no injuries" default) so a
    // genuinely-injured user's onboarding entry can't be overwritten by the
    // AI-coach extraction pass later (migration 148). The default `['none']`
    // is NOT locked: it is a filled-in default, not a deliberate user
    // statement, so the AI should still be free to populate real injuries
    // from chat for a user who skipped this at onboarding.
    //
    final onboardingInjuries = profileData['injuries'];
    if (onboardingInjuries is List &&
        shouldLockOnboardingInjuries(List<String>.from(onboardingInjuries))) {
      unawaited(lockCoachExtractionFields(['injuries']));
    }

    // Unit 3b round-1-review P1 fix (2026-07-30): user_progress routes
    // through the SAME optimistic-lock RPC every other progress writer uses
    // (migration 115's update_user_progress_snapshot) instead of a raw
    // version-blind upsert — see SyncService.pushOnboardingProgressSnapshot's
    // doc comment for why a raw upsert here was a real, live cross-device
    // race. _sanitize still runs first (drops empty-string values that would
    // 400 a strict-typed column, e.g. a blank date).
    await SyncService.instance.pushOnboardingProgressSnapshot(
      userId: userId,
      progressData: _sanitize(progressData),
    );
  }

  /// Pure decision, extracted for testability (a2b-2, single-owner batch,
  /// 2026-09-27): should onboarding's `injuries` answer be locked against
  /// AI-coach extraction? Only when it is genuinely non-default —
  /// `details_screen.dart` seeds `_injuries = ['none']` whenever the user
  /// never answers, so the onboarding answer is NEVER actually empty; a
  /// plain non-empty check would therefore lock injuries for 100% of new
  /// signups regardless of whether a real answer was given.
  ///
  /// Uses `listEquals`, never a bare `!=` — `List` does not override `==`
  /// in Dart, so `injuries != const ['none']` would be REFERENCE
  /// inequality, always true, which would reproduce the exact "locks 100%
  /// of new signups" bug this function exists to avoid, just via a
  /// different mechanism (matches this file's own
  /// `listEquals(_injuries, _originalInjuries)` convention in
  /// edit_profile_screen.dart).
  @visibleForTesting
  static bool shouldLockOnboardingInjuries(List<String> injuries) {
    return !listEquals(injuries, const ['none']);
  }

  /// Additive-only lock: marks [fields] (subset of `diet_preference` /
  /// `lifestyle_activity` / `injuries`) as user-owned in
  /// `user_profile.coach_extraction_locked_fields`, so daily-snapshot's
  /// coach-extraction merge (migration 148) skips them instead of silently
  /// overwriting a manual edit. Best-effort: swallows failure after one
  /// retry — a lock RPC that never lands means the NEXT extraction pass
  /// might still overwrite the field once, which is a much smaller harm than
  /// blocking the profile save the caller is running this alongside.
  static Future<void> lockCoachExtractionFields(List<String> fields) async {
    if (fields.isEmpty) return;
    final supabase = SupabaseService.instance.client;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await supabase.rpc('lock_coach_extraction_fields', params: {
          'p_fields': fields,
        });
        return;
      } catch (e, st) {
        if (attempt == 1) {
          // H-42 telemetry pair.
          debugPrint(
            '[UserRepository] lockCoachExtractionFields($fields) failed after retry (non-fatal): $e',
          );
          unawaited(ErrorTelemetry.recordNonFatal(e, st,
              reason: 'user_repository_lock_coach_extraction_fields'));
        }
      }
    }
  }

  // ── Account Management ───────────────────────────────────────────────────
  //
  // audit-2026-05-16 E.8 — `softDeleteAccount(userId)` method DELETED.
  // APK Test #11 Task H1 replaced the soft-delete flow with the canonical
  // 2-step hard-delete via the `delete-account` Edge Function (see
  // `DeleteAccountScreen`). The legacy method had 0 production callers for
  // 3 weeks; founder approved deletion via Phase D NEEDS_DECISION 4
  // Option A. Tests at `test/features/profile/delete_account_screen_test.dart`
  // H1-E group (which previously asserted the deprecated method still
  // compiled) are deleted in the same batch.

  // ── AI Assessment (Edge Functions) ───────────────────────────────────────

  /// Invokes the `assess-body-composition` Edge Function with the given photo
  /// and biometric context.
  ///
  /// Returns the raw response data map on HTTP 200, or throws a
  /// [BodyCompositionAssessmentException] carrying the server's `code` and
  /// `error` fields on any non-200 status.
  static Future<Map<String, dynamic>> assessBodyComposition({
    required String imageBase64,
    required String mimeType,
    required double weightKg,
    required double heightCm,
    required String gender,
    required int age,
  }) async {
    // §2.31: callFunction refreshes the JWT (+ cold-start retry) before the
    // authed invoke — a stale token would 401 (check_authed_invoke_fresh_token).
    final response = await SupabaseService.instance.callFunction(
      'assess-body-composition',
      body: {
        'image_base64': imageBase64,
        'mime_type': mimeType,
        'weight_kg': weightKg,
        'height_cm': heightCm,
        'gender': gender,
        'age': age,
      },
    );
    if (response.status != 200) {
      final data = response.data as Map? ?? {};
      final code = data['code'] as String?;
      final error = data['error'] as String? ?? 'Assessment failed';
      final nextAllowedAt = data['next_allowed_at'] as String?;
      throw BodyCompositionAssessmentException(
        code: code,
        message: error,
        status: response.status,
        nextAllowedAt: nextAllowedAt,
      );
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  // ── Sanitize ─────────────────────────────────────────────────────────────

  /// Strips empty strings and non-finite numbers from a payload map.
  /// Null values are preserved (PostgREST happily stores NULL in nullable
  /// columns) but empty strings on strict-typed columns (date, time, numeric,
  /// integer, timestamptz) would otherwise reject the entire upsert.
  ///
  /// Also coerces the five integer-only target columns
  /// (daily_calories / protein_grams / carbs_grams / fat_grams /
  /// water_target_ml) via `.round()` — NutritionTargets stores them as int
  /// today, but a stale Hive row from a pre-migration-021 client could hold a
  /// double and tank the whole row.
  static const _integerOnlyColumns = <String>{
    'daily_calories',
    'protein_grams',
    'carbs_grams',
    'fat_grams',
    'water_target_ml',
    'days_per_week',
    'session_duration_minutes',
    'bmr',
    'tdee',
  };

  static Map<String, dynamic> _sanitize(Map<String, dynamic> input) {
    final out = <String, dynamic>{};
    input.forEach((key, value) {
      if (value is String && value.trim().isEmpty) {
        // Drop empty string — column is either nullable (fine to omit) or
        // strict-typed and would reject the whole row.
        return;
      }
      if (value is double && (value.isNaN || value.isInfinite)) {
        return;
      }
      if (_integerOnlyColumns.contains(key) && value is num) {
        out[key] = value.round();
      } else {
        out[key] = value;
      }
    });
    return out;
  }
}

/// Thrown by [UserRepository.assessBodyComposition] when the Edge Function
/// returns a non-200 status. Callers can switch on [code] for known error
/// conditions ('pro_required', 'rate_limited', 'unsuitable_image').
class BodyCompositionAssessmentException implements Exception {
  const BodyCompositionAssessmentException({
    required this.code,
    required this.message,
    required this.status,
    this.nextAllowedAt,
  });

  /// Server-supplied error code (e.g. 'pro_required', 'rate_limited',
  /// 'unsuitable_image'). May be null for unexpected failures.
  final String? code;

  /// Human-readable error message from the server.
  final String message;

  /// HTTP status code from the Edge Function response.
  final int status;

  /// ISO-8601 timestamp after which the user may next request an assessment.
  /// Only present when [code] == 'rate_limited'.
  final String? nextAllowedAt;

  @override
  String toString() =>
      'BodyCompositionAssessmentException(code=$code, status=$status, message=$message)';
}
