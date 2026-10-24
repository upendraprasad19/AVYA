---
bug_id: f3a8d1
date: 2026-10-01
batch: gemini3-limits-caching (Part A — outage fix)
status: fixed
blast_radius: platform
symptom: |
  The new GEMINI_API_KEY returns HTTP 404 "no longer available to new users" for the retired gemini-2.5-* slugs (gemini-2.5-flash-lite was probed; 2.5-flash and 2.5-pro were reported 404 by the founder, not probed), so ai-proxy chat, food text, scan, cart, prediction, ai-media-proxy, assess-body-composition, daily-snapshot, rolling-context and weekly-report all exhausted both attempts (primary and fallback were both 2.5 slugs). Chat was down in production. Three secondary defects made it worse: (a) a 404 was not classified anywhere -- alerts 55-62 show only the FALLBACK's 404, so a retired primary followed by a transient fallback 503 would have read as 'transient, no action needed'; (b) geminiChat retried on ANY null including a 404, burning two extra passes on a model that can never answer (10 call sites set retries); (c) the fallback guard `model !== MODEL_FLASH_LITE` would, once every tier shares one slug, silently remove the fallback for every call.
concept: gemini_flash_reliability
sot_registry_entry: null
writers:
  - { file: supabase/functions/_shared/gemini.ts, method_or_widget: "MODEL_* constants (one per tier, all gemini-3.1-flash-lite) + MODEL_FALLBACK gemini-3.5-flash-lite", line: 82 }
  - { file: supabase/functions/_shared/gemini.ts, method_or_widget: "geminiChat / geminiChatWithTools: attempts list [model, MODEL_FALLBACK], per-attempt status capture, 404 prune", line: 319 }
  - { file: supabase/functions/_shared/gemini_failure_alert.ts, method_or_widget: "alertClass: model_unavailable when ANY attempt was a 404, else quota / auth / one collapsed `transient` class (5xx, timeouts, unclassified -- so one outage pages once, not once per last-attempt status); class stored in alerts.context_json.class and part of the dedup key", line: 32 }
readers:
  - { file: supabase/functions/_shared/gemini_failure_alert.ts, method_or_widget: "reportGeminiExhaustion dedup select filters context_json->>class", line: 108 }
  - { file: supabase/functions/ai-proxy/index.ts, method_or_widget: "every exhaustion site passes attemptStatuses (food, scan, cart, prediction via prediction_handler, tool-loop chat catch)", line: 502 }
hive_key_prefix: n/a
hive_key_formula: "n/a -- server-only Edge Function change"
sync_methods: []
restore_methods: []
cloud_table: "ai_coach_interactions / alerts (existing columns only)"
cloud_columns:
  - model_used
  - context_json
contract_test_path: supabase/functions/_shared/gemini3_migration_test.ts
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "n/a -- service-role Edge Functions; no per-user client state."
forbidden_patterns_checked:
  - { pattern: "a call site opting out of the fallback with fallbackToLite:false (the four 'already Lite' sites)", absent: true }
  - { pattern: "any gemini-2.5 slug or 'Gemini 2.5' label in non-test function code", absent: true }
  - { pattern: "a tier comparison against a MODEL_* constant (identity no longer distinguishes tiers)", absent: true }
proposed_fix: |
  Founder decision D2 (2026-10-01): gemini-3.1-flash-lite for every tier, gemini-3.5-flash-lite as the second attempt, one constant per tier so a revert is one line.
  1. gemini.ts: new constants; fallback guard `model !== MODEL_FALLBACK` in BOTH loops; the four fallbackToLite:false sites lose their `false` (option name kept: CI runs deno test --no-check).
  2. A 404 prunes that model for the rest of THIS call (no cross-request negative cache); a pass whose only failures are non-429 4xx is never retried; retry eligibility is judged per attempt (see d9a4f7).
  3. GeminiResult and the thrown tools Error carry attemptStatuses (every attempt, a side field -- lastError stays {status,message}); reportGeminiExhaustion classes the alert model_unavailable when ANY attempt was a 404 (suggested action: change the constant), stores the class in context_json.class, and keys dedup on it so a different-class outage inside the window is not downgraded.
  4. A structured `[gemini] MODEL_UNAVAILABLE model=<m>` log line on every 404.
regression_test_planned: |
  supabase/functions/_shared/gemini3_migration_test.ts (35 after the B-pass round: constants/labels, fallback guard in both loops, 404 prune, both-404 one pass, attemptStatuses incl. transport nulls, 5xx/408/403 classification, deterministic blocks not retried, both wall-clock deadlines, the MODEL_UNAVAILABLE and trying-fallback log lines), supabase/functions/_shared/tool-loop_gemini_exhaustion_alert_test.ts (a 404 primary + 503 fallback reaches the alert as model_unavailable WITH both statuses, through the REAL runToolLoop), supabase/functions/_shared/gemini_failure_alert_test.ts (alertClass over every attempt, both real 404 body shapes as fixtures, dedup keyed per class and a different class not suppressed), supabase/functions/_shared/gemini3_callsites_test.ts (presence-only for the module-scope serve() files: no fallbackToLite:false, no 2.5 slug, every exhaustion report passes attemptStatuses).
mutation_proof: |
  Rule 21, each mutation confirmed APPLIED by an exact-count assertion, whole Deno suite run, file restored byte-for-byte and re-compared; reddened = tests beyond the 2 known env failures. M1 fallback guard collapsed to !== MODEL_FLASH_LITE in both loops: 21 reds. M2 attempts.push(model): 12 (recounted by the B-pass reviewer; 11 was an earlier miscount). M7a no 404 prune in geminiChat: 1. M7b no 404 prune in the tools loop: ZERO at first (the existing 404+503 test only asserted statuses), fixed by asserting the call sequence [P,F,F], then 1 red. M7c geminiChat counts a 404 as transient: 1. M8 alertClass ignores earlier attempts: 2. M9 dedup not keyed per class: 2. M13 ai-proxy scan restores fallbackToLite:false: 1 (presence).
