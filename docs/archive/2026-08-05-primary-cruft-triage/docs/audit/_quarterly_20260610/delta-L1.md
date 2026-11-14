# Quarterly audit — Lens L1 (writer/reader field drift), DELTA scope

Scope: `git diff --name-only 969c117..HEAD` ∪ `git show a767725` — 3 batches:
WI-1..4 (server-seam gate, migrations 088/089), apk34-obs (8 fixes), slow-boot +
additive-restore (ADR-0014). Method: for each Hive write touched, traced every
cloud reader; for each cloud write, every Hive reader; pinned SEMANTICS not
presence. Files read in full: sync_workout.dart, sync_nutrition.dart,
reports_screen.dart, profile_provider.dart, profile_image_url.dart,
workout_repository.dart (streak walk + getWeeklyWorkoutCounts + getScheduleForDate),
workout_write_service.dart (markCompleted), restore_orphan_completion_test.dart.

## Findings

### F1 — orphan-completion synthesis writes a `schedule_` row but no `wlog_` row — P2 — REAL (low impact)
- file: `lib/core/services/sync/sync_workout.dart:845-856` (`_restoreScheduleCompletions` synthesize branch, d9d201c)
- verbatim:
  `await _hive.workoutBox.put(key, { 'date': date, 'workout_name': ..., 'status': 'completed', 'type': 'logged', ... 'source': 'cloud_restore_completion' });`
- claim: The production writer `WorkoutWriteService.markCompleted` (workout_write_service.dart:413-431) writes BOTH a `schedule_<date>` row AND a `wlog_<date>` row. The restore synthesize branch (aligned by d9d201c to markCompleted's *schedule* branch only) writes only the `schedule_` row. The streak reader `_calculateStreak` (workout_repository.dart:261, reads `schedule_<date>` status=='completed') IS satisfied — obs 5.2 fix is correct. BUT the reports "This Week" tile + frequency chart read `getWeeklyWorkoutCounts()` (workout_repository.dart:755), which counts ONLY `type=='workout_log'` (`wlog_`) rows. An orphan completion's `wlog_` row is restored via the SEPARATE `workout_logs` → `_restoreWorkoutLogs` path (line 606, sets `type:'workout_log'`), so the count is normally covered — this is a gap ONLY if the cloud `workout_logs` row is missing while `workout_schedule_completions` has the row. Not a name/semantic drift; a completeness asymmetry between two restore tables. The diagnose already flags a `behavioral_test_required` follow-up.
- verify: `grep -n "type'\] != 'workout_log'\|'type': 'workout_log'\|'type': 'logged'" lib/features/train/repositories/workout_repository.dart lib/core/services/sync/sync_workout.dart`
- verdict: REAL (P2 — divergent-table completeness edge, not a field-name drift; streak path correct)

## Checked clean (no drift)

- **Additive-restore writers** (sync_workout `_restoreWorkoutLogs`:606, `_restoreExerciseLogs`:787, sync_nutrition `_restoreNutritionLogs`:443, `_restoreSavedMeals`:535): local-wins guard `if (box.get(key) != null) continue;` is additive only; written field shapes (`type`, `workout_name`, `sets`, `food_name`/`name`, `quantity_g`) match their existing readers — no field renamed by the additive change. `_restoreExerciseLogs` still reconstructs canonical `sets` + `set_number` (D2 names).
- **Reports c2e8b4** (reports_screen.dart:376-377, 399): "This Week" now reads `getWeeklyWorkoutCounts().first` (current-week, same source as the frequency bar) instead of lifetime `total_workouts_done`; streak label `${currentStreak}d` matches Home's day-walk semantic. Correct.
- **Profile image b1f3a7** (profile_image_url.dart + profile_provider.dart:162/240, sync_service.dart:828 / sync_profile.dart:106-107): version token travels INSIDE the stored `avatar_url`/`banner_url` string value; `forDisplay` passes verbatim, sync pushes verbatim. Writer/reader agree on the field; no per-build mutation. Correct.
- **Set-number widen (089) + clamp parity** (sync_workout.dart:330/347 wls reps≤10000, dur≤3600): clamp values match the migration CHECK bounds; out-of-range logged not silently dropped. No reader sees a lying type.
- **Streak walk vs orphan row**: synthesized `type:'logged'`/`status:'completed'` is read correctly by `_calculateStreak` (non-rest/off + completed ⇒ streak+1) and `completionRateOverWindow:347`. Correct.
- **`_restoreScheduleCompletions` B-pass P2 (d9d201c)**: now writes both `completed_at` (ISO, read by getScheduleForDate stale-guard) and `completed_at_ms` (epoch) — schema parity with markCompleted's synthesize branch. Correct.
