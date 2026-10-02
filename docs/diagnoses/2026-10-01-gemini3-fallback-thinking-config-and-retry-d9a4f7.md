---
bug_id: d9a4f7
date: 2026-10-01
batch: gemini3-limits-caching (Part A — outage fix)
status: fixed
blast_radius: platform
symptom: |
  (1) Both request builders sent generationConfig.thinkingConfig = {thinkingBudget:0} for every non-MODEL_PRO attempt. Probe v2: gemini-3.5-flash-lite REJECTS thinkingBudget:0 with HTTP 400 on every request shape (plain, JSON, vision, tool, cache), so with the old code the fallback attempt could never succeed. The `opts.model !== MODEL_PRO` thinking guard also misfires once every tier shares one slug. (2) Retry eligibility: geminiChatWithTools tracked `lastRetriable` from the last attempt only, so primary 429 + fallback 404 aborted the retry of the healthy-but-throttled primary; geminiChat had no retriability notion at all and retried on any null.
concept: gemini_flash_reliability
sot_registry_entry: null
writers:
  - { file: supabase/functions/_shared/gemini.ts, method_or_widget: "THINKING_BY_MODEL capability table + thinkingConfigFor (off={thinkingLevel:minimal}, on={thinkingLevel:low}); unknown slug -> no config + warn", line: 98 }
  - { file: supabase/functions/_shared/gemini.ts, method_or_widget: "_callOnce / _callOnceWithTools resolve thinkingConfig from the ATTEMPT model", line: 409 }
  - { file: supabase/functions/weekly-report/index.ts, method_or_widget: "thinking:'on' (line 558), maxTokens 4096 (line 559; thought tokens count against the cap)", line: 558 }
readers:
  - { file: supabase/functions/_shared/gemini.ts, method_or_widget: "geminiChatWithTools per-pass passHadRetriableFailure (any attempt), pruned list, attempts.length>0", line: 771 }
  - { file: supabase/functions/_shared/gemini.ts, method_or_widget: "geminiChat passHadTransientFailure (null / 408 / 425 / 429 / 5xx only; a deterministic SAFETY/RECITATION/PROHIBITED_CONTENT/BLOCKLIST/SPII block is never transient)", line: 319 }
hive_key_prefix: n/a
hive_key_formula: "n/a -- server-only Edge Function change"
sync_methods: []
restore_methods: []
cloud_table: "ai_coach_interactions / alerts (existing columns only)"
cloud_columns:
  - model_used
  - context_json
contract_test_path: supabase/functions/_shared/gemini_thinking_config_test.ts
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "n/a -- service-role Edge Functions; no per-user client state."
forbidden_patterns_checked:
  - { pattern: "thinkingBudget anywhere in a request body or in the capability table", absent: true }
  - { pattern: "a retry decision based on only the last attempt's status", absent: true }
  - { pattern: "weekly-report maxTokens 1500 with thinking on", absent: true }
proposed_fix: |
  1. Capability table keyed by the ATTEMPT slug; `off` = thinkingLevel minimal and `on` = low (probe-proven 200 on BOTH Lite models in every shape, 0 vs ~135 thought tokens). Per-call `thinking` option (default off) replaces the identity test. Unknown slug: send no thinkingConfig and warn (never throw -- legacy test slugs flow through the real function; an omitted config is 0 thoughts on the Lite models).
  2. Per-attempt retriability in both loops: a pass is retried when ANY attempt failed transiently (null/429/5xx; tools: result.retriable), the 404'd model is pruned, never when only non-429 4xx remain; existing wall-clock deadlines unchanged.
  3. weekly-report: thinking on + maxTokens 1500 -> 4096 (founder decision: 3.1-flash-lite, thinking on; a 1,000-token synthetic prompt measured ~135 thought tokens at low).
regression_test_planned: |
  supabase/functions/_shared/gemini_thinking_config_test.ts (rewritten: default off = minimal and never thinkingBudget; on = low; the FALLBACK attempt resolves its OWN row in both loops -- proven by making the rows differ for the test; unknown slug sends nothing; every exported MODEL_* has an off+on row), supabase/functions/_shared/gemini3_migration_test.ts (per-attempt retry sequences in both loops incl. transport nulls), supabase/functions/_shared/gemini3_callsites_test.ts (weekly-report thinking on + 4096; no other function enables thinking).
