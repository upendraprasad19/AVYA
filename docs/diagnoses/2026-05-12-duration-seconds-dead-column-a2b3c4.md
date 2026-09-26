---
bug_id: a2b3c4
date: 2026-05-12
batch: APK Test #15.3
status: in_progress
symptom: |
  Cloud column `workout_log_exercises.duration_seconds` is always NULL for
  rows written by the modern `WorkoutWriteService`. The
  `SyncService._syncExerciseLogs` projection writes
  `'duration_seconds': log['duration_seconds']` reading a top-level field
  that the new writer never populates — per-set durations live inside the
  `sets[]` list as `duration_sec` (canonical) or `duration_seconds`
  (legacy shape after restore). Consumers (receipt card, train_screen
  expanded view, weekly-report Edge Function) all work around by summing
  per-set rows from the child table `workout_log_sets`. The aggregate
  column is dead schema data — future analytics queries / Edge Functions
  that JOIN on `workout_log_exercises` directly see 0/null and silently
  under-report total seconds for timed/cardio exercises.
concept: workout_receipt_rendering
sot_registry_entry: workout_receipt_rendering
writers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: _syncExerciseLogs projection, line: 1436 }
readers:
  - { file: lib/features/train/widgets/workout_receipt_card.dart, method_or_widget: WorkoutReceiptData.fromExerciseLogs (per-set sum workaround), line: 386 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: _resolvePerSetList, line: 1592 }
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: logExercise (writer of exlog_ shape), line: 166 }
hive_key_prefix: exlog_
hive_key_formula: "'exlog_${istDateStr(date)}_${exerciseName.hashCode.toUnsigned(32).toRadixString(16)}'"
sync_methods:
  - SyncService._syncExerciseLogs
restore_methods:
  - SyncService._restoreExerciseLogs
cloud_table: workout_log_exercises
cloud_columns:
  - id
  - workout_log_id
  - user_id
  - exercise_id
  - exercise_name
  - logging_type
  - set_number
  - reps
  - weight_kg
  - duration_seconds
  - distance_km
  - is_pr
  - has_warmup_sets
  - completed_at
contract_test_path: test/contracts/duration_seconds_aggregate_populated_test.dart
ist_handling:
  - { file: lib/core/utils/ist_date.dart, line: 1, fn: istDateStr }
provider_invalidations:
  - currentPlanProvider
  - workoutStatsProvider
  - calendarWeekProvider
  - streakProvider
  - todayWorkoutProvider
  - allExercisePRsProvider
telemetry_op_types:
  success: []
  failure:
    - upsert_exercise_log
cross_account_guard: |
  HiveUserSession-scoped writes: workoutBox is opened per-user via the
  user-scoped session (see lib/core/services/hive_user_session.dart).
  _syncExerciseLogs iterates the current session's workoutBox only —
  scoped to userId derived from the live Supabase JWT. No cross-account
  read or write path. The projection touches only the row's own
  per-set list (resolvedSets, local to the iteration) — no shared state
  between iterations.
forbidden_patterns_checked:
  - { pattern: "'duration_seconds': log['duration_seconds']", absent: true }
  - { pattern: "hardcoded duration_seconds: 0 unconditionally", absent: true }
