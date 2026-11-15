---
bug_id: 0ebfcb
date: 2026-11-10
batch: coach-workout-parity
status: fixed
blast_radius: account
symptom: >-
  OI-379: a workout completed from the coach chat (the chat workout card, typed sets that log every planned exercise,
  or the Complete workout tap on the "X of Y" tile) marked the day done but never raised total_workouts_done, never
  ran the daily or weekly streak update, never wrote the per-week streak row, never checked badges and never ran the
  rank promotion check. Only Active Workout did. Separately, a second Active Workout session on the same day added a
  second workout to the lifetime count.
concept: workout_completion_bookkeeping
sot_registry_entry: workout_completion_bookkeeping
writers:
  - file: lib/features/train/services/workout_completion_bookkeeping.dart
    method: WorkoutCompletionBookkeeping.afterCompletion (steps 0-6; the ONE writer of the after-completion fields)
    line: 104
  - file: lib/core/services/workout_write_service.dart
    method: markCompleted decides newlyCompleted under the per-date lock before any write
    line: 621
readers:
  - file: lib/core/services/workout_read_service.dart
    method_or_widget: completedWorkoutDayCount (distinct completed days; the heal floor and the badge count)
    line: 61
  - file: lib/core/services/badge_service.dart
    method_or_widget: checkAll totalWorkouts
    line: 93
  - file: lib/core/services/rank_service.dart
    method_or_widget: _readEvaluationState total_workouts_done
    line: 412
  - file: lib/features/profile/providers/profile_provider.dart
    method_or_widget: UserStatsNotifier totalWorkouts (Profile)
    line: 313
  - file: lib/features/train/providers/train_provider.dart
    method_or_widget: graduationStatsProvider totalWorkouts
    line: 2549
hive_key_prefix: userBox
hive_key_formula: "userBox['progress'] (total_workouts_done, current_streak_days, current_streak_weeks, last_counted_week_key, last_workout_date); healthBox['streaks'] row streak_<week start>; configBox['unlockedBadges']"
sync_methods:
  - UserRepository.updateProgress -> SyncService.syncProgressNow
restore_methods:
  - UserRepository.mergeCloudProgress (max-wins on total_workouts_done and current_streak_weeks)
cloud_table: user_progress
cloud_columns: [total_workouts_done, current_streak_days, current_streak_weeks, last_counted_week_key, last_workout_date]
contract_test_path: test/contracts/workout_completion_bookkeeping_behavioral_test.dart
ist_handling:
  - afterCompletion works on istDateStr(workoutDate) and a UTC-midnight DateTime of that IST day
provider_invalidations: []
telemetry_op_types:
  success: []
  failure:
    - workout_completion_bookkeeping
    - completion_bookkeeping_owner_changed
    - completion_bookkeeping_no_progress
    - completion_bookkeeping_restore_unsettled
    - active_workout_mark_completed_failed
