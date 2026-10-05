# AI Coach - moved-out detail

On-demand detail for `lib/features/ai_coach/CLAUDE.md`. Everything here was moved VERBATIM out of the nested file (dated incident narratives, correction histories, long test inventories) to keep the auto-loaded file lean. The nested file keeps the current contract for each item and points here. Nothing below is a live contract that differs from the nested file; read this when you need the history, the plan-review provenance, or the full test inventory.

## screens/ai_coach_screen.dart bullet (full)

_Moved verbatim from `lib/features/ai_coach/CLAUDE.md` (original lines 30-30, context-lean batch 2026-09-29)._

- `screens/ai_coach_screen.dart` — chat UI + reasoning tab (PRO) + photo upload (5 free lifetime reads, then PRO; PRO capped 50/IST-day, OI-153) + suggested-actions sidebar + Telegram toggle. ⚠ There is NO video uploader: `media_picker.dart` is the only `sendWithMedia` call site and always sends `mediaType: 'image'` (`grep -rn "pickVideo\|'video'" lib/` is empty). The server's PRO video cap (10/IST-day) protects the API surface, not a UI path — this line said "photo / video upload" until 2026-09-12.

## coach_derived_completion row (full)

_Moved verbatim from `lib/features/ai_coach/CLAUDE.md` (original lines 44-44, context-lean batch 2026-09-29)._

| Concept | Writer | Reader |
|---|---|---|

| `coach_derived_completion` | `tool_dispatcher.dart` `_maybeCompleteScheduledDay` → `WorkoutWriteService.markCompleted`. **Unit 1 (2026-07-06, 280c4d):** completion = **all-logged AUTO** (auto-`markCompleted(completedVia:'auto')` ONLY when `plannedCount > 0` AND EVERY planned `exercises[]` entry has a log today — swap-tolerant via `swapped_from`, warmup/cooldown/finisher optional; an **empty `exercises[]` plan-less day is NOT auto-completed** (finding-4) — it falls through to the tap-card so only an explicit tap can finish it) **OR** a **user-tapped card**. A genuine partial STAYS `planned` and writes a LOCAL-ONLY `completion_prompt_<date>` coachBox row (`kind:'completion_prompt'`, date-scoped, UPDATE-not-INSERT) → `ChatHistoryNotifier` renders a two-button `[Log more] · [Complete workout]` tile; the tap → `markCompleted(completedVia:'tap')`. The model NEVER asserts completion (ADR-0012). One coach `logSet` no longer completes the whole day (the founder bug). Idempotent: the per-date lock lives inside markCompleted (workout_write_service.dart:424) — `_maybeCompleteScheduledDay`'s own status re-check (tool_dispatcher.dart:399) runs OUTSIDE it; the benign-race posture is documented at workout_write_service.dart:430-439. (Corrected 2026-09-18 — this cell previously claimed the re-check was under the lock.) Prompt row is LOCAL-ONLY (sync push skips `kind`-tagged rows; never restored). | `train_screen` completed-day view + home Today's Workout card; cloud `scheduled_workouts.status`; `ChatHistoryNotifier.build` (prompt tile) + `ai_snapshot_builder` `today_workout.today_workout_completion:{total_planned,total_logged,all_logged}`. |

## coach_extraction_locked_fields row (full)

_Moved verbatim from `lib/features/ai_coach/CLAUDE.md` (original lines 46-46, context-lean batch 2026-09-29)._

| Concept | Writer | Reader |
|---|---|---|

| `coach_extraction_locked_fields` (a2b-2, single-owner batch, 2026-09-27) | `lock_coach_extraction_fields` RPC (migration 148, additive-only UNION) ← `UserRepository.lockCoachExtractionFields`, called from Edit Profile's `_save` (fields that actually changed) and `syncOnboardingToSupabase` (a real onboarding injuries selection, not the `['none']` default). `daily-snapshot/index.ts`'s `mergeCoachingNotes` reads the lock list before writing any of `diet_preference`/`lifestyle_activity`/`injuries` into `user_profile`, and writes an attempted-value conflict marker to `coach_memory.locked_field_conflicts` (merged over any existing marker, never a wholesale replace) instead of silently overwriting a locked field. **Ground-truth correction during implementation**: the plan's own Design originally targeted `user_preferences.coaching_notes` for the conflict marker — that column has zero readers anywhere (`ai-proxy`/`_shared`/`rolling-context`/`weekly-report`), found only by grepping every call site, not by any of the plan's 5 converged review rounds. | `mergeCoachingNotes` itself (the lock list). The conflict marker reaches the AI via `_getCoachMemoryForContext()`'s wholesale `mem.toJson()` pass-through — same reader as `coach_notes` above, no new plumbing needed once the field exists on `CoachMemory`. |

