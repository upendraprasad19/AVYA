// lib/core/services/plan_integrity_reconciler.dart
//
// Heals the plan-schedule invariant after a fresh-install restore:
//
//   every PLANNED workout day in the current plan window carries its
//   workout_name + exercises[] (the content the cloud `scheduled_workouts`
//   table cannot supply — it has NO exercises / NO name column).
//
// **Root cause it closes** (restore plan_json skip, diagnose 2026-06-06): on a
// reinstall a plan was locally (re)generated before/around restore, so
// `_restoreWorkoutPlan`'s `if (current_plan != null) return` early-returned and
// the exercise-rich `plan_json.schedules` snapshot was never applied. Only the
// exercise-less `_restoreScheduledWorkouts` populated the days, so every
// not-yet-completed day rendered "REST DAY / No exercises scheduled" with a
// dead START button. The same skip left `plan_start_date` stale, cascading into
// the week/phase numbering.
//
// The reconciler re-applies the cloud `plan_json` snapshot — plan_start_date +
// the date-keyed schedules — using the SAME completed-status-preserving merge
// the restore path uses (a locally-completed day is authoritative and is never
// overwritten by the frozen snapshot).
//
// Properties (mirrors [PhaseProgressReconciler]):
//  - **Symptom-gated** — does NOTHING (no network) unless the current plan
//    window actually has a contentless planned workout day, so a healthy user
//    is always a cheap local no-op.
//  - **Idempotent** — safe to run on every boot; a second run finds no symptom.
//  - **Completed-day safe** — never overwrites a local `status='completed'`
//    day or its `completed_at` (mirrors `feedback_monotonic_field_recompute_demotion`).
//  - **Kill-switch** — skips when `configBox['disable_plan_integrity_reconciler']`
//    is `true` (§4.6 risky-change escape hatch without a rebuild).

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';

import 'day_swap/day_swap_rules.dart';
import 'error_telemetry.dart';
import 'hive_service.dart';
import 'migrated_key.dart';
import 'plan_window_reanchor.dart';
import 'sync_flags.dart';
import 'sync/sync_skip_index.dart';
import 'supabase_service.dart';
import 'sync_service.dart';
import 'template_identity.dart';
import 'workout_schedule_read_service.dart';

/// OI-252 (stable ID rework) — true when [entry] (a raw `plan_json.schedules`
/// value, LOCAL Hive-key shape) is assigned to a template that is in
/// [deletedTemplateCloudIds] (cloud ids). A frozen `plan_json` snapshot can
/// carry a day scheduled against a template deleted since the snapshot was
/// taken — reapplying it during a restore/heal would resurrect exactly the
/// reference the delete removed. Shared by `_restoreWorkoutPlan`
/// (`sync/sync_workout.dart`) and [PlanIntegrityReconciler.reconcile] so the
/// two ghost-day filters can't drift, the same reasoning as
/// [PlanIntegrityReconciler.mergeScheduleEntry] being shared with the
/// restore path.
///
/// PURE — no I/O, `@visibleForTesting`-exposed via being a public top-level
/// function (this file already keeps `mergeScheduleEntry` etc. as static
/// members instead; this one is top-level so `sync_workout.dart`, which is
/// `part of '../sync_service.dart'` and cannot see file-private members of a
/// DIFFERENT library, can call it without going through the class).
bool isGhostScheduleEntry(
  Map<String, dynamic> entry,
  Set<String> deletedTemplateCloudIds,
) {
  final templateKey = entry['template_id'] as String?;
  if (templateKey == null) return false;
  final cloudId = cloudIdFromKey(templateKey);
  return cloudId != null && deletedTemplateCloudIds.contains(cloudId);
}

class PlanIntegrityReconciler {
  PlanIntegrityReconciler._();

  /// Hive `configBox` flag; set `true` to disable the reconciler at runtime.
  static const String killSwitchKey = 'disable_plan_integrity_reconciler';

  static const String _schedulePrefix = 'schedule_';
  static const String _planStartKey = 'plan_start_date';
  static const String _planEndKey = 'plan_end_date';

