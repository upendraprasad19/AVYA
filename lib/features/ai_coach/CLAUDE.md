---
scope: ai_coach
parent: ../../../CLAUDE.md
created: 2026-05-18
updated: 2026-05-21
status: active
---

# AI Coach — Local Rules

> This file is auto-loaded by Claude Code when working under `lib/features/ai_coach/`.
> Root CLAUDE.md (../../../CLAUDE.md) contains process invariants and a pointer index.

## What lives here

`lib/features/ai_coach/` owns the AI Coach tab: a single server-side agent (`ai-proxy` → Gemini 3.1 Flash Lite) with **tool access** to log raw workouts / meals, do confirmed plan edits, swap exercises, and read the user's activity snapshot. The surface is **derive-only** (ADR-0012): the AI logs raw input only — PRs, completion and calorie targets are *computed* by the app. **21 tools (FREE 9 / PRO 12)**; a client that omits `client_capabilities` sees exactly the 20 legacy tools (`allTools` requires the capability string to be present, not merely PRO). See `coach_swap_workout_days` below.

Pieces:

- `screens/ai_coach_screen.dart` — chat UI + reasoning tab (PRO) + photo upload (5 free lifetime reads, then PRO; PRO capped 10/IST-day, OI-153; was 50 until Part B) + suggested-actions sidebar + Telegram toggle. There is NO video uploader (`media_picker.dart` is the only `sendWithMedia` call site and always sends `mediaType: 'image'`); the server's PRO video cap (5/IST-day; was 10 until Part B, 2026-10-01; server-side duration validation is OI-276) protects the API surface, not a UI path.
- `widgets/` — chat bubble, ai breakdown card (logs meals from text/photo via tool call), the photo uploader, quick-prompt chips, voice button (`SpeechListenOptions`).
- `copy/coach_replies.dart` — the CLIENT MIRROR of `supabase/functions/_shared/coach_replies.ts`. Every server key must have a byte-identical Dart twin and neither file may say "unlimited" (`test/contracts/coach_replies_test.dart` derives the key set from the `.ts` object — a drifted, missing or unmirrored key fails). Nothing on the client reads the new OI-153 keys today; the refusal reaches the user as the server's 200 `reply`, which `sendWithMedia` already renders as a coach bubble.
- **Chat daily limit (Part B, migration 153, 2026-10-01):** free 7/day, PRO 20/day, both server-enforced by `trg_chat_app_rate_limit` on the `model_used='pending'` reservation row only. Numbers: `AppConstants.freeAiMessagesPerDay` / `proAiMessagesPerDay` (parity-pinned to `_shared/ai_limits.ts` and the trigger literals by `test/contracts/ai_message_limit_parity_test.dart`). The 429 body carries `tier` + `limit`; `CoachReplies.chatRateLimitedFromError` words it (free: cap + 'PRO adds dedicated coaching and higher limits'; PRO: no upsell, resets midnight IST, never 'unlimited'). A transport-failed turn is refunded server-side (`refund_quota`, 3/IST day) and the 200 body says `refunded: true` (`AiChatResponse.refunded`, stored on the coachBox row): the send + retry paths tick the local tally UNLESS `refunded`, `sendWithMedia` never ticks it (media goes through ai-media-proxy, no chat unit), and `getTodayUserMessageCount` skips `failed` rows, `mode: media` rows and hard-failure rows the server refunded; a content-blocked apology (not refunded) still counts. There is NO PRO message counter in the UI. **Paywall label:** the coach-limit paywall's `feature` label is `Higher daily AI coach limit` (was `Unlimited AI Coach`; the analytics series split once at that build, see d7a1f5). **Funnel label:** PRO media rows keep `ai_coach_interactions.channel='app'` with a real model label, so a dashboard counting `channel='app'` rows over-counts PRO chat; the `usage_counters` `chat_app` key is the chat truth. Pin: `test/contracts/chat_limit_part_b_client_test.dart`.
- `services/tool_dispatcher.dart` — receives the agent's `tool_call` and routes to the canonical WriteService (NEVER calls Hive directly — `coach_derived_completion` SoT). After a coach `logSet` on a scheduled day `_maybeCompleteScheduledDay` derives completion: auto-`markCompleted` ONLY when EVERY planned exercise is now logged (the all-logged backstop, Unit 1 / 280c4d), else it writes a `completion_prompt_<date>` tap-card row — one coach `logSet` no longer completes the whole day.
- `services/ai_snapshot_builder.dart` — builds the snapshot payload (recent logs + today's targets + plan day + coach memory excerpt). Read-only.
- `repositories/ai_coach_repository.dart` — Hive read for chat history + snapshot inputs; cloud upward sync for `coach_interactions` + `coach_memory.coach_notes`.
- `providers/ai_coach_provider.dart` — chat state, error mapping, dedup ring buffer.

## Single-source-of-truth contracts

| Concept | Writer | Reader |
|---|---|---|
| `coach_interactions` | `ai_coach_repository.dart` `appendInteraction` → Hive + sync | chat thread renderer in `ai_coach_screen.dart`. **Dedup guards:** 60s client-side dedup + `ai-proxy` placeholder dedup + 3-strike circuit breaker (APK Test #16.1 / Theme B). |
| `ai_snapshot_building` | `ai_snapshot_builder.dart` `buildAiContext` (extracted from `ai_coach_repository` per audit 2026-05-20 / A10) | `ai-proxy` Edge Function request body. Includes `personal_records` + `today_workout` + `recent_logs` from `exlog_*` Hive rows. |
| `coach_derived_completion` | `tool_dispatcher.dart` `_maybeCompleteScheduledDay` → `WorkoutWriteService.markCompleted`. Completion = **all-logged AUTO** (`completedVia:'auto'` ONLY when `plannedCount > 0` AND every planned `exercises[]` entry has a log today; swap-tolerant via `swapped_from`; empty-`exercises[]` day never auto-completes) **OR** a user tap on the LOCAL-ONLY `completion_prompt_<date>` coachBox row (`completedVia:'tap'`). A partial STAYS `planned`. The model NEVER asserts completion (ADR-0012). The per-date lock is inside `markCompleted`; the dispatcher's status re-check runs outside it (benign race). | `train_screen` + home Today's Workout card; cloud `scheduled_workouts.status`; `ChatHistoryNotifier.build` (prompt tile) + `ai_snapshot_builder` `today_workout_completion`. History: `docs/architecture/ai-coach-detail.md`. |
| `coach_memory_coach_notes_upward_sync` | `ai_coach_repository.dart` → cloud `coach_memory.coach_notes` (renamed from `coaching_notes`; Hive key preserved) | `ai_snapshot_builder.dart`. APK Test #16.2 / 9th writer/reader drift. |
| `coach_extraction_locked_fields` | `lock_coach_extraction_fields` RPC (migration 148, additive-only) ← `UserRepository.lockCoachExtractionFields` (Edit Profile `_save` changed fields; onboarding real injuries selection). `daily-snapshot` `mergeCoachingNotes` reads the lock list before writing `diet_preference`/`lifestyle_activity`/`injuries` and writes conflicts to `coach_memory.locked_field_conflicts` (merged, not replaced). NOT `user_preferences.coaching_notes` (zero readers). | `mergeCoachingNotes`; the marker reaches the AI via `_getCoachMemoryForContext()`'s `mem.toJson()`. |
| `ai_proxy_placeholder_resolution` | `ai-proxy` Edge Function v66 inserts placeholder row BEFORE Gemini call (rate-limit trigger SoT) | dedup logic checks placeholder before issuing a new request. |
| `chat_media_signed_url` | `ai-media-proxy` Edge Function (PRO only) — SSRF-allowlisted to `chat-media`, `coach-media`, `progress-photos` Storage buckets only (corrected 2026-07-30, Unit 8 — this row previously named a bucket, `chat-attachments`, that never existed in the codebase) | `WardroomChatBubble` photo renderer. |
| `coach_media_consent` (Unit 8, OI-25) | `CoachInteractionRepository.recordMediaSaveDecision` writes `media_save_state` (`null`\|`'saved'`\|`'declined'`) on the `coach_<ms>` row; `CoachMediaRepository.saveForLater` copies `chat-media` → `coach-media`. | `ChatBubble` save chip (`mediaAnalysisComplete && mediaSaveState == null`); `SavedCoachPhotosScreen` via `CoachMediaRepository.list()`. |
| `bodyweight_trend_nudge` (W2.6) | `PatternDetector._bodyweightTrendNudge` (LOW severity), deduped ON THE OUTCOME of `_weightTrendAlert`; kill-switch `configBox['disable_bodyweight_trend_nudge']`. | home `insight_card.dart`. **`severity: low` is LOAD-BEARING** — `_getCoachNotices` drops `low` before the AI prompt; `medium` would start feeding it in. |
| `coach_swap_workout_days` | Tool `swapWorkoutDaysTool` (`_shared/tools/workout/swapWorkoutDays.ts`) — PRO, `confirmationClass: reviewable`, `requiresCapability: 'swap_workout_days'`. `_executeSwapWorkoutDays` routes to `SwapService.swapDays` (never a bespoke Hive write). Client declares `kCoachClientCapabilities` → `client_capabilities` (≤32 entries, `^[a-z_]{1,48}$`, dropped not 400'd). Server picks a routing block via `daySwapRoutingCase(isPro, capabilities)`. **Two gates:** offer-time `allTools(isPro, capabilities)` AND execution-time re-check in `tool-loop.ts` (`capability_blocked`) — the model can emit a tool BY NAME it was never offered. | `daySwapWeekProvider` / `daySwapAllowanceProvider` invalidated after dispatch. Snapshot `week_lookahead` + `swaps_left` are both in `trimSnapshotToBudget`'s never-trim set. |
| `coach_chat_history_replay` (Unit 2) | `CoachInteractionRepository.recentHistoryExchanges` — last N COMPLETE exchanges oldest→newest; excludes `kind`-tagged / pending / `failed` / `had_hard_failure` / `mode:'media'` / empty rows; sent as `history` via `ai_service.chat` (assembled ONCE in `SendMessageNotifier.send`, both call sites). Kill-switch `configBox['disable_coach_history']`. **History-poisoning guard:** the hardcoded `tool-loop.ts` apologies set `hadHardFailure` → `had_hard_failure` (a DEDICATED field, NOT `failed`); restore path uses `isRestoredHardFailureRow` (apology text OR `kModelUsedLoopThrewSentinel`). | `ai-proxy` `capCoachHistory` (§4.4 rule 18: ≤16 entries / 2000 chars each / 12000 total) → `tool-loop.ts` `repairHistoryAlternation`. Provenance: `docs/architecture/ai-coach-detail.md`. |

## Tool dispatch contract

When the agent emits a `tool_call`, the dispatcher MUST:

1. Validate the tool name against the kept allowlist (`logSet`, `logMealByText`,
   `createCustomExercise`, `createCustomTemplate`, `scheduleTemplate`,
   `swapExercise`, `shortenWorkout`, `generateHotelWorkout`, `swapWorkoutDays`
   (day-swapper + sync-load batch — PRO + capability-gated, see
   `coach_swap_workout_days` above), plus the 5 plan-edit
   tools `switchGoal` / `regeneratePlanBlock` / `rescheduleWeek` / `pausePlan` /
   `modifyWorkoutForInjury`, plus the read tools). The 4 derive-violating tools
   (`logPR`, `markWorkoutComplete`, `adjustCaloricTarget`, `prelog`) were
   **removed 2026-05-31** — the dispatcher has no case for them (defense-in-depth
   against a stale/replayed intent). See ADR-0012. `switchGoal` / `regeneratePlanBlock` never
   write past the stored `plan_end` (OI-189, `b9e4d1`): `RegeneratePlanResult.totalWeeks` is the bounded count; an empty regen whose sweep removed rows returns SUCCESS (`count: 0, cleared: N`), and is refused only when the sweep removed nothing.
2. Call the corresponding **canonical WriteService** — never raw Hive,
   never bypass `wrapUserScopedBox`. Bypassing surfaced as APK Test #16.2 / E
   (the now-removed `logPR` path) — the dispatcher is a *router*, not a writer.
3. Fire-and-forget `unawaited(syncDomain())` after the write.
4. Return a structured `ToolResult` to the agent so the next assistant turn can
   refer to it.

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| Mic stops after 2-3 seconds | `pauseFor: 5s`, `listenFor: 60s`, `ListenMode.dictation`, `partialResults: true` via `SpeechListenOptions`. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| "Restart the app" error copy | Never use. Map server errors to actionable user messages in `ai_coach_provider.dart`: `Message too long` → "shorten it", `Snapshot too large` → "try a shorter question", `Image too large` → "max 5 MB", `502/503/504` → "model temporarily unavailable, try in a minute". | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| AI breakdown card "didn't log" but data was saved | Data WAS saved; the bug was UI (no confirmation signal). `AiBreakdownNotifier.saveMeal` returns `Future<WriteResult>`, card shows `Meal saved ✓` snackbar + `HapticFeedback.lightImpact()`, `_saving` guards double-tap. **Every save action that mutates data MUST give the user a confirmation signal.** Canonical patterns: `scan_meal_section.dart`, `food_search_sheet.dart`. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Tool dispatcher writes to Hive directly | Always route through the canonical WriteService. The dispatcher is a *router*, not a writer. (Founding incident was the now-removed `logPR` path — APK Test #16.2 / E.) | `coach_derived_completion` SoT |
| AI tool asserts a derived value (PR, completion, calorie target) instead of raw input | Derive-only surface (ADR-0012): the AI logs raw sets/reps/weight/meals; PRs derive via `_rescanPrFor`/`loadAllExercisePRs`, completion derives via `_maybeCompleteScheduledDay → markCompleted`, calorie target stays derived. Never re-add a tool that lets the model assert a computed result — it's a progression-gaming / data-integrity hole. | ADR-0012 + `derive_only_tool_surface_test.dart` |
| Chat 3× duplicates after weak network | 60s client-side dedup + `ai-proxy` placeholder dedup + 3-strike circuit breaker (APK Test #16.1 / Theme B). Don't disable any of the three layers. | `feedback_observability_silent_drop.md` |
| Photo analysis returns 500 with no actionable error | APK Test #16.1 / Theme C — `ai-media-proxy` now classifies into 400 (user input) / 502 (upstream) / 500 (server) via `HttpError` shape. Chat bubble renders "photo-failed" state distinctly. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| A goal tool's `z.enum` drifts from the `FitnessGoals` SoT | `switchGoal.newGoal` and `regeneratePlanBlock.goal` MUST both list exactly the `FitnessGoals` tokens. Enforced by `scripts/check_goal_token_exhaustiveness.dart` Check 4 + `ai_proxy_goal_enum_parity_test.dart`; dispatcher guards via `FitnessGoals.isKnown`. | diagnose a4f7e1 + ADR-0015 |

## Tests pinning the rules here

- `test/contracts/coach_extraction_locked_fields_writer_to_reader_test.dart` (source-structure wiring pins) + `supabase/functions/daily-snapshot/index_test.ts` (behavioral) + `test/profile/edit_profile_coach_extraction_lock_test.dart` + `test/shared/user_repository_coach_extraction_lock_test.dart` + `test/ai_coach/coach_memory_model_test.dart`.
- Writer/reader contracts: `test/contracts/coach_interactions_writer_to_reader_test.dart`, `coach_replies_test.dart`, `coach_notes_upward_sync_test.dart`, `coaching_notes_writer_to_reader_test.dart`, `ai_snapshot_builder_only_test.dart`, `ai_snapshot_building_writer_to_reader_test.dart`, `ai_proxy_placeholder_resolution_test.dart`, `ai_proxy_day_injection_test.dart`, `conversational_log_handler_uses_write_service_test.dart`, `chat_media_signed_url_test.dart`, `ai_media_proxy_*_test.dart` (SSRF allowlist, status classification, telemetry, user scope).
- `test/contracts/coach_chat_history_replay_writer_to_reader_test.dart` (behavioral) + Deno `supabase/functions/_shared/tool-loop.test.ts` + `tool-loop_hard_failure_flag_test.ts` + `test/ai_coach/ai_service_had_hard_failure_parse_test.dart` + `test/contracts/hard_failure_apology_texts_parity_test.dart` (TS/Dart apology + sentinel parity, `isRestoredHardFailureRow`, `_restoreCoachInteractions` wiring pin).
- `test/contracts/derive_only_tool_surface_test.dart` (registry = 20 tools, 4 removed absent, dispatcher has no removed cases, completion-derivation wired).
- `test/contracts/coach_derived_pr_and_completion_test.dart` (behavioral — PR derives from `logSet` via `loadAllExercisePRs`; coach `logSet` on a scheduled day → `completed`).
- `test/contracts/coach_completion_prompt_test.dart` (behavioral — partial stays planned + prompt row; all-logged auto; tap complete; swap counts; one prompt per date).
- `test/contracts/ai_proxy_goal_enum_parity_test.dart` (server goal enums == `FitnessGoals` tokens; dispatcher goal-guard symmetry).
- `test/contracts/no_legacy_log_set_with_pr_rescan_declaration_test.dart`, `bodyweight_trend_nudge_test.dart`, `coach_media_consent_test.dart`, `coach_media_repository_test.dart` (behavioral / source-grep pins).
- `test/widgets/chat_bubble_media_consent_test.dart`, `test/router/saved_coach_photos_route_test.dart`.
- `test/contracts/ai_media_proxy_ssrf_allowlist_test.dart` pins the exact `ALLOWED_BUCKETS` set (`chat-media`, `coach-media`, `progress-photos`).

## See also

- `supabase/functions/CLAUDE.md` — `ai-proxy` + `ai-media-proxy` deploy + rate-limit triggers.
- `docs/architecture/ai-coach-detail.md` — moved-out history, provenance and full test inventory for this file.
- `docs/architecture/ai.md` — model matrix + tools + triggers + semantic retrieval.
- `lib/features/nutrition/CLAUDE.md` — AI breakdown card lives in nutrition (cross-feature).
