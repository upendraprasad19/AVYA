---
bug_id: a5c8e2
date: 2026-10-01
batch: gemini3-limits-caching (Part A — outage fix)
status: fixed
blast_radius: platform
symptom: |
  When runToolLoop returns hadHardFailure (the hardcoded 'I had trouble reaching the model' apology), ai-proxy's reservation-resolve UPDATE wrote that text with the real model label (`loop.usedFallback ? LABEL_FLASH_LITE : LABEL_FLASH`) and tokens_used=0. chat_dedup.ts dedupDecision treats any row with a non-empty ai_response whose model_used is not the failure sentinel as a normal reply, so a retry of the same message inside the 30-second dedup window received the apology as a 200 reply, and the cloud row is indistinguishable from a real reply (the a1c6b9 history-poisoning class; the client-side guards cover the live Hive path and a restore by exact apology text only).
concept: coach_chat_history_replay
sot_registry_entry: null
writers:
  - { file: supabase/functions/_shared/row_model_label.ts, method_or_widget: "rowModelLabel(hadHardFailure, modelUsed, sentinel): sentinel on a hard failure, labelForModel(slug that answered) otherwise", line: 20 }
  - { file: supabase/functions/ai-proxy/index.ts, method_or_widget: "chat reservation-resolve UPDATE writes model_used: rowModelUsed (inline, on the existing success path; NOT through failReservation, which is Part B)", line: 1151 }
readers:
  - { file: supabase/functions/_shared/chat_dedup.ts, method_or_widget: "dedupDecision: model_used === sentinel -> replay_failure", line: 32 }
  - { file: supabase/functions/ai-proxy/index.ts, method_or_widget: "dedup branch consults dedupDecision(recentDup, MODEL_USED_LOOP_THREW_SENTINEL)", line: 778 }
  - { file: lib/core/services/sync/sync_coach.dart, method_or_widget: "_restoreCoachInteractions excludes model_used == 'failed' (unchanged)", line: 47 }
hive_key_prefix: n/a
hive_key_formula: "n/a -- server-only Edge Function change"
sync_methods: []
restore_methods: []
cloud_table: "ai_coach_interactions / alerts (existing columns only)"
cloud_columns:
  - model_used
  - context_json
contract_test_path: supabase/functions/_shared/row_model_label_test.ts
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "n/a -- service-role Edge Functions; no per-user client state."
forbidden_patterns_checked:
  - { pattern: "the real model label written on a row whose reply is the hardcoded apology", absent: true }
  - { pattern: "the sentinel in the CLIENT response body (the response keeps the real label + had_hard_failure)", absent: true }
  - { pattern: "failReservation() or any Part B helper referenced from Part A code (the hard_failure_apology_texts_parity test slices catch (loopErr))", absent: true }
proposed_fix: |
  Stamp MODEL_USED_LOOP_THREW_SENTINEL ('failed', ai-proxy:115) when loop.hadHardFailure, through the pure rowModelLabel (unit-testable; ai-proxy calls serve() at module scope). The CLIENT response and embedding metadata keep the real provider label via labelForModel(loop.modelUsed ?? MODEL_FLASH), and had_hard_failure is unchanged. ToolLoopResult gains modelUsed so the label no longer relies on usedFallback (every tier shares one slug now). dedupDecision then returns the new `replay_hard_failure` for a sentinel row holding a delivered apology -- ai-proxy replays the SAME flagged 200 (reply, had_hard_failure:true, deduplicated:true) the original request got -- and keeps `replay_failure` (the 502) only for the loop-THREW marker row, empty or non-string text (fail safe: never serve unknown text). B-pass R2 found that a 502 for a delivered apology would send the client's cold-start retry (2/6/12 s) into the same dedup hit for ~20 s before an error bubble. sync_coach.dart already skips the row on restore, and the two SERVER readers that feed `Coach:` text into prompts now skip it too: daily-snapshot's conversation read adds `.or("model_used.is.null,model_used.neq.failed")` (NULL-safe: a bare .neq would drop NULL rows under SQL three-valued logic) and rolling-context selects model_used, never embeds or summarises `failed` rows, but still DELETES them with the rest. Part B later folds this stamp into failReservation() and repoints the contract test.
regression_test_planned: |
  supabase/functions/_shared/row_model_label_test.ts (sentinel on hard failure, real label otherwise, END-TO-END: the label rowModelLabel produces is what dedupDecision reads -- failed row -> replay_failure, good row -> replay_reply; ai-proxy wiring pin: row label via rowModelLabel with the sentinel, response keeps the real label), supabase/functions/_shared/chat_dedup_test.ts (existing), test/contracts/hard_failure_apology_texts_parity_test.dart (still green: the inline stamp sits outside its catch (loopErr) slice).
mutation_proof: |
  Rule 21: M11 rowModelLabel returns the real label on a hard failure: 2 reds (the unit case and the end-to-end dedup case). M14 prediction label ignoring the slug: 1 (the label-from-slug pin). B-pass round (the presence tests were satisfiable by dead code: three mutations survived with ZERO reds, so the wiring pins were rewritten as position-pinned slices of the real UPDATE / catch / call): UPDATE writes the client label: 1; ai-media-proxy constant label + a stray void call: 1; replay fallback label 'unknown': 1; throw-catch stamp a re-typed literal: 1; food label a constant: 1; hard-failure dedup branch collapsed to replay_failure: 2; daily-snapshot .or removed: 2 and the bare-neq variant: 9 (after the fake was made SQL-NULL-faithful); rolling-context embeds failed rows: 1.
impact_analysis: |
  A user whose request hit total Gemini exhaustion: the retry within 30 s used to get the apology back as a successful 200 reply and still does (now flagged had_hard_failure so the client keeps it out of history, matching the first response), while a loop-THREW row replays its 502 as before. The row itself is now marked, so restore, dedup and the two server prompt-readers can tell it from a real reply. Verified live count: no existing row carries model_used='failed' from this path. The apology no longer looks like a real reply in the cloud table either.
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
recurrence: a1c6b9 (docs/diagnoses/2026-09-16-coach-history-poisoning-hard-failure-a1c6b9.md): same history-poisoning class, a third writer path (the success-path resolve UPDATE) the original fix did not cover
related_bugs: [a1c6b9, e5c9d2]
---

# ai-proxy persisted the hardcoded failure apology with the REAL model label, so dedup replayed it as a normal reply
