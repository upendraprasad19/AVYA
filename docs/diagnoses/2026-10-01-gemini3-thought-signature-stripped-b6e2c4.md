---
bug_id: b6e2c4
date: 2026-10-01
batch: gemini3-limits-caching (Part A — outage fix)
status: fixed
blast_radius: platform
symptom: |
  Gemini 3 models attach `thoughtSignature` beside the `functionCall` part and require it back when the model turn is replayed in the next round. tool-loop.ts (line 360 when found; the store is now at :375) stored resp.parts, and geminiChatWithTools rebuilt each part as {functionCall:{name,args}} (and dropped text-part signatures), so round 2 of every tool turn would send a functionCall without a signature. Probe v2 (real calls on the new key): replaying the stripped turn is HTTP 400 "Function call is missing a thought_signature in functionCall parts" on gemini-3.1-flash-lite, gemini-3.5-flash-lite and gemini-3.8-flash; the raw echo is 200 on all three; the documented dummy skip_thought_signature_validator is 200; a 3.1->3.5 raw echo (default thinking config) is 200. Cross-model replay under thinkingLevel:minimal is UNPROVEN.
concept: gemini_flash_reliability
sot_registry_entry: null
writers:
  - { file: supabase/functions/_shared/gemini.ts, method_or_widget: "_callOnceWithTools part normalisation: every recognised part kept RAW (signature beside functionCall/text; signature-only part echoed)", line: 947 }
  - { file: supabase/functions/_shared/tool-loop.ts, method_or_widget: "messages.push model turn via fillMissingThoughtSignature(resp.parts)", line: 375 }
  - { file: supabase/functions/_shared/gemini.ts, method_or_widget: "fillMissingThoughtSignature: dummy only on the first functionCall of a turn that carries NO signature", line: 554 }
readers:
  - { file: supabase/functions/_shared/gemini.ts, method_or_widget: "geminiChatWithTools fallback safety net: 400 mentioning thought_signature -> retry THAT attempt once with dummy-filled history", line: 734 }
  - { file: supabase/functions/_shared/tool-loop.ts, method_or_widget: "round N+1 request body = the stored messages[] (the reader of the stored signature)", line: 375 }
hive_key_prefix: n/a
hive_key_formula: "n/a -- server-only Edge Function change"
sync_methods: []
restore_methods: []
cloud_table: "ai_coach_interactions / alerts (existing columns only)"
cloud_columns:
  - model_used
  - context_json
contract_test_path: supabase/functions/_shared/tool-loop_thought_signature_test.ts
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "n/a -- service-role Edge Functions; no per-user client state."
forbidden_patterns_checked:
  - { pattern: "a rebuilt {functionCall:{name,args}} part replacing the raw part in geminiChatWithTools", absent: true }
  - { pattern: "thoughtSignature or the dummy value reaching toolCallsLog / intents / text / any DB row (asserted by serialising the result)", absent: true }
proposed_fix: |
  1. Keep EVERY recognised part raw (`{...p, functionCall:{name,args}}` normalises name/args only), echo a signature-only part, keep text-part signatures. GeminiPart gains optional thoughtSignature.
  2. Defensive dummy fill happens when the model turn is STORED (tool-loop), never at parse time, ONLY on the first functionCall and ONLY when no part in the turn carries a signature (parallel calls carry one signature on the first call; the dummy is single-call-tested).
  3. Safety net (B-pass hardened): if ANY attempt (primary included) 400s with a body naming a missing thought signature (/thought[\s_]?signature/i, tested on the UNtruncated body so a long tool name cannot push the token past the 200-char preview), retry that attempt once with a FORCED dummy fill (first unsigned functionCall even when a text part carries a signature) and REUSE that dummy history for every later attempt and pass of the call; skipped when the fill would change nothing (an identical re-send). Any other 400 does not trigger it. The [text(sig), functionCall(unsigned)] wire shape is NOT probed; the forced fill bounds the risk.
3b. An empty-text part that only carries a signature is no longer accepted as a terminal reply on the tools path (geminiChat already treated !text as failure; the two paths now agree).
  4. Signatures live only in the in-memory messages[] of one request: toolCallsLog holds name/args only and nothing stringifies parts -- pinned by a test.
regression_test_planned: |
  supabase/functions/_shared/gemini3_migration_test.ts (raw functionCall part returned, text-part and signature-only parts kept, round-2 request body carries the signature, fillMissingThoughtSignature rules incl. no mutation of input, safety-net retry sequence [P, F, F] with dummy only in the third request, no retry on an unrelated 400), supabase/functions/_shared/tool-loop_thought_signature_test.ts (REAL runToolLoop 2-round turn: signature replayed exactly; dummy at store time; signature and dummy never in toolCallsLog/intents/text; modelUsed).
mutation_proof: |
  Rule 21 (applied-asserted, whole suite, restored): M4 strip the signature (drop ...p): 3 reds. M10 tool-loop stores a rebuilt functionCall: 2. M6 400 safety net disabled: 1. B-pass round: safety net skipped on the primary 4; dummy history not remembered 1; identical re-send guard removed 1; forced fill dropped 1; regex on the truncated preview 1; empty-text check deleted 1; anySig looks only at part 0 1; zero-arg args default dropped 1.
impact_analysis: |
  Every tool-using chat turn (a tool call in round 1, a reply in round 2) on any Gemini 3.x model: without this fix the turn 400s in round 2 and the user sees the hard-failure apology. A plain no-tool message passes either way, so the post-deploy smoke (A5) must use a 2-round tool turn for BOTH a free and a PRO user (different tool lists).
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
recurrence: none -- a new Gemini 3 API requirement (not a prior recurrence); the stored-turn shape was correct for 2.5
related_bugs: [f3a8d1, 7fbe21]
---

# tool-loop stored a rebuilt functionCall part, dropping the Gemini 3 thoughtSignature, so every tool-using chat turn would 400
