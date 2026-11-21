# OI-199 + OI-471 — `cron_call_log` retention: per-function keep-set, drop the orphan 7-day pruner

Tier: L (schema migration that replaces a live function and drops another); blast radius CATASTROPHIC BY CONTENT (R2-1:
`scripts/blast_radius_content_rules_lib.dart` escalates any migration whose text contains `SECURITY DEFINER`, comments included, and
the new file must restate it), so the merge needs `bpass: accepted` AND `hermes: accepted` with a Hermes report. Execution mode:
INLINE, one worktree. Branch `cron-log-retention-oi199-oi471`. Plan revision: v3 = v2 + review #2 (design and gates: one P0,
one P1, four P2, nits; applied as R2-1..R2-12, listed at the end); v2 = v1 + review #1 (ground truth: no P0, four P1, four P2,
nits; R1-1..R1-12). Two review rounds are done.
Lenses: L1 (writer/reader), L9 (cron), L31 (alert coverage).

Scope decisions (founder, 2026-11-06, "Ok" to the proposal):
- The batch is ONE migration (next free number is 172, minted at build start with `mint_migration.sh --stub`, not before the
  reviews converge) and tests/docs. **No Edge Function is deployed; the only Edge Function files touched are two comment-only edits in the `telegram-admin-bot` tree (R2-7; precedent: commit `0d16beb1` edited exactly these comments, +4 and +3 lines, with no redeploy).** Telegram is deferred, so the
  `telegram-admin-bot` `/cron` 7-day window that OI-199 also owns is split into its own new OI (`Blocked on:` the deferral,
  `reopen_when:` the admin bot is back in use) instead of being built here. OI-199 closes for its Fix shape and the R2-11
  precondition; the split OI carries the rest, so nothing is left as an intention (CLAUDE.md §4.2).
- OI-471 (drop the orphan `cron_call_log_cleanup_7d()`) rides in the same migration: it is the same table's other pruner and
  the same live checks. The DROP is `Destructive?: yes`: it needs its own explicit live go.

## Facts (verified 2026-11-06, live project `dedsavbjuwgarrhphgnl`, read-only)

- `public.cleanup_cron_call_log()` live = migration 169 body, byte for byte: `prosrc` md5 `0d14570d905770a34f9845683ca4aed4`,
  length 372, `SECURITY DEFINER`, `search_path=public`. 10-day cut; keep-set = the newest `success` row table-wide UNION the
  newest row of any status table-wide (TWO rows total). Definitions: 068, 109, 110, 169 (last wins; 069 only schedules the nightly job, R1-9). Only caller: cron job 41
  `db_maintenance_nightly` (`30 3 * * *`, its command starts `SELECT public.cleanup_cron_call_log();`).
- `public.cron_call_log_cleanup_7d()` live: `prosrc` md5 `853d4dc0ce64bb76c5c2e8a12f8b2099`, length 84, body
  `DELETE FROM public.cron_call_log WHERE started_at < now() - interval '7 days'`, `SECURITY DEFINER`,
  `search_path=public, extensions, vault, private`. References, all read live: `cron.job` commands naming either pruner = job 41
  only (and it names the OTHER function); `pg_proc.prosrc` naming it = none besides itself; `pg_trigger` on either = none;
  `pg_views` = none; `pg_depend` normal dependents of it = none. Repo: migrations 090:43 and 091:22 (REVOKE/ACL) and
  `test/contracts/security_definer_revoke_migration_test.dart` (reads those two FILES, unaffected by a later DROP). **No migration
  CREATEs the orphan** (verified: only 068/109/110/169 create `cleanup_cron_call_log`; 090 and 091 only REVOKE/ALTER/GRANT the
  orphan), so it was made out of band, a fresh replay of the migrations already breaks at 090, and OI-471's sentence "the pre-109
  pruner that `cleanup_cron_call_log` replaced" is unverified: the new migration's header will not repeat it. Live ACL of BOTH
  functions: `{postgres=X/postgres,service_role=X/postgres}`, owner `postgres`. Blind spot, stated: `track_functions = none`, so a
  caller over RPC with the service-role key cannot be ruled out from statistics; the repo has none (R1-9).
- Live `cron_call_log` differs from the 068 text in two ways that do not touch the DELETE: RLS enabled with no policies (the
  owner has BYPASSRLS, and the function is `SECURITY DEFINER`), and the partial index is `WHERE status <> 'success'`.
- `public.cron_call_log` (068:21-40): `id BIGSERIAL PK`, `function_name TEXT NOT NULL`, `started_at TIMESTAMPTZ NOT NULL`,
  `status TEXT NOT NULL DEFAULT 'started'` (`started|success|failed`), index `idx_cron_call_log_function_started
  (function_name, started_at DESC)`. Live: 17 distinct function names, every one with a success inside the last 4.6 days (oldest 4.59 d at 2026-11-06 04:40 UTC; all 598 rows are `status = 'success'`, none `failed` or `started`; R1-9)
  (weekly-recap-ready, Sunday cadence, is the oldest: 2026-11-01). Nothing is dead today.
- Readers of the table: `alert_cron_function_dead` (170: `status='success'`, `started_at > now() - interval '14 days'`, fires
  at `days_silent >= 8`, 72 h dedup); `alert_cron_silence` (109/110, total-fleet `MAX(started_at)` thresholds 2 h / 6 h);
  `ops_alerts_30min` (30 min / 1 h / 6 h lookbacks); `founder_metrics_ops()` (live body: a 24 h window counting `failed` rows and
  `started` rows older than 1 h; rows the keep-set adds are older than 10 days, so it cannot change that count);
  `telegram-admin-bot` `cmdCron` (`index.ts:570`, 7-day `.gte()`). No reader in `lib/`, no other Edge Function (grep). **Live
  catalog sweep for the TABLE name, 2026-11-06 (read-only):** `pg_proc.prosrc` (all non-system schemas) = `founder_metrics_ops()`
  plus the two pruners; `pg_views`, `pg_matviews`, `pg_rules`, `pg_policies` = none; `cron.job` commands = jobs 31
  `alert_cron_silence`, 32 `alert_cron_function_dead`, 41 `db_maintenance_nightly`, 43 `ops_alerts_30min`; non-internal triggers
  on the table = none. The pruner's text is read by `test/contracts/alert_threshold_below_retention_test.dart`
  via `test/helpers/cron_call_log_windows.dart` `readRetentionDays` (regex: `started_at < now() - interval 'N days'` inside the
  `$fn$` body of the LAST migration defining the function), and by `cron_vacuum_single_statement_test.dart` (job body of 144 only).
