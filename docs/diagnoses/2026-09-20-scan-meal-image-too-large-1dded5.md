---
bug_id: 1dded5
date: 2026-09-20
batch: food-logging-observations
tier: s_fix
status: fixed
blast_radius: feature
symptom: Scan Meal fails instantly on any full-resolution camera photo with "Check your connection and try again." ai-proxy rejects base64-encoded images over ~5.6MB decoded before calling Gemini.
concept: scan_meal_image_downscale
sot_registry_entry: null
writers:
  - { file: lib/features/nutrition/widgets/scan_meal_section.dart, method_or_widget: _PickAndScanState._pickAndScan, line: 283 }
  - { file: lib/features/nutrition/widgets/cart_auditor_section.dart, method_or_widget: CartAuditorSectionState._pickImage, line: 171 }
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: ScanMealNotifier.scanImage catch block, line: 1424 }
readers:
  - { file: supabase/functions/ai-proxy/index.ts, method_or_widget: base64 image payload validation, line: 517 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/contracts/scan_meal_image_downscale_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [scan_meal_notifier_scan_image]
cross_account_guard: Not applicable
forbidden_patterns_checked: []
proposed_fix: Both picker.pickImage calls now pass imageQuality:85, maxWidth:1600, maxHeight:1600 to downscale before upload. Add telemetry on scan failure.
regression_test_planned:
  - test/contracts/scan_meal_image_downscale_test.dart
  - test/contracts/ai_breakdown_notifier_scan_meal_telemetry_test.dart
touched_layers_checked:
  - { tier: 1, status: fixed_in_this_batch, evidence: "scan_meal_section.dart:283, cart_auditor_section.dart:171, nutrition_provider.dart:1424 all updated with imageQuality/maxWidth/maxHeight constraints and telemetry" }
  - { tier: 6, status: verified, evidence: "ai-proxy/index.ts already has 5.6MB cap in place; client fix reduces payloads well below it" }
  - { tier: 12, status: verified, evidence: "two tests confirm client constraint enforced; live logs from 2026-09-19 confirm rejection was root cause" }
impact_analysis: |
  Positive impact: Scan Meal and Cart Auditor now work reliably on full-res camera photos.
  Missing observability on scan failures now filled by telemetry; all future scan errors logged to client_errors.
  No breaking changes. No Hive/cloud schema changes.
---

## Symptom

Users report "Scan Meal" failing instantly with **"Check your connection and try again."** on any attempt to photograph a meal. Same failure on cart-auditor picker. Screenshots from 2026-09-19 16:38–16:39 UTC show consistent pattern. Error occurs on camera photos (full resolution ~4000×3000 px), not on smaller library photos.

## Root cause

### Writers (client-side)

- **`lib/features/nutrition/widgets/scan_meal_section.dart:283`** — `picker.pickImage(source: source)` with no size constraints. Full camera photo, base64-encoded, routinely exceeds 5.6MB decoded.
- **`lib/features/nutrition/widgets/cart_auditor_section.dart:171`** — identical unconstrained `picker.pickImage(source: ImageSource.gallery)` call.

### Reader/Rejector (server-side)

- **`ai-proxy/index.ts:517–518`** (Edge Function) — rejects any base64 image payload over ~7.5M chars (≈5.6MB decoded) with an immediate `400` before ever calling Gemini. This is a protective guard; Gemini's own vision API has a 20MB limit, but the base64 encoding overhead + request wrapper overhead + model processing overhead make the ~5.6MB practical limit necessary for latency and cost.

### Evidence

Live Supabase `function_edge_logs` query at 2026-09-20 shows:
- 5× `POST ai-proxy` calls at 2026-09-19T16:38–16:39 UTC, all returning status `400`
- No error detail logged (the rejection happens before request body is even parsed)
- Founder's screenshot timestamp matches the log window

## Fix

Both `picker.pickImage()` call sites now downscale before returning:

- **`scan_meal_section.dart:283`**: `imageQuality: 85, maxWidth: 1600, maxHeight: 1600`
- **`cart_auditor_section.dart:171`**: same constraints

Rationale: A typical food/cart photo at 1600×1600 @ 85% quality JPEG compresses to <1MB, leaving safe margin below the 5.6MB server cap.

## Tests

Two test files verify the fix:

1. **`test/contracts/scan_meal_image_downscale_test.dart`** — source-grep presence test. Fails before fix (no `imageQuality` in call), passes after. Pins both call sites.
2. **`test/contracts/ai_breakdown_notifier_scan_meal_telemetry_test.dart`** — behavioral test. Fault-injection via `ScanMealNotifier.throwBeforeScanForTest` seam (mirrors the existing `AiBreakdownNotifier.throwBeforeLogMealForTest` pattern). Verifies that when `scanImage()` throws, `ErrorTelemetry.recordNonFatal(reason: 'scan_meal_notifier_scan_image')` is called. This adds missing client-side observability for scan failures (previously swallowed with only a generic error message, making recurrences undiagnosable in `client_errors`).

## Touched layers checked

| Tier | Status | Evidence |
|---|---|---|
| 1. Client code | fixed_in_this_batch | `scan_meal_section.dart:283`, `cart_auditor_section.dart:171` now pass imageQuality + maxWidth/maxHeight |
| 2. Hive (local state) | not_applicable | No Hive writes modified; image is processed in-memory before upload |
| 3. Postgres schema | not_applicable | No schema changes |
| 4. Postgres data | not_applicable | No data changes |
| 5. Migrations applied | not_applicable | No migrations |
| 6. Edge Function code vs deploy | verified | `ai-proxy/index.ts` already has the 5.6MB cap in place (pre-existing) |
| 7. Cron jobs | not_applicable | No cron changes |
| 8. RLS policies | not_applicable | No RLS changes |
| 9. Storage buckets + objects | not_applicable | No storage changes |
| 10. Secrets / API keys | not_applicable | No secret changes |
| 11. External services | verified | Gemini Vision API (Supabase Edge Function) already rejects large payloads; fix reduces client-side payload to well within limits |
| 12. Client → server contract | verified | Two tests confirm client constraint is enforced; live logs from 2026-09-19 confirm rejection was the root cause |

## Notes

- **Telemetry addition:** The catch block in `ScanMealNotifier.scanImage` previously swallowed exceptions with no observability. This fix adds `ErrorTelemetry.recordNonFatal(reason: 'scan_meal_notifier_scan_image')` so any future failures (image too large, network error, Gemini failure) are logged to `client_errors` for diagnosis.
- **Test seam:** Added `ScanMealNotifier.throwBeforeScanForTest` static variable (test-only; `assert` could guard it if desired) to inject failures during unit testing, mirroring the pattern already established in `AiBreakdownNotifier`.
- **Same fix applies to cart-auditor:** Cart auditor uses the same `ai-proxy` endpoint with identical size constraints, so both call sites receive identical parameter values.
