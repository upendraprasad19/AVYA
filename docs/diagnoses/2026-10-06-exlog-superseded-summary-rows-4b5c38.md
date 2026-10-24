---
bug_id: 4b5c38
date: 2026-10-06
batch: coach-history-correctness-sync
status: fixed
blast_radius: platform
symptom: |
  OI-307 (writer half). An exercise logged, synced, then edited to a
  different number of sets leaves TWO live summary rows in
  workout_log_exercises for the same (user_id, workout_log_id, exercise_id):
  set_number (the summary's set COUNT) is part of the natural key
  uniq_wle_user_wlog_ex_set (migration 082), so the push after the count
  changed inserts a new row instead of replacing the old one. Live
  2026-10-06 (plan §0): 44 duplicate groups / 99 rows / 1 account, rows
  differing only by set_number, 24 groups with a PR row; per-set rows above
  a lowered count also survive. The coach's history tools, weekly report and
  PR detection count both versions; a new-device restore keeps the OLDEST
  (ascending completed_at + put-if-absent).
concept: wle_single_live_summary
sot_registry_entry: wle_single_live_summary
writers:
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_syncExerciseLogs — summary set_number = resolvedSets.length, upserted on a key that includes it", line: 379 }
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_syncExerciseLogs — summary upsert onConflict user_id,workout_log_id,exercise_id,set_number", line: 481 }
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_syncExerciseLogs — per-set upsert after the summary", line: 494 }
readers:
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_restoreExerciseLogs — ascending completed_at + put-if-absent => the oldest duplicate wins locally; joins every per-set row", line: 866 }
  - { file: supabase/functions/_shared/tools/progress/getExerciseHistory.ts, method_or_widget: "coach history tool — counts every live row (L1b B1 dedupes on its own until this apply)", line: 1 }
  - { file: supabase/functions/weekly-report/index.ts, method_or_widget: "weekly report — sums live rows (L1b)", line: 1 }
hive_key_prefix: "exlog_"
hive_key_formula: "WorkoutWriteService.exlogKey(date, exerciseName)"
sync_methods:
  - "SyncService._syncExerciseLogs (sync_workout.dart) — summary then per-set upsert"
restore_methods:
  - "SyncService._restoreExerciseLogs (sync_workout.dart) — restore-side selection is L1a-2 U2"
cloud_table: workout_log_exercises
cloud_columns: [user_id, workout_log_id, exercise_id, set_number, deleted_at]
contract_test_path: test/sql/wle_single_live_summary_live_verify.sql
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  - "none new — the summary upsert succeeds before and after; the trigger changes which rows stay live"
cross_account_guard: Not applicable — SECURITY INVOKER trigger under the pushing user's RLS; the per-key advisory lock and every UPDATE/DELETE are scoped to new.user_id.
forbidden_patterns_checked:
  - "drop set_number from the natural key — rejected: every installed APK upserts on the 4-column onConflict target; PostgREST needs a matching unique index (42P10 otherwise, test/sql/onconflict_live_arbiter.sql case 19). The server enforces one live row with a trigger instead, which works for installed APKs too."
  - "an AFTER INSERT trigger — rejected (plan round-2 P0): an identical re-push becomes an UPDATE that migration 149's trg_suppress_redundant_updates cancels, and an AFTER trigger never fires on a suppressed update; BEFORE INSERT fires on every PostgREST upsert."
  - "keep the highest set_number or the greatest created_at in the cleanup — rejected: the founder rule is 'last sync or write wins' (2026-10-06); the youngest xmin is the last push (V11: 44/44 distinct, created_at agrees in only 5/44)."
  - "cast new.workout_log_id to uuid in the per-set delete — rejected: non-uuid fixture/legacy ids would throw 22P02; the uuid COLUMN is cast to text (mutant M8 reddens N6 and the 150/151 cases)."
proposed_fix: |
  L1a-1 migration (one DO block, plan §3): cleanup of existing duplicate
  groups (keep the youngest-xmin row, tombstone the rest, delete per-set rows
  above the kept count) with preconditions and an in-body end-state
  assertion, then a new BEFORE INSERT trigger
  workout_log_exercises_single_live WHEN (new.deleted_at is null): per-key
  advisory lock; tombstone live siblings at another set_number (151's UPDATE
  branch renames them); unless new.set_number = 0, delete workout_log_sets
  rows above new.set_number for the key (uuid column cast to text).
regression_test_planned:
  - "test/sql/wle_single_live_summary_live_verify.sql (new) — N1 pushes 4 -> 7 -> 4 => one live row, the last write; N2 identical re-push with a stale sibling => sibling tombstoned; N3 7 -> 4 then sets => per-set rows {1..4}; N4 legacy gapped {1,2,4} at count 3 survives a re-push; N5 a count-0 push supersedes the live row (one live row, count 0) and keeps every per-set row; N6 non-uuid workout_log_id pushes without error; N7 the per-key advisory lock is held; N8 push isolation (owner role, a second user): bystanders — same user's other exercise, same exercise in another workout, another user's row under the same workout_log_id — keep their ids and 12 per-set rows, the pushed key's per-set rows are {1,2,3} right after the summary push (pins the `>` boundary before any sets re-push), and an identical re-push keeps the same row id with no new tombstone. Before the migration N1, N2, N3, N5, N7, N8 FAIL with their own message; N4, N6 pass (invariants)."
  - "test/sql/wle_single_live_summary_dryrun_cases.sql — R5: duplicate {4 older, 3 younger} with sets 1..4 => the live row is the 3, sets {1,2,3} (added after mutant M9 'keep the oldest' was caught only by a seed-dependent count, which prod's data, V12 = 0, would not provide); R6 cleanup key isolation (a second user, another exercise, another workout; count-0 youngest keeps its per-set rows); R7 siblings sharing an xmin => PRECONDITION_B."
  - "Mutations (rule 21), local Supabase Postgres 17.6 container, 57 mutants after two B-pass rounds, 55 red, 2 equivalent (see bd79b1). Round 2 added: the cleanup's ranking/count partitions without user_id / workout_log_id / exercise_id => R6 (bystanders now younger than the kept row, carrying legacy per-set rows above their count); the cleanup's per-set delete on every group (`k.n > 1` -> true) => R6; precondition (b) grouped without a key column => R11; single_live's lock moved after its UPDATE => N7; single_live SECURITY DEFINER or no search_path => N12. D1-relevant: M4 no sibling tombstone => N1, N2, N5, N8; M5 no per-set delete => N3, N8; M6 no lock in single_live => N7; M7 no count-0 guard => N5; M8 cast text to uuid => N6, C1_4; M9 keep the oldest => R5, R6 + the migration-phase count; A1 `>=` / A2 `<>` in the per-set delete => N8; A3/A4/A5 sibling UPDATE without exercise_id / workout_log_id / user_id => N8; dropping `set_number <> new.set_number` (every push would replace the same-count row) => N8; A6/A7/A8 per-set delete without user_id / exercise_id / workout_log_id => N8; A12/A13/A14 cleanup per-set delete without user_id / workout_log_id / exercise_id => R6; A21 no precondition (b) => R7; A23 no count-0 guard in the cleanup => R6; A28 AFTER instead of BEFORE INSERT => N2."
impact_analysis: |
  - After the apply every cloud write leaves one live summary row per
    (user, workout_log_id, exercise_id), for installed APKs too; the 44
    existing groups are cleaned (55 rows tombstoned on 2026-10-06 numbers,
    snapshotted with a rollback recipe).
  - Per-set rows above a lowered count are deleted at push time (they belong
    to the superseded version). 0 exist today (V12).
  - A count-0 push (count unknown, legacy shape) supersedes the live summary
    but deletes no per-set rows; readers take every per-set row under a
    count-0 summary (L1a-2 U2(b)). V16: 0 live count-0 summaries today.
  - Cost: the trigger's per-set DELETE casts the uuid column to text, so it
    cannot use the per-set unique index beyond its user_id prefix; measured
    by the B-pass at 5.9 ms per push for a user with 40k per-set rows. Live
    size 2026-10-06: 559 per-set rows in total — not material.
  - Residuals (plan §5): R3 a per-set push that always fails (duplicate
    explicit set_numbers in a legacy sets_detail) loses the cloud copy of
    above-count sets (Hive keeps them; new APKs: L1a-2 U3 renumbers); R4 a
    stale-device resend after an operator sync_epoch bump supersedes the
    newer row (runbook caveat in docs/operations/SYNC_EPOCH_RESYNC.md); R5
    same-second cross-device per-set interleave (founder-accepted).
related_bugs: [3f8a91, e1c8b4, a3e8f1, e6a2d4, OI-307]
recurrence: >-
  Same concept as 3f8a91 (cloud_upsert_natural_key_contract) and the
  2026-06-02 user_id key fix: the natural key of workout_log_exercises was
  chosen for idempotent re-push, but includes a value (the set count) that
  changes on edit, so an edit is not idempotent. Extends debugging class 2.4
  (partial-unique / ON CONFLICT traps) with the "key column changes on
  edit" shape. Red flag added: an AFTER trigger never fires on an update a
  BEFORE trigger suppressed.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: not_applicable, evidence: "No lib/ change in L1a-1; restore-side selection, per-set renumbering and delete coverage are L1a-2 (docs/plans/coach-history-correctness-client.md)." }
  - { tier: 3, name: "Postgres schema", status: fixed_in_this_batch, evidence: "New trigger workout_log_exercises_single_live (BEFORE INSERT, tgtype 7 after a local apply) + function, SECURITY INVOKER, search_path ''. Live constraints read 2026-10-06: wle.user_id FK public.users, wls.user_id FK auth.users, uniq_wls_user_wlog_ex_set (user_id, workout_log_id, exercise_id, set_number)." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "V1 44 groups/99 rows/1 account; V11 youngest xmin = highest set_number 44/44; V12 0 per-set rows above the kept count; V14 45 orphan per-set rows unreachable (verified_clean); V16 0 count-0 summaries (plan §0)." }
  - { tier: 5, name: "Migrations applied", status: fixed_in_this_batch, evidence: "Applied live 2026-10-07 (founder go #2) as 155_wle_single_live_summary, cloud version 20261007105911, after the prod rolled-back dry-run (go #1, 2026-10-06, DRYRUN_OK). Snapshot backups/wle_single_live_cleanup_snapshot.json; post-apply verification in the 'Live apply' section below; ledger entry 155 carries the as-applied sha256." }
  - { tier: 8, name: "RLS policies", status: verified, evidence: "wle_update_own and workout_log_sets_delete_own (100_rls_initplan_select_wrap.sql:176-177) allow the in-trigger sibling UPDATE and per-set DELETE for the pushing user; every live-verify case runs as authenticated." }
  - { tier: 12, name: "Client → server contract", status: verified, evidence: "_syncExerciseLogs upserts the summary (:481) then the per-set rows (:494); N3/N4 reproduce that order; test/sql/onconflict_live_arbiter.sql case 19 uses a fresh uuid key per run, so the new trigger finds no sibling there." }
