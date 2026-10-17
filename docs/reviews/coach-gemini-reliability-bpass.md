---
staged_against: ff82b5c
verdict: accepted
---

# B-pass code review — coach-gemini-reliability (HEAD `ff82b5c`)

- **Reviewer role:** fresh, context-blind adversarial B-pass (find bugs, not validate).
- **Scope:** the six source files + two Deno tests + one Dart test in commit `ff82b5c`
  ("fix(coach): revive Flash coach (thinkingBudget:0) + error-surface, food-retry, prompt-safety, calorie clamp").
- **Method:** read every changed file in full against its callers/readers; traced the two
  Gemini attempt loops and the tool-loop exit/catch paths by hand; ran the FC6 Dart test
  (green); confirmed reader type-coercion for the clamp; confirmed the retries/thinking/maxTokens
  wiring is scoped as claimed. Deno not installed locally (the two `.ts` tests are CI-only, as
  their headers state) — I verified them by reading, not executing.

## Verdict: **SHIP** (with one P2 worth a follow-up decision)

No P0 or P1 found. The six fixes are correctly wired, type-safe, and scoped. One P2
latency regression on the coach meal-log path under a genuine Gemini outage, plus two nits.

---

## Findings

### P2-1 — `parseFoodText` retries can add up to ~76 s of unbounded latency inside an untimed write-tool path
- **File:** `supabase/functions/_shared/food_parser.ts:87-93` (`timeoutMs:15_000`, `retries:2`)
  consumed via `supabase/functions/_shared/tools/nutrition/logMealByText.ts:32` →
  `supabase/functions/_shared/tool-loop.ts:316`.
- **Scenario:** `logMealByText` is a **write** tool (`kind:"write"`). Its `intentBuilder`
  runs at tool-loop.ts:316, which — unlike the **read** path at tool-loop.ts:245 — is NOT
  wrapped in the `Promise.race`/`maxLatencyMs` timeout. So `parseFoodText`'s own budget is the
  only bound. With `retries:2` and `timeoutMs:15_000`, the worst case is
  `3 passes × (Flash 15 s + Flash-Lite 15 s) + 2 × 700 ms ≈ 91.4 s` for a single meal-log intent
  build. There is no wall-clock deadline / `AbortController` around `runToolLoop` in
  `ai-proxy/index.ts:788`, and the client Dio instance is a bare `Dio()` with no `receiveTimeout`
  (`ai_service.dart:94`), so nothing trims this earlier. It only fires during an actual
  Gemini degradation (the exact case FC3 targets) — no data loss, no crash — but a "trivial"
  5-second auto-confirm meal log can hang up to ~1.5 min, and if the outage persists the loop
  then feeds `intent_build_failed` back and burns further rounds. Under the Flash-only common
  case (FC1 fixed the empty-candidate cause) this rarely triggers, which is why it's P2 not P1.
- **Suggested fix:** either (a) drop `parseFoodText` to `retries:1` (worst case ~46 s), or
  (b) give the write-tool `intentBuilder` the same `maxLatencyMs` race guard the read path has
  (e.g. a 20-30 s ceiling on the builder), or (c) pass an overall wall-clock deadline into
  `geminiChat`'s retry loop so the extra passes are skipped once the request budget is spent
  (mirrors the `TOOLS_RETRY_DEADLINE_MS` guard already present in `geminiChatWithTools`).

### Nit-1 — stale line reference in the FC7 size-budget comment
- **File:** `supabase/functions/ai-proxy/index.ts:711` — comment says
  "snapshot_json ≤ 10 KB (input check at line 412)"; the actual 10 KB guard is at line 547
  (`if (snapshot_json && JSON.stringify(snapshot_json).length > 10000)`). Cosmetic; update the
  line number. (The guard itself is correct and runs before the wrap.)

### Nit-2 — clamp can leave `total_calories != sum(items)` for garbage payloads
- **File:** `lib/core/services/nutrition_write_service.dart:203-217`. The meal total is clamped
  at 15000 while each item is clamped at 10000. A 2-item garbage payload lands as total=15000 but
  items summing to 20000; on the next append/edit the totals are recomputed from items and
  re-clamped back to 15000. Both numbers are in absurd-value territory (this only happens to a
  payload that tripped the ceiling), so it's cosmetic, not a data bug. Acceptable as-is for an
  injection/garbage defense; noted only for completeness.

---

## What I verified clean (per the hunt list)

**FC1 (thinkingBudget:0)** — correct.
- Request body shape is `generationConfig.thinkingConfig.thinkingBudget = 0`
  (`gemini.ts:226-230` in `_callOnce`, `gemini.ts:548-552` in `_callOnceWithTools`), keyed on
  `opts.model !== MODEL_PRO`.
- `opts.model` is genuinely the **attempt** model at both sites: `geminiChat`'s attempt loop
  passes `attemptModel` (`gemini.ts:126-137`) and `geminiChatWithTools`' attempt loop passes
  `attemptModel` (`gemini.ts:453-463`). So a Pro budget can never reach the Flash-Lite fallback —
  each attempt is keyed independently.
