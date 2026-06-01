---
source: CLAUDE.md §11
migrated: 2026-05-18
status: scaffold
---

# AI Architecture — Reference

> Cross-cutting concern. Fetch via Read when AI-related work is in scope.
> Root CLAUDE.md contains pointers but not the full content.

Single provider: **Google Gemini** (via `GEMINI_API_KEY`). Cerebras + OpenRouter were retired on 2026-04-18 — one key to rotate, one billing line, one source of truth.

## Semantic retrieval (since ai-proxy v46, 2026-04-24) — Phase B live

Every chat turn now embeds the user's message via `getEmbedding(text, "RETRIEVAL_QUERY")` and queries `match_memories(user_id, embedding, match_count=5, threshold=0.65)` for the top-5 most semantically similar past memories (source types: `conversation`, `daily_summary`, `coaching_note`, `pattern_insight`). Results are injected into the system prompt as a "Relevant context from earlier conversations" block between the snapshot and coaching_notes sections. `formatRetrievalBlock` caps each line at 200 chars (5 lines ≈ 1 KB prompt growth).

**Helper:** `supabase/functions/_shared/memory_retrieval.ts` — `retrieveRelevantMemories(supabaseClient, userId, query, options?)`. Never throws; all failure modes return `{ memories: [], source: <code> }`. Options: `matchCount`, `threshold`, `embeddingTimeoutMs` (default 3000), `getEmbeddingFn` (test injection seam).

**Fallback behavior:** when retrieval returns 0 matches, fails embedding, hits the 3s timeout, or errors on the RPC, the prompt falls back to the existing full-dump `coaching_notes` path. Zero regression risk. `[ai-proxy] memory_retrieval fallback: source=...` warnings are logged on any non-retrieval / non-empty outcome.

**Gating:** all users (free + PRO). Per-turn cost ~$0.00001 via Gemini embedding API — PRO-gating added complexity without meaningful savings. Retrieval latency: ~150 ms p50, hard-bound at 3 s.

**Phase A (accumulation)** has been running since 2026-03-31 (migration `20260331000001_add_pgvector_memory.sql`): `ai-proxy/index.ts:635` + `rolling-context/index.ts:210` embed every chat turn + nightly summary into `memory_embeddings`. No Phase B backfill needed — older coaching_notes reach the coach via the recent-N fallback. Retrieval hit rates become meaningful only after users accumulate ~10+ conversations.

## Tool-calling (since ai-proxy v44, 2026-04-20) — 20 AI coach tools (derive-only surface)

`ai-proxy` chat channel uses Gemini function-calling via `_shared/tool-loop.ts` (multi-round, max 3 rounds, validation feedback to model). 20 typed tools across 5 families, defined in `_shared/tools/<family>/<tool>.ts` and registered in `_shared/tools/registry.ts`. Tier filtering: free users see 9 FREE tools, PRO sees all 20.

