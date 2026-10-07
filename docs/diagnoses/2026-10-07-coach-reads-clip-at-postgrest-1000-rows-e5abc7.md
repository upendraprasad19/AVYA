---
bug_id: e5abc7
date: 2026-10-07
batch: coach-history-correctness-tools
status: fixed
tier: m_fix
blast_radius: platform
symptom: >-
  getProgressSummary, getExerciseHistory, getNutritionHistory, getPromotionStatus, getPRTimeline and future-prediction read long histories with no paging, so a long period silently stopped at PostgREST's 1,000-row cap with HTTP 200 (OI-296).
concept: wle_live_summary_read_contract
sot_registry_entry: wle_live_summary_read_contract
writers:
  - { file: supabase/functions/_shared/paged_fetch.ts, method: "PostgREST db-max-rows = 1000", line: 1 }
readers:
  - { file: supabase/functions/_shared/paged_fetch_bounded.ts, method_or_widget: "the six readers", line: 1 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: workout_log_exercises
cloud_columns:
  - workout_log_id
  - exercise_id
  - set_number
  - reps
  - is_pr
  - completed_at
  - deleted_at
contract_test_path: supabase/functions/_shared/paged_fetch_bounded_test.ts
ist_handling:
  - "windows are N IST dates; a row's day is the date whose UUID v5 equals workout_log_id (exercise_day.ts), fallback IST(completed_at)"
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "readers are keyed by user_id; liveSummaryRows keys on user_id because workout_log_id is date-only and not user-scoped"
forbidden_patterns_checked:
  - { pattern: "\\.eq\\(\"is_pr\", true\\) before any dedupe in a reader", absent: true }
  - { pattern: "completed_at used to select a day window of wle rows", absent: true }
proposed_fix: >-
  _shared/paged_fetch_bounded.ts fetchPagesBounded (count on page 0 only, offsets advance by rows received, bounded maxPages, truncated flag) and wle_window_read.ts; future-prediction uses fetchAllPages. Tools surface `truncated` where a read can hit its budget (getProgressSummary, getNutritionHistory); getPromotionStatus throws instead of shortening a streak. Gate check_unbounded_cron_reads.dart now scans _shared/tools/** (scoped WARN, flip pending: the LAST L1b commit, at least 24 h after the first, deletes the scoped branch).
regression_test_planned: >-
  supabase/functions/_shared/paged_fetch_bounded_test.ts (plus the per-reader Deno tests named in docs/audit/coach-history-correctness-tools.closure.yaml). Tests use the Deno runner:
  deno test --no-check --allow-all --node-modules-dir=none supabase/functions/.
mutation_proof: >-
  Rule 21, 50 mutants over the shared helpers and every reader (each confirmed applied: the driver asserts the file changed and reports NOT-APPLIED otherwise; restored after each run). First pass 38 RED, 6 survivors and 1 NOT-APPLIED (bad edit text, rebuilt); the survivors were real test gaps, each closed with a new test (server cap below the page size; an out-of-window missing-date-bucket row for getExerciseHistory and getProgressSummary; getPRTimeline `to`; the pr-detection half-open `<` pin; the i-see-you `x reps` template; the weekly-recalc 28-date pin) and re-run RED: 50 of 50 RED in the end (5 more were added for the B-pass fixes: case-insensitive exercise key, `to` defaulting to today, the in-window winner rule, its half-open boundary, the truncated flag; two first survived and were closed with tests). Presence-only pins (pr-detection read bounds, weekly-recalc window, i-see-you wiring) are named as such; the pure functions behind them are behaviourally tested. Driver (mutant list, one edit each): docs/audit/coach-history-correctness-tools.mutants.py.
impact_analysis: >-
  Before: a 90-day summary of a heavy logger clipped silently. After: all rows read or an honest truncated flag.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: not_applicable, evidence: "L1b touches no lib/ file" }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "server readers only" }
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "backups/live_schema_columns.json: workout_log_exercises has id, workout_log_id, user_id, exercise_id, exercise_name, set_number, reps, weight_kg, is_pr, completed_at, deleted_at; no schema change" }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "read-only 2026-10-07: 171 live / 55 tombstoned wle rows, 0 live duplicate groups after migration 155, 47 live PR rows, live volume 143926 kg over 37 days; one live row per key is the post-L1a-1 state the readers now assume AND no longer depend on" }
  - { tier: 5, name: "Migrations applied", status: verified, evidence: "migration 155 applied live 2026-10-07 (single_live trigger); this batch adds none" }
  - { tier: 6, name: "Edge Function code vs deploy", status: verified, evidence: "Edge Functions are NOT deployed by this batch: each deploy is its own founder go, from post-merge main (closure ledger deploy rows); until then the live code is unchanged" }
  - { tier: 7, name: "Cron jobs", status: verified, evidence: "proactive_pr_detection schedule read from the migration writers: 0 * * * * (migration 141); CRON_REGISTRY.md row agrees" }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "service-role and own-user reads unchanged" }
  - { tier: 9, name: "Storage buckets + objects", status: not_applicable, evidence: "none" }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "none" }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "no new push path; pr-detection and i-see-you-callout send fewer, not more, notifications" }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "Deno behavioural tests drive each reader against a table-backed fake that applies the same filters PostgREST does (eq/in/is/gte/lte/order/range/count); no live call is made by tests; live effect measured read-only 2026-10-07" }
recurrence: "recurrence of docs/diagnoses/2026-08-01-unbounded-cron-reads-d3f7b2.md"
related_bugs: []
---

# Coach reads clip at postgrest 1000 rows

## What was wrong

getProgressSummary, getExerciseHistory, getNutritionHistory, getPromotionStatus, getPRTimeline and future-prediction read long histories with no paging, so a long period silently stopped at PostgREST's 1,000-row cap with HTTP 200 (OI-296).

## Fix

_shared/paged_fetch_bounded.ts fetchPagesBounded (count on page 0 only, offsets advance by rows received, bounded maxPages, truncated flag) and wle_window_read.ts; future-prediction uses fetchAllPages. Gate check_unbounded_cron_reads.dart now scans _shared/tools/** (scoped WARN, flip pending: the LAST L1b commit, at least 24 h after the first, deletes the scoped branch).

## Verification

Read-only live check 2026-10-07 (project dedsavbjuwgarrhphgnl): workout_log_exercises has 171 live and 55 tombstoned rows, 0 live duplicate groups (migration 155 applied), 47 live PR rows, 143,926 kg live volume over 37 workout days. Plan: `docs/plans/coach-history-correctness-tools.md` (v12, converged in 11 rounds). Deploys are separate founder-approved actions; until then the live Edge Functions are unchanged.
