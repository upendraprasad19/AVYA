---
bug_id: c9b3e2
date: 2026-06-11
batch: audit-2026-06-10
status: fixed
blast_radius: platform
symptom: >
  The quarterly audit's live-DB pass (Supabase security advisor + pg_proc inspection)
  found several SECURITY DEFINER functions in schema public that were EXECUTE-able by
  the anon and/or authenticated roles over PostgREST (/rest/v1/rpc/<fn>). Because
  SECURITY DEFINER bypasses RLS, this was a privilege-escalation / revenue surface:
  an UNauthenticated caller could POST /rest/v1/rpc/extend_subscription with any
  user_id + days to grant any account free PRO; redeem_referral_atomic to mint free
  referral days; increment_promo_used_count to tamper promo counters; and
  update_streak_progress (which takes p_user_id as an arg) to write ANY user's streak
  state (cross-account write).
concept: security_definer_function_exposure
sot_registry_entry: subscription_state
writers: >
  Postgres functions (definers). Legit callers verified by grep of lib/ + supabase/
  functions/: increment_promo_used_count ← verify-payment + razorpay-webhook EFs
  (service_role); redeem_referral_atomic ← redeem-referral EF (service_role);
  extend_subscription ← NO caller in repo (admin/manual via service key);
  update_streak_progress ← NOT invoked by literal RPC name anywhere (referenced only
  in comments in streak_progress_service.dart / workout_repository.dart). The four
  trigger functions (auto_approve_community_item, update_user_subscription_status,
  handle_new_auth_user, rls_auto_enable) fire from triggers, never via RPC.
readers: >
  PostgREST exposes every public-schema function as an RPC endpoint; the anon and
  authenticated API roles could call them directly. service_role (Edge Functions /
  cron) retains EXECUTE and is unaffected by the revoke.
hive_key_prefix: not_applicable
hive_key_formula: "not_applicable (Postgres GRANT/RLS hardening; no Hive key)"
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: "subscriptions, user_progress, promo_codes, referral_redemptions (the tables the exposed functions wrote)"
cloud_columns: not_applicable (no column change — EXECUTE grant + function-body guard)
contract_test_path: test/contracts/security_definer_revoke_migration_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: true
forbidden_patterns_checked:
  - "anon/authenticated EXECUTE on extend_subscription/redeem_referral_atomic/increment_promo_used_count + 4 trigger fns — REVOKED FROM PUBLIC in migration 091. (090's `REVOKE FROM anon, authenticated` was a NO-OP: EXECUTE is inherited from PUBLIC; the role-specific revoke does nothing while PUBLIC holds the grant — caught by the live post-apply has_function_privilege check.)"
  - "update_streak_progress writable cross-account (p_user_id arg, SECURITY DEFINER) — REVOKED FROM PUBLIC + re-GRANTed to authenticated (self-write) in 091; body raises when auth.uid() IS NOT NULL AND p_user_id <> auth.uid() (090)."
  - "function_search_path_mutable on 10 SECURITY-relevant functions — fixed inclusive search_path (090)."
proposed_fix: >
  Migration 090: REVOKE EXECUTE FROM anon, authenticated on the service-only / dead /
  trigger functions (extend_subscription, redeem_referral_atomic,
  increment_promo_used_count, cron_call_log_cleanup_7d, auto_approve_community_item,
  update_user_subscription_status, handle_new_auth_user, rls_auto_enable). For
  update_streak_progress: REVOKE FROM anon (block unauthenticated) but KEEP authenticated
  (the optimistic-lock self-write path) and CREATE OR REPLACE the body with an
  auth.uid() cross-account guard (service_role / cron, auth.uid() IS NULL, pass through).
  Plus search_path hardening (broad inclusive fixed path) on the 10 advisor-flagged
  functions. service_role keeps EXECUTE everywhere. Founder-console items NOT in code:
  leaked-password protection toggle + public-bucket (avatars/banners) listing policy.