mutation_proof: |
  Rule 21: M3 thinking row not resolved per attempt: 3 reds. M5 tools loop reverted to last-attempt retriability: 1. M7c: 1. M12 weekly-report maxTokens back to 1500: 1 (presence-only; the module calls serve() at import so only the call site can be pinned). B-pass round: 5xx threshold: 1; 408: 1; deterministic check: 1; both deadlines: 1 each; 403 pruned as unavailable: 1.
impact_analysis: |
  Every Gemini call: before, the fallback attempt 400'd on thinkingBudget:0. weekly-report is the only caller with thinking on (ONE call per user per week), cost +~135 thought tokens. The probe measured thinkingLevel:high at ~850 thought tokens and 2x latency for a similar answer, so `low` was chosen.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: verified, evidence: "No client behaviour change (lib/core/services/ai_service.dart:64 is a doc comment). 200+ source-grep/contract Dart tests that read the changed EF files re-run green (hard_failure_apology_texts_parity_test, ai_proxy_placeholder_resolution*, vision/food cap pins, weekly_report_*)." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "Server-side Edge Function change; sync_coach.dart already excludes model_used='failed' rows on restore and is unchanged." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "Part A has no migration (alerts.context_json is an existing jsonb column; backups/live_schema_columns.json lists it)." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "alerts rows 55-62 (read-only, earlier this session) show only the FALLBACK's 404 for every exhausted call; no existing ai_coach_interactions row carries model_used='failed' (live count query), so stamping the sentinel orphans nothing." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration in Part A." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "deno check --node-modules-dir=none clean for ai-proxy, ai-media-proxy, weekly-report, assess-body-composition, daily-snapshot, rolling-context; whole-tree deno test 821 passed with 2 failures that are the honcho-api Docker container holding port 8000 on this VPS (AddrInUse in re-engagement and future-prediction, files this batch does not touch; CI has no such conflict). Full TZ=Asia/Kolkata flutter test --exclude-tags golden: 7303 passed, 0 failed; flutter analyze lib/: 0 warnings/errors. DEPLOYED 2026-10-02 on the founder's go, host-shell deploy from merged main 9fb68189 (PR #65): ai-proxy v92, ai-media-proxy v31, weekly-report v34, assess-body-composition v21, daily-snapshot v32, rolling-context v25; versions and unchanged verify_jwt confirmed read-only via MCP list_edge_functions. Each deploy's own smoke reached the function; ai-proxy also answered an anon-Bearer POST with its own 401, not a 503, so it booted. The real free and PRO user-token smoke (a 2-round tool turn, the 7/7 and 20/20 429 copy) is NOT yet run: it needs user JWTs." }
  - { tier: 7, name: "Cron jobs", status: verified, evidence: "rolling-context (nightly cron) imports gemini.ts + gemini_failure_alert.ts, so it rides this change; it keeps its own alert source rolling_context_gemini_exhausted and retries:1." }
  - { tier: 10, name: "Secrets / API keys", status: verified, evidence: "The NEW GEMINI_API_KEY (paid-tier project) returns 200 for gemini-3.1-flash-lite / gemini-3.5-flash-lite / gemini-embedding-001 and HTTP 404 for every gemini-2.5-* slug (founder-run probes v2 + v3, 2026-10-01; summary docs/audit/2026-10-01-gemini3-probe-summary.md)." }
  - { tier: 11, name: "External services", status: verified, evidence: "Real Gemini calls on the new key: 404 bodies for retired and unknown slugs captured as test fixtures; thinkingLevel minimal/low accepted by both Lite models; thinkingBudget:0 rejected (400) by 3.5; thought-signature 400 reproduced and the raw-echo / dummy fixes proven 200." }
  - { tier: 12, name: "Client -> server contract", status: fixed_in_this_batch, evidence: "tool-loop_thought_signature_test.ts drives the REAL runToolLoop through a 2-round tool turn and asserts round 2's request carries the signature; the post-deploy A5 smoke (real free + PRO user token, 2-round tool turn) is the live end-to-end proof and is blocked_on_user." }
recurrence: 7fbe21 FC1 (docs/diagnoses/2026-07-04-coach-gemini-25-reliability-7fbe21.md): the same 'thinking config follows the attempt model' rule, re-expressed for the Gemini 3 API
related_bugs: [f3a8d1, 7fbe21]
---

# The 2.5-era thinkingBudget:0 400s on gemini-3.5-flash-lite, and retry eligibility keyed on the LAST attempt only
