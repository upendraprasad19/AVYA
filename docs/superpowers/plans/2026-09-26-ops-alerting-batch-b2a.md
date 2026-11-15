# Batch B2a-1 — alert when a pure-SQL cron job fails (OI-178)

Branch: `ops-alerting-b2a` (from `main` @ 5c4d89ff, after B1 merged).
Execution mode: **inline**, single coordinator (§4.12.7). Tier: **platform**
(migration 145 has no SECURITY DEFINER; classified on the written file).
Review: ×2 plus a B-pass. No Hermes.

## Why this is its own piece (§4.12.1 split)

Plan-review R1 of the original B2a (this alert + the client telemetry fixes +
the spike-breadth alert) returned 3 P1 and 4 P2 findings, and most of them
redesigned the client half (P1-1, P1-3, P2-4…P2-7). Following §4.12.1, the
converged piece ships first:

- **B2a-1 (this plan):** migration 145 only. It shares no file with the client
  half.
- **B2a-2:** the client classification, the queue drift, dual write and spike
  breadth. It gets a new plan that absorbs R1's P1-1/P1-3/P2-4…P2-7/P3-8/P3-9,
  has its own ×2 review, and runs next in this session.
- **B2b:** OI-200 + OI-179. Both change SECURITY DEFINER functions, which
  makes them catastrophic tier and requires a Hermes pass.

Founder decision (2026-09-26): OI-178 is solved with a new alert on
`cron.job_run_details`, not with a telemetry bridge.

## Facts (verified live, project dedsavbjuwgarrhphgnl, read-only)

F1. The alerts on `cron_call_log` (143 `alert_cron_failures`, 110
    `alert_cron_function_dead`, `alert_cron_silence`) cannot see a SQL job,
    because only Edge Functions write `cron_call_log`. The only record of a SQL
    job's run is the row pg_cron writes itself, in `cron.job_run_details`.
F2. Last 30 days of `status='failed'` rows: jobid 41 failed 5 of 5 nights
    (VACUUM in a transaction block, d6b2f9). On 2026-09-21, 14 jobs failed —
    9 first-failing 01:46-04:41 UTC, 5 more first-failing 14:28-15:39 UTC, all
    `job startup timeout` (DB saturation, e8b4a1). 50 failed rows belong to
    jobids that are no longer in `cron.job`. (Corrected in the B-pass round:
    this said "within 7 h"; the real span is ~14h44m across those two
    clusters — verified independently against live `cron.job_run_details`.)
F3. `public.alerts`: `summary` is NOT NULL, and severity has
    CHECK ∈ {info, warn, critical}. Trigger `trg_dispatch_critical_alert_notify`
    (133:62) sends a Telegram page on `critical` only.
F4. pg_cron runs a job's command as ONE transaction (d6b2f9), so the job must
    be a single statement.

## R1 findings that apply here, and how 145 absorbed them (superseded in part by R2/R3 below)

- **P1-2:** one critical per job would have paged about 35 times in 30 days
  (14 on 09-21 alone). A NULL jobname would violate the NOT NULL summary, and a
  per-jobid dedup breaks whenever a job is rescheduled under a new jobid. 145
  therefore:
  - raises **ONE aggregated alert per run**;
  - grades severity by **failure kind**: `critical` if any failure is not a
    startup timeout, otherwise `warn`;
  - dedups **per severity** for 24 h, so an open warn never hides a critical;
  - uses **LEFT JOIN + coalesce(jobname, 'jobid N')**.
- **P3-9 (the part that applies here):** registered in `alerts/_thresholds.yaml`
  (`defined_in_migration`) and in CRON_REGISTRY (Gate 31).

## R2 findings (plan-review round 2, on the post-R1 draft) and how 145 absorbs them

- **P1-1:** the window was on `start_time`, but a row reads `failed` only when
  the run ENDS. 9 of 100 failed rows in 30 d were invisible to every check,
  and the longest failed run took 1h09m. Now `coalesce(end_time, start_time)`.
- **P2-2:** the quoted-name idempotency unschedule made Gate 31 read the job as
  removed (OI-193). It now unschedules by jobid, and Gate 31 counts 8
  migration jobs instead of 7.
- **P2-3:** NOT EXISTS, both intervals, the window column and yaml↔SQL
  agreement are now pinned (8 tests, 15 mutations).
- **P2-4:** an open critical hid every NEW failing job for 24 h. For critical,
  the dedup now also requires that the open alert names every failing job.
  Warn keeps severity-only dedup; job-set dedup for warn replays at 13 warns
  instead of 4.
- **P3-5:** 24 h sat on the nightly check-to-check boundary, so it would page
  on random nights. Now 23 h.
- **P3-6:** the capacity class widens to connection failed / connection slots /
  server restarted / could not connect.
- **P3-7:** the test's extractor reads `cron.alter_job` and tagged dollar
  quotes, and fails on anything it cannot parse.
- **P3-8:** nothing is committed before the founder-authorized apply. The
  ledger gates (`check_migration_ledger_paired`, `check_migrations_applied`)
  and `applied_migrations_parity_test` cannot pass until 145 is applied, which
  is the same sequence as B1.
