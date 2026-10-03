---
bug_id: 7ad0d6
date: 2026-05-11
batch: audit-2026-05-11
status: shipped
symptom: 3 Edge Function input-validation gaps. (H-21) ai-proxy `scan_meal` + `cart_auditor` accepted `body.image` (base64) with NO size validation — a 50MB+ blob would forward to Gemini unbounded, burning cost + Edge Function memory. ai-media-proxy already enforces 5MB; ai-proxy was the gap. (H-22) ai-proxy `food_text_analysis` accepted `body.text` with NO length cap, while the chat channel had a 5000-char cap on `message`. (H-23) ai-media-proxy PRO image-chat path had NO per-day rate limit — a compromised PRO token could drain unlimited Gemini-vision quota in minutes.
concept: edge_input_validation
sot_registry_entry: edge_function_input_validation
writers:
  - { file: supabase/functions/ai-proxy/index.ts, method_or_widget: scan_meal/cart_auditor image cap + food_text_analysis length cap, line: 297 }
  - { file: supabase/functions/ai-media-proxy/index.ts, method_or_widget: PRO daily image-chat cap, line: 318 }
readers: []
hive_key_prefix: "n/a — Edge Function input validation"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: ai_coach_interactions
cloud_columns: [user_id, channel, created_at]
contract_test_path: "n/a — TS Edge Function input bounds; verified by deploy + manual oversize tests"
ist_handling: ["istDayStartIso() for PRO image-chat daily window"]
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: ["ai_proxy_image_no_size_check", "ai_proxy_food_text_no_length_cap", "ai_media_proxy_pro_no_rate_limit"]
proposed_fix: (H-21) inside the scan_meal/cart_auditor branch, validate body.image is a string + base64 length ≤ 7.5M chars (~5.6MB decoded, matches ai-media-proxy's 5MB hard ceiling with a small slop margin). Return 400 on violation. (H-22) inside food_text_analysis branch, validate body.text is a string + length ≤ 5000. Mirrors the chat channel cap. (H-23) add PRO_IMAGE_DAILY_CAP=50; new helper countProImageAnalysesToday() walks ai_coach_interactions filtered by IST-day start; gate PRO image-chat behind it with a 429 + Retry-After: 3600.
regression_test_planned:
  - "n/a — TS Edge Function bounds; verified by deploy"
---
# Audit H-21 / H-22 / H-23: Edge Function input validation

## H-21: ai-proxy scan_meal/cart_auditor image size

**File:** `supabase/functions/ai-proxy/index.ts:297-308`

Pre-fix: `body.image` (base64 string) was forwarded directly to
Gemini. ai-media-proxy enforces a 5MB hard ceiling; ai-proxy did
NOT. A malicious / accidental 50MB base64 blob would:
- Consume Edge Function memory (Deno isolate cap).
- Burn Gemini per-call cost (input bytes are billed).
- Potentially trigger Gemini's internal payload reject after we've
  already paid for the upload bandwidth.

**Fix:** validate `body.image` is a string + length ≤ 7.5M chars
(≈ 5.6MB decoded — small slop above the 5MB ceiling so legitimate
5MB images don't edge-trip). Return 400 on violation.

## H-22: ai-proxy food_text_analysis no length cap

**File:** `supabase/functions/ai-proxy/index.ts:195-209`

Pre-fix: the chat path validates `message` ≤ 5000 chars
(line 425-427), but `food_text_analysis` had no equivalent check on
`body.text`. A 1MB description would forward to Gemini unbounded —
same cost class as H-21 but easier to trigger (no image required).

**Fix:** validate `text` is a string + length ≤ 5000 (same as
chat). Return 400 on violation.

## H-23: ai-media-proxy PRO image-chat no rate limit

**File:** `supabase/functions/ai-media-proxy/index.ts:318-350`

Pre-fix: free users had a 5-LIFETIME image-analysis cap (good).
PRO users had NO cap at all — a compromised PRO token could drain
unlimited Gemini-vision quota in minutes.

**Fix:** `PRO_IMAGE_DAILY_CAP = 50` per user per IST day.
- New helper `countProImageAnalysesToday()` walks
  `ai_coach_interactions` filtered by `channel` ∈
  `('pro_image_analysis', 'image_analysis')` and
  `created_at >= istDayStartIso()` (IST midnight aligned).
- Gate inserted after the free-user paywall branch and before the
  Gemini call.
- Over-cap: 429 with `{ code: 'RATE_LIMITED', limit, used_today }`
  + `Retry-After: 3600`.

50/day is well above legitimate use (~2 photos/hour over 24h) but
stops the abuse case cold.

## Deploys

- `ai-proxy`
- `ai-media-proxy`

Suite: 1569 pass / 0 fail / 2 skip (Dart-only — Edge Function
changes don't affect the client test suite).

## Related

- CLAUDE.md §11 Input Validation section (existing 5K char + 10K
  snapshot + 5MB image caps documented for the chat channels)
- 7ad0d3 (Phase 3 IST sweep — istDayStartIso() helper used here)
