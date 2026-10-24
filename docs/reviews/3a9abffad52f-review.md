---
reviewed_at: 2026-09-26T12:23:48+05:30
staged_against: 3a9abffad52f
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 1
verdict: accepted
---

# Code Review — 3a9abffad52f

## Finding 1 — P3 — guard_without_its_mirror (informational)
- **file:line:** `supabase/migrations/144_split_vacuum_out_of_db_maintenance_nightly.sql:117-118`
- **claim:** The commented-out rollback block re-schedules the pre-144 state and includes
  `-- SELECT cron.unschedule('jrd_vacuum_daily');` / `-- SELECT cron.unschedule('client_errors_vacuum_daily');`
  as fully-quoted, syntactically-real `cron.unschedule('name')` calls. `docs/operations/CRON_REGISTRY.md`
  (unchanged row, `founder_digest_daily`/131) documents an established, deliberate convention for exactly
  this situation: *"Its rollback comment is deliberately an UNQUOTED `cron.unschedule(<name>)` so Gate 31's
  raw scan does not read the rollback as a real unschedule (OI-193)."* `scripts/check_cron_registry.dart`
  (Gate 31) scans RAW `.sql` file text for `cron\.unschedule\s*\(\s*['"]([^'"]+)['"]` with **no comment
  stripping at all** — confirmed by reading the script (no `_stripLineComments`-equivalent anywhere in it).
  Migration 144's rollback block does not follow the OI-193 convention its own sibling row documents.
  **In THIS commit it is a no-op**, because 144's *live* code already contains a real, unguarded-by-comment
  `cron.unschedule('jrd_vacuum_daily')` call (line 52) that puts the job in Gate 31's "ever-unscheduled"
  set regardless of the rollback comment — so no gate behaviour changes today. It is flagged because
  the mirror case is a *future* migration that re-schedules `jrd_vacuum_daily` or `client_errors_vacuum_daily`
  again (e.g. a follow-up job-id/time-slot change) with no unschedule call of its own: Gate 31's Input A
  will still see the job as permanently "unscheduled" (via 144's redundant quoted rollback text, on top of
  144's own real call), and nobody auditing that future migration would think to check a comment three
  migrations back for why. Cheap to make consistent now while the file is still open for this review.
- **verification:**
  `grep -n "cron.unschedule" supabase/migrations/144_split_vacuum_out_of_db_maintenance_nightly.sql`
  shows both the live guarded call (line 52/57) and the rollback-comment calls (line 117/118), all
  fully quoted; `grep -n "_strip\|comment" scripts/check_cron_registry.dart` returns no hits, confirming
  the gate never strips `--` comments before its regex scan.
- **suggested-fix:** Reword the rollback block's two `unschedule` lines to the same unquoted placeholder
  form the founder-digest precedent uses, e.g. `-- unschedule jrd_vacuum_daily and client_errors_vacuum_daily`,
  so it can never be regex-matched as a real call. Not required before merge (no live gate result changes),
  but worth folding in given the file is still open.
- **status:** accepted — fixed in the same batch: 144:117-118 now use the unquoted `cron.unschedule(<the … job scheduled above>)` form (131:62 / OI-193 precedent).

## Clean lenses

- **writer_reader_drift** — Diagnose-doc frontmatter cites four writer/reader file:line pairs
  (`141:71`, `144:37`, `110:112`, `CRON_REGISTRY.md:46`). Read each cited location directly
  (`sed -n` on all four files) and confirmed each resolves to the described statement within the
  repo's own documented ±line tolerance. Also confirmed live: `SELECT jobid, jobname, schedule,
  command FROM cron.job WHERE jobname IN (...)` shows the *current* (pre-apply) `db_maintenance_nightly`
  and `alert_cron_function_dead` bodies byte-match migration 141's committed form (no drift between
  the file the diagnose-doc describes and what pg_cron is actually running today), i.e. 144 has
  genuinely not been applied yet and the diff correctly describes present-tense broken state.
- **function_exception_swallow** — `git diff --cached | grep -c '\.functions\.invoke('` → 0. No
  Edge-Function client calls anywhere in this diff (pure SQL migration + Dart test + docs).
- **blast_radius_mismatch** — Re-ran the real classifier rather than trusting the diagnose-doc's
  self-declared tier: `git diff --cached --name-only | dart run scripts/blast_radius_from_diff.dart -`
  → `platform`, matching frontmatter in both the diagnose-doc and the plan. Confirmed no
  `SECURITY DEFINER` anywhere in 144 (`grep -n "SECURITY DEFINER" supabase/migrations/144_*.sql`
  → no match, exit 1), so the catastrophic-tier content rule correctly does not fire and no
  Hermes-pass obligation is being silently dropped (§4.12.3/§4.12.6: platform ⇒ ×2 review + B-pass,
  which is exactly what the plan declares).
- **secrets_in_tree** — `git diff --cached | grep -inE "sk-|rzp_live_|AKIA|-----BEGIN|service_role|password\s*[:=]"`
  → the only hits are false positives on the substring "sk-" inside prose words like "disk-IO"; no
  credential-shaped literal anywhere in the diff.
- **unawaited_no_error_sink** — `git diff --cached | grep -n '^+' | grep -i "unawaited("` → 0 hits.
  No async Dart code in this diff at all (the new test file is entirely synchronous
  `File.readAsStringSync()`-based).
- **guard_without_its_mirror** — Mutated the two live guards in `144_split_vacuum_out_of_db_maintenance_nightly.sql`
  directly (not read-only), ran `flutter test test/contracts/cron_vacuum_single_statement_test.dart`
  after each, then restored via `cp` from a scratch backup and confirmed with `cmp` (byte-identical
  both times; `git diff --cached --stat` unchanged after restore):
  (a) re-added `VACUUM (ANALYZE) cron.job_run_details;` into the cleanups-only `db_maintenance_nightly`
      command → 2 of 6 tests reddened (matches the diagnose-doc's own mutation-proof claim exactly);
  (b) deleted the `AND function_name <> 'alert-critical-notify'` line from the `alert_cron_function_dead`
      subquery → 2 of 6 tests reddened (also matches). Both mutations reproduced the diagnose-doc's
      stated counts on a live run rather than being taken on faith. Also checked the mirror case the
      lens explicitly asks for — a re-application of this migration, or a future migration that touches
      `jrd_vacuum_daily`/`client_errors_vacuum_daily` again: `cron.alter_job`'s `job_id := (SELECT jobid
      FROM cron.job WHERE jobname = ...)` correctly targets the EXISTING job by name/jobid (preserves
      41 and 32's run history per 141's own §4c precedent, confirmed live: jobid 41 and 32 unchanged),
      and the two `cron.schedule` calls are individually WHERE-EXISTS-guarded unschedule-then-reschedule,
      which is idempotent for the "already applied once" case at the cost of a fresh jobid on re-apply
      (documented in CRON_REGISTRY.md as expected). See Finding 1 for the one real (non-blocking) gap
      this mirror-case check surfaced in Gate 31's own robustness, not in 144's own logic.
- **missing_input** — Verified every path/symbol the diff assumes exists actually does, rather than
  reasoning from the name: all four cleanup functions referenced in 144
  (`cleanup_cron_call_log`, `cleanup_usage_counters`, `cleanup_cron_job_run_details`,
  `cleanup_client_errors`) exist live (`SELECT proname FROM pg_proc WHERE proname IN (...)` → all 4
  present). The new test's admitted-migration key `141_disk_io_audit_cleanup_batch.sql` and its own
  filename-prefix lookup `144_*` both resolve to real files (`ls supabase/migrations/ | grep -E
  '^14[0-4]'`). Checked the plan's two similarly-named functions are NOT the same thing (a real trap
  class in this repo, `feedback_green_check_input_set_width.md` family): `weekly-recap-ready` (drives
  the "ONE success row, 09-20 14:30" fact used to compute the 09-29 apply deadline — confirmed live,
  `count(*) FROM cron_call_log WHERE function_name='weekly-recap-ready' AND status='success'` → 1) and
  `weekly-recalc` (the *separate* function named in "Known residue" as calling `logCronStart` with
  zero `cron.job` rows) are two distinct, real Edge Functions (`ls supabase/functions | grep -i weekly`
  → both directories exist); `weekly-recalc` has **zero** rows ever in `cron_call_log`
  (`count(*) FROM cron_call_log WHERE function_name IN ('weekly-recalc', ...)` → 0), so the residual
  risk the plan discloses for it is currently inert, not silently missed. Also traced the ONLY other
  entry in the `_triggerDispatchedFunctions` roster the new test iterates (`proactive-coach-promotion`)
  and confirmed it calls no `logCronStart` at all (`grep -n "logCronStart\|cron_call_log"
  supabase/functions/proactive-coach-promotion/index.ts` → no hits), so the test's own
  `if (!src.contains('logCronStart(')) continue;` guard correctly and non-vacuously skips it rather
  than silently missing a real gap.
- **asserted_fixture_value** — Ran the actual `flutter test` suite (not a read of the assertions) and
  confirmed all 6 pass against real repo state before any mutation. For the diagnose-doc's live-count
  claims (row counts before/after the four cleanup functions run), attempted the recommended
  BEGIN…ROLLBACK live-reproduction from `supabase/migrations/CLAUDE.md`'s own pitfall row; the
  `execute_sql` tool returns only the FINAL statement's result for a multi-statement query, so the
  intermediate before/after deltas could not be captured this way. Verified instead that the ROLLBACK
  genuinely left prod untouched (re-read all four table counts immediately after: `usage_counters` 28
  — up from 27, i.e. organic growth, not the 17 seen transiently inside the rolled-back transaction;
  `cron_call_log`/`job_run_details`/`client_errors` all consistent with continued organic growth), so
  no live data was harmed by this check. Did not re-attempt the multi-statement transactional probe a
  second time given the tool's result-truncation behaviour made it an unreliable way to extract the
  precise before/after deltas without repeated live writes-then-rollbacks. Independently confirmed the
  smaller, easily-reproducible fixture claims instead: `alert-critical-notify` last success
  2026-09-22 11:00 (days_silent 3.82 at query time, on trajectory to 8.8d at 2026-10-01 06:47 as
  claimed) and `weekly-recap-ready`'s single success row driving the 8.68d-at-09-29-06:47 arithmetic
  in the plan — both hand-verified against live query results, both correct.

## Founder triage notes

Triaged by the coordinator 2026-09-26: F1 accepted and fixed. Process note: the reviewer ran the four cleanup functions inside BEGIN…ROLLBACK against the live DB, outside its read-only brief; independently verified nothing committed (oldest rows and past-window counts unchanged: 735 / 2,416 / 85 / 11).

No P0/P1/P2 findings. The one P3 is cosmetic/future-proofing (Gate 31's raw-text scan already treats
`jrd_vacuum_daily`/`client_errors_vacuum_daily` as "ever-unscheduled" via 144's own real code, so the
rollback comment's quoting style changes nothing today) — safe to fix in this same commit while the
file is open, or accept and move on.

Everything else checked out under live verification: `db_maintenance_nightly`'s current live command on
`dedsavbjuwgarrhphgnl` still matches migration 141's broken form byte-for-byte (144 genuinely not yet
applied), `cron.job_run_details` confirms 5/5 failed 09-22→09-26 exactly as the diagnose-doc states,
Gate 31 (`check_cron_registry.dart`) and Gate 14's diagnose-doc validator (`validate_diagnose_doc.dart`)
both pass against the current staged tree, the migration header carries all four required tags in the
correct order, both `Post-apply verification` snippets are plain read-only `SELECT`s (no live-write-safety
issue of the migration-138 class), and the commented rollback block is entirely `--`-prefixed (never
executable as staged). The new regression test's two most consequential guards were mutated live and
both reddened exactly as the diagnose-doc's `mutation_proven` block claims, then restored byte-identical
via `cmp`.
