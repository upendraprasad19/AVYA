---
reviewed_at: 2026-11-16T17:30:00+05:30
staged_against: 7dabae87c09e1fd58d4b1c00a098ca1eaa031f03
branch: generator-step3c
blast_radius: platform
reviewer: claude-sonnet-via-skill (2 fresh seats)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 13
verdict: accepted
verdict_note: self-triaged under the standing directive; 0 P0/P1, 5 P2 and 8 P3; 12 fixed in the B-pass commit, 1 kept as intended (A F4), none a false alarm
---

# B-pass: generator-step3c (Unit 3C, the cardio finisher shown, injury-safe and timed, OI-396)

This is the self-initiated ≥account B-pass (§4.3). It ran on the committed head 7dabae87, with CI green on that SHA
(PR #288). Two fresh Sonnet seats read the three-dot diff `origin/main...7dabae87`:
- **Seat A, the engine, the reservation, the read rule and the minutes readers:** `cardio_finisher`, `plan_generator`
  (the waived lines), `session_budget`, `session_estimate`, `session_set_allocator`, `finisher_safety`,
  `finisher_show_context`, `train_provider`, `home_screen`.
- **Seat B, the coach, the display surfaces and the writers:** `tool_dispatcher`, `coach_injury_profile`,
  `injury_vocab`, the confirm card and sheet, the diff preview, the active workout, Train's expansion and preview
  sheet, `swap_service`, `workout_schedule_read_service`, `hotel_workout_planner`.

Both briefs quoted the founder decisions d56, d61, d74-d79 and the rejected alternatives of plan rounds 1-6. No
finding re-opened a decision. Every new guard below was mutated once after its fix (M16-M21 in diagnose `f3c9a6`, each
red, each file restored with an equal sha256).

## Finding A1 - P2 - guard_without_its_mirror - no profile read as uninjured
- **file:line:** `lib/shared/repositories/plan_engine/finisher_show_context.dart` (`read`)
- **claim:** a read failure fails closed to injured, but its mirror, a device with no profile yet (before its restore),
  read `isInjured(null)` = false and could show the HIIT to an injured user.
- **fix:** `injured: profile == null || ...`; test "no profile yet ... is read as injured" with its mirror (a profile
  with `injuries: null` shows the HIIT). Mutant M18 red.
- **status:** fixed

## Finding A2 - P2 - asserted_fixture_value - the 2-day and 5-day finisher days untested
- **file:line:** `lib/shared/repositories/plan_engine/cardio_finisher.dart` (`_pickFinisherDays`)
- **claim:** mutants on the 2-day `{0, 1}` and 5-day `{0, 3}` branches survived.
- **fix:** "the finisher days per day count" pins 2 to 6 days on `days` and `secondsByDay.keys`. M19, M20 red.
- **status:** fixed

## Finding A3 - P3 - writer_reader_drift - home CLAUDE.md cites `homeCardMinutes(schedule)`
- **status:** fixed (now `homeCardMinutes(schedule, finisher:)` plus the finisher's share).

## Finding A4 - P3 - guard_without_its_mirror - `shortenDay` removes the key with the switch set
- **claim:** with `disable_cardio_finisher_shown` set, `shortenDay` still removes the stored `finisher` key.
- **status:** kept, intended: the user asked for a shorter day, and once the switch is deleted (OI-516) the kept key
  would bring the finisher back over that target. Recorded in diagnose `f3c9a6`.

## Finding A5 - P3 - writer_reader_drift - a fourth schedule writer unnamed
- **claim:** `regenerate_plan_planner.dart:373` writes `finisher` too; the docs named three writers.
- **status:** fixed (train CLAUDE.md row, diagnose writers list).

## Finding A6 - P3 - wording - the attach doc comment did not name the day sets
- **status:** fixed.

## Finding B1 - P2 - missing_input - the injury line is unreachable
- **file:line:** `lib/features/ai_coach/widgets/tool_confirm_sheet.dart` (`_confirm`)
- **claim:** `modify_workout_for_injury` is destructive, so `chat_area.dart:146` sends it to `ToolConfirmSheet`, whose
  confirm dropped `result.data`; the `Knee added to your injuries` line lived only on `ToolConfirmCard`.
- **fix:** on a success with `profileInjuryAdded(result) != null` the sheet shows `executedMessageFor(...)` after it
  closes (messenger captured before the pop). `test/ai_coach/tool_confirm_sheet_injury_line_test.dart` (3). M16 red.
- **status:** fixed

## Finding B2 - P2 - guard_without_its_mirror - the owner captured at the handler start was not pinned
- **file:line:** `lib/features/ai_coach/services/tool_dispatcher.dart` (`_executeModifyWorkoutForInjury`)
- **claim:** the test called the save seam with a stale owner; moving the capture below the swap loop stayed green.
- **fix:** seam `debugAfterInjurySwapLoop`; the test opens another user there and sees no write and no lock on either
  account. M17 (owner read at write time) red.
- **status:** fixed

## Finding B3 - P2 - missing_input - the preview sheet's FINISHER section untested
- **file:line:** `lib/features/train/screens/train/exercise_preview_sheet.dart:314-326`
- **fix:** a widget test opens another day of the week from the real Train screen and checks the section, `9 MIN`, the
  order above COOL-DOWN and the rows. M21 red.
- **status:** fixed

## Finding B4 - P3 - unawaited_no_error_sink - the injuries lock failure was debugPrint only
- **status:** fixed (`ErrorTelemetry.logEvent('tool_dispatch_coach_injury_lock_unfinished')`).

## Finding B5 - P3 - function_exception_swallow - two silent catches
- **claim:** `FinisherShowContextReader.read` and `coachInjuryTokenToAdd` caught with `catch (_)`.
- **status:** fixed (`recordNonFatal`; the context read reports once per process, it runs on every build).

## Finding B6 - P3 - wording - grammar and doc nits
- **claim:** `1 finisher exercises included`; three naming rows had 2 cells, not 3; diagnose `ist_handling` pointed at
  a comment line.
- **status:** fixed.

## Finding B7 - P3 - process - plan-review record `bpass: pending`
- **status:** fixed (`bpass: accepted` in the B-pass commit).

## Founder triage notes
Self-triaged under the founder's standing directive (finish the board without stopping). No finding changes a
founder decision.

## Tuning entry

- **2026-11-16** - blast-radius platform - 13 findings (0 P0/P1, 5 P2, 8 P3); 0 false_alarm; tuning: one lesson.
  - A result field a widget renders must be traced to the widget the intent's CONFIRMATION CLASS routes to
    (`chat_area.dart` sends destructive intents to `ToolConfirmSheet`, not `ToolConfirmCard`). The plan's six rounds
    and the author's tests all exercised the card, so the line was unreachable in the app. Seat briefs for a coach
    result change now name the routing file.
