# OI-473 (+ OI-472) — `alert_cron_function_dead`: storm, duplicate alerts, exclusion list

Tier: L (migration changing a live cron body). Execution mode: INLINE. Branch `oi473-cron-dead-alert-edges`.
Lenses: L1 (writer/reader), L31 (alert coverage), L9 (cron).
Plan revision: v3 = v2 + review #2 (12 findings, no P0, all P2/P3 mechanical: R2-1..R2-12). v2 = v1 + review #1 (12 findings, no P0: R1-1..R1-12). Both rounds are applied below; review #2 raised no design change (cap, window, exclusion list and roster test unchanged).
Scope decisions already made with the founder (2026-11-05): OI-201 closed as moot, Telegram is deferred, so the
Telegram retry is OUT of scope. OI-472 (`weekly-recalc` exclusion) is folded in because the roster test this batch adds
cannot be green without it; both close in this batch.

## Facts (verified 2026-11-05, live project `dedsavbjuwgarrhphgnl`, read-only)

- Live alert body md5 `bb2108a12cf313fa5cb4ee8c7f8d9398` (jobname `alert_cron_function_dead`, daily 06:47 UTC); it
  contains the `alert-critical-notify` exclusion and `acknowledged = false` in the dedup. Writer of the body: migration 144
  (`alter_job`), no later migration redefines it.
- Writer of alert rows: this job's `INSERT ... SELECT`, one row per dead function. Trigger
  `trg_dispatch_critical_alert_notify` (migration 133, `AFTER INSERT ... FOR EACH ROW WHEN severity = 'critical'`)
  dispatches `alert-critical-notify` per row.
- Readers of that alert's `context_json`: none besides the alert's own dedup (grep of `lib/`, `supabase/functions/`,
  `test/`, `scripts/`, `docs/sot_registry.yaml`: only tests that read the job BODY: `alert_threshold_below_retention_test.dart`,
  `cron_vacuum_single_statement_test.dart`, `alert_cron_failures_sync_test.dart` text mention).
- 17 `cron_call_log` function names today; 19 `logCronStart("<name>")` callers in `supabase/functions/*/index.ts`
  (the two extra: `alert-critical-notify` trigger-dispatched, `weekly-recalc` no schedule).
- **Deriving the exclusion from live `cron.job` text does NOT work (measured):** `compute-admin-metrics-daily` and
  `compute-coach-signals` have no `cron.job` command naming them; their URLs come from
  `private.compute_admin_metrics_function_url()` / `private.compute_coach_signals_function_url()`. A name join would
  silently drop two live functions out of the alert (the unsafe direction). So the exclusion stays an explicit list in
  the body, tied to reality by a contract test.

## Fix

**Statement shape (R2-1):** one data-modifying CTE statement, no `;` inside the command:
`WITH dead AS (SELECT ... FROM public.cron_call_log ... GROUP BY function_name), fresh AS (SELECT ... FROM dead d WHERE
d.days_silent >= 8 AND NOT EXISTS (...72 h dedup...)), n AS (SELECT count(*) AS c FROM fresh), singles AS (INSERT INTO
public.alerts (source, severity, summary, context_json, suggested_action) SELECT ... FROM fresh, n WHERE n.c <= 3 RETURNING 1)
INSERT INTO public.alerts (...) SELECT ... FROM n WHERE n.c > 3;`. `dead` is its own CTE closing right after `GROUP BY` so the
`FROM public.cron_call_log` parenthesised scope stays free of the 72 h interval; `FROM public.cron_call_log` appears exactly
once. All CTEs see one snapshot and the two arms are mutually exclusive on `n.c`, so there is no visibility problem (answer to
open question 3: none). A summary can never be inserted when `fresh` is empty (`n.c` = 0).

One migration (number from `sh scripts/mint_migration.sh oi473_cron_dead_alert_edges`; slug avoids `rls` /
`security_definer`), `cron.alter_job(job_id := (SELECT jobid FROM cron.job WHERE jobname = 'alert_cron_function_dead'),
command := ...)`. The body is the 144 body plus these changes, and nothing else (schedule untouched):

