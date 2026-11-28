---
reviewed_at: 2026-10-11T16:20:00+05:30
staged_against: 7058fd0f49df
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill (one fresh context-blind reader, exhaustive read-only command list, sandbox databases bp_* only; about 110 tool calls)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 10
verdict: accepted
---

# Code Review (B-pass) - OI-320, migration 158 (per-referrer referral cap)

Scope: `supabase/migrations/158_referral_referrer_cap.sql` (untracked when reviewed, because a staged migration needs the ledger entry that exists only after the live apply) (sha256 `527999b451925d04bf8bafba10be5f3e8e44d7dc8922f59ba6cba5a8e92ecafa`, unchanged by every fix below) plus the staged tests, plan, ledger and docs. Result: **no P0 or P1; 5 P2 and 5 P3, every one with a terminal state in this batch.** The reviewer reproduced two of its own findings and wrote 7 mutants of the migration that passed both SQL test files (n1-n7); the fixes make all but two red in SQL and the other two red in a Dart pin (details per finding). The reviewer's report is reproduced in substance; the fix and its proof are the `status:` lines and the ledger rows BP1-BP11 in `docs/audit/oi320-referrer-cap.closure.yaml`.

## Finding 1 - P2 - guard_without_its_mirror
- **file:line:** `test/sql/oi320_referrer_cap_replica_schema.sql:28-29, 64-125, 131`
- **claim:** the replica-only files refuse to run without `public.oi320_replica_marker`, but the file that creates the marker had no guard of its own: run in psql's default mode against a database that already held the replica it created the marker first, REPLACED the capped function with the old uncapped body, inserted 20 users and left a valid marker, so the delete-capable files then ran.
- **verification:** reproduced twice (md5 `e69618b8...` -> `1066f4cb...`, users 20 -> 40, marker f -> t); the deletion file then executed DELETEs instead of refusing.
- **status:** accepted - fixed. The file is one BEGIN ... COMMIT transaction, opens with a guard that raises REFUSED on any existing replica object, creates the marker last; proven in three scenarios; Dart group 3d pins it (9 of 9 mutants red).

## Finding 2 - P2 - writer_reader_drift (can a user rewrite their own audit rows?)
- **file:line:** `docs/plans/oi320-referrer-cap.md` section 4 step 1
- **claim:** the cap holds only if no authenticated user can DELETE or UPDATE their own `referral_redemptions` rows; the repo shows only the SELECT policy but the table predates the migration tree, so dashboard-created write policies could not be ruled out; the apply protocol read `pg_constraint` only.
- **status:** accepted - verified clean on a live read-only query (RLS on, one SELECT policy, no triggers; anon/authenticated hold full grants so RLS is the only barrier) and made durable: apply step 1 re-reads policies, grants and `created_at`; live verify case I7; replica K6 (see ledger BP2, HM1).

## Finding 3 - P2 - process
- **file:line:** `docs/plans/oi320-referrer-cap.md` step 5 and section 3
- **claim:** "merge origin/main into the branch before the commit" cannot work: `docs/sot_registry.yaml` is staged and changed on `origin/main`, so a plain merge refuses, and committing first is blocked by Gate 14 while the unapplied file is on disk.
- **status:** accepted - fixed. Order is apply -> commit -> merge origin/main into the clean branch -> re-run the gate loop.

## Finding 4 - P2 - writer_reader_drift (account-deletion documentation)
- **file:line:** `docs/architecture/payment.md:56`, `docs/naming_conventions.md:294`, `supabase/functions/delete-account/index.ts:16,369-372`, `supabase/migrations/CLAUDE.md` (migration-049 row), `integration_test/flows/delete_account_e2e_test.dart:47-50`
- **claim:** all enumerate exactly five pseudonymised surfaces; `referral_redemptions` is now a sixth that keeps its rows after an account deletion.
- **status:** accepted - fixed in the four documents/tests; the two Edge Function comments are true of migration 049 as written and are deliberately not edited (git-vs-deployed drift of a catastrophic-tier function, no behavioural effect).

## Finding 5 - P2 - blast_radius_mismatch
- **file:line:** `docs/blast_radius.yaml` (catastrophic `requires:` includes `feature_flag`)
- **claim:** neither the plan nor the ledger took a position on the kill-switch requirement.
- **status:** accepted - fixed. Plan section 2 states "no runtime kill switch; the inline rollback block, measured byte-exact, is the revert".

## Finding 6 - P3 - guard_without_its_mirror / asserted_fixture_value
- **file:line:** `test/sql/oi320_referrer_cap_live_verify.sql` (L1; E1; every case used one code)
- **claim:** L1 tested only the NULL-referee arm; no case had a referrer who was also a referee; every case used one code. Mutants n1 (referrer arm dropped), n2 (count also matches rows where the referrer was the referee), n7 (count scoped per code) passed both SQL files.
- **status:** accepted - fixed. L2 (NULL referrer), E1 with the referrer as the referee of a credited row, M1 through a second code. n1/n2/n7 are red (L2; E1,F1; M1,R1).

## Finding 7 - P3 - guard_without_its_mirror (restated, unpinned logic)
- **file:line:** `supabase/migrations/158_referral_referrer_cap.sql:160-162, 175`
- **claim:** the referrer credit block is re-typed inside the new IF; dropping the `status = 'active'` filter (n3) or hard-coding `interval '7 days'` (n5) passed every SQL file and every Dart pin.
- **status:** accepted - fixed. Dart group 3c pins both credit blocks to the previous body's text; 8 of 8 mutants red. n3 and n5 stay green in SQL by design.

