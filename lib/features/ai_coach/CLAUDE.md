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

`lib/features/ai_coach/` owns the 💬 AI Coach tab. The user chats with a single
server-side AI agent (`ai-proxy` Edge Function → Gemini 2.5 Flash) that has
**tool access** to log raw workouts / meals, do confirmed plan edits, swap
exercises, and read the user's recent activity snapshot. The surface is
**derive-only** (ADR-0012): the AI logs raw input only — PRs, completion, and
calorie targets are *computed* by the app, never AI-asserted. 20 tools total
(FREE 9 / PRO 11) after the 2026-05-31 prune.

Pieces:

- `screens/ai_coach_screen.dart` — chat UI + reasoning tab (PRO) + photo upload (5 free lifetime reads, then PRO; PRO capped 50/IST-day, OI-153) + suggested-actions sidebar + Telegram toggle. ⚠ There is NO video uploader: `media_picker.dart` is the only `sendWithMedia` call site and always sends `mediaType: 'image'` (`grep -rn "pickVideo\|'video'" lib/` is empty). The server's PRO video cap (10/IST-day) protects the API surface, not a UI path — this line said "photo / video upload" until 2026-09-12.
- `widgets/` — chat bubble, ai breakdown card (logs meals from text/photo via tool call), the photo uploader, quick-prompt chips, voice button (`SpeechListenOptions`).
- `copy/coach_replies.dart` — the CLIENT MIRROR of `supabase/functions/_shared/coach_replies.ts`. Every server key must have a byte-identical Dart twin and neither file may say "unlimited" (`test/contracts/coach_replies_test.dart` derives the key set from the `.ts` object — a drifted, missing or unmirrored key fails). Nothing on the client reads the new OI-153 keys today; the refusal reaches the user as the server's 200 `reply`, which `sendWithMedia` already renders as a coach bubble.
- `services/tool_dispatcher.dart` — receives the agent's `tool_call` and routes to the canonical WriteService (NEVER calls Hive directly — `coach_derived_completion` SoT). After a coach `logSet` on a scheduled day `_maybeCompleteScheduledDay` derives completion: auto-`markCompleted` ONLY when EVERY planned exercise is now logged (the all-logged backstop, Unit 1 / 280c4d), else it writes a `completion_prompt_<date>` tap-card row — one coach `logSet` no longer completes the whole day.
- `services/ai_snapshot_builder.dart` — builds the snapshot payload (recent logs + today's targets + plan day + coach memory excerpt). Read-only.
- `repositories/ai_coach_repository.dart` — Hive read for chat history + snapshot inputs; cloud upward sync for `coach_interactions` + `coach_memory.coach_notes`.
- `providers/ai_coach_provider.dart` — chat state, error mapping, dedup ring buffer.

## Single-source-of-truth contracts

| Concept | Writer | Reader |
|---|---|---|
| `coach_interactions` | `ai_coach_repository.dart` `appendInteraction` → Hive + sync | chat thread renderer in `ai_coach_screen.dart`. **Dedup guards:** 60s client-side dedup + `ai-proxy` placeholder dedup + 3-strike circuit breaker (APK Test #16.1 / Theme B). |
| `ai_snapshot_building` | `ai_snapshot_builder.dart` `buildAiContext` (extracted from `ai_coach_repository` per audit 2026-05-20 / A10) | `ai-proxy` Edge Function request body. Includes `personal_records` + `today_workout` + `recent_logs` from `exlog_*` Hive rows. |
| `coach_derived_completion` | `tool_dispatcher.dart` `_maybeCompleteScheduledDay` → `WorkoutWriteService.markCompleted`. **Unit 1 (2026-07-06, 280c4d):** completion = **all-logged AUTO** (auto-`markCompleted(completedVia:'auto')` ONLY when `plannedCount > 0` AND EVERY planned `exercises[]` entry has a log today — swap-tolerant via `swapped_from`, warmup/cooldown/finisher optional; an **empty `exercises[]` plan-less day is NOT auto-completed** (finding-4) — it falls through to the tap-card so only an explicit tap can finish it) **OR** a **user-tapped card**. A genuine partial STAYS `planned` and writes a LOCAL-ONLY `completion_prompt_<date>` coachBox row (`kind:'completion_prompt'`, date-scoped, UPDATE-not-INSERT) → `ChatHistoryNotifier` renders a two-button `[Log more] · [Complete workout]` tile; the tap → `markCompleted(completedVia:'tap')`. The model NEVER asserts completion (ADR-0012). One coach `logSet` no longer completes the whole day (the founder bug). Idempotent: the per-date lock lives inside markCompleted (workout_write_service.dart:424) — `_maybeCompleteScheduledDay`'s own status re-check (tool_dispatcher.dart:399) runs OUTSIDE it; the benign-race posture is documented at workout_write_service.dart:430-439. (Corrected 2026-09-18 — this cell previously claimed the re-check was under the lock.) Prompt row is LOCAL-ONLY (sync push skips `kind`-tagged rows; never restored). | `train_screen` completed-day view + home Today's Workout card; cloud `scheduled_workouts.status`; `ChatHistoryNotifier.build` (prompt tile) + `ai_snapshot_builder` `today_workout.today_workout_completion:{total_planned,total_logged,all_logged}`. |
| `coach_memory_coach_notes_upward_sync` | `ai_coach_repository.dart` → cloud `coach_memory.coach_notes` (renamed from `coaching_notes`; Hive key preserved) | `ai_snapshot_builder.dart`. APK Test #16.2 / 9th writer/reader drift. |
| `ai_proxy_placeholder_resolution` | `ai-proxy` Edge Function v66 inserts placeholder row BEFORE Gemini call (rate-limit trigger SoT) | dedup logic checks placeholder before issuing a new request. |
| `chat_media_signed_url` | `ai-media-proxy` Edge Function (PRO only) — SSRF-allowlisted to `chat-media`, `coach-media`, `progress-photos` Storage buckets only (corrected 2026-07-30, Unit 8 — this row previously named a bucket, `chat-attachments`, that never existed in the codebase) | `WardroomChatBubble` photo renderer. |
| `coach_media_consent` (Unit 8, OI-25, 2026-07-30) | `CoachInteractionRepository.recordMediaSaveDecision` writes `media_save_state` (`null`\|`'saved'`\|`'declined'`) in place on the same `coach_<ms>` row that carries `media_url`/`media_storage_path`. `CoachMediaRepository.saveForLater` does the actual Storage `.copy()` from `chat-media` → `coach-media` (no metadata table — migration 070's buckets + RLS only) | `ChatBubble`'s save-consent chip (gates on `mediaAnalysisComplete && mediaSaveState == null`); `SavedCoachPhotosScreen` lists `coach-media/<uid>/` directly via `CoachMediaRepository.list()` (signed-URL pattern mirrored from `ProgressPhotoRepository.list()`). |
| `bodyweight_trend_nudge` (W2.6) | `TrainingHistoryAnalyzer.bodyweightTrendSignal()` (28d-vs-prior-28d MEAN, was dead) → `PatternDetector._bodyweightTrendNudge` (13th detector) emits a LOW-severity `CoachingInsight`. **Deduped ON THE OUTCOME** of `_weightTrendAlert` (calls it, returns null if it fired — the 14-day alert and 28d-mean nudge use divergent metrics, so re-deriving the threshold would double-fire/gap). Goal-aware copy for all 5 `FitnessGoals` tokens + empty-goal fallback (sole weight signal for strength/general_fitness/recompose). Kill-switch `configBox['disable_bodyweight_trend_nudge']`. | home `insight_card.dart` (`topInsightProvider`→`getTopInsight`). **`severity: low` is LOAD-BEARING** — `_getCoachNotices` (`ai_snapshot_builder.dart:911`) drops `low` before the AI prompt, so it never pollutes the coach snapshot; a bump to `medium` would silently start feeding it in. |
| `coach_chat_history_replay` (Unit 2, 2026-07-07) | `CoachInteractionRepository.recentHistoryExchanges` — last N COMPLETE exchanges, oldest→newest, sorted by `created_at`; excludes `kind`-tagged / pending / `failed` / `had_hard_failure` / `mode:'media'` / empty rows + the `coach_memory` singleton — sent as a `history` field via `ai_service.chat` (assembled ONCE in `SendMessageNotifier.send`, threaded into BOTH the primary `:895` and auth-retry `:967` call sites AND both request bodies). Kill-switch `configBox['disable_coach_history']`. **History-poisoning fix (APK +43 obs 2, diagnose `a1c6b9`, 2026-09-16):** TWO hardcoded, non-model apologies in `tool-loop.ts` (`HARD_FAILURE_APOLOGY_GEMINI_CALL_FAILED` / `HARD_FAILURE_APOLOGY_ROUNDS_EXHAUSTED`, exported constants) used to be persisted like real output and replayed into the NEXT turn's history, so the model echoed one as a normal continuation — one transient outage became a self-perpetuating "stuck" chat. `runToolLoop`'s `ToolLoopResult.hadHardFailure` (set true at BOTH sites) threads through `ai-proxy`'s response body (`had_hard_failure`) → `AiChatResponse.hadHardFailure` → `CoachInteractionRepository.updateInteractionWithResponse(hadHardFailure:)` writes a **NEW, dedicated `entry['had_hard_failure']`** field — plan-review round 1 finding: the original draft reused `entry['failed']`, which collided with `failed`'s OTHER reader (`ChatHistoryNotifier.build`'s error-bubble+Retry render); `failed` stays unconditionally `false` on this success-resolution path exactly as it always was, and `recentHistoryExchanges` now excludes on `failed == true || had_hard_failure == true`. **Restore-path defense (same finding, round 1; widened round 2):** `ai-proxy`'s reservation-resolve persists `ai_response` to the cloud UNCONDITIONALLY (no cloud column for the flag), so `sync_coach.dart`'s `_restoreCoachInteractions` recognizes a restored hard-failure row via `isRestoredHardFailureRow` — either exact text match against `kKnownHardFailureApologyTexts` (a client-side mirror of both TS apology constants, parity-pinned) OR `model_used` matching `kModelUsedLoopThrewSentinel` (a mirror of `ai-proxy/index.ts`'s exported `MODEL_USED_LOOP_THREW_SENTINEL`, plan-review round 2 finding — the `runToolLoop`-THREW catch block writes a third, differently-worded failure text the apology-text match alone could not catch). Also guards the semantic-memory embed so neither apology is ever embedded either. | `ai-proxy` `capCoachHistory` size-bounds it (§4.4 rule 18: ≤16 entries / ≤2000 chars each / ≤12000 total, oldest-first) → `tool-loop.ts` `repairHistoryAlternation` (shrink-only) seeds `messages[]` BEFORE the current user turn (never 400s Gemini on consecutive same-role turns). Snapshot stays in the system prompt (FC7), so history is a clean `user→model` chain. Complementary to snapshot + `coach_memory` + semantic retrieval. |

## Tool dispatch contract

When the agent emits a `tool_call`, the dispatcher MUST:

1. Validate the tool name against the kept allowlist (`logSet`, `logMealByText`,
   `createCustomExercise`, `createCustomTemplate`, `scheduleTemplate`,
   `swapExercise`, `shortenWorkout`, `generateHotelWorkout`, plus the 5 plan-edit
   tools `switchGoal` / `regeneratePlanBlock` / `rescheduleWeek` / `pausePlan` /
   `modifyWorkoutForInjury`, plus the read tools). The 4 derive-violating tools
   (`logPR`, `markWorkoutComplete`, `adjustCaloricTarget`, `prelog`) were
   **removed 2026-05-31** — the dispatcher has no case for them (defense-in-depth
   against a stale/replayed intent). See ADR-0012. `switchGoal` / `regeneratePlanBlock` never
   write past the stored `plan_end` (OI-189, `b9e4d1`): `RegeneratePlanResult.totalWeeks` is the
   bounded count, `requestedWeeks` what was asked, `clearsPastPhaseEnd` what the commit will sweep;
   both commit sites sweep then push `plan_json`; an empty regen whose sweep removed rows returns
   SUCCESS with `count: 0, cleared: N` (so the invalidate tail runs), and is refused — cache kept,
   Retry repeats the message — only when the sweep removed nothing.
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
| AI breakdown card "didn't log" but data was saved | Test #11 L1 (founder-reported). Data WAS saved correctly to Hive + cloud with `items[]`. Bug was UI: no snackbar / haptic / toast on save → card just disappeared → user assumed failure. Fixed: `AiBreakdownNotifier.saveMeal` now returns `Future<WriteResult>`, card pops `Meal saved ✓` snackbar with `HapticFeedback.lightImpact()`. Plus `_saving` guard prevents double-tap race. **Pattern lesson:** every save action that mutates data MUST give the user a confirmation signal, even if the success is "just" a card vanishing. Compare canonical patterns at `scan_meal_section.dart:445-465` and `food_search_sheet.dart:519`. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Tool dispatcher writes to Hive directly | Always route through the canonical WriteService. The dispatcher is a *router*, not a writer. (Founding incident was the now-removed `logPR` path — APK Test #16.2 / E.) | `coach_derived_completion` SoT |
| AI tool asserts a derived value (PR, completion, calorie target) instead of raw input | Derive-only surface (ADR-0012): the AI logs raw sets/reps/weight/meals; PRs derive via `_rescanPrFor`/`loadAllExercisePRs`, completion derives via `_maybeCompleteScheduledDay → markCompleted`, calorie target stays derived. Never re-add a tool that lets the model assert a computed result — it's a progression-gaming / data-integrity hole. | ADR-0012 + `derive_only_tool_surface_test.dart` |
| Chat 3× duplicates after weak network | APK Test #16.1 / Theme B — 60s client-side dedup + `ai-proxy` placeholder dedup + 3-strike circuit breaker fixed it. Migration 066 cleaned 10/18 dupe rows. Don't disable any of the three layers. | `feedback_observability_silent_drop.md` |
| Photo analysis returns 500 with no actionable error | APK Test #16.1 / Theme C — `ai-media-proxy` now classifies into 400 (user input) / 502 (upstream) / 500 (server) via `HttpError` shape. Chat bubble renders "photo-failed" state distinctly. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| A goal tool's `z.enum` drifts from the `FitnessGoals` SoT | The two plan tools that carry a goal (`switchGoal.newGoal`, `regeneratePlanBlock.goal`) each expose a `z.enum` to the model — both MUST list exactly the `FitnessGoals` tokens. A token in one tool but not the other (recompose was — F19 sibling) means the AI can't act on it or the client rejects it. Enforced by `scripts/check_goal_token_exhaustiveness.dart` Check 4 + `ai_proxy_goal_enum_parity_test.dart`; the dispatcher also guards both `_executeSwitchGoal` / `_executeRegeneratePlanBlock` via `FitnessGoals.isKnown`. | diagnose a4f7e1 + ADR-0015 |

## Tests pinning the rules here

- `test/contracts/coach_interactions_writer_to_reader_test.dart`
- `test/contracts/coach_chat_history_replay_writer_to_reader_test.dart` (behavioral — Unit 2: `recentHistoryExchanges` alternating/sorted/filtered; both `chat()` call sites carry history; server-seam source assertions; APK +43 obs 2 — `hadHardFailure:true` excludes the turn from replay via the NEW `had_hard_failure` field while `failed` stays false, default `false` keeps it; plan-review round 1 added 2 cases — `had_hard_failure` alone excludes, and a simulated restored row excludes) + Deno `supabase/functions/_shared/tool-loop.test.ts` (`repairHistoryAlternation` + `capCoachHistory`) + `supabase/functions/_shared/tool-loop_hard_failure_flag_test.ts` (`hadHardFailure` set true at BOTH apology sites — Gemini-call-failed catch block and rounds-exhausted branch — false on the happy path and the FC2 queued-intent case) + `test/ai_coach/ai_service_had_hard_failure_parse_test.dart` (`had_hard_failure` JSON → `AiChatResponse.hadHardFailure` parse, incl. missing-field default) + `test/contracts/hard_failure_apology_texts_parity_test.dart` (plan-review round 1 — TS/Dart apology-text parity, `isKnownHardFailureApologyText` pure-function behavior, `_restoreCoachInteractions` wiring pin; round 2 extended — `MODEL_USED_LOOP_THREW_SENTINEL` parity, `isRestoredHardFailureRow` behavioral coverage across all 4 boolean-input combinations, wiring pin updated to the composed function — 17 tests total).
- `test/contracts/coach_replies_test.dart`
- `test/contracts/coach_notes_upward_sync_test.dart`
- `test/contracts/coaching_notes_writer_to_reader_test.dart`
- `test/contracts/ai_snapshot_builder_only_test.dart`
- `test/contracts/ai_snapshot_building_writer_to_reader_test.dart`
- `test/contracts/ai_proxy_placeholder_resolution_test.dart`
- `test/contracts/ai_proxy_day_injection_test.dart`
- `test/contracts/conversational_log_handler_uses_write_service_test.dart`
- `test/contracts/chat_media_signed_url_test.dart`
- `test/contracts/ai_media_proxy_*_test.dart` (4 — SSRF allowlist, status classification, telemetry, user scope).
- `test/contracts/derive_only_tool_surface_test.dart` (registry = 20 tools, 4 removed absent, dispatcher has no removed cases, completion-derivation wired).
- `test/contracts/coach_derived_pr_and_completion_test.dart` (behavioral — PR derives from `logSet` via `loadAllExercisePRs`; coach `logSet` on a scheduled day → `completed`).
- `test/contracts/coach_completion_prompt_test.dart` (behavioral — Unit 1 / 280c4d: partial coach log STAYS planned + writes a `completion_prompt` row; all-logged → auto-completed (`completed_via:auto`); `[Complete workout]` tap → completed (`completed_via:tap`); swapped exercise counts; prompt deduped one-per-date; snapshot carries `today_workout_completion`).
- `test/contracts/ai_proxy_goal_enum_parity_test.dart` (server `switchGoal` + `regeneratePlanBlock` goal enums == `FitnessGoals` tokens; dispatcher goal-guard symmetry — F19 sibling a4f7e1).
- `test/contracts/no_legacy_log_set_with_pr_rescan_declaration_test.dart` (legacy `logSetWithPrRescan` declaration stays deleted).
- `test/contracts/bodyweight_trend_nudge_test.dart` (behavioral — W2.6: trend→low nudge; dedup-on-outcome vs `_weightTrendAlert`; flat/insufficient → none; kill-switch; goal coverage across all `FitnessGoals.tokens`).
- `test/contracts/coach_media_consent_test.dart` (behavioral, Unit 8 — `mediaStoragePath` persists on `saveUserMessagePending`; `recordMediaSaveDecision` writes `saved`/`declined`, no-ops on a missing key; a `ChatHistoryNotifier.build`-simulated rebuild proves the user bubble now carries `coachKey` (regression for the pre-existing gap where only the AI/error bubble did) and `mediaAnalysisComplete` flips only once the SAME row's `ai_response` resolves).
- `test/contracts/coach_media_repository_test.dart` (pure-Dart `ChatMessage.copyWithMediaState` round-trip + source-grep pins on `coach_media_repository.dart`: `.copy(...destinationBucket: 'coach-media')`, source-delete gated `if (!isPro)`, ownership prefix check present in both `saveForLater` and `delete`).
- `test/widgets/chat_bubble_media_consent_test.dart` (widget — save-consent chip gates on `isUser && hasMediaUrl && mediaAnalysisComplete && mediaSaveState == null`; `onSaveMedia`/`onDeclineMedia` fire on tap; `'saved'` renders the badge instead; `'declined'` renders neither; AI bubbles and failed-photo bubbles never show it).
- `test/router/saved_coach_photos_route_test.dart` (source-grep — `/profile/saved-coach-photos` route registered; Profile REPORTS card has a Saved Photos row navigating to it).
- `test/contracts/ai_media_proxy_ssrf_allowlist_test.dart` extended (Unit 8) — pins the exact `ALLOWED_BUCKETS` set (`chat-media`, `coach-media`, `progress-photos`) and asserts the phantom `chat-attachments` name is absent, closing the gap that let the CLAUDE.md doc drift stale.

## See also

- `supabase/functions/CLAUDE.md` — `ai-proxy` + `ai-media-proxy` deploy + rate-limit triggers.
- `docs/architecture/ai.md` — model matrix + tools + triggers + semantic retrieval.
- `lib/features/nutrition/CLAUDE.md` — AI breakdown card lives in nutrition (cross-feature).
