---
bug_id: d3a1c7
date: 2026-06-09
batch: apk34-obs-2026-06-09
status: fixed
blast_radius: account
symptom: >
  APK +34 obs 3 — AI features (chat, food logging, weekly report) intermittently
  failed with no useful error, while ai-proxy itself was ACTIVE (v70) and still
  logging interactions. client_errors showed FunctionException 401 "Invalid or
  expired token" on push_snapshot + sync_service catches. Root: several authed
  Edge Function callers did not send a FRESH user token.
concept: edge_function_token_freshness
sot_registry_entry: edge_function_token_freshness
writers: >
  not_applicable (no data writer). The fix is in the EF CALL paths:
  lib/core/services/ai_service.dart _directHttpCall + _directMediaHttpCall (the
  web/CORS fallbacks) and lib/core/services/sync_service.dart (_sendDeadLetterTelemetry,
  pushSnapshot, _reportSyncFailure). The canonical SupabaseService.callFunction
  already refreshed (ensureFreshToken + hard-refresh); these non-canonical callers
  did not.
readers: >
  Server side — supabase/functions/ai-proxy + ai-media-proxy + weekly-report +
  daily-snapshot + log-client-error validate the Bearer JWT. An anon or expired
  token yields 401 "Invalid or expired token".
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: pushSnapshot (daily-snapshot), _reportSyncFailure / _sendDeadLetterTelemetry (log-client-error)
restore_methods: not_applicable
cloud_table: ai_coach_interactions, user_progress (plan_json / coach_memory via daily-snapshot), client_errors
cloud_columns: not_applicable (Edge Function gateway auth, not a column)
contract_test_path: test/contracts/edge_function_token_freshness_test.dart
ist_handling: not_applicable
provider_invalidations: []
telemetry_op_types:
  success: [edge_function_cold_start_retry]
  failure: [push_snapshot, sync_service_catch_2]
cross_account_guard: >
  not_applicable to the fix — ensureFreshToken / refreshSession operate on the
  current session only; no cross-user surface touched.
forbidden_patterns_checked:
  - "ai_service direct-HTTP must not fall back to the anon key as the Bearer token for an authed EF (the `accessToken ?? AppConstants.supabaseAnonKey` pattern); sync_service must refresh (ensureFreshToken) before each authed functions.invoke. Pinned by test/contracts/edge_function_token_freshness_test.dart."
proposed_fix: >
  ai_service _directHttpCall/_directMediaHttpCall: replace the anon-key fallback
  with a fresh USER token or a clear AiServiceException(401) re-auth signal
  (ensureFreshToken → currentSession → hard refreshSession → throw). sync_service:
  await _supabase.ensureFreshToken() before the daily-snapshot push and both
  log-client-error invokes so a stale access token doesn't 401.
regression_test_planned: >
  test/contracts/edge_function_token_freshness_test.dart — comment-stripped
  source-grep: ai_service no longer contains `accessToken ?? AppConstants.supabaseAnonKey`
  and throws AiServiceException on no session; sync_service calls
  _supabase.ensureFreshToken() at least 3 times (the three authed invokes).
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "ai_service ×2 + sync_service ×3 callsites route through a fresh user token; dart analyze clean on both files + the new test; token-freshness contract green" }
  - { tier: 6, layer: edge_function_code_vs_deploy, status: verified, evidence: "ai-proxy v70 ACTIVE + daily-snapshot v20 + log-client-error v7 ACTIVE (list_edge_functions); they reject anon/expired Bearer with 401 — the symptom the client now avoids by sending a fresh user token" }
  - { tier: 12, layer: client_server_contract, status: fixed_in_this_batch, evidence: "the push_snapshot 401 in client_errors is the obs-1 enabler (stale plan_json never re-persisted); refreshing before daily-snapshot closes that path" }
impact_analysis: >
  Account blast radius — auth-token freshness across all authed Edge Function
  callers. The canonical SupabaseService.callFunction already refreshed; this
  brings the AI web/CORS fallbacks and the sync_service direct invokes to the
  same contract. Also the most likely enabler of the obs-1 stale-plan_json split
  (BUG-A): push_snapshot's 401 meant the regenerated plan window never persisted.
  Happy path adds at most an in-memory expiry check (ensureFreshToken only hits
  the network when the token is within 5 min of expiry). New bug class for the
  debugging skill (token freshness inconsistent across EF callers) added in the
  batch self-evolve step.
---

# Authed Edge Function callers sent a stale / anon token → 401

## What happened
AI chat / food logging / weekly report intermittently failed (APK +34 obs 3)
though ai-proxy was up; client_errors showed 401 "Invalid or expired token" on
push_snapshot and sync catches.

## Root cause
Non-canonical EF callers didn't send a fresh user token:
- `ai_service` `_directHttpCall`/`_directMediaHttpCall` fell back to the anon key
  (`... ?? AppConstants.supabaseAnonKey`) when the proactive refresh returned
  null → ai-proxy 401.
- `sync_service` called `functions.invoke` directly (daily-snapshot push + two
  log-client-error) without refreshing → stale-token 401. push_snapshot's 401
  meant the regenerated plan_json/coach_memory snapshot never persisted — the
  obs-1 stale-plan_json enabler.

## Fix
AI direct HTTP: fresh user token or a clear `AiServiceException(401)` (no anon
fallback). sync_service: `await ensureFreshToken()` before each authed invoke.

## Verification
`dart analyze` clean; `edge_function_token_freshness_test.dart` (no anon Bearer
fallback + ≥3 sync refreshes). ai-proxy v70 / daily-snapshot v20 / log-client-error
v7 confirmed ACTIVE.

## See also
- `lib/core/services/supabase_service.dart` callFunction / ensureFreshToken (the canonical refresh-aware path)
- Debugging skill: new bug class "token freshness inconsistent across EF callers"
