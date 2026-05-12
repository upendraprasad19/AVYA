---
bug_id: 6e1b45
date: 2026-05-12
batch: APK Test #15.3
status: in_progress
symptom: |
  On Train screen day card (Monday 2026-05-11), Handstand Hold renders
  as "3 sets · 0s" and Jump Rope as "2 sets · 0s" instead of showing
  per-set duration chips for the durations the user logged
  (10s × 3 / 30s × 2). Cloud `workout_log_sets.duration_secs` HAS the
  correct values; cloud `workout_log_exercises` summary shows
  `reps=30/20`, `weight_kg=0`, and lacks `duration_seconds` (writer
  never persists top-level aggregate duration on exlogs). Local Hive
  per-set entries lost their duration on re-merge.
concept: exercise_set_field_name_contract
sot_registry_entry: exercise_log_per_set
writers:
  - { file: lib/core/services/write_result.dart, method_or_widget: "ExerciseSet.toMap", line: 95 }
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: "logExercise (per-set merge)", line: 96 }
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: "editLog (per-set recompute)", line: 643 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: "_restoreExerciseLogs (legacy field name)", line: 2842 }
readers:
  - { file: lib/shared/widgets/wardroom/ward_set_chips.dart, method_or_widget: "WardSetChips._perSetLabel", line: 70 }
  - { file: lib/features/train/screens/train_screen.dart, method_or_widget: "_showDayDetail per-set parse", line: 1265 }
  - { file: lib/features/train/widgets/workout_receipt_card.dart, method_or_widget: "fromExerciseLogs per-set parse", line: 367 }
  - { file: lib/core/services/write_result.dart, method_or_widget: "ExerciseSet.fromMap", line: 102 }
hive_key_prefix: exlog_
hive_key_formula: "'exlog_${istDateStr(date)}_${lower(exerciseName).hashCode.toRadixString(16)}'"
sync_methods:
  - SyncService._syncExerciseLogs
restore_methods:
  - SyncService._restoreExerciseLogs
cloud_table: workout_log_sets
cloud_columns:
  - id
  - user_id
  - workout_log_id
  - exercise_id
  - set_number
  - weight_kg
  - reps
  - duration_secs
  - distance_km
  - completed_at
contract_test_path: test/contracts/timed_exercise_render_contract_test.dart
ist_handling:
  - { file: lib/core/utils/ist_date.dart, line: 1, fn: istDateStr }
provider_invalidations:
  - todayWorkoutProvider
  - calendarWeekProvider
  - currentPlanProvider
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: |
  workoutBox is user-scoped via HiveUserSession (lib/core/services/hive_user_session.dart);
  every read/write goes through the active user's namespaced box.
  ExerciseSet.fromMap is a pure stateless factory — no user_id is read,
  no cross-account state can leak through it. The fix changes only
  field-name acceptance in the factory; no telemetry payload changes.
forbidden_patterns_checked:
  - { pattern: "durationSec: (m['duration_sec'] as num?)?.toInt(),\\n        loggedAt", absent: true }
  - { pattern: "durationSec: \\(m\\['duration_sec'\\] as num\\?\\)\\?\\.toInt\\(\\)$", absent: true }
proposed_fix: |
  Extend `ExerciseSet.fromMap` (lib/core/services/write_result.dart:102)
  to accept BOTH the canonical field name `duration_sec` (written by
  `ExerciseSet.toMap`) and the legacy field name `duration_seconds`
  (written by `SyncService._restoreExerciseLogs` and pre-Test-#12
  edit-sheet payloads):

  ```dart
  durationSec: (m['duration_sec'] as num?)?.toInt() ??
      (m['duration_seconds'] as num?)?.toInt(),
  ```

  This is the universal repair point. Every downstream re-parse of an
  existing per-set entry (60s-dedup merge in `logExercise`, sets[]
  recompute in `editLog`) now preserves restored durations regardless
  of which field name the upstream writer used.

  No changes to the readers (WardSetChips / train_screen /
  workout_receipt_card) — they already accept both field names
  directly off the raw Hive map. The bug was that the WRITER's re-merge
  path (which lives between restore and render) silently zeroed the
  field via fromMap.
