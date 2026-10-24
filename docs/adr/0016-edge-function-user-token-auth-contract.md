---
adr_id: 0016
title: Edge Functions authenticate the caller via a service-role client + getUser(token); clients send a freshly-refreshed token
status: accepted
date: 2026-06-26
deciders: Upendra
---

# ADR-0016: Edge Function user-token auth contract (service-role client + getUser(token)) + client token-freshness

## Context

Every `verify_jwt`-style Edge Function must answer one question on each request:
*"which authenticated user is calling me?"* There are two superficially-plausible
ways to do it with `supabase-js`, and **one of them rejects every valid token**:

```ts
// WRONG — the user JWT is passed as the supabaseKey (apikey header)
const c = createClient(SUPABASE_URL, authHeader.replace("Bearer ", ""));
const { data } = await c.auth.getUser();        // no token arg
```

`createClient(url, <userJWT>)` sets `apikey: <userJWT>`. GoTrue rejects that — a user
JWT is not a project API key — so the request 401s for **every** valid session token.
`getUser()` with no argument also has no token to validate. This is invisible to an
anon boot-smoke (an anon Bearer → 401 is the *correct* response), so it only surfaces
with a REAL user token. It shipped to prod in `delete-account` and made the DPDP §17
erasure right unreachable for ALL users until the live E2E walk caught it
(diagnose **e8a1c3**, 2026-06-12). The same EF-auth class recurred as the referral P0
(JWT-in-global-headers ran PostgREST as `authenticated` → RLS blocked the read,
diagnose **d2b9e6**) and the community-review GAP (own-only RLS → empty for everyone,
**c7d4f1**).

A second, independent failure mode lives on the **client** seam: a Flutter-**web**
session can hold a stale `access_token` (the web SDK doesn't always auto-refresh before
an `invoke`), so an otherwise-correct EF still 401s — not because the EF is wrong but
because the token arrived expired.

These two seams together are CLAUDE.md coding-rule 9; this ADR records the *why* so the
contract is not "fixed" back into either trap.

## Decision

**Server seam — an Edge Function authenticates the caller with a SERVICE-ROLE client and
an explicitly-passed token:**

```ts
const token = authHeader.replace("Bearer ", "");
const authClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);  // valid apikey
const { data: userRes } = await authClient.auth.getUser(token);   // token passed explicitly
const userId = userRes.user?.id;                                   // 401 if null
```

GoTrue still validates the user JWT (so this is genuine authentication, not a bypass),
but the `apikey` header is a real project key (service-role), so the request is accepted.
The four EFs that always worked — `daily-snapshot`, `ai-media-proxy`,
`assess-body-composition`, `beat-my-coach` — do exactly this; every authenticating EF
mirrors them.

Corollary (the d2b9e6 lesson): **never pass the user JWT into a service-role client's
global headers** to "act as the user." That silently re-runs PostgREST as the
`authenticated` role under RLS, which empties any query that legitimately needs to read
other users' rows. Authenticate with `getUser(token)`; do the privileged read with the
service-role client (no per-request Authorization header) and an explicit user-scope
filter + anonymized projection.

**Client seam — an authed `functions.invoke` routes through
`SupabaseService.callFunction`, which calls `ensureFreshToken()` first**
(`lib/core/services/supabase_service.dart:231` → `:176`). The token is refreshed (web
especially) before the request leaves the device, so a stale web token never reaches a
correct EF.

**Enforcement (gates, in the pre-commit + CI gate loop):**
- `scripts/check_edge_function_auth_pattern.dart` — bans the
  `createClient(SUPABASE_URL, authHeader…)` + bare `getUser()` shape in
  `supabase/functions/`.
- `scripts/check_authed_invoke_fresh_token.dart` — flags an authed `functions.invoke`
  that bypasses `callFunction`/`ensureFreshToken`.

**Verification rule:** a `verify_jwt=true` EF is verified with a REAL user token, never
just an anon boot (anon → 401 is correct and hides the bug). Codified in the
`edge-function-deploy-rollback` skill (bug-class 6.7) and debugging skill §2.35.

## Alternatives considered

1. **`createClient(url, userJWT)` and let the client "be" the user (the broken shape).**
   Rejected — it's the bug. The user JWT is not a valid `apikey`; GoTrue 401s it. This is
   the exact pattern e8a1c3 removed.
2. **Pass the user JWT into the service-role client's `global.headers.Authorization` to
   read under the user's own RLS.** Rejected — it downgrades the client to the
   `authenticated` role, so any cross-user read (community queue, referrer-code lookup)
   silently returns empty while auth still "succeeds." This is the d2b9e6 / c7d4f1 class.
   Authenticate with `getUser(token)`; read with an unscoped service-role client + an
   explicit filter.
3. **Trust the client to always hold a fresh token (skip `ensureFreshToken`).** Rejected —
   the Flutter-web SDK can present a stale `access_token` to `invoke`; a correct EF then
   401s for a reason that has nothing to do with the EF. The refresh belongs at the single
   `callFunction` chokepoint, not duplicated per call site.
4. **Set `verify_jwt=false` and authenticate by hand only.** Rejected — loses the
   platform's built-in gateway rejection of obviously-bad tokens; the gateway + an
   in-function `getUser(token)` is defense-in-depth.

## Consequences

Good:
- One auth shape across every authenticating EF — copy a known-good EF, never re-derive.
- DPDP erasure, referral redemption, and the community-review queue all work for real
  users (the three P0s this class produced are structurally prevented).
- The two gates fail the build on a regression of either seam, at pre-commit and in CI.

Bad / watch:
- The EF holds the service-role key to *authenticate* — it must NOT then use that client
  to perform writes outside the caller's scope without an explicit `user_id` filter. The
  service-role client bypasses RLS, so every privileged query carries the user-scope
  assertion in code (SSRF/scope rules: coding-rule 16, OI-28).
- `getUser(token)` is a network round-trip to GoTrue per request — acceptable (the four
  reference EFs have always paid it); cache only within a single request, never across.
- A new EF author who copies an *old* pre-e8a1c3 function would reintroduce the trap —
  hence the source-grep gate, not just code review.

## Status

Accepted. The server pattern shipped live in `delete-account` v5+ (e8a1c3, 2026-06-12),
`redeem-referral` v12 (d2b9e6, 2026-06-13), and `get-community-review-items` v1
(c7d4f1 + migration 092, 2026-06-13). Both gates are wired into the pre-commit + CI gate
loop. Recorded as an ADR 2026-06-26 (E2E fix-wave Unit F) so the contract is durable
beyond the diagnose-docs.

## See also

- `docs/diagnoses/2026-06-12-delete-account-auth-rejects-valid-token-e8a1c3.md` (founding incident)
- diagnoses d2b9e6 (referral JWT-in-headers) + c7d4f1 (cross-user own-only RLS)
- `docs/handbook/bug-classes/edge-function-user-token-auth.md` (the durable rule)
- `supabase/functions/_shared/` + the four reference EFs (daily-snapshot / ai-media-proxy / assess-body-composition / beat-my-coach)
- `lib/core/services/supabase_service.dart:176,231` (`ensureFreshToken` / `callFunction`)
- `scripts/check_edge_function_auth_pattern.dart`, `scripts/check_authed_invoke_fresh_token.dart` (the gates)
- CLAUDE.md §4.4 rule 9; debugging skill §2.35 / §2.31 / §2.38; `feedback_edge_function_auth_jwt_as_apikey.md`, `feedback_cross_user_read_rls_context.md`
- `.claude/skills/edge-function-deploy-rollback/SKILL.md` (real-token verify, bug-class 6.7)