regression_test_planned: >
  test/sql/security_definer_anon_revoke.sql — live post-apply assertions via MCP
  (has_function_privilege false for anon/authenticated on the revoked fns; authenticated
  retained on update_streak_progress; cross-account guard present in the body;
  service_role retained; search_path set). test/contracts/security_definer_revoke_migration_test.dart
  — CI source-grep pinning the REVOKE statements + the guard in migration 090 so the
  hardening can't silently regress in the repo. Post-apply: re-run get_advisors(security)
  → the anon-exec SECURITY DEFINER findings clear.
touched_layers_checked:
  - { tier: 3, layer: postgres_schema, status: fixed_in_this_batch, evidence: "migrations 090 (guard + search_path) + 091 (REVOKE FROM PUBLIC + GRANT) applied live; post-apply has_function_privilege confirms anon/authenticated CANNOT exec the service-only fns + service_role CAN; advisor re-run cleared 15/16 anon-exec + all 9 search_path findings" }
  - { tier: 8, layer: rls_policies, status: verified, evidence: "SECURITY DEFINER bypasses RLS — closed at the EXECUTE-grant + function-body layer; legit callers (EFs via service_role) verified by grep, unaffected" }
  - { tier: 10, layer: secrets_api_keys, status: verified, evidence: "morning_alert_get_service_key (vault reader) search_path set with inclusive path incl vault — no body break" }
  - { tier: 12, layer: client_server_contract, status: verified, evidence: "no client .rpc() call to any revoked function (grep lib/ — only comments); authenticated retained on update_streak_progress for the self-write path" }
impact_analysis: >
  Platform blast radius — the exposed extend_subscription let any unauthenticated actor
  grant free PRO to any account (direct revenue impact); update_streak_progress let any
  authenticated user write any other user's streak. The fix is a pure REVOKE +
  function-body guard with NO legit caller broken (verified: EFs use service_role which
  retains EXECUTE; no client RPC to these functions exists). Found via the live security
  advisor + independent pg_get_functiondef confirmation. Live apply is founder-authorized
  (own explicit go) per the prod-apply rule. related: WI-1 server-seam gate (the previous
  audit's class of live-prod-only contract bugs invisible to static scans).
---

# Anon-executable SECURITY DEFINER functions — privilege escalation / free-PRO (c9b3e2)

## What happened
The quarterly audit's live-DB pass ran the Supabase security advisor and inspected
`pg_proc`. Several `SECURITY DEFINER` functions in `public` were callable by the `anon`
(unauthenticated) and/or `authenticated` API roles via `/rest/v1/rpc/<fn>`. Because
`SECURITY DEFINER` runs as the definer and **bypasses RLS**, this exposed:
- `extend_subscription(user_id, days)` — anyone grants any account **free PRO**.
- `redeem_referral_atomic(...)` — anyone mints free referral days.
- `increment_promo_used_count(code)` — promo-counter tampering.
- `update_streak_progress(user_id, …)` — **cross-account streak writes** (takes `user_id`).

## Root cause
PostgREST exposes every `public` function as an RPC, and PostgreSQL grants `EXECUTE` to
`PUBLIC` (→ `anon`/`authenticated`) by default unless explicitly revoked. The RLS
lockdown migrations (052–055) hardened table RLS but never revoked function EXECUTE, and
`SECURITY DEFINER` functions ignore RLS anyway.

## Fix (migration 090, founder-authorized live apply)
- REVOKE EXECUTE FROM anon, authenticated on the service-only / dead / trigger functions.
- `update_streak_progress`: revoke anon; keep authenticated; add an `auth.uid()`
  cross-account guard in the body (service_role/cron pass through on null uid).
- `search_path` hardening on the 10 advisor-flagged functions (inclusive fixed path).
- service_role keeps EXECUTE → Edge Functions + cron unaffected (verified by grep).

## Verification
- `test/sql/security_definer_anon_revoke.sql` (live, post-apply) — grants closed, guard present.
- `test/contracts/security_definer_revoke_migration_test.dart` (CI source-grep).
- Re-run `get_advisors(security)` post-apply → anon-exec findings clear.

## NOT code-fixed (founder console)
- Auth → leaked-password protection (HaveIBeenPwned) toggle.
- Storage → tighten `avatars`/`banners` public-bucket broad SELECT (listing) policy.