regression_test_planned:
  - test/contracts/timed_exercise_render_contract_test.dart
---

# Bug 4c — timed exercises render "N sets · 0s" after restore + re-merge

## Symptom

User completed today's workout (2026-05-11 IST morning) which included
Handstand Hold (timed, 10s × 3 sets) and Jump Rope (timed, 30s × 2 sets).
Cloud `workout_log_sets` HAS the correct `duration_secs` values. On the
Train screen day-detail card, both exercises render as a single chip:

- "3 sets · 0s" for Handstand Hold
- "2 sets · 0s" for Jump Rope

This format is the WardSetChips `fallbackLabel` path that fires when
`perSetBreakdown.isEmpty` (or every entry has `durationSeconds == null`
for a timed log). The user-entered durations are nowhere to be found.

## Root cause

`ExerciseSet.fromMap` at `lib/core/services/write_result.dart:102`:

```dart
factory ExerciseSet.fromMap(Map<dynamic, dynamic> m) => ExerciseSet(
      weightKg: (m['weight_kg'] as num?)?.toDouble() ?? 0.0,
      reps: (m['reps'] as num?)?.toInt() ?? 0,
      durationSec: (m['duration_sec'] as num?)?.toInt(),  // ← only canonical
      loggedAtMs: (m['logged_at_ms'] as num?)?.toInt(),
    );
```

This factory reads ONLY the canonical field name `duration_sec` (the
name `ExerciseSet.toMap` writes). But three other writers persist the
legacy field name `duration_seconds` on per-set maps:

1. `SyncService._restoreExerciseLogs:2842` — when reconstructing
   `sets[]` from cloud `workout_log_sets`, the projection emits per-set
   entries with `'duration_seconds': (s['duration_secs'] as num).toInt()`.
   Restored data therefore lives in Hive with field name
   `duration_seconds`.
2. `EditWorkoutLogSheet._save` legacy aggregate path
   (`edit_workout_log_sheet.dart:119`, 209) writes
   `setMap['duration_seconds']` for `timed` per-set rows.
3. `EditWorkoutLogSheet` per-set update at line 119 writes
   `duration_seconds` too.

When `WorkoutWriteService.logExercise` is called again for the same
date+exercise (AI tool-dispatcher logging an additional set, 60s
dedup re-merge, etc.), it parses the existing per-set list at
`workout_write_service.dart:96-99` via `ExerciseSet.fromMap`. Because
`fromMap` ignores `duration_seconds`, every restored entry comes back
with `durationSec=null`. The merged list (containing these nulls)
flows through `_stripPhantomFields` and persists via
`cleanedSets.map((s) => s.toMap()).toList()` — the durations are gone.

A symmetric drop happens in `editLog` (line 643-647) when an edit
forces a sets[] recompute.

After the merge, readers (WardSetChips, train_screen day card,
workout_receipt_card) see per-set entries with `duration_sec=null` and
no `duration_seconds` either. For `loggingType='timed'`, the per-set
chip text becomes `'0 secs'` for each chip — and the train_screen
fallback (which fires when `rawSets` is functionally empty) shows
"N sets · 0s".

This explains why the founder's cloud `workout_log_sets.duration_secs`
is correct (the cloud sync ran at write time, before the silent merge
drop) but the Hive-local render is broken (the merge drop happened
after restore + before render).

## Fix

Extend `ExerciseSet.fromMap` to accept BOTH field names. The reader-side
readers (chip primitive, train_screen, receipt) already had the same
fallback, so this aligns the fromMap factory with the rest of the
readers. The change is one line:

```dart
durationSec: (m['duration_sec'] as num?)?.toInt() ??
    (m['duration_seconds'] as num?)?.toInt(),
```