  /// PURE production helper (shared by the restore path + the boot heal so they
  /// can't drift): merge one `plan_json.schedules` entry into the local Hive
  /// `schedule_*` entry. The plan_json snapshot is the source of the content
  /// (`workout_name` + `exercises[]` + `type` + `workout_focus`) that the
  /// exercise-less `scheduled_workouts` restore drops; the LOCAL row is the
  /// source of live progress (`status` / `completed_at`).
  ///
  ///  - no local row            → take the snapshot wholesale.
  ///  - local `completed`       → KEEP local untouched (the logged session +
  ///                              status are authoritative; never demote to the
  ///                              frozen `planned` snapshot).
  ///  - otherwise (planned/rest)→ take the snapshot's content but keep the
  ///                              local live `status` / `completed_at`.
  static Map<String, dynamic> mergeScheduleEntry(
    Map<String, dynamic>? existing,
    Map<String, dynamic> planJson, {
    bool forceSnapshotArrangement = false,
  }) {
    if (existing != null && existing['status'] == 'completed') {
      return _normalizeHybrid(Map<String, dynamic>.from(existing));
    }
    // Spec 2026-09-26-day-swapper-design.md sec 5.7 L3: a genuinely NEWER
    // downloaded arrangement for this week takes the snapshot's row
    // WHOLESALE (content, status, markers) — the completed guard above
    // already returned, so this can never demote a completed day (I6).
    if (forceSnapshotArrangement) {
      return _normalizeHybrid(Map<String, dynamic>.from(planJson));
    }
    if (existing == null) return _normalizeHybrid(Map<String, dynamic>.from(planJson));
    // If the local day ALREADY has its exercises, treat it as authoritative —
    // it may carry a local swap not yet synced into plan_json. Only FILL from
    // the snapshot when the local content was dropped (the restore-skip bug).
    // Keeps restore + the boot heal idempotent + swap-safe (review P1 2026-06-06).
    final localEx = existing['exercises'];
    if (localEx is List && localEx.isNotEmpty) {
      return _normalizeHybrid(Map<String, dynamic>.from(existing));
    }
    // Spec sec 5.7 L1: NEVER refill a rest row with workout content — every
    // hybrid in secs 1.3/1.4 of the spec comes from exactly this refill. A
    // local row of type 'rest', or with status 'rest', is kept as-is.
    // Kill switch `disable_rest_row_refill_guard` restores the pre-fix
    // unconditional-refill behaviour verbatim (CLAUDE.md sec 4.6).
    if (SyncFlags.restRowRefillGuardEnabled) {
      final isWorkoutType =
          !PlanEngineFlags.isRestDayConsideringLogged(existing['type']);
      if (!isWorkoutType || existing['status'] == 'rest') {
        return _normalizeHybrid(Map<String, dynamic>.from(existing));
      }
    }
    final merged = Map<String, dynamic>.from(planJson);
    final localStatus = existing['status'];
    if (localStatus != null) merged['status'] = localStatus;
    if (existing['completed_at'] != null) {
      merged['completed_at'] = existing['completed_at'];
    }
    return _normalizeHybrid(merged);
  }

  /// Spec sec 5.7 merge-output normalizer (deviation D5): a row that would
  /// render as `type: workout` + `status: rest` + no exercises is corrected
  /// to `type: rest`. Applied to EVERY [mergeScheduleEntry] return path
  /// (including the wholesale-take branches), so a hybrid can never re-enter
  /// Hive through any of them. Deliberately UNSWITCHED — CLAUDE.md sec 4.6 /
  /// spec sec 11 list "restore type derivation" among the pure bug fixes
  /// that get no kill switch; preserving the old output shape here would
  /// just preserve the bug the fix exists to close, even with L1 disabled.
  static Map<String, dynamic> _normalizeHybrid(Map<String, dynamic> row) {
    if (isRestHybrid(row)) return {...row, 'type': 'rest'};
    return row;
  }

  /// The ONE hybrid predicate (spec §1.3/§1.4, plan D5): `status: rest`, a
  /// workout type, and no exercises. Shared by [_normalizeHybrid] and the
  /// one-time `ScheduleHybridRepairMigrator` (Task 23) so the two can never
  /// disagree about what a hybrid is. A hybrid WITH exercises is not one of
  /// these (ambiguous; left alone by both).
  static bool isRestHybrid(Map<String, dynamic> row) {
    final isWorkoutType =
        !PlanEngineFlags.isRestDayConsideringLogged(row['type']);
    final ex = row['exercises'];
    final hasExercises = ex is List && ex.isNotEmpty;
    return row['status'] == 'rest' && isWorkoutType && !hasExercises;
  }

