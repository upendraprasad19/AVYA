---
bug_id: 60dc46
date: 2026-11-26
batch: nutrition-history-v2
status: fixed
tier: full
blast_radius: feature
symptom: |
  Founder, web (2026-11-26): "In hit rate and streaks, everything is zero. What is this?" A sparse logger (27 days logged over 210) saw "best run 0 · current 0" on calories and protein. Code reading: hitStats broke a run on every day whose hit was null (not logged, partial), so any gap between two full days reset it; with logging every few days no run could pass 1, and the insight "Your best protein run is N days in a row" (threshold 5) could never fire.
concept: nutrition_history
sot_registry_entry: nutrition_history
writers:
  - { file: lib/core/services/nutrition_write_service.dart, method_or_widget: "NutritionWriteService.logMeal writes the meal rows (unchanged)", line: 91 }
readers:
  - { file: lib/features/nutrition/services/nutrition_history.dart, method_or_widget: "hitStats: runs now skip a non-full day for calories and protein; current run 0 when stale", line: 488 }
  - { file: lib/features/nutrition/widgets/history/history_sections.dart, method_or_widget: "HistoryHitRates: 'N of M', run wording, zero-state line", line: 208 }
hive_key_prefix: "nlog_ (read only, unchanged)"
hive_key_formula: "n/a (no key change)"
sync_methods: []
restore_methods: []
cloud_table: "none"
cloud_columns: ["none"]
contract_test_path: test/features/nutrition/nutrition_history_v2_test.dart
ist_handling: ["recency bound compares IST day keys via parseDayKey (UTC calendar dates), as every history rule"]
provider_invalidations: ["none (derived in nutritionHistoryProvider, unchanged watches)"]
telemetry_op_types:
  success: ["none"]
  failure: ["none"]
cross_account_guard: "Unchanged: nutritionHistoryProvider's '<anon>' guard."
forbidden_patterns_checked:
  - { pattern: "a run broken by an unlogged day for calories or protein", absent: true }
  - { pattern: "a current run older than 7 days shown as current", absent: true }
proposed_fix: |
  Founder D2 (plan docs/plans/nutrition-history-v2.md §1, §9 U2): hitStats(..., skipUnjudged) skips a day whose hit is null for calories and protein (water keeps the break rule); only a full day that misses breaks a run; currentRun is 0 when the last counted day is more than kRunStaleDays (7) before today. Copy: "N of M" full days, "best run · current (full days in a row)", a zero-state line with one next step (hitZeroReason), insight "N full days in a row". A separate logging run (header) counts consecutive logged days.
regression_test_planned: |
  test/features/nutrition/nutrition_history_v2_test.dart group "runs (60dc46)": a full day every third day keeps a 10-day run; a full miss breaks; 7 vs 8 days stale; water breaks on a no-water day. test/contracts/nutrition_history_writer_to_reader_test.dart: protein (4, 3, 2, 1) with the gap skipped, insight copy.
mutation_proof: |
  Applied by script (count confirmed 1), run against the three history test files, reverted. M1 skip -> break, M2 recency 7 -> 30, M3 water skips, M5 today breaks the logging run, M6 zero-state tie: each turned tests red (counts in the plan §13).
impact_analysis: |
  Runs and the best-run insight now reflect consistency on the days a user logs. Display only; nothing stored.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "nutrition_history.dart hitStats; history_sections.dart HistoryHitRates; whole-project analyze clean of warnings." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "Read-only over nlog_* rows; real-Hive case in nutrition_history_writer_to_reader_test.dart." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "Client-only derived view; no server read or write." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "Client-only." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "Client-only." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "grep of supabase/ for hitStats: none." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Client-only." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "Client-only." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Client-only." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Client-only." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Client-only." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "Client-only." }
recurrence: "Not a recurrence: no prior diagnose on history runs (INDEX grep: c2a4e8, d7b3f1, a9d5c3 are target history and weekly buckets). Class: a rule written for a daily logger applied to a sparse one (the cold-start/absent state of lens 8)."
related_bugs: [d7b3f1]
---

# 60dc46 - history runs broke on every unlogged day

## What happened
A run of target hits reset on any day without a full log, so a user who logs every few days always saw 0.

## The fix
Runs for calories and protein skip days that are not full days; a run older than a week is not "current"; a zero row says why.

## Not established
- The founder's own zeros are inferred from the code shape (the web Hive is in their browser); the test reproduces the shape.
