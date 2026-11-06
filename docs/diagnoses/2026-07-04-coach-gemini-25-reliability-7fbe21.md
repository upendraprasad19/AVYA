---
bug_id: 7fbe21
date: 2026-07-04
batch: coach-gemini-reliability (Unit B — AI coach Gemini 2.5 reliability / FC1+FC2+FC3)
status: fixed
blast_radius: platform
symptom: >
  The AI coach and the meal-text parser were unreliable in three linked ways.
  (FC1) Gemini 2.5 Flash runs "thinking" ON by default and the hidden thinking
  tokens count against maxOutputTokens; with our low output caps (1024/800/2048)
  Flash spent the whole budget thinking and returned an EMPTY candidate
  (finishReason=MAX_TOKENS), which silently degraded to Flash-Lite — so the
  "primary Flash" path effectively never answered. (FC2) When a write intent was
  queued in an early round but a LATER summarization round hit a transient Gemini
  failure, the tool-loop surfaced "I had trouble reaching the model" OVER the
  working "Logged" APPLY card the user was looking at. (FC3) A one-shot empty
  Gemini response on the meal-text parse path failed the whole meal log with no
  retry.
concept: gemini_flash_reliability
sot_registry_entry: >
  Not a Hive/cloud writer-reader storage concept — this is Edge Function request
  shaping + tool-loop control flow (see the a4f7e1 precedent for a non-storage EF
  diagnose). The contract is: every NON-Pro Gemini attempt disables thinking
  (thinkingBudget:0) so the visible answer gets the full output budget; the tool
  loop never buries a queued intent under an apology; and the meal-text parse
  path retries a transient empty. Pinned by the co-located Deno tests below.
writers:
  - "{ file: supabase/functions/_shared/gemini.ts, method: _callOnce, line: 226 } — FC1: sets generationConfig.thinkingConfig.thinkingBudget=0 for every non-Pro attempt (single-turn path)."
  - "{ file: supabase/functions/_shared/gemini.ts, method: _callOnceWithTools, line: 548 } — FC1: same thinkingBudget:0 guard on the tool-calling path; MODEL_PRO keeps dynamic thinking."
  - "{ file: supabase/functions/_shared/gemini.ts, method: geminiChat retries loop, line: 125 } — FC3: wraps the [primary, Flash-Lite] attempt list in a for(pass=0; pass<=retries; pass++) loop with a 700ms backoff; retries defaults to 0 (unchanged for the ~17 other callers)."
  - "{ file: supabase/functions/_shared/gemini.ts, method: GeminiOptions.retries, line: 77 } — FC3: new optional retries?: number (default 0) on the options surface."
  - "{ file: supabase/functions/_shared/food_parser.ts, method: parseFoodText, line: 93 } — FC3: passes retries:2 so a transient empty on the meal-text path is absorbed instead of failing the whole meal log."
  - "{ file: supabase/functions/_shared/tool-loop.ts, method: runToolLoop geminiChatWithTools call, line: 128 } — FC1: passes maxTokens:2048 (was 1024 default) now that thinkingBudget:0 frees the cap for the visible answer."
  - "{ file: supabase/functions/_shared/tool-loop.ts, method: runToolLoop catch block, line: 143 } — FC2: apology gated on (!finalText && intents.length === 0) so a failed summarization round never overwrites a queued intent."
  - "{ file: supabase/functions/_shared/tool-loop.ts, method: runToolLoop loop-exit, line: 378 } — FC2: when intents.length>0 and no terminal text, sets a POSITIVE 'queued below, tap APPLY' confirmation instead of the exhaustion apology."
readers:
  - "{ file: supabase/functions/ai-proxy/index.ts, method: chat handler runToolLoop consumer, line: 716 } — consumes runToolLoop().text + intents to build the coach reply; benefits from FC1 (Flash answers) + FC2 (no apology over a queued card)."
  - "{ file: supabase/functions/_shared/tools/nutrition/logMealByText.ts, method: intentBuilder, line: 1 } — calls parseFoodText, which now retries a transient empty (FC3) instead of throwing intent_build_failed on the first blip."
  - "{ file: supabase/functions/_shared/gemini.ts, method: geminiChat attempt loop, line: 126 } — reads opts.model per attempt so the FC1 thinkingBudget guard is keyed on the ATTEMPT model (Flash + Lite get 0; Pro untouched)."
contract_test_path: supabase/functions/_shared/gemini_thinking_config_test.ts
hive_key_prefix: n/a (Edge Function request-shaping + control flow; no keyed Hive concept)
hive_key_formula: n/a
sync_methods: >
  n/a for the Gemini request shaping itself. Downstream, a coach log_set /
  log_meal intent that the user APPLIES routes through the normal WriteService
  sync fan-out — but that is unchanged by FC1/FC2/FC3.
restore_methods: n/a (request-shaping + tool-loop control flow; no restored state)
cloud_table: ai_coach_interactions
cloud_columns: >
  (the coach reply text + tool_calls JSONB are persisted by ai-proxy as before;
  FC1/FC2/FC3 change WHAT the model returns and how the loop narrates it, not the
  column set — no schema change.)
