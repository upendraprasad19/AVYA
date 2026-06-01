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

- `screens/ai_coach_screen.dart` — chat UI + reasoning tab (PRO) + photo / video upload (PRO) + suggested-actions sidebar + Telegram toggle.
- `widgets/` — chat bubble, ai breakdown card (logs meals from text/photo via tool call), photo/video uploaders, quick-prompt chips, voice button (`SpeechListenOptions`).
- `services/tool_dispatcher.dart` — receives the agent's `tool_call` and routes to the canonical WriteService (NEVER calls Hive directly — `coach_derived_completion` SoT). After a coach `logSet` on a scheduled day it auto-calls `WorkoutWriteService.markCompleted` (`_maybeCompleteScheduledDay`) so completion **derives** from logging.
- `services/ai_snapshot_builder.dart` — builds the snapshot payload (recent logs + today's targets + plan day + coach memory excerpt). Read-only.
- `repositories/ai_coach_repository.dart` — Hive read for chat history + snapshot inputs; cloud upward sync for `coach_interactions` + `coach_memory.coach_notes`.
- `providers/ai_coach_provider.dart` — chat state, error mapping, dedup ring buffer.

## Single-source-of-truth contracts

| Concept | Writer | Reader |
|---|---|---|
| `coach_interactions` | `ai_coach_repository.dart` `appendInteraction` → Hive + sync | chat thread renderer in `ai_coach_screen.dart`. **Dedup guards:** 60s client-side dedup + `ai-proxy` placeholder dedup + 3-strike circuit breaker (APK Test #16.1 / Theme B). |
| `ai_snapshot_building` | `ai_snapshot_builder.dart` `buildAiContext` (extracted from `ai_coach_repository` per audit 2026-05-20 / A10) | `ai-proxy` Edge Function request body. Includes `personal_records` + `today_workout` + `recent_logs` from `exlog_*` Hive rows. |
| `coach_derived_completion` | `tool_dispatcher.dart` `_maybeCompleteScheduledDay` → `WorkoutWriteService.markCompleted` (only when a `schedule_*` row exists for the date and isn't already `completed`; idempotent). Replaces the removed `markWorkoutComplete` tool — completion **derives** from a coach `logSet`. | `train_screen` completed-day view + home Today's Workout card; cloud `scheduled_workouts.status`. |
| `coach_memory_coach_notes_upward_sync` | `ai_coach_repository.dart` → cloud `coach_memory.coach_notes` (renamed from `coaching_notes`; Hive key preserved) | `ai_snapshot_builder.dart`. APK Test #16.2 / 9th writer/reader drift. |
| `ai_proxy_placeholder_resolution` | `ai-proxy` Edge Function v66 inserts placeholder row BEFORE Gemini call (rate-limit trigger SoT) | dedup logic checks placeholder before issuing a new request. |
| `chat_media_signed_url` | `ai-media-proxy` Edge Function (PRO only) — SSRF-allowlisted to `progress-photos` + `chat-attachments` Storage buckets only | `WardroomChatBubble` photo renderer. |

## Tool dispatch contract

When the agent emits a `tool_call`, the dispatcher MUST:

1. Validate the tool name against the kept allowlist (`logSet`, `logMealByText`,
   `createCustomExercise`, `createCustomTemplate`, `scheduleTemplate`,
   `swapExercise`, `shortenWorkout`, `generateHotelWorkout`, plus the 5 plan-edit
   tools `switchGoal` / `regeneratePlanBlock` / `rescheduleWeek` / `pausePlan` /
   `modifyWorkoutForInjury`, plus the read tools). The 4 derive-violating tools
   (`logPR`, `markWorkoutComplete`, `adjustCaloricTarget`, `prelog`) were
   **removed 2026-05-31** — the dispatcher has no case for them (defense-in-depth
   against a stale/replayed intent). See ADR-0012.
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

## Tests pinning the rules here

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
- `test/contracts/derive_only_tool_surface_test.dart` (registry = 20 tools, 4 removed absent, dispatcher has no removed cases, completion-derivation wired).
- `test/contracts/coach_derived_pr_and_completion_test.dart` (behavioral — PR derives from `logSet` via `loadAllExercisePRs`; coach `logSet` on a scheduled day → `completed`).
- `test/contracts/no_legacy_log_set_with_pr_rescan_declaration_test.dart` (legacy `logSetWithPrRescan` declaration stays deleted).

## See also

- `supabase/functions/CLAUDE.md` — `ai-proxy` + `ai-media-proxy` deploy + rate-limit triggers.
- `docs/architecture/ai.md` — model matrix + tools + triggers + semantic retrieval.
- `lib/features/nutrition/CLAUDE.md` — AI breakdown card lives in nutrition (cross-feature).
