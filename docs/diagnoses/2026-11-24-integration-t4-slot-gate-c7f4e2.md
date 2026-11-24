---
bug_id: c7f4e2
date: 2026-11-24
batch: oi348-t4-integration (main red since PR 328)
status: fixed
tier: full
blast_radius: feature
symptom: |
  The main-only CI job "Supabase Integration Tests" has been red on every main push since 70add5cf (PR 328, OI-348 Landing 1a-ii, 2026-11-23): runs on 70add5cf, e28cdab8, d0d53f89, 1a45bd9c, b6940494. One test each time: test/supabase/sync_service_test.dart "T4: nutrition logs sync to nutrition_logs table", `rows.single` -> "No element" (nutrition_logs empty for the QA user after the push). No `[sync-skip] nlog` line is printed, so the push sent nothing. The job runs only on a push to main (`if: github.event_name == 'push' && github.ref == 'refs/heads/main'`), so PR 328's own CI could not see it.
concept: nutrition_slot_sync
sot_registry_entry: nutrition_slot_sync
writers:
  - { file: lib/core/services/sync/nutrition_slot_section.dart, method_or_widget: "pushBody: returns before any RPC while the engine is not re-baselined (nslot_push_gated_not_rebaselined)", line: 173 }
  - { file: lib/core/services/sync/nutrition_slot_engine.dart, method_or_widget: "rebaseline: stamps an entry_id on id-less rows; a cloud winner for a slot (row OR tombstone) removes that slot's local rows (removeKeys.addAll(rs))", line: 997 }
  - { file: supabase/migrations/181_nutrition_slot_sync.sql, method_or_widget: "nutrition_logs_tombstone_trg: every direct DELETE of a nutrition_logs row writes a tombstone for its slot", line: 524 }
  - { file: test/supabase/supabase_test_helper.dart, method_or_widget: "cleanup: deletes the QA user's rows (now also nutrition_slot_tombstones, after nutrition_logs)", line: 370 }
readers:
  - { file: test/supabase/sync_service_test.dart, method_or_widget: "T4: seeds an id-less nlog_ row, pulls (re-baseline), pushes, polls nutrition_logs (bounded 30 s)", line: 259 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: "pullNutritionSlots: the launch/resume pull; its first run on a device is the re-baseline", line: 297 }
hive_key_prefix: "nutritionBox nlog_<date>_lunch_qa (the test seed)"
hive_key_formula: "n/a (no key changes)"
sync_methods: [pushNutritionLogsForSyncDomain, pullNutritionSlots]
restore_methods: []
cloud_table: "nutrition_logs, nutrition_log_items, nutrition_slot_tombstones"
cloud_columns: ["unchanged"]
contract_test_path: test/supabase/sync_service_test.dart
ist_handling: ["none: fixed seed date 2026-01-15, unchanged"]
provider_invalidations: ["none: test-only change"]
telemetry_op_types:
  success: ["none"]
  failure: ["none"]
cross_account_guard: "Unchanged. cleanup() still runs assertDisposableTarget before any delete, so the new tombstone delete reaches only the designated QA account's rows; the RLS policy nutrition_slot_tombstones_delete_own (migration 181) also scopes it to auth.uid()."
forbidden_patterns_checked:
  - { pattern: "a product change to make the test pass (the push gate and the tombstone rule are the 1a-ii design)", absent: true }
  - { pattern: "an unbounded wait for the cloud row", absent: true }
  - { pattern: "tombstones deleted BEFORE nutrition_logs (the delete itself would write a new one)", absent: true }
proposed_fix: |
  Test harness only; the product behaviour is the 1a-ii design (spec docs/plans/nutrition-slot-sync.md).
  1. T4 runs the launch order: `pullNutritionSlots(userId)` (the device's first pull is its re-baseline, which stamps an entry_id on the id-less seed), asserts the local row kept and stamped, then `pushNutritionLogsForSyncDomain()`.
  2. The re-baseline's follow-up push is fired by `_release` -> `schedulePush` and awaited by nobody, and while it holds the slot the explicit push only marks itself owed; so the cloud row is awaited by a bounded poll (500 ms steps, 30 s, inside the file's 90 s timeout). The assertions after it are unchanged (`single`, totals, one item `Dal Tadka` at index 0).
  3. cleanup() also deletes `nutrition_slot_tombstones`, placed AFTER `nutrition_logs`: every direct delete of a nutrition_logs row writes a tombstone, and a tombstone left by one run's cleanup would win the next run's re-baseline for (2026-01-15, lunch) and remove the seeded local row, so T4 would pass once and fail on the following run.