ist_handling: n/a (no date logic in the thinking-config / retry / apology paths)
provider_invalidations: >
  n/a server-side. Client-side, an APPLIED coach intent invalidates its domain
  providers via the usual WriteService path — unchanged by this batch.
telemetry_op_types: >
  No new op type. Existing breadcrumbs: geminiChat logs "recovered (model →
  attempt, pass N)" on an FC3 retry recovery; geminiChatWithTools logs fallback /
  recovery; tool-loop logs the max-rounds-exhausted line. FC1's effect is visible
  as a drop in the Flash→Flash-Lite fallback rate.
cross_account_guard: >
  user-scoped — ai-proxy authenticates the caller (service-role getUser(token))
  before runToolLoop; the tool context is user-scoped. The thinking-config /
  retry / apology changes carry no cross-account surface.
forbidden_patterns_checked: >
  A non-Pro Gemini attempt must NOT ship dynamic thinking on our low output caps
  (both _callOnce and _callOnceWithTools guard on opts.model !== MODEL_PRO). The
  tool-loop must NOT surface a "trouble reaching the model" / "ran out of steps"
  apology when intents.length>0 (both the catch guard and the loop-exit branch
  enforce this). MODEL_PRO must KEEP thinking (weekly-report reasoning) — the
  guard is keyed to exclude Pro.