- **P3-9:** diagnose citations corrected.

## R3 findings (round 3, on the post-R2 draft) and how 145 absorbs them

- **P2-1:** R2's job-set dedup compared the mixed `jobs` set (capacity-only
  jobs included). That could hide a new real failure in a job that had only
  timed out, and re-page hourly during a saturation storm. It now compares
  `sql_jobs`, the jobs failing with a real error.
- **P2-2 (scope):** OI-178 also covers jobs that are deactivated or never
  launched, which write no run row, so 145 cannot see them. **OI-178 stays OPEN**
  until a separate job-silence alert (B2a-1b, same session, next unit) lands,
  and that commit carries `closes-oi`. 145's commit does not.
- **P3-3/P3-4:** the window-gap and overlap residuals are stated in the header
  and the diagnose doc.
- **P3-5:** the extractor guard also trips on an unschedule (a retirement
  migration), and the `--`-in-literal limit is stated.
- **P3-6:** a missing yaml key fails with its name, not a null-check.
- **P3-7/P3-8:** counts corrected (18 of 100 in 30 d; 101 all-time) and the
  warn text completed. The CRON_REGISTRY `(jobid)` suffix is added at apply.

30-day replay of the final SELECT, at each hourly :23 check, read-only, with
dedup simulated and every alert left unacknowledged: **5 critical** (jobid 41,
each night from night one) and **4 warn** (one per DB-saturation episode). The
empty 65-min window returns 0 rows.

## Deliverables

1. `supabase/migrations/145_alert_sql_job_failures.sql`: a guarded unschedule,
   then `cron.schedule('alert_sql_job_failures', '23 * * * *', <one INSERT…SELECT>)`,
   a read-only post-apply check, and a rollback comment.
2. `alerts/_thresholds.yaml` `sql_job_failures:` and a CRON_REGISTRY row.
3. `test/contracts/alert_sql_job_failures_test.dart`, 8 tests, mutation-proven:
   19 mutations, each reddens ≥1 test.
4. Diagnose doc `b4c8e2`. **No `closes-oi` on this commit:** OI-178 stays OPEN until B2a-1b (the job-silence alert) lands, and that commit closes it.
5. `supabase/migrations/CLAUDE.md` pitfall row: a pg_cron command is one
   transaction (the lesson from B1).
6. Apply (founder go required, §4.3), then the `backups/applied_migrations.json`
   entry and a `backups/live_cron_jobs.json` regen in the same commit.

## Live proof after apply

The next `:23` run reads `succeeded` in `cron.job_run_details`, and no
`alert_sql_job_failures` row appears while nothing is failing.

---

# B2a-1b — alert when a pg_cron job stops running or is switched off (OI-178, second half)

Same branch and push as B2a-1. It exists because R3 P2-2 showed 145 covers only
half of OI-178: a job that is deactivated (`active = false`) or never
launched writes no run row. **This unit's commit carries `closes-oi: OI-178`.**
Review: ×2 plus a B-pass, on 146 specifically.

## Facts (live, read-only, 2026-09-26)

G1. `cleanup_cron_job_run_details` (SECURITY DEFINER) keeps 14 d and spares
    only each job's NEWEST run. A history-based threshold therefore cannot see
    a dead weekly job: its previous run is pruned before the threshold is
    reached. The newest run always survives.
G2. There are 26 active jobs (24 launched at least once, plus the 2 never-run
    vacuum jobs from 144) and 0 inactive. Schedules seen: `M H * * *`,
    `M * * * *`, `*/30 * * * *`, `*/15 H-H * * *`, `M H * * D`.
G3. Replay of "expected-from-schedule × 1.25 + 1 h" over every gap between
    consecutive launches, across all retained history (09-06 → 09-26): exactly
    2 flags, both real. `alert_payment_flow_health` and `alert_cron_silence`
    were not launched for 5 h on 2026-09-21 (e8b4a1). The history-based
    variant also flagged the windowed `morning_alert_deliver_*` jobs in their
    first week, and was rejected.

## Deliverables

1. `supabase/migrations/146_alert_cron_job_silent.sql`: a by-jobid guard,
   then `cron.schedule('alert_cron_job_silent', '33 * * * *', <one INSERT…SELECT>)`.
   - SILENT (critical): active, launched before, and overdue.
   - INACTIVE (warn): `active = false`.
   - Critical dedup: 23 h, unacknowledged, by silent-job set.
   - Warn dedup: 7 d by inactive-job set, acknowledged or not.
2. `alerts/_thresholds.yaml` `cron_job_silent:` and a CRON_REGISTRY row. Gate
   31 now counts 9 migration jobs.
3. `test/contracts/alert_cron_job_silent_test.dart` (7 tests, 15 mutations).
   The 145 test moves onto the shared `test/helpers/cron_job_body_reader.dart`,
   and its stale-body guards were re-proven through the helper.
4. Diagnose doc `f7a3d2`, and `closes-oi: OI-178` (the board and OPEN_INDEX in
   the apply commit).
5. Apply 145 and 146 together, on the founder's go.