  static final RegExp _isoDateShape = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// Spec sec 5.7 L3: the IST Monday (`YYYY-MM-DD`) of the week containing
  /// [isoDate], via the day-swap engine's own [DaySwapRules.mondayOf] so the
  /// restore merge and the swap engine can never disagree on week bounds.
  /// Deliberately NOT `mondayOfIst` (takes a `DateTime`; double-shifts east
  /// of IST). Keys here come from cloud data, so a malformed legacy key is
  /// its own one-key "week" instead of throwing mid-restore
  /// (`DaySwapRules.mondayOf` parses with `int.parse`).
  static String _mondayOfIsoWeek(String isoDate) =>
      _isoDateShape.hasMatch(isoDate) ? DaySwapRules.mondayOf(isoDate) : isoDate;

  /// Spec sec 5.7 L3 (PURE, visible for testing): the `schedule_<date>` keys
  /// where the DOWNLOADED bundle's arrangement is the newer one, per Mon-Sun
  /// IST week. A missing `arranged_at_ms` counts as 0. Only dates STAMPED on
  /// either side are eligible, and only when they exist on the snapshot
  /// side (nothing to take otherwise). A TIE keeps local (strictly newer
  /// required).
  @visibleForTesting
  static Set<String> snapshotArrangementWinsKeys({
    required Map<String, dynamic> localRows,
    required Map<String, dynamic> snapshotRows,
  }) {
    int? stampOf(Object? row) {
      if (row is! Map) return null;
      final v = row['arranged_at_ms'];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return null;
    }

    final localMaxByWeek = <String, int>{};
    final snapshotMaxByWeek = <String, int>{};
    final stampedKeysByWeek = <String, Set<String>>{};

    void scan(Map<String, dynamic> rows, Map<String, int> maxByWeek) {
      for (final entry in rows.entries) {
        final key = entry.key;
        if (!key.startsWith(_schedulePrefix)) continue;
        final date = key.substring(_schedulePrefix.length);
        final week = _mondayOfIsoWeek(date);
        final stamp = stampOf(entry.value);
        final ms = stamp ?? 0;
        if (ms > (maxByWeek[week] ?? 0)) maxByWeek[week] = ms;
        if (stamp != null) {
          (stampedKeysByWeek[week] ??= <String>{}).add(key);
        }
      }
    }

    scan(localRows, localMaxByWeek);
    scan(snapshotRows, snapshotMaxByWeek);

    final winning = <String>{};
    for (final week in stampedKeysByWeek.keys) {
      final localMax = localMaxByWeek[week] ?? 0;
      final snapshotMax = snapshotMaxByWeek[week] ?? 0;
      if (snapshotMax > localMax) {
        for (final key in stampedKeysByWeek[week]!) {
          if (snapshotRows.containsKey(key)) winning.add(key);
        }
      }
    }
    return winning;
  }

