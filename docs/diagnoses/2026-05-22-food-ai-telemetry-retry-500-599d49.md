---
bug_id: 599d49
date: 2026-05-22
batch: APK Test #16.2 +30 obs 5-12 batch (commit 5 / Theme I)
status: shipped
symptom: |
  Founder opened Nutrition → Log Food → AI tab → typed → tapped
  ANALYSE & LOG → got the toast "The AI is temporarily unavailable.
  Please try again in a minute." (founder IS PRO with active
  subscription). Two observability gaps + one real bug:

  1. ZERO per-call telemetry to tell us whether it was a cold-start
     502/503/504 (retried but exhausted), a 500 (no retry budget), a
     Gemini upstream timeout, or something else. The existing
     `nutrition_ai_text_analyse_failed` event fired but carried only a
     500-char error message — no HTTP status, no latency, no error
     class.
  2. The toast told the user "temporarily unavailable" with no
     differentiation between transient (Gemini hiccup; retry will
     work) and outage (regional; wait it out). No status surfaced.
  3. ai-proxy returns 500 on transient Gemini upstream timeouts but
     SupabaseService.retryColdStart only retried 502/503/504. A 500
     from Gemini got no retry budget and surfaced as an immediate
     failure to the user.

concept: food_text_analysis
sot_registry_entry: food_text_analysis
writers:
  - { file: lib/core/services/supabase_service.dart, method_or_widget: retryColdStart now accepts retryOn500 parameter, line: 270 }
  - { file: lib/core/services/supabase_service.dart, method_or_widget: callFunction forwards retryOn500 to retryColdStart, line: 213 }
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: AiBreakdownNotifier.analyse emits 3 lifecycle telemetry events + passes retryOn500=true + surfaces status in toast, line: 663 }
readers:
  - { file: lib/features/nutrition/widgets/food_logger_section.dart, method_or_widget: renders AiBreakdownData.error in user-facing toast/card, line: 1 }
hive_key_prefix: "n/a — pure Edge Function call wiring"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: nutrition_logs
cloud_columns: []
contract_test_path: test/contracts/food_ai_telemetry_retry_test.dart
ist_handling:
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, line: 663, source: "no date-key math — pure telemetry + error handling" }
provider_invalidations: []
telemetry_op_types:
  success: [food_ai_call_initiated, food_ai_call_succeeded]
  failure: [food_ai_call_failed, edge_function_cold_start_retry]
cross_account_guard: callFunction already routes through SupabaseService.ensureFreshToken which respects HiveUserSession.currentOwnerFullId.
forbidden_patterns_checked:
  - "Edge Function call without per-call lifecycle telemetry — the next debugger has no signal."
  - "ai-proxy 500 without retry budget — Gemini upstream timeouts surface as user-visible failures."
  - "Generic 'temporarily unavailable' toast that hides the actual HTTP status — user can't distinguish 'try again' from 'regional outage'."
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "supabase_service.dart:213+270 + nutrition_provider.dart:663 — all changes wrapped + tested" }
  - { tier: 6, name: edge_function_code, status: verified, evidence: "ai-proxy v66 unchanged — this fix is purely client-side retry budget extension + telemetry. Server logs to be pulled live during smoke per the spec." }
  - { tier: 12, name: end_to_end_contract, status: fixed_in_this_batch, evidence: "test/contracts/food_ai_telemetry_retry_test.dart — 9 assertions" }
impact_analysis:
  callers_audited:
    - lib/features/nutrition/providers/nutrition_provider.dart (food_text_analysis path)
    - Every other callFunction site (verified that retryOn500=false default is preserved — no behavior change)
  callers_updated_in_this_batch:
    - lib/core/services/supabase_service.dart (callFunction + retryColdStart signatures)
    - lib/features/nutrition/providers/nutrition_provider.dart (AiBreakdownNotifier.analyse)
  callers_unchanged:
    - All non-nutrition callers — retryOn500 defaults to false, so retryColdStart behaves exactly as before for ai-coach, ai-media-proxy, log-client-error, etc.
