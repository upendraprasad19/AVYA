---
reviewed_at: 2026-09-14T21:15:00+05:30
staged_against: 57b11b5c90cb
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 0
verdict: accepted
---

# Code Review — 57b11b5c90cb

Branch `telegram-admin-bot`, Task 6 third follow-up: migration 136
(`founder_metrics_ops()` — add `error_code is distinct from 'info'` to the
`client_errors_7d` subquery, mirroring migration 135's identical fix already
applied to `client_errors_today`). Already applied live with explicit
founder authorization (2026-09-14T20:41:30+05:30). This is a review of the
already-applied commit, not a gate on whether to apply it. Staged files: the
migration, the paired `backups/applied_migrations.json` entry, and a manual
SQL live-verification script.

## Method

1. **`blast_radius_mismatch` (SECURITY DEFINER hygiene).** Diffed the staged
   function body against the live `pg_get_functiondef('public.
   founder_metrics_ops()'::regprocedure)` pulled via MCP `execute_sql` — byte
   -identical modulo Postgres's canonical `timestamp with time zone` vs the
   source's `timestamptz` spelling (cosmetic, not a behavioural diff).
   `SET search_path TO 'public'` is present in the live definition, so the
   function is pinned and cannot be redirected by a caller-controlled
   `search_path`. Re-queried `has_function_privilege` for all three roles
   directly against the LIVE database (not trusted from the migration
   header's stated values): `anon=false`, `authenticated=false`,
   `service_role=true` — matches the migration's `REVOKE ALL ... FROM
   PUBLIC` + `GRANT EXECUTE ... TO service_role` and is unchanged from
   135/101's original scoping. `list_migrations` confirms `136_...` is the
   live-applied version (`20260914154130`), matching
   `applied_migrations.json`'s `cloud_version`.

2. **`guard_without_its_mirror`.** This migration is itself a mirror-fix
   (135 fixed `client_errors_today`, 136 fixes the sibling
   `client_errors_7d` subquery in the same function). Checked for a THIRD
   site with the same `error_code='info'` inflation that neither migration
   catches:
   - `supabase/migrations/102_admin_metrics_daily_snapshot.sql` — the
     `admin_metrics_daily.client_errors_today/_7d` columns are populated
     FROM `founder_metrics_ops()`'s own return values (confirmed by reading
     `compute-admin-metrics-daily/index.ts:108-109`, which reads
     `ops.client_errors_today` / `ops.client_errors_7d` off the RPC result
     and persists them verbatim) — inherits the fix automatically, not an
     independent site.
   - `supabase/functions/telegram-admin-bot/index.ts:481` (`cmdErrors`) —
     a genuinely separate, direct `.from("client_errors")` query (the
     `/errors` Telegram command). Read the full function
     (`index.ts:472-520`): it already excludes `error_code === 'info'`
     AND re-includes failure-shaped `'event'`-coded rows via the same
     regex pattern 087 uses on the cron-alert side (documented in-file as
     "R2-02", i.e. already fixed in an earlier round of this same branch's
     review). Not a missed mirror — already correctly handled, and more
     completely than `founder_metrics_ops()` itself (it excludes both
     `'info'` and non-failure `'event'`, where `founder_metrics_ops()`
     still only excludes `'info'` — a pre-existing, already-documented gap
     from the 2026-09-14(c) tuning entry below, not new to this diff).
   - `086_alert_client_errors_spike_tune.sql` / `087_...reinclude_failure_
     events.sql` (the hourly spike-alert cron) — independent site, already
     excludes both `'event'` and `'info'` with the same failure-shaped
     re-inclusion regex; untouched by and unaffected by this migration.
   - `proactive-coach-promotion/index.ts:340` — an INSERT into
     `client_errors` (writes telemetry), not a count/read site; not in
     scope for this lens.
   No third undetected mirror found. The one asymmetry that exists
   (`founder_metrics_ops()` excludes only `'info'`, not `'event'`, while
   086/087/`cmdErrors` exclude both) is the SAME gap already surfaced and
   accepted as P2/pre-existing by the 2026-09-14(c) review entry for
   migration 135 — 136 doesn't introduce or worsen it; it's an
   already-tracked, non-regression scope boundary, not a fresh finding.

3. **`asserted_fixture_value`** (new SQL verify file). Cross-checked every
   literal against live schema/constraints, not reasoned from the migration
   alone:
   - `client_errors` columns present per `backups/live_schema_columns.json`:
     `id, user_id, error_code, error_message, op_type, retry_count,
     client_version, platform, created_at` — the test file's INSERT column
     list (`op_type, error_code, client_version, platform, created_at`) is a
     subset of real columns, none invented (this is exactly the class of
     bug 073/078 hit with fabricated columns, cited and avoided here).
   - NOT NULL checks: `018_client_errors.sql` originally made `user_id`
     NOT NULL, but `119_client_errors_nullable_user_id_for_preauth.sql`
     drops that constraint — so the test file's omission of `user_id`
     (leaving it NULL) is valid against the CURRENT (not original) schema.
     `error_code`, `client_version`, `platform` are NOT NULL and the test
     supplies all three on both INSERTs. `op_type` has no NOT NULL
     constraint; also supplied anyway.
   - The two INSERTed rows (`error_code='info'` for the no-op case,
     `error_code='minified:x'` for the must-count case) exercise the
     positive AND negative path per rule 21/lens-8's "would this pass if
     the feature did nothing at all?" question — an all-'info' test would
     have been vacuous; this one also asserts the real-error row moves the
     count, and separately re-asserts `client_errors_today` (135's earlier,
     different fix) is unregressed by 136 — a genuine third assertion, not
     restated padding.
   - Executed-value sanity: 135's own live-verify file (run ~58 min
     earlier) recorded `baseline_7d=143`; 136's records `baseline_7d=140`.
     A net decrease over ~1h on an append-only-except-cron-retention table
     is possible — `client_errors` has no ad hoc deletes (only a 30-day-old
     retention job per `121_log_table_retention.sql`, far outside a 7-day
     window) — via ordinary rolling-window aging (rows falling out the back
     of the 7-day window faster than new ones arrive at a given moment).
     Not itself checkable after the fact without re-querying at the exact
     historical instant, and not a claim this review can falsify or that
     the migration's correctness depends on — flagged here only so the
     reasoning is recorded, not left as an unexamined discrepancy. Does not
     rise to a finding: it's informational post-apply logging, not an
     assertion the migration or its correctness relies on.
   - Citation check: the migration's header claims its body is "135's body
     verbatim... with ONLY the `client_errors_7d` subquery changed." Diffed
     135's staged body (read from `supabase/migrations/
     135_founder_metrics_ops_exclude_info_client_errors.sql`) against 136's
     — confirmed true: the `client_errors_today` subquery, `alerts`,
     `cron_call_log` subqueries, and the `RETURNS TABLE`/grant footer are
     byte-identical; only the `client_errors_7d` subquery gained the
     `and error_code is distinct from 'info'` clause.

4. **`missing_input`.** The migration's claim that "085/086/087 already
   established" the exclusion pattern, and that 135 is "the highest-numbered
   migration that defines `founder_metrics_ops()`" — verified both exist and
   say what's claimed (086/087 read and confirmed above; 135 confirmed via
   `list_migrations` as the migration immediately preceding 136 for this
   function, with no intervening redefinition — `grep -l
   founder_metrics_ops supabase/migrations/*.sql` returns only 093 (create),
   101 (redefine, cited by 135 as the prior definition), 135, 136). The two
   citations this migration's own header makes (086/087 pattern; 135 as
   verbatim base) both check out against the actual files, not just the
   prose.

5. **`writer_reader_drift` / `unawaited_no_error_sink` / `secrets_in_tree` /
   `function_exception_swallow`.** No Hive writes, no `functions.invoke(`
   calls, no `unawaited(`, and no credential-shaped literals anywhere in
   the staged diff (a pure SQL migration + a JSON metadata record + a
   manual verification script) — all four lenses are structurally
   inapplicable to this diff's content, confirmed by reading every line of
   the three files rather than assumed from the file types.

## Findings

None. Zero findings across all 8 lenses, each backed by a live-state check
(MCP `execute_sql`/`list_migrations`) or a real-file cross-reference rather
than a read of the migration's own prose.

## Founder triage notes
<filled in by founder during triage>
