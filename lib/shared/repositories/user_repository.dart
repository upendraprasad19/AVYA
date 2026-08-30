import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';
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

  const ProgressMergeResult({
    required this.merged,
    required this.declinedFields,
    this.malformedFields = const <String>[],
  });

  bool get hasDeclined => declinedFields.isNotEmpty;
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
  for (final f in result.malformedFields) {
    unawaited(ErrorTelemetry.logEvent(
      'progress_restore_field_malformed',
      message: 'source=$source field=$f',
    ));
  }
}

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
  /// Deliberately NOT in this set, each for a reason:
  ///   - `current_streak_days` / `current_streak_weeks` — a streak legitimately
  ///     RESETS to 0. Max-wins would make a genuinely broken streak
  ///     un-resettable from the cloud, which is a worse bug than the one this
  ///     list fixes.
  ///   - the `streak_freezes_*` family — already merged by the dedicated
  ///     `StreakProgressService.mergeFreezeProgress`
  ///     (`sync_restore_completeness.dart:225`). Two merge rules over one field
  ///     is how writer/reader drift starts.
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
  ];

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
  static ProgressMergeResult mergeCloudProgress({
    required Map<String, dynamic> local,
    required Map<String, dynamic> cloud,
  }) {
    final merged = <String, dynamic>{...local};
    final declined = <ProgressDemotion>[];
    final malformed = <String>[];
    // §4.6 kill-switch: verbatim pre-OI-83 behaviour, cloud-non-null-wins for
    // EVERY key including the monotonic ones.
    final guardOff = _monotonicMergeDisabled;

    for (final entry in cloud.entries) {
      if (entry.value == null) continue; // unchanged: cloud null never wins
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
        merged[entry.key] = cloudRaw;
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
        merged[entry.key] = cloudRaw;
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
      } else {
        merged[entry.key] = cloudValue;
      }
    }
    return ProgressMergeResult(
        merged: merged, declinedFields: declined, malformedFields: malformed);
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
    await supabase.from('user_profile').upsert({
      'user_id': userId,
      ..._sanitize(profileData),
    }, onConflict: 'user_id');

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