- `test/sql/cleanup_cron_call_log_retention_live_verify.sql` (169's pin) seeds the rows of BOTH scenarios under their OWN function
  names (A: `c9e2a7_1h`, `_9d`, `_11d`; B: `_s0`, `_s`, `_x`). Under a per-function keep-set each of those rows is the newest of
  its own function and survives, so `retention_11d_pruned` (A) AND `keep_set_older_success_pruned` (B) turn red (reviewer 1 ran
  Scenario A in a container: all three rows survive; R1-1). It must change in this batch (see Tests). Nothing executes it
  automatically; docs cite it.

## Fix

**1. `cleanup_cron_call_log()` gets a per-function keep-set (OI-199).** New migration, `CREATE OR REPLACE`, same retention
(10 days), same shape as 169, the keep-set widened:

```sql
CREATE OR REPLACE FUNCTION public.cleanup_cron_call_log()
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
  DELETE FROM public.cron_call_log
  WHERE started_at < now() - interval '10 days'
    AND id NOT IN (
      SELECT id FROM (
        (SELECT DISTINCT ON (function_name) id FROM public.cron_call_log
          WHERE status = 'success' ORDER BY function_name, started_at DESC, id DESC)
        UNION
        (SELECT DISTINCT ON (function_name) id FROM public.cron_call_log
          ORDER BY function_name, started_at DESC, id DESC)
      ) AS keep_rows
    );
$fn$;
```
plus the 169 grants restated (`REVOKE ALL ... FROM PUBLIC`, `FROM anon, authenticated`, `GRANT EXECUTE ... TO postgres`).

- **Every row the old keep-set kept survives (proof, tested; the B-pass corrected "strict superset", R1-3):** the global newest
  success is the newest success OF ITS OWN function, and the global newest row is the newest row of its own function, so a row of
  the same function, `started_at` and status is kept. Only on an exact `started_at` tie between two rows of ONE function can the
  kept id differ from the one 169 picked (169 broke such a tie arbitrarily). The 110 NULL-guard property (a table with no success
  row is never wiped; a fully dead fleet keeps its newest row for `alert_cron_silence`) is preserved for the same reason.
- **Why two arms:** the alert reads the newest SUCCESS per function; the newest row of ANY status per function keeps the
  evidence of a function that only ever fails or only logs `started` (no success row exists for it).
- **Why unbounded (no "newer than N days" cap on the keep-set):** a cap would let a fully dead fleet empty the table again
  after N days, re-opening the F5 wipe class (`docs/audit/2026-07-26-hermes-cron-secret-auth.md:81`), and needs a second
  tunable. Cost, stated: past the 10-day cut at most TWO rows per distinct `function_name`, forever, on top of every row younger than 10 days (17 names seen live and 19 literal `logCronStart` names in the code, so 34 to 38 old rows; Hermes C-3). A retired or
  renamed function leaves its two rows; the manual purge is `DELETE FROM public.cron_call_log WHERE function_name = '<name>'`.
- **Tie-break `id DESC` (R2-10; v1 and v2 had none, as 169):** both reviewers leaned to add it and it costs nothing. A tie between
  two rows of one function at the same microsecond could never lose the function, but a deterministic pick is easier to test and
  matches the sibling pruner `cleanup_cron_job_run_details` (live prosrc: `ORDER BY jobid, start_time DESC, runid DESC`). Reviewer 1
  ran the body WITHOUT it on 3000 fixtures; this version is re-proven by the harness (case F2, case H with ties, mutant M12).
- Not changed: the retention number (the contract test still reads 10 from the last definition), the alert bodies, the nightly
  job, the schedule, any Edge Function.

**2. Consequence for the live alert (behaviour change, no alert edit).** `alert_cron_function_dead` sees only rows younger than
its 14-day lookback. Until now a dead function's last success left the table at day 10, so the alert could see it on days 8 to 10
only: ONE page (72 h dedup exceeds that span). With the keep-set the last success stays, so the alert sees it on days 8 to 14:
the dedup expires 3 days (or 4, with start jitter) after the first page, so the SAME dead function pages a SECOND time at about
day 11 to 13, and never a third (a third run would sit at age 14 or more, outside the lookback). Beyond day 14 the alert is
silent by design (a function retired on purpose must not page forever); the row stays in the table for any reader. Migration 170's
header already lists this as a stated limit ("a keep-set row can keep one function visible past day 10"). The plan measures it
(Tests, case J) instead of leaving it as arithmetic, and the final report names it so the founder can veto.

**3. Drop the orphan pruner (OI-471).** Same migration, after the `CREATE OR REPLACE`:
`DROP FUNCTION IF EXISTS public.cron_call_log_cleanup_7d();` (no `CASCADE`, so an unseen dependent makes the migration fail
closed rather than drop it). Header `Destructive?: yes`. `Rollback strategy: inline`: a commented block re-creates it from the
live body and ACL in Facts (`search_path=public, extensions, vault, private`; EXECUTE for `postgres` and `service_role` only), with
the warning that doing so undoes the retention fix the moment anyone schedules it, and a second commented block restores the 169
two-row body. Both blocks are written as `--` lines: the test helpers strip only line comments, so a `/* */` block would be read
as live SQL (R1-9). Rollback block 1 is the 169 body byte for byte, line breaks included, so `md5(prosrc)` after a rollback equals
the 169 value `0d14570d905770a34f9845683ca4aed4`; a Dart test compares it with the 169 file (B-pass R1-4). Re-check immediately before the live apply (read-only): the reference queries above, plus
`md5(prosrc)` of BOTH functions still equal to the values in Facts (so the apply replaces and drops what this plan examined). Because `track_functions = none` hides an RPC caller of the orphan
(`service_role` can execute it; the repo has no caller), the recheck also reads `pg_stat_statements` and the project API logs for
`cron_call_log_cleanup_7d` / `rpc/cron_call_log_cleanup_7d` (R2-9); a hit stops the DROP and goes to the founder.

## Tests

All behavioural proof runs in a LOCAL docker Postgres (`public.ecr.aws/supabase/postgres:17.6.1.084`, `docker exec`, no host
psql, unique container name `oi199-pgtest`, removed in a trap), never against production (feedback: rehearse SQL in local docker).

1. **Harness `test/sql/cleanup_cron_call_log_per_function_local.sh`** (new; run it with `bash`, `/bin/sh` is dash and the script
   uses `pipefail`, B-pass R1-1). It creates the table and index from 068 by
   extracting them from `supabase/migrations/068_cron_call_log.sql` (not retyping them), creates the orphan function by hand
   from the LIVE body and ACL in Facts (no migration creates it), then applies the REAL migration files, not embedded copies, so
   there is no rehearsal-body-sync test to drift. **Every run starts from the same reset state (R1-6):** table emptied, orphan
   re-created, `cleanup_cron_call_log` reset by applying the 169 file; otherwise M9 (delete the DROP) would run against a state
   where the orphan is already gone and survive. Step 1 resets, applies the 169 file and runs the verify file (the OLD body: cases
   B, C, D, F2, H, H2's oracle label, I and J must go red; A, E, F, G, K and H2's fixture and 169-keep labels pass); step 2 resets, applies the new migration and runs it again (all green); step
   2b builds the LIVE APPLY REQUEST from the migration file (the wrapper of "Live apply" below) and runs it on the 169 state: it
   commits and leaves md5 `6597e3e2...`, the 169 ACL and no orphan; a wrong md5 aborts it and the CREATE and the DROP roll back
   together; an unseen catalog dependent of the orphan (a view) makes the DROP fail and rolls the CREATE back with it (Hermes A-1
   made testable instead of prose); step 3 runs the mutant table below, each on its own reset. Output: one summary line per run (`ALL OK (n checks)` / `FAILED: k of n`).
2. **Verify file `test/sql/cleanup_cron_call_log_per_function_verify.sql`** (new), `BEGIN ... ROLLBACK`, results in a temp table.
   Seeds are back-dated from `now()` (frozen in a transaction). Cases:
   - A retention boundary, ONE function name for every row (R1-1): rows at 1 h (newest, kept), 9 d (kept), exactly 10 d (kept:
     the cut is a strict `<`), 10 d 1 min, 11 d and 12 d `failed` (pruned: not the newest of anything).
   - B one dead function PLUS a healthy one (R1-2): dead function with success at 41 d, 40 d, 30 d (newest success) and failed at
     29 d (newest row); the healthy function has a success at 1 h. Exactly the 30 d success and the 29 d failed row survive. The
     healthy function is load-bearing: with a SINGLE function the 169 keep-set equals the per-function one and the case would pass
     under the old body (reviewer 1 measured it: `B_alone` green, `B_healthy` red). Only B-with-healthy, C, D, H and J
     discriminate the old body.
   - C TWO silent functions (newest successes 30 d and 25 d): each keeps its own; the old body keeps only the 25 d function's.
   - D a function with NO success ever (failed 20 d, started 19 d, failed 18 d) beside a healthy one: its newest row (18 d) survives.
   - E recent rows (all within 10 d, mixed status): none touched.
   - F empty table: no error. F2 tie (R2-10): two `success` rows of ONE function with the SAME `started_at` (30 d old, so older than
     the cut), and no newer row of that function, beside a healthy function: the pair is the function's newest success AND newest
     row, so exactly ONE of the two survives and it is the higher `id`. G idempotent: a second run deletes 0 rows.
   - H every row the 169 keep-set kept survives + exactness: a fixed mixed fixture (6 functions, about 40 rows, ages 0 to 60 d, generated deterministically; R1-7:
     the generator PINS statuses so status-filter mutants die: one function whose newest row is `started`, one whose newest row is
     `failed` with an older newest success, one with no success at all, and a few functions carry TIED
     `started_at` rows: the oracle orders by `started_at DESC, id DESC`, the same total order as the body, so a tie cannot
     produce a false red, R2-10);
     compute the OLD keep-set (the 169 formula, written exactly as in 169; this fixture has no global tie, so the ids agree)
     before the run; after the run assert OLD keep-set rows <= survivors, and survivors
     older than the cut are EXACTLY the per-function newest-success + newest-row ids as computed by an independent oracle
     (`row_number() OVER (PARTITION BY function_name ...)`, a different formulation from `DISTINCT ON`).
   - H2 a DEAD FLEET (Hermes D-5): in H the rows the 169 keep-set kept belong to a healthy function and are 0 to 1 days old, so
     retention keeps them whatever the keep-set does and `H_old_keep_set_is_subset_of_survivors` could never go red (observed: red
     in no run and no mutant). H2 has nothing younger than 11 d: three functions, the two rows 169 keeps (newest success 20 d, newest
     row 11 d failed) are OLD, the third function is one 169 would wipe. Labels: the fixture really has two old 169-keep rows; those
     rows survive; survivors are exactly the four oracle rows (green under 169 for the first two, red for the oracle label).
   - I the drop: `to_regprocedure('public.cron_call_log_cleanup_7d()') IS NULL` after the migration; applying the migration a
     second time raises no error (`IF EXISTS`).
   - K the security envelope (B-pass R1-2 / R2-3; the plan had no check of it): `prosecdef` true, `proconfig` exactly
     `{search_path=public}`, no PUBLIC entry in `proacl` and a non-default ACL, `has_function_privilege` false for `anon` and
     `authenticated`, and an explicit `postgres` EXECUTE entry in the ACL (`has_function_privilege('postgres', ...)` is true for a superuser
     whatever the ACL says, a vacuous check, Hermes D-6). `CREATE OR REPLACE` keeps the old ACL but resets the security mode and `proconfig`, so a
     dropped attribute shows only here. The harness also compares `proacl::text` after 169 with the value after 172 (identical).
   - The file's first statement is a local-only guard that RAISEs unless the scaffold's `public._alert_cmd` exists (B-pass R1-5):
     it empties `cron_call_log` and deletes `alerts`, and a first production rehearsal of OI-473 hung for over an hour. The harness
     PROVES the guard fires (Hermes D-7): it renames `_alert_cmd`, runs the file, expects a non-zero exit and the guard's message,
     renames it back; a text grep alone stays green when the guard is neutered to `IF false`.
   - J alert interplay (R1-3, one scenario asserting the NEW behaviour; there is no separate J1, because a verify file cannot
     test "under 169" without an embedded copy of the 169 body, and the harness's step 1 already runs this same file against the
     real 169 migration, where J reddens). Simulated nightly for 9 loops: shift every `started_at` and `alerts.detected_at` back
     one day per loop, run the pruner, then the 170 command extracted from the migration file between its `$$` tags. A dead
     function with its last success at age 7.6 d, PLUS a healthy function re-seeded with a fresh success EVERY loop (R1-3b:
     without a fresher success the dead function is the global newest success and even the 169 body keeps it; a healthy row
     seeded once would itself become 8 days old and page). Pages are counted PER FUNCTION NAME from `context_json ->> 'function_name'`
     (R1-3c), not by `id > max_id_before`. Two variants: exact (`detected_at` shifted back by `interval '1 day'`) and jitter
     (shifted back by `interval '1 day' - interval '1 minute'`, i.e. LESS than a day, which keeps the dedup holding one loop longer;
     R1-5: a "+1 minute" shift gives the same loops as the exact one). Assert for the new body: exact = pages at loops 1 and 4
     (ages 8.6 and 11.6 d), jitter = pages at loops 1 and 5 (8.6 and 12.6 d), total 2 in both, never 3. J3: a function whose last
     success is already 15 d old pages ZERO times and its row is still in the table. Under the 169 body (step 1, reviewer 1
     measured it) the first function pages once (loop 1) and the 15 d row is pruned; the diagnose doc records those numbers.
     The exact-variant second page rests on the strict tie `detected_at = now() - 72 h` (`>` is false), which matches the live job
     text; the jitter variant shows the other side of the knife edge.
   The container has minimal `alerts` (no trigger, nothing in the cases needs one) and `cron_call_log` tables (from 076/068).
3. **Mutants (harness step 3, on a scratch copy of the new migration, each confirmed applied with `grep -c` / `cmp`, each run
   against the verify file, red-case count recorded in the diagnose doc):** M1 drop `WHERE status = 'success'` in arm 1; M2 drop
   arm 2; M3 remove `DISTINCT ON (function_name)` from both arms (keeps every row); M3b make both arms global (`ORDER BY
   started_at DESC LIMIT 1`, the 169 shape); M4 `started_at DESC` -> `ASC`; M5 `UNION` -> `INTERSECT`; M6 `'10 days'` -> `'7 days'`;
   M7 `NOT IN` -> `IN`; M8 delete the `started_at < now() - ...` guard; M9 delete the `DROP FUNCTION` line (needs the per-run reset
   above, R1-6); M10 arm 2 gets `WHERE status <> 'started'` (dies only because H pins a function whose newest row is `started`,
   R1-7); M11 `<` -> `<=` at the cut (killed by the exact-boundary row in case A: under a frozen `now()` a row at exactly
   `now() - interval '10 days'` CAN be seeded; calling this mutant "equivalent", as reviewer 1's reconstruction did, was only
   true because that reconstruction had no boundary row). M12 remove `, id DESC` from both arms (killed by F2 only if the planner's tie pick is the lower id; if it does not
   redden here it is reported as surviving and planner-dependent, never as coverage). Equivalent by construction and stays so: `UNION ALL` for `UNION`
   (the `NOT IN` set is identical; the Dart fixture W2 still rejects the text). M13 `GRANT ... TO postgres, anon`; M14 `SECURITY
   DEFINER` -> `SECURITY INVOKER`; M15 delete the `SET search_path` line: each is killed by exactly its own K label (B-pass R1-2). M16 `TO postgres, PUBLIC`, M17 `TO postgres, authenticated`, M18 replace the
   GRANT by `REVOKE EXECUTE ... FROM postgres` (Hermes D-6: three of the six K labels had no mutant that reddened them).
   Deleting a REVOKE line is equivalent INSIDE the harness (172 is applied on top of 169's ACL), so the REVOKE and GRANT text is
   pinned by the Dart fixtures A3 to A5 instead. A mutant that reddens nothing is reported as such, never as coverage.
4. **Contract test `test/contracts/cleanup_cron_call_log_per_function_keep_test.dart`** (new, presence + shape, no database; 65
   tests). It is a SOURCE-SHAPE pin and says so: the behaviour is proved by the harness, which no CI gate runs. The LAST migration
   defining the function (via `latestMigrationDefining`) has retention 10 (`readRetentionDays`, which reads the LAST definition);
   inside the BALANCED `AND id NOT IN (` list there are exactly two arms, each `SELECT DISTINCT ON (function_name) id FROM
   public.cron_call_log` ordered `function_name, started_at DESC, id DESC`, exactly one with the case-exact `WHERE status =
   'success'`, and once the two arms are removed only `SELECT id FROM ( UNION ) AS keep_rows` remains (a third arm, `UNION ALL` or
   a whole-table SELECT fails; B-pass R2-1). **`bodyDriftProblems` (Hermes D-1):** the list check was blind to everything around
   the list (`... ) OR started_at < now() - interval '30 days'`, a second DELETE, another DELETE target), so the WHOLE function text,
   whitespace-collapsed and comment-free, must equal migration 172's; a deliberate change has to edit this pin on purpose.
   **`attributeProblems` (rewritten, Hermes D-2 and D-8):** pins SECURITY DEFINER, a `SET search_path` list that is exactly `public`
   (order-insensitive against other SET clauses), and reads EVERY GRANT/REVOKE statement whatever the spelling of the name
   (qualified or not, quoted, spaces in the parentheses): the union of revoked roles must include PUBLIC, anon and authenticated,
   the only grantee is postgres, postgres is never revoked, and an `ON ALL FUNCTIONS IN SCHEMA` GRANT/REVOKE is refused. One
   combined REVOKE statement, a reordered SET clause and an extra SET clause are ACCEPTED (fixtures P1, P2). **The newer-migration
   tripwire is DDL-only (Hermes D-3):** `functionDdlMentions` flags a later migration only for CREATE/ALTER/DROP/COMMENT ON FUNCTION,
   GRANT/REVOKE ON FUNCTION, or a schema-wide GRANT/REVOKE; a later `SELECT public.cleanup_cron_call_log();` (job 41's command, in
   141 and 144) is not DDL and does not flag. Seven pure fixtures. `dropFormProblems`: `DROP FUNCTION IF EXISTS
   public.cron_call_log_cleanup_7d()` with no `CASCADE`, in exactly one migration; no OTHER migration at or after it (a suffixed
   sibling counts) mentions the orphan outside comments. `rollbackProblems`: rollback block 1, with its `-- ` prefix removed, equals
   the 169 function, BODY byte for byte (R1-4) and HEADER (name, language, security mode, search_path) whitespace-insensitively
   (Hermes D-4). Further: md5 and byte length of the raw `$fn$` text equal `6597e3e24f91126b6268b3d54aa7ea57` and 460 and the same
   literals appear in the harness, this plan and the migration's post-apply block; the harness orphan function equals rollback
   block 2 (Hermes: one live read, two copies); the harness reads the migration FILES (no embedded body, checked whitespace-
   insensitively), is documented as `bash`, runs M1 to M18 and the scaffold-refusal step; the verify file carries every case label
   incl. H2 and K and the local-only guard. The checkers are fed 40 fixtures (37 must be rejected, 3 must be accepted), FROZEN on
   migration 172's own text so a legitimate 173 cannot turn them into "anchor not found" (R2-6): M1, M2, M3, M3b (the 169 shape),
   M4, M5, M6, M7, M8, M10, M11, M12; W1 to W5 (too wide); B1 to B3 the text around the list, B4 comment/whitespace-only (accepted);
   A1 to A10 the envelope and grants; P1, P2 (accepted); R1 to R4 the rollback; D1 to D3 the DROP. Each rejection asserts the
   SPECIFIC problem text it must raise (`anyElement(contains(...))`, Hermes D-10), so a fixture cannot go red for an unrelated reason.
   Neutering the checkers in a scratch copy must redden exactly the rejection fixtures (§4.4 r21; the run is recorded in the
   diagnose doc).
5. **`test/sql/cleanup_cron_call_log_retention_live_verify.sql` updated (R1-1)** so BOTH scenarios use ONE function name per
   scenario: Scenario A puts the 1 h, 9 d and 11 d rows under one name (11 d is then pruned, 9 d survives), Scenario B puts the
   31 d and 30 d successes under one name (`keep_set_older_success_pruned` then means "an older success OF THE SAME FUNCTION is
   pruned") and keeps the `failed` row under its own. Its header, which still says "always sparing the newest SUCCESS row and
   the newest row of ANY status", is corrected to "per function". It stays a valid pin for the new body; the harness also runs
   this file against the new body in the container.
6. Existing tests that must stay green: `alert_threshold_below_retention_test.dart` (the tripwire list does not need the new file:
   it matches migrations with BOTH `FROM public.cron_call_log` and `INTO public.alerts`; the new one has no `alerts` insert),
   `cron_vacuum_single_statement_test.dart`, `cron_call_log_writers_roster_test.dart`, `applied_migrations_parity_test.dart`
   (the ledger entry rides in the apply commit).
7. Migration immutability: the new file is hashed with `scripts/migration_ledger_hash.dart <NNN>`; the harness copies the file to
   a scratch path before mutating and the mutants never touch the tracked file.

## Docs and board

Files the real commit touches: the migration; `backups/applied_migrations.json` (same commit as the apply); the contract test;
the harness and verify SQL; `docs/plan-reviews/cron-log-retention-oi199-oi471.md` (one path per cited file, each with a bare
`verdict: accepted` line) the B-pass file `docs/reviews/<staging-hash>-review.md` with its `## Tuning entry`; the Hermes report
`docs/audit/2026-11-0X-hermes-cron-log-retention-oi199-oi471.md` (the record's `hermes_report:`, a line-anchored `verdict: accepted`;
R2-1); the two comment-only `telegram-admin-bot` edits named below; the diagnose doc
(`closes-diagnose:`, full template, recurrence: OI-179 c9e2a7 / OI-473 f7b3d1 are the same table and the same alert); the board
(`open_issues.md` and `closed_issues.md`, append only): OI-199 and OI-471 closed with `closes-oi:` trailers, one NEW OI minted with
`scripts/mint_oi.sh` for the `/cron` window (`telegram-admin-bot/index.ts` `cmdCron`, `sevenDaysAgoIso`; the `cmdCron queries a 7-day time window` test in `index_test.ts`;
`deno check`, a redeploy with its own go). **The new OI states the RESIDUAL (R2-6), not just the window:** evidence is kept
forever but no reader looks beyond 14 d (the alert) or 7 d (`/cron`), so a function silent for more than 14 days is still
invisible to every reader. Its Done-when is a reader that lists the functions whose newest success is older than 14 days,
filtered against the CRON_REGISTRY roster (a retired function leaves two rows forever, so the reader must not treat those as
dead), plus the `/cron` window change and the wording refresh of job 32's own message text (below). It quotes the founder's
answer verbatim ("Ok", to the 2026-11-06 proposal "I'd do only the migration and leave out the Telegram `/cron` window change,
since Telegram is deferred"), and so does the diagnose doc.
**Four comment-only edits ARE made in this batch (R2-7, Hermes B-3 and B-5)**, because they would otherwise stay as false code
comments citing a closed OI: `telegram-admin-bot/index.ts` (the `cmdCron` comment block that says "110 spares TWO rows globally ...
beyond 10 days the purge still does (OI-199)"), `telegram-admin-bot/index_test.ts` (the same claim in the `cmdCron` window test),
`founder-digest/index.ts` (header: "`alert_cron_function_dead` cannot fire at all", false since 169) and `_shared/cron_telemetry.ts`
(header: "Retention: 10 days", now plus each function's newest success and newest row). The comments name
migration 172 without a date, because the date of the apply is not known when they are written (B-pass R2-8). Comment text only, no behaviour
and no redeploy (precedent `0d16beb1`; no gate compares deployed bytes), `deno check --node-modules-dir=none` on `telegram-admin-bot`, `founder-digest` and every function importing `cron_telemetry.ts`
that the batch's tests read, before the commit, and the Deno test file of `telegram-admin-bot` still passes.
**Job 32's own message text becomes inexact (R2-5) and is NOT changed here:** the singles message ends "If the function was retired
on purpose this is the one alert; it stops once its rows leave cron_call_log" (rows no longer leave; there can be two pages; it stops
paging at the 14-day lookback), and the summary says "newly detected, not already alerted" (inexact on a repeat). Fixing the
strings means a new `cron.alter_job` (another migration, another Hermes pass, and churn in the 170 rehearsal-sync contract test
that pins the body); the founder is told in the live-apply ask and may ask for it. Until then it is recorded in the diagnose doc,
in CRON_REGISTRY row 45, and in the new OI (its Done-when above), so it is tracked, not implicit.
NOT needed: any Edge Function DEPLOY (the four edits above are comment text),
`docs/sot_registry.yaml`, `backups/live_cron_jobs.json` (no job changes), `live_schema_columns.json` (no column changes),
`docs/naming_conventions.md` (no new domain term; "keep-set" is the existing wording of 169 and 110, checked).
Gate 40 (closure ledger): three batch units (OI-199 closed, OI-471 closed, the new `/cron` OI-478 filed) is below the four-unit
threshold of CLAUDE.md §4.2, so the batch keeps per-fix diagnose docs and no `docs/audit/<batch>.closure.yaml`. **OI-480** (the
cost of the complete local gate loop; the founder asked for it on 2026-11-06 while this batch's loop was running) rides on this
PR's board diff but fixes nothing here, so it is NOT a unit of this batch and the commit message says so (B-pass R2-2). The two
edits to the sibling comments ("lookback is only a cap" in `test/helpers/cron_call_log_windows.dart` and
`alert_threshold_below_retention_test.dart`) are part of the doc-claim sweep below. The gate loop also runs `check_context_artifact_budget.dart` (a new tracked plan, diagnose and review file
can shift the budget; re-baseline with `--record` only if the drift is intended).

Doc-claim sweep (one edit, grepped): `docs/operations/CRON_REGISTRY.md` row 45 ("silence beyond 10 days is invisible again until
OI-199's per-function keep-set": now done; say the alert can see a dead function through day 14 and pages about twice) and row 80
("always sparing the newest success row and the newest row of any status": now per function); the "up to three alerts" and "pages
only while 8-10 days" wording stays as history in 169's immutable header and the c9e2a7 / f7b3d1 / Hermes records, which the new
diagnose doc names as superseded (c9e2a7 lines 66-70, f7b3d1 lines 43-45, the Hermes record and plan of OI-179, the 169 and 170
headers). The B-pass found more of the same class and the same edit fixed them: row 45's "the 14-day lookback is now only a cap"
(the lookback is now the binding bound), the same phrase in `test/helpers/cron_call_log_windows.dart` and
`alert_threshold_below_retention_test.dart`, and the stale `s0` and header prose of the 169-era pin test.

## Order of work (R1-4)

A new `NNN_*.sql` with no ledger entry reddens Gate 14 (`scripts/check_migrations_applied.dart`), `applied_migrations_parity_test.dart`
and, at commit time, `check_migration_ledger_paired.dart`; a ledger entry for an unapplied migration would be a false record. So
the sequence is (migration 169, the same tier, followed it): (1) plan converged (this document after review #2); (2) mint the number with
`mint_migration.sh --stub`, build the migration, verify SQL, harness, contract test, SQL pin update and docs; (3) harness
red/green/mutants recorded; (4) the COMPLETE local gate loop (`flutter analyze --no-fatal-infos`, `TZ=Asia/Kolkata flutter test`,
`sh scripts/pre-commit.sh` on the staged tree) run BEFORE the B-pass, which must show EXACTLY these expected reds and no others (R2-3; v2 said "one", which was wrong): Gate 14
(`check_migrations_applied.dart`), `applied_migrations_parity_test.dart`, `check_migration_ledger_paired.dart` (at commit time),
and `check_code_review_pass_exists.dart` (it is not on the `pre-commit.sh` skip list and demands a STAGED
`docs/reviews/<hash>-review.md` at catastrophic); the first three clear with the ledger entry in step 8, the fourth with the B-pass
file in step 5. Every other gate and test is green, EXCEPT three reds that belong to this VPS and not to the diff, which the run
must name (OI-480): two `golden`-tagged `WardRankPill` pixel diffs (CI passes `--exclude-tags golden`, so the local loop does
too) and the load-sensitive `test/scripts/land_pr_e2e_test.dart` hung-gh cases (a 400 ms deadline against a forking `sh` stub at
load 14; CI is the clean control). The loop is reported with that list, not trimmed to a subset (§4.12.8), and is
re-run COMPLETE in step 9, green apart from those environment reds (measured: 2 h 22 min under load 14 to 17 with three other
sessions running their own suites); (5) B-pass on the staged, UNCOMMITTED diff, then the Hermes pass (Sonnet
agents: the founder rule is Sonnet for review and never Opus, which overrides the hermes-pass skill's Opus default) because the tier
is catastrophic (R2-1); there is no deadline for the apply (the first night that deletes 10-day-old rows is about 2026-11-08 to
11-09, and no function's newest success is older than 4.6 days), so the extra pass costs nothing; (6) ask the founder for the
live-apply go, naming BOTH the function replacement and the DROP, with the B-pass and Hermes verdicts, the two-pages behaviour
change, the unchanged alert text (R2-5) AND that the SECOND page will carry text that is wrong ("it stops once its rows leave
cron_call_log"; OI-478 part 2, Hermes B-2), the RLS precondition as read live (Hermes C-1), the statement that the local docker
rehearsal stands in for the Supabase-branch dry run that `supabase/migrations/CLAUDE.md` asks of a `Destructive?: yes` migration
(R2-9), that OI-480 and OI-481 ride on the PR without being units of the batch, and that commit, push, merge (`land_pr.sh`) and any
rollback are SEPARATE gos (Hermes A-10); (7) apply, post-checks;
(8) ledger entry appended as text (hash via `scripts/migration_ledger_hash.dart <NNN>`), board closure, diagnose "Apply state"
section, and, because those files change the staging hash, recompute it and rename the B-pass file plus its citations as in
OI-473; (9) the complete gate loop again, now all green; (10) TWO commits in ONE PR (R2-2; "ONE commit" in v2 was impossible): commit 1 = migration, ledger, board,
diagnose, tests, docs, the two Edge Function comments and the B-pass file; commit 2 = the plan-review record and the Hermes report.
The record cites the B-pass by hash and the hash covers every staged path except `docs/reviews/`
(`check_code_review_pass_exists.dart`), so a record staged with commit 1 would move the hash it cites; migrations 169 and 170 both
split this way. Then ONE `sh scripts/land_pr.sh <pr>`, which replays the record gate at the merge revision. Applier: `execute_sql` ONLY, ONE request,
statements only (Live apply below; Hermes A-1 and A-2: `.claude/apply_migration_via_api.js` posts the raw file with no BEGIN and
no timeouts, and the 7,456 B file is far above the size at which a 7 KB DDL block failed on 2026-10-24).

## Live apply

Separate explicit go from the founder (CLAUDE.md §4.3), for BOTH the replacement and the DROP; commit, push, merge and any
rollback are further, separate gos (Hermes A-10).

**Route (Hermes A-1, A-2, A-3, A-4).** `execute_sql` only, ONE request, never split: a failed DROP then rolls the CREATE back with
it, which a retry in pieces would not. `.claude/apply_migration_via_api.js` is NOT used (it posts the raw file with no BEGIN and
none of the timeouts). The request carries the statements only (lines CREATE to DROP of the file, about 880 B; the whole 7,456 B
file is above the size at which a 7 KB DDL block failed on 2026-10-24 with "Invalid or expired requestState" and nothing ran) and
they are a byte copy of those lines (checked with `diff` before sending); the file stays the record:

```
BEGIN;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '60s';
<CREATE OR REPLACE FUNCTION public.cleanup_cron_call_log() ... $fn$;  REVOKE; REVOKE; GRANT;  DROP FUNCTION IF EXISTS ...;>
DO $a$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = 'public.cleanup_cron_call_log()'::regprocedure
                   AND md5(prosrc) = '6597e3e24f91126b6268b3d54aa7ea57' AND length(prosrc) = 460)
     OR to_regprocedure('public.cron_call_log_cleanup_7d()') IS NOT NULL THEN
    RAISE EXCEPTION 'migration 172 post-condition failed';
  END IF;
END $a$;
COMMIT;
```

`SET LOCAL`, not `SET` (a plain `SET` outlives the transaction on a pooled connection). The assertion inside the transaction means a
body that is not byte-identical to the file rolls the whole request back; a mismatch found only after the commit is repaired by
re-running the statements (idempotent). Any time outside 03:25 to 03:35 UTC (a harmless caution: seat A found that `CREATE OR
REPLACE` takes only a RowExclusive lock on `pg_proc`, nothing calls the orphan, and a concurrent run of job 41 neither blocks nor is
blocked).

**Pre-apply recheck (read-only; every result goes into the diagnose doc).** The Facts queries; `md5(prosrc)` and length of BOTH
functions equal the Facts values (169: `0d14570d905770a34f9845683ca4aed4`, 372 B; orphan: `853d4dc0ce64bb76c5c2e8a12f8b2099`, 84 B),
so the apply replaces and drops what this plan examined; `proacl` of both functions; for the orphan `pg_get_functiondef`,
`provolatile`/`procost`/`proparallel`, its `pg_description` comment and the overload count of `proname` (attributes the rollback
block cannot restore, Hermes A-5); `relrowsecurity`, the policy count and the `anon`/`authenticated` table privileges of
`cron_call_log` (expect true, 0; the precondition of the per-name bound, Hermes C-1, OI-184); `count(*)`, `count(distinct
function_name)`, `min(started_at)` and `count(*) WHERE started_at < now() - interval '7 days'` (snapshots, Hermes A-6 and A-7: rows
older than 7 days still present prove the orphan has not run since they crossed 7 days, a stronger signal than the logs); the
`pg_depend` dependents of the orphan; `cron.job.command` and `pg_proc.prosrc` text search for `cron_call_log_cleanup_7d` (a text
reference creates no dependency, so the DROP's fail-closed behaviour covers catalog dependents only, Hermes C-2); `pg_stat_statements`
and the project API logs for `cron_call_log_cleanup_7d` / `rpc/cron_call_log_cleanup_7d` (the API logs cover about a day, so a weekly
external caller such as the OpenClaw bot would not show: stated, not hidden); job 41's command unchanged. A hit stops the DROP and
goes to the founder.

**Post-apply (read-only):** `md5(prosrc)` and `length(prosrc)` of `cleanup_cron_call_log` equal `6597e3e24f91126b6268b3d54aa7ea57`
and 460; `to_regprocedure('public.cron_call_log_cleanup_7d()')` is null; `proacl` IDENTICAL to the recorded pre-apply value
`{postgres=X/postgres,service_role=X/postgres}` and `has_function_privilege` for `anon` and `authenticated` false (the platform
default grants live in no migration, so only the live check sees them; the 169 `GRANT ... TO postgres` restated in the new file does
not touch the `service_role` entry); `prosecdef` true and `proconfig` `{search_path=public}`; `relrowsecurity` and the policy count
unchanged; `count(*)` not below the pre-apply snapshot minus nothing (the migration deletes no row, so the count can only have grown
by the writers' own inserts) and `min(started_at)` unchanged; job 41 command unchanged.

**Part of the live behaviour IS observable (R2-4):** a runtime error in the new body would roll back ALL FOUR cleanups of job 41
(`cleanup_cron_call_log`, `cleanup_usage_counters`, `cleanup_cron_job_run_details`, `cleanup_client_errors`; one implicit
transaction, `cron.use_background_workers=off`, measured in docker) and would page through job 46 `alert_sql_job_failures`.
`check_function_bodies` is on live and the body has no cast or division, so only a data or timeout error could escape CREATE time,
and live runs of job 41 take about 0.8 s, so the follow-ups (read-only, written into the diagnose doc as they happen) are: the
first 03:30 UTC run after the apply shows job 41 `succeeded`; on the first nights that delete rows older than 10 days `min(started_at)`
of each frequent function moved forward and each function's newest row survived (the first night with a deletion is about
2026-11-08 to 11-09; the first run after the apply deletes nothing under either body). The keep-set ITSELF is NOT observable until
a function goes quiet for more than 10 days (every row older than 10 days is already pruned and all 17 functions are young), so
the diagnose doc says "keep-set not yet observed live" and rests on the md5 equality plus the local rehearsal. It also names the
OI-194 interplay (R2-8): `weekly-recap-ready` fires at 14:30 UTC on Sundays beside `streak-guardian` and `protein-gap-alert`, the
burst shape of OI-194 (OPEN); a lost Sunday log row already gives a false critical at day 8, and the keep-set repeats it at day 11
to 13.

**Emergency path (Hermes A-8).** If the first 03:30 UTC run after the apply fails, job 41 rolls back all four cleanups every night
until a fix lands. Then rollback block 1 goes through `execute_sql` in ONE request with the founder's go (a full forward migration is
an L-tier batch of its own), and a record-only forward migration follows. Block 1 returns to the 169 keep-set, so the next 03:30
run prunes the old rows this migration retained; the block's own header says so. A rollback migration PR must also change
`cleanup_cron_call_log_per_function_keep_test.dart`, which pins the latest definition. Otherwise rollback = the commented blocks
in the migration applied as a NEW forward migration; prefer a forward fix.

## Review #1 applied (v2)

Reviewer 1 re-ran the SQL on PG 17.6 in a scratch container (3000 random fixtures, 0 violations of "old keep-set is a subset of
the new survivors" and of "survivors older than the cut are exactly the per-function newest-success and newest-row ids"), confirmed
the parenthesised `DISTINCT ON` arms inside `UNION`, `id` is `bigint NOT NULL` live (no `NOT IN` null trap), and measured the
two-page consequence. Applied: R1-1 old verify file Scenario A also breaks (both scenarios fixed); R1-2 case B needs a healthy
function; R1-3 case J rewritten as one new-behaviour scenario, healthy row re-seeded per loop, pages counted per function;
R1-4 order of work and the single expected red; R1-5 jitter variant wording (`1 day - 1 minute`); R1-6 per-run reset (M9);
R1-7 H fixture pins statuses and unique timestamps, M10; R1-8 M3b explicit in the contract test and both stale `/cron` comments
named in the new OI; R1-9 nits (069 only schedules, 4.6 days not 5.2, orphan made out of band, `--` rollback lines, ACL);
R1-10 `proacl` identical before and after; R1-11 M11 (`<=`, killed by the exact-boundary row, which also corrects the
reviewer's "equivalent" label); R1-12 Gate 40 count and the budget gate named. Kept as written, with reviewer 1's agreement:
no tie-break (0 of 300 same-microsecond fixtures lost a 169 keep id), unbounded keep-set (at most 2 rows per literal
`logCronStart` name, 19 call sites), the alert untouched (moving its dedup to about 7 days means a new `cron.alter_job`
migration and an update to the 170 rehearsal-sync contract test: a larger blast radius).

## Review #2 applied (v3)

Reviewer 2 (design and gates, read-only live checks plus a docker measurement) found no design defect in the SQL or the keep-set,
and: **R2-1 (P0)** the batch is catastrophic by content, so a Hermes pass and `hermes: accepted` are required (header, order of
work, files list); **R2-2 (P1)** the plan-review record and the B-pass hash are circular, so two commits in one PR; **R2-3 (P2)** the
expected-red list named; **R2-4 (P2)** job 41 is one transaction of four cleanups, so the post-apply checks are written down;
**R2-5 (P2)** job 32's message text becomes inexact, recorded and tracked, not changed; **R2-6 (P2)** the new OI states the residual
and a Done-when, and quotes the founder's "Ok"; **R2-7 (P2)** the two stale Telegram comments are edited in this batch, comment
only, `deno check`, no redeploy; **R2-8** OI-194 named in the diagnose doc; **R2-9** `pg_stat_statements` and API-log reads for the
orphan caller, the dry-run substitute stated in the ask; **R2-10** the `id DESC` tie-break added (case F2, H with ties, M12);
**R2-11** answers below; **R2-12** the second-page wording in the alert message folded into R2-5. Confirmed live by reviewer 2: job
41 text and nightly timing, ten sampled nights all `succeeded` in about 0.8 s, both functions' md5 and ACL, table 599 rows / 17
names / all `success`, job 32 text (the `NOT IN` exclusion satisfies OI-199's R2-11 precondition; it has never inserted a row).
Answers to the five questions: (1) two pages with the alert untouched: yes (the second page falls at +3 or +4 days, a third is
impossible, no consumer mishandles a second critical: dedup is per function name, the digest lists by `detected_at`, the
dashboard lists open rows, `alert-critical-notify` fires per row); (2) B-pass-first order accepted, with the Hermes pass before the
ask and the two-commit split; (3) the `/cron` split is a legitimate founder-agreed scope call tied to an external condition
(Telegram deferred, OI-201 precedent) with a `reopen_when`, not a deferral to a later batch, and the gates accept closing two OIs
plus filing one (`check_closes_oi_performed` reads both boards); (4) unbounded, at most two rows per name: right (the sibling
`cleanup_cron_job_run_details` is already an unbounded per-key keep-set with 19 tombstone rows live; a capped version needs a second
interval that `readRetentionDays` cannot read and reopens the F5 wipe); (5) the likely merge failures were the Hermes gap, the
record/hash circularity and the red list, all now in the plan. Unit size: do NOT split (the DROP fails closed in one transaction;
splitting leaves the heavy SECURITY DEFINER half needing Hermes anyway and only adds a second go).

## B-pass applied (v4)

Two fresh Sonnet reviewers (R1 the SQL and harness, R2 the Dart gate test, docs, board and Edge Function comments) found no P0 and
no P1. Applied: **R1-1** the harness is run with `bash`; **R1-2 = R2-3** the security envelope and grants were pinned by nothing:
case K, the `proacl` equality, mutants M13 to M15, Dart `attributeProblems` and fixtures A1 to A6; **R1-3** "strict superset"
reworded everywhere, `_old_keep` written exactly as 169; **R1-4** rollback block 1 byte for byte, with a Dart test; **R1-5** the
local-only guard in the verify file; **R1-6** the "trigger 133 stand-in" sentence removed; **R1-7** M12's planner dependence stated
where it is reported, the tie-break text pinned by a Dart fixture; **R2-1** the Dart keep-set check was only half a check (nothing
rejected a keep-set that is too wide): it now reads the balanced `NOT IN` list and requires only the skeleton around the two arms,
fixtures W1 to W5 (a third arm, `UNION ALL`, a whole-table SELECT, both arms on success, `'SUCCESS'`); **R2-2** OI-480 named and
excluded from the unit count; **R2-4** the case-exact `'success'` literal; **R2-5** the last definition in a file is read, and no
migration newer than the resolved one may mention the function; **R2-6** fixtures frozen on 172, the drop tests fixtured (D1 to
D3), the embedded-copy check whitespace-insensitive; **R2-7** four pieces of stale prose fixed (the 169-era pin test header and
`s0` comment, row 45, the diagnose line number 563); **R2-8** the comments carry no apply date, and the commit message states that
the apply is a precondition of the docs; **R2-9** the plan's test list, fixture list, "fully green" claim, the superseded-wording
list, the M12 caveat and tier 6 (`not_applicable`: no deploy, no deployed-version read) now match the files. Live-state claims
neither reviewer could check (live md5s, ACLs, row counts, the job texts, the Postgres major version) stay with the pre-apply
recheck above.

## Hermes applied (v5)

Four Sonnet seats (A runbook and reversibility, B readers and behaviour change, C security and abuse of the definer function, D the
remediation code), read-only, no P0 and no P1. Every finding was checked against the file or the container before it was applied.
**Seat A:** A-1 and A-2 one `execute_sql` request, statements only, never the script route; A-3 `SET LOCAL`; A-4 the md5 and length
written down (`6597e3e24f91126b6268b3d54aa7ea57`, 460) and asserted inside the transaction, pinned by a Dart test and a harness
expectation; A-5 orphan attributes captured before the DROP; A-6 and A-7 row-count and `min(started_at)` snapshots and the age-7
count; A-8 the emergency path (migration header and above); A-9 diagnose line numbers recomputed; A-10 the separate gos. **Seat B:**
B-1 CRON_REGISTRY row 52 reworded; B-2 the second page carries wrong text, now said in the ask; B-3 the `founder-digest` header
comment; B-4 the "No reader looks beyond..." sentence no longer contradicts the alert_cron_silence line (STATED LIMITS); B-5 the
`cron_telemetry.ts` header; B-6 line numbers, "day 11 to 13", the comments no longer say when 172 was applied. **Seat C:** C-1 the
per-name bound rests on live RLS with zero policies (migration 068 says RLS stays disabled; OI-184 is open): stated in the COST
paragraph, read before and after the apply; C-2 "fail closed" now says catalog dependents only; C-3 "34 rows" replaced by "at most
two per name past the cut, plus the last 10 days"; C-4 `error_summary` is not sanitised at the sink: a habit, not a defect of this
change, filed as OI-481 (not a unit of this batch); C-5 the orphan's wide `search_path` noted in rollback block 2. **Seat D:**
D-1 the list check was blind to the text around the list: `bodyDriftProblems` pins the whole function text; D-2 and D-8 the
GRANT/REVOKE reader missed other spellings of the name and false-red on benign edits: rewritten, fixtures A7 to A10, P1, P2; D-3 the
newer-migration tripwire false-red on a plain call: DDL-only, seven fixtures; D-4 the rollback header was never compared; D-5 the
"169 keep rows survive" half of case H was vacuous: case H2; D-6 three K labels had no mutant: M16 to M18 and an ACL-based postgres
label; D-7 the local-only guard was never proved to fire: a harness step; D-9 `readRetentionDays` reads the last definition (done in
the B-pass round); D-10 M1 to M12 assert specific messages. Seat D also asked for the expected md5 and for a check tying rollback
block 2 to the harness orphan: both added.

## Live apply result

Applied 2026-11-06 about 20:47 IST after the founder's explicit go, as the single request of "Live apply" (the first attempt expired at
the tool's confirmation prompt and ran nothing; the live state was re-read unchanged before the second). Post-apply reads: `md5(prosrc)`
6597e3e24f91126b6268b3d54aa7ea57, length 460, orphan gone, `proacl` identical, `anon` and `authenticated` cannot execute, SECURITY
DEFINER and `search_path=public`, RLS enabled with 0 policies, job 41 unchanged, 616 to 624 rows (writers only), `min(started_at)`
unchanged. Ledger entry 172, OI-199 and OI-471 closed, the diagnose "Apply state" holds the numbers. Not yet observable: the keep-set
itself. Next observations: job 41 `succeeded` on 2026-11-07 03:30 UTC; first deletions about 2026-11-09 03:30 UTC.

### Questions put to review #2 (answered above)

1. Two pages per dead function (day 8 to 9, then day 11 to 13) is the default; one page would need the alert's dedup moved to
   about 7 days. Is leaving the alert untouched and naming the behaviour change to the founder the right call?
2. Is the order of work (B-pass BEFORE the apply, single expected red in the pre-B-pass gate loop) acceptable against §4.12.8,
   or must the apply come first so the loop is fully green? (Cost of apply-first: a B-pass defect in the body then needs a
   forward migration; cost of B-pass-first: one named red and a mechanical hash recompute.)
3. Is splitting the `/cron` window into a new OI a legitimate founder scope call under §4.2, or does it read as a deferral?
4. Is "unbounded, at most two rows per function name forever" the right contract, given a retired function leaves a tombstone
   that a future `/cron` reader would sort to the top of a "most stale first" list?
5. Is anything in the board/doc/record sequence (closing OI-199 for its Fix shape while a new OI carries the `/cron` half;
   the `closes-oi:` trailers; the plan-review record fields) likely to fail a merge gate?
