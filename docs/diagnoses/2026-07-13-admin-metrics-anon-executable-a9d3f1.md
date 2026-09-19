---
bug_id: a9d3f1
date: 2026-07-13
batch: admin-dashboard
blast_radius: catastrophic
status: fixed
symptom: >
  The three public.founder_metrics_*() SECURITY DEFINER functions (migration
  101) were EXECUTE-able by the anon and authenticated roles. Because they are
  SECURITY DEFINER (they count across all users, bypassing RLS), any anonymous
  caller could POST /rest/v1/rpc/founder_metrics_ops (etc.) and read live
  aggregate business metrics (total users, PRO counts, error counts, open-alert
  counts). Caught by the migration-101 post-apply privilege verification
  (has_function_privilege('anon', ...) returned true).
concept: admin_dashboard_metrics_snapshot
sot_registry_entry: admin_dashboard_metrics_snapshot
writers:
  - { file: supabase/migrations/103_admin_metrics_revoke_from_roles.sql, line: 33, source: "revoke execute on function public.founder_metrics_for_admin_api() from anon, authenticated" }
  - { file: supabase/migrations/101_admin_dashboard_metrics_functions.sql, line: 36, source: "create ... public.founder_metrics_for_admin_api() security definer (the over-granted function)" }
readers:
  - { file: supabase/functions/admin-dashboard-data/index.ts, line: 197, source: "admin.rpc('founder_metrics_for_admin_api') — the intended service-role-only caller" }
hive_key_prefix: n/a
hive_key_formula: n/a
sync_methods: n/a
restore_methods: n/a
cloud_table: admin_metrics_daily
cloud_columns: [id, snapshot_date, total_users, signups_today_ist, signups_7d, signups_30d, pro_active, pro_expired, free_users, active_subscriptions, active_last_7d, workouts_logged_today, food_logs_today, ai_messages_today, streak_maintained_current_week, client_errors_today, client_errors_7d, open_alerts_count, cron_failures_24h, computed_at]
contract_test_path: test/contracts/admin_metrics_functions_role_revoke_test.dart
ist_handling: n/a
provider_invalidations: n/a
telemetry_op_types: n/a
cross_account_guard: >
  This bug WAS a cross-account exposure — the SECURITY DEFINER functions
  aggregate across every user's rows. The guard is that ONLY service_role may
  execute them; the anon/authenticated grants defeated that. Fixed by revoking
  from the roles (migration 103), leaving proacl = {postgres, service_role}.
forbidden_patterns_checked: >
  Confirmed no OTHER public SECURITY DEFINER function created in THIS batch was
  left anon/authenticated-executable. Note: many EXISTING public SECURITY
  DEFINER functions ARE intentionally authenticated-executable (they are the
  app's RPCs, e.g. increment_promo_used_count) — so a blanket source-grep gate
  is NOT viable; the distinguishing signal is intent, not syntax.
proposed_fix: >
  Migration 103 revokes EXECUTE on all three functions from anon + authenticated
  explicitly (REVOKE FROM PUBLIC does not remove Supabase's platform default
  direct-to-role grants). End-state proacl = {postgres=X, service_role=X}.
regression_test_planned: >
  test/contracts/admin_metrics_functions_role_revoke_test.dart pins migration
  103's role-revokes in the committed source (comment-stripped). The LIVE
  privilege state (anon/authenticated execute = false) is verified out-of-band
  at apply time (§6 tier 8) — a unit test can't reach the live catalog.
touched_layers_checked:
  - { layer: postgres_schema, status: fixed_in_this_batch, evidence: "pg_proc.proacl for all 3 functions = {postgres=X/postgres,service_role=X/postgres} after migration 103" }
  - { layer: postgres_privileges_rls, status: verified, evidence: "has_function_privilege('anon'|'authenticated', fn, 'execute') = false; service_role = true (live query 2026-07-13)" }
  - { layer: migrations_applied, status: fixed_in_this_batch, evidence: "103 applied live + recorded in backups/applied_migrations.json" }
  - { layer: edge_function_code, status: verified, evidence: "read EF calls the functions as service_role (SUPABASE_SERVICE_ROLE_KEY); unaffected by the role revoke" }
  - { layer: client_code, status: not_applicable, evidence: "no client change — the functions were never meant to be client-reachable" }
impact_analysis: >
  Exposure window: from migration 101 apply until migration 103 apply — a few
  minutes on 2026-07-13, entirely within this batch's own apply sequence,
  before any client could call it (the Flutter client isn't live until the
  post-merge web rebuild) and before the functions were announced anywhere.
  Data at risk was AGGREGATE COUNTS only (no per-user PII — the functions
  return counts, not rows). No anon call was possible in practice during the
  window (the rpc endpoints were not referenced by any deployed client). Net
  real-world exposure: none; the class, however, is catastrophic (an
  anon-readable SECURITY DEFINER function over all-user data) and is why the
  live post-apply privilege check is mandatory.
---

# Anon-executable SECURITY DEFINER admin functions (a9d3f1)

## Root cause

Migration 101 created `public.founder_metrics_{for_admin_api,engagement,ops}()`
with the same lockdown as migration 093 — `REVOKE ALL FROM PUBLIC` +
`GRANT EXECUTE TO service_role`. That lockdown is **sufficient in the `private`
schema** (093's home) because PostgREST never routes to `private`, so the
function is unreachable regardless of grants. It is **NOT sufficient in
`public`**: Supabase provisions every project with platform-level default
privileges that `GRANT EXECUTE` on new public-schema functions **directly to the
`anon` and `authenticated` roles** (not via `PUBLIC`). `REVOKE ... FROM PUBLIC`
does not touch a direct-to-role grant, so both roles retained EXECUTE. The
`pg_proc.proacl` made it unambiguous: `{postgres=X/postgres, anon=X/postgres,
authenticated=X/postgres, service_role=X/postgres}` — `anon=X` is a direct grant.

This is the [[feedback_revoke_from_public_not_role]] trap in its **inverse**
form: the classic case is "you revoked from the role but PUBLIC still holds it";
here it is "you revoked from PUBLIC but the role holds it directly."

## Why the reviews missed it (and the live check caught it)

The Hermes L23 lens checked for `ALTER DEFAULT PRIVILEGES` across all migrations
and found none — correctly, because the grant comes from Supabase's
**platform-level** defaults, which are NOT in any migration file. Static review
of the migration source cannot see it. The **§6 multi-tier post-apply privilege
check** (tier 8) — `has_function_privilege('anon', ...)` against the LIVE
catalog — is the only thing that surfaces it, which is exactly why it is a
mandatory apply-time step. It caught this within the batch's own apply sequence.

## Fix

Migration 103: `REVOKE EXECUTE ON FUNCTION public.<fn>() FROM anon, authenticated`
for all three. Verified live: proacl now `{postgres=X, service_role=X}`;
`has_function_privilege` = false for anon/authenticated, true for service_role.

## Prevention

- **Process (primary):** after applying ANY migration that creates a
  service-role-only public SECURITY DEFINER function, run the live privilege
  check — `has_function_privilege('anon'|'authenticated', fn, 'execute')` must be
  false. Added to `supabase/migrations/CLAUDE.md` pitfalls.
- **Source pin:** `test/contracts/admin_metrics_functions_role_revoke_test.dart`
  fails if migration 103's role-revokes are removed.
- A blanket gate is deliberately NOT added: most public SECURITY DEFINER
  functions are legitimately authenticated-executable app RPCs, so syntax can't
  distinguish "admin-only" from "app RPC" — the live check is the real guard.