1. **Edge 1, storm: cap with one summary row.** The dead set is computed in CTEs. If the number of NEW dead functions
   (after dedup) is <= 3, insert one row per function exactly as today. If it is > 3, insert ONE `critical` summary row
   (`context_json` = `{"function_names": [...], "count": N}`, no `function_name` key, text names the first 20) instead of
   N rows. One mechanism only: no dependence on `alert_cron_silence` state (considered and dropped: suppressing while
   `alert_cron_silence` is open couples two alerts' acknowledge states). Constant: cap = 3 (`n <= 3` singles, `n > 3`
   summary). Form (R1-6): a separate `n AS (SELECT count(*) AS c FROM fresh)` CTE; the summary is
   `INSERT ... SELECT ..., (SELECT jsonb_agg(function_name ORDER BY days_silent DESC) FROM fresh) FROM n WHERE n.c > 3`,
   never an aggregate over `fresh` without GROUP BY (that returns one row even when `fresh` is empty and would insert a
   bogus summary every quiet day). The count is taken AFTER dedup, so 2 new + 4 already alerted = 2 singles.
   Summary text (R2-11): built from a `LIMIT 20` of `fresh` ordered `days_silent DESC, function_name` (deterministic); `alerts.summary` is unbounded TEXT and neither consumer truncates it, but 20 names stay near 600 characters, far under the 4096 Telegram limit. `count` and the `function_names` array hold only the NEW functions (those not already alerted), the text says so.
   Effect: the worst case (8-10 day fleet outage, 17 functions) is ONE critical row and one dispatch. ACCEPTED RESIDUALS,
   stated not solved (R1-7): (a) post-recovery stragglers (functions scheduled after 06:47 UTC look dead on the first
   morning) still raise one summary or up to 3 singles; (b) functions that cross the 8-day line on different days
   (staggered) produce another summary or singles on the second day. (c) a keep-set row (`cleanup_cron_call_log` spares the newest success overall and the newest row overall, `169:40-45`) can keep one function visible past day 10 up to the 14 d lookback, so it re-fires about every 3 days (R2-10). All three are bounded, none is a storm.
2. **Edge 2, duplicates: dedup on function name for 72 h, independent of acknowledgement** (R1-1: v1 said 48 h).
   Drop `acknowledged = false`; window 24 h -> 72 h. Why 72 and not 48: `detected_at` is the run's transaction `now()`
   (`076:15`); a dead function's last success is visible on 2 or 3 consecutive daily runs (age range [8 d, 10 d + 3 h 17 m]:
   the prune runs 03:30 UTC and the scan 06:47 UTC); run 3 happens at run 1 + 48 h + pg_cron start jitter, so a 48 h window
   re-fires on run 3 about half the time (the exact jitter hazard OI-473 item 2 names, moved, not removed). 72 h exceeds
   the whole visible span (about 2.14 d), so ONE alert per dead function holds. A function is also "already alerted" if it
   appears in the `function_names` array of a summary row in the window: written
   `(a.context_json ->> 'function_name' = d.function_name OR a.context_json -> 'function_names' @> to_jsonb(d.function_name))`,
   parenthesised (R1-10: `@>` instead of `?`, which collides with placeholder-style clients). NULL semantics are safe
   inside NOT EXISTS. The 72 h `interval` lives in `fresh`, OUTSIDE the `FROM public.cron_call_log` parenthesised scope
   (R1-11).
3. **Edge 3 + OI-472, exclusion list.** `function_name <> 'alert-critical-notify'` becomes
   `function_name NOT IN ('alert-critical-notify', 'weekly-recalc')` with a comment per entry (trigger-dispatched, and
   unscheduled, OI-472). New contract test `test/contracts/cron_call_log_writers_roster_test.dart`:
   - Set A (R1-3): every `logCronStart(` call site in `supabase/functions/*/index.ts` (prefix `telemetry.` allowed, single OR
     double quotes: `clean-orphan-media/index.ts:48` is single-quoted, `alert-critical-notify/index.ts:64` is
     `telemetry.`-prefixed). The count of call sites (comments and the typed-parameter declaration lines excluded) must equal
     the count of literal-name matches, so a caller passing a constant or variable FAILS with a clear message instead of being
     invisible. Non-vacuity pin: `|A| >= 19` plus the named members `alert-critical-notify`, `weekly-recalc`, `clean-orphan-media` (R2-8: `== 19` would make the test red for every legitimately added cron function, on top of the real subset failure).
   - Set B (R1-4): parse only the table whose header contains `| Function |` in `docs/operations/CRON_REGISTRY.md` (the
     Deprecated table has a different header), take the Function cell, extract `` `([a-z0-9-]+)` `` from it (so
     `` `morning-alert` (generate) `` yields `morning-alert` and `private.process_referral_conversions()` yields nothing).
     Non-vacuity: contains `founder-digest` and `morning-alert`, at least 17 names.
   - Set C: the names in `function_name NOT IN (...)` parsed from `latestCronJobBody('alert_cron_function_dead')`;
     non-vacuity: contains `alert-critical-notify` and `weekly-recalc`.
   - Assertions: A subset of B union C; C subset of A; **B intersect C is empty** (R1-5: a function later scheduled and
     registered, e.g. `weekly-recalc` via OI-472's other option, must leave the exclusion list, else it is silently
     unwatched). Day one (checked by the reviewer by hand): all 17 other callers are in B, the two excluded ones in A only, so
     nothing is red.
   - Optional cross-check (R2-12): the `_triggerDispatchedFunctions` roster in `test/contracts/cron_auth_adoption_test.dart` is a subset of C, so the two lists cannot diverge.
   - Mutants (run, applied-checked): drop `weekly-recalc` from C; add a fake caller; add a stale C entry; put a scheduled
     function in C; empty parse of each set; a variable-name caller; a single-quoted caller dropped from the regex.
   Known residual, stated not hidden: a function RETIRED from the repo and the registry still pages once (the 72 h dedup
   makes it exactly one alert) before its rows leave `cron_call_log`; the alert text says to confirm retirement.
