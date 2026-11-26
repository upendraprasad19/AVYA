# Design — AI Coach UX & Tool-Integrity Batch

- **Date:** 2026-09-18
- **Branch:** `ai-coach-ux-tool-integrity`
- **Status:** approved (founder, 2026-09-18 brainstorm session)
- **Origin:** founder APK test2 session — three observations from chatting with the AI coach and tapping the Compass tools sheet
- **Blast-radius (expected):** `account` (streak/rank math, plan writes, Edge Function prompt) → ×2 plan review + B-pass before merge per CLAUDE.md §4.3/§4.12

## Problem statements

1. **Verbosity.** Chat replies are too long, especially after a photo upload. Root cause: `captainPrompt()`'s `chat` channel suffix is EMPTY (`supabase/functions/_shared/captain_manual.ts:426`) while `morning`/`weekly`/`proactive` all carry hard length caps. The manual's "briefing rhythm, short sentences" voice rule has no enforceable bound.
2. **Tool UX.** The Compass tools sheet (`lib/features/ai_coach/widgets/compass_tools_sheet.dart:36-63`) is a TEXT-PREFILL palette, not a flow. Tap `/SWAP` → composer fills with the literal string `Swap [exercise] for ` → user taps send → the model asks "I need the specific exercise IDs" (screenshot evidence, 2026-09-18). No user knows exercise IDs; the model is SUPPOSED to resolve names→IDs from its own snapshot (`swapExercise.ts:5-9`). `/LOG` prefills `Log my workout: ` → the model interrogates for "exercises, sets, reps" with no capture assist.
3. **Tool interference.** No audit had ever traced the 12 write tools against streak math, completion derivation, targets, plan-engine invariants and client staleness. Audit of 2026-09-18 (explore agent, verified against source) found 4 RISK + 3 GAP (table below).

## Founder decisions (locked in brainstorm)

| Decision | Choice |
|---|---|
| Scope | All three observations, ONE batch |
| Tool UX model | Native structured capture (never free-text interrogation) |
| Capture surface | In-coach bottom sheets (reuse existing patterns) |
| Verbosity fix | Prompt-side caps only (no client expander) |
| Paused-day × streak rule | **Paused = invisible** — never breaks, never burns a freeze |

## Part A — Verbosity (server-side, ai-proxy redeploy)

### A1. Chat channel suffix

Add a `chat` suffix in `captainPrompt()` (`supabase/functions/_shared/captain_manual.ts:424-439`):

- Default reply ≤100 words.
- Bullets over paragraphs; figures first, prose second.
- Media-analysis replies (photo in the turn) ≤60 words + at most ONE follow-up question.
- Never narrate what you are about to do; do the thing and report the result.

### A2. Anti-interrogation rules (same suffix)

These fix the screenshot failure mode:

- NEVER ask the user for exercise IDs, slot IDs, or any identifier the snapshot already carries. Resolve user-named exercises → IDs from `snapshot.today_workout.exercises[]` and `snapshot.custom_exercises` yourself.
- Ambiguous exercise name → offer 2-3 NAMED options in one short line ("Bench, Incline Bench, or Machine Press?").
- Required input genuinely missing → ask ONE short question. Never a checklist of demands ("specify exercises, sets, reps, and weights" is banned).
- If a request needs structured data the user would type slowly (a full workout), say what you need in one line and remind them the ⊕ Compass /LOG form does it in three taps.

### A3. Deploy + verification

- `deno check --node-modules-dir=none supabase/functions/ai-proxy/index.ts` before commit.
- Host-shell deploy (`node .claude/emit_payload.js ai-proxy --auto …` + `deploy_via_api.js`) — live deploy needs founder's explicit per-action go (§4.3).
- No client-side changes. `coach_replies` parity tests untouched (the manual is server-only, not mirrored to `copy/coach_replies.dart`).
- Spec-note: this section IS the Captain Manual amendment its header requires ("Do not edit ad-hoc — propose changes via spec amendment first").