regression_test_planned: |
  T4 itself (test/supabase/sync_service_test.dart) is the regression test; it runs only in the main-push CI job (QA credentials are CI secrets, not on this machine). Locally the file compiles, analyzes clean (one pre-existing deprecation info in the helper) and skips by design.
  test/supabase/cleanup_call_timeout_test.dart (credential-free, runs in Unit Tests): table counts repointed 12 -> 13 and 13 -> 14 (PR 335's first CI run caught the stale counts), plus a new pin that nutrition_slot_tombstones is deleted after nutrition_logs.
mutation_proof: |
  Rule 21, stated honestly: this test cannot run on this machine (no QA credentials; I do not handle the password). The "mutant" is the pre-fix test, which is red on 5 consecutive main runs (45195149928, 45227053138, 45313402791, 45319467400, 45320916004), every time on T4 alone. The fix is proven by (a) the first main run after the merge: T4 green, and (b) the SECOND main run after it: T4 green again, which is the run the tombstone cleanup exists for (without it, (b) is the run that fails). Live check after (a): `select count(*) from nutrition_slot_tombstones where user_id = <QA user>` must be 0. Recorded below once observed.
  Order pin (runs here): mutant = tombstones moved before nutrition_logs in cleanup() (grep showed 'nutrition_slot_tombstones' at 392, 'nutrition_logs' at 393) -> 1 of 4 red in cleanup_call_timeout_test.dart; restored by cp, cmp identical.
impact_analysis: |
  Test-only. No product code, schema, function or Hive key changes. The main CI's integration job returns to green, which restores the only live check that the nutrition writer lands rows in cloud.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: verified, evidence: "Read pushBody (nutrition_slot_section.dart:173), rebaseline (nutrition_slot_engine.dart:997, removeKeys at 1149), buildPayload (per-entry totals, item food_name from name, item_index by order) on main b6940494; no client change." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "The re-baseline keeps the seed key and stamps entry_id (kRows[k] for a non-UUID row); T4 now asserts it." }
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "Migration 181: nutrition_slot_tombstones with delete_own RLS; nutrition_slot_put writes nutrition_logs + nutrition_log_items." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "Live 2026-11-24: 0 tombstones for the QA user (039b8eb3...), consistent with T4 never having pushed a row since 1a-ii (cleanup had nothing to delete)." }
  - { tier: 5, name: "Migrations applied", status: verified, evidence: "181 is live (applied 2026-11-23, ledger)." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No function involved." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "None." }
  - { tier: 8, name: "RLS policies", status: verified, evidence: "nutrition_slot_tombstones_delete_own: USING auth.uid() = user_id, so the QA session can delete its own tombstones." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "None." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "None changed." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "None." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "T4 drives the real pull and push against the live project in the main CI job." }
recurrence: "Recurrence of the 'a green check is only as wide as its input set' class (feedback_green_check_input_set_width.md): PR 328 was green on every PR job, but the one job that exercises the live nutrition writer runs only after the merge, and main then stayed red for 5 runs. Same class as the 2026-11-23 and 2026-11-24 instances in that file."
related_bugs: [a6c4e2]
---

# c7f4e2 - integration T4 vs the nutrition slot gate

## What happened
Landing 1a-ii (a6c4e2) replaced the nutrition push with the slot engine. By design it sends nothing until the device's first pull has re-baselined it, and it only sends rows that carry an `entry_id`. T4 seeds an id-less row in a fresh session and pushes without a pull, so nothing is sent and `rows.single` fails. The job that runs T4 only runs on main, so the PR was green and main went red.

## The fix
T4 now follows the app's launch order (pull, then push) and waits up to 30 s for the row, because the re-baseline's own push is not awaited by anyone. The cleanup also clears the QA user's tombstones after deleting its meals. Otherwise the next run's re-baseline sees a tombstone for the same slot and removes the seeded row.

## Residual, stated
- Proof needs two main runs (see mutation_proof); until both are green this doc is self-attested.
- The job still runs only on main pushes, so a PR cannot see this class before merging. Changing that means giving PR runs the QA secrets, which is a founder decision and is not changed here.
