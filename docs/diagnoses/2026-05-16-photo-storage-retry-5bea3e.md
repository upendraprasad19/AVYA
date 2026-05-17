---
bug_id: 5bea3e
date: 2026-05-16
batch: audit-2026-05-16 reader-side / Obs 6 (post-+27 install observation)
status: fixed
symptom: |
  AI coach photo analysis still fails on first attempt after the Test
  #16.1 / Bug 913261 classification fix. Chat bubble correctly renders
  the red-bordered "PHOTO FAILED · Tap to retry" tile (the new UI from
  913261 is working), but the underlying analysis returns an error and
  the assistant bubble shows "Sorry, I couldn't analyse that photo.
  Please try again." Test #16.1 made the failure visible; it did not
  add the recovery path for the common 400/storage CDN-race case.
concept: ai_media_proxy_classification
sot_registry_entry: ai_proxy_placeholder_resolution
writers:
  - { file: supabase/functions/ai-media-proxy/index.ts, method: HttpError throw sites, line: 165 }
readers:
  - { file: lib/core/services/supabase_service.dart, method: retryColdStart, line: 269 }
  - { file: lib/core/services/ai_service.dart, method: _retryHttpColdStart, line: 395 }
  - { file: lib/features/ai_coach/widgets/chat_bubble.dart, method: ChatBubble mediaFailed render, line: 42 }
hive_key_prefix: ""
hive_key_formula: ""
sync_methods: []
restore_methods: []
cloud_table: ""
cloud_columns: []
contract_test_path: test/contracts/edge_function_storage_race_retry_test.dart
ist_handling: []
provider_invalidations: [aiCoachStateProvider]
telemetry_op_types:
  success: [edge_function_storage_race_retry]
  failure: []
cross_account_guard: "JWT validated server-side via auth.getUser(token) on every ai-media-proxy call"
forbidden_patterns_checked:
  - { pattern: "400 status without error_type body discrimination", absent: true }
proposed_fix: |
  Both retry helpers extended with a SECOND retry track for 400
  responses whose body carries `error_type: "storage"` —
  ai-media-proxy v17's typed Storage 404 (upload-CDN race) shape.
  Schedule [500, 1500, 3000] ms — sub-second-friendly since CDN
  propagation typically resolves in <1s. Total budget ~5s. Other 400s
  (validation, oversized image, malformed body) still rethrow
  immediately because they are caller bugs that retry will not help.
  Telemetry op_type `edge_function_storage_race_retry` per attempt
  for ops visibility — distinct event from `edge_function_cold_start_retry`
  so dashboards can tell which class is dominating in production.
  Tolerant body parse: details may be Map (Supabase Flutter native)
  or JSON-string (rare); both forms are handled in
  `_functionDetailsIsStorageRace`.
regression_test_planned:
  - test/contracts/edge_function_storage_race_retry_test.dart
---
# Body

## Symptom

AI coach photo tap by founder on +27 fresh install:
1. User picks photo from gallery (writes to Supabase Storage
   `chat-media/<uid>/<ts>.jpg`).
2. Client immediately invokes ai-media-proxy with `media_url`.
3. ai-media-proxy v17 attempts to fetch the photo from Storage —
   CDN propagation hasn't completed yet -> Storage returns 404.
4. v17 maps Storage 404 to `HttpError(400, "storage", "Image upload
   incomplete — please retry")`.
5. Client retry budget (`retryColdStart` + `_retryHttpColdStart`)
   covers 502/503/504 only. 400 status is intentionally NOT retried
   because most 400s are caller bugs (validation, oversized image).
6. The 400/storage error propagates to ChatBubble — the red-bordered
   PHOTO FAILED tile renders (913261 fix working). User sees
   "Sorry, I couldn't analyse that photo".

## Root cause

The Test #16.1 / 913261 fix improved CLASSIFICATION (Storage 404 now
maps to 400/storage instead of being lumped into 500), and the chat
bubble correctly RENDERS the failure as a retry-affordance tile.
But neither the classification fix nor the bubble UI fix added a
RECOVERY path for the upload-CDN race itself. The user-visible
failure mode is identical to pre-913261 — the fix made the bug
visible without making it less common.

CDN propagation for Supabase Storage typically completes in
sub-second windows. A ~5s retry budget with exponential backoff
absorbs the typical race without noticeably slowing the success
case.

## Fix

See `proposed_fix` in frontmatter. Dual retry track in
`SupabaseService.retryColdStart` (the primary path used by
`callFunction`) and `AiService._retryHttpColdStart` (the
`_directHttpCall` / `_directMediaHttpCall` web/CORS fallback). Both
mirror each other for consistency.

## Regression test

`test/contracts/edge_function_storage_race_retry_test.dart` — 6
cases covering: 400/storage retry to success (Map details), 400/storage
retry to success (JSON-string details), 400/validation rethrow no-retry,
400/null-details rethrow, storage-race budget exhaustion, 502+400
sequential independent-budget retry.
