---
hermes_pass_id: 2026-11-06-hermes-cron-log-retention-oi199-oi471
ran_at: 2026-11-06T14:55:00+05:30
batch_scope: staged, uncommitted tree of branch cron-log-retention-oi199-oi471 (migration 172, harness, contract test, docs, four comment-only Edge Function edits), after the B-pass fixes
lens_set: [L1, L2, L23, L35, L40, guard_without_its_mirror, asserted_fixture_value]
agents_dispatched: 4
findings_total: 31
findings_by_severity: { P0: 0, P1: 0, P2: 7, P3: 24, false_alarm: 0 }
verdict: accepted
verdict_note: every finding has one terminal state below; no P0 or P1; the SQL of migration 172 drew no defect, every P2 was a runbook, wording or checker-strength defect and was fixed before the commit
---

# Hermes Pass - OI-199 + OI-471 (migration 172, per-function keep-set for cron_call_log, drop of the orphan 7-day pruner), catastrophic tier by content (SECURITY DEFINER)

Four Sonnet seats in one wave (the founder rule is Sonnet for review and never Opus, which overrides the hermes-pass skill's Opus
default), read-only against the staged tree, no production access. The brief listed the allowed commands exhaustively and banned
database statements, `dart run scripts/` and writes. Seat A: L35 and the live-apply runbook and reversibility. Seat B: L1, the readers
and consumers of "old kept rows" and of "a dead function pages twice". Seat C: L2, L23, L40, security and abuse of the definer
function. Seat D: guard_without_its_mirror and asserted_fixture_value on the checkers and the verify harness. Ran AFTER the B-pass
fixes (`docs/reviews/*-review.md`, renamed to the final staging hash before the commit).

## Summary
- 0 P0, 0 P1, 7 P2, 24 P3 records, 0 false_alarm. Ship-blockers: none.
- All four seats agree on the SQL: the body is a superset of the 169 keep-set up to a same-function `started_at` tie (the header says
  so), the first nightly run after the apply deletes nothing under either body, `CREATE OR REPLACE` keeps the ACL, the grants are
  restated exactly, and a failed DROP inside one request aborts the CREATE with it.
- Every finding was checked against the file or the container before it was applied. Where a seat's figure differed from mine I used
  the one I could reproduce (seat D computed the md5 of the 172 body by another method; the value used is the md5 of the raw text
  between the `$fn$` tags, leading and trailing newline included: `6597e3e24f91126b6268b3d54aa7ea57`, 460 bytes, asserted by the
  harness and by a Dart test).
- Command deviations disclosed by the seats: seat A and seat C each ran one read-only `python3` snippet on a scratch copy; seat D ran
  the Dart test and the docker harness it was allowed to run. No seat wrote to the repo, the network or a database.

## Findings by seat

### Seat A - L35 and the live-apply runbook
- **A-1 (P2, REAL):** the plan said to send the statements only "if the file nears ~12 KB"; the 7,456 B file with its comments is
  above the size at which a 7 KB DDL block failed on 2026-10-24, and a retry in pieces would break atomicity. **Terminal: fixed** (plan
  "Live apply": ONE `execute_sql` request, statements only, never split).
- **A-2 (P2, PARTIAL):** `.claude/apply_migration_via_api.js` posts the raw file with no BEGIN and none of the timeouts. **Terminal:
  fixed** (the plan names `execute_sql` as the only route).
- **A-3 (P3, REAL):** `lock_timeout` / `statement_timeout` must be `SET LOCAL`. **Terminal: fixed.**
- **A-4 (P3, REAL):** the expected md5 was written nowhere. **Terminal: fixed** (the value and 460 bytes are in the migration's
  post-apply block, the plan, the harness, a Dart test, and asserted inside the apply transaction).
- **A-5 (P3, PARTIAL):** rollback block 2 cannot restore attributes nobody captured. **Terminal: fixed** (the pre-apply recheck reads
  `pg_get_functiondef`, volatility/cost/parallel, the comment and the overload count of the orphan).
