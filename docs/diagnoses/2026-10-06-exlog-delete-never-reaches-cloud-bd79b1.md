---
bug_id: bd79b1
date: 2026-10-06
batch: coach-history-correctness-sync
status: fixed
blast_radius: platform
symptom: |
  OI-312. Deleting an exercise log never reaches the cloud. The delete drain
  (`_drainPendingExlogDeletes`) upserts a tombstone keyed on
  (user_id, workout_log_id, exercise_id, set_number). Migration 151's BEFORE
  INSERT branch of `workout_log_exercises_delete_final_rename` suffixes
  `exercise_id` (' ‹del:xxxxxxxx›') BEFORE the ON CONFLICT arbiter runs, so
  the upsert never conflicts with the live row it was meant to delete: the
  live row stays live and a separate suffixed tombstone row is inserted.
  Rolled-back live probe 2026-10-06 (plan V10): live row at set 4 + the
  drain-shaped upsert at set 4 => live=1, tombstones=1, total=2. Every
  server reader (coach tools, weekly report, PR detection) and every restore
  on a new device keeps showing the deleted exercise.
concept: wle_single_live_summary
sot_registry_entry: wle_single_live_summary
writers:
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_drainPendingExlogDeletes — upserts a tombstone at the queued natural key (deleted_at = drain time)", line: 216 }
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: "deleteLog — queues PendingExlogDeletes with the LOCAL count at delete time (resolveSummarySetCount)", line: 1258 }
  - { file: supabase/migrations/151_workout_log_exercises_delete_trigger_insert_path.sql, method_or_widget: "workout_log_exercises_delete_final_rename INSERT branch — suffixes exercise_id before the arbiter (the defect)", line: 75 }
readers:
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_restoreExerciseLogs — skips deleted_at rows only; a live row the delete never reached is restored", line: 910 }
  - { file: supabase/functions/_shared/tools/progress/getExerciseHistory.ts, method_or_widget: "coach history tool — reads live rows (L1b)", line: 1 }
hive_key_prefix: "exlog_"
hive_key_formula: "WorkoutWriteService.exlogKey(date, exerciseName)"
sync_methods:
  - "SyncService._drainPendingExlogDeletes (sync_workout.dart) — the tombstone upsert"
restore_methods:
  - "SyncService._restoreExerciseLogs (sync_workout.dart) — skips deleted_at rows"
cloud_table: workout_log_exercises
cloud_columns: [exercise_id, set_number, deleted_at]
contract_test_path: test/sql/workout_log_exercises_delete_final_rename_live_verify.sql
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  - "sync_drain_pending_exlog_deletes — unchanged; the drain's upsert succeeds both before and after the fix (it simply inserted the wrong row before)"
cross_account_guard: Not applicable — the triggers run SECURITY INVOKER under the pushing user's RLS (wle_update_own); the in-trigger UPDATE can only reach that user's rows.
forbidden_patterns_checked:
  - "tombstone EVERY count at the drain's key — rejected (plan §5 R2): the drain's deleted_at is drain time, so a failed drain followed by a re-log at ANY count would be killed by the late drain; the same-count rule is kept and the stale-count delete (R2) is an installed-APK residual under OI-313 (new APKs: L1a-2 U4)."
  - "move the suffix into an AFTER trigger — rejected: the arbiter has already failed or succeeded by then; the fix must find the live row before the arbiter, in the BEFORE INSERT branch."
  - "hard DELETE of the live row from the trigger — rejected: tombstones are the restore contract (e1c8b4); the live row is UPDATEd to deleted_at, which 151's UPDATE branch renames."
  - "typing the U+2039/U+203A angle quotes in new SQL — rejected (CLAUDE.md §4.9): built with chr(8249)/chr(8250); the produced suffix is byte-identical to 151's."