### B2a-1b R1 fixes (applied)

- P1: the CASE order is now month 366 d → dow 7 d → dom 62 d → hour 1 d, so
  no branch gives a gap shorter than the schedule's real one. It is pinned as
  one ordered string.
- `why` carries the last run's status, so a hung run reads as `(running)`.
- The shared helper throws on `UPDATE cron.job` next to the job name, and on
  ANY numeric-id `alter_job` (0 exist).
- Residuals are filed: OI-250 (out-of-band heartbeat, self/correlated
  silence, the `cron.log_run` dependency) and OI-251 (retention effect unobserved).
- Mutations: 18 on 146 plus 2 helper legs. Every one reddened at least one test.

### B2a-1b R2 review — not converged, 1 material — fixes applied

- **P2-1 (material):** re-enabling a switched-off job, or shortening its
  schedule via `cron.alter_job`, pages ONE false critical — `cron.job` has no
  timestamp columns, so "last launched" still predates the change until the
  job's next scheduled run. No suppression is safe: keying it off the earlier
  warn would leave a re-enabled-but-never-relaunched job permanently
  unjudged, which is exactly the failure this alert exists to catch. Fixed by
  documenting the one expected page in the migration header and in both
  `suggested_action` strings ("acknowledge it").
- **P3-1:** two schedule shapes have an unbounded real gap no fixed guess
  covers — both day fields set with one starting `*` (pg_cron ANDs them,
  e.g. `0 0 */2 * 1` = Mondays on odd dates only) and a set month with
  day-of-month 29–31 (leap-day / month-length edges). Fixed: two new
  not-judged (NULL) arms, ordered before the month arm. Whether either arm
  incorrectly swallows any LIVE schedule into NULL is R3's job to confirm.
- **P3-2:** 3 of the reviewer's 4 mutations against the round-1 test suite
  survived (green): a dead warn arm (`WHERE NOT j.active AND false`), the
  `silent_jobs` aggregate filtered on `'inactive'` instead of `'silent'`
  (which — with 0 inactive jobs live — makes the key NULL, `@> NULL` is NULL,
  `NOT EXISTS` is always true, and the job would page critical hourly with
  every test green), and `last_status` sorted `ASC` (cosmetic). Fixed: 3 new
  assertions pin the full `UNION ALL` text, both `FILTER` clauses, and the
  `ORDER BY … DESC NULLS LAST` clause. Re-mutated: all 3 now redden.
- **P3-3:** the shared helper missed the `job_id => 5` named-argument
  spelling of a numeric-id `alter_job` (only `:=` was caught). Fixed: regex
  now accepts `:=` or `=>`. The loop-variable `alter_job(r.jobid, …)` form
  (107's shape) stays a stated, undetectable limit.
- **P3-4:** a job that recovers then goes silent again within 23 h of an
  unacknowledged page naming it is not re-paged. Stated as a residual, not
  code-changed — the open page already stands for it.
- **P3-5:** text/count corrections (OI-250's "flags once then goes quiet" →
  "re-pages every 23 h and after each ack"; malformed `* * 1-5` example →
  `M H * * 1-5`; stale "7,004 rows" → live "7,010").
- Mutations for this round: 5 on 146 (the 3 survivors plus dropping each new
  NULL arm) plus the helper's `=>` form. Every one reddened at least one test.

### B2a-1b R3 review — CONVERGED, 0 material

Independent fresh reviewer, re-verified all 6 R2 fixes from scratch rather than
trusting the diagnose doc's own claims:

- P2-1, P3-4, P3-5: verified present as documented, no code change needed.
- **P3-1's open question — does either new NULL arm swallow a live schedule
  it shouldn't — is now closed: no.** Live-executed the CASE against all 26
  active jobs (0 deactivated); none has both day-fields set or a set month,
  so neither new arm fires today. Also confirmed the arm is load-bearing, not
  vacuous: dropping it reddens 1 test.
- P3-2: independently re-ran all 3 survivor mutations (M2/M3/M4) one at a
  time with its own scratch-backup + sha256 restore-verification cycle for
  each — all 3 now redden exactly 1 test, matching the counts claimed.
- P3-3: wrote a standalone 10-case probe against the helper's regex — both
  `:=` and `=>` numeric forms caught, both real subquery forms (`job_id :=
  (SELECT ...)`, used by 141/144) correctly NOT flagged; cross-checked against
  every live `alter_job` call in the repo (107/108 loop-variable form stays a
  documented gap; 141/144 subquery form correctly ignored).
- Structural: still one statement; blast radius still platform (no
  SECURITY DEFINER, no destructive DDL); both sibling contract tests green
  (146: 7/7, 145: 8/8).
- One non-blocking note (not a defect): the new NULL-arm condition is
  conservative beyond the minimal case it targets (e.g. a hypothetical
  list+step combination also lands in NULL even though its real gap may be
  bounded) — costs nothing today since no live job uses such a shape.

Verdict: **CONVERGED.** Both migrations (145 after 4 rounds, 146 after 3) have
now independently converged. Next: self-triggered B-pass, then the branch
plan-review record.
