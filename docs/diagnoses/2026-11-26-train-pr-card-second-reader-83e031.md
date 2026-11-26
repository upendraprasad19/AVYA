---
bug_id: 83e031
date: 2026-11-26
batch: pr-card-unify
status: fixed
tier: full
blast_radius: account
symptom: |
  Founder, web app (2026-11-26): Home's PERSONAL RECORDS (charts, SEE ALL) and Train's YOUR STATS (VIEW ALL EXERCISE PRS) are two different things; Train's list has no chart, and every Train tile says "First logged!". Code reading: Train's grid read the key lifts through its own reader (loadKeyLiftPRs: substring names, so Incline / Dumbbell Bench Press counted as "Bench Press"; top-level weight_kg; a "previous" taken from Hive key order, so "↑ X this month" was not about this month), and its fallback set previous 0, so every tile printed "First logged!".
concept: exercise_personal_records
sot_registry_entry: exercise_personal_records
writers:
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: "WorkoutWriteService.logExercise writes the exlog_* rows (unchanged)", line: 135 }
readers:
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: "loadKeyLiftPRs: the SECOND PR reader (deleted)", line: 1035 }
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "workoutStatsProvider over loadKeyLiftPRs (deleted)", line: 1215 }
  - { file: lib/features/train/screens/train/screen.dart, method_or_widget: "TrainScreen: was StatsGrid (stats_grid.dart, deleted: _loadPRs / 'First logged!' / sheet copy), now PrSnapshot(seeAll: PrSeeAll.button)", line: 344 }
  - { file: lib/features/home/widgets/pr_snapshot.dart, method_or_widget: "PrSnapshot over allExercisePRsProvider -> loadAllExercisePRs (now Home AND Train)", line: 31 }
hive_key_prefix: "exlog_ (read only, unchanged)"
hive_key_formula: "n/a (no key change)"
sync_methods: []
restore_methods: []
cloud_table: "none"
cloud_columns: ["none"]
contract_test_path: test/contracts/pr_card_unify_behavioral_test.dart
ist_handling: ["not date-keyed (PR order is loadAllExercisePRs' own IST day order, unchanged)"]
provider_invalidations: ["workoutStatsProvider removed from: edit_workout_log_sheet, template_builder_screen, train_provider (x2), graduation_screen, day_swap_provider, workout_surface_invalidation, day_rollover_service; each PR-changing site already invalidates allExercisePRsProvider (checked per site); the two that do not (template save / delete) change no exlog row"]
telemetry_op_types:
  success: ["none"]
  failure: ["workout_surface_invalidate_<source> (existing, one entry fewer)"]
cross_account_guard: "Train now reads allExercisePRsProvider and exercisePrSeriesProvider, both return empty on '<anon>' (home_provider.dart AllExercisePRsNotifier.build, pr_series_provider.dart), as workoutStatsProvider did."
forbidden_patterns_checked:
  - { pattern: "a second PR reader outside loadAllExercisePRs (loadKeyLiftPRs, a Train copy of the list sheet)", absent: true }
  - { pattern: "'First logged' / 'this month' text in a PR tile", absent: true }
proposed_fix: |
  Plan docs/plans/pr-card-unify.md (founder D1-D3, D6). Train renders Home's PrSnapshot under a PERSONAL RECORDS eyebrow with seeAll: PrSeeAll.button (Train's full-width VIEW ALL EXERCISE PRS button, opening Home's sheet with sparks and trend sheets); no PR -> Home's line, no button. Deleted: stats_grid.dart, pr_stats_grid.dart (no reference), loadKeyLiftPRs, workoutStatsProvider and its eight invalidation sites, its entry in the mutation-invalidation gate set.
regression_test_planned: |
  test/contracts/pr_card_unify_behavioral_test.dart: six PRs on six days -> Home and Train show the same four tiles newest first; Train has the button and no SEE ALL, Home the link and no button; the button opens the sheet, rows carry sparks and open PrTrendSheet; no PR -> the line, no button; one PR -> the button; no "First logged"; the OI-389 cardio port (30 MIN, 40 M, never 1800). Repointed: exercise_personal_records_writer_to_reader_test (a vacuous "stats_grid exists" test became an assertion on the one card), train_screen_compact_layout_test, signed_out_provider_rebuild_behavioral_test (train_provider 6 -> 5), workout_surface_invalidation_test (7 -> 6), phase_unlock_end_to_end_test, test/safety/provider_invalidation_test 9b, purchase_literal_inventory_test.
mutation_proof: |
  Applied by script (count confirmed), run, reverted; no compile errors. K1 Train passes link: 2 red. K2 the button opens nothing: 1. K3 the empty branch skipped for the button: 1. K4 five tiles: 1. K5 the style inverted: 4.
impact_analysis: |
  Train's PR block now changes with the most recent PRs (founder D1) instead of a fixed Bench / Squat / Deadlift / OHP line-up. One provider fewer rebuilt per workout mutation. No write, sync or schema change.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "pr_snapshot.dart PrSeeAll; train screen.dart; deletions listed above. Whole-project analyze: no warning or error." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "Read-only: the card reads loadAllExercisePRs over exlog_* (unchanged reader); no key written or removed." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "Client display and reader removal only: no schema, data, function, cron, policy, bucket, secret or external service is read or written." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "Client display and reader removal only." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "Client display and reader removal only." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "grep of supabase/ for the deleted symbols: none." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Client display and reader removal only." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "Client display and reader removal only." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Client display and reader removal only." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Client display and reader removal only." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Client display and reader removal only." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "Client display and reader removal only." }
recurrence: "Recurrence of cb1ab1 (2026-05-16): its doc said fixing loadAllExercisePRs closed all three PR displays, including StatsGrid; StatsGrid's key-lift branch was a second reader it never reached. Same class as OI-377 (a duplicate reader of one concept) and debugging class 2.1 (writer/reader drift). Known-good fix applied: delete the duplicate, route every display through the canonical reader."
related_bugs: [cb1ab1, 592da4]
---

# 83e031 - Train's PR grid was a second PR reader

## What happened
Train had its own PR grid over its own key-lift reader. Its names matched by substring, its "previous" came from Hive key order, and its fallback printed "First logged!" on every tile. Its list sheet was a hand copy of Home's without charts.

## The fix
Train renders Home's card with a full-width VIEW ALL button. The duplicate reader, provider, grid and sheet copy are deleted.

## Not established
- Not yet seen on a device or the web app; founder check after the merge.
- The unchanged WardButton label overflows its row at 316 dp under the test font (Ahem); the test runs at 600 dp. Same button, same width as before; DM Sans not measured here.