proposed_fix: |
  In `_syncExerciseLogs` projection (sync_service.dart around line 1436),
  replace the dead top-level read with a per-set aggregate computed from
  `resolvedSets` (already built earlier in the method by
  `_resolvePerSetList`).

  Gate the aggregate on `logging_type in {timed, cardio}` so that
  non-timed types (weight_reps, bodyweight_reps, weighted_bodyweight,
  distance) land as 0 instead of mixing nulls. The column is
  `integer NULL` so either 0 or null is valid — 0 keeps downstream
  analytics queries (`SUM(duration_seconds) WHERE ...`) deterministic.

  Read both per-set field names: `duration_sec` (canonical, written by
  WorkoutWriteService) and `duration_seconds` (legacy after restore from
  pre-Test-#6 cloud rows). Mirrors the dual-name fallback in
  `workout_receipt_card.dart:367-368` and the Bug 4c (6e1b45) /
  Bug 6 (e1f8a2) precedents.

  No new fields, no schema change, no migration. Other projection map
  entries (id, workout_log_id, set_number, reps, weight_kg, distance_km,
  is_pr, has_warmup_sets, completed_at) preserved verbatim.
regression_test_planned:
  - test/contracts/duration_seconds_aggregate_populated_test.dart
---

# Bug 7 (a2b3c4) — duration_seconds dead column on workout_log_exercises

## Symptom

After the WorkoutWriteService rewrite in APK Test #6, the cloud column
`workout_log_exercises.duration_seconds` has been NULL for every new row.
The column is `integer NULL` so the write succeeds silently — no Postgres
constraint fires, no telemetry trips, no UI breaks.

Consumers all work around by summing the per-set `duration_secs` field
from the child table `workout_log_sets`:

- `WorkoutReceiptData.fromExerciseLogs` (`workout_receipt_card.dart:386`):
  `final effectiveDuration = duration > 0 ? duration : perSetDurationSum;`
  The top-level `duration > 0` branch is dead — duration is always 0
  for WriteService rows.
- Server-side analytics / Edge Functions joining on
  `workout_log_exercises` directly (none yet, but the column exists in
  the schema for exactly this reason) see 0/null and silently
  under-report total seconds.

## Root cause

`SyncService._syncExerciseLogs` projection at line 1446 (pre-fix):

```dart
await _supabase.client.from('workout_log_exercises').upsert({
  // ...
  'duration_seconds': log['duration_seconds'],   // ← always null
  // ...
});
```

The Hive `exlog_*` shape written by `WorkoutWriteService.logExercise`
(workout_write_service.dart:166) does NOT include a top-level
`duration_seconds` field. The writer's shape:

```dart
final entry = <String, dynamic>{
  'exercise_name': exerciseName,
  'date': dateStr,
  'workout_log_id': wid,
  'sets': cleanedSets.map((s) => s.toMap()).toList(),  // ← duration here
  'set_number': cleanedSets.length,
  'reps_completed': totalReps,
  'weight_kg': maxWeight,
  'volume_kg': volume,
  'logging_type': resolvedType,
  // ...
};
```

Per-set durations live INSIDE `sets[]` entries as `duration_sec` (the
ExerciseSet.toMap key) or `duration_seconds` (legacy shape after
restore from pre-Test-#6 cloud rows — surfaced by Bug 4c / Bug 6
dual-name precedent).

## Fix

In `_syncExerciseLogs` (sync_service.dart), insert an aggregate
computation immediately before the upsert call and use the result in
the projection map:

```dart
// Bug a2b3c4 — populate aggregate duration for timed/cardio exercises.
final loggingType = log['logging_type'] as String?;
final isTimedOrCardio =
    loggingType == 'timed' || loggingType == 'cardio';
int aggregateDurationSecs = 0;
if (isTimedOrCardio && resolvedSets.isNotEmpty) {
  for (final s in resolvedSets) {
    final raw = s['duration_sec'] ?? s['duration_seconds'];
    aggregateDurationSecs += (raw as num?)?.toInt() ?? 0;
  }
}
await _supabase.client.from('workout_log_exercises').upsert({
  // ...
  'duration_seconds': aggregateDurationSecs,
  // ...
});
```

`resolvedSets` is already computed earlier in the method by
`_resolvePerSetList` — reuse it. Non-timed/cardio logging types (weight_reps,
bodyweight_reps, weighted_bodyweight, distance) write 0 deterministically;
0 vs null is a cosmetic choice for an `integer NULL` column but 0 keeps
downstream `SUM(...)` queries deterministic.

For `cardio` exercises specifically: per-set durations are stored in
SECONDS (not minutes) — `active_workout_screen._captureSetValues:1276`
passes `int.tryParse(_durationControllers[setIdx].text)` directly into
`durationSeconds`. The UI labels the input "DURATION (s)" / shows a
minutes-and-seconds breakdown but the underlying scalar is always
seconds. No unit conversion needed.

## Why this matters

Today: no user-facing impact. Receipt + train_screen + weekly-report all
work around via the child table.

Tomorrow: any new analytics query or Edge Function (e.g. a "total time
trained this week" stat, a cardio-volume coach trigger, a leaderboard
on duration totals) that joins on `workout_log_exercises` directly
sees 0/null and silently under-reports. The column was added to the
schema specifically to avoid forcing every such consumer to also JOIN
`workout_log_sets`. Populating it now closes the schema-data gap before
the next downstream consumer ships against the dead column.

## Founder direction (locked 2026-05-12)

Populate the column, do not drop it. Future analytics queries / Edge
Functions joining `workout_log_exercises` will see the correct
aggregate for timed/cardio exercises instead of dead nulls.

## Related

- Bug 4c (6e1b45): per-set field-name dual support (`duration_sec` +
  `duration_seconds`). Same fallback pattern.
- Bug 6 (e1f8a2): writer-vs-reader field-name drift; sibling
  precedent.
- CLAUDE.md §11 "Exercise Log Cloud Contract": defines the per-exercise
  summary semantics — `set_number` = total, `reps` = cumulative,
  `weight_kg` = best. This fix adds `duration_seconds` = aggregate sum
  for timed/cardio, completing that family.
- `sot_registry.yaml#workout_receipt_rendering`: cloud_columns list
  did not include `duration_seconds` before — kept in sync with this
  fix is a follow-up but not gating (the column already existed).