---

# Superseded exercise-log summary rows stay live (OI-307, writer half)

## Root cause

`uniq_wle_user_wlog_ex_set` includes `set_number`, which for a summary row is
the set COUNT. `_syncExerciseLogs` upserts on that key (`sync_workout.dart:481`),
so after an edit changes the count the upsert finds no conflict and inserts a
second live row next to the old one. Nothing on the server ever retires the
old version.

## Fix

A `BEFORE INSERT` trigger supersedes live siblings at another count and drops
per-set rows above the new count, serialised per key by an advisory lock;
the migration cleans the 44 existing groups first, keeping each group's last
push (youngest `xmin`).

## Verification

Local Supabase Postgres 17.6 container, prod schema shape + seed: dry-run
harness `DRYRUN_OK`; N1/N2/N3/N7 failed before the migration with their own
messages and passed after; standalone `wle_single_live_summary_live_verify.sql`
after a local apply: "all 7 cases passed". The prod rolled-back dry-run result (founder go #1) is below.

## Prod rolled-back dry-run (founder go #1, 2026-10-06 16:52 UTC)

`test/sql/wle_single_live_summary_dryrun_harness.sql` (sha256 `57996025…40ac`,
embedding the migration text sha256 `62b945e4…26c1`) sent byte-for-byte to
`dedsavbjuwgarrhphgnl` through the Management API query endpoint (one
request, ~2 s round trip). Result, verbatim from the error text:

```
DRYRUN_OK
baseline: dup_groups=44 live=226 tombs=0 wls=559 oi312_pairs=0 expect_tombstoned=55 expect_wls_deleted=0
before: N1 F, N2 F, N3 F, N4 P, N5 F, N6 P, N7 F, N8 F, N9 F, N10 F, N11 P, N12 F, C1_4 P, C5 F, C6 P, R1-R12 P  (all as expected; every F with its own 'FAIL <id>:' message)
migration: dup_groups_after=0 tombstoned=55 (expected 55) wls_deleted=0 (expected 0) oi312_pairs_live_after=0
after: N1-N12, C1_4, C5, C6 all P
```

Read-only check right after: triggers on `workout_log_exercises` unchanged
(`trg_suppress_redundant_updates`, `workout_log_exercises_delete_final_rename`),
0 leftover functions, 0 fixture rows, live 226 / tombstones 0 / per-set 559.
The live delete function is 151's logic applied without its in-body comments
(`prosrc` 242 chars, md5 `34d27274655e507a1346d551f0b8de96`) — the rollback
reference for "151 restored".

## Live apply (founder go #2, 2026-10-07)

Reserved `mig/155` (`mint_migration.sh`, no `--stub`); live migration list read
first (newest applied `153`, `154` reserved by another session). Final
read-only snapshot 2026-10-07 10:56:32 UTC (55 rows to tombstone, 0 per-set
rows to delete, 44 groups) saved to
`backups/wle_single_live_cleanup_snapshot.json`. Applied through MCP
`apply_migration` as `155_wle_single_live_summary` => cloud version
`20261007105911` (the tool call itself took over two minutes; the database work
was sub-second). Post-apply, read-only: stored statement sha256 equals the
file's (`62b945e4…26c1`); `workout_log_exercises_delete_final_rename` and
`workout_log_exercises_single_live` bodies match a local apply (md5
`8a239c83…`, `2fc9a035…`); triggers `trg_suppress_redundant_updates`(19),
`workout_log_exercises_delete_final_rename`(23), `workout_log_exercises_single_live`(7),
all enabled; both functions SECURITY INVOKER with an empty `search_path`;
live 171 / tombstones 55 (all 151-suffixed) / duplicate groups 0 / per-set 559;
the 55 tombstoned ids are exactly the snapshot's, none outside it.