mutation_proof_bpass_round: |
  B-pass round 2026-10-01 (three context-blind reviewers + the author re-running their surviving mutations; each applied-asserted, whole suite, restored and re-compared). New protection and its reds: geminiChat 5xx threshold >=600: 1; 408 dropped: 1; deterministic-block check dropped: 1; geminiChat deadline removed: 1; tools deadline removed: 1; 403 treated as model-unavailable: 1; MODEL_UNAVAILABLE/trying-fallback log position: 1; tool-loop attemptStatuses typo (the chat catch, previously ZERO reds because the only pin was a presence grep satisfied by the type annotation): 1; alert classes not collapsed: 3. The prior zero-red mutations in this area (deadlines, 5xx threshold, 403) are now red.
  Accepted without a code change, with reasons: (a) an empty MAX_TOKENS candidate is still retried in geminiChat -- it is the FC1 symptom (the fallback answers where the primary spent its budget) and cannot be told apart from a transient empty; (b) defensive guards `attempts.length === 0` / `> 0` and the iteration copy are equivalent mutants (documented in comments, not claimed as covered).
impact_analysis: |
  Who: every user of chat, food text, scan/cart, prediction, body-composition, daily snapshot, photo chat and the weekly report. Behaviour change: with one live model and a fallback on a different model, a single retired or throttled slug no longer takes a feature down, and a retired model now pages as model_unavailable with the one-line fix named. Cost: none beyond the intended 3.1-flash-lite pricing. Deploy: gemini.ts and gemini_failure_alert.ts are imported by the whole fleet, so ai-proxy deploys first, then a real chat smoke (A5), then the rest.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: verified, evidence: "No client behaviour change (lib/core/services/ai_service.dart:64 is a doc comment). 200+ source-grep/contract Dart tests that read the changed EF files re-run green (hard_failure_apology_texts_parity_test, ai_proxy_placeholder_resolution*, vision/food cap pins, weekly_report_*)." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "Server-side Edge Function change; sync_coach.dart already excludes model_used='failed' rows on restore and is unchanged." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "Part A has no migration (alerts.context_json is an existing jsonb column; backups/live_schema_columns.json lists it)." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "alerts rows 55-62 (read-only, earlier this session) show only the FALLBACK's 404 for every exhausted call; no existing ai_coach_interactions row carries model_used='failed' (live count query), so stamping the sentinel orphans nothing." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration in Part A." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "deno check --node-modules-dir=none clean for ai-proxy, ai-media-proxy, weekly-report, assess-body-composition, daily-snapshot, rolling-context; whole-tree deno test 821 passed with 2 failures that are the honcho-api Docker container holding port 8000 on this VPS (AddrInUse in re-engagement and future-prediction, files this batch does not touch; CI has no such conflict). Full TZ=Asia/Kolkata flutter test --exclude-tags golden: 7303 passed, 0 failed; flutter analyze lib/: 0 warnings/errors. DEPLOYED 2026-10-02 on the founder's go, host-shell deploy from merged main 9fb68189 (PR #65): ai-proxy v92, ai-media-proxy v31, weekly-report v34, assess-body-composition v21, daily-snapshot v32, rolling-context v25; versions and unchanged verify_jwt confirmed read-only via MCP list_edge_functions. Each deploy's own smoke reached the function; ai-proxy also answered an anon-Bearer POST with its own 401, not a 503, so it booted. The real free and PRO user-token smoke (a 2-round tool turn, the 7/7 and 20/20 429 copy) is NOT yet run: it needs user JWTs." }
  - { tier: 7, name: "Cron jobs", status: verified, evidence: "rolling-context (nightly cron) imports gemini.ts + gemini_failure_alert.ts, so it rides this change; it keeps its own alert source rolling_context_gemini_exhausted and retries:1." }
  - { tier: 10, name: "Secrets / API keys", status: verified, evidence: "The NEW GEMINI_API_KEY (paid-tier project) returns 200 for gemini-3.1-flash-lite / gemini-3.5-flash-lite / gemini-embedding-001 and HTTP 404 for gemini-2.5-flash-lite plus an unknown slug (founder-run probes v2 + v3, 2026-10-01; 2.5-flash and 2.5-pro were reported 404 by the founder but not probed; summary docs/audit/2026-10-01-gemini3-probe-summary.md)." }
  - { tier: 11, name: "External services", status: verified, evidence: "Real Gemini calls on the new key: 404 bodies for retired and unknown slugs captured as test fixtures; thinkingLevel minimal/low accepted by both Lite models; thinkingBudget:0 rejected (400) by 3.5; thought-signature 400 reproduced and the raw-echo / dummy fixes proven 200." }
  - { tier: 12, name: "Client -> server contract", status: fixed_in_this_batch, evidence: "tool-loop_thought_signature_test.ts drives the REAL runToolLoop through a 2-round tool turn and asserts round 2's request carries the signature; the post-deploy A5 smoke (real free + PRO user token, 2-round tool turn) is the live end-to-end proof and is blocked_on_user." }
recurrence: 7fbe21 (docs/diagnoses/2026-07-04-coach-gemini-25-reliability-7fbe21.md, gemini_flash_reliability: the same helper, a different failure mode -- thinking tokens exhausting the output cap)
related_bugs: [7fbe21, a1c6b9, f7a2c9]
---

# A retired model slug (HTTP 404 on the new key) took every Gemini call down and was classified as nothing
