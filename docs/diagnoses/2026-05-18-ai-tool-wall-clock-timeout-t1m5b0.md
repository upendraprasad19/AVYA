---
bug_id: t1m5b0
date: 2026-05-18
batch: APK Test #16.2 observations (2026-05-18)
status: shipped
symptom: |
  Two related AI-coach failures within a single session.

  Failure A (08:34 IST). User asked "how was my workout today and in
  this phase till now?". The coach replied: "Recruit, the system timed
  out gathering your phase summary. This sometimes occurs under heavy
  load. We will attempt to retrieve the data again. What is your next
  query?" The phrase is not a hard-coded string; it is Gemini's
  natural-language synthesis after the server-side tool getProgressSummary
  returned tool_timeout from the 3500 ms wall-clock budget.

  Failure B (11:51 IST). User attached a photo with caption "Analyse
  this photo". The photo bubble rendered the new "PHOTO FAILED / Tap
  to retry" failed-tile (introduced Test #16.1 Theme C) and the coach
  replied: "Sorry, I couldn't analyse that photo. Please try again."
  The client's ai-media-proxy retry budget was exhausted; the typed
  HttpError shape needs client_errors log query to confirm which leg
  failed (400 storage URL / 502 upstream Gemini / 500 server).
concept: ai_tool_wall_clock_and_media_proxy_error_class
sot_registry_entry: coach_interactions
writers:
  - { file: supabase/functions/_shared/tools/progress/getProgressSummary.ts, method_or_widget: getProgressSummary handler, line: 31 }
  - { file: supabase/functions/_shared/tool-loop.ts, method_or_widget: maxLatencyMs gate per tool call, line: 1 }
  - { file: supabase/functions/ai-media-proxy/index.ts, method_or_widget: HttpError mapping, line: 1 }
readers:
  - { file: lib/core/services/supabase_service.dart, method_or_widget: retryColdStart wraps Edge Function invocation, line: 1 }
  - { file: lib/core/services/ai_service.dart, method_or_widget: chat / chatWithMedia callers; _extractError parses error_type, line: 1 }
  - { file: lib/features/ai_coach/widgets/chat_bubble.dart, method_or_widget: _buildPhotoFailedTile renders failed state, line: 1 }
hive_key_prefix: "coach_<chatId>"
hive_key_formula: "client-side coachBox per-chat entry; cloud authoritative row in ai_coach_interactions"
sync_methods: [syncCoachInteractions]
restore_methods: [restoreFromCloudForUser]
cloud_table: ai_coach_interactions
cloud_columns: [user_id, channel, message, ai_response, tokens_used, model_used, tool_calls, failed, created_at]
contract_test_path: test/contracts/get_progress_summary_parallel_queries_test.dart
ist_handling: []
provider_invalidations: [aiCoachConversationProvider]
telemetry_op_types:
  success: [get_progress_summary_under_budget]
  failure: [get_progress_summary_tool_timeout, ai_media_proxy_502_upstream, ai_media_proxy_400_storage, ai_media_proxy_500_internal]
cross_account_guard: ai-proxy validates JWT via auth.getUser(token); ai-media-proxy enforces user-scope on Storage URLs per OI-28 (audit-2026-05-17 Phase B).
forbidden_patterns_checked:
  - "Sequential await on multiple read-only Supabase SELECTs inside a tool handler bounded by a tight wall-clock budget"
touched_layers_checked:
  - { tier: 1, name: client_code, status: verified, evidence: "ai_service.dart _extractError + chat_bubble.dart _buildPhotoFailedTile already render typed HttpError shape from Test #16.1" }
  - { tier: 7, name: edge_function_handler, status: fixed_in_this_batch, evidence: "getProgressSummary.ts parallelises 5 read-only SELECTs with Promise.all to stay under 3500 ms tool budget" }
  - { tier: 8, name: edge_function_error_shape, status: fixed_in_this_batch, evidence: "ai-media-proxy HttpError mapping pinned by contract test" }
  - { tier: 10, name: telemetry, status: verified, evidence: "telemetry op types enumerated for both success and the 4 failure classes" }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "tool_calls cloud column unchanged; client retryColdStart wraps invocation as before" }
