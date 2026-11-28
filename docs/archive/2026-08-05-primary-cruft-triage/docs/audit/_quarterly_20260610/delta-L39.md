# Delta audit — Lens L39 (Backup/restore round-trip completeness)

L39 IS defined in `docs/audit/LENS_REGISTRY.md:96` ("Backup/restore round-trip
completeness — every `syncX` has a paired `_restoreX` + round-trip contract
test"). Applied over the delta scope (`969c117..HEAD` ∪ `a767725`).

Focus: ADR-0014 additive local-wins restore + orphan-completion synthesis
(e9b4a2) + canonical Hive key/field round-trip.

## Findings

### F1 — INFO (not a defect) — orphan-completion synthesis round-trips correctly
- `lib/core/services/sync/sync_workout.dart:829-857` (`_restoreScheduleCompletions`)
  synthesizes `schedule_<date>` with `'status':'completed'`, `'type':'logged'`.
- Reader `_calculateStreak` reads `schedule_<date>` **directly from the box**
  (`workout_repository.dart:226-262`), checks `type`(rest/off skip) +
  `status=='completed'` — NOT through `getScheduleForDate`, so the stale-
  completion downgrade guard (`workout_schedule_read_service.dart:459-471`) does
  NOT strip the synthesized row. Streak walk counts it.
- Verify: `flutter test test/contracts/restore_orphan_completion_test.dart`
- **FALSE_ALARM** (verified clean; the read path the fix targets finds the row).

### F2 — LOW — additive skip-if-local-exists does NOT strand cloud gap rows
- Claim audited: does `if (box.get(key) != null) continue;` (sync_workout.dart:605,
  787; sync_nutrition.dart:443, 535; sync_workout `_restoreScheduleCompletions`
  else-branch only writes when ABSENT) ever skip a cloud row that SHOULD restore?
- For a returning user on a fresh reinstall the local box is EMPTY → every cloud
  row is absent → all gap rows restore. Skip only fires when a local row with the
  SAME canonical key already exists, which by ADR-0014 is intentionally
  local-wins. No cloud row is stranded that the canonical key doesn't already
  cover locally. `since='2020-01-01T00:00:00Z'` (sync_service.dart:941,1057) =
  full history, so no window-based stranding either.
- Verify: `flutter test test/contracts/restore_local_wins_additive_test.dart`
- **FALSE_ALARM** (verified clean — additive skip is keyed, full-history window).

### F3 — INFO — canonical Hive keys + field names preserved on restore
- `_restoreExerciseLogs` writes canonical `set_number` (not `sets_completed`,
  sync_workout.dart:726-728) and canonical `sets` list (not `sets_detail`,
  :763-767); key via `WorkoutWriteService.exlogKey` (:694).
- `_restoreWorkoutLogs` reads `workout_name` (not dead `exercise_name`, :614);
  key `wlog_<dateStr>` (:600).
- `_restoreNutritionLogs` rebuilds key via `SyncService._nlogKeyForRestore`
  (:433); `_restoreSavedMeals` via `NutritionWriteService.savedMealKey` (:530).
- Verify: `flutter test test/contracts/restore_completeness_test.dart`
- **FALSE_ALARM** (verified clean — all delta restore writers use canonical
  key/field names).

### F4 — LOW (observation, pre-existing, NOT introduced by delta) — NULL `completed_at` cloud completion is invisible to restore
- `_restoreScheduleCompletions` filters `.gte('completed_at', since)`
  (sync_workout.dart:811). Postgres `gte` excludes NULL, so a
  `workout_schedule_completions` row with NULL `completed_at` is never fetched →
  never synthesized → not counted in the streak. The push side defaults
  `completed_at` to NOW (:517), so client-written rows always have it; risk is
  only for rows seeded by other writers (sim/legacy) with NULL. Out of delta
  blast (filter line unchanged by this batch); flag for awareness only.
- Verify: `git log -1 --format=%h -S "gte('completed_at'" -- lib/core/services/sync/sync_workout.dart` (predates 969c117)
- **REAL** but PRE-EXISTING / out-of-delta-scope; severity LOW. NO fix per brief.

## Summary
0 delta-introduced defects. Orphan-completion synthesis, additive local-wins
restore, and canonical key/field round-trip all verify clean against
`test/contracts/restore_*`. One pre-existing LOW observation (F4, NULL
completed_at filter) noted for awareness only — outside delta scope.
