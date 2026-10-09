---
bug_id: b4e7a1
date: 2026-10-06
batch: streak-freeze-restore-ownership (Unit 1 of 2: the streak-decay persist is gated on the restore for THIS account having settled)
status: fixed
blast_radius: platform
symptom: |
  Founder (account upendra), 2026-10-06 06:45 IST, phone: Home shows streak 16 with 2 streak freezes. Truth is streak 16 with ZERO freezes in reserve. The Home streak number is a read-only walk (WorkoutRepository.currentStreak) that SIMULATES freeze spending: it only reaches 16 because the missed days 2026-10-03 and 2026-10-05 are counted as covered by two simulated freezes. The chip shows the PERSISTED streak_freezes_available, which was still 2, and the cloud row confirms that no debit was ever persisted (available 2, used_dates unchanged after the 06:46:44 push). Three defects: F1 a cold start never persists the idle-day debit, F2 the same gate is never reset on an account swap so a stale tick debited the NEW account on 2026-09-17 (one freeze lost, 09-16 sits in the permanent ledger although a workout was logged that day), F5 once F1 is fixed a debit can land on a mounted Home with no notice.
concept: streak_decay_restore_settled_marker
sot_registry_entry: streak_decay_restore_settled_marker
writers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: "bumpRestoreCompleted (the ONLY writer of restoreCompletedTick; pre-fix the tick was both the UI-refresh signal AND the decay gate)", line: 1857 }
  - { file: lib/features/auth/screens/restoring/heal_after_restore.dart, method_or_widget: "_healAfterRestoreInBackground (the one pre-fix call site of the bump, only on the background branch and only after the cold-start rollover; post-fix it calls DayRolloverObserver.reckonAndNotifyAfterRestore)", line: 14 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: "_settleRestoreMarker (post-fix: the ONE writer of the per-account restore-settled marker)", line: 1913 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: "restoreFromCloudForUser (post-fix wrapper: runs the core inside RestoreFailureCollector.run, heals titles, then settles the marker)", line: 1944 }
  - { file: lib/core/services/sync/sync_restore_failure_collector.dart, method_or_widget: "RestoreFailureCollector.note (post-fix: records a streak-critical failure into the zone's sink; total, never throws)", line: 56 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: "_reportSyncFailure (the single failure funnel; post-fix its first statement notes the collector)", line: 2882 }
  - { file: lib/core/services/day_rollover_service.dart, method_or_widget: "reckonAndNotifyAfterRestore (post-fix: reckon, one best-effort LOW event, bump LAST)", line: 161 }
  - { file: lib/core/services/sync/sync_restore_failure_collector.dart, method_or_widget: "RestoreFailureCollector.clear (B-pass reviewer B F4: the single-call attempt faulted, the legacy fan-out re-reports for itself)", line: 72 }
  - { file: lib/features/auth/screens/restoring/heal_after_restore.dart, method_or_widget: "healAfterRestoreWhenSucceeded (B-pass reviewer C F1: the CONTINUE escape also gets the post-restore heal + reckon)", line: 93 }
  - { file: lib/core/services/plan_integrity_reconciler.dart, method_or_widget: "filterGhostScheduleEntries (B-pass reviewer B F1: reconcile writes schedule_* rows AFTER the marker settled and outside any collector; a lookup that could not answer now skips the template days)", line: 335 }
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_deletedTemplateCloudIdsOrNull / deletedTemplateCloudIdsForUser (null = could not answer; {} = answered none deleted; the restore-side _deletedTemplateCloudIds keeps the fail-empty wrapper)", line: 1785 }
readers:
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: "reckonStreakDecayAndPersist (the gate: pre-fix restoreCompletedTick.value > 0, post-fix SyncService.restoreSettledForCurrentUser; callers day_rollover_service.dart _doRolloverWithRef, train_provider.dart completeWorkout, and the post-restore reckon)", line: 252 }
  - { file: lib/features/auth/screens/restoring_screen.dart, method_or_widget: "_goHome (awaits runRolloverNow BEFORE the restore's heal is attached, so on a returning user's cold start the tick is still 0 at the only rollover that day; the heal attach is the .then at its end)", line: 298 }
  - { file: lib/features/auth/screens/restoring_screen.dart, method_or_widget: "_onContinueAnyway (B-pass reviewer C F1: leaves the screen while the restore runs; now attaches the heal + reckon through healAfterRestoreWhenSucceeded)", line: 583 }
  - { file: lib/features/home/screens/home_screen.dart, method_or_widget: "invalidateOnBackgroundRestore (post-fix override: invalidateOnRetry plus _checkStreakFreezeUsed, so a debit landed by the background restore shows its notice on an already-mounted Home)", line: 186 }
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: "StreakFreezeNotifier (the chip; reads the PERSISTED count)", line: 274 }
hive_key_prefix: progress
hive_key_formula: "userBox['progress'][streak_freezes_available | streak_freeze_used_dates | streak_freeze_just_used | current_streak_days]; the marker itself is in memory only (SyncService._restoreSettledUserId), never persisted"
sync_methods:
  - syncFreezes
  - syncProgressNow