## Finding 8 - P3 - writer_reader_drift (SoT registry)
- **claim:** the new concept's `readers:` had one entry although `reader_manifest_complete: true`; the older `referral_redemption` concept lists a nonexistent column `referrer_user_id`.
- **status:** accepted - fixed (five readers added, column corrected; registry gates pass).

## Finding 9 - P3 - documentation truth
- **claim:** OI-336 and the plan cite the invite-copy files at wrong paths; a gate cite line moved; the ledger quotes two mutant counts; two documents say a NULL party is tolerated by "every reader".
- **status:** accepted - fixed.

## Finding 10 - P3 - apply protocol and header gaps
- **claim:** step 1 never reads `created_at`'s type; step 3 never reads `show lock_timeout` after a fired timeout; the window-gap read is taken only before the apply; the header says `Destructive?: no` on a migration that re-creates two foreign keys.
- **status:** accepted - protocol reads added; the header tag stays `no` (nothing is dropped, rewritten or lost; the header spells out the DDL) - ledger BP10.

## Lenses with no findings
- **function_exception_swallow:** `redeem-referral/index.ts` makes exactly one RPC per request and maps anything but 23505 to a generic 500; no `.functions.invoke(` in the diff.
- **blast_radius (rollback):** the commented rollback block, extracted and run on a database with real redemptions and NULL-party rows, returns `md5(pg_get_functiondef)` to `1066f4cb5b1c36058fd5c0b635e3209d` (length 1825), both FKs to CASCADE, both columns NOT NULL, ACL and `search_path` unchanged. Catastrophic tier is right (content rule, `supabase/migrations/*.sql` + SECURITY DEFINER).
- **secrets_in_tree, unawaited_no_error_sink:** nothing (no `lib/` or Edge Function code in the diff).
- **missing_input:** `test/helpers/migration_cap_reader.dart` exports what the test uses; `backups/live_schema_columns.json` lists all 8 columns and no `redeemed_at`; the marker exists in the template; `origin/mig/158` exists.
- **asserted_fixture_value:** old body 9 ok / 17 fail exactly as claimed (before L2), 27 ok on 158; 49 days = 7 x 7; md5 and length match; the Dart file's pins pass.
- **Attacks:** 400 redemptions over 8 clients on one referrer gave exactly 7 credited; mutual redemption 2 x 2500 gave 96 deadlocks on the old body and 0 on 158; a paid active row +20 d credited to +27 d; a cancelled future row gets a new trial; 3 legacy rows older than 90 d do not count; 8 pre-158 rows inside the window are NOT counted (the window gap is real; apply step 2 is the control); NULL referrer raises 23502; self-redemption raises `no_self_referral`; the migration applied twice, with `-1`, and as one string left identical state; a fired `lock_timeout` left a state that a re-run converged from.

## Mutants the reviewer wrote
n1 referrer arm of the guard dropped; n2 count also matches referee rows; n3 `MAX(end_date)` without the status filter; n4 locks moved after the count (red under the race script); n5 referrer extension hard-codes 7 days; n6 shared advisory locks (red under the race script); n7 count scoped per code. All were run against verify (26 cases at the time) and deletion (5); results after the fixes are in `docs/plans/oi320-referrer-cap.md` section 3 and ledger row C16.

## Deviations from the command list (disclosed by the reviewer)
A classifier-denied probe of `pg_database`, one `python3 --version`, one `rm -f` of its own scratch file, `sed` as an output filter; its `bp_*` databases dropped; `/tmp/bp_*.sql` pgbench scripts left inside the sandbox container (removed by the coordinator at cleanup). Nothing outside the sandbox or its scratchpad was touched; no `scripts/*`, gate, git write or network call was run.

## Founder triage notes
All ten findings accepted and resolved in this batch (fixed, or verified clean with the evidence in the ledger).

## Commit-time addendum (2026-10-11, after the live apply)
The migration SQL (sha256 `527999b4...ecafa`) and every test file are byte-identical to what the reviewer read; nothing the findings touch changed. What this commit adds on top of the reviewed tree, all records of the apply and none of it executable:
- the `backups/applied_migrations.json` entry for 158 (hash by `scripts/migration_ledger_hash.dart`, Gate 39 green), appended as text without re-dumping the file;
- plan section 6 (the apply record), closure ledger rows A1 (now `closed_in_commit`) and Q1 (founder accepted the default; now `closed_in_commit`), Q2 reworded (the founder answered yes; wording review and the Edge Function deploy go remain, tracked as OI-336);
- the OI-320 entry moved to `docs/audit/closed_issues.md` (`closes-oi: OI-320`), OI-336 records the founder's two yes answers, `OPEN_INDEX.md` regenerated.
Live facts behind the records (read-only, project `dedsavbjuwgarrhphgnl`): apply version `20261011182941`; the stored statement's sha256 equals the file's; function md5 `e69618b8bdabe6ef495a0a463efd51e0`, equal to a local apply of the same file; `proconfig` `{search_path=public}`, ACL `{postgres=X/postgres,service_role=X/postgres}`, SECURITY DEFINER, void; both foreign keys `confdeltype n`; both columns nullable; `lock_timeout` 0 on a fresh session; `oi320_referrer_cap_live_verify.sql` 28 of 28 `ok` with nothing persisted (3 rows, no NULL-party rows, no `AVYA-VERIFY` code, no new trial subscription). The old-body baseline (18 fail / 10 ok) was measured on the local replica, not live: the old body was never run against production.