- **A-6 (P3, PARTIAL):** the `pg_stat_statements` and API-log reads are weak evidence of "no caller". **Terminal: fixed** (stated, and
  `min(started_at)` plus the count of rows older than 7 days added as the stronger signal).
- **A-7 (P3, REAL):** "deletes nothing by itself" had no before/after snapshot. **Terminal: fixed** (row count and `min(started_at)`
  before and after).
- **A-8 (P3, PARTIAL):** no emergency path if the first 03:30 UTC run fails. **Terminal: fixed** (migration header and plan; the
  rollback block warns that it prunes the retained rows at the next run).
- **A-9 (P3, REAL):** diagnose line references stale. **Terminal: fixed** (writers cite lines 49 and 72 of the final file).
- **A-10 (P3, REAL):** commit, push, merge and a rollback need their own gos. **Terminal: fixed** (the ask names them separately).

### Seat B - L1, readers and consumers
- **B-1 (P3, REAL):** `CRON_REGISTRY.md` row 52 still says the alert "sees only 8-10 days of silence". **Terminal: fixed.**
- **B-2 (P2, PARTIAL, deliberately unfixed):** job 32's critical text ("it stops once its rows leave cron_call_log") is false on the
  second page, and `alert-critical-notify` sends it verbatim. **Terminal: filed** (OI-478 part 2, a new `cron.alter_job` migration with
  its own Hermes pass) **and disclosed** in the live-apply ask so the founder can veto or ask for the body fix first.
- **B-3 (P3, REAL):** `founder-digest/index.ts` header says the alert "cannot fire at all". **Terminal: fixed** (comment only).
- **B-4 (P3, REAL, wording):** "No reader looks beyond 14 days" contradicted the header's own `alert_cron_silence` line. **Terminal:
  fixed** (STATED LIMITS paragraph).
- **B-5 (P3, REAL):** `_shared/cron_telemetry.ts` header says "Retention: 10 days". **Terminal: fixed** (comment only).
- **B-6 (P3, nits):** stale line numbers, "day 11 to 12" instead of 11 to 13, present-tense "rows now stay" in comments while 172 is
  unapplied. **Terminal: fixed.**
- Re-derived by the seat: a third page is impossible (it would need age 14 d or more, outside the lookback); the second falls at age
  11 to 13; no consumer of `alerts` keys on source or acknowledgement; OI-194 interplay confirmed (weekly-recap-ready only).

### Seat C - L2, L23, L40, security and abuse
- **C-1 (P2, PARTIAL):** the "two rows per name" bound rests on live RLS (enabled, zero policies) that no migration sets (068 says RLS
  stays disabled) and on OI-184 (open: anon and authenticated hold raw table grants). **Terminal: fixed** (stated in the migration's
  COST paragraph; `relrowsecurity`, the policy count and the table privileges are read before and after the apply; OI-184 itself stays
  open on the board, it pre-exists this batch).
- **C-2 (P3, PARTIAL):** "fails closed" is true for catalog dependents only. **Terminal: fixed** (wording; the recheck also searches
  `cron.job` and `prosrc`).
- **C-3 (P3, PARTIAL):** "34 rows" is easy to misread. **Terminal: fixed** (past the cut at most two per name, 34 to 38 by the code's
  19 literal names, plus every row younger than 10 days).
- **C-4 (P3, REAL, a habit):** `error_summary` is capped at 1000 characters but not sanitised at the sink; no leak path found.
  **Terminal: filed** (OI-481; not a unit of this batch, does not change what 172 retains in kind).
- **C-5 (P3):** the commented rollback re-creates a wider-than-needed definer. **Terminal: fixed** (noted in rollback block 2).
- Clean by the seat: writers are the shared telemetry module with 19 literal names; the function qualifies the table and is
  idempotent; no credential-shaped literal in the diff (the only password is the throwaway container's `POSTGRES_PASSWORD=x`, no
  published port, removed by a trap).