  /// Spec sec 5.7 (L1 + L3 combined write path). Applies EVERY entry of
  /// [schedules] (a `plan_json.schedules`-shaped map, key `schedule_<date>`)
  /// against the CURRENT `workoutBox` rows and writes the merged result
  /// directly to Hive. SHARED by `_restoreWorkoutPlan` (sync_workout.dart)
  /// and [reconcile] (this file) so the two consumers of the SAME cloud
  /// snapshot can never apply different merge semantics — two copies of
  /// this loop is exactly how the a7d3f1 / d9b2c5 recurrence class starts
  /// (CLAUDE.md sec 4.1.5). Returns the processed-entry count (for
  /// `reconcile`'s `healed` telemetry) and whether L3 discarded at least
  /// one LOCAL arrangement — the caller logs ONE `swap_merge_conflict`
  /// event per call, never per row (spec sec 5.7).
  static Future<({int processedCount, bool discardedLocalArrangement})>
      mergeScheduleBundleIntoHive(Map<String, dynamic> schedules) async {
    final workoutBox = HiveService.instance.workoutBox;
    final localRows = <String, dynamic>{
      for (final k in workoutBox.keys)
        if (k is String && k.startsWith(_schedulePrefix)) k: workoutBox.get(k),
    };
    final snapshotRows = <String, dynamic>{
      for (final e in schedules.entries)
        if (e.key.toString().startsWith(_schedulePrefix))
          e.key.toString(): e.value,
    };
    final winningKeys = SyncFlags.swapArrangementMergeEnabled
        ? snapshotArrangementWinsKeys(
            localRows: localRows, snapshotRows: snapshotRows)
        : const <String>{};

    var processed = 0;
    var discardedLocalArrangement = false;
    for (final entry in snapshotRows.entries) {
      final key = entry.key;
      final incoming = entry.value;
      if (incoming is! Map) continue;
      final existingRaw = workoutBox.get(key);
      final existingMap =
          existingRaw is Map ? Map<String, dynamic>.from(existingRaw) : null;
      final forceSnapshot = winningKeys.contains(key);
      // A completed row is protected by mergeScheduleEntry's first guard, so
      // nothing of it is discarded: no conflict to report (round-1 review E F1).
      // An UNSTAMPED local row (no arranged_at_ms) in a winning week is also
      // not counted: it holds no local arrangement to lose — the snapshot's
      // arrangement came from another device (round-2 review E F1, by design).
      if (forceSnapshot &&
          existingMap != null &&
          existingMap['status'] != 'completed' &&
          existingMap['arranged_at_ms'] != null) {
        discardedLocalArrangement = true;
      }
      final merged = mergeScheduleEntry(
        existingMap,
        Map<String, dynamic>.from(incoming),
        forceSnapshotArrangement: forceSnapshot,
      );
      // Day-swapper + sync-load Task 22 (spec sec 5.7 L2): "when the merge
      // runs, write a row only if the merged result differs from the local
      // row". Skips a redundant Hive.put on every date the bundle re-sends
      // unchanged every restore/reconcile pass -- this is where most of the
      // "up to 112 writes/launch" figure comes from, since a whole plan
      // bundle's worth of dates is looped every pass regardless of whether
      // any single date actually changed. Compared via
      // SyncFingerprint.canonicalJson (sorted map keys at every depth, same
      // primitive Task 4's push-side skip index uses) rather than `==`, so a
      // jsonb round-trip's key reordering never forces a write. Kill switch
      // disable_plan_merge_skip_when_known reverts to an unconditional put
      // every pass (CLAUDE.md sec 4.6) -- the SAME flag also gates the
      // whole-bundle skip in _restoreWorkoutPlan (one flag, both L2
      // optimizations).
      final unchanged = existingMap != null &&
          SyncFlags.planMergeSkipWhenKnownEnabled &&
          SyncFingerprint.canonicalJson(merged) ==
              SyncFingerprint.canonicalJson(existingMap);
      if (!unchanged) {
        await workoutBox.put(key, merged);
      }
      processed++;
    }
    return (
      processedCount: processed,
      discardedLocalArrangement: discardedLocalArrangement,
    );
  }

  /// PURE (visible for testing): does any entry describe a PLANNED workout day
  /// that lost its exercises — the restore-skip symptom? A genuine rest day
  /// (`type != workout`) and a completed day are both fine.
  @visibleForTesting
  static bool needsHeal(Iterable<Map<String, dynamic>> entries) {
    for (final e in entries) {
      final type = e['type'];
      final isWorkout = !PlanEngineFlags.isRestDayConsideringLogged(type);
      if (!isWorkout) continue;
      if (e['status'] == 'completed') continue;
      final ex = e['exercises'];
      final hasExercises = ex is List && ex.isNotEmpty;
      if (!hasExercises) return true;
    }
    return false;
  }