## Part B — Compass redesign: text-prefill → structured capture (client)

The Compass sheet becomes a LAUNCHER for in-coach capture sheets. Nothing it launches sends placeholder text to the model.

### B1. Log-workout sheet (replaces `/LOG` prefill)

- Lists today's planned exercises (from the schedule row the snapshot builder already reads).
- Per exercise: sets/reps/weight entry with sensible defaults (previous log for that exercise, else plan prescription).
- Confirm → executes through the EXISTING dispatcher path — the same `_executeLogSet` internals (`tool_dispatcher.dart:287`), same `WorkoutWriteService`, same `_maybeCompleteScheduledDay` derivation. Zero Gemini tokens; deterministic; the derive-only surface (ADR-0012) is untouched because the app computes completion exactly as before.
- Sheets emit a coach-visible confirmation row in the chat thread (same rendering path as a tool confirmation card) so the transcript stays honest.

### B2. Swap sheet (replaces `/SWAP` prefill)

- Picker 1: today's exercises.
- Picker 2: substitutes from the exercise library, filtered by the existing equipment-capability guard (`swap_service.dart:253-273`).
- Confirm → existing swap preview card (reviewable confirmation class) → `_executeSwapExercise` path. The model NEVER needs to be involved.

### B3. Meal log (replaces `/LOG MEAL` prefill)

- Opens the existing AI-breakdown log surface (text meal description → same `logMealByText` canonical writer).

### B4. Removed and reformed chips

- **REMOVED:** `/PR` ("Log a PR") and `/TARGET` ("Adjust calorie target") — both advertise tools deleted 2026-05-31 by ADR-0012 (derive-only). They are dead-end conversations by construction.
- **REFORMED (conversational tools):** `/SHORTEN`, `/HOTEL`, `/INJURY`, `/PAUSE`, `/SWITCH`, `/SCHEDULE`, `/SHUFFLE`, `/PROGRESS`, `/HISTORY`, `/SUGGEST` keep one-line prefills, but any `[placeholder]` token renders as an UNFILLED FIELD — the send/confirm control is disabled while a placeholder remains, or the chip opens a light form (injury: body-part picker; pause: duration picker; switch: goal picker from `FitnessGoals` tokens). No `[exercise]`-shaped string can ever reach the model.

### B5. Visuals

- All sheets: Wardroom palette, DM Sans, existing `tool_confirm_sheet` / `AiBreakdownCard` patterns. No new colors.

## Part C — Audit fixes (all findings, same batch — no deferrals)

Audit evidence key: pausePlan writer `tool_dispatcher.dart:1026` → `workout_schedule_write_service.dart:130-172`; streak reader `workout_repository.dart:351` (`_calculateStreak`), `:440` (`completionRateOverWindow`).