### Seat D - guard_without_its_mirror, asserted_fixture_value
- **D-1 (P2, REAL):** the Dart keep-set check only read the inside of the `NOT IN` list; a `) OR started_at < ... '30 days'`, a second
  DELETE or another target passed. **Terminal: fixed** (`bodyDriftProblems`, fixtures B1 to B4).
- **D-2 (P2, REAL):** the GRANT/REVOKE scan only saw the exact spelling `public.cleanup_cron_call_log()`. **Terminal: fixed**
  (statement-wise scan, fixtures A7 to A10).
- **D-3 (P2, PARTIAL):** the "no newer migration mentions the function" tripwire false-redded on a plain call. **Terminal: fixed**
  (DDL-only, seven pure fixtures, three hand mutations with scratch migrations).
- **D-4 (P3, REAL):** the rollback header was never compared with 169. **Terminal: fixed** (fixture R4).
- **D-5 (P3, REAL):** `H_old_keep_set_is_subset_of_survivors` was vacuous (the 169 keep rows are 0 days old in that fixture).
  **Terminal: fixed** (case H2, dead fleet; `H2_dead_fleet_old_keep_rows_survive` reddens under M2, M4, M5, M7).
- **D-6 (P3, REAL):** three of six K labels had no mutant. **Terminal: fixed** (M16 to M18, plus an ACL-based postgres label because
  `has_function_privilege('postgres', ...)` is true for a superuser).
- **D-7 (P3, REAL):** nothing proved the local-only guard fires. **Terminal: fixed** (a harness step, rc 3 and the message).
- **D-8 (P3, REAL):** benign edits false-redded with a misleading message. **Terminal: fixed** (fixtures P1, P2).
- **D-9 (P3, REAL):** `readRetentionDays` read the first definition. **Terminal: fixed** (last definition; already done in the B-pass
  round, now fixtured in `alert_threshold_below_retention_test.dart`).
- **D-10 (P3, PARTIAL):** M1 to M12 asserted only `isNotEmpty`. **Terminal: fixed** (specific message per fixture).
- Also from the seat: an expected md5 for the post-apply check, and a check tying rollback block 2 to the harness orphan copy.
  **Terminal: fixed** (both added).

## Verification after the fixes (2026-11-06)
- Harness (`bash test/sql/cleanup_cron_call_log_per_function_local.sh`, local docker, exit 0): 169 body 15 of 35 red; 172 body 35 of 35;
  proacl identical; md5|length equal the asserted values; 19 mutants killed (M12 included); the scaffold-refusal step passes; step 2b
  runs the exact live apply request (commits on the 169 state; a wrong md5 or an unseen catalog dependent aborts it with the CREATE and
  the DROP rolled back together).
- Neuter experiment on the Dart checkers (scratch copy, removed): 42 tests reddened, exactly the rejection fixtures plus the five DDL
  fixtures that expect a flag. `deno check --node-modules-dir=none` passes for `telegram-admin-bot` and `founder-digest`; the 51
  `telegram-admin-bot` Deno tests pass.

## Not verifiable here (stays with the pre-apply recheck)
Live md5s and ACLs of both functions, the orphan's attributes and dependents, `pg_stat_statements` visibility, the API-log window, RLS
and table privileges on `cron_call_log`, the live text of jobs 31, 32, 41 and 43, the live Postgres major version, the row total and
the 17 names. Each is a read-only query written into the plan's "Live apply" section.

## Tuning notes
- A pin written against the first definition of a function goes stale the moment a later change widens its meaning: the Dart pin
  compared a list, not the function. Pin the whole text and make a deliberate change edit the pin on purpose.
- A source check that is only too-narrow-aware needs a too-wide mirror (B1 to B3, W1 to W5).
- A security envelope is not pinned by `CREATE OR REPLACE`: it keeps the ACL and resets the security mode and `proconfig`. Check both
  in the live-shaped harness.
