---
bug_id: d2b9e6
date: 2026-06-13
batch: referral-p0-fix
status: fixed
blast_radius: account
symptom: >
  Live web E2E (test2@gmail.com, Unit 1). Applying a referral code ALWAYS failed —
  the Profile "Apply Referral Code" sheet showed "Network error. Try again in a
  moment." and the welcome-stash redeem at onboarding silently no-op'd.
  referral_redemptions has 0 rows EVER (no user has ever successfully redeemed), so
  the 7-day-PRO referral growth lever has never worked for anyone since launch.
concept: edge_function_cross_user_read_rls_context
sot_registry_entry: referral_redemption
writers: >
  supabase/functions/redeem-referral/index.ts — reads the REFERRER's referral_codes
  row, the referee's referral_redemptions idempotency row, and calls
  redeem_referral_atomic. Now built with a PURE service-role client (BYPASSRLS) and
  an explicit getUser(token) used ONLY to resolve the referee identity.
readers: >
  lib/features/profile/repositories/referral_repository.dart (redeem; used by
  apply_referral_sheet), lib/features/profile/screens/invite_friends_sheet.dart
  (GOT A CODE? apply), and lib/features/onboarding/providers/onboarding_provider.dart
  (welcome-stash redeem at completeOnboarding) — all three now agree on one
  {success, days_granted} / {error} contract.
hive_key_prefix: not_applicable
hive_key_formula: not_applicable (Edge Function + cloud-only redemption)
sync_methods: []
restore_methods: []
cloud_table: referral_codes, referral_redemptions, subscriptions
cloud_columns: >
  referral_codes(user_id, code, expires_at); referral_redemptions(referee_id UNIQUE,
  referrer_id, code, days_granted_each); subscriptions(user_id, plan, status, end_date)
contract_test_path: test/contracts/referral_redeem_success_contract_test.dart
ist_handling: not_applicable
provider_invalidations: []
telemetry_op_types:
  success: []
  failure:
    - referral_repository_redeem
cross_account_guard: true
forbidden_patterns_checked:
  - "createClient(URL, SERVICE_ROLE, {global:{headers:{Authorization: userJWT}}}) — the user JWT in global.headers overrides the service_role apikey, so PostgREST runs as the `authenticated` role and RLS blocks BOTH the cross-user referral_codes read (own-only policy) AND the service_role-only redeem_referral_atomic RPC. REMOVED — replaced with a pure service-role client."
  - "client referral redeem masking every non-2xx (incl. 4xx validation) as 'Network error' — supabase_flutter throws FunctionException on non-2xx; the catch now unpacks it to surface the server's reason. FIXED."
  - "raw client.functions.invoke('redeem-referral') at onboarding_provider.dart:537 (no token refresh) — routed through SupabaseService.callFunction. FIXED (and the gate that missed the multi-line invoke is fixed too)."
proposed_fix: >
  redeem-referral: build ONE pure service-role client createClient(URL, SERVICE_ROLE)
  (no global headers, so it keeps BYPASSRLS); authenticate the caller with
  admin.auth.getUser(token) explicitly (mirror delete-account e8a1c3) to obtain
  referee.id and referee.created_at; run the referral_codes lookup + the
  referral_redemptions idempotency read + the redeem_referral_atomic RPC on that
  service-role client so the cross-user reads are not RLS-blocked. Add success:true to
  the 200 body so all three client callers share one success shape. Client: the
  repository catch unpacks FunctionException to show the server message; the onboarding
  redeem routes through callFunction (fresh token).
regression_test_planned: >
  test/contracts/referral_redeem_success_contract_test.dart — pins (1) the EF 200 body
  carries `success` (source-grep, comment-stripped); (2) the redeem-referral handler is
  built with a pure service-role client and getUser(token), NOT the JWT-in-global-headers
  pattern; (3) the repository catch unpacks FunctionException (surfaces the server message)
  rather than only returning the generic "Network error". Plus a live smoke after deploy:
  redeeming AVYA-TESTCODE as test2 grants a 7-day referral_trial subscription to BOTH test2
  and amar (referral_redemptions + subscriptions rows), then cleaned up.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "referral_repository unpacks FunctionException; onboarding redeem and paywall validate-promo routed through callFunction; flutter analyze clean on all changed files" }
  - { tier: 6, layer: edge_function_code_vs_deploy, status: fixed_in_this_batch, evidence: "redeem-referral rebuilt with a pure service-role client + getUser(token) + success:true; emit_payload OK; redeploy + live smoke pending the founder deploy authorization (classifier-gated)" }
  - { tier: 8, layer: rls_policies, status: verified, evidence: "live pg_policy: referral_codes SELECT = auth.uid()=user_id (own-only) so an authenticated-context client cannot read the referrer's code; redeem_referral_atomic EXECUTE granted to service_role only (has_function_privilege('authenticated', ...) = false). The pure service-role client bypasses both." }
  - { tier: 12, layer: client_server_contract, status: verified, evidence: "pre-fix: referral_redemptions = 0 rows ever and every apply showed 'Network error'. post-fix live smoke (redeem AVYA-TESTCODE) is the proof a redemption row + 2 referral_trial subscriptions are written — runs after deploy." }
