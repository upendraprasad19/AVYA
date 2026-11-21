---
reviewed_at: 2026-09-14T20:15:00+05:30
staged_against: c0ea56c3d0e5
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 2
verdict: accepted
---

# Code Review — c0ea56c3d0e5

Staging hash originally confirmed by the dispatched reviewer as
`5eb09cde42a2` against the diff at that time. After that review, the
orchestrating session corrected Finding 1 below (an overclaim in
migration 135's own header comment) by editing `docs/audit/open_issues.md`
(filing OI-200) and the diagnose-doc instead of the migration file
itself — migration 135 was already applied live and is immutable per
`supabase/migrations/CLAUDE.md` — and staging a `docs/audit/OPEN_INDEX.md`
auto-regen the pre-commit hook produced on an earlier failed attempt.
Both moved the hash. The dispatched reviewer's SKILL.md §3 protocol
(followed verbatim) states only `docs/reviews/` is excluded from the
gate's hash — this is now STALE documentation: `check_code_review_pass_
exists.dart`'s own header comment (OI-162 slice 4 addendum, 2026-09-11)
records that `.claude/skills/code-review/SKILL.md` is ALSO excluded, for
the identical self-reference reason (its own required §5.1 tuning entry
would otherwise move the hash on every catastrophic review). Two
generations of this session's own renames (`0f340b489139`, then
`20b400c500d8`) were driven by exactly this stale-documentation gap —
SKILL.md edits were believed to move the hash and were being chased
iteratively, when the real gate ignores SKILL.md's content entirely.
Recomputed correctly per the gate's actual exclusion set
(`':(top,exclude)docs/reviews' ':(top,exclude).claude/skills/code-review/
SKILL.md'`) and landed on this filename, which now needs no further
renames regardless of what else is edited in SKILL.md. This file was
renamed 4 times total (`5eb09cde42a2` → `0f340b489139` → `d71012062873` →
`20b400c500d8` → `c0ea56c3d0e5`) before landing on the correct one. The
findings below are unaffected by any of the renames — see the Founder
triage notes for the resolution. Filed as a SKILL.md doc-accuracy note
in the Tuning history entry below, since §3's protocol text (the part
every dispatched reviewer actually reads) is the thing that is wrong,
not just this file's own comment.

Blast-radius confirmed via `git diff --cached --name-only | dart run scripts/blast_radius_from_diff.dart -`: **catastrophic** (content-rule forced — `supabase/migrations/135_founder_metrics_ops_exclude_info_client_errors.sql` contains `SECURITY DEFINER`).

