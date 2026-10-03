---
bug_id: c01d57
date: 2026-05-15
batch: APK Test #15.5 (obs #4)
status: in_progress
symptom: |
  Edge Function logs at 09:33 IST show 3× ai-proxy 502 BAD_GATEWAY with
  execution_times 6.1s / 6.6s / 7.2s in rapid succession. The Test #15.3
  retry schedule `[1500, 4000]` ms (~5.5 s total wait) was too tight — the
  third 502 fired AFTER the 4s backoff still landed on a cold instance.
  User sees the "AI is temporarily unavailable" toast even though the
  function would have served warm a few seconds later. Additionally, the
  `ai-media-proxy` direct-HTTP web fallback (`_directMediaHttpCall` in
  `ai_service.dart:438`) bypasses `retryColdStart` entirely — any 502 on
  the web/CORS fallback path surfaces immediately with zero retries.
concept: edge_function_cold_start_resilience
sot_registry_entry: workout_completion_status
writers:
  - { file: lib/core/services/supabase_service.dart, method_or_widget: retryColdStart helper + _coldStartBackoffsMs schedule, line: 201 }
readers:
  - { file: lib/core/services/ai_service.dart, method_or_widget: chat (calls _supabase.callFunction ai-proxy), line: 263 }
  - { file: lib/core/services/ai_service.dart, method_or_widget: chatWithMedia (calls _supabase.callFunction ai-media-proxy), line: 402 }
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: AiBreakdownNotifier.analyse food_text_analysis, line: 602 }
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method_or_widget: _executeLogMealByText, line: 1108 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/contracts/edge_function_cold_start_retry_behavioral_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [edge_function_cold_start_retry]
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: |
  Bump retry schedule from `[1500, 4000]` ms (2 retries, ~5.5 s total)
  to `[2000, 6000, 12000]` ms (3 retries, ~20 s total). This matches
  the worst-case warm-start measurement of 20.2 s captured in the
  Test #15.3 / 7c4e1a diagnose, so a worst-case cold instance has
  budget to finish booting before the user-facing error fires.
  Extend the retry-trigger set from `{502, 503}` to also include 504
  (Gateway Timeout) since cold-start exhaustion can surface as either
  502 (gateway gave up) or 504 (gateway timed out waiting). 5xx 500
  remains a hard fail — it's a server-side runtime error, not a boot
  delay.
  `ai-media-proxy` callsites: the primary path
  (`AiService.chatWithMedia`) already goes through `_supabase.callFunction`
  → `retryColdStart`, so it inherits the bumped budget automatically.
  The web/CORS fallback `_directMediaHttpCall` is a fresh `http.post` —
  wrap it in a lightweight inline retry mirror that uses the same
  status-code gate + telemetry op_type, and matching schedule. Same
  treatment for the ai-proxy direct-HTTP fallback `_directHttpCall`.
  All telemetry continues to emit `edge_function_cold_start_retry` so
  every retry remains visible in `client_errors`.
  The 401-recursion guard (2026-04-07) is preserved — only 502/503/504
  are retryable; 4xx including 401/403 still rethrow immediately. The
  bounded loop (no recursion) is preserved — at most 4 total invocations
  on the worst path.
regression_test_planned:
  - test/contracts/edge_function_cold_start_retry_behavioral_test.dart
---

# Bug c01d57 — ai-proxy cold-start budget undersized for ~20s warm-start

## Symptoms

This morning (2026-05-15 09:33 IST) the founder saw "The AI is temporarily unavailable. Please try again in a minute." Edge Function logs show three back-to-back `ai-proxy` 502 BAD_GATEWAY responses:

- 09:33:12 IST — 502, execution_time 6128 ms
- 09:33:21 IST — 502, execution_time 6603 ms  (retry #1 after 1500 ms backoff)
- 09:33:30 IST — 502, execution_time 7202 ms  (retry #2 after 4000 ms backoff)

Schedule `[1500, 4000]` from Test #15.3 (`7c4e1a`, 2026-05-12) was already a bump from the original single-retry. It's not enough — the worst-case warm-start measurement captured in that same diagnose was **20.2 s**, and `ai-proxy` is the heaviest function in the project (Gemini model load + 20-tool registry boot). A ~5.5 s total wait window doesn't span the worst case.

Second observation: `ai-media-proxy` web/CORS fallback `_directMediaHttpCall` (used when the Supabase client throws `http.ClientException` or "Failed to fetch") fires a raw `http.post` with **zero retries**. Same for `_directHttpCall` on `ai-proxy`. Any 502 on the web fallback surfaces immediately as an `AiServiceException` to the user.

## Root cause

`lib/core/services/supabase_service.dart:201`:

```dart
static const List<int> _coldStartBackoffsMs = [1500, 4000];
```

3 attempts × backoffs that don't span 20 s = surfaced error during a normal cold-start window.

`lib/core/services/ai_service.dart:438` `_directMediaHttpCall` and `:336` `_directHttpCall` — direct `http.post` paths invoked on web fallback. They do not call `_supabase.callFunction`, so they never touch `retryColdStart`. A web user hitting CORS + a cold-start at the same time sees an immediate error.

## Fix

1. **Bump schedule** in `supabase_service.dart` to `[2000, 6000, 12000]` ms (3 retries → up to 4 total invocations → ~20 s wait window).
2. **Extend cold-start trigger** from `{502, 503}` to `{502, 503, 504}`. Cold-start gateway timeouts can present as 504; the semantics are the same (function booting, not yet ready). 500 stays excluded — that's a real server error, not a cold-start.
3. **Wrap `_directHttpCall` and `_directMediaHttpCall`** in an inline retry mirror that uses the same status gate (`502/503/504`) + same schedule + same `edge_function_cold_start_retry` telemetry op_type. Web fallback now inherits the same resilience.
4. **Preserve the 401-recursion guard** (2026-04-07). Only the documented status set is retryable; 401/403/4xx still rethrow immediately. Bounded loop (no recursion).

## Verification

Extends `test/contracts/edge_function_cold_start_retry_behavioral_test.dart` (created in Test #15.3) with new behavioral cases:

- **3× 502 then 200** — succeeds on attempt 4 (retry budget exhausted minus 1).
- **4× 502** — exhausts retries → rethrows last 502.
- **504 then 200** — newly-retryable status; succeeds on attempt 2.
- **502 + 500** — second attempt's 500 is NOT cold-start, must rethrow without further retry (preserves 2026-05-12 break/rethrow semantics, just with the wider retry set).
- Default-schedule test bumped from 3 to 4 expected invocations.

Each test comment cites the schedule change `[1500, 4000] → [2000, 6000, 12000]`.

## Risks

- **User-perceived worst-case wait jumps from ~5.5 s to ~20 s.** Acceptable trade — pre-fix the user saw a hard error and had to retap; post-fix they see a loading spinner for longer but the call succeeds. Telemetry will show retry frequency so we can re-tune if needed.
- **Edge Function quota.** Worst-case 4 invocations vs prior 3 — +33% on the heaviest failure mode. Cold-start invocations don't bill for completion (BAD_GATEWAY = no Gemini call), so the marginal cost is negligible.
- **504 in trigger set.** If Cloudflare/Supabase ever starts returning 504 for legitimate auth issues, we'd retry futilely. Mitigated by bounded loop + telemetry visibility — would surface immediately in `client_errors`.

## Related

- `7c4e1a` (2026-05-12) — supersedes its retry bounds while preserving design.
- `24d6d54` (2026-05-11) — original single-retry.
- `feedback_no_deferrals.md` — landing in same Test #15.5 batch as obs #4.
