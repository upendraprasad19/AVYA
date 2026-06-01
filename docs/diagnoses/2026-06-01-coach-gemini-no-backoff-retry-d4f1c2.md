---
bug_id: d4f1c2
date: 2026-06-01
batch: derive-only-ai-coach-tool-surface
status: fixed
blast_radius: platform
symptom: >
  Driving the AI coach live as amar, messages intermittently came back with
  "I had trouble reaching the model. Try again in a moment." — and the SAME
  message succeeded on a manual retry seconds later. Verified in
  ai_coach_interactions: the 01:20 UTC "Create a custom exercise..." turn and
  the 01:23 UTC "Give me my progress summary" turn both had tool_calls=null
  and that apology, while a 20:40 UTC logSet turn had tool_calls=[array] (the
  set WAS queued on round 1) yet still showed the apology (round-2 narration
  failed). The founder's premise was "client times out while the server
  finishes in 13s" — investigation INVERTED that: the server itself gave up.
  Every ai-proxy gateway log was HTTP 200 in 5-13.6s (none near the 25s
  per-call timeout), so the apology is generated server-side and returned 200.
concept: ai_coach_tool_loop_gemini_resilience
sot_registry_entry: >
  not_applicable — this is Edge Function upstream-call resilience (Gemini),
  not a Hive/cloud writer/reader SoT concept. The coach tool path is charted
  under COACH-* in docs/architecture/functionality-flow.md and docs/architecture/ai.md.
recurrence: "First SERVER-side instance of the missing-backoff-retry-on-transient-upstream class. The CLIENT-side analog is the retryColdStart helper (lib/core/services/supabase_service.dart, debugging skill 2.5) added for Edge Function cold-starts — the server->Gemini hop lacked the equivalent."
related_bugs:
  - 7c4e1a
  - c01d57
writers:
  - supabase/functions/_shared/gemini.ts geminiChatWithTools (FIX: bounded, time-spaced backoff-retry over the [Flash -> Flash-Lite] attempt list for the RETRIABLE bucket, capped by TOOLS_MAX_PASSES + a wall-clock deadline)
  - supabase/functions/_shared/gemini.ts _callOnceWithTools (FIX: returns retriable:boolean so the caller distinguishes a transient 429/5xx/empty from a 25s timeout or a non-429 4xx)
readers:
  - supabase/functions/_shared/tool-loop.ts runToolLoop (catches a geminiChatWithTools throw and surfaces the "I had trouble reaching the model" apology — now only fires after the bounded retries are exhausted)
  - supabase/functions/ai-proxy/index.ts (returns reply + tool_intents; the apology lands in ai_coach_interactions.ai_response with tool_calls=null)
hive_key_prefix: not_applicable
hive_key_formula: not_applicable (no Hive key involved — server-side Edge Function resilience)
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: ai_coach_interactions
cloud_columns: >
  ai_coach_interactions(id, user_id, channel, user_message, ai_response,
  model_used, tokens_used, tool_calls, created_at). The symptom AND the fix are
  observable here: a failed turn = ai_response apology + tool_calls null; a
  fixed turn = the tool's "queued"/"ok" record in tool_calls + a real reply.
contract_test_path: supabase/functions/_shared/gemini_backoff_retry_test.ts
ist_handling: not_applicable (no date math changed)
provider_invalidations: not_applicable (server-side path; no client provider state touched)
telemetry_op_types: >
  not_applicable for client telemetry. Server observability ADDED: a per-attempt
  console.warn now carries `retriable=<bool> pass=<n>`, and a successful retry
  logs `recovered on retry pass=<n> model=<m>` so a transient-vs-persistent
  Gemini failure is greppable in the edge-function logs.
cross_account_guard: >
  not_applicable — the retry layer is per-request and stateless; ai-proxy's
  userId scoping and auth are unchanged. No cross-account state is read or
  written by the resilience change.
forbidden_patterns_checked:
  - "Abandon the Gemini tool call on the FIRST transient failure with zero backoff-retry (only an immediate Flash->Flash-Lite fallback that shares the same project quota) — eliminated: the whole attempt list is re-run with a 700ms backoff for the retriable bucket; pinned by gemini_backoff_retry_test.ts case 'recovers a transient 5xx on the retry pass'."
  - "Retry a 25s timeout in place (would risk the overall wall clock) — explicitly NOT retriable (AbortError -> retriable:false); pinned by the 'does NOT retry a timeout' test."
  - "Retry a non-429 4xx (a malformed request a different model/retry can't fix) — explicitly NOT retriable (status===429||status>=500 only); pinned by the 'does NOT retry a non-429 4xx' test."
  - "Unbounded retry loop — bounded by TOOLS_MAX_PASSES(2) and TOOLS_RETRY_DEADLINE_MS(20s); pinned by the 'stays bounded on a persistent retriable failure' test (asserts exactly 4 calls then throw)."
