# Gemini 3.x probe — summary (v2 run, 2026-10-01 11:29 UTC)

Source: `gemini_probe.mjs` v2 run by the founder on the NEW key (paid-tier project, D1). Redacted summary: no key, synthetic prompts only (the 4 quality prompts are synthetic, not user data). Manual used = the real `captain_manual.ts` (20,565 chars incl. one added line). Node v24.20.0.
Companion run: `gemini_probe3.mjs` (v3, 2026-10-01 11:46 UTC) results are in the v3 section below.

## Binding facts (each is one or more real calls; HTTP status shown)

| # | Question | Result |
|---|---|---|
| 1 | Do the chosen models exist and answer on this key? | `gemini-3.1-flash-lite`, `gemini-3.5-flash-lite`, `gemini-3.8-flash`: 200. `gemini-embedding-001` (768d): 200, `vector_len=768`. |
| 2 | **`thinkingBudget:0` per model** | 3.1-flash-lite: **accepted** (200; plain, JSON, vision, tool round-trip; thoughts 0). **3.5-flash-lite: REJECTED, HTTP 400 "Request contains an invalid argument"** (plain, JSON t0.7/t0.2, vision, tool call, cache prompt — every shape that sent it). 3.8-flash: accepted but it still thinks (354 thought tokens on the plain call). |
| 3 | `thinkingLevel` per model | 3.1-flash-lite: `minimal` 200 (0 thoughts), `low` 200 (170 thoughts), `high` 200 (374). 3.5-flash-lite: `minimal` 200 (0), `low` 200 (238), `high` 200 (453). 3.8-flash: `minimal` **400 "Thinking level MINIMAL is not supported for this model"**, `low` 200, `high` 200. |
| 4 | Default (no thinkingConfig) | Both Lite models: 0 thought tokens (plain call and tool calls). 3.8-flash: 412 thought tokens (thinks by default). |
| 5 | **Thought signatures** | Every model returns a `thoughtSignature` on a `functionCall` part. **Replaying the model turn WITH its raw parts: 200 on all three. Replaying it STRIPPED to `{functionCall:{name,args}}` (what `tool-loop.ts:360` stores today): HTTP 400 on all three — "Function call is missing a thought_signature in functionCall parts."** A documented dummy value (`skip_thought_signature_validator`) is accepted (200) on all three. Cross-model (signature minted by 3.1-lite replayed to 3.5-lite, default thinking config): raw echo 200; stripped 400. (Cross-model with `thinkingBudget:0` returned 400 only because 3.5 rejects that config — not the signature.) |
| 6 | JSON mode on 3.1-flash-lite with budget0, t0.7 and t0.2 | 200, valid JSON both. 3.8-flash 200 valid. (3.5-flash-lite JSON untested with an accepted config — covered by v3.) |
| 7 | Vision (inline PNG) on 3.1-flash-lite | 200, "says red" = true, ~1,101 prompt tokens for a 64x64 PNG. (3.5-flash-lite vision untested with an accepted config — v3.) |
| 8 | **Caching (v2 observation; see the v3 CORRECTION below)** | `cachedContentTokenCount` = 0 in EVERY v2 call on 3.1-flash-lite at our prompt size (5.8K tokens): cross-request +2 s/+30 s/+120 s, ~1.5K/~3K prefixes, and the within-request tool round. **v2's inference "implicit caching is not available on 3.1-flash-lite" was WRONG** — v3 shows it works above a minimum prompt size; our prompt is below it. |
| 9 | Prompt size | Chat prompt = **5,837–5,851 tokens per request** (manual + tools + dynamic block). Average logged `tokens_used` 13,610 ⇒ ≈ 2.3 model calls per chat message, each resending ~5.9K static tokens. |
| 10 | Retired-model 404 shapes (fixtures) | (a) `gemini-2.5-flash-lite`: HTTP 404, `status:"NOT_FOUND"`, message "This model models/gemini-2.5-flash-lite is no longer available to new users. Please update your code to use models/gemini-3.5-flash-lite for the latest features and improvements. We recommend you to use the Interactions API …". (b) unknown name: HTTP 404, `status:"NOT_FOUND"`, "models/gemini-9-does-not-exist is not found for API version v1beta, or is not supported for generateContent …". ⇒ classify on HTTP 404 / `status == NOT_FOUND`, NOT on message wording. |
| 11 | Quality replays (3.1-flash-lite, production config budget0, real manual) | 4/4 answered in persona ("Stand to", "Chalo", "Carry on"); chest-pain prompt correctly refused to "push through" and sent the user to a doctor; Hinglish answer fluent (but it narrated "get_meals_today tool use kar raha hoon" in user-facing text — a prompt-polish note, not a failure); 3-day split complete. 3.8-flash comparable, slightly longer. 3.5-flash-lite: no replays (all 400 because of the budget0 config) — v3. |
| 12 | Latency/cost signals | ~6K prompt tokens per round; replay `out` 118–402 tokens. Consistent with the ₹0.32/message estimate. |