  /// PURE (visible for testing): the two INDEPENDENT decisions a reconcile pass
  /// makes — FOB-7(b) / OI-60.
  ///
  /// Returns a RECORD, not a bool, and that is the point. The whole fix is the
  /// distinction between "fetch and heal the schedule rows" and "move the plan
  /// window", and a single bool cannot carry a distinction its caller then has
  /// to re-derive. (Sibling of the recurring guard-without-its-mirror class: a
  /// `bool` return that throws away the binding the fix exists to make.)
  ///
  ///  - [shouldFetch]  — EITHER symptom justifies pulling the cloud snapshot and
  ///                     merging `schedule_*` rows. Hold weeks included.
  ///  - [mayReanchor]  — ONLY the weeks-1-4 symptom may authorise the
  ///                     `plan_start_date` / `plan_end_date` writes. Widening
  ///                     this is REFUTED (P0-11 / d7f3a9): that scan IS the
  ///                     re-anchor trigger, so widening buys no healing and only
  ///                     makes the window move more often.
  /// The current hold weeks' schedule rows — the second symptom source
  /// FOB-7(b) feeds to [computeTriggers].
  ///
  /// Extracted and `@visibleForTesting` because it was INLINE in [reconcile]
  /// and therefore untestable without a live Supabase client — which is exactly
  /// how it shipped the `weekStart` bug below past two review rounds' test
  /// suites. A loop no test can reach is a loop no test protects.
  ///
  /// ⚠ ANCHORS ON THE NORMALIZED MONDAY, never on `weekStart` directly.
  /// [HoldWeekInfo.weekStart] is `byOrdinal[ordinal]!.first` — the first
  /// SURVIVING hold date (`workout_schedule_read_service.dart:870`) — so a hold
  /// week whose Monday row is missing yields a TUESDAY, and a 0..6 walk from
  /// there reads [Tue..Sun, next Mon]: one day short at the front, one day of
  /// the FOLLOWING week at the back. This pattern was already found, rejected
  /// BY NAME and scar-commented for the streak arm
  /// (`train_provider.dart:577-579`; `oi60-streak-identity.closure.yaml:51`),
  /// with a missing-Monday reproduction in
  /// `hold_week_streak_identity_behavioral_test.dart`. Round 2 caught this
  /// batch reintroducing it here — the same class, one file over.
  ///
  /// Returns `const []` when `enable_hold_weeks` is OFF, because
  /// [WorkoutScheduleReadService.activeHoldWeeks] does; that is what keeps the
  /// whole FOB-7(b) path byte-identical with the flag off.
  @visibleForTesting
  static List<Map<String, dynamic>> gatherHoldRows(
      WorkoutScheduleReadService scheduleService) {
    final out = <Map<String, dynamic>>[];
    for (final h in scheduleService.activeHoldWeeks()) {
      final monday = scheduleService.normalizeToMonday(h.weekStart);
      for (var d = 0; d < 7; d++) {
        final row =
            scheduleService.getScheduleForDate(monday.add(Duration(days: d)));
        if (row != null) out.add(row);
      }
    }
    return out;
  }

  @visibleForTesting
  static ({bool shouldFetch, bool mayReanchor}) computeTriggers({
    required Iterable<Map<String, dynamic>> windowRows,
    required Iterable<Map<String, dynamic>> holdRows,
  }) {
    final window = needsHeal(windowRows);
    return (shouldFetch: window || needsHeal(holdRows), mayReanchor: window);
  }

