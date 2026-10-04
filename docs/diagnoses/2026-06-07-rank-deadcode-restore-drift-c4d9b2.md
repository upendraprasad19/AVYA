---
bug_id: c4d9b2
date: 2026-06-07
batch: psych-skill-and-audit-2026-06-07 (audit remediation — Batch 5, SoT drift + dead reads)
status: fixed
blast_radius: account
symptom: >
  Five writer/reader-hygiene defects. F2: the rank-ladder DEPLOYMENTS tile read
  progress total_workouts_done while the RANK card read deployments_complete — two
  surfaces showing different numbers for the same concept. F5/F12: the weight_logs
  contract test + sot_registry named home_provider WeightLogNotifier (a pass-through
  delegate) as the writer, not the real writer health_write_service; the registry's
  regression_test even pointed at the streaks test. F18: rank_service computed
  workoutsRemaining only when a gate set totalWorkoutsAtLeast, but no kRankGates
  entry ever sets it, so the value was always null and the service-record
  "in ~N workouts" branch was dead. F39: workout-log restore wrote a sets_completed
  value, but migration 067 dropped that column (cloud 100% NULL) — a dead restore
  write.
concept: writer_reader_drift_and_dead_reads
sot_registry_entry: "deployments_complete → UserRepository.saveProgress (writer) / rank_ladder_screen + service_record_section (readers, BOTH now deployments_complete); weight_logs → health_write_service.logWeight (canonical writer), home_provider is a delegate"
writers:
  - "lib/shared/repositories/user_repository.dart saveProgress — stamps deployments_complete (monotonic); the F2 defect was reader-side"
  - "{ file: lib/core/services/health_write_service.dart, line: 114 } — canonical weight_logs writer (F5/F12)"
readers:
  - "{ file: lib/features/profile/screens/rank_ladder_screen.dart, line: 302 } — DEPLOYMENTS tile now reads deployments_complete (F2)"
  - "{ file: lib/features/profile/widgets/service_record_section.dart, line: 180 } — dead workoutsRemaining branch removed (F18)"
  - "{ file: lib/core/services/sync/sync_workout.dart, line: 596 } — restore no longer writes the dropped sets_completed (F39)"
hive_key_prefix: n/a
hive_key_formula: "deployments_complete = current_phase - 1 (monotonic); weight_dateStr (health_write_service)"
sync_methods: n/a
restore_methods: "_restoreWorkoutLogs (sync_workout.dart) — dead sets_completed write removed (F39)"
cloud_table: workout_logs
cloud_columns: "sets_completed (DROPPED migration 067 — F39); total_workouts_done vs deployments_complete on user_progress (F2)"
contract_test_path: test/contracts/audit_2026_06_07_batch5_regression_test.dart
ist_handling: n/a
provider_invalidations: n/a
telemetry_op_types: n/a
cross_account_guard: n/a
forbidden_patterns_checked: >
  rank_service + service_record no longer contain workoutsRemaining (comments
  stripped); sync_workout restore no longer writes the dropped sets_completed;
  rank_ladder no longer reads total_workouts_done under the DEPLOYMENTS label.
  Asserted by the Batch 5 regression guard + the F2/F5 behavioural tests.
proposed_fix: >
  F2: rank_ladder_screen reads progress deployments_complete (matching the RANK
  card). F5: weight_logs test retargets the WRITER assertions at health_write_service
  (key build + type stamp + syncWeightNow). F12: sot_registry names
  health_write_service.logWeight as canonical writer + fixes regression_test to
  weight_logs_writer_to_reader_test. F18: drop the workoutsRemaining computation +
  the RankInfo field + the dead service-record branch. F39: remove the dead
  sets_completed restore write.
regression_test_planned: test/contracts/audit_2026_06_07_batch5_regression_test.dart (F18/F39 groups) + deployments_complete_writer_to_reader_test.dart (F2) + weight_logs_writer_to_reader_test.dart (F5) — all GREEN
touched_layers_checked:
  - "{ layer: client_code, status: fixed_in_this_batch, evidence: F2 reader aligned; F18/F39 dead paths removed; analyze clean }"
  - "{ layer: hive, status: verified, evidence: F2 deployments_complete monotonic writer-to-reader test green (4 cases); F5 weight_logs writer test green (8 cases) }"
  - "{ layer: postgres_schema, status: verified, evidence: workout_logs.sets_completed confirmed dropped (migration 067) — restore write was 100% NULL }"
  - "{ layer: docs_registry, status: fixed_in_this_batch, evidence: sot_registry weight_logs writer + regression_test corrected (F12) }"
impact_analysis: >
  The recurring writer/reader-drift class (15+ instances since Test #6). F2 was a
  live two-surfaces-disagree bug; F5/F12 meant the contract test + registry guarded
  the wrong writer (false confidence); F18/F39 were dead code that would mislead the
  next reader. All account-tier; no money/auth path.
closes-diagnose: c4d9b2
---

# Rank/restore SoT drift + dead reads (F2 / F5 / F12 / F18 / F39)

The recurring writer/reader-drift class plus two dead reads, swept together.

## Fixes
- **F2 — DEPLOYMENTS tile.** `rank_ladder_screen.dart` read
  `progress['total_workouts_done']` under the DEPLOYMENTS label while the RANK card
  (`service_record_section.dart`) read `deployments_complete`. Pointed the tile at
  `deployments_complete`; the reader-side test now pins BOTH surfaces.
- **F5/F12 — weight_logs writer attribution.** The test + `sot_registry.yaml`
  named the `home_provider` delegate; the real writer is
  `health_write_service.logWeight` (builds `weight_<dateStr>`, stamps
  `type:'weight_log'`, fires `syncWeightNow`). Retargeted both; fixed the
  registry's mis-pointed `regression_test`.
- **F18 — dead next-rank workouts plumbing.** No `kRankGates` entry sets
  `totalWorkoutsAtLeast`, so `RankInfo.workoutsRemaining` was always null and the
  "in ~N workouts" service-record branch never rendered. Removed the computation,
  the field, and the dead branch.
- **F39 — dead sets_completed restore.** Migration 067 dropped
  `workout_logs.sets_completed`; the restore write was 100% NULL. Removed.

## Guard
`audit_2026_06_07_batch5_regression_test.dart` (F18/F39) +
`deployments_complete_writer_to_reader_test.dart` (F2) +
`weight_logs_writer_to_reader_test.dart` (F5).
