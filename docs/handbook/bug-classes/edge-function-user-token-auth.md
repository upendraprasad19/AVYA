---
title: Edge Function user-token auth — service-role client + getUser(token), never JWT-as-apikey
category: bug-classes
source_memory: feedback_edge_function_auth_jwt_as_apikey.md
last_reviewed: 2026-06-26
---

# Edge Function user-token auth — service-role client + getUser(token)

## The class

An authenticating Edge Function must identify the caller. Two shapes look right; one
401s **every** valid token, a second empties **every** cross-user read.

### Trap A — user JWT passed as the apikey (401s every valid token)

```ts
// WRONG
const c = createClient(SUPABASE_URL, authHeader.replace("Bearer ", ""));
const { data } = await c.auth.getUser();   // no token arg
```

`createClient(url, <userJWT>)` makes `apikey: <userJWT>` — GoTrue rejects it (a user JWT
is not a project key) → 401 for every real session. An anon boot-smoke can't catch this
(anon Bearer → 401 is *correct*); only a REAL user token surfaces it.

### Trap B — user JWT in the service-role client's global headers (silent empty read)

```ts
// WRONG when the feature must read OTHER users' rows
const c = createClient(SUPABASE_URL, SERVICE_ROLE, {
  global: { headers: { Authorization: authHeader } },  // downgrades to `authenticated` role
});
```

This runs PostgREST as the `authenticated` role under RLS. Auth *succeeds*, but any
query that legitimately needs cross-user rows (community queue, a referrer's code)
returns empty for everyone. Distinct from Trap A — no 401, just silent emptiness.

## The correct shape

```ts
const token = authHeader.replace("Bearer ", "");
const authClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);  // valid apikey
const { data: userRes } = await authClient.auth.getUser(token);   // token passed explicitly
const userId = userRes.user?.id;                                   // null → 401

// Privileged / cross-user reads: use a service-role client with NO per-request
// Authorization header + an explicit user-scope filter + anonymized projection.
```

GoTrue validates the user JWT (genuine auth), the `apikey` is a real key (service-role),
so the request is accepted. The four reference EFs do exactly this: `daily-snapshot`,
`ai-media-proxy`, `assess-body-composition`, `beat-my-coach`.

## Client seam — send a fresh token

A Flutter-**web** session can present a stale `access_token` to `functions.invoke`, so a
correct EF still 401s. Route every authed invoke through
`SupabaseService.callFunction` (`lib/core/services/supabase_service.dart:231`), which
calls `ensureFreshToken()` (`:176`) first. Never call `client.functions.invoke` directly
from an authed path.

## How to detect

- Live: same valid token → `/auth/v1/user` 200 + `ai-proxy` 200 but the new EF 401
  (request_id in the response) → Trap A.
- Live: the feature's list is empty for ALL users though rows exist → Trap B (cross-user
  RLS), not "no data."
- A `verify_jwt=true` EF that only ever got an anon boot-smoke is **unverified** — anon
  → 401 hides Trap A.

## Prevention

- Server gate: `scripts/check_edge_function_auth_pattern.dart` bans the
  `createClient(SUPABASE_URL, authHeader…)` + bare `getUser()` shape.
- Client gate: `scripts/check_authed_invoke_fresh_token.dart` flags an authed
  `functions.invoke` bypassing `callFunction`/`ensureFreshToken`.
- Verify rule: smoke a `verify_jwt` EF with a REAL user token, not just anon boot.
  (`edge-function-deploy-rollback` skill, bug-class 6.7.)

## Instances

1. `delete-account` (e8a1c3, 2026-06-12) — Trap A made the DPDP §17 erasure unreachable
   for ALL users until the live web walk caught it.
2. `redeem-referral` (d2b9e6, 2026-06-13) — Trap B: JWT-in-global-headers ran the
   referrer-code read as `authenticated` → RLS blocked it → referral redemption failed.
3. `get-community-review-items` (c7d4f1 + migration 092, 2026-06-13) — Trap B: own-only
   SELECT RLS → the review queue was empty for everyone; fixed with a scoped service-role
   EF + anonymized projection (never relaxed the table RLS).

## References

- ADR: [`../../adr/0016-edge-function-user-token-auth-contract.md`](../../adr/0016-edge-function-user-token-auth-contract.md)
- Diagnose: `docs/diagnoses/2026-06-12-delete-account-auth-rejects-valid-token-e8a1c3.md`
- Memory: `feedback_edge_function_auth_jwt_as_apikey.md`, `feedback_cross_user_read_rls_context.md`
- Related: [`sot-audit-required.md`](sot-audit-required.md); debugging skill §2.35 / §2.31 / §2.38; CLAUDE.md §4.4 rule 9.