  /// Reconcile the current user's local schedule against the cloud `plan_json`
  /// snapshot. [scheduleService] is injected so this is callable from the boot
  /// path (via the Riverpod provider) and from tests, mirroring
  /// [PhaseProgressReconciler.reconcile].
  ///
  static Future<PlanReconcileOutcome> reconcile(
      WorkoutScheduleReadService scheduleService) async {
    try {
      final hive = HiveService.instance;
      if (hive.configBox.get(killSwitchKey) == true) {
        return PlanReconcileOutcome.skipped('kill_switch');
      }

      // Without a known plan window we can't classify the current weeks → skip
      // (a reconcilable user always has a plan_start).
      final planStart = scheduleService.getPlanStartDate();
      if (planStart == null) {
        return PlanReconcileOutcome.skipped('no_plan_start');
      }

      // Cheap LOCAL symptom check first — gather the current 4-week window's
      // schedule rows and bail (no network) when every planned workout day
      // already has its exercises.
      final local = <Map<String, dynamic>>[];
      for (var w = 1; w <= 4; w++) {
        local.addAll(scheduleService.getWeek(w));
      }

      // FOB-7(b) / OI-60 — THE TRIGGER IS SPLIT FROM THE WRITE.
      //
      // The 1..4 scan above is date-driven off plan_start, so a hold week (which
      // sits at plan_start+28 and beyond) is invisible to it. A holder whose
      // hold-week exercises were dropped by the restore-skip bug therefore never
      // healed — the exact failure this reconciler exists to cure, on the only
      // week a free user is training.
      //
      // ⚠ WIDENING THE 1..4 SCAN IS REFUTED and must not be re-proposed:
      // docs/audit/oi60-streak-identity.closure.yaml, P0-11 concern d7f3a9. That
      // scan is ALSO the re-anchor trigger, so widening it buys no healing and
      // only makes the plan_start/plan_end write below fire more often.
      //
      // So this is a SECOND, INDEPENDENT predicate over the SAME fetch. It can
      // authorise the schedule merge (which only ever touches `schedule_*` keys)
      // and it deliberately CANNOT authorise the re-anchor (which only touches
      // plan_start_date / plan_end_date). The two key sets are disjoint, so the
      // merge cannot move the plan window by any path.
      //
      // Gated seam on purpose: activeHoldWeeks() returns const [] when
      // `enable_hold_weeks` is OFF, so with the flag off this whole block is a
      // no-op and the function behaves byte-identically to before FOB-7(b).
      //
      // ⚠ ANCHOR ON THE NORMALIZED MONDAY, never on `weekStart` directly.
      // `HoldWeekInfo.weekStart` is `byOrdinal[ordinal]!.first` — the first
      // SURVIVING hold date (workout_schedule_read_service.dart:870), so a hold
      // week whose Monday row is missing yields a TUESDAY. Walking 0..6 from
      // there reads [Tue..Sun, next Mon]: one day short at the front and one day
      // of the following week at the back. This exact pattern was already found,
      // rejected by name and scar-commented for the streak arm
      // (`train_provider.dart:577-579`, `oi60-streak-identity.closure.yaml:51`),
      // and its missing-Monday reproduction lives in
      // `hold_week_streak_identity_behavioral_test.dart`. Round 2 caught this
      // batch reintroducing it here.
      final holdRows = gatherHoldRows(scheduleService);
      final triggers =
          computeTriggers(windowRows: local, holdRows: holdRows);

      // healthy → no-op, no fetch
      if (!triggers.shouldFetch) {
        return PlanReconcileOutcome.skipped('healthy');
      }

      // Symptom present → pull the authoritative plan_json snapshot from cloud.
      final userId = SupabaseService.instance.client.auth.currentUser?.id;
      if (userId == null) {
        return PlanReconcileOutcome.skipped('no_user');
      }

      final rows = await SupabaseService.instance.client
          .from('user_progress')
          .select('plan_json')
          .eq('user_id', userId)
          .limit(1);
      if (rows.isEmpty) {
        return PlanReconcileOutcome.skipped('no_cloud_row');
      }
      final planJson = rows.first['plan_json'];
      if (planJson is! Map) {
        return PlanReconcileOutcome.skipped('no_plan_json');
      }
      final bundle = Map<String, dynamic>.from(planJson);

      // Re-anchor plan_start / plan_end from the snapshot, MONOTONICALLY +
      // phase-gated (free-tier-hold durability #1, PlanWindowReanchor): same
      // phase keeps the LATER plan_end so a hold extension survives this heal;
      // a stale-plan_start install takes cloud verbatim (the original a7d3f1
      // inflated-week fix). Reached only when needsHeal fires — a healthy hold
      // is a no-op above.
      final pjStart = bundle['plan_start_date'];
      final pjEnd = bundle['plan_end_date'];
      final reanchor = PlanWindowReanchor.resolve(
        localStart: MigratedKey.read<String>(_planStartKey),
        localEnd: MigratedKey.read<String>(_planEndKey),
        cloudStart: pjStart is String ? pjStart : null,
        cloudEnd: pjEnd is String ? pjEnd : null,
      );
      final reStart = reanchor.planStart;
      final reEnd = reanchor.planEnd;
      // FOB-7(b): the re-anchor stays on its ORIGINAL trigger. A hold-only
      // symptom brings us here to heal `schedule_*` rows and must not move the
      // plan window — that is the whole point of splitting the two predicates.
      // This DECLINES TO WIDEN OI-127's exposure — it does not narrow it, and
      // round 2 caught the stronger claim as false. `shouldFetch` is a superset
      // of `mayReanchor`, so `shouldFetch && mayReanchor` reduces to exactly the
      // pre-batch `needsHeal(weeks 1-4)`. Adding the hold trigger gave these two
      // writes no new way to fire; OI-127 itself stays fully OPEN.
      if (triggers.mayReanchor) {
        if (reStart != null) await MigratedKey.write(_planStartKey, reStart);
        if (reEnd != null) await MigratedKey.write(_planEndKey, reEnd);
      }

      final schedules = bundle['schedules'];
      var healed = 0;
      if (schedules is Map) {
        // OI-252 (merged from main) — same ghost-day filter as
        // `_restoreWorkoutPlan`: this frozen `plan_json` snapshot can carry a
        // day scheduled against a template deleted since the snapshot was
        // taken. Healing it back in would resurrect exactly the reference the
        // delete removed. Filtered out BEFORE the L1/L3 bundle merge. The
        // deleted-template set is resolved once, lazily, and only for an entry
        // that carries a template_id — the common case (a rest/plan day with
        // no template) never pays a live query it has no use for.
        Set<String>? deletedTemplateIdsCache;
        Future<Set<String>> deletedTemplateIds() async =>
            deletedTemplateIdsCache ??=
                await SyncService.instance.deletedTemplateCloudIdsForUser(userId);
        final live = <String, dynamic>{};
        for (final entry in schedules.entries) {
          final incoming = entry.value;
          if (incoming is Map &&
              incoming['template_id'] != null &&
              isGhostScheduleEntry(Map<String, dynamic>.from(incoming),
                  await deletedTemplateIds())) {
            continue;
          }
          live[entry.key.toString()] = incoming;
        }
        final result = await mergeScheduleBundleIntoHive(live);
        healed = result.processedCount;
        if (result.discardedLocalArrangement) {
          unawaited(ErrorTelemetry.logEvent('swap_merge_conflict',
              message: 'source=reconcile'));
        }
      }

      unawaited(ErrorTelemetry.logEvent(
        'plan_integrity_reconciled',
        message: 'healed=$healed planStart=$pjStart',
      ));
      return PlanReconcileOutcome.healed(healed);
    } catch (e, st) {
      // Non-fatal — never block boot on a reconciliation hiccup.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'plan_integrity_reconciler'));
      return PlanReconcileOutcome.failed('$e');
    }
  }
}

