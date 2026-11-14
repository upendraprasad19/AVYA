# Agent 5 Findings — Cluster 6 (AI architecture end-to-end)

**Date:** 2026-05-16

## Tool-routing matrix — 24 tools (NOT 20 as CLAUDE.md states)

Registry: `supabase/functions/_shared/tools/registry.ts:35-73` — 24 tools across Workout (8), Progress (5), Nutrition (5), Plan (5), Exercise (1).

Tier split per registry `tier` field: **11 FREE / 13 PRO** (CLAUDE.md §11 claims "6 FREE / 20 PRO" — wrong).

| # | Tool | Family | R/W | Tier | Dispatcher line | WriteService canonical? | Cloud target |
|---|---|---|---|---|---|---|---|
| 1 | swapExercise | workout | W | PRO | L113 | ✅ `WorkoutScheduleService.swapExerciseInDay` | scheduled_workouts |
| 2 | logSet | workout | W | FREE | L116 | ✅ `WorkoutWriteService.logExercise` | workout_log_exercises + _sets |
| 3 | markWorkoutComplete | workout | W | FREE | L119 | ✅ `WorkoutWriteService.markCompleted` | workout_logs + scheduled_workouts |
| 4 | shortenWorkout | workout | W | FREE | L122 | ✅ `WorkoutScheduleService.shortenDay` | scheduled_workouts |
| 5 | createCustomExercise | workout | W | FREE | L125 | ✅ `WorkoutRepository.createCustomExercise` | user_custom_exercises |
| 6 | modifyWorkoutForInjury | workout | W | PRO | L128 | ✅ `WorkoutScheduleService.swapExerciseInDay` ×N | scheduled_workouts |
| 7 | rescheduleWeek | workout | W | PRO | L131 | ✅ `WorkoutWriteService.upsertScheduled` | scheduled_workouts |
| 8 | generateHotelWorkout | workout | W | PRO | L134 | ✅ `WorkoutWriteService.upsertScheduled` | scheduled_workouts |
| 9 | getProgressSummary | progress | R | FREE | — | n/a | workout_log_exercises + scheduled_workouts + weight_logs + nutrition_logs |
| 10 | getExerciseHistory | progress | R | PRO | — | n/a | workout_log_exercises |
| 11 | **logPR** | progress | W | FREE | **L161** | ⚠️ **BYPASSES — uses `WorkoutRepository.logSetWithPrRescan`** | workout_log_exercises |
| 12 | getPromotionStatus | progress | R | FREE | — | n/a | user_profile + users + workout_logs + user_progress |
| 13 | getPRTimeline | progress | R | FREE | — | n/a | workout_log_exercises |
| 14 | logMealByText | nutrition | W | FREE | L152 | ✅ `NutritionWriteService.logMeal` | nutrition_logs + _items |
| 15 | adjustCaloricTarget | nutrition | W | PRO | L155 | ✅ `NutritionRepository.adjustDailyTarget` | (Hive-local) |
| 16 | suggestMeal | nutrition | R | PRO | — | n/a | food_database |
| 17 | prelog | nutrition | W | PRO | L158 | ✅ `NutritionWriteService.logMeal` ×N | nutrition_logs + _items |
| 18 | getNutritionHistory | nutrition | R | FREE | — | n/a | nutrition_logs + nutrition_log_items |
| 19 | regeneratePlanBlock | plan | W | PRO | L137 | ✅ `WorkoutWriteService.upsertScheduled` ×N | scheduled_workouts |
| 20 | pausePlan | plan | W | PRO | L140 | ✅ `WorkoutScheduleService.pauseRange` | scheduled_workouts |
| 21 | switchGoal | plan | W | PRO | L143 | ✅ `userBox['profile']` + `WorkoutWriteService.upsertScheduled` ×N | user_profile + scheduled_workouts |
| 22 | createCustomTemplate | plan | W | PRO | L146 | ✅ `WorkoutRepository.createTemplate` | workout_templates + template_exercises |
| 23 | scheduleTemplate | plan | W | PRO | L149 | ✅ `WorkoutScheduleService.assignTemplateToDate` ×N | scheduled_workouts |
| 24 | getFormCues | exercise | R | FREE | — | n/a | exercise_library |

**17/17 write tools dispatched. Zero shadow tables for READ tools.**

## Findings

### F6-1: Tool count drift in CLAUDE.md vs registry — DOCS_GAP
- CLAUDE.md §11 says 20 tools; registry has 24
- Tier split wrong: "6 FREE / 20 PRO" → actually "11 FREE / 13 PRO"
- Missing from docs: `getPromotionStatus`, `getPRTimeline`, `getNutritionHistory`, `getFormCues` (the entire `exercise` family)
- **Remediation:** Update CLAUDE.md §11 to 24 tools.

