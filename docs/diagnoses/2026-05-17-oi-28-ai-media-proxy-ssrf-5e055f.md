---
bug_id: 5e055f
date: 2026-05-17
batch: Hermes audit 2026-05-17 — Phase B (P1 security)
status: shipped
symptom: |
  ai-media-proxy validated only that the supplied `media_url` started
  with `${SUPABASE_URL}/storage/v1/object/`, then fetched the URL with
  `Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}`. Service role
  bypasses Storage RLS — any authenticated user could supply ANOTHER
  user's private Storage URL (progress-photos, chat-media, coach-media)
  and the function would fetch the bytes + forward them to Gemini in
  the response. Potential cross-user image leak.
concept: ai_media_proxy_user_scope_assertion
sot_registry_entry: subscription_payment_grace_window
writers:
  - { file: supabase/functions/ai-media-proxy/index.ts, method: parseStorageUrl, line: 181 }
  - { file: supabase/functions/ai-media-proxy/index.ts, method: fetchImageAsBase64 authUserId param, line: 200 }
  - { file: supabase/functions/ai-media-proxy/index.ts, method: user-scope assertion, line: 229 }
readers:
  - { file: test/contracts/ai_media_proxy_user_scope_test.dart, method_or_widget: 6-case contract suite, line: 1 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: storage.objects
cloud_columns:
  - bucket_id
  - name
contract_test_path: test/contracts/ai_media_proxy_user_scope_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "path.startsWith(authUserId/) assertion before service-role fetch"
forbidden_patterns_checked:
  - { pattern: "fetchImageAsBase64 without authUserId param", absent: true }
  - { pattern: "service-role Storage fetch without user-scope check", absent: true }
proposed_fix: |
  Tightened `fetchImageAsBase64` to require `authUserId: string` as its
  second parameter. New helper `parseStorageUrl(imageUrl)` decomposes
  the URL into `{bucket, path}` for any of the 3 Storage URL shapes
  (public / sign / authenticated). Three new assertions run BEFORE
  the service-role fetch:

  1. URL parses cleanly (else 400 validation).
  2. `bucket` is in `ALLOWED_BUCKETS` = {chat-media, coach-media,
     progress-photos} (else 400 validation).
  3. `path.startsWith(${authUserId}/)` matching the Storage RLS shape
     `(storage.foldername(name))[1] = (auth.uid())::text` (else 403
     authorization).

  serve handler now passes the authenticated `userId` (extracted via
  `supabaseClient.auth.getUser(token)`) into `fetchImageAsBase64`.

  Why this shape (not a request-schema refactor): keeps client code
  unchanged. The SSRF hole is closed entirely server-side; client can
  later migrate to `{bucket, path}` shape as a follow-up if we want
  type-safety on the client.

  Why missed by today's audit: lens L23 (service-role authz
  defense-in-depth) did not exist. OI-12 RLS audit was table-level only
  — verified policies on tables but didn't audit service-role bypass
  paths inside Edge Function code.
regression_test_planned:
  - test/contracts/ai_media_proxy_user_scope_test.dart
---

# Bug 5e055f — ai-media-proxy SSRF / cross-user image leak

closes-oi: OI-28

## Root cause

Service role bypasses Storage RLS. The pre-fix validation was:

```typescript
if (!imageUrl.startsWith(STORAGE_PREFIX)) {
  throw new HttpError(400, "validation", "Only Supabase Storage URLs are allowed");
}
const headers = { Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`, ... };
const response = await fetch(imageUrl, { headers });
```

A user A with a valid JWT could call ai-media-proxy with `media_url =
${SUPABASE_URL}/storage/v1/object/public/progress-photos/<userB-uid>/file.jpg`
— prefix check passes, service-role fetch returns user B's image
bytes, Gemini analyses + returns description in the chat response. The
prefix check was authentication-grade (is this a Storage URL?) but
NOT authorization-grade (does the caller own this path?).

## Why this matters

3 buckets are at risk:

- `progress-photos/<uid>/...` — PRO before/after body shots
- `chat-media/<uid>/...` — photos sent to AI coach (food, body, form)
- `coach-media/<uid>/...` — long-term consented saves (per OI-23
  migration 070)

All 3 buckets enforce `(storage.foldername(name))[1] = (auth.uid())::text`
in their SELECT RLS policies. The application code must apply the
same shape because the service-role read bypasses RLS.

## Fix

`parseStorageUrl(imageUrl)` extracts `{bucket, path}` from any of the
3 Storage URL shapes. `fetchImageAsBase64(imageUrl, authUserId)` runs
the assertion chain before fetching:

```typescript
const parsed = parseStorageUrl(imageUrl);
if (!parsed) throw new HttpError(400, "validation", "...");
if (!ALLOWED_BUCKETS.has(parsed.bucket)) throw new HttpError(400, ...);
if (!parsed.path.startsWith(`${authUserId}/`)) {
  // Don't leak whose URL it was — generic 403.
  throw new HttpError(403, "authorization", "...");
}
```

The 403 message is intentionally generic — doesn't confirm whether
the path exists or which user owns it. Pre-fix the function would
silently succeed AND return the bytes; now it 403s with no
information leak.

## Deploy

`ai-media-proxy v17 → v18` (verify_jwt: true). Client unchanged.

## Verification

```
$ flutter test test/contracts/ai_media_proxy_user_scope_test.dart
All tests passed! (6 cases)
```

The 6 cases pin: signature requires authUserId; parseStorageUrl
helper exists; ALLOWED_BUCKETS allowlist enforced; `startsWith(${authUserId}/)`
assertion present; 403 "authorization" error_type fires on mismatch;
serve handler passes userId to fetchImageAsBase64.

## Related

- CLAUDE.md §11 — Edge Function SSRF rule (now upgraded with user-scope)
- `docs/audit/LENS_REGISTRY.md` — L23 service-role authz defense-in-depth
- Storage RLS policies in migration 047 + 070 (the `(storage.foldername(name))[1] = (auth.uid())::text` shape this fix mirrors)
- OI-12 RLS audit — table-level only; this fix closes the service-role bypass gap