/// What [PlanIntegrityReconciler.reconcile] actually did.
///
/// Added by OI-83 round-1 review P2. `reconcile` returned `void` and swallowed
/// every exception, and it has six early-exit paths (kill-switch, no
/// plan_start, healthy, no user, no cloud row, no plan_json). A caller could
/// therefore report "repaired" for a run that did nothing at all — which is
/// exactly what `reconcileAfterDeclinedAdvance` did, unconditionally, while its
/// own catch block was unreachable. Telemetry that reports 100% success at 0%
/// repair rate is worse than none.
class PlanReconcileOutcome {
  /// Rows written. 0 on every skip and on failure.
  final int healedCount;

  /// Why nothing was written — `null` when the run reached the write loop.
  final String? skipReason;

  /// Set only when the body threw; the exception, stringified.
  final String? failure;

  const PlanReconcileOutcome._(this.healedCount, this.skipReason, this.failure);

  const PlanReconcileOutcome.healed(int count) : this._(count, null, null);
  const PlanReconcileOutcome.skipped(String reason) : this._(0, reason, null);
  const PlanReconcileOutcome.failed(String error) : this._(0, null, error);

  bool get didWrite => healedCount > 0;
  bool get didFail => failure != null;

  /// Compact, PII-free telemetry payload.
  String describe() => didFail
      ? 'failed=$failure'
      : skipReason != null
          ? 'skipped=$skipReason'
          : 'healed=$healedCount';
}