proposed_fix: |
  L1a-1 migration (one DO block, plan §3 step 3): replace the function body of
  `workout_log_exercises_delete_final_rename`. UPDATE branch unchanged. On an
  INSERT with deleted_at set: take the per-key advisory lock
  (pg_advisory_xact_lock(hashtextextended(user|wlog|exercise))); if a LIVE
  row exists at the same (user_id, workout_log_id, exercise_id, set_number),
  UPDATE it SET deleted_at = new.deleted_at (151's UPDATE branch renames it)
  and RETURN NULL — nothing is inserted; otherwise suffix and insert as 151.
  The same migration repairs existing OI-312 pairs (step 2a): for each
  suffixed tombstone T, every live row at (user, wlog, strip(T.exercise_id)),
  any count, written BEFORE T (age(L.xmin) > age(T.xmin)) is tombstoned; a
  re-log written after T stays. Precondition (a) aborts the whole migration
  if any tombstone is not 151-suffixed.
regression_test_planned:
  - "test/sql/workout_log_exercises_delete_final_rename_live_verify.sql — case C5 (new): live row at 4 + drain-shaped upsert at 4 => 0 live rows, 1 row in total (FAILS before the fix: 'live=1', PASSES after); case C6 (new): drain at 3 leaves the live 4 (the documented same-count rule); cases 1-4 (150/151) wrapped in a marker block, unchanged."
  - "test/sql/wle_single_live_summary_dryrun_cases.sql — R1 (L then T at the same count => L tombstoned), R2 (L, T, re-log L2 at 3 => L tombstoned, L2 live), R3 (duplicate group {3,4} then T at 4 => 0 live), R4 (an unsuffixed tombstone => PRECONDITION_A abort). Run only in the dry-run's before phase."
  - "test/sql/wle_single_live_summary_live_verify.sql — N9 (drain isolation: bystanders at the SAME count — same user's other exercise, same exercise in another workout, another user's row under the same workout_log_id — stay live; owner role so RLS cannot mask a missing user_id), N10 (the drain path holds the per-key advisory lock), N11 (another authenticated user's drain for this user's key changes nothing: SECURITY INVOKER + WITH CHECK). C1_4 case 4 gained a NULL check (a missing row passed both its assertions vacuously)."
  - "test/sql/wle_single_live_summary_dryrun_cases.sql — R6 (2a key isolation with a second user and another workout), R8 (a second apply refuses with ALREADY_APPLIED and changes nothing)."
  - "test/sql/wle_single_live_summary_dryrun_harness.sql — generated; runs every case before and after the migration with an expected outcome per case, and compares what the migration touched with a baseline prediction. Local run 0.18 s."
  - "test/sql/wle_single_live_summary_dryrun_cases.sql (B-pass round 2) — R9/R10: a fixture BEFORE UPDATE trigger swallows the tombstoning, so both END_STATE assertions must abort the migration; R11: rows of different keys sharing an xmin neither abort nor get tombstoned; R12: the migration replaces the caller's lock_timeout with 5s and takes both table locks before its first check. N10/N7 also pin that each trigger takes its advisory lock BEFORE its UPDATE; N12 that both functions are SECURITY INVOKER with an empty search_path; C1_4/C5 pin 151's exact suffix bytes and the drain's deleted_at value."
  - "Mutations (rule 21), local Supabase Postgres 17.6 container (prod is PG 17.6) with a prod-shaped schema + seed: 57 mutants after two B-pass rounds, 55 red, 2 equivalent for every reachable input (single_live's WHEN clause removed: the rename trigger has already suffixed exercise_id, so single_live matches nothing on a tombstone insert; the `$` anchor dropped from the suffix regex: differs only for an exercise name containing U+2039 mid-string). D0-relevant: M1 no step 2a => END_STATE aborts R1-R3, R5, R6, R8 and the migration phase; M2 no age guard => R2; M3 no INSERT-branch fix => C5; M10 no precondition (a) => R4; A9 no lock in the rename function => N10; A10 lock key without exercise_id => N10; A11a/b/c the drain UPDATE without user_id / workout_log_id / exercise_id => N9; A20 `if found` -> `if true` => C1_4; A26a/b 2a join without user_id / workout_log_id => R6; A31 the rename function SECURITY DEFINER => N11; no ALREADY_APPLIED guard => R8. Each mutant confirmed applied (exact-text replacement, count == 1)."
  - "B-pass 2026-10-06 (two fresh reviewers, one reading, one executing on the local container): the first-draft cases pinned no key predicate (about 20 mutants green), a second apply tombstoned every kept row, and the drain lock was unpinned — all fixed above; review file in docs/reviews/."
impact_analysis: |
  - Deletes of exercise logs reach the cloud for EVERY APK, installed ones
    included (the fix is server-side): the coach, weekly report and PR
    detection stop counting deleted exercises, and a new-device restore no
    longer brings them back.
  - Existing OI-312 pairs are repaired by the migration (step 2a); V4 = 0
    tombstones on 2026-10-06, so the repair touches nothing today unless a
    delete lands before the apply (snapshot + rollback recipe cover it).
  - The migration refuses a second run (ALREADY_APPLIED): a retried apply
    after an uncertain result cannot tombstone the rows the first run kept.
  - Residuals (installed APKs, OI-313): R1 delete + failed drain + re-log at
    the SAME count => the late drain tombstones the re-log; R2 stale-count
    delete leaves the last pushed row live. New APKs: L1a-2 U4.
related_bugs: [e1c8b4, f4a8c2, OI-312, OI-313]
recurrence: >-
  Recurrence of e1c8b4's own fix. Migration 151 (OI-246 adversarial round 1,
  mirroring f4a8c2/migration 146 for workout_templates) made the delete
  transition suffix on INSERT so a tombstone could be the FIRST cloud write;
  its live verification (cases 1-4) never upserted a tombstone onto an
  EXISTING live row at the same key, which is the drain's normal case. The
  suffix placed before the arbiter turned every normal delete into "insert a
  separate tombstone". Lesson for the class (debugging skill class 2.4, red
  flag added in this batch): a BEFORE INSERT trigger that rewrites a column
  of the ON CONFLICT key defeats the arbiter; verify the trigger with the
  writer's real upsert shape against an existing row, not only against an
  empty key.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: not_applicable, evidence: "No lib/ change in L1a-1; the drain's payload and onConflict target (sync_workout.dart:221-228) are unchanged and verified against uniq_wle_user_wlog_ex_set." }
  - { tier: 3, name: "Postgres schema", status: fixed_in_this_batch, evidence: "Live trigger inventory 2026-10-06 (read-only pg_trigger): workout_log_exercises has trg_suppress_redundant_updates (19) and workout_log_exercises_delete_final_rename (23); workout_log_sets has trg_suppress_redundant_updates only. Constraints/indexes read live (uniq_wle_user_wlog_ex_set, uniq_wls_user_wlog_ex_set, NOT NULL completed_at). The migration replaces the delete function body; after a local apply pg_trigger shows the rename trigger unchanged (23) and the new single_live (7)." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "V4 0 tombstones; V10 rolled-back probe reproduced OI-312 (live=1 tombstones=1); V15 0 rows in the missing-date bucket (plan §0)." }
  - { tier: 5, name: "Migrations applied", status: fixed_in_this_batch, evidence: "Applied live 2026-10-07 (founder go #2) as 155_wle_single_live_summary, cloud version 20261007105911, after the prod rolled-back dry-run (go #1, 2026-10-06, DRYRUN_OK). Post-apply verification is in the 'Live apply' section below; backups/applied_migrations.json entry 155 carries the as-applied sha256." }
  - { tier: 8, name: "RLS policies", status: verified, evidence: "wle_update_own / wle_insert_own (100_rls_initplan_select_wrap.sql:173-176) permit the in-trigger UPDATE of the pushing user's own row; the dry-run harness runs every fixture write as authenticated with request.jwt.claims (prod auth.uid() reads request.jwt.claims, verified live)." }
  - { tier: 12, name: "Client → server contract", status: verified, evidence: "The drain's upsert shape (all columns + onConflict user_id,workout_log_id,exercise_id,set_number => PostgREST INSERT ... ON CONFLICT DO UPDATE) is reproduced verbatim in case C5 and R1-R3." }
---

# Exercise-log deletes never reach the cloud (OI-312)

## Root cause

`_drainPendingExlogDeletes` (`sync_workout.dart:215-243`) upserts a tombstone
on `(user_id, workout_log_id, exercise_id, set_number)`. Migration 151's
`BEFORE INSERT` branch suffixes `exercise_id` on any row with `deleted_at`
set. `BEFORE INSERT` row triggers fire before PostgreSQL's speculative
insertion checks the arbiter index, so the suffixed key never matches the
live row: the upsert inserts a NEW tombstone and leaves the live row live.

## Fix

The delete function's INSERT branch now first tombstones the live row at the
same natural key (under a per-key advisory lock) and returns `NULL`, so
nothing is inserted. The migration also repairs pairs that already exist
(step 2a, guarded by `age(xmin)` so a re-log written after the delete stays
live).

## Verification

Local Supabase Postgres 17.6 container with the prod schema shape: the dry-run
harness returned `DRYRUN_OK` — C5 failed before the migration with its own
message ("the drain at the live row's count left 1 live row(s)") and passed
after; R1–R4 passed; the migration tombstoned exactly the predicted rows.
The prod rolled-back dry-run result (founder go #1) is below.

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
