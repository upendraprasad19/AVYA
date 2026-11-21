---
bug_id: a7c3e1
date: 2026-05-30
batch: web-e2e-2026-05-30
status: fixed
symptom: >
  Surfaced during AUDIT-1 (systematic schema-reference audit, 2026-05-30).
  StatSnapshotService._compute7dAverages selected two columns that do not
  exist: `daily_steps.total_steps` (real column: `steps`) and
  `sleep_logs.hours` (real column: `duration_hrs`). Each SELECT throws
  PostgrestException 42703; because the three queries run sequentially inside
  one try block, the daily_steps query (run first of the two) throws and the
  whole block jumps to catch → every 7d average (calories, protein, steps,
  sleep) returns 0. So promotion snapshots and manual progress snapshots record
  avg_calories_7d / avg_protein_7d / avg_steps_7d / avg_sleep_hours_7d as 0,
  and the snapshot-diff "progress over time" view shows no nutrition/activity
  movement between snapshots.
concept: user_stat_snapshot_7d_averages
sot_registry_entry: n/a
blast_radius: feature
writers:
  - { file: lib/core/services/stat_snapshot_service.dart, method: _compute7dAverages, line: 460 }
readers:
  - { file: lib/core/services/stat_snapshot_service.dart, method: snapshotOnPromotion, line: 265 }
  - { file: lib/core/services/stat_snapshot_service.dart, method: snapshotManual, line: 313 }
hive_key_prefix: "n/a (cloud-only read; user_stat_snapshots is server-side)"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: daily_steps
cloud_columns: [user_id, date, steps]
contract_test_path: test/contracts/stat_snapshot_7d_averages_columns_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [stat_snapshot_compute_7d_averages]
cross_account_guard: >
  Unchanged. _compute7dAverages scopes every query by .eq('user_id', userId)
  where userId is the authenticated supa.auth.currentUser.id.
forbidden_patterns_checked:
  - { pattern: "from('daily_steps').select('total_steps')", absent: true }
  - { pattern: "from('sleep_logs').select('hours')", absent: true }
proposed_fix: >
  daily_steps stores the daily total in column `steps` (NOT `total_steps`);
  sleep_logs stores duration in `duration_hrs` (NOT `hours`). Both verified
  against live information_schema 2026-05-30:
  daily_steps = (id, user_id, date, steps, source, synced_at, created_at);
  sleep_logs = (id, user_id, date, duration_hrs, quality, bed_time, wake_time,
  notes, created_at). Fix: select `steps` + read result key `steps`; select
  `duration_hrs` + read result key `duration_hrs`. The nutrition_logs query in
  the same method (total_calories, total_protein) was already correct.
regression_test_planned:
  - test/contracts/stat_snapshot_7d_averages_columns_test.dart
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "stat_snapshot_service.dart _compute7dAverages now selects steps + duration_hrs and reads those result keys" }
  - { tier: 3, layer: postgres_schema, status: verified, evidence: "information_schema 2026-05-30: daily_steps has `steps` not `total_steps`; sleep_logs has `duration_hrs` not `hours`" }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "live SELECT steps FROM daily_steps -> 1526 (ok); SELECT total_steps FROM daily_steps -> 42703; SELECT duration_hrs FROM sleep_logs -> ok (table empty, no error)" }
  - { tier: 12, layer: end_to_end_contract, status: fixed_in_this_batch, evidence: "source-grep contract test pins correct columns + asserts wrong ones absent; check_schema_column_refs.dart gate validates every .from().select column against committed schema snapshot" }
impact_analysis: >
  Feature-tier (progress-tracking analytics), not account/platform. No data
  loss and no crash: _compute7dAverages is fully wrapped in try/catch returning
  all-zero averages, so the snapshot row still inserts cleanly — it just carries
  0 for all four 7d-average fields on promotion + manual snapshots. The
  onboarding snapshot hardcodes 0 for these fields anyway (no _compute7dAverages
  call), so baseline-vs-current diffs of calories/protein were always 0→0
  regardless. User-visible harm: the "progress over time" snapshot-diff view
  under-reports nutrition + activity trends (always 0 delta). Third instance of
  the wrong-column class found in the 2026-05-30 web-E2E batch (after e2a4f7
  user_profile.full_name and the f4b2c9 trigger). This one was NOT found by the
  live web walk (snapshots fire on promotion, which the trigger bug f4b2c9 had
  itself blocked) — it was found only by the deterministic schema-reference
  audit, which is why the durable fix is a build gate, not another test.
---

# a7c3e1 — StatSnapshotService 7d averages queried two non-existent columns

## What happened
`StatSnapshotService._compute7dAverages` builds the `avg_*_7d` fields for
`user_stat_snapshots` rows. It ran three sequential queries:

1. `nutrition_logs.select('total_calories, total_protein')` — correct.
2. `daily_steps.select('total_steps')` — **wrong**, real column is `steps`.
3. `sleep_logs.select('hours')` — **wrong**, real column is `duration_hrs`.

Query 2 throws `PostgrestException 42703` before query 3 even runs; the method's
try/catch returns `{calories: 0, protein: 0, steps: 0, sleep: 0}`. So every
promotion + manual snapshot persisted **all four** 7d-average fields as 0 — even
calories/protein, whose query succeeded, because the exception unwound the whole
block.

## Why prior audits missed it
- No test exercised the live `daily_steps` / `sleep_logs` columns; the service
  is defensively zero-returning, so a broken query looks identical to "no data
  in the last 7 days." Silent by design.
- `snapshotOnPromotion` only fires from `RankService.evaluateAndPromote` — and
  the f4b2c9 trigger bug was *itself* rolling back every `rank_promotions`
  INSERT, so promotion snapshots rarely ran in practice. The two bugs masked
  each other.
- The live web walk could not reach it (no promotion happened).

## Root cause
Writer/reader column drift between the client SELECT and the live schema —
the same class as e2a4f7 (full_name) and f4b2c9 (trigger). The column names
`total_steps` / `hours` are *plausible* (they read like the right concept) but
never matched the actual table DDL.

## Fix
Select `steps` (daily_steps) and `duration_hrs` (sleep_logs); read those keys
from the result rows. Verified against live `information_schema`.

## Durable prevention
`scripts/check_schema_column_refs.dart` (new gate) extracts every
`.from('<table>').select('<cols>')` / `.eq` / `.gte` / `.order` column reference
in `lib/` and validates each against a committed snapshot of the live
`information_schema` (`backups/live_schema_columns.json`). The wrong-column
class can no longer reach `main` silently — this is the structural answer to
"why do bugs survive our audits": every prior audit was static + mock-data, and
never cross-checked column literals against the real catalog.

## Verification
Live (2026-05-30): `SELECT steps FROM daily_steps LIMIT 1` → 1526;
`SELECT total_steps FROM daily_steps LIMIT 1` → 42703;
`SELECT duration_hrs FROM sleep_logs LIMIT 1` → ok (empty table, no error).
Contract test fails on `main` (asserts the wrong columns absent) and passes
with the fix.