4. Existing tests (R1-2, R1-8, R1-11):
   - `alert_threshold_below_retention_test.dart` group "tripwire" asserts the exact sorted list of migrations containing both
     `FROM public.cron_call_log` and `INTO public.alerts` (:104-115): APPEND the new migration filename (the new NNN sorts last).
     Run this test FIRST once the migration file exists.
   - The same test's `latestCronJobBody` pins need the shape: inside the paren-balanced scope that starts at
     `FROM public.cron_call_log`, exactly one `interval '14 days'` (asserts `[14.0]`); exactly one
     `(days|hours)_silent >= N`, spelled `d.days_silent >= 8` (asserts `[8.0]`); `cron.alter_job(` ... `jobname =
     'alert_cron_function_dead'` ... `command :=` before the first `;`; `$$` as the quote tag (like 144).
   - `cron_vacuum_single_statement_test.dart` :146-198 reads migration 144 BY NUMBER, so it passes forever on the immutable 144
     and no longer guards the live body. DECISION: leave those two tests as the record of 144, and the new roster test
     supersedes them for the latest body (it fails if `alert-critical-notify` is not in C). This departs from OI-473's
     "extend cron_vacuum_single_statement_test.dart" on purpose: a roster test spanning functions, registry and body does not
     belong in a VACUUM-shape test file.

## Tests

- Roster test above, with its mutants.
- Behavioural rehearsal `test/sql/alert_cron_function_dead_edges_live_verify.sql`, `BEGIN ... ROLLBACK`, REPEATABLE READ per
  the `cleanup_cron_call_log_retention_live_verify.sql` precedent (re-run on a serialization failure). Run against the OLD body
  first (storm reddens), then the new one, as two separate calls. Mechanics (R2-3, R2-4, R2-5):
  - Body once: `CREATE TEMP TABLE _b AS SELECT $b$<body>$b$ AS t`; each case runs `EXECUTE (SELECT t FROM _b)` inside a
    `DO $v$ ... $v$` block (three distinct dollar tags; the body itself contains no `$$`). This keeps the call near 10 KB, not
    the 12 KB MCP limit: measure the file with `wc -c` before sending; on a size overrun the error is "Invalid or expired
    requestState" and nothing ran.
  - Byte-identity: the rehearsal's md5 is taken over the RAW text between the migration's `$$ ... $$` (extracted with `sed -n`,
    leading newline included), NOT over `latestCronJobBody(...).body`, which has `--` comments stripped and can never match
    `cron.job.command`. The md5 only proves the body the rehearsal ran is the body being applied; state it that way.
  - Isolation: `DELETE FROM public.cron_call_log` first (rolled back), per the precedent, and delete this source's `alerts`
    rows between cases, in the transaction. Results are counted by `id > max_id_before`, never by whole-table counts, so live
    rows cannot mix in. `now()` is frozen in a transaction, so every time-dependent case uses back-dated seeds for
    `cron_call_log.started_at` and `alerts.detected_at`. Seed "already alerted" rows with `severity = 'warn'` (dedup keys on
    source and function name only), so seeds never fire trigger 133. `cron_call_log` seeds need only
    `(function_name, status, started_at)`; `alerts` seeds need source, severity, summary, context_json.
  Cases: (a) 5 dead => exactly 1 summary (`count` 5); (b) 3 dead => 3 singles; (c) **4 dead => 1 summary** (the 3/4
  boundary); (d) **0 dead => 0 rows** (R1-6); (e) run again right after (a) => 0 rows; (f) acknowledge the summary, run again => 0
  rows; (g) `weekly-recalc` success 9 days old => 0 rows; (h) **2 new + 4 already alerted => 2 singles** (cap counts post-dedup);
  (i) a real summary row (`function_names` array) 25 h old, 3 functions named in it => 0 rows; (j) window boundary: an alert
  `detected_at = now() - interval '71 hours 59 minutes'` suppresses, one at `now() - interval '72 hours 1 minute'` does not.
  (A "pruned function, no row => no alert" case is documentation only: no row means no group, so it passes under any body and
  reddens under no mutant (R2-9); it is not listed as protection.)