## Consequences for the plan
1. **A2 (signature pass-through) is MANDATORY**, not conditional: today's loop 400s on every tool-using chat turn on any Gemini 3.x model.
2. **A1 capability table is mandatory and non-trivial:** the fallback model 400s on the current `thinkingBudget:0`, so with today's code every fallback attempt would fail too.
3. **Caching: see the v3 section below** (v2's "not available" inference was corrected there).

---
# Probe v3 (2026-10-01 11:46 UTC) — targeted follow-up

| # | Question | Result |
|---|---|---|
| 1 | **Fallback model + minimal thinking, every production request shape** | `gemini-3.5-flash-lite` with `thinkingLevel:"minimal"` AND with no thinkingConfig: 200 for plain, JSON (t0.7 and t0.2, valid JSON), vision (says red), tool round-trip with raw-echo, both short and FULL (5.8K) prompt; 0 thought tokens. `gemini-3.1-flash-lite` with `thinkingLevel:"minimal"` and with no config: identical, all 200. ⇒ **a single uniform "off" = `{thinkingLevel:"minimal"}` is proven on BOTH lite models in every shape; `thinkingBudget:0` is proven only on 3.1 and is REJECTED by 3.5.** |
| 2 | **Weekly report on 3.1-flash-lite (1,000-token synthetic prompt)** | omit: 0 thoughts, 245 out, 2.3 s. `low` cap 1500: 134 thoughts, 277 out, 2.9 s, STOP. `low` cap 4096: 135 thoughts, 3.1 s. `high` cap 4096: 847 thoughts, 250 out, 5.9 s. No truncation at 1,500 on this small prompt (the real prompt is larger, so headroom is still required). `high` = 6x thought tokens and 2x latency for a similar-length answer. |
| 3 | **Implicit caching (3.1-flash-lite), bigger prompts** | ~12K-token prompt: 11,311 prompt tokens, **4,079 cached on call 1**, **8,158 cached on a repeat 2 s later**. ~24K-token prompt: 22,417 prompt, 8,174 cached, then **16,349 cached** on the repeat. ⇒ implicit caching WORKS on 3.1-flash-lite, in ~4K-token blocks, but only above a minimum prompt size (between 5.9K — v2: 0 cached — and 11.3K tokens). **Our chat prompt (5.77–5.85K) is below it.** |
| 4 | Implicit caching on gemini-3.8-flash | 0 cached at 5.7K and 11.3K tokens, but those calls ended `MAX_TOKENS` with ~93 thought tokens (cap 100) — inconclusive; 3.8 is not a planned model. |
| 5 | **Explicit caching (3.1-flash-lite)** | `cachedContents` create (static `systemInstruction` + tools, ttl 300 s): 200, **5,709 tokens**. Three generateContent calls using `cachedContent`: **cached 5,709 of 5,766–5,811 prompt tokens (~99%)**, including the tool-round second call; latency unchanged (~1.6–2.0 s). DELETE: 200. |
| 6 | usageMetadata fields | `promptTokenCount, candidatesTokenCount, totalTokenCount, promptTokensDetails, serviceTier`; plus `cachedContentTokenCount` and `cacheTokensDetails` only when tokens were cached; `thoughtsTokenCount` only when thinking tokens > 0. ⇒ C1 logging must default absent fields to 0. |
| 7 | 3.5-flash-lite quality replays (level:minimal) | 4/4 acceptable: persona kept, chest-pain answer correct (stop, see a physician), Hinglish fine. Minor: on the split prompt it asserted "your current plan is already built into the system" (unsupported claim — a manual line about not asserting plan contents). |
| 8 | Latency | 1.2–1.7 s per Lite call; weekly report 2.3–3.1 s (5.9 s at `high`). |

## Cost model with these measurements (INR 86/USD; Google's pricing page via a summarizing fetch — re-verify)
- Static prefix = 5,709 tokens. Always-on explicit cache: storage $1.00 per 1M tokens per hour ⇒ $0.0057/h ≈ ₹0.49/h ≈ **₹11.8/day**; saving ≈ 2.3 rounds × 5.7K cached tokens × ($0.25 − $0.025)/M ≈ **₹0.25 per message** ⇒ break-even ≈ **46 messages/day**.
- **On-demand cache with a short TTL (e.g. 15 min):** creation ≈ ₹0.12 + storage ≈ ₹0.12 ≈ ₹0.24 per cache, saving ≈ ₹0.25 per message inside the window ⇒ neutral for an isolated message, ≈ 60% cheaper over a 4-message session. Needs a cache-registry table, per-(model, tier/routing/tool-set) caches, and moving the dynamic prompt blocks (date, coach memory, snapshot, retrieval) out of `systemInstruction` into the user turn (a trust-position change for untrusted data).
- Real volume (usage_counters `chat_app`, IST days 2026-09-25..10-01): 1 free user, ≤ 10 messages/day; PRO not yet recorded.
