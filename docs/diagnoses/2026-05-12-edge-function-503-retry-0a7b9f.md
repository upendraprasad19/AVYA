---
bug_id: 0a7b9f
date: 2026-05-12
batch: APK Test #15.1
status: in_progress
symptom: Two surfaces affected. (G) Food text analysis returned "The AI is temporarily unavailable. Please try again in a minute." after the user typed a meal description and tapped Analyse & Log. (H) Telemetry shows push_snapshot FunctionException(status 503, BOOT_ERROR) for sumit1 at 06:46 UTC.
concept: edge_function_cold_start_resilience
sot_registry_entry: workout_completion_status
writers:
  - { file: lib/core/services/supabase_service.dart, method_or_widget: callFunction, line: 193 }
readers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: pushSnapshot (daily-snapshot call), line: 489 }
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: analyse food_text_analysis call, line: 613 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: [pushSnapshot]
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/contracts/edge_function_503_retry_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [push_snapshot, food_text_analysis]
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: |
  In SupabaseService.callFunction (the wrapper every Edge Function call
  routes through), catch FunctionException + retry once after 1500ms
  ONLY when status is 502 or 503. These are the cold-start / BOOT_ERROR
  signatures from supabase Edge Functions — transient. Other statuses
  (401, 403, 4xx) rethrow so callers can handle auth / validation
  errors. Persistent 5xx still surfaces (second attempt also fails →
  caller sees the error) so we don't mask a real outage.
regression_test_planned:
  - test/contracts/edge_function_503_retry_test.dart
---

# Bugs G + H — Edge Function 503 BOOT_ERROR cold-start retry

## Symptoms

**Bug G** (founder Obs 6): user typed meal description into food log, tapped Analyse & Log, got "The AI is temporarily unavailable. Please try again in a minute." This copy fires from `nutrition_provider.dart:693` when the caught error matches `503/502/unavailable/non-2xx/food ai/food analysis failed`.

**Bug H** (telemetry-surfaced): sumit1's session at 06:46 UTC produced 2x `push_snapshot FunctionException(status: 503, BOOT_ERROR, message: Function failed to start)` events in `client_errors`.

## Root cause

Edge Function logs confirm:
- `daily-snapshot` execution times routinely 39–40 seconds (Gemini extraction runs inline)
- When multiple users hit it concurrently, a cold-start instance returns 503 BOOT_ERROR while spinning up
- Same class affects `ai-proxy` (food_text_analysis)

No retry layer in client. First-attempt 503 surfaces as user-facing error even though the function would have succeeded 1–2 seconds later.

## Fix

Single attempt → one retry, in `SupabaseService.callFunction`:

```dart
FunctionResponse response;
try {
  response = await client.functions.invoke(name, headers: headers, body: body);
} on FunctionException catch (e) {
  final isColdStart502_503 = e.status == 502 || e.status == 503;
  if (!isColdStart502_503) rethrow;
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  response = await client.functions.invoke(name, headers: headers, body: body);
}
return response;
```

- **Only 502/503 trigger retry.** 401/403 still throw → caller handles auth refresh.
- **Single retry**, not exponential. If the function is still cold after 1.5s, more retries won't help quickly enough — second 503 surfaces to user with the existing copy.
- **1500ms delay** balances thundering-herd avoidance vs UX. Sub-1s would re-hit the same cold-start; >3s wastes user wait.

Applies to ALL functions routed through `callFunction`: pushSnapshot, food_text_analysis, scan_meal, cart_auditor, validate_promo, verify_payment, etc. Single defensive layer benefits everything.

## Verification

- 5 source-grep contract tests pass:
  - `on FunctionException catch (e)` present
  - `e.status == 502 || e.status == 503` gate present
  - retry delay 250–3000 ms range
  - exactly 2 `invoke()` calls in the method body (not 3+)
  - `if (!isColdStart502_503) rethrow;` present

## Skills evolution

Adding to `docs/sot_registry.yaml` in the skills-evolution sub-batch: every long-running Edge Function (>5s p95) should be documented as such; the client retry layer handles cold-start blips for them automatically. Suggested follow-up (deferred — out of this batch's scope per Bug-G/H sizing): split `daily-snapshot` into a fast upsert + async Gemini extraction so cold-starts complete quickly.

## Related

- `feedback_no_deferrals.md` — Bugs G + H ship in same batch.
- audit-batch H-42 retrofit (`baa9925`) — added the telemetry that surfaced this bug class.