- Trigger safety (R1-9, R2-2): the body's own critical inserts DO fire trigger 133 (`net.http_post`) inside the transaction; a
  ROLLBACK should discard the queue insert (pg_net queues in the caller's transaction). A before/after count of
  `net.http_request_queue` is noisy (the pg_net worker deletes rows concurrently), so the guard is deterministic: INSIDE the
  transaction, before ROLLBACK, count queue rows whose `body::jsonb->>'alert_id'` is one of the ids this run inserted (expect
  more than 0 when the vault secret is readable; 0 is also acceptable if the trigger returns early without it, and the run
  prints which); AFTER the ROLLBACK, in a SEPARATE call, count queue rows referencing those ids (expect 0; if more than 0, STOP:
  real notifications would have been sent). Read-only checks run first and are reported: `has_table_privilege(current_user,
  'net.http_request_queue', 'SELECT')` and `private.cron_get_secret() IS NOT NULL`. If either guard cannot run, the rehearsal
  uses `SET LOCAL session_replication_role = replica` (disables the trigger; whether the MCP role may set it needs a live
  check) and the dispatch path is covered by the existing `alert_critical_notify_trigger_live_verify.sql` instead.
- Mutation discipline (§4.4 r21): mutate the new body (cap 3 -> 4, window 72 -> 48 h, drop `weekly-recalc`, drop the post-dedup
  count) and confirm the rehearsal reddens; confirm each mutation applied; record how many cases reddened in the diagnose doc.

## Docs and board

Files the real commit touches (R2-6, from the stats of the 144 and 169 commits): the migration; `backups/applied_migrations.json`
(hash via `scripts/migration_ledger_hash.dart`, same commit as the apply); the roster test; the appended tripwire list; the
rehearsal SQL; `docs/plan-reviews/oi473-cron-dead-alert-edges.md` (one path per cited file, each with a `verdict: accepted`
line); the B-pass file `docs/reviews/<sha>-review.md` with a `## Tuning entry` section; a Hermes report if the tier demands it;
`docs/audit/open_issues.md` + `closed_issues.md` (append only); the diagnose doc. NOT needed: `backups/live_cron_jobs.json`
(schedule unchanged), `docs/sot_registry.yaml`, `alerts/_thresholds.yaml` (no entry for this job), regression-catalog
registration of a `test/sql` file. The commented rollback must carry no raw `cron.schedule(` / `cron.unschedule(` line (Gate 31).

Doc-claim sweep (R2-7), one edit, grepped: the old "24 h dedup / up to three alerts / pages only during days 8-10" text lives in
`docs/operations/CRON_REGISTRY.md` row 45 (keep its OI-199 half), `docs/audit/open_issues.md` OI-473 (closed),
`docs/diagnoses/2026-11-05-cron-call-log-retention-below-alert-threshold-c9e2a7.md:68-69`,
`docs/audit/2026-11-05-hermes-oi179-cron-dead-alert.md:61`, `docs/plans/oi179-cron-dead-alert.md:38` and the immutable 169
header. Records stay as history; the new diagnose doc names them as superseded.

`docs/operations/CRON_REGISTRY.md` row 45 (the 24 h dedup text, "pages only while ... 8-10 days"; say "one alert per dead function, 72 h dedup", and the summary row), diagnose doc
(`closes-diagnose:`, full template, recurrence class: `feedback_green_check_input_set_width` / OI-179 d6b2f9), OI-473 and
OI-472 closed with `closes-oi:` trailers and moved to `closed_issues.md` (append only), `backups/applied_migrations.json`
in the same commit as the apply, SoT registry entry only if a writer/reader contract line moves (it does not).

## Live apply

Separate explicit go from the founder (CLAUDE.md §4.3). Order: rehearsal on the old body (red) and new body (green) in
`BEGIN ... ROLLBACK`; apply; `SELECT md5(command)` equals the migration body; the next 06:47 UTC run is the first real
observation (nothing is dead today, so expect 0 rows: state that in the diagnose doc as "not yet observed").
Rollback: `cron.alter_job` back to the 144 body (the migration carries a commented pointer to migration 144 lines 65-102, not a copy).

## Open questions for the reviewers

Is cap = 3 and window = 72 h right given retention 10 d / threshold 8 d and the 03:30 prune / 06:47 scan? Does any consumer other than the alert read
`alerts.context_json->>'function_name'` for this source? Can the data-modifying CTEs in one `cron` command raise a
snapshot or visibility problem between `fresh` and the two inserts?