proposed_fix: |
  Three layers:

  1. SupabaseService.callFunction + retryColdStart accept an opt-in
     `bool retryOn500 = false` parameter. When true, the isColdStart
     predicate extends to include status==500. Forwarded by
     callFunction so callers can opt in without re-implementing the
     retry loop. Default-false preserves global behavior — only the
     opt-in path retries 500.

  2. nutrition_provider.dart AiBreakdownNotifier.analyse passes
     `retryOn500: true` to its callFunction call. The food_text_analysis
     Edge Function (ai-proxy) returns 500 on Gemini upstream timeouts
     which are transient; the existing [2000, 6000, 12000] ms backoff
     budget covers them.

  3. Three lifecycle telemetry events around the call:
     - food_ai_call_initiated (BEFORE callFunction, with text_len)
     - food_ai_call_succeeded (on 2xx, with ms=<latency>)
     - food_ai_call_failed (on throw, with status + error_class + ms)
     Stopwatch declared BEFORE the try{} block (Dart scoping — vars in
     try{} are not visible in catch{}).

  4. Toast template surfaces HTTP status when captured:
     - Pre-fix: "The AI is temporarily unavailable. Please try again
       in a minute." (regardless of underlying status)
     - Post-fix: "The AI is offline (502). Please try again in a
       minute." when FunctionException.status is captured; falls
       back to the generic copy if not (e.g. network DNS failure).

  5. isServiceError predicate extended to match 500 too so the
     retry-exhausted 500 still routes to the "service unavailable"
     copy rather than the generic "Could not analyse".
regression_test_planned:
  - test/contracts/food_ai_telemetry_retry_test.dart — 9 assertions covering retryOn500 parameter (declaration + isColdStart predicate + forwarding), three lifecycle telemetry events, retryOn500: true call-site, status-in-toast template, isServiceError 500 inclusion.
related_bugs:
  - 7b3eaf  # Theme F2 — verifyFromServer hardening; similar observability pattern (telemetry on every exit)
  - c01d57  # Test #16 — edge-function cold-start budget [2000, 6000, 12000]; reuses the same retry helper
---
# Body

## Why retryOn500 is opt-in (not global)

The default retry-set 502/503/504 are gateway-side signals (cold start
in Supabase Edge runtime, gateway timeout in Cloud Run / Knative). They
are RELIABLY transient — retry budget will eventually succeed.

500 is "internal server error" — semantics depend on the Edge Function:
- ai-proxy: Gemini upstream timeout → transient, retry helps.
- log-client-error: validation failure → caller bug, retry is wasted.
- ai-media-proxy: bucket misconfiguration → not transient, retry is wasted.

Making retryOn500 opt-in lets ai-proxy's caller retry without changing
behavior for the other 8 Edge Functions. Caller knows the upstream
semantics; the helper doesn't.

## Why surface the HTTP status in the toast

Users don't care about HTTP. They care about "should I tap again now,
or wait 10 minutes, or contact support?". The status code answers that:
- 502/503/504: cold start; ~10s and try again.
- 500: Gemini upstream; ~30s and try again.
- 429: rate limit; wait until tomorrow.
- 4xx: caller error; the toast already covers (message too long, etc.).

Surfacing the number turns an opaque "try again later" into an
actionable signal. Founder won't have to ask "what does temporarily
unavailable mean" again.

## Pull ai-proxy server logs (separate investigation)

Per the Theme I spec, the next debugging step (post-deploy) is to query
ai-proxy server-side logs via Supabase MCP `get_logs` service=edge-
function for the founder's `food_text_analysis` call window. If the
cause was a Gemini timeout (now retried) the fix already covers it.
If the cause was a deploy regression (ai-proxy v66 specific), a
follow-up server-side fix lands in a separate commit.

That investigation is read-only data-gathering — does not block this
commit. The instrumentation here gives us the signal the founder's
next tap needs to diagnose what we couldn't before.