No changes needed in:
- `WardSetChips` — already correct, branches on logging_type and reads
  durationSeconds (Dart field) which is populated by upstream callers.
- `workout_receipt_card.dart:367-369` — already handles both field
  names directly on the raw map.
- `train_screen.dart:1273-1274` — already handles both field names
  directly on the raw map.
- `sync_service.dart` restore projection — keeps writing `duration_seconds`
  (legacy) which is fine; fromMap now picks it up.

The fix is at the canonical fromMap factory because that's where the
restore-shape data first re-enters the writer's domain. Patching only a
reader would leave the writer's re-merge path still silently zeroing
the field on every subsequent mutation.

## Why this matters

Without the fix, any user who:
1. Logs a timed exercise via active workout (per-set duration_sec
   persists correctly the first time)
2. Reinstalls the app or clears Hive (restore writes per-set with the
   legacy field name `duration_seconds`)
3. Subsequently logs another set via the AI coach or completes a new
   workout that triggers logExercise on the same exercise+date (rare
   but real — multi-session days, AI "I did one more set" intents)

...loses their original duration data forever. The new merge writes
sets[] with `duration_sec=null` everywhere, and the cloud projection
on the next sync mirrors the local loss → cloud `workout_log_sets` also
loses `duration_secs` on the next push.

This is the canonical class CLAUDE.md §15 warns about: "field renames
must update consumers in the same PR." Pre-Test-#6 the per-set field
name was `duration_seconds`; Test #6's `WorkoutWriteService` introduced
the new canonical `duration_sec` but `ExerciseSet.fromMap` (the gate
between restore-shape and writer-shape) never got the symmetric
fallback. The reader-side surfaces all got fallback patches over the
last 12+ test batches, but the fromMap gap stayed open.

## Verification

Contract test at `test/contracts/timed_exercise_render_contract_test.dart`
covers four layers:

1. **Writer persists duration_sec for timed per-set entries** — pins
   that active-workout writes survive the strip pass.
2. **Restore reconstructs per-set duration into readable shape** — pins
   that the receipt reader handles the `duration_seconds` legacy name.
3. **Writer→receipt end-to-end** — pins that perSetBreakdown is
   non-empty so WardSetChips doesn't fall back.
4. **ExerciseSet.fromMap accepts BOTH field names** — the new test that
   FAILS pre-fix and PASSES post-fix. Includes a direct unit-level
   assertion plus an integration assertion that pre-seeds Hive with
   restore-shape and exercises the logExercise re-merge path.

Pre-fix: Layer 4 fails with `Expected: <30>, Actual: <null>` on the
re-merged set.
Post-fix: all five tests pass.

## Out of scope

- **Cloud `workout_log_exercises.duration_seconds` aggregate column** —
  the writer at `workout_write_service.dart:166` doesn't write a
  top-level aggregate `duration_seconds` on exlog rows, so the cloud
  summary column stays null. The receipt + train screen both sum
  per-set durations as a fallback (workout_receipt_card.dart:386,
  train_screen.dart:1289 fallback path). Filing as a separate
  schema-completeness issue is out of scope for this bug.

- **EditWorkoutLogSheet legacy aggregate fallback** — when restored
  logs have `sets[]` (canonical key) but no `sets_detail`, the edit
  sheet's `_ExerciseEditRow.fromLog` at
  `edit_workout_log_sheet.dart:865` falls through to the legacy
  aggregate view because it reads ONLY `log['sets_detail']`. The
  legacy view then reads `log['duration_seconds']` (top-level
  aggregate, which writer doesn't persist) → user sees an empty
  `durationCtrl`. This is a separate readers-side gap; filing as a
  follow-up.

## Related

- CLAUDE.md §15 "Hive field-name contract" — the discipline this bug
  enforces.
- `docs/diagnoses/2026-05-12-edit-log-id-injection-f4c9e1.md` (Bug F /
  9499452) — sibling field-name contract drift on `id` injection.
- APK Test #6 — introduced the `duration_sec` canonical field name
  without sweeping all parsers.
