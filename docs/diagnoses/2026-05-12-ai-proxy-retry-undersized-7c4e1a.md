---
bug_id: 7c4e1a
date: 2026-05-12
batch: APK Test #15.3
status: in_progress
symptom: User tapped "Analyse & Log" on Nutrition → Log Food → AI tab. Got toast "The AI is temporarily unavailable. Please try again in a minute." Same error class also fires from AI coach `logMealByText` tool dispatch when ai-proxy is cold. Edge-function logs show two consecutive POST /ai-proxy 502 BAD_GATEWAY at 05:08:05 UTC (8475 ms) and 05:08:13 UTC (6654 ms); the next successful call ~3 min later took 20219 ms (warm-start completion).
concept: edge_function_cold_start_resilience
sot_registry_entry: workout_completion_status
writers:
  - { file: lib/core/services/supabase_service.dart, method_or_widget: callFunction retry block, line: 226 }
readers:
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: AiBreakdownNotifier.analyse food_text_analysis call, line: 602 }
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method_or_widget: _executeLogMealByText, line: 1108 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/contracts/retry_loop_guard_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [edge_function_cold_start_retry, food_text_analysis, log_meal_by_text]
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: |
  Bump the existing single retry to TWO retries with backoff schedule
  [1500ms, 4000ms]. Edge Function cold-start on ai-proxy can take 20+
  seconds when Gemini is loading the model; one retry at 1500 ms isn't
  enough wait time for the second invocation to land on a warm
  instance. Two retries at 1.5s + 4s give a ~5.5 s total wait window —
  enough to catch most cold-starts while still surfacing a real outage
  to the user reasonably quickly. Each retry emits an
  ErrorTelemetry.logEvent with op_type
  `edge_function_cold_start_retry` and attempt+backoff details so ops
  can see cold-start frequency in `client_errors`. The existing
  502/503-only gate is preserved; non-cold-start errors still rethrow
  immediately. The 401-recursion guard from 2026-04-07 stays intact
  (no 401 retry, no `return send()` recursion in AiCoachProvider).
regression_test_planned:
  - test/contracts/retry_loop_guard_test.dart
---

# Bug 7c4e1a — ai-proxy retry undersized for 20s cold-start

## Symptoms

User tapped **Analyse & Log** on the Nutrition → Log Food → AI tab. Toast read "The AI is temporarily unavailable. Please try again in a minute." (mapped from `nutrition_provider.dart:602` `AiBreakdownNotifier.analyse`). The same `callFunction('ai-proxy', ...)` is used by the AI coach `logMealByText` tool dispatch in `tool_dispatcher.dart:1108`, which surfaces the same error class.

Direct evidence from edge-function logs:

- `POST /ai-proxy` → 502 BAD_GATEWAY at 05:08:05 UTC, 8475 ms
- `POST /ai-proxy` → 502 BAD_GATEWAY at 05:08:13 UTC, 6654 ms (retry from `callFunction`)
- next successful POST ~3 min later took 20219 ms to warm-start the function

## Root cause

The single retry added on 2026-05-11 (`24d6d54`, APK Test #15.1 / Bug G+H) is correct in shape but undersized in timing. At `supabase_service.dart:215-243`:

```dart
} on FunctionException catch (e) {
  final isColdStart502_503 = e.status == 502 || e.status == 503;
  if (!isColdStart502_503) rethrow;
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  response = await client.functions.invoke(name, headers: headers, body: body);
}
```

One retry at 1500 ms covers a fast cold-start, but `ai-proxy` is one of the heaviest functions (loads Gemini model + tools registry on boot). The warm-start measurement of 20.2 s shows we need a longer total wait window before giving up. The user saw the toast because both invocations (initial + 1500 ms retry) fired while the function was still booting.

## Fix

Replace the inline single-shot retry with a const backoff schedule and loop:

```dart
static const List<int> _coldStartBackoffsMs = [1500, 4000];

// in callFunction:
int attempt = 0;
while (true) {
  try {
    response = await client.functions.invoke(name, headers: headers, body: body);
    return response;
  } on FunctionException catch (e) {
    final isColdStart = e.status == 502 || e.status == 503;
    if (!isColdStart || attempt >= _coldStartBackoffsMs.length) rethrow;
    final backoffMs = _coldStartBackoffsMs[attempt];
    unawaited(ErrorTelemetry.logEvent(
      'edge_function_cold_start_retry',
      message: 'fn=$name attempt=${attempt + 1} status=${e.status} backoff_ms=$backoffMs',
    ));
    await Future<void>.delayed(Duration(milliseconds: backoffMs));
    attempt++;
  }
}
```

Properties:

- **Up to 3 total invocations** (1 initial + 2 retries) — bounded loop, no recursion.
- **Backoff schedule [1500ms, 4000ms]** — ~5.5 s total wait window before the user-facing error fires.
- **502/503-only gate preserved.** 401/403/4xx still rethrow immediately; the 2026-04-07 retry-loop bug class (401-recursion compounding with AiCoachProvider) is not re-introduced.
- **Telemetry per retry.** `op_type=edge_function_cold_start_retry`, fire-and-forget so the retry's own latency isn't doubled by the log-client-error round-trip.
- **Public signature unchanged.** Callers see the same `FunctionResponse` on success or the same `FunctionException` on persistent failure.

## Verification

`test/contracts/retry_loop_guard_test.dart` source-grep guards updated:

- "at most 2 invocations" → "at most 3 invocations" (1 initial + 2 retries).
- existing 401-recursion guard intact (`response.status == 401` still forbidden).
- 502/503 gate assertion intact.
- new assertion: backoff const list `_coldStartBackoffsMs` present and length == 2.
- new assertion: retry path emits `edge_function_cold_start_retry` telemetry op_type.
- new assertion: telemetry is `unawaited` so retry isn't double-latency-hit.

## Related

- `feedback_no_deferrals.md` — landing in the same Test #15.3 batch as other Test #15.2 install observations.
- `24d6d54` (2026-05-11) — Bug G+H, original single-retry; this commit supersedes its retry bounds while preserving its design.