## coach_media_consent row (full)

_Moved verbatim from `lib/features/ai_coach/CLAUDE.md` (original lines 49-49, context-lean batch 2026-09-29)._

| Concept | Writer | Reader |
|---|---|---|

| `coach_media_consent` (Unit 8, OI-25, 2026-07-30) | `CoachInteractionRepository.recordMediaSaveDecision` writes `media_save_state` (`null`\|`'saved'`\|`'declined'`) in place on the same `coach_<ms>` row that carries `media_url`/`media_storage_path`. `CoachMediaRepository.saveForLater` does the actual Storage `.copy()` from `chat-media` → `coach-media` (no metadata table — migration 070's buckets + RLS only) | `ChatBubble`'s save-consent chip (gates on `mediaAnalysisComplete && mediaSaveState == null`); `SavedCoachPhotosScreen` lists `coach-media/<uid>/` directly via `CoachMediaRepository.list()` (signed-URL pattern mirrored from `ProgressPhotoRepository.list()`). |

## bodyweight_trend_nudge row (full)

_Moved verbatim from `lib/features/ai_coach/CLAUDE.md` (original lines 50-50, context-lean batch 2026-09-29)._

| Concept | Writer | Reader |
|---|---|---|

| `bodyweight_trend_nudge` (W2.6) | `TrainingHistoryAnalyzer.bodyweightTrendSignal()` (28d-vs-prior-28d MEAN, was dead) → `PatternDetector._bodyweightTrendNudge` (13th detector) emits a LOW-severity `CoachingInsight`. **Deduped ON THE OUTCOME** of `_weightTrendAlert` (calls it, returns null if it fired — the 14-day alert and 28d-mean nudge use divergent metrics, so re-deriving the threshold would double-fire/gap). Goal-aware copy for all 5 `FitnessGoals` tokens + empty-goal fallback (sole weight signal for strength/general_fitness/recompose). Kill-switch `configBox['disable_bodyweight_trend_nudge']`. | home `insight_card.dart` (`topInsightProvider`→`getTopInsight`). **`severity: low` is LOAD-BEARING** — `_getCoachNotices` (`ai_snapshot_builder.dart:911`) drops `low` before the AI prompt, so it never pollutes the coach snapshot; a bump to `medium` would silently start feeding it in. |

## coach_swap_workout_days row (full)

_Moved verbatim from `lib/features/ai_coach/CLAUDE.md` (original lines 51-51, context-lean batch 2026-09-29)._

| Concept | Writer | Reader |
|---|---|---|

| `coach_swap_workout_days` (day-swapper + sync-load batch) | Tool `swapWorkoutDaysTool` (`supabase/functions/_shared/tools/workout/swapWorkoutDays.ts`) — PRO, `confirmationClass: reviewable`, `requiresCapability: 'swap_workout_days'` (`CAPABILITY_SWAP_WORKOUT_DAYS` in `day_swap_routing.ts`), intent type `swap_workout_days`. `tool_dispatcher.dart`'s `_executeSwapWorkoutDays` routes to `SwapService.swapDays` — never a bespoke Hive write. Client declares support via `kCoachClientCapabilities` → the `client_capabilities` request field (`client_capabilities.ts`: ≤32 entries considered, each `^[a-z_]{1,48}$`, silently dropped rather than 400'd — unlike `message`/`snapshot_json`, which DO 400 over-limit). Server picks exactly one Captain-Manual routing block per request via `daySwapRoutingCase(isPro, capabilities)` (`free` / `pro_old_app` / `pro_capable`) so the model is never asked to infer tier or app version itself; a PRO user on an app build that predates this feature gets the verbatim `DAY_SWAP_OLD_APP_LINE`, never a silent `rescheduleWeek` misroute. **Two independent gates, not one:** the offer-time filter (`allTools(isPro, capabilities)` excludes the tool from what Gemini is even shown) AND an EXECUTION-time re-check in `tool-loop.ts` (`capability_blocked` status, `error: "capability_required"`) — the model can still emit a functionCall BY NAME for a tool it was never offered (hallucinated, or recalled from `history`), so the offer-time filter alone is not enough. | `daySwapWeekProvider` / `daySwapAllowanceProvider` invalidated after dispatch (`tool_dispatcher.dart`, `intent.type == 'swap_workout_days'` branch — day-swap's own two providers are NOT covered by the general workout-provider invalidation batch). Snapshot: `week_lookahead` + `swaps_left` (`ai_snapshot_builder.dart`), both in `trimSnapshotToBudget`'s never-trim `keep` set — `swaps_left` is tiny (~2 entries) but useless without the lookahead it annotates, so both are kept or neither is (plan D7). |

## coach_chat_history_replay row (full)

_Moved verbatim from `lib/features/ai_coach/CLAUDE.md` (original lines 52-52, context-lean batch 2026-09-29)._

| Concept | Writer | Reader |
|---|---|---|

| `coach_chat_history_replay` (Unit 2, 2026-07-07) | `CoachInteractionRepository.recentHistoryExchanges` — last N COMPLETE exchanges, oldest→newest, sorted by `created_at`; excludes `kind`-tagged / pending / `failed` / `had_hard_failure` / `mode:'media'` / empty rows + the `coach_memory` singleton — sent as a `history` field via `ai_service.chat` (assembled ONCE in `SendMessageNotifier.send`, threaded into BOTH the primary `:895` and auth-retry `:967` call sites AND both request bodies). Kill-switch `configBox['disable_coach_history']`. **History-poisoning fix (APK +43 obs 2, diagnose `a1c6b9`, 2026-09-16):** TWO hardcoded, non-model apologies in `tool-loop.ts` (`HARD_FAILURE_APOLOGY_GEMINI_CALL_FAILED` / `HARD_FAILURE_APOLOGY_ROUNDS_EXHAUSTED`, exported constants) used to be persisted like real output and replayed into the NEXT turn's history, so the model echoed one as a normal continuation — one transient outage became a self-perpetuating "stuck" chat. `runToolLoop`'s `ToolLoopResult.hadHardFailure` (set true at BOTH sites) threads through `ai-proxy`'s response body (`had_hard_failure`) → `AiChatResponse.hadHardFailure` → `CoachInteractionRepository.updateInteractionWithResponse(hadHardFailure:)` writes a **NEW, dedicated `entry['had_hard_failure']`** field — plan-review round 1 finding: the original draft reused `entry['failed']`, which collided with `failed`'s OTHER reader (`ChatHistoryNotifier.build`'s error-bubble+Retry render); `failed` stays unconditionally `false` on this success-resolution path exactly as it always was, and `recentHistoryExchanges` now excludes on `failed == true || had_hard_failure == true`. **Restore-path defense (same finding, round 1; widened round 2):** `ai-proxy`'s reservation-resolve persists `ai_response` to the cloud UNCONDITIONALLY (no cloud column for the flag), so `sync_coach.dart`'s `_restoreCoachInteractions` recognizes a restored hard-failure row via `isRestoredHardFailureRow` — either exact text match against `kKnownHardFailureApologyTexts` (a client-side mirror of both TS apology constants, parity-pinned) OR `model_used` matching `kModelUsedLoopThrewSentinel` (a mirror of `ai-proxy/index.ts`'s exported `MODEL_USED_LOOP_THREW_SENTINEL`, plan-review round 2 finding — the `runToolLoop`-THREW catch block writes a third, differently-worded failure text the apology-text match alone could not catch). Also guards the semantic-memory embed so neither apology is ever embedded either. | `ai-proxy` `capCoachHistory` size-bounds it (§4.4 rule 18: ≤16 entries / ≤2000 chars each / ≤12000 total, oldest-first) → `tool-loop.ts` `repairHistoryAlternation` (shrink-only) seeds `messages[]` BEFORE the current user turn (never 400s Gemini on consecutive same-role turns). Snapshot stays in the system prompt (FC7), so history is a clean `user→model` chain. Complementary to snapshot + `coach_memory` + semantic retrieval. |

## Pitfall row: AI breakdown card 'didn't log' (full)

_Moved verbatim from `lib/features/ai_coach/CLAUDE.md` (original lines 86-86, context-lean batch 2026-09-29)._

| Pitfall | How to avoid | Source |
|---|---|---|

| AI breakdown card "didn't log" but data was saved | Test #11 L1 (founder-reported). Data WAS saved correctly to Hive + cloud with `items[]`. Bug was UI: no snackbar / haptic / toast on save → card just disappeared → user assumed failure. Fixed: `AiBreakdownNotifier.saveMeal` now returns `Future<WriteResult>`, card pops `Meal saved ✓` snackbar with `HapticFeedback.lightImpact()`. Plus `_saving` guard prevents double-tap race. **Pattern lesson:** every save action that mutates data MUST give the user a confirmation signal, even if the success is "just" a card vanishing. Compare canonical patterns at `scan_meal_section.dart:445-465` and `food_search_sheet.dart:519`. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |

## Pitfall row: Chat 3x duplicates (full)

_Moved verbatim from `lib/features/ai_coach/CLAUDE.md` (original lines 89-89, context-lean batch 2026-09-29)._

| Pitfall | How to avoid | Source |
|---|---|---|

| Chat 3× duplicates after weak network | APK Test #16.1 / Theme B — 60s client-side dedup + `ai-proxy` placeholder dedup + 3-strike circuit breaker fixed it. Migration 066 cleaned 10/18 dupe rows. Don't disable any of the three layers. | `feedback_observability_silent_drop.md` |

## Tests: coach_extraction_locked_fields (full)

_Moved verbatim from `lib/features/ai_coach/CLAUDE.md` (original lines 95-95, context-lean batch 2026-09-29)._

- `test/contracts/coach_extraction_locked_fields_writer_to_reader_test.dart` (source-structure wiring pins, incl. the P0 backfill + RAISE-not-INSERT shape) + `supabase/functions/daily-snapshot/index_test.ts` (behavioral — 6 tests: unlocked-applies-normally, locked-with-real-conflict-writes-marker, locked-with-same-value-is-a-no-op, injuries array-value-equality across reorder, injuries genuine-difference-conflict, new-conflict-merges-over-existing) + `test/profile/edit_profile_coach_extraction_lock_test.dart` (pure `computeCoachExtractionFieldsToLock`) + `test/shared/user_repository_coach_extraction_lock_test.dart` (pure `shouldLockOnboardingInjuries`) + `test/ai_coach/coach_memory_model_test.dart` (`lockedFieldConflicts` round-trip).

## Tests: coach_chat_history_replay (full)

_Moved verbatim from `lib/features/ai_coach/CLAUDE.md` (original lines 97-97, context-lean batch 2026-09-29)._

- `test/contracts/coach_chat_history_replay_writer_to_reader_test.dart` (behavioral — Unit 2: `recentHistoryExchanges` alternating/sorted/filtered; both `chat()` call sites carry history; server-seam source assertions; APK +43 obs 2 — `hadHardFailure:true` excludes the turn from replay via the NEW `had_hard_failure` field while `failed` stays false, default `false` keeps it; plan-review round 1 added 2 cases — `had_hard_failure` alone excludes, and a simulated restored row excludes) + Deno `supabase/functions/_shared/tool-loop.test.ts` (`repairHistoryAlternation` + `capCoachHistory`) + `supabase/functions/_shared/tool-loop_hard_failure_flag_test.ts` (`hadHardFailure` set true at BOTH apology sites — Gemini-call-failed catch block and rounds-exhausted branch — false on the happy path and the FC2 queued-intent case) + `test/ai_coach/ai_service_had_hard_failure_parse_test.dart` (`had_hard_failure` JSON → `AiChatResponse.hadHardFailure` parse, incl. missing-field default) + `test/contracts/hard_failure_apology_texts_parity_test.dart` (plan-review round 1 — TS/Dart apology-text parity, `isKnownHardFailureApologyText` pure-function behavior, `_restoreCoachInteractions` wiring pin; round 2 extended — `MODEL_USED_LOOP_THREW_SENTINEL` parity, `isRestoredHardFailureRow` behavioral coverage across all 4 boolean-input combinations, wiring pin updated to the composed function — 17 tests total).

## Tests: per-feature test inventory (full)

_Moved verbatim from `lib/features/ai_coach/CLAUDE.md` (original lines 110-118, context-lean batch 2026-09-29)._

- `test/contracts/coach_completion_prompt_test.dart` (behavioral — Unit 1 / 280c4d: partial coach log STAYS planned + writes a `completion_prompt` row; all-logged → auto-completed (`completed_via:auto`); `[Complete workout]` tap → completed (`completed_via:tap`); swapped exercise counts; prompt deduped one-per-date; snapshot carries `today_workout_completion`).
- `test/contracts/ai_proxy_goal_enum_parity_test.dart` (server `switchGoal` + `regeneratePlanBlock` goal enums == `FitnessGoals` tokens; dispatcher goal-guard symmetry — F19 sibling a4f7e1).
- `test/contracts/no_legacy_log_set_with_pr_rescan_declaration_test.dart` (legacy `logSetWithPrRescan` declaration stays deleted).
- `test/contracts/bodyweight_trend_nudge_test.dart` (behavioral — W2.6: trend→low nudge; dedup-on-outcome vs `_weightTrendAlert`; flat/insufficient → none; kill-switch; goal coverage across all `FitnessGoals.tokens`).
- `test/contracts/coach_media_consent_test.dart` (behavioral, Unit 8 — `mediaStoragePath` persists on `saveUserMessagePending`; `recordMediaSaveDecision` writes `saved`/`declined`, no-ops on a missing key; a `ChatHistoryNotifier.build`-simulated rebuild proves the user bubble now carries `coachKey` (regression for the pre-existing gap where only the AI/error bubble did) and `mediaAnalysisComplete` flips only once the SAME row's `ai_response` resolves).
- `test/contracts/coach_media_repository_test.dart` (pure-Dart `ChatMessage.copyWithMediaState` round-trip + source-grep pins on `coach_media_repository.dart`: `.copy(...destinationBucket: 'coach-media')`, source-delete gated `if (!isPro)`, ownership prefix check present in both `saveForLater` and `delete`).
- `test/widgets/chat_bubble_media_consent_test.dart` (widget — save-consent chip gates on `isUser && hasMediaUrl && mediaAnalysisComplete && mediaSaveState == null`; `onSaveMedia`/`onDeclineMedia` fire on tap; `'saved'` renders the badge instead; `'declined'` renders neither; AI bubbles and failed-photo bubbles never show it).
- `test/router/saved_coach_photos_route_test.dart` (source-grep — `/profile/saved-coach-photos` route registered; Profile has one live (comment-stripped) Photos row to the `/profile/photos` hub, whose Saved row navigates to it) + `test/router/photos_hub_route_resolution_test.dart` (the real route table resolves `/profile/saved-coach-photos` under `/profile` inside the shell and builds `SavedCoachPhotosScreen`).
- `test/contracts/ai_media_proxy_ssrf_allowlist_test.dart` extended (Unit 8) — pins the exact `ALLOWED_BUCKETS` set (`chat-media`, `coach-media`, `progress-photos`) and asserts the phantom `chat-attachments` name is absent, closing the gap that let the CLAUDE.md doc drift stale.

## What lives here: opening paragraph (full)

_Moved verbatim from `lib/features/ai_coach/CLAUDE.md` (original lines 16-26, context-lean batch 2026-09-29)._

`lib/features/ai_coach/` owns the 💬 AI Coach tab. The user chats with a single
server-side AI agent (`ai-proxy` Edge Function → Gemini 3.1 Flash Lite) that has
**tool access** to log raw workouts / meals, do confirmed plan edits, swap
exercises, and read the user's recent activity snapshot. The surface is
**derive-only** (ADR-0012): the AI logs raw input only — PRs, completion, and
calorie targets are *computed* by the app, never AI-asserted. **21 tools total
(FREE 9 / PRO 12)** since the day-swapper + sync-load batch added `swapWorkoutDays`
(20 total, FREE 9 / PRO 11, after the 2026-05-31 prune, before that) — see
`coach_swap_workout_days` below; a client that omits `client_capabilities`
entirely still sees exactly the 20 legacy tools (`allTools` requires the
capability string to be present, not merely PRO).

## Tool dispatch item 1: OI-189 plan_end bound (full)

_Moved verbatim from `lib/features/ai_coach/CLAUDE.md` (original lines 67-72, context-lean batch 2026-09-29)._

   against a stale/replayed intent). See ADR-0012. `switchGoal` / `regeneratePlanBlock` never
   write past the stored `plan_end` (OI-189, `b9e4d1`): `RegeneratePlanResult.totalWeeks` is the
   bounded count, `requestedWeeks` what was asked, `clearsPastPhaseEnd` what the commit will sweep;
   both commit sites sweep then push `plan_json`; an empty regen whose sweep removed rows returns
   SUCCESS with `count: 0, cleared: N` (so the invalidate tail runs), and is refused — cache kept,
   Retry repeats the message — only when the sweep removed nothing.


## Rows and list items condensed in place (verbatim originals)

_Moved verbatim from `lib/features/ai_coach/CLAUDE.md` (context-lean batch 2026-09-29); the nested file keeps a condensed form of each._

| A goal tool's `z.enum` drifts from the `FitnessGoals` SoT | The two plan tools that carry a goal (`switchGoal.newGoal`, `regeneratePlanBlock.goal`) each expose a `z.enum` to the model — both MUST list exactly the `FitnessGoals` tokens. A token in one tool but not the other (recompose was — F19 sibling) means the AI can't act on it or the client rejects it. Enforced by `scripts/check_goal_token_exhaustiveness.dart` Check 4 + `ai_proxy_goal_enum_parity_test.dart`; the dispatcher also guards both `_executeSwitchGoal` / `_executeRegeneratePlanBlock` via `FitnessGoals.isKnown`. | diagnose a4f7e1 + ADR-0015 |
- `test/contracts/coach_interactions_writer_to_reader_test.dart`
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