proposed_fix: >
  FC1 — set generationConfig.thinkingConfig.thinkingBudget=0 for every non-Pro
  attempt in both _callOnce and _callOnceWithTools, keyed on the attempt model so
  Flash + its Lite fallback disable thinking while MODEL_PRO keeps it; raise the
  tool-loop's maxTokens 1024→2048 now that the visible answer gets the full cap.
  FC2 — gate the tool-loop catch-block apology on (!finalText && intents.length
  === 0) and replace the loop-exit exhaustion message with a positive
  "queued below, tap APPLY" confirmation when intents were queued. FC3 — add an
  optional retries?: number (default 0) to GeminiOptions and wrap geminiChat's
  attempt list in a bounded pass loop with a 700ms backoff; parseFoodText opts in
  with retries:2 (defense-in-depth on top of FC1's thinkingBudget:0).
regression_test_planned: >
  supabase/functions/_shared/gemini_thinking_config_test.ts (Deno, 2 cases) —
  MODEL_FLASH request body has thinkingConfig.thinkingBudget===0; MODEL_PRO
  (fallbackToLite:false) has generationConfig.thinkingConfig undefined. Mirrors
  the fetch-stub pattern in gemini_backoff_retry_test.ts.
  supabase/functions/_shared/tool-loop_intent_apology_test.ts (Deno, 1 case) —
  a round queues a logSet intent then a later round fails persistently;
  runToolLoop().text is NOT the "trouble reaching the model" apology and one
  intent is present. FC3's retry path is additionally covered by the existing
  gemini_backoff_retry_test.ts (bounded retry semantics). Both new Deno tests are
  written for CI — Deno is not installed on the dev machine, so they could not be
  run locally.
touched_layers_checked:
  - "{ layer: edge_function_code_vs_deploy, status: fixed_in_this_batch, evidence: gemini.ts _callOnce (l226) + _callOnceWithTools (l548) add thinkingBudget:0 for non-Pro; geminiChat (l125) adds the retries pass loop; food_parser (l93) passes retries:2; tool-loop maxTokens:2048 (l128), catch guard (l143), loop-exit positive confirmation (l378). ai-proxy redeploy is the live-ship step (deploy authorization is a separate explicit go). }"
  - "{ layer: client_to_server_contract, status: verified, evidence: the coach reply contract (text + intents) is unchanged in shape — FC1 makes Flash actually answer, FC2 changes the narration when an intent is queued, FC3 makes the meal-text parse survive a transient empty. No client change required to consume it. }"
  - "{ layer: client_code, status: verified, evidence: the client already renders runToolLoop().text + APPLY card for a queued intent; FC2 only changes which server string it shows. No client edit in this batch. }"
  - "{ layer: postgres_schema, status: not_applicable, evidence: no schema change — request-shaping + control-flow only. }"
  - "{ layer: postgres_data, status: not_applicable, evidence: no data change — the coach reply/tool_calls persist as before. }"
  - "{ layer: secrets_api_keys, status: verified, evidence: GEMINI_API_KEY usage is unchanged; thinkingConfig is a request-body field, not a credential. }"
impact_analysis: >
  Pre-fix the coach's PRIMARY model (Flash) frequently returned an empty
  candidate because thinking consumed the whole low output budget, so the app
  silently rode on Flash-Lite (weaker) and — when even the fallback blipped —
  surfaced an apology, sometimes OVER a working queued "Logged" card, and the
  meal-text parser failed the whole log on a single transient empty. Post-fix:
  FC1 disables thinking for every non-Pro attempt so Flash gets its full output
  budget and actually answers (Pro/weekly-report keeps thinking); FC2 guarantees
  a queued intent is never buried under an apology and instead gets a positive
  APPLY confirmation; FC3 gives the meal-text path two bounded backoff retries so
  a transient empty no longer drops the meal. The changes are request-shaping +
  tool-loop control flow — no schema, no data backfill. Live-ship is an ai-proxy
  redeploy, which requires its own explicit deploy authorization per §4.3.
closes-diagnose: 7fbe21
---

# 7fbe21 — Coach Gemini 2.5 reliability: silent Flash empties, buried intents, one-shot parse failures

## What happened
Three linked reliability defects on the AI coach + meal-text path:

- **FC1 — Flash returned empty candidates.** Gemini 2.5 Flash runs "thinking" ON
  by default and the hidden thinking tokens count against `maxOutputTokens`. With
  our low caps (1024 tool-loop / 800 parser / 2048), Flash could spend the entire
  budget thinking and return an empty candidate (`finishReason=MAX_TOKENS`). The
  caller then degraded to Flash-Lite (thinking OFF by default), so the "primary
  Flash" path effectively never answered.
- **FC2 — a queued intent got buried under an apology.** If an early round queued
  a write intent (the APPLY card) but a later summarization round hit a transient
  Gemini failure, `runToolLoop` set `finalText = "I had trouble reaching the
  model…"` — shown OVER the working "Logged" card.
- **FC3 — a one-shot empty failed the whole meal log.** `parseFoodText` had no
  retry, so a single transient empty threw and failed the entire
  `log_meal_by_text` action.

## Root cause
FC1: default-on thinking + a low output cap is a silent-empty trap on Gemini 2.5.
FC2: the catch/exhaustion paths chose the apology unconditionally, ignoring
whether an intent had already been queued. FC3: the single-turn `geminiChat` had
no retry on a transient empty, and the parser is the one path where that empty is
user-fatal (no tool-loop retry above it).

## Fix
1. **FC1** — `thinkingBudget: 0` for every non-Pro attempt in both `_callOnce`
   and `_callOnceWithTools` (keyed on the attempt model, so Flash + its Lite
   fallback disable thinking; `MODEL_PRO` keeps dynamic thinking for the
   weekly-report reasoning path). Raise the tool-loop `maxTokens` 1024→2048 now
   that the visible answer owns the full cap.
2. **FC2** — gate the catch-block apology on `!finalText && intents.length === 0`
   and replace the loop-exit exhaustion message with a positive "queued below,
   tap APPLY" confirmation when `intents.length > 0`.
3. **FC3** — add an optional `retries?: number` (default 0) to `GeminiOptions`;
   `geminiChat` wraps its attempt list in a bounded pass loop with a 700ms
   backoff; `parseFoodText` opts in with `retries: 2` (defense-in-depth on top of
   FC1). The ~17 other `geminiChat` callers keep `retries: 0` — no latency/quota
   regression for the cron generators.
4. **Tests** — two new Deno tests (`gemini_thinking_config_test.ts`,
   `tool-loop_intent_apology_test.ts`) plus the existing
   `gemini_backoff_retry_test.ts` for the bounded-retry semantics.

## Recurrence
FC2 is the same "flakiness surfaces a raw apology" class as **d4f1c2** (the
tool-loop backoff-retry diagnose) — d4f1c2 added the retry that recovers the
transient blip; FC2 fixes the *narration* when the blip still lands after an
intent was queued. FC1 is a new Gemini-2.5-specific request-shaping defect. The
ship step is an ai-proxy redeploy (separate explicit deploy authorization per
§4.3).

## Blast-radius reasoning (Hermes P3-DOC-1)

Two questions arose about `thinkingBudget: 0` and the shared `gemini.ts`
bundle. Recording the reasoning so a future audit doesn't have to re-derive it:

- **No cron / JSON-caller regression from `thinkingBudget: 0`.** Every JSON
  caller passes `jsonMode` (which sets `responseMimeType: "application/json"`),
  and that constraint guarantees a well-formed JSON candidate *independently* of
  whether thinking is on — the structured-output decode does not rely on a
  thinking pass. The short-copy alert crons (morning/evening alert, protein-gap,
  plateau, etc.) emit a single short string and do no multi-step reasoning, so
  removing the hidden thinking budget cannot degrade their output; it only frees
  the (already ample) output cap. `MODEL_PRO` — the only caller that genuinely
  benefits from thinking (weekly-report deep reasoning) — is explicitly excluded
  from the guard.
- **Deploying `ai-proxy` alone is a graceful partial rollout, not a
  coordinated-deploy requirement.** `thinkingConfig` and the retry loop live in
  the shared `_shared/gemini.ts`, but each Edge Function carries its own bundled
  copy at its last deploy. Redeploying `ai-proxy` updates only `ai-proxy`; the
  cron fleet keeps serving the *prior* bundled `gemini.ts` until each function is
  itself redeployed. That is safe: the new behavior (retries default `0`,
  thinking-off for non-Pro) is a strict, backward-compatible improvement — a
  cron on the old bundle simply keeps its pre-fix behavior with no contract
  break. So the crons can be redeployed opportunistically (or on their next
  routine deploy); no lock-step, all-at-once ship is needed.