restore_methods:
  - restoreFromCloudForUser
  - _restoreWorkoutPlan
  - _restoreWorkoutLogs
  - _restoreScheduleCompletions
  - _restoreScheduledWorkouts
  - _restoreUserProgress
  - _restoreUserProfile
  - _restoreFreezes
contract_test_path: test/contracts/streak_reckon_restore_settled_behavioral_test.dart
cloud_table: user_progress
cloud_columns:
  - streak_freezes_available
  - streak_freezes_used_dates
  - current_streak_days
ist_handling:
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: "reckonStreakDecayAndPersist -> consumeMissedDayIfFreezeAvailable walks IST date keys; this batch changes only WHEN the reckon may persist, not any date arithmetic", line: 252 }
provider_invalidations:
  - restoreCompletedTick listeners (Home, Train, Nutrition, AI Coach) are now notified AFTER the reckon, so they repaint from the debited ledger
  - streakProvider and streakFreezeProvider through Home's invalidateOnRetry (unchanged set)
telemetry_op_types:
  success:
    - streak_reckon_withheld
  failure:
    - bg_heal_streak_reckon
cross_account_guard: "The gate is now PER ACCOUNT: the marker names the account whose restore settled and the getter requires marker == _liveUserId == HiveUserSession.currentOwnerFullId. _onUserChanged clears it, so an account swap cannot inherit a settled state (the 2026-09-17 spurious debit). The wrapper captures the uid BEFORE awaiting and settles only if the live uid and the Hive owner still equal it (pure shouldSettleRestoreMarker, one unit-test row per clause). A to B to A inside ONE restore step stays the pre-existing e5c2d1 residual (restoreAbortedFor runs only between steps)."
forbidden_patterns_checked:
  - { pattern: "restoreCompletedTick.value > 0 as the streak-decay gate (outside the kill-switch branch)", absent: true }
  - { pattern: "a restore_ prefix match for the critical op set (weeklyFullSync pushes through _safeRestoreOp with sync_* labels that say nothing about the walk)", absent: true }
  - { pattern: "a failed-op set read from _safeRestoreOp's catch (blind: every op swallows its own error and returns normally; only the 45 s ceiling reaches that catch)", absent: true }
  - { pattern: "a mutable field as the failure sink (a concurrent restoreLightweightAlways or push sweep would pollute or clear it; the sink is a zone value)", absent: true }
  - { pattern: "a write, a telemetry call or a writer-vocabulary call inside the restoreSettledForCurrentUser getter (the CQRS gate scans every getter)", absent: true }
  - { pattern: "a bare bumpRestoreCompleted call in the background heal (it must go through reckonAndNotifyAfterRestore so the bump is LAST)", absent: true }
