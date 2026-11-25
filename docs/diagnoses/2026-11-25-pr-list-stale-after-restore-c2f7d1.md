---
bug_id: c2f7d1
date: 2026-11-25
batch: pr-strength-charts
status: fixed
tier: full
blast_radius: feature
symptom: |
  Found by plan review (round 1) of the PR strength charts, confirmed by reading the code and by a behavioral test, NOT observed on a device: after a completed background restore the Home PR card (and Train's PR tiles) keep the value they were built with. A returning user whose exercise logs arrive by restore sees "Log workouts to see your PRs here", or a stale list, until a workout is logged, a log is edited, or the day rolls over.
concept: exercise_personal_records
sot_registry_entry: exercise_personal_records
writers:
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_restoreExerciseLogs: writes exlog_* rows into workoutBox during a restore", line: 972 }
readers:
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: "AllExercisePRsNotifier.build: reads the box once per build (WorkoutRepository.loadAllExercisePRs)", line: 1097 }
  - { file: lib/features/home/screens/home_screen.dart, method_or_widget: "invalidateOnRetry (also the body of invalidateOnBackgroundRestore): does not list allExercisePRsProvider", line: 156 }
hive_key_prefix: "exlog_ (read only)"
hive_key_formula: "n/a (no key change)"
sync_methods: []
restore_methods: ["_restoreExerciseLogs"]
cloud_table: "none"
cloud_columns: ["none"]
contract_test_path: test/contracts/pr_list_follows_restore_tick_behavioral_test.dart
ist_handling: ["unchanged: the PR day comes from WorkoutReadService.istDateForExlogRow"]
provider_invalidations: ["allExercisePRsProvider now watches restoreCompletedTickProvider (home_provider.dart:1105); exercisePrSeriesProvider follows it because it takes the PR list as its input"]
telemetry_op_types:
  success: ["none"]
  failure: ["none"]
cross_account_guard: "Unchanged. The watch sits AFTER the '<anon>' early return, as in StreakNotifier.build, so a signed-out build still reads no box."
forbidden_patterns_checked:
  - { pattern: "a second ref.invalidate(allExercisePRsProvider) added to Home's invalidateOnRetry only (would leave Train's StatsGrid stale when Home is not mounted)", absent: true }
  - { pattern: "a Hive read before the token check in AllExercisePRsNotifier.build", absent: true }
proposed_fix: |
  AllExercisePRsNotifier.build adds ref.watch(restoreCompletedTickProvider) after the '<anon>' return and before loadAllExercisePRs. That provider bridges SyncService.restoreCompletedTick, which the post-restore heal bumps LAST, so every completed restore rebuilds the PR list whichever tab is mounted. It is the mechanism the streak chip providers already use (diagnose freeze-refill-sync).
regression_test_planned: |
  test/contracts/pr_list_follows_restore_tick_behavioral_test.dart: real Hive and SyncHarness; read the PR list (empty), write two restore-shaped exlog rows, assert still empty, bump the tick (SyncService.bumpRestoreCompleted), assert the tick provider moved (so the test cannot pass on its no-SyncService fallback), assert the PR and its two-point series.
mutation_proof: |
  The watch line deleted (applied: file content changed, counted 1 site): the test goes red (0 passed, 1 failed). Reverted from the in-memory original. Run together with eight other mutants of the same batch (docs/plans/pr-strength-charts.md section 5.6), each red.
impact_analysis: |
  Client only, one added watch. The PR list (Home card, see-all list, Train StatsGrid, graduation stats readers of the same provider) and the new PR charts rebuild once per completed restore. No write, no sync, no schema.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "home_provider.dart:1105; flutter analyze --no-fatal-infos on the whole project in the batch gate loop." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "The regression test writes real workoutBox rows and reads them back through the provider." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema involved." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "No data involved." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "None." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "None." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "None." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "None." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "None." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "None." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "None." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "The restore itself is unchanged; only a local reader follows its completion tick." }
recurrence: "Recurrence of the class 'a Hive-reading provider that nothing rebuilds after a write made outside its watched dependencies': 9c8958 (streakFreezeProvider missing from the day-rollover list), b3c9d4 (userProfileProvider missing from Home's restore list) and the freeze-refill-sync chip fix that introduced restoreCompletedTickProvider. Same known-good fix applied: watch the restore tick at the source."
related_bugs: [9c8958, b3c9d4]
---

# c2f7d1 - the PR list does not follow a completed restore

## What happened
`AllExercisePRsNotifier` reads the workout box once per build. A background restore writes exercise logs after Home is already mounted, and nothing rebuilt the notifier: Home's `invalidateOnRetry` (the list its background-restore hook runs) never named `allExercisePRsProvider`, and the notifier watched only the auth token.

## The fix
One watch on `restoreCompletedTickProvider` inside the notifier, after the signed-out return. Fixing it at the source, not in Home's list, also covers Train's PR tiles when Home has never been built.

## Not established
- Not reproduced on a device. The cause is read from the code and shown by the behavioral test; how often a real returning user hit it is unknown (it needs the restore to finish after Home's first build).
- Whether the launch-path (blocking) restore is affected: there Home is built after the restore, so the first build already sees the rows. Only the background restore leaves the stale window.
