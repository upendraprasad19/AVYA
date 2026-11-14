---
reviewed_at: 2026-11-11T16:30:00+05:30
staged_against: c81d1041 (branch coach-workout-parity-1c, staged diff, 23 files)
blast_radius: account
reviewer: claude-sonnet-via-skill (two fresh context-blind seats, S1 and S2)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 4
verdict: accepted
verdict_note: no P0 or P1; four P2, each fixed with a mutation-proven test (one product fix in the card); one seat mutant recorded as equivalent with its reason.
---

# Code Review: coach workout parity 1c (OI-491)

Scope: Active Workout opens an exercise the AI coach already logged today as DONE (LOGGED IN CHAT). RE-OPEN adds rows after the coach's sets, and FINISH saves only the new rows, appended to the coach's `exlog_` row. KEEP AS LOGGED undoes a re-open while no row is checked. A sticky Hive-local `coach_logged` marker is carried by `logExercise`, the `moveExerciseLogs` collision and the `ExlogKeyMigrator` group merge, and is never pushed. The header and FINISH counts include the coach's sets, and `finishBlockedLine` picks one of three FINISH lines over the live list. Plan: `docs/plans/coach-workout-parity-1c.md` (rev 7, six review rounds).

Each seat got the staged diff, the 8 lenses, an exhaustive command list (read-only git, file reads, named test files, `dart analyze` per staged file, mutation of its own slice's `lib/` files under a backup / sha256 restore protocol) and a ban on scripts, the `supabase` CLI, network tools and any database statement. S1 covered state, writers and derived reads: `train_provider.dart`, `chat_logged_exercises.dart`, `coach_day_completion.dart`, `log_exercise_logic.dart`, `workout_write_service.dart`, `exlog_key_migrator.dart` and `workout_read_service.dart`. S2 covered the UI, copy, screen wiring and test quality: `exercise_card.dart`, `finish_dialog.dart`, `screen.dart` and `wardroom_copy.dart`.

Before dispatch, the gate loop was green:
- whole-project `flutter analyze --no-fatal-infos`: 0 warnings;
- full Flutter suite (`TZ=Asia/Kolkata`, golden excluded): 14,049 passed, 15 skipped, exit 0;
- pre-commit loop: green;
- 72 author mutants: all red.

Both seats ended with `git status --porcelain` showing only staged entries, and every mutated file's sha256 matched its backup.

## Finding 1 — P2 — guard_without_its_mirror (S1)
- **file:line:** `lib/features/train/providers/train_provider.dart:1487-1488` (`hasCheckedRow`)
- **claim:** The trailing hyphen in `startsWith('$index-')` is what stops index 1 from matching the keys of exercises 10 and 11. The mutant `startsWith('$index')` left every test green, so a day of 11 or more exercises could hide KEEP AS LOGGED, and `keepChatLogged` could refuse, on the wrong exercise. The code was correct; the shared predicate was unpinned.
- **fix:** new T5 case: 12 exercises, checked rows only on 10 and 11. It asserts `hasCheckedRow(s, 1)` is false, rows 10 and 11 read true, and `keepChatLogged(1, 'E1')` succeeds.
- **mutation:** MB1 (hyphen dropped): the new case goes red (1 of 77).
- **status:** fixed

## Finding 2 — P2 — guard_without_its_mirror (S2)
- **file:line:** `lib/features/train/screens/active_workout/screen.dart:268-269` (the `reopenChatLogged:` argument) and `:692-696` (the `onKeepChatLogged` closure)
- **claim:** No test touched the real screen wiring of the two callbacks. The card harness re-implements both closures, so dropping either one left all 104 tests green. Plan C9's "focus skips the chat card" screen test was also missing.
- **fix:** new screen test. On the real `ActiveWorkoutScreen` it taps LOGGED IN CHAT (re-opened, 2 rows), taps KEEP AS LOGGED (done, `sets` back to 3), waits out the real re-open guard and re-opens again. New screen test "focus skips a chat-done card": with a chat-done card first, the expanded card is the plain one (3 rows).
- **mutation:** MB2 (argument removed) and MB3 (`onKeepChatLogged` null) turn the real-screen test red. MB7 (`isExerciseDone` without the chat early return) turns both new screen tests red.
- **status:** fixed

## Finding 3 — P2 — guard_without_its_mirror (S2)
- **file:line:** `lib/features/train/screens/active_workout/exercise_card.dart` `_chatEntryIn` (`_logMode` guard), and the `weighted_bodyweight` meta branch
- **claim:**
  - (a) No test put a chat entry into a flag-OFF (per-set) card, so dropping the `_logMode` guard stayed green.
  - (b) No test covered the `weighted_bodyweight` meta text.
- **fix:**
  - (a) New flag-OFF card test with a chat entry in state: no LOGGED IN CHAT, no KEEP, no chips, 3 per-set rows.
  - (b) `weighted_bodyweight` was added to the re-opened meta-text cases.
- **mutation:**
  - MB4 (`_chatEntryIn` ignores `_logMode`): the flag-OFF test goes red.
  - MB5 (a split `weighted_bodyweight` case in `_metaTextForLogMode` reading `widget.exercise.sets`): the new meta case goes red.
- **equivalent mutant (recorded):** the seat's mutant D edits `_metaText`'s `weighted_bodyweight` branch to read `widget.exercise.sets`. It cannot change output.
  - In LOG mode, `_metaTextForLogMode` handles `weighted_bodyweight` itself and never calls that branch.
  - In per-set mode `_chatEntryIn` is null, so `_metaSets()` already equals `widget.exercise.sets`.
  - MB5 is the reachable form of the same regression.
- **status:** fixed

## Finding 4 — P2 — writer_reader_drift (S2)
- **file:line:** `train_provider.dart` `keepChatLogged` (clears the index's `setInputValues` and `suggestedInputs`), read by `exercise_card.dart` `_initControllers` (first-init marks) and `didUpdateWidget` (shrink / append).
- **claim:** KEEP cleared the provider's captured values and suggested marks, but the card kept its controllers, so the fields still held their text. On a second re-open, row 0 showed prefill as if typed (no faded mark, no PREFILLED), and the provider held no values for it. The coordinator traced the consequence further.
  - LOG captures the controllers before logging (`_onLogPressed`), so no wrong set could be saved.
  - The divergence was real for typed text, though: a value typed on the first re-open stayed on screen after KEEP while the provider no longer had it, so the typed-unsaved FINISH check could not see it.
  - The clearing (plan B5-F7) was right about the provider. It was wrong to assume the card would follow.
- **fix (product, card only):** `didUpdateWidget` detects the re-opened-to-done transition (`_chatKeptBack`: chat entry present, the name was in `reopenedExercises` and no longer is, same exercise). It disposes the controllers and runs `_initControllers` again, as the swap path does. KEEP already cleared the index's captures, so every row is a first init: prefill, then one `recordCardEdit` with values and marks. A later re-open then starts exactly like the first one.
- **test:** the real-screen test (Finding 2) asserts that, after KEEP and a second re-open, `setInputValues['0-0']` is captured and a `0-0-*` suggested mark exists.
- **mutation:** MB6 (the transition check forced false): the real-screen test goes red.
- **status:** fixed

## Extra mutants (S1's "not run" list, run by the coordinator)
| id | edit | red |
|---|---|---|
| MX1 | `workingSetCounts`: drop the `continue` after a chat-done exercise | 3 (T4 counts, T5 empty-per-set case, screen header) |
| MX2 | `finishGuard`: `!data.isChatLogged(i)` replaced by `true` | 1 (T4 finishGuard chat cases) |
| MX3 | `_chatLoggedSnapshot`: the plan-date equality guard replaced by `true` | 1 (T2 past-dated day) |

Each S1 "not run" item that is not in this table was already in the author's run: the `keepChatLogged` clearing (M45), the `swapExercise` outgoing-planned check (M19), the marker clauses (M10a-c, M35, M36, M41) and `coachCount = sets.length` (M31).

All 10 coordinator mutants (MB1-MB7, MX1-MX3) were confirmed applied, ran without a compile error, and were restored with a matching sha256. The log is in the session scratchpad (`1c_mut_bpass.log`).

## Clean lenses (both seats)
- **function_exception_swallow:** no `functions.invoke` in the diff.
- **secrets_in_tree:** none.
- **unawaited_no_error_sink:** `ErrorTelemetry.logEvent` never throws, and the re-open announcement uses the existing `unawaited(sendAnnouncement)`.
- **blast_radius_mismatch:** `account`, client only, with a Hive-local field and no schema or EF.
- **missing_input:** `rawScheduleRow`, `plannedExercisesOf` and `exerciseLogRow` exist with the assumed shape.
- **Copy:** the five strings match plan C8 character for character.
- **Persistence:** `ActiveWorkoutData` is not persisted, so a killed app re-snapshots at START.
- **Marker writers:** the seat enumerated every one and found no new way to lose or gain the marker beyond the accepted residuals R6 and R9.
- **`loggedNameForPlannedExercise`:** byte-identical to the old count for every input shape.

## Founder triage notes
None needed: no P0 or P1, and every P2 is fixed in this batch.

## Tuning entry
- **2026-11-11** - blast-radius account - 4 findings; 0 false_alarm; tuning: none. Two repeated shapes. First, a test harness that re-implements the production closures (`card_harness.dart`) hides the real screen wiring, so a seam the screen owns needs one test on the real screen. Second, a state clear in a notifier is only half a fix when a widget keeps its own copy of that state (controllers). Follow every cleared field to each widget that caches it (lens 1 writer/reader, across the provider/widget boundary).