- `MODEL_PRO` gets NO `thinkingConfig` (verified: `weekly-report/index.ts:471` is the ONLY
  `MODEL_PRO` caller; all other callers use `MODEL_FLASH`/`MODEL_FLASH_LITE`). The behavioral
  test `gemini_thinking_config_test.ts` asserts Flash→budget 0 and Pro→undefined.
- Coexists with jsonMode: `responseMimeType` (line 213) and `thinkingConfig` (line 227) are two
  independent keys on the same `generationConfig` object — no clobber.
- The 13 Flash / Flash-Lite callers (daily-snapshot, morning-alert, rolling-context,
  future-prediction, alerts, assess-body-composition, food_parser, etc.) are all short
  structured-output/alert generators — none needs Gemini's chain-of-thought. Only weekly-report
  (Pro) does, and it's excluded. No caller legitimately loses required thinking.

**FC1 maxTokens 1024→2048** — `tool-loop.ts:128` passes `maxTokens:2048` at the single
`geminiChatWithTools` call site; the coach is the only caller, so no other path is affected.

**FC3 (retries pass-loop)** — correct.
- `retries` defaults to 0 (`gemini.ts:108`), so `for (let pass = 0; pass <= retries; pass++)`
  runs exactly once → identical single-pass behavior for the other 17 callers. Grep confirms
  `retries:` is passed ONLY by `food_parser.ts:93`.
- No off-by-one / infinite loop: `pass <= retries` with `retries:2` = 3 passes; the 700 ms sleep
  is guarded by `if (pass < retries)` so it runs only *between* passes, never after the last
  (`gemini.ts:153-156`). `retries` is not forwarded into `_callOnce` (correct — it's a
  geminiChat-level loop). No double-count of the fallback.

**FC2 (apology vs positive confirmation)** — airtight across all exit paths.
- Throw/catch path (`tool-loop.ts:143`): apology only when `!finalText && intents.length===0`.
  With an intent queued, `finalText` stays "" and the loop-exit block sets the positive message.
- Loop-exhaust path (`tool-loop.ts:373-385`): `intents.length>0` → positive "tap APPLY"; else
  the exhaustion message.
- The empty-terminal-text edge (`functionCalls.length===0 && resp.text===""` → `finalText=""` at
  line 154) is impossible to reach: `_callOnceWithTools` returns `ok:false` (→ throw) when
  `textBuffer.length===0 && functionCalls.length===0` (`gemini.ts:648-654`), so a terminal round
  always has non-empty text. Even if it somehow did, `if (!finalText)` at line 373 re-routes to
  the positive branch. No path leaks the apology/exhaustion message over a queued intent.
- The behavioral test `tool-loop_intent_apology_test.ts` drives the real path (round 0 queues
  `logSet`, round 1 persistent 503 → throw → catch) and asserts no apology + "APPLY" present.

**FC6 (calorie clamp)** — correct and type-safe.
- Clamped item keys (`calories/protein/carbs/fat/fiber`) exactly match `FoodItem.toMap()` /
  `FoodItem.fromMap()` keys (`nutrition_write_source.dart:62-80`).
- Clamping the payload map in place BEFORE `box.put` does bound what is read back: append/editLog
  reconstruct via `FoodItem.fromMap` from the stored (clamped) item maps, then recompute + the
  clamp re-runs on the recomputed totals.
- No type break: totals written as `int` via `.round()` (matches pre-FC6, which already
  `.round()`d totals to int); items written as `double` via `.toDouble()` (matches
  `FoodItem.fromMap`'s `(m['x'] as num).toDouble()`). Every reader coerces via
  `(log['total_calories'] as num?)` — int/double is a non-issue.
- `clampNum` cannot crash on a negative or non-num value: non-num → treated as 0
  (`v is num ? v : 0`), negative → clamped to 0. `@visibleForTesting static` split is clean; the
  telemetry side-effect lives only in the wrapper. FC6 regression test **run locally — 2/2 green.**
- `ErrorTelemetry.recordNonFatal(Object, StackTrace?, {required String reason})` signature matches
  the FC6 call; `unawaited` + `@visibleForTesting` imports present.

**FC7 (snapshot delimiter)** — safe.
- `snapshot_json` is never re-parsed OUT of the assembled prompt anywhere (grep of ai-proxy):
  only `JSON.stringify(snapshot_json)` is embedded, and the 10 KB validation (line 547) runs
  against the original object, not the prompt string. The +~250 chars of delimiter/guard text is
  negligible against the ~19.5 KB documented prompt ceiling and the Flash context window. No
  message-array/role change.

**FC5 (non-disclosure refusal)** — correctly placed.
- The clause sits at `captain_manual.ts:264`, inside the `HARD-LINE REFUSALS` block within the
  exported `CAPTAIN_MANUAL` template literal (opens line 7, continues well past 264). `ai-proxy`
  imports `CAPTAIN_MANUAL` (line 48) and pushes it as `promptParts[0]` (line 714), so it is in
  every assembled chat system prompt.

**Cross-cutting** — no TS/Dart type errors spotted; `retries`/`thinkingConfig`/`maxTokens`
wiring is scoped exactly as the commit message claims; diagnose docs 7fbe21 / 9c2d4a / 4e8f1b
exist; SoT registry line-range shift for `nutrition_write_service deleteLog` updated in the same
commit. No unintended behavior change to any of the other geminiChat callers.