proposed_fix: |
  1. Marker. SyncService._restoreSettledUserId (in memory) is set by the restoreFromCloudForUser() wrapper only when the restore succeeded AND no streak-critical op REPORTED a failure AND the captured uid is still the live uid and the open Hive owner. restoreSettledForCurrentUser is a PURE getter (marker == live uid == Hive owner). _onUserChanged clears the marker and the withheld reason.
  2. Failure collector at the funnel. Every restore op catches its own error, calls _reportSyncFailure(opType: 'restore_<x>') and returns normally, so a failed-op set read from _safeRestoreOp is blind. RestoreFailureCollector (new part file sync/sync_restore_failure_collector.dart) is a zone-scoped sink fed by the FIRST statement of _reportSyncFailure; the allowlist kStreakCriticalRestoreOpTypes is EXACT: restore_workout_plan, restore_workout_logs, restore_schedule_completions, restore_scheduled_workouts, restore_user_progress, restore_user_profile, restore_freezes, restore_deleted_template_ids. The last is the one op not emitted through the funnel: _deletedTemplateCloudIds fails EMPTY by design, but inside a "successful" plan or scheduled-workouts restore an empty answer lets ghost days back in as past planned rows and the debit would become permanent, so its catch calls the collector directly.
  3. Gate. reckonStreakDecayAndPersist replaces the tick test with restoreSettledForCurrentUser (the empty-schedule gate and the reentrancy guard stay). Kill switch disable_streak_reckon_user_gate (fail-open getter in SyncFlags): set means the pre-fix tick gate verbatim.
  4. Post-restore reckon. DayRolloverObserver.reckonAndNotifyAfterRestore(): reckon + persist (try/catch, reason bg_heal_streak_reckon), one best-effort LOW streak_reckon_withheld event when the restore succeeded but did not settle, then bump restoreCompletedTick LAST. The background heal calls it after refillIfNewWeek(). The foreground branch needs no new call: it awaits the restore before runRolloverNow, so the marker is set when the rollover reckons.
  5. Home notice. Home overrides invalidateOnBackgroundRestore to run _checkStreakFreezeUsed, so a debit landed by the background restore shows the freeze notice on a mounted Home (the check clears streak_freeze_just_used before it schedules the snackbar, so initTab plus the tick listener cannot double-fire).
  6. B-pass reviewer B F1 (P2, verified): PlanIntegrityReconciler.reconcile writes schedule_* rows AFTER the marker settled and OUTSIDE any collector zone, through the public forwarder deletedTemplateCloudIdsForUser, which failed EMPTY. A failed lookup therefore wrote a deleted template's day back as a past planned row, and the heal's reckon (or any later one) debited a freeze for it for good. The lookup is now tri-state (_deletedTemplateCloudIdsOrNull: null = could not answer, {} = answered none deleted; the restore-side wrapper keeps fail-empty and the collector keeps withholding the marker there) and reconcile routes its bundle through the extracted filterGhostScheduleEntries, which SKIPS every tmpl_<uuid> day on null (a legacy-shaped key can never be a ghost and is kept without a query). The same hole existed for the foreground and boot reconcile callers; fixing it at the writer closes all three.
  7. B-pass reviewer C F1: healAfterRestoreWhenSucceeded attaches the heal + reckon to the in-flight restore from _onContinueAnyway (a failed or cancelled restore never heals). Before, that cohort could settle the marker and never reckon until completeWorkout, a midnight rollover or the next cold start. restoring_screen.dart gained three lines (Gate 43 headroom 6); the logic lives in the part file.
  8. B-pass reviewer B F3/F4: _onUserChanged clears the marker as its FIRST statement (every later step can throw; a throw must not leave account A's marker open for an A -> B -> A return); a single-call FAULT clears the failure sink before the legacy fan-out re-runs the ops (RestoreFailureCollector.clear), so a stale entry from the aborted attempt cannot hold the marker closed.
  9. B-pass reviewer B F2: three more critical reads are driven through the REAL restoreFromCloudForUser (workout_logs, workout_schedule_completions, user_progress each answering 500 withhold the marker and name their op).
regression_test_planned: |
  test/contracts/streak_reckon_restore_settled_behavioral_test.dart (59 tests, all new: 41 from the first pass plus 18 from the B-pass). T1 the collector (records an allowlisted op, ignores non-allowlisted and out-of-zone notes, two concurrent runs isolated). T2 marker set and tick pinned at 0 => the reckon PERSISTS (the cold-start and foreground cases the old gate never opened). T3 marker = A, live uid = B, tick > 0 => NO persist (the F2 repro, fails pre-fix). T3b _onUserChanged clears the marker. T3c marker null, tick > 0 => NO persist (the F1 repro, fails pre-fix). T4 reckonAndNotifyAfterRestore reckons FIRST and bumps LAST (a tick listener records streak_freezes_available at callback time and already sees the debit). T4b withheld => no persist, tick still bumped, the event carries the reason. T5 a REAL failure through the real funnel for each critical op (malformed payload through restoreFreezesForTest, restoreUserProgressForTest, restoreWorkoutPlanForTest, restoreUserProfileForTest, restoreScheduledWorkoutsForTest, and the deleted-template-ids lookup). T6 kill switch => the pre-fix tick gate verbatim. T7 through the real restoreFromCloudForUser() (legacy fan-out under SyncHarness): all reads OK => marker set, scheduled_workouts 500 => withheld and the reason names the op, a non-critical weight_logs failure still settles, a later failed restore never clears an earlier success, and end to end a settled restore persists the founder's idle-day debit while a withheld one persists nothing. T8 forcing function: every _safeRestoreOp label (newline-tolerant regex, 15 next-line labels) in the core AND the single-call path is classified, all seven critical labels FOUND in both (a vacuous scan fails), each critical op spelling pinned. T9 presence pins (labelled). T10 shouldSettleRestoreMarker, one row per clause. B-pass additions: T1 clear() empties only the active zone sink; T5 the lookup forwarder returns null on a failed read and {} / the id on an answered one (mirror), and the restore-side wrapper still fails empty and notes the collector; T7 workout_logs, workout_schedule_completions and user_progress each withhold the marker through the real wrapper; T9 pins for the marker-clear-first and the single-call-fault clear (labelled presence-only); T11 filterGhostScheduleEntries (null skips the template days and keeps the plain one, {} keeps all, an answered set drops exactly the ghost, one lookup however many days and none for a legacy key, reconcile routes through it); T12 healAfterRestoreWhenSucceeded (success heals once; failed, cancelled, null and a throwing future never heal; a pending future waits; _onContinueAnyway attaches it after navigating only with the Hive session open). Also repointed, never loosened: streak_decay_reckon_permanent_ledger_test.dart (the gate tests open the NEW gate; the two gate-OFF tests keep the marker null with tick = 1 and now FAIL pre-fix), background_restore_test.dart (the heal calls reckonAndNotifyAfterRestore after refillIfNewWeek and never a bare bump), sync_service_public_api_snapshot_test.dart, restore_write_if_changed_test.dart and restore_lightweight_single_plan_fetch_test.dart (fixtures made truthful about the account uid).
mutation_proof: |
  Rule 21, scratch-copy protocol (copy, mutate with sed, confirm the hash CHANGED, run, restore from the copy, confirm the hash identical; no run was a compile error). Run against the new test file only (41 tests): N1 the marker is never set 4 red; N2 the collector note removed from _reportSyncFailure 9 red; N3 the bump moved BEFORE the reckon 4 red; N4 the marker not cleared by _onUserChanged 1 red; N5 the gate back to the tick 4 red; N6a live-uid clause dropped from shouldSettleRestoreMarker 1 red; N6b Hive-owner clause dropped 1 red; N6c failures clause dropped 4 red; N7 restore_scheduled_workouts dropped from the allowlist 5 red; N8 the deleted-template-ids note removed 2 red. B-pass, against the 59-test file: N6d result.succeeded clause dropped 2 red; N6e uid != null clause dropped 1 red (so ALL FIVE conjuncts of the settle decision now have a killer, the original pass mutated three); MB1 the reconciler treats null as empty 1 red; MB2 the forwarder back to fail-empty 1 red; MB3a/b/c restore_workout_logs / restore_schedule_completions / restore_user_progress dropped from the allowlist 2 / 1 / 3 red; MB4 a step placed before the marker clear in _onUserChanged 1 red; MB5a the single-call-fault clear call removed 1 red; MB5b clear() neutered 1 red; MB6 the CONTINUE-escape attach removed 1 red; MB7 the heal ignoring the restore result 1 red. MB4, MB5a and MB6 are caught by presence pins only (labelled); the behaviour of the marker clear, the sink clear and the heal helper is covered by T3b, the T1 clear test and the T12 unit rows. Every mutation reddened a distinct, expected set.
impact_analysis: |
  Confirmed on ONE account (the founder's) from live read-only SELECTs and client_errors, project dedsavbjuwgarrhphgnl, 2026-10-06; every other user on a returning-user cold start is exposed to F1 by the code (the reckon never persists on a cold start for once-a-day usage; completeWorkout, a resume across midnight or the foreground midnight timer reckon once the tick is above 0, so this is exact for a user who opens the app once a day, not every session). F2 is exposed on any device that swaps accounts (this one does, routinely). The CONTINUE-escape cohort (a returning-user routing read that failed for 30 s with no local evidence) used to settle the marker with no heal attached; B-pass fix 7 closes it. BEHAVIOUR CHANGES, accepted: (1) the persisted debit now lands on app open, so a user returning after an idle gap sees the freeze count drop and the notice; the shipped rule that a freeze is consumed for every fresh missed day while one is available (_calculateStreak) is unchanged, which means a freeze can be spent when the streak breaks anyway (finding F8, a founder product decision, closure state blocked_on_user); the notice text for a multi-freeze debit still reads "Streak Freeze used! 0 remaining this week."; (2) LIVENESS: ANY streak-critical op that REPORTED a failure (a 57014, a 45 s ceiling, a malformed row) withholds the persist for the whole process, including completeWorkout's reckon, where the pre-fix tick was bumped on result.succeeded regardless. On a bad-backend morning the founder's original symptom therefore recurs until the next cold start whose restore settles cleanly; this is a DESIGNED property the plan disclosed up front (closure state verified_clean with notes, not a closed defect); the failing op is already named in client_errors by _reportSyncFailure, and the new LOW event is best effort; (3) on the foreground branch (fresh install, disable_bg_restore) the tick never bumped so even completeWorkout's reckon was read-only for the whole process; with the marker it persists there. DISCLOSED RESIDUALS (upstream_blocked or blocked_on_user in the closure ledger, OIs minted at commit time): the marker means "no critical op REPORTED a failure", not "every row was fetched": empty-answer blind spots (a user_progress, user_profile, workout_plan or freezes read that returns nothing is silent; on the legacy path an RLS-filtered stale-token empty answer is indistinguishable from an empty table; the default single-call path is service-role and fail-closed), the edge function's silent caps (scheduled_workouts .range(0, 999), workout_schedule_completions no limit; blocked_on_user in the closure ledger because lifting them is an Edge Function change needing the founder's deploy go), an A to B to A swap inside one restore step (the pre-existing e5c2d1 class), and the marker is not freshness-bounded (a resume days later reckons against rows another device completed in between; OI-279 is the pull-on-resume fix). F6, the 127-second restore on the morning of the report, is device-measured (per-op restore_op_done durations 9 to 41 seconds, two 45-second ceilings) and its cause (the phone's network or Supabase) cannot be separated from the repo.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "sync_service.dart (marker, getter, pure settle decision, wrapper, _onUserChanged clear first, funnel note, sink clear on a single-call fault), the new part file sync/sync_restore_failure_collector.dart, sync_workout.dart (deleted-template-ids note, tri-state lookup), plan_integrity_reconciler.dart (filterGhostScheduleEntries), sync_flags.dart (kill switch getter), workout_repository.dart (gate), day_rollover_service.dart (reckonAndNotifyAfterRestore), heal_after_restore.dart (+ healAfterRestoreWhenSucceeded), restoring_screen.dart (the CONTINUE-escape attach), home_screen.dart (override). flutter analyze (whole project, --no-fatal-infos): 0 errors and 0 warnings (356 infos, none a warning). Full suite on the final tree (TZ=Asia/Kolkata flutter test test/ --exclude-tags golden, 2026-10-06, 40 min): 7854 passed, 9 skipped, 0 failed, exit 0." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "T2/T4/T7e drive the real reckon over a real Hive workoutBox and userBox (setUpHiveForTests) and read streak_freezes_available, streak_freeze_used_dates and streak_freeze_just_used back after the call." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema change; the persisted debit uses the existing user_progress columns through syncFreezes." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "Read-only SELECTs 2026-10-06 against the founder's user_progress (available 2, used_dates two entries, version 121), scheduled_workouts (16 completed days, 10-03 and 10-05 planned with no workout_logs) and subscriptions; no write. The 2026-09-17 sequence was reconstructed from client_errors (hive_session_closed, auth_signed_in, streak_freeze_consume_done 0.39 s before restore_started)." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: verified, evidence: "REPO READ ONLY: supabase/functions/restore-user-snapshot/index.ts was READ (no deploy, no edit, and NO comparison of the deployed version with the repo file) to confirm the single-call path is service-role and fail-closed on a query error and to record its row caps (.range(0, 999) on scheduled_workouts, no limit on workout_schedule_completions) as a disclosed residual. The deployed bundle was not diffed; this repo has had a fix sit undeployed for 14 days before." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "No cron involvement." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "No policy change; the legacy-path RLS-empty ambiguity is disclosed as a residual, not changed." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Not involved." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "No secret read or written." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "No external service." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "T7 runs the real restoreFromCloudForUser() against a stub server: a 500 on scheduled_workouts withholds the marker and the following reckon persists nothing; an all-OK restore settles it and the same call persists the idle-day debit; a failing non-critical read still settles. Real-device confirmation (cold start after an idle gap: the freeze count drops, the notice shows) is the founder's check and is NOT done." }
recurrence: "Recurrence of f9d2e7 (the D2 reckon; its text says it runs on every app open, true only when the tick is already above 0, and its own Deviation section records the tick is bumped only from the background heal), 9c4a17, a8f3d1, e9d4b7 and 9c8958. Founding symptom of the class: streak 1 / freeze 1 after two idle days. Open board items on the same class: OI-293 (restore outcomes unobservable), OI-294 (success-only tick bump; its requirement 2 'never reuse restoreCompletedTick, it gates streak decay' becomes obsolete), OI-279 (pull-on-resume)."
related_bugs: [f9d2e7, 9c4a17, a8f3d1, e9d4b7, 9c8958, d4a7e1, e5b2a9]
---

# b4e7a1 — the streak decay was gated on a process-wide tick that opened too late and never closed

## What happened

`WorkoutRepository.reckonStreakDecayAndPersist` persists a freeze debit only when the restore has confirmed the real completion history, otherwise a stale `schedule_*` status reads a completed day as missed. The signal for "the restore is done" was `restoreCompletedTick > 0`, a process-wide counter with two properties nobody checked together:

1. **It opens after the one rollover that matters (F1).** For a returning user `RestoringScreen` awaits `runRolloverNow` (`restoring_screen.dart:322`) BEFORE it attaches the restore's `.then(heal)`. The only writer of the tick is the background heal, so at that rollover the tick is 0 even if the restore finished instantly, and nothing re-runs the reckon afterwards. Result: for once-a-day usage the idle-day debit never persists on a cold start, and the Home streak keeps SIMULATING freezes the chip still shows as available.
2. **It never closes (F2).** `_onUserChanged` did not reset it. After an account swap in the same process a tick above 0 is inherited and the reckon persists against the NEW account's pre-restore local rows. On 2026-09-17 the log shows `streak_freeze_consume_done newly=2026-09-16` 0.39 s before `restore_started`, for a day the cloud shows completed: one freeze lost for nothing.

## Fix, in one paragraph

The gate becomes a per-account marker set only by the `restoreFromCloudForUser()` wrapper, and only when no streak-critical restore op REPORTED a failure (a zone-scoped collector fed from the single failure funnel; an exact allowlist; one extra op, the fail-empty deleted-template lookup, notes the collector directly). The background heal now calls `reckonAndNotifyAfterRestore`, which reckons, emits one best-effort event if the restore was withheld, and bumps the tick LAST. Home checks the freeze notice when a background restore lands. Two kill switches: `disable_streak_reckon_user_gate` (this unit) and `disable_progress_freeze_merge` (c9d2f6); with the box unopened the fix stays ON for both.

The B-pass (three context-blind reviewers) added four things to this unit, all verified against the code first: the plan reconciler's ghost-day lookup is tri-state so a failed lookup can no longer write a deleted template's day back after the marker settled (proposed_fix 6); the CONTINUE escape gets the same post-restore heal + reckon (7); the marker clear is `_onUserChanged`'s first statement and a single-call fault clears the failure sink (8); three more critical reads are exercised through the real wrapper (9).

## Why the units were NOT split

Unit 2 (c9d2f6) alone does not fix the report, and Unit 1 must never ship without Unit 2: without it `restoreLightweightAlways`, which runs in another zone on every cold start, can overwrite a just-persisted debit with the stale cloud count. Round 3 found no P0/P1 in Unit 1's mechanism, so the §4.12.1 split rule did not fire. Each unit has its own commit and its own diagnose doc.

## Mutation table

| Mutation (scratch copy, hash confirmed changed and restored) | Tests red (N rows of 41, the rest of 59) |
|---|---|
| N1 marker never set | 4 |
| N2 collector note removed from the funnel | 9 |
| N3 bump moved before the reckon | 4 |
| N4 marker not cleared on account swap | 1 |
| N5 gate back to the tick | 4 |
| N6a live-uid clause dropped | 1 |
| N6b Hive-owner clause dropped | 1 |
| N6c failures clause dropped | 4 |
| N7 allowlist entry dropped | 5 |
| N8 deleted-template-ids note removed | 2 |
| N6d `result.succeeded` clause dropped (B-pass, of 59) | 2 |
| N6e `uid != null` clause dropped (B-pass) | 1 |
| MB1 reconciler treats null as empty | 1 |
| MB2 forwarder back to fail-empty | 1 |
| MB3a `restore_workout_logs` dropped from the allowlist | 2 |
| MB3b `restore_schedule_completions` dropped | 1 |
| MB3c `restore_user_progress` dropped | 3 |
| MB4 a step before the marker clear (presence pin) | 1 |
| MB5a single-call-fault clear call removed (presence pin) | 1 |
| MB5b `clear()` neutered | 1 |
| MB6 CONTINUE-escape attach removed (presence pin) | 1 |
| MB7 heal ignores the restore result | 1 |

Only the new test file was run per mutation; `streak_decay_reckon_permanent_ledger_test.dart` and `background_restore_test.dart` were repointed and re-run unmutated in the full-suite run (7854 passed, 0 failed).

## Limits

See `impact_analysis` (liveness, the empty-answer and cap blind spots, the A to B to A residual, not freshness-bounded). The founder's own ledger remains one freeze short; the founder decided on 2026-10-06 to leave it (no production write).