Scope: this migration is **already applied live** to `dedsavbjuwgarrhphgnl` with explicit founder authorization (per the batch's own framing). This review audits the commit of that already-applied change, not whether to apply it.

## Finding 1 — P2 — blast_radius_mismatch / guard_without_its_mirror

- **file:line:** `supabase/migrations/135_founder_metrics_ops_exclude_info_client_errors.sql:1-8` (header claim), `:31` (the added predicate)
- **claim:** The migration's own header says it "Mirrors the exclusion pattern migrations 086/087 already established on the alert-spike side," but it implements only **half** of that pattern. 086/087 exclude **both** `error_code = 'event'` and `error_code = 'info'` from the alert-spike cron's count (087 additionally re-includes failure-shaped `event` rows via an `op_type` regex, because `ErrorTelemetry.logEvent` hardcodes `error_code='event'` for a very high-volume mix of benign breadcrumbs — `restore_op_done` ×3581 per 087's own comment — and real failures). Migration 135 adds only `and error_code is distinct from 'info'` to `founder_metrics_ops()`'s `client_errors_today` subquery; it does **not** exclude `'event'`.
  Live-verified right now (2026-09-14, post-apply): `select error_code, count(*) from public.client_errors where created_at >= <IST-today-start> group by error_code` returns `{event: 4, info: 2}` — **zero real error codes today**. `client_errors_today` therefore currently evaluates to **4** (all `'event'`-coded breadcrumbs; the 2 `'info'` rows are correctly excluded), not 0. The founder-facing "Client errors today" figure in `/status` (telegram-admin-bot) and the admin dashboard is still inflated by exactly the breadcrumb-noise class 086/087 exist to filter — this migration closes the *new* inflation source (134's `'info'`-coded success telemetry) but not the pre-existing, much larger one (`ErrorTelemetry.logEvent`'s `'event'` code, used across `ai_service.dart`, `guarded_box.dart`, `hive_user_session.dart`, `auth_session_bootstrapper.dart`, etc.).
  This is **not a regression** — `'event'` rows were already counted in `client_errors_today` before this migration, so 135 does not make anything worse — but the header's citation of 086/087 as the mirrored precedent overstates what was actually done, and the migration's own stated goal ("`client_errors_today` count must not include [noise]") is only partially achieved.
- **verification:**
  ```sql
  -- live, dedsavbjuwgarrhphgnl, 2026-09-14
  select error_code, count(*) from public.client_errors
  where created_at >= (date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata')
  group by error_code order by 2 desc;
  -- => event: 4, info: 2
  ```
  and `grep -n "error_code.*'event'" lib/core/services/error_telemetry.dart:332` confirms the client hardcodes `'event'` for `logEvent`.
- **suggested-fix:** Not urgent (informational metric, no functional/security impact) — but worth a follow-up migration that either (a) excludes `'event'` the same way `'info'` is now excluded, mirroring 086's simpler cut, or (b) reuses 087's op_type-regex re-inclusion so genuine `'event'`-coded failures still count while breadcrumbs don't. Either way, correct the header's "mirrors 086/087" claim to state precisely which half is mirrored, or complete the mirror.
- **status:** accepted — real, live-reproducible gap, but pre-existing (not a regression introduced by this diff), non-blocking, cosmetic on a founder-only ops metric. Tracked here for a founder-scheduled follow-up rather than fixed in-place, since fixing it changes live behavior of an already-applied, already-founder-authorized migration and deserves its own explicit go per CLAUDE.md §4.3.

## Finding 2 — P3 — asserted_fixture_value (documentation-only)

- **file:line:** `test/sql/founder_metrics_ops_excludes_info_client_errors_live_verify.sql:8-12`
- **claim:** The sentence "Run against the live project inside a transaction that always rolls back." is duplicated verbatim — once at line 8 (standalone) and again folded into the longer sentence at lines 10-12 ("Run against the live project inside a transaction that always rolls back, same pattern as..."). Harmless (a manual verification script, not executed by any gate), but reads as an unresolved edit.
- **verification:** `grep -n "Run against the live project" test/sql/founder_metrics_ops_excludes_info_client_errors_live_verify.sql` → two hits, lines 8 and 10.
- **suggested-fix:** Delete the standalone line 8; keep the fuller sentence at 10-12.
- **status:** accepted — cosmetic, non-blocking; harmless duplicate prose in a manual (non-gated) verification script.

## What else was checked and came back clean

- **SECURITY DEFINER hygiene (blast_radius_mismatch lens, primary check):** `search_path` is pinned (`SET search_path = public`), matching migration 101's original definition. Live-verified via `pg_get_functiondef('public.founder_metrics_ops()'::regprocedure)` — the deployed function body is **byte-identical** (module whitespace normalization aside) to the staged migration's `CREATE OR REPLACE FUNCTION` block. Live ACLs re-verified independently (not trusted from the migration's own note): `has_function_privilege('anon', ..., 'execute') = false`, `('authenticated', ...) = false`, `('service_role', ...) = true` — unchanged from before the migration, correctly scoped to `service_role` only.
- **Rollback block correctness:** the commented-out rollback `CREATE OR REPLACE FUNCTION` at the end of the migration was diffed by eye against migration 101's original body (before 135's added predicate) — matches exactly, including the unchanged `client_errors_7d`/`open_alerts_count`/`cron_failures_24h` subqueries and the `REVOKE`/`GRANT` pair.
- **`applied_migrations.json` pairing (§4.5):** the new entry's `cloud_version: "20260914141301"` was cross-checked against `list_migrations` on the live project — the version string and name (`135_founder_metrics_ops_exclude_info_client_errors`) both match exactly. The `diagnose: "82b018"` reference resolves: `docs/diagnoses/2026-09-14-telegram-admin-bot-whole-branch-review-round1-fixes-82b018.md` exists.
- **`asserted_fixture_value` on the new SQL verify file's real-schema claims:** `public.client_errors`'s live columns (`backups/live_schema_columns.json` → `tables.client_errors`) are `id, user_id, error_code, error_message, op_type, retry_count, client_version, platform, created_at` — every column the test file's two `INSERT`s reference (`op_type, error_code, client_version, platform, created_at`) exists. Checked the historical NOT NULL trail too, since the migration-133/134 diagnose-doc's own header explicitly warns about wrong-column P0s in this exact table: migration `018_client_errors.sql` originally declared `user_id text NOT NULL`, which would make migration 134's `user_id: NULL` telemetry inserts fail — but `119_client_errors_nullable_user_id_for_preauth.sql` dropped that constraint (diagnose `b6e4f2`, verified by reading the migration, not assumed from the column list alone), so the inserts are valid. `client_version`/`platform` are still `NOT NULL` and both the test file's inserts and migration 134's own inserts supply non-null values for both.
- **writer_reader_drift:** `founder_metrics_ops()`'s `client_errors_today` field is read by 4 sites (`telegram-admin-bot/index.ts:158/168`, `admin-dashboard-data/index.ts:199`, `compute-admin-metrics-daily/index.ts:108/135`, `lib/features/admin/models/admin_dashboard_data.dart:82/176`) — all pass the numeric value through unmodified (formatting/parsing only), none assert a fixture literal that this migration's changed count would break. `telegram-admin-bot/index_test.ts`'s only `founder_metrics_ops` fixture (`cmdStatus` test, line 187) stubs `open_alerts_count`/`cron_failures_24h`, not `client_errors_today` — unaffected.
- **function_exception_swallow / unawaited_no_error_sink / secrets_in_tree:** N/A — no `.functions.invoke(`, no `unawaited(`, no credential-shaped literal anywhere in this 3-file diff (pure SQL + a JSON metadata record).
- **missing_input:** the migration's function body is asserted (in its own header) to be copied verbatim from `101_admin_dashboard_metrics_functions.sql` with one predicate added — confirmed by direct comparison of both files' `founder_metrics_ops()` bodies (identical apart from the added `and error_code is distinct from 'info'` line).

## Founder triage notes

Finding 1 is real and live-reproducible (`client_errors_today` currently reads 4, not 0, for a day with zero actual errors), but it is a pre-existing condition this migration does not worsen, and the fix it *does* ship (excluding the new `'info'` inflation from migration 134) is correct and complete for its own stated scope. Recommend `verdict: accepted` once triaged — this is not blocking given (a) no P0/P1, (b) the P2 is informational/cosmetic on an internal founder-only ops tool, not a security or data-integrity issue, and (c) the fix as shipped does what its own narrow intent states, even though the header's precedent-citation overstates it. Whether to complete the `'event'` exclusion in a follow-up is a founder call, not a blocker for this commit.