| # | Finding | Fix | Test |
|---|---|---|---|
| C1 | **R1 (most severe): pausePlan breaks streaks.** Past paused days fall through to the missed-day arm of `_calculateStreak` (`workout_repository.dart:350-387`) — freeze burned (`:376-383`) or streak broken (`:384-387`). `completionRateOverWindow` (`:440-446`) counts paused as scheduled-not-completed, dragging the officer-track rank gate. No unpause writer exists anywhere in `lib/`. | **Paused = invisible (founder rule):** both readers skip `status=='paused'` rows entirely — never break, never burn a freeze, never count against rate. Document the rule in `docs/architecture/business-rules.md` (currently silent on pause × streak). | `test/contracts/streak_paused_day_not_missed_test.dart` (behavioral: paused past day neither breaks nor burns; active-day miss still breaks) + extend `streaks_writer_to_reader_test.dart` |
| C2 | **R2: rescheduleWeek raw-deletes the source row** (`tool_dispatcher.dart:710,719`) — a HOLE in the streak walk-back, which `_calculateStreak` treats as an unconditional break (`:343-347`) and freezes CANNOT protect (worse than a missed day). Partial logs stay orphaned under the old date. The delete never reaches cloud (OI-174 family). | Route source-row removal through the WriteService as a terminal `status` (not a row delete — no hole). The new status JOINS the C1 invisible set — `_calculateStreak` and `completionRateOverWindow` skip it exactly like `paused` (a status value unknown to the readers must never fall through to the missed arm again). Move partial `exlog_` rows with the day, add cloud delete fan-out. | behavioral: moved day keeps logs; walk-back sees terminal status, not a hole; cloud reflects the move |
| C3 | **R3: silent un-pause.** `generateHotelWorkout` (`tool_dispatcher.dart:774-788`), `scheduleTemplate` (`template_service.dart:131-142`), `regeneratePlanBlock` overwrite `paused` rows — they skip only `completed`. | Add the same paused guard completed has (skip paused rows; surface them in the preview so the user sees what was skipped). | per-tool test extensions |
| C4 | **GAP: staleness.** Coach meal log never invalidates `aiTextLogRemainingProvider` (`nutrition_provider.dart:1548`; manual path invalidates at `food_logger_section.dart:92`). `createCustomExercise` invalidates no picker provider. | Add both invalidations to the dispatcher's post-write tails. | writer→reader tests |
| C5 | **GAP: races + telemetry.** `coachBox['coach_memory']` read-modify-write with no mutex (`tool_dispatcher.dart:1530-1551`) — concurrent multi-intent confirmations can lose an injury append. pausePlan failure paths skip `ErrorTelemetry.logEvent` (unlike reschedule `:740`, hotel `:807`, regen `:1003`). ai_coach CLAUDE.md claims completion status re-check happens "under a lock"; the lock actually lives inside `markCompleted` (`workout_write_service.dart:424`) — doc drift. | Mutex the coach_memory RMW; add failure telemetry to pausePlan; fix the CLAUDE.md drift line. | source/behavioral pins |
| C6 | **R4 + UX: dead chips + placeholder prefills** (see B4). | Same change as B4. | widget tests: `/PR`+`/TARGET` absent; placeholder blocks send |

## Error handling

- Capture sheets follow the loading/error/empty rule (§4.4 rule 13): skeleton while reading today's plan, retry on read failure, empty state ("No workout scheduled today") for plan-less days.
- Sheet-execution failures surface the same `WriteResult` error mapping the dispatcher already returns — no new error vocabulary.

## Testing & verification

- Every fix lands with a behavioral regression test that FAILS without the fix; mutation-run each new test per §4.4 r21 (record what was mutated + red count in the diagnose-doc).
- Diagnose-docs per §4.4 r22 for C1/C2 (bug-class fixes); closure YAML only if the batch tracks ≥4 audit findings as a formal audit ledger — this spec's Part C table IS the finding ledger; terminal states recorded in the retrospective.
- `flutter analyze` + targeted `flutter test` during dev; pre-push (≥account) + CI run the full suite.
- New Deno test not required for A (prompt-text change); existing `tool-loop` tests must stay green; `deno check` is the compile gate.

## Sequencing (within the batch)

1. C1 → C2 → C3 (state integrity first — they touch the same files)
2. C4 → C5 (dispatcher tails + docs)
3. C6 + B4 (chip removal — small, ships with B's files)
4. A (EF redeploy last among server work; independent of client tests)
5. B1-B3, B5 (largest UI surface, depends on nothing above)
6. End-of-batch: ×2 plan review + B-pass, merge `--no-ff`, then founder-authorized live deploy of `ai-proxy`

## Explicitly out of scope

- No unpause writer (the invisible rule makes it unnecessary; revisit only if founder wants un-pausing).
- Client-side reply expander (chose prompt-side only).
- Cloud prune for previously-deleted schedule rows (OI-174, pre-existing, tracked on the board).
- New tools / capability changes to the model's tool surface (registry stays 19 write+read tools).