### F6-2: 🚨 CRITICAL — `logPR` tool bypasses WorkoutWriteService — CONFIRMED_BUG (8th drift)
- `tool_dispatcher.dart:349` routes `log_pr` to `WorkoutRepository.logSetWithPrRescan` (the legacy pre-WriteService writer).
- Sibling `log_set` at L312 correctly uses `WorkoutWriteService.logExercise`.
- `logSetWithPrRescan` was ONE OF THE 3 ROGUE `exlog_*` key formulas closed in APK Test #16.1 / Bug A (commit `a16c1a`). The AI-coach tool callsite at `workout_repository.dart:1133` was a rogue writer.
- After Test #16.1 fix, the rogue formula was routed through canonical `exlogKey`, but the calling pattern STILL bypasses `WorkoutWriteService` (no mutex, no telemetry, no batched cloud sync).
- **Severity:** medium-high. Silent risk of regression resurfacing rogue-key shapes if anyone modifies that method.
- **Remediation:** Route `logPR` tool through `WorkoutWriteService.logExercise` with `sets: [ExerciseSet(weightKg, reps, loggedAtMs: now)]`. PR rescan moves inside the WriteService.

### F6-3: `model_used='pending'` 8 stuck rows — CONFIRMED_BUG
- **Live SQL:** 8 rows with `ai_response IS NOT NULL` and `model_used='pending'` spanning 2026-05-11 → 2026-05-15.
- **Root cause — server side:** `ai-proxy/index.ts:307-336` success path uses fire-and-forget UPDATE (`.then((r) => {if(r.error) console.error})`). Any network blip between L256 INSERT and L319 UPDATE leaves placeholder stale.
- **Root cause — client side:** `sync_coach.dart:88-96` upserts `coach_<ms>` Hive entries with `model_used: entry['model_used'] ?? 'unknown'` — preserves `'pending'` if Hive entry wasn't updated post-success.
- **Remediation:** (1) `await` the UPDATE at L319; (2) update Hive entry's `model_used` + `tokens_used` on success in `ai_coach_provider.dart`; (3) one-shot SQL backfill: `UPDATE ai_coach_interactions SET model_used='unknown_legacy' WHERE model_used='pending' AND ai_response IS NOT NULL AND created_at < now() - interval '24 hours'`.

### F6-4: 🚨 Cross-channel duplicate pairs still accumulating — CONFIRMED_BUG (Test #16.1 incomplete)
- **Live SQL:** 8 cross-channel dupe pairs (same user + message within 60s, opposite channels) across 2026-05-11 → 2026-05-15.
- **Root cause:** Test #16.1 / Bug B's 60s dedup at `ai-proxy/index.ts:222-254` only catches intra-channel duplicates. The CLIENT'S `_syncCoachInteractions` orphan upsert at `sync_coach.dart:91` writes via a totally separate code path — server-side dedup can't see it.
- User flow: paste same meal text into AI coach chat (→ `coach_<ms>` Hive → orphan upsert) and AI Text tab (→ `food_text_analysis` placeholder) within 20s.
- **Remediation:** Either (A) in `sync_coach.dart`, before orphan upsert, SELECT for matching `channel='app'` row within last 5 minutes; skip if hit. Or (B) deprecate orphan path entirely — comment at L60-66 calls them "rare edge cases", but 8 in 5 days disproves that. Skip orphan upsert when entry has no real UUID `id`.

### F6-5: daily-snapshot cron health unverified — DEFERRED to Agent 7
- daily-snapshot Edge Function exists but cron execution status not visible from cluster 6 scope.

## Health checks (all PASS)

- **H-1 Context SoT:** `AiCoachRepository.buildAiContext()` (4 callsites) + `AiService._compactContext()` (6 callsites internal) are single-source. ✅
- **H-2 Semantic retrieval:** `match_memories(p_user_id uuid, p_query_embedding vector, p_match_count int=5, p_similarity_threshold double=0.65)` RPC present. 137 embeddings across 2 users (oldest 2026-05-03, newest 2026-05-15). ai-proxy invokes per chat turn. ✅
- **H-3 READ-tool SoT:** All 7 READ tools query canonical UI-written tables. Zero shadow paths. ✅
- **H-4 Rate limits:** `trg_food_text_rate_limit` trigger enabled. Vision 15/day cap enforced at `ai-proxy/index.ts:367-376` via IST-day SELECT. Message/snapshot/image size caps in place. ✅
- **H-5 Edge Function auth shape:** Spot-checked ai-proxy + ai-media-proxy + validate-promo + verify-payment. All manually validate JWT via `supabaseClient.auth.getUser(token)`, return `{error, request_id}` shape, log server-side. ✅
- **H-6 Dispatcher coverage:** 17/17 write tools dispatched. 1h TTL guard L89, Hive idempotency L99-107, concurrent-edit guards on 3 critical paths, 6-provider invalidation batch L1462-1492. ✅
- **H-7 GEMINI cost (14d):** Flash 66,773 tok + Flash-Lite 32,128 tok ≈ $0.0125. ~$0.03/user/month at current volume. Healthy. ✅

## Summary

- **4 confirmed bugs + 1 docs gap.**
- **Zero shadow tables.** AI architecture is structurally sound.
- **F6-2 is the highest-leverage finding** — 8th writer/reader drift instance. Confirms `feedback_writer_reader_field_drift_recurring.md` recurrence.
- **F6-3 + F6-4 both at `ai_coach_interactions`.** Same lesson as Test #16.1: dedup must consider all-pairs writer surfaces, not single-channel pairs.