cross_account_guard: true
forbidden_patterns_checked: []
proposed_fix: >-
  Coach workout parity slice 1a (plan docs/plans/coach-workout-parity-1a.md rev 4, three review rounds): markCompleted
  reports newlyCompleted (no completed status and no wlog_ before this call, decided under its per-date lock);
  ONE shared step WorkoutCompletionBookkeeping.afterCompletion, called by all four doors only after a successful
  mark, with the Hive owner captured as each door's first statement: count first (+1 on a first completion, healed
  up to the distinct completed days on record, never down), then the daily reckon and the weekly streak (only once
  this user's restore has settled), one progress write (last_workout_date later-wins), the streak row (settled only),
  badges and the rank check, each step in its own try/catch; the owner is re-checked after every await, and the
  day's completion prompt is resolved there for every door (B-pass 2026-11-10). BadgeService counts distinct completed days.
regression_test_planned:
  - test/contracts/workout_completion_bookkeeping_behavioral_test.dart
  - test/workout_write_service/mark_completed_test.dart
  - test/contracts/coach_completion_counts_behavioral_test.dart
related_bugs:
  - 280c4d  # Unit 1: the all-logged backstop + completion tap (the coach doors this fix wires)
  - 3a7b9f  # monotonic recompute demotion (the only-increment rule the count follows)
  - d1f6b3  # progress restore max-wins (why an over-count is permanent)
  - b7d3e5  # weekly marker = the calendar week last counted
  - b4e7a1  # restore-settled marker (the gate on the streak steps)
recurrence: |
  Writer drift by omission, not a value drift: ADR-0012 routed coach completion through markCompleted on the
  assumption that markCompleted "feeds streak / rank"; the bookkeeping actually lived only in Active Workout's
  completeWorkout, so every door added later skipped it. Same shape as the monotonic-field class (3a7b9f): the fix
  puts the bookkeeping in one shared step and keeps the count only-increment (+1 per first completion, healed upward).
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "One shared step called by all four doors (train_provider.dart:2276, conversational_log_handler.dart:429, tool_dispatcher.dart:479, ai_coach_provider.dart:423); T1/T2/T3 behavioural tests and the mutations below." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "T1 drives afterCompletion on real Hive: userBox progress, healthBox streaks, configBox unlockedBadges; T3 runs every door end to end and reads userBox progress." }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "No schema change: every field written is an existing user_progress column (backups/live_schema_columns.json: total_workouts_done, current_streak_days, current_streak_weeks, last_counted_week_key, last_workout_date)." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "Pre-launch, testers only (CLAUDE.md §1). Tester counts heal upward on their next completion through the distinct-day floor; no data migration." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function change in 1a. The rank cron counting distinct dates is Landing 2 (minted OI)." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron job touched; weekly-recalc keeps Math.max on the same columns." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy touched; the push goes through the existing syncProgressNow path." }
  - { tier: 9, name: storage_buckets_and_objects, status: not_applicable, evidence: "No storage." }
  - { tier: 10, name: secrets_and_api_keys, status: not_applicable, evidence: "No secret." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service." }
  - { tier: 12, name: client_to_server_contract, status: verified, evidence: "updateProgress fires syncProgressNow (user_repository.dart:1018, pinned by test/sync/sync_gap_test.dart); the push RPC takes GREATEST and restore merges max-wins, so the client count reaches user_progress unchanged." }
impact_analysis: >-
  Every coach completion now counts once per day and updates the streaks, badges and rank check exactly as Active
  Workout does. A second Active Workout session on a day already completed no longer adds a workout. A tester whose
  count is below their completed days heals upward on the next completion. While the restore has not settled the
  streak steps wait (the next completion after it settles does them); the count, last_workout_date, badges and the
  rank check still run, as Active Workout always ran them.
---

# Coach completions skip the after-completion bookkeeping (0ebfcb)

## Root cause
`total_workouts_done`, the daily and weekly streak, the per-week streak row, badges and the rank check were written
only inside Active Workout's `_persistCompletion`. The three coach doors called `WorkoutWriteService.markCompleted`
alone. ADR-0012 assumed `markCompleted` feeds streak and rank; it never did.

## Fix
- `markCompleted` returns `WriteResult.newlyCompleted`: true only when the day had no `completed` status and no
  `wlog_<date>` before this call, decided under the per-date lock, so two doors on one day see exactly one true.
- `WorkoutCompletionBookkeeping.afterCompletion` is the one shared step (plan D2): owner and null-progress guards,
  the count first (`max(stored + (newly ? 1 : 0), completedWorkoutDayCount())`, read as `num`), the restore-settled
  gate on the streak steps only (the same expression as the reckon: the marker, or the restore tick when `disable_streak_reckon_user_gate` is
  on, so the kill switch moves both together), reckon, weekly (hold ordinal `activeHoldOrdinalFor(nowWall())`), the owner re-check, one progress write
  (`last_workout_date` through `laterIsoDate`, the one date rule the restore merge also uses, so a backdated coach
  log never pulls it back and a stored date after IST today + 1 is repaired), the streak row, badges and the rank
  check. Each step has its own try/catch.
- Each door captures the owner as its first statement and calls the step only when the mark succeeded.
- `BadgeService.checkAll` counts distinct completed days.
- Test seam: `ActiveWorkoutNotifier.debugBeforeMarkGate` (awaited before the mark; null in production).

## Mutation evidence (rule 21)
Run by a script that applied each mutation by exact text (count checked = 1), ran the named test files under
`TZ=Asia/Kolkata`, restored the file and compared it with `cmp`.

| mutation | applied | red |
|---|---|---|
| M1 the `newlyCompleted` gate dropped (always +1) | 1 | T1 3 (heal-off +1/+0, never-lowers, weekly second door); T3 2 (second Active Workout session, chat card then Active Workout) |
| M2 the heal's `max` removed | 1 | T1 2 (heal raises to completed days, distinct dates) |
| M3a the call removed: chat card | 1 | T3 7 (every chat-card case that counts) |
| M3b the call removed: typed backstop | 1 | T3 2 (typed auto, auto then tap) |
| M3c the call removed: prompt tap | 1 | T3 1 (prompt tap) |
| M3d the call removed: Active Workout | 1 | T3 7 (every Active Workout case that counts) |
| M4 `newlyCompleted` false for `paused` | 1 | T2 1 (the paused row); end to end the heal masks it, as the plan predicted |
| M5 rows counted instead of distinct dates | 1 | T1 1 (distinct dates) |
| M6a owner read at the step, chat card | 1 | T3 2 (account change at the submit gate and at the mark gate) |
| M6b owner read at the step, Active Workout | 1 | T3 1 (account change before the mark) |
| M7 the restore-settled gate dropped | 1 | T1 2 (restore not settled; the kill switch with no tick) |
| M13 step 1b reads the marker alone, ignoring the reckon's kill switch | 1 | T1 2 (switch + tick runs the streak steps; switch with no tick writes only the count) |
| M8 the count read as `int?` | 1 | T1 1 (stored double) |
| M9 `last_workout_date` assigned instead of `laterIsoDate` | 1 | T1 2 (backdated same week, later stored date stays) |
| M10 the first owner guard removed | 1 | T1 1; T3 3 (all three account-change cases) |
| M11 a reckon fault inside the count's try | 1 | T1 1 (throw in reckon) |
| M12 the IST normalisation dropped | 1 | T1 1 (22:00 UTC Sunday) |

Every mutated file was restored byte-identical (`cmp`), and the seven product files were compared with the pre-run
diff afterwards.

**Not as predicted.** The plan expected M1 to redden the "completed status, no wlog_" chat-card case too. It does
not: that day is a first wlog, so +1 and the heal both give 1. The second Active Workout session is the case that
separates them, and it reddens.

**Test harness note.** A gate Completer created in the fake-async test zone never resumes a submit held inside
`tester.runAsync` (its completion is queued on the fake zone's microtask queue). T3 creates its gates inside
`runAsync`.

**Gate 19 baseline (+8 lines, B-pass 2026-11-10 asked why).** `backups/gate19_drift_baseline.txt` gained eight
`workout_read_service.dart :: wlog_* :: {...}` lines. They are false positives of the heuristic, not reads of fields
nobody writes: before 1a the file never named the `'wlog_'` literal (`git show ea37ed59:lib/core/services/workout_read_service.dart | grep -c "'wlog_'"` is 0), and `completedWorkoutDayCount` (`:66`) now does,
so Gate 19 attributes every map field the file reads to `wlog_` rows. The eight fields (`reps`, `sets_detail`,
`distance_km` and the rest) are `exlog_` row reads elsewhere in the file (for example `:106`, `:206`); the new code
reads only `type` and `date` from a `wlog_` row. The lines were added by hand, not by `--update-baseline`, which also
prunes unrelated entries.

## B-pass fixes (2026-11-10, `docs/reviews/coach-workout-parity-bpass.md`)
- **Restore not settled (seat B F1, P1).** The gate used to stop the step after the count, so an Active Workout
  finish before the restore settled skipped `last_workout_date`, badges and the rank check, which the old
  `_persistCompletion` always ran. Now only the streak steps (reckon, weekly, streak row) wait; `last_workout_date`
  (later-wins), badges and rank (unlock / promote only) run. Writer `workout_completion_bookkeeping.dart` step 1b;
  readers `BadgeService.checkAll`, `RankService.evaluateAndPromote`, `mergeCloudProgress` (`laterIsoDate`).
- **Owner re-checked after every await (seat B F2).** `_ownerChanged` runs after the prompt resolve, after the
  count and after the progress write, so an account switch mid-step never writes the old account's streak row or
  badges into the new account.
- **The prompt resolve moved into the step (seat A F1, F3, F4).** The doors resolved `completion_prompt_<date>`
  themselves: the backstop even after a FAILED mark, none re-checked the owner, and Active Workout never did. Now
  step 0b resolves it, after a successful mark only and owner-checked.
- **`markCompleted` keeps a stored duration (seat A F5).** A 0 s mark (tap, backstop) racing a timed save no
  longer wipes `duration_seconds`; a real duration still replaces it.
- Tests: `workout_completion_bookkeeping_behavioral_test.dart` (restore-unsettled rewritten; prompt resolve for
  Active Workout; owner change after prompt / count / progress, three cases), and the 1b files below. Mutation
  table: `docs/diagnoses/2026-11-10-coach-card-marks-uncountable-days-24e630.md`, section "B-pass mutations".