proposed_fix: >
  In geminiChatWithTools, wrap the existing [primary -> Flash-Lite] attempt
  list in a bounded outer loop: on a RETRIABLE failure of the whole pass, sleep
  TOOLS_PASS_BACKOFF_MS (700ms) and re-run the list, up to TOOLS_MAX_PASSES (2)
  and only while elapsed < TOOLS_RETRY_DEADLINE_MS (20s). _callOnceWithTools now
  returns retriable:boolean — true for HTTP 429/5xx and empty/no-candidate
  (transient overload), false for a 25s AbortError timeout (budget already
  spent) and non-429 4xx (a retry can't help; SAFETY/RECITATION/PROHIBITED
  content blocks are deterministic so also non-retriable). The happy path is
  unchanged (success returns on the first call — pinned by the happy-path test
  asserting exactly 1 call). tool-loop.ts is untouched: its catch remains the
  final graceful apology, now reached only after the bounded retries fail. This
  also closes a narrow double-apply edge: a partial multi-round failure
  (round-1 queues a write intent, round-2 narration throws) returned the apology
  WITH a live tool_intent (ai-proxy returns tool_intents regardless of text), so
  a confused user re-sending could double-apply — the retry lets round-2 narrate
  normally, so the user sees a confirmation instead of an apology.
regression_test_planned: >
  supabase/functions/_shared/gemini_backoff_retry_test.ts — a BEHAVIORAL Deno
  test that stubs globalThis.fetch (no module-mock shim needed; geminiChatWithTools
  calls the global directly) with 5 cases: (1) transient 503 on both models pass-0
  then 200 pass-1 -> returns ok, exactly 3 fetch calls; (2) non-429 4xx -> throws,
  exactly 2 calls (no retry pass); (3) AbortError timeout -> throws, exactly 2
  calls (no retry pass); (4) persistent 429 -> throws, exactly 4 calls (bounded);
  (5) happy path -> exactly 1 call. Runs under `deno test --allow-env`. NOTE: the
  repo does not gate Deno tests in pre-commit/CI (consistent with the existing
  _shared/**/*_test.ts files; tool-loop_test.ts documents this), and Deno is not
  on the local PATH — so this fix is ALSO proven by the live web E2E below.
touched_layers_checked:
  - { tier: 6, layer: edge_function_code_vs_deploy, status: fixed_in_this_batch, evidence: "gemini.ts geminiChatWithTools now retries the retriable bucket with a 700ms backoff bounded by 2 passes + a 20s deadline; ai-proxy redeployed host-shell (byte-identical config verify_jwt=false) -> HTTP 201 version 69 ACTIVE; deploy smoke POST returned HTTP 401 (auth-required function reachable -> deployment confirmed)" }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "ai_coach_interactions before/after on amar: 01:20 UTC createCustomExercise turn + 01:23 UTC progress-summary turn = tool_calls null + ai_response 'I had trouble reaching the model'; after v69 the identical createCustomExercise message at 03:59:08 UTC = tool_calls [createCustomExercise status=queued] + ai_response 'I have created Cable Face Pull'" }
  - { tier: 12, layer: client_server_contract, status: verified, evidence: "live web E2E (amar, real CanvasKit, foreground tab): the previously-failing 'Create a custom exercise now: Cable Face Pull...' message drove the tool end-to-end on v69 -> coach narrated success -> APPLY -> 'Created' chip -> cloud user_custom_exercises row ca8cbdac-fbc3-569d-813b-5da972e341c4 (name Cable Face Pull, category pull, logging_type weight_reps, equipment_needed [full_gym]). Zero apology." }
impact_analysis: >
  Platform blast radius — touches geminiChatWithTools, the single Gemini
  tool-calling entry point behind EVERY user's AI coach chat turn. Before the
  fix the coach gave up on the FIRST transient Gemini blip: the two-model
  attempt list (Flash -> Flash-Lite) fires back-to-back on the same project
  quota, so one rate-limit/overload window trips both in ~1-2s and runToolLoop
  surfaces the apology with no retry. Gemini returns transient 429/503/empty
  under normal load, so any user sending a couple of quick messages could see
  it; the trigger this session was the rapid E2E test burst (a matching 20+
  log-client-error storm at ~20:36 UTC corroborates). The fix is additive and
  conservative: the success path is unchanged (1 call), retries fire only on
  transient failures, timeouts and 4xx are never retried, and the total is
  bounded by 2 passes + a 20s deadline — worst-case added latency on a fast
  transient is one extra pass (~2 calls + one 700ms sleep), and the slow
  (timeout) path is never worse than before. It only converts
  previously-FAILING turns into successes. It also closes a narrow re-send
  double-apply edge (partial round-1 write + round-2 narration failure). Found
  live during the derive-only AI-coach batch's cross-surface E2E on amar.
---

