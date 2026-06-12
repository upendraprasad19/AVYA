---
bug_id: e8a1c3
date: 2026-06-12
batch: e2e-obs-fixes
status: fixed
blast_radius: platform
symptom: >
  Live web E2E (test1@gmail.com, Obs#10). The delete-account Edge Function (DPDP
  §17 erasure) rejected EVERY valid user token with 401 "unauthenticated" — so no
  user could delete their account via the EF. Proven live: with the SAME session
  access_token, GET /auth/v1/user returned 200 (user def7bb05) and POST /ai-proxy
  returned 200, but POST /delete-account returned 401 (request_id 84b8f6ad; also
  401 with a freshly-refreshed token, req 512483ef). The UI "Delete Account" button
  (Obs#9) also did not fire, so the DPDP erasure was unreachable by either path.
concept: edge_function_user_token_validation_pattern
sot_registry_entry: not_applicable
writers: >
  supabase/functions/delete-account/index.ts (the JWT-auth block — now uses a
  service-role client + getUser(token), mirroring the working EFs).
readers: >
  the rest of delete-account/index.ts reads userRes.user.id (userId) for every
  privileged erasure step; a 401 here aborts the whole flow.
hive_key_prefix: not_applicable
hive_key_formula: not_applicable (Edge Function)
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: not_applicable
contract_test_path: test/contracts/delete_account_auth_pattern_test.dart
ist_handling: not_applicable
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: true
forbidden_patterns_checked:
  - "createClient(SUPABASE_URL, authHeader.replace('Bearer ','')).auth.getUser() — the user JWT passed as the supabaseKey (so apikey=userJWT, rejected by GoTrue) + getUser() with no token arg. REMOVED."
  - "auth.getUser() with no argument in delete-account — REMOVED; the token is now passed explicitly via getUser(token)."
proposed_fix: >
  Mirror the working EFs (daily-snapshot, ai-media-proxy, assess-body-composition,
  beat-my-coach): create the auth client with the SERVICE_ROLE key and validate the
  user by passing the token explicitly — getUser(token). This still confirms the
  token is for a real authenticated user (GoTrue validates the JWT in /auth/v1/user)
  but uses a VALID apikey (service-role) so the request is accepted.
regression_test_planned: >
  test/contracts/delete_account_auth_pattern_test.dart — scoped source-grep (EF runs
  in Deno) with comment-stripping: the JWT-auth block calls getUser(token) (token
  passed), uses SERVICE_ROLE for the auth client, and does NOT contain the broken
  createClient(SUPABASE_URL, authHeader.replace(...)) + bare getUser() pattern.
  Plus a live re-test after deploy: a valid user token must now be accepted (the
  test1 erasure is that live proof).
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "delete-account/index.ts auth block → SERVICE_ROLE client + getUser(token); delete_account_auth_pattern_test green" }
  - { tier: 6, layer: edge_function_code_vs_deploy, status: fixed_in_this_batch, evidence: "fixed delete-account redeployed (v5); REAL-token erasure of test1 (def7bb05) via the EF returns 200 success — the live proof a valid token is now accepted" }
  - { tier: 12, layer: client_server_contract, status: verified, evidence: "pre-fix: same valid token → /auth/v1/user 200 + ai-proxy 200 but delete-account 401 (req 84b8f6ad). post-fix: delete-account accepts it + erases. End-to-end DPDP path restored." }
impact_analysis: >
  Platform/DPDP-compliance blast radius. The delete-account auth pattern was broken
  such that NO valid user token was accepted → the DPDP §17 erasure right was
  unexercisable via the EF for ALL users. PRE-DATES a2c8e6 (which only touched the
  Razorpay-cancel step, not the auth block); the prior boot-verify (anon-Bearer →
  401, which is the CORRECT response for an anon token) could not catch it — only a
  REAL user-token test surfaces it. The fix mirrors four already-working EFs.
  Lesson captured for the edge-function-deploy-rollback skill: verify a
  verify_jwt=true function with a REAL user token, not just boot. related: a2c8e6,
  b4e2a9 (prior delete-account work); Obs#9 (the UI delete button not firing — the
  other broken deletion path, tracked separately).
---

# delete-account EF rejects every valid user token (401) → DPDP §17 erasure unreachable (e8a1c3)

## What happened
`POST /functions/v1/delete-account` returned `401 {"error":"unauthenticated"}` for a
provably-valid session token. Same token, same instant: `/auth/v1/user` → 200 (user
`def7bb05`), `/ai-proxy` → 200, `delete-account` → 401. So no user could erase their
account via the EF.

## Root cause
The JWT-auth block built its client wrong:
```ts
const userClient = createClient(SUPABASE_URL, authHeader.replace("Bearer ", ""));  // user JWT AS THE KEY
const { data: userRes } = await userClient.auth.getUser();                          // no token arg
```
`createClient(url, <userJWT>)` makes the `apikey` header the user JWT — which GoTrue
rejects (not a project API key) — and `getUser()` with no argument has no token to
validate. Result: every valid token → 401. Four other EFs do it correctly:
`createClient(url, SERVICE_ROLE)` + `getUser(token)`.

## Fix
```ts
const token = authHeader.replace("Bearer ", "");
const userClient = createClient(SUPABASE_URL, SERVICE_ROLE);
const { data: userRes } = await userClient.auth.getUser(token);
```
Valid apikey (service-role) + token passed explicitly → GoTrue validates the user JWT
and returns the user. Still confirms a real authenticated user.

## Verification
- `test/contracts/delete_account_auth_pattern_test.dart` (source-grep, comment-stripped).
- Live: the test1 (`def7bb05`) erasure via the redeployed EF returns 200 — a valid
  token is now accepted (this is what was impossible pre-fix).

## See also
- supabase/functions/delete-account/index.ts (JWT AUTH block)
- working reference: daily-snapshot / ai-media-proxy / assess-body-composition / beat-my-coach
- docs/diagnoses/...-a2c8e6... (Razorpay-cancel non-fatal, same EF, same batch lineage)
- .claude/skills/edge-function-deploy-rollback/SKILL.md (real-token verify lesson)