**Derive-only prune (2026-05-31, ADR-0012):** the surface dropped 24→20 by removing 4 tools that let the AI assert a *derived* value or future state — a progression-gaming / data-integrity hole. Removed: `logPR` (PR derives from `logSet` via `_rescanPrFor`/`loadAllExercisePRs`), `markWorkoutComplete` (completion now derives — a coach `logSet` on a scheduled day auto-calls `markCompleted` via the dispatcher's `_maybeCompleteScheduledDay`), `adjustCaloricTarget` (target stays derived from the plan), `prelog` (no pre-logging — users log raw input daily as they eat). Principle: **the user logs raw input; the app computes the rest.** (Pre-2026-05-16 audit, this doc claimed 20 tools / 6 FREE / 20 PRO — drift from registry growth across Tests #12–#16, since pruned back to 20 with a different composition. Verified live against `_shared/tools/registry.ts` + `test/contracts/derive_only_tool_surface_test.dart`.)

| Family | Tools |
|---|---|
| Workout (7) | `swapExercise`, `logSet`, `shortenWorkout`, `createCustomExercise`, `modifyWorkoutForInjury`, `rescheduleWeek`, `generateHotelWorkout` |
| Progress (4) | `getProgressSummary`, `getExerciseHistory`, `getPromotionStatus`, `getPRTimeline` |
| Nutrition (3) | `logMealByText`, `suggestMeal`, `getNutritionHistory` |
| Plan (5) | `regeneratePlanBlock`, `pausePlan`, `switchGoal`, `createCustomTemplate`, `scheduleTemplate` |
| Exercise (1) | `getFormCues` |

**Hive-first hybrid architecture:** READ tools (e.g. `getProgressSummary`, `getExerciseHistory`, `suggestMeal`) execute server-side and feed Gemini results in same turn. WRITE tools emit typed `ToolIntent` to client; client confirms via card/sheet, then writes Hive + fire-and-forget syncs (matching the existing CLAUDE.md §6 rule 1 mutation pattern).

3 confirmation classes: trivial (5s auto-confirm card), reviewable (explicit inline card), destructive (bottom-sheet with diff preview). Per-intent dispatch in `lib/features/ai_coach/services/tool_dispatcher.dart`. 1-hour intent TTL + concurrent-edit guards on every dispatch.

Telemetry: per-tool-call records written to `ai_coach_interactions.tool_calls` JSONB column (migration 029), surfaced via `coach_tool_invocations_v` view.

## Proactive triggers (8 of 8 brainstorm §5 triggers, since 2026-04-20)

All 8 cron-driven Edge Functions in prod. Each uses `_shared/proactive_dedup.ts` (`shouldSendProactive` + `markProactiveSent`) to prevent same-type push twice per IST day, writing `coach_memory.last_proactive_type` after successful send.

| # | Trigger | Edge Function | Cron (UTC → IST) | Tier |
|---|---|---|---|---|
| 1 | Morning Brief | `morning-alert` | (existing 2-stage) → 7am IST | both |
| 2 | Workout Window Closing | `workout-window-closing` | `30 15 * * *` → 21:00 IST | both |
| 3 | Protein Gap Alert | `protein-gap-alert` | `30 14 * * *` → 20:00 IST | PRO |
| 4 | Streak Protection | `streak-guardian` | (existing) → 20:00 IST | both |
| 5 | PR Detection | `pr-detection` | `*/15 * * * *` → near-real-time | both |
| 6 | Plateau Alert | `plateau-alert` | `30 13 * * *` → 19:00 IST | PRO |
| 7 | Weekly Recap | `weekly-recap-ready` | (existing) → Sunday | both |
| 8 | Re-engagement | `re-engagement` | `30 06 * * *` → 12:00 IST | both |

**Plateau-alert** + **re-engagement** read scores from `coach_memory.{plateau_risk_score, dropout_risk_score}` (computed nightly by `compute-coach-signals` → `compute_coach_signals_for_user(user_id)` RPC). Re-engagement has a fallback path that scans `workout_logs/nutrition_logs/weight_logs` directly for users without `coach_memory` rows yet.

Cron registrations live in `supabase/migrations/031_proactive_triggers_cron.sql`. Each uses `private.morning_alert_get_service_key()` for the Bearer token (consistent with `compute_coach_signals` cron pattern).

## Model matrix
| Edge Function | Model | Purpose |
|---|---|---|
| `ai-proxy` (chat + food text + prediction) | `gemini-2.5-flash` | Free + PRO coach, food text analysis, prediction card |
| `ai-proxy` (scan_meal, cart_auditor) | `gemini-2.5-flash-lite` | Vision: nutrition JSON from photos |
| `ai-media-proxy` | `gemini-2.5-flash-lite` | PRO photo-upload chat |
| `assess-body-composition` | `gemini-2.5-flash-lite` | Body-fat % from photo |
| `daily-snapshot` (coaching notes) | `gemini-2.5-flash` | Extract facts from daily conversations |
| `morning-alert` | `gemini-2.5-flash` | Personalised morning push |
| `rolling-context` | `gemini-2.5-flash` | Nightly conversation summary |
| `future-prediction` | `gemini-2.5-flash` | 90-day forecast card |
| `weekly-report` | `gemini-2.5-pro` | Deepest reasoning, PRO-only weekly |
| `_shared/embeddings.ts` | `gemini-embedding-001` | Memory retrieval vectors |

## Shared helper: `_shared/gemini.ts`
`geminiChat({model, systemPrompt, userPrompt, maxTokens, temperature, imageBase64, jsonMode, fallbackToLite})` is the ONE interface for all Gemini calls. Handles:
- Message translation from OpenAI-style `{system, user}` to Gemini's `{systemInstruction, contents}`.
- Vision input via `inline_data` parts.
- `responseMimeType: application/json` when `jsonMode=true`.
- **Built-in fallback:** on 5xx / 429 / empty content, automatically retries once on `gemini-2.5-flash-lite`. Pass `fallbackToLite: false` when primary is already Flash-Lite.

## Single AI coach endpoint — no client-side routing
```
Client (free + PRO) → ai-proxy (Gemini 2.5 Flash)
  JWT → auth.getUser(token)
  isPro = SELECT 1 FROM subscriptions WHERE user_id AND active AND end_date > now()
  If !isPro: enforce 30-day trial window + 15/day cap via ai_coach_interactions
  If  isPro: no cap, no trial
  ← Response + model_used + tokens_used
```
The old separate `ai-proxy-pro` function returns **410 Gone** for any orphan clients still calling it.

## Cost estimates (Gemini pricing at 2026-04-18)
| Scale | Cost/month (coach + vision + weekly Pro) |
|---|---|
| 50 beta users | ~$3 |
| 1,000 users | ~$70 |
| 10,000 users | ~$700 |

Input $0.075/M · output $0.30/M for Flash; $1.25/M · $10/M for Pro; Flash-Lite is the cheapest tier.

## Input Validation (all AI Edge Functions)
- **Message length:** Max 5,000 chars. Enforced server-side on `ai-proxy`, `ai-media-proxy`.
- **Snapshot size:** Max 10,000 chars (stringified JSON). Enforced on `ai-proxy`.
- **Image size:** Max 5MB. Enforced on `ai-media-proxy` via content-length + arrayBuffer check.
- **SSRF protection:** `ai-media-proxy` only fetches from `${SUPABASE_URL}/storage/v1/object/` prefix. All other URLs rejected.

## Client-Side Context Compaction (`AiService._compactContext`)
- **Target:** <9,500 bytes (buffer under 10KB server limit for JSON overhead).
- **Trim order** (least load-bearing first): `step_history_7d` → `weight_trend` → `nutrition_trend` → `exercise_history` → `personal_records` → `coach_notices` → truncate `coaching_notes` (1,500 char cap) → drop `fitness_summary`.
- Applied on EVERY AI call (`chat`, `chatWithMedia`, `predict`, direct-HTTP fallbacks). Without this, historical queries that trigger `enrichContextForQuery` get rejected with a 400 from the server.

## Client-Side Error Extraction (`AiService._extractError`)
- Parses `{"error": "..."}` out of non-200 responses on all AI Edge Functions.
- Replaces generic "status X" with actionable messages at the provider level (`ai_coach_provider.dart`):
  - `Message too long` → "Your message is too long (max 5000 chars). Please shorten it and try again."
  - `Snapshot too large` → "Your coaching context is unusually large. Please try a shorter question."
  - `Image too large` → "That photo is too large (max 5 MB)."
  - `Only Supabase Storage URLs are allowed` → "Upload failed — please try picking the photo again."
  - `502`/`503`/`504` → "The AI model is temporarily unavailable. Please try again in a minute."
- **Never use "restart the app" copy.** It doesn't fix any of these root causes.

## Edge Function Auth
- `ai-proxy`: `verify_jwt: false` (Supabase gateway bug). Manual JWT validation via `auth.getUser()` + server-side `isPro` check for unlimited tier.
- `ai-media-proxy`: `verify_jwt: true` + manual JWT + PRO subscription check.
- `validate-promo`: `verify_jwt: true` + manual JWT validation (prevents unauthenticated promo enumeration).
- `future-prediction`: `verify_jwt: true` + manual JWT validation.

## Vision Features (ai-proxy — Gemini 2.5 Flash Lite)
- `food_text_analysis`: Text → nutrition JSON. **Rate limited: 50/day free, 200/day PRO** (server-side abuse cap; client has no hard limit — server is source of truth). Counted via `ai_coach_interactions` rows with `channel='food_text_analysis'`.
- `scan_meal`: Photo → nutrition JSON. Client: 3 free / 10 PRO per day. Server: 15/day abuse cap.
- `cart_auditor`: Grocery screenshot → health audit JSON (items, health_score, suggestions). Client: 1 free / 10 PRO per day. Server: 15/day abuse cap.
- Server-side rate limit: scan_meal + cart_auditor combined counted via `ai_coach_interactions` rows with `channel IN ('scan_meal', 'cart_auditor')`. Client-side limits handle exact free/PRO tiers.

## Edge Function Error Sanitization (ALL functions)
- **Never leak raw exceptions, stack traces, or database error strings to the client.** Every Edge Function catch block follows this shape:
  ```ts
  } catch (err) {
    const requestId = crypto.randomUUID().split("-")[0];
    console.error(`[function-name] request_id=${requestId}`, err);
    return new Response(
      JSON.stringify({ error: "Internal server error", request_id: requestId }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
  ```
- Short request IDs (8 hex chars) are logged server-side AND returned to the client so support can grep logs for the exact failure. The client sees a generic message; the logs retain full detail.
- **Validation errors** (400 responses like "Message too long", "Image too large", "PRO subscription required") ARE safe to return verbatim — they're user-actionable and don't leak internals.
- Applies to all 18 live Edge Functions: `ai-proxy`, `ai-media-proxy`, `razorpay-webhook`, `verify-payment`, `verify-subscription`, `validate-promo`, `assess-body-composition`, `beat-my-coach`, `daily-snapshot`, `expiry-reminder`, `future-prediction`, `morning-alert`, `redeem-referral`, `rolling-context`, `streak-guardian`, `weekly-recalc`, `weekly-recap-ready`, `weekly-report`. (`ai-proxy-pro` is a 410-Gone stub — retired 2026-04-18 — excluded.)

## Server-Side Workout Analytics
- `weekly-recalc`: Reads exercise-level data from `workout_log_exercises` (NOT `workout_logs`). Derives date from `completed_at`. Groups exercises by `exercise_id` (= exercise_name) for weight progression tracking. `total_workouts_done` counts distinct dates, not exercise rows.
- `weekly-report`: Two-query approach — exercise data from `workout_log_exercises`, workout metadata (duration, RPE) from `workout_logs`. `sets_completed` reads actual `set_number` from per-exercise summary (not hardcoded 1). RPE guarded against zero-denominator (returns "N/A" when no RPE data).

## Exercise Log Cloud Contract (workout_log_exercises)
Each row is a **per-exercise summary** (NOT per-set), matching the Hive exlog_* shape:
- `exercise_id` = exercise_name (stable identity for cross-week grouping)
- `workout_log_id` = deterministic ID from date (groups all exercises in same workout)
- `set_number` = total completed sets for this exercise (NOT "which set number")
- `reps` = cumulative reps across all sets
- `weight_kg` = best (max) weight across sets
- RPE: NOT stored per exercise. Workout-level RPE column exists in `workout_logs` but is currently never written by the Flutter app (no UI for it).

## coaching_notes
- Batch extraction daily (11PM IST with snapshot)
- Process that day's conversations → extract facts → append to Hive
- NOT per-message extraction (too expensive)

## Context Injection
- System prompt receives `user_daily_snapshot` JSON (~300 tokens)
- Contains: profile (incl. city), this week's workouts, today's nutrition (incl. urine status), weight, streak, PRs, detected experience, coaching_notes
- One Hive read. Complete context. Zero additional queries.