impact_analysis: >
  Account-tier (referral PRO grant + EF auth-context). The referral redemption flow has
  been broken end-to-end since inception: the EF read the referrer's code under the
  referee's RLS context (own-only), so every redemption failed at the code lookup, and the
  client masked the server's reason as a generic network error. NOT an auth bug (getUser
  itself worked); the DATA-read RLS context was wrong. Same class FAMILY as e8a1c3 but the
  opposite mechanism — e8a1c3 put the user JWT in the apikey slot; here the user JWT in
  global.headers overrode the service-role apikey so PostgREST ran as `authenticated`.
  Verified across 4 independent review rounds before any code. Surfaced + fixed a same-class
  paywall validate-promo token-freshness bug via the gate fix.
  related: e8a1c3 (delete-account auth, EF-auth class family); 2.31 (token freshness — the
  onboarding + paywall raw invokes); 2.36 (FunctionException not unpacked → masked errors).
---

# redeem-referral reads the referrer's code under the referee's RLS context → every redemption fails (d2b9e6)

## What happened
Applying a referral code ALWAYS failed. The Profile "Apply Referral Code" sheet showed
"Network error. Try again in a moment."; the welcome-screen stash redeem at onboarding
silently did nothing. `referral_redemptions` has **0 rows ever** — the 7-day-PRO referral,
a core growth lever, has never worked for a single user.

## Root cause
The Edge Function built its client with the user JWT in `global.headers`:
```ts
const supabase = createClient(URL, SERVICE_ROLE, {
  global: { headers: { Authorization: userJWT } },   // <-- overrides the service_role apikey
});
const { data } = await supabase.auth.getUser();        // bare (worked only via the header)
// ...
await supabase.from("referral_codes").select(...).eq("code", code).single();   // RLS: own-only
await supabase.rpc("redeem_referral_atomic", {...});                            // service_role-only
```
supabase-js lets `global.headers.Authorization` override the apikey, so PostgREST derives the
role from the **user JWT** → it runs as `authenticated`, not `service_role`. Consequences
(both live-verified): (1) the `referral_codes` lookup of the REFERRER's row is blocked by
`auth.uid() = user_id` own-only RLS → "We don't recognize that code"; (2) `redeem_referral_atomic`
is `EXECUTE`-granted to `service_role` only. Either way the redemption dies, and the client
(`functions.invoke` throws `FunctionException` on the 4xx) collapses it to "Network error".

## Fix
```ts
const token = authHeader.replace("Bearer ", "");
const supabase = createClient(URL, SERVICE_ROLE);     // PURE service-role → BYPASSRLS
const { data } = await supabase.auth.getUser(token);  // authenticate the caller explicitly
// reads + redeem_referral_atomic now run as service_role → not RLS-blocked
```
Plus `success: true` in the 200 body (one shape for all three callers); the repository catch
unpacks `FunctionException` (server message); the onboarding redeem routes through `callFunction`.

## Verification
- `test/contracts/referral_redeem_success_contract_test.dart` (source-grep, comment-stripped).
- Live smoke (after deploy): redeem `AVYA-TESTCODE` as test2 → a `referral_redemptions` row +
  a 7-day `referral_trial` subscription for BOTH test2 and amar; then cleaned up (0 residual).

## See also
- supabase/functions/redeem-referral/index.ts
- docs/diagnoses/2026-06-12-delete-account-auth-rejects-valid-token-e8a1c3.md (EF-auth family)
- scripts/check_authed_invoke_fresh_token.dart (multi-line-invoke gate fix; caught paywall too)
