---
bug_id: c7f4d1
date: 2026-09-20
batch: food-logging-observations (fix round, B-pass reviewer B finding 3)
status: fixed
blast_radius: platform
symptom: |
  `reportGeminiExhaustion` used a constant `source` string
  ("ai_proxy_gemini_exhausted") for every one of the 3 ai-proxy request
  types (food_text_analysis, scan_meal, cart_auditor) it is called from
  — deliberately, so the 30-minute dedup window spans all three
  endpoints together. That same constant was also the ONLY identifier in
  the alert's `summary` text and `context_json`, so three otherwise-
  identical Telegram alerts (one per endpoint) were indistinguishable
  except by timestamp, defeating the feature's own stated purpose of
  fast diagnosis (a founder reading "Gemini exhausted all attempts —
  HTTP 429" has no way to tell which of the 3 nutrition AI features is
  actually broken). Found by B-pass reviewer B.
concept: gemini_failure_alert
sot_registry_entry: not_applicable
writers:
  - { file: supabase/functions/_shared/gemini_failure_alert.ts, method_or_widget: reportGeminiExhaustion, line: 32 }
readers:
  - { file: supabase/functions/ai-proxy/index.ts, method_or_widget: food_text_analysis handler, line: 443 }
hive_key_prefix: (n/a — server-side Edge Function, no Hive involvement)
hive_key_formula: (n/a)
sync_methods: []
restore_methods: []
cloud_table: alerts
cloud_columns: [summary, context_json]
contract_test_path: supabase/functions/_shared/gemini_failure_alert_test.ts
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: Not applicable — founder-only admin alert, not user data.
forbidden_patterns_checked: []
proposed_fix: |
  Add an optional 4th `endpoint?: string` parameter to
  `reportGeminiExhaustion`, used in the `summary` string
  (`${endpoint ?? source}: Gemini exhausted...`) and in `context_json`
  (`endpoint: endpoint ?? null`) — but NOT as the dedup key, so the
  30-minute same-source dedup window still spans all three endpoints
  together as originally designed. Wire the 3 ai-proxy call sites to
  pass their own request-type string ("food_text_analysis", "scan_meal",
  "cart_auditor").
regression_test_planned:
  - supabase/functions/_shared/gemini_failure_alert_test.ts
impact_analysis: |
  Purely additive: one new optional parameter with a safe fallback
  (`?? source`), used only in two display/diagnostic fields. The dedup
  query (`.eq("source", source)`) is untouched, so dedup behavior across
  the 3 endpoints is unchanged. No client-facing effect either way — the
  parameter only affects the founder-only Telegram alert's text.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: not_applicable, evidence: "Server-side only; no lib/ code touched." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "deno check --node-modules-dir=none supabase/functions/_shared/gemini_failure_alert.ts passes with 0 errors. NOT yet deployed — the live ai-proxy deploy remains a separate, founder-authorized action not requested this session." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "The client-facing ai-proxy response shape is unchanged; endpoint only reaches the founder-only alerts table." }
mutation_proven:
  mutated: "Changed the summary template from `${endpoint ?? source}: Gemini exhausted...` to `${source}: Gemini exhausted...`, dropping the endpoint fallback, confirmed applied by reading the file."
  result: "Ran `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/_shared/gemini_failure_alert_test.ts`: RED — 'endpoint distinguishes otherwise-identical alerts' failed (summary no longer started with 'scan_meal:'), 8 passed / 1 failed. Reverted the mutation; re-ran the full file: GREEN, 9/9 passed."
  confirmed_applied: "Read the file (Read tool) before and after each edit to confirm the template string matched the intended mutation."
---

## Summary

`reportGeminiExhaustion`'s alert text used only the constant `source` string, shared
across all 3 ai-proxy request types it is called from — so three otherwise-identical
Telegram alerts (one per endpoint) were indistinguishable except by their timestamp.

## Root cause

The `source` parameter deliberately stays constant across the 3 call sites so the
30-minute dedup window spans all of them together (a quota exhaustion on
`food_text_analysis` should suppress a near-simultaneous duplicate from `scan_meal`).
But that same constant doubled as the ONLY identifying text in the alert itself, so
the dedup design's necessary constant became an accidental information loss in the
alert's diagnostic content.

## Fix

Added an optional `endpoint?: string` 4th parameter, used only in the `summary` text
and `context_json` — never in the dedup query, which still keys on `source` alone.
Wired the 3 `ai-proxy` call sites to pass their own request-type string.

## Verification

- New test: with `endpoint: "scan_meal"`, the alert's `summary` starts with
  `"scan_meal:"` and `context_json.endpoint` is `"scan_meal"`.
- New mirror test: with `endpoint` omitted, `summary` falls back to `source` and
  `context_json.endpoint` is `null`.
- Mutation proof: dropped the `?? source` fallback in the summary template — the new
  test caught it; reverted, 9/9 green again.
- `deno check --node-modules-dir=none supabase/functions/_shared/gemini_failure_alert.ts`
  — 0 errors.

## Files changed

- Modified: `supabase/functions/_shared/gemini_failure_alert.ts` (landed in commit
  `7fa29427`, this batch's prior fix-round commit — the `endpoint?` parameter and its
  use in `summary`/`context_json` were part of that commit's diff).
- Modified: `supabase/functions/_shared/gemini_failure_alert_test.ts` (added the
  endpoint-identification test + its mirror case).
- Modified: `supabase/functions/ai-proxy/index.ts` (wired the 3 call sites to pass
  `"food_text_analysis"` / `"scan_meal"` / `"cart_auditor"`).
- Created: this diagnose-doc.