# AI coach "I had trouble reaching the model" — server gave up on a transient Gemini blip with zero backoff-retry

## What happened

Driving the live coach as amar, some turns came back "I had trouble reaching
the model. Try again in a moment." — and re-sending the SAME message seconds
later worked. The founder framed it as a **client timeout** ("client gives up
while the server finishes in 13s, possible double-apply").

Investigation inverted the premise:

- Every `ai-proxy` gateway log was **HTTP 200 in 5–13.6s** — none near the 25s
  per-call timeout. The client did not time out; the **server returned 200 with
  an apology body**.
- `ai_coach_interactions` showed the failing turns with `tool_calls=null` +
  the apology, while a `logSet` turn at 20:40 UTC had `tool_calls=[array]` (the
  set WAS queued on round 1) yet still apologised — a **multi-round** failure
  where round-2 narration threw.

## Root cause

`runToolLoop` (tool-loop.ts:127–138) catches **any** throw from
`geminiChatWithTools` and immediately writes the apology — **no retry**.
`geminiChatWithTools` (gemini.ts) tries `[Flash → Flash-Lite]` **once each,
back-to-back, with no time spacing**, both on the same `GEMINI_API_KEY`/project
quota. A transient 429/5xx/empty-candidate blip that hits the project trips
**both** attempts within ~1–2s, so the function `throw`s and the coach gives
up. Waiting ~1s and retrying — what a user does by hand, and what succeeded —
is exactly what the code never did. The codebase already has this pattern
**client-side** (`retryColdStart`, debugging skill §2.5) for Edge Function
cold-starts; the **server→Gemini** hop lacked it.

## Fix

Wrap the attempt list in a bounded outer loop: on a **retriable** failure of the
whole pass, sleep `TOOLS_PASS_BACKOFF_MS` (700ms) and re-run, up to
`TOOLS_MAX_PASSES` (2) and only while `elapsed < TOOLS_RETRY_DEADLINE_MS` (20s).
`_callOnceWithTools` now returns `retriable:boolean` — **true** for HTTP 429/5xx
and empty/no-candidate; **false** for a 25s timeout (budget spent) and non-429
4xx / deterministic content blocks (a retry can't help). Happy path unchanged.
`tool-loop.ts` is untouched — its catch is still the final graceful apology,
now reached only after the bounded retries fail.

This also closes a narrow **double-apply** edge: ai-proxy returns `tool_intents`
even when the text is the apology (index.ts:872), so a partial multi-round
failure left a live APPLY card next to the apology — a re-send could double-log.
With the retry, round-2 narrates normally and the user sees a confirmation.

## Verification

- `flutter`/Dart not involved (Edge Function TS). Deno not on local PATH; the
  repo does not gate Deno tests — so verified by review + the live E2E below.
- Regression spec `supabase/functions/_shared/gemini_backoff_retry_test.ts`
  (5 cases: recover-on-503 = 3 calls; no-retry-4xx = 2; no-retry-timeout = 2;
  bounded-persistent-429 = 4; happy-path = 1).
- Deploy: `ai-proxy` host-shell redeploy → **HTTP 201 version 69 ACTIVE**
  (`verify_jwt:false` unchanged); deploy smoke **HTTP 401 = reachable**.
- Live (amar, real CanvasKit): the message that failed at 01:20 UTC
  ("Create a custom exercise … Cable Face Pull") now drives the tool on v69 —
  `ai_coach_interactions` 03:59:08 UTC turn has `tool_calls=[createCustomExercise
  status=queued]`, the coach narrated success, APPLY → "Created", and the cloud
  `user_custom_exercises` row `ca8cbdac-fbc3-569d-813b-5da972e341c4` landed.
  Zero apology.

## Lesson / class

First **server-side** instance of *missing backoff-retry on a transient upstream
call*. A two-model fallback that fires back-to-back on one shared quota is NOT a
retry — a transient rate-limit/overload trips both at once. Any upstream hop
that can return transient 429/5xx needs a **time-spaced, bounded** retry for the
retriable bucket only (never timeouts, never 4xx), inside the wall-clock budget.
The client-side analog (`retryColdStart`, debugging skill §2.5) already existed;
this brings the server→Gemini hop to parity.

## See also

- `supabase/functions/_shared/gemini.ts` (`geminiChatWithTools`, `_callOnceWithTools`)
- `supabase/functions/_shared/tool-loop.ts` (`runToolLoop` catch → apology)
- `supabase/functions/ai-proxy/index.ts` (returns `tool_intents` even with the apology — the double-apply edge)
- `supabase/functions/_shared/gemini_backoff_retry_test.ts`
- Client-side analog: `retryColdStart` in `lib/core/services/supabase_service.dart`; debugging skill §2.5; related `7c4e1a` / `c01d57`.
- ADR-0012 (the derive-only AI-coach batch this surfaced in)