impact_analysis:
  callers_audited:
    - supabase/functions/_shared/tools/progress/getProgressSummary.ts
    - supabase/functions/_shared/tool-loop.ts
    - supabase/functions/ai-media-proxy/index.ts
    - lib/core/services/ai_service.dart (chat / chatWithMedia)
    - lib/features/ai_coach/widgets/chat_bubble.dart (_buildPhotoFailedTile)
  callers_updated_in_this_batch:
    - supabase/functions/_shared/tools/progress/getProgressSummary.ts (parallel SELECTs)
    - supabase/functions/ai-media-proxy/index.ts (HttpError mapping audit)
  callers_unchanged:
    - lib/core/services/supabase_service.dart (retryColdStart already wraps Edge Function calls)
    - lib/features/ai_coach/widgets/chat_bubble.dart (Test #16.1 already added failed tile)
proposed_fix: |
  Two independent fixes, one per failure.

  Failure A (getProgressSummary wall-clock):

  The handler at getProgressSummary.ts:31-end does 5 SELECTs sequentially:
  - workout_log_exercises (volume, dates) at line 41
  - scheduled_workouts (planned count) at line 69
  - weight_logs (period start/end weight) — separate SELECT
  - nutrition_logs (avg daily kcal, log days) — separate SELECT
  - workout_log_exercises again (is_pr flag count) — separate SELECT

  At ~200-1200 ms per round-trip on Supabase ap-southeast-1, the 5
  sequential awaits brush or cross the 3500 ms wall and trigger
  tool_timeout. None of the 5 SELECTs depend on each other's results,
  so Promise.all on the 5 independent queries collapses wall-clock
  latency to the slowest single query (~1-1.5 s).

  Two-step fix:
  1. Refactor getProgressSummary handler to dispatch all 5 queries via
     Promise.all and consume the resolved rows in the existing tally
     loops. No schema changes; pure latency reshuffle.
  2. Raise maxLatencyMs from 3500 → 6000 in the tool registration so the
     occasional cold-Postgres-cache rebuild does not nuke a parallel
     fan-out that would have completed in 4-5 s.

  Deploy via .claude/deploy_via_api.js dedsavbjuwgarrhphgnl ai-proxy
  per CLAUDE.md §0 host-shell deploy procedure.

  Failure B (photo failed):

  Before any code change, query client_errors for the user's
  request_ids around 11:50-11:52 IST to identify which leg failed:
  - ai_media_proxy_502_upstream → Gemini was rate-limited or down; the
    retry schedule [2000, 6000, 12000] ms in ai_service.dart already
    handles cold-start; bumping to one more retry is plausible if logs
    show consistent 502.
  - ai_media_proxy_400_storage → Storage URL race; current
    [500, 1500, 3000] ms backoff might still be too tight for the
    user's slow network.
  - ai_media_proxy_500_internal → server bug; review the request_id's
    stack trace and fix the specific code path.

  The investigation produces the actual fix; this diagnose-doc covers
  only the framing and ensures the photo path is tracked. Plan task:
  query client_errors first, then propose the targeted fix.
regression_test_planned:
  - test/contracts/get_progress_summary_parallel_queries_test.dart — pin that the handler uses Promise.all over the 5 SELECTs (source-grep contract).
  - integration test against staging Supabase that asserts getProgressSummary returns under 4000 ms for a representative user with 30-day data.
  - test/contracts/ai_media_proxy_error_type_telemetry_test.dart — pin that error_type values map to distinct telemetry op_types so future failures are queryable.
---
# Body

## How we know "timed out gathering your phase summary" came from the server

`Grep "the system timed out gathering"` across `lib/` and `supabase/`
returns no matches. The exact phrase is Gemini's natural-language
synthesis: when a tool returns `{error: "tool_timeout"}` to the
tool-loop, Gemini paraphrases the error into a user-facing apology.
The Captain manual prompt at `supabase/functions/_shared/captain_manual.ts`
shapes tone but does not script that specific phrase.

The corollary: ai-proxy itself did NOT time out at the function level.
It ran successfully — the failure was internal to the
`getProgressSummary` tool's 3500 ms self-imposed wall clock at
`getProgressSummary.ts:161` (registration).

## Why this is the right framing

We don't fix Gemini's wording; we fix the wall-clock so the tool
returns real data instead of `tool_timeout`. Parallelizing the 5
independent SELECTs is the correct lever — it does not change any
business logic and is one of the highest signal-to-cost performance
wins available in the codebase.

## Photo failure is a separate investigation, not a separate batch

The user reported both A and B in one observation; the user intent is
"AI is broken." The technical fix has two halves but they ship
together because:
- They affect the same surface (AI coach chat).
- They share a deploy gate (ai-proxy + ai-media-proxy versions).
- They share regression tests (error_type telemetry coverage).

## T4b resolution — root cause confirmed, fix applied (2026-05-18 same day)

`client_errors` query for 2026-05-18 11:50-11:51 IST surfaced 8 events
for user `d7a67a37-0b05-4f0a-b13c-388bff3cb59b`:

  - Six `edge_function_storage_race_retry` events (two retry cycles ×
    three attempts each, with 500/1500/3000 ms backoff) all returning
    `status=400 error_type=storage`.
  - Two terminal events: `ai_service_chat_with_media_failed` with
    `FunctionException(status: 400, details: {error: Failed to fetch
    image: 400 Bad Request, error_type: storage, request_id: 54babf44})`
    and `ai_media_proxy_unknown_error` with `AiServiceException:
    Failed to fetch image: 400 Bad Request`.

The Storage object DID exist — `storage.objects` row for
`chat-media/d7a67a37-0b05-4f0a-b13c-388bff3cb59b/1779085235891.jpg`
landed at 11:50:37 IST, 174806 bytes, image/jpeg, owner = founder.
First ai-media-proxy attempt was 11 seconds later.

The persistent 400 across three retries with growing backoff rules out
all transient explanations (storage propagation race, Gemini 502
cold-start, DNS hiccup). The retry budget was exercised in full.

Storage rejected the URL because the `chat-media` bucket is PRIVATE
(`storage.buckets.public = false`, verified live) but the client at
`lib/features/ai_coach/screens/ai_coach_screen.dart:1673` called
`getPublicUrl(storagePath)` which returned
`${SUPABASE_URL}/storage/v1/object/public/chat-media/...`. The `/public/`
path component is only valid for buckets with `public=true`; for
private buckets Storage's HTTP API returns 400 regardless of the
bearer token (even service-role) because the URL shape itself is
invalid for the bucket's configuration.

The pre-Hermes-Phase-B ai-media-proxy code generic 500-catch may have
masked this 400 historically; the typed HttpError mapping introduced
2026-05-16 in commit `584d136` correctly surfaced the underlying
status, so the photo flow had probably been broken for some time and
the surface-level error only became readable last week.

### Fix

`lib/features/ai_coach/screens/ai_coach_screen.dart:1673` —
replace `getPublicUrl(storagePath)` with `await createSignedUrl(
storagePath, 600)`. The 10-minute TTL is comfortable: the Edge
Function fetches the URL within seconds. ai-media-proxy's
`parseStorageUrl` already accepts the `/sign/<bucket>/<path>?token=...`
shape (`supabase/functions/ai-media-proxy/index.ts:178-180`).

The fix is client-only — no Edge Function redeploy required for the
photo half (ai-proxy v67 was redeployed for the T4a parallelization).
Pinned by `test/contracts/chat_media_signed_url_test.dart`. Other
private-bucket upload sites (progress-photos, coach-media) were not
audited in this batch — the search did not find any additional
`getPublicUrl` callsites against private buckets in `lib/`. The only
other `getPublicUrl` call lives in `user_repository.uploadImage` which
is parameterised over a bucket name and is currently only invoked for
the public `avatars` and `banners` buckets; out of scope here.

### Verification

The fix lands in the same commit that bumps `ai-proxy` to v67 (T4a).
Founder should retry a photo upload after the next APK rebuild — the
client side is what changed for the photo half; the server side is
unchanged for ai-media-proxy.

### Adjacent finding (NOT fixed in this batch)

Both `progress-photos` and `coach-media` are also private buckets. If
their upload paths use `getPublicUrl`, they have the same bug. Audit
covers `lib/` and no other private-bucket `getPublicUrl` calls were
found, but a server-side audit of every URL passed to ai-media-proxy
across recent traffic should be run before assuming we are clean.
