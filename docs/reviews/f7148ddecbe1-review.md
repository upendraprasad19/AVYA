---
reviewed_at: 2026-10-21T22:05:00+05:30
staged_against: f7148ddecbe1
branch: train-coach-log-refresh
blast_radius: platform
reviewer: claude-sonnet-via-skill (1 fresh context-blind seat, read-only, exhaustive command list, mutants proposed not applied; self-initiated per CLAUDE.md 4.3)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 12
verdict: accepted
verdict_note: "0 P0 / 0 P1; 3 P2 + 9 P3, 0 false alarms. The review ran on staged fb5048e68fae (blast radius account); this file is named by the hash after its fixes were staged, per the 2026-10-20 precedent. F12a's new blast_radius.yaml rule raises the batch to platform. Fixes mutation-proven: 16 mutants, all red (docs/audit/train-coach-log-refresh.closure.yaml BPASS_fb5048e68fae). Two founder calls were decided 2026-10-21: keep the saved card as approved (F6) and keep the KEEP layout as built (F3); one pre-existing bug found by F10's test is filed separately (cardio duration zeroed by logExercise)."
---

# Code Review (B-pass) - train-coach-log-refresh, reviewed at `fb5048e68fae`, fixes staged at `f7148ddecbe1`

Scope: plan `docs/plans/train-coach-log-refresh.md` rev 11 (OI-370 / OI-371): B (one invalidation helper for the three
coach write paths), B' (the chat workout card's saved / partial / held states), C (readable Train rows).

The reviewer ran `flutter analyze --no-fatal-infos lib/` (60 infos, no warning or error) and the 8 permitted test files
(94 tests, all green), read every other test that could depend on the moved code, and proposed 10 mutants (PM1-PM10).

## Finding 1 - P2 - writer_reader_drift - FIXED
- **file:line:** `conversational_log_handler.dart` the refresh gated on `saved.isNotEmpty`
- **claim:** a retry that saves nothing new but newly marks the day (the mark failed on attempt 1) wrote
  `schedule_<date>.status` and `wlog_` and refreshed nothing, so Train stayed stale while the card dropped its day line.
- **fix:** `markedNow` from the mark result; refresh and `pushSnapshot` on `saved.isNotEmpty || markedNow`.
- **tests / mutants:** "a retry that saves nothing new but marks the day refreshes the workout surfaces" and its mirror
  "…saves nothing and marks nothing refreshes nothing" observe the real container (a `ProviderObserver` sees the
  invalidation dispose `lastPerformanceProvider('X')`, probed on riverpod 3.2.1); `bp_refresh_only_on_save` and
  `bp_refresh_always` red. (PM1 as proposed, `&& failed.isEmpty`, is now covered by the same case.)

## Finding 2 - P2 - guard_without_its_mirror - FIXED
- **file:line:** `test/contracts/workout_surface_invalidation_test.dart` completion-prompt pin; `screen.dart` handler
- **claim:** a whole-file `contains` survives a commented-out or moved call; no test mounts the handler.
- **fix:** the pin reads comment-stripped source and requires the call to be the first statement of the handler's
  `if (result.success)` branch, exactly once in the file. `AiCoachScreen` needs Firebase and Supabase singletons, so
  a behavioural mount stays out of reach; stated in the test.
- **mutant:** `bp_prompt_commented_out` (the reviewer's PM3) red.

## Finding 3 - P2 - guard_without_its_mirror - FIXED (property) + founder call (literal layout)
- **file:line:** `workout_log_confirm_card.dart` `_discardConfirmRow`
- **claim:** no test pinned where KEEP and DISCARD sit; the founder rule is that a quick double tap on DISCARD keeps.
- **measured while writing the test:** KEEP does NOT sit where DISCARD was. The question line above the confirm row
  pushes the row down (39 px at 1.0, 52 px at 1.5, 106 px at 2.0 on 320 dp), so the second tap lands on that inert line.
  The rule's purpose holds; its literal wording in the plan and the code comment did not.
- **fix:** a test at 1.0 / 1.5 / 2.0 records DISCARD's centre, taps DISCARD, asserts "Discard the rest" is not under
  that point, taps it, and asserts the card and its saved names survive. Comment and plan corrected to the measured
  layout. Mutant `bp_discard_rest_under_finger` (question line below, KEEP first) red at all three scales.
- **founder decision (2026-10-21):** keep the layout as built; the rule's purpose is what the test pins.

## Finding 4 - P3 - guard_without_its_mirror - FIXED
- **claim:** with a held card behind a partial one, a double tap on the wide left "Discard the rest" applies the held
  card and its second tap can land on that card's CONFIRM, logging a workout the user never saw.
- **fix:** a card applied from hold ignores CONFIRM for `kHeldCardTapGuard` (500 ms, real time via a `Stopwatch`).
- **test / mutants:** held draft "(f)"; `bp_tap_guard_removed` and `bp_tap_guard_every_card` red. The first run of
  `bp_tap_guard_removed` hung (an unguarded tap ran Hive I/O in fake time); the tap now goes through `tapWrite`
  (real time), so the mutant fails fast.

## Finding 5 - P3 - guard_without_its_mirror - FIXED
- **claim:** "already done" keyed on `schedule.status == completed` only, so a completed day with no `wlog_` (a restore
  whose workout_logs row is missing) never got one, unlike origin/main.
- **fix:** already done = status completed AND `wlog_<date>` is a Map (read as `swap_service.dart:161` does).
- **test / mutant:** "a completed status with no wlog_ still gets its wlog_"; `bp_wlog_check_dropped` red.

## Finding 6 - P3 - guard_without_its_mirror - FOUNDER DECIDED: keep as approved
- **claim:** after a partial save, a fully successful retry shows "Workout logged" with only the retried rows.
- **resolution:** not false; the founder kept the approved card (2026-10-21): Train shows the full day.

## Finding 7 - P3 - unawaited_no_error_sink - FIXED (tripwire)
- **fix:** "the draft notifier survives an auth rebuild" asserts the instance is identical across an auth flip and the
  state was reset. Presence-only (it pins a Riverpod behaviour, not our code).

## Finding 8 - P3 - writer_reader_drift - FIXED
- **fix:** the handler passes no `WidgetRef` to `logExercise` / `markCompleted` (it only fed the unwired
  `onInvalidate` hook). Comment-stripped pin: no `ref: ref` in the handler body; mutant `bp_ref_passed_again` red.

## Finding 9 - P3 - writer_reader_drift - FIXED
- **fix:** the helper's comment, plan §2 and `sync.md` now say `aiInsightProvider` follows `todayWorkoutProvider`
  (c7e3a9). The plan claimed `sync.md` and the unit test named the omission; neither did. Now the unit test asserts the
  omission and pins the `ref.watch(todayWorkoutProvider)` inside `AiInsightNotifier.build`; mutant `bp_aiinsight_reads`
  red.

## Finding 10 - P3 - asserted_fixture_value - FIXED (+ a pre-existing bug found)
- **fix:** the Train-screen test logs a timed (`Plank Hold`, 3 x 45 s) and a cardio (`Rowing Erg`) exercise and pins
  `3 sets · best 45s` and the cardio NBSP format. Mutants `bp_timed_breaking_sep` and `bp_cardio_breaking_space` red.
- **found:** the cardio row read `0 min` for 1200 s logged. `WorkoutWriteService._normalizeSetsByLoggingType` zeroes
  `durationSec` for every non-timed type, cardio included, and Active Workout captures cardio as duration only
  (`log_exercise_logic.dart:98`). Pre-existing on origin/main, outside this batch's writer: filed as a separate task
  (closure ledger `CARDIO_DURATION_ZEROED`, upstream_blocked); the test asserts the format, not the minutes.

## Finding 11 - P3 - asserted_fixture_value - FIXED
- **fix:** a haptic test mocks `SystemChannels.platform` (saved: one `lightImpact`; partial: none); the screen pin now
  requires `workoutDraftChangeScrolls(prev, next)`. Mutants `bp_haptic_removed`, `bp_haptic_every_change`,
  `bp_scroll_args_swapped` red. PM6 (a saved card re-submitting) is now asserted in "id guards, direct";
  `bp_saved_card_resubmits` red.

## Finding 12 - P3 - docs hygiene - FIXED
- **12a:** `docs/blast_radius.yaml` pins `workout_surface_invalidation.dart` at account (exact path, above
  `lib/features/train/**`), with `test/contracts/blast_radius_workout_surface_invalidation_test.dart`; mutant
  `bp_blast_rule_removed` red. The rule makes this batch platform tier.
- **12b:** the registry range is `screen.dart:479-486`; the three handler ranges re-checked after the new import.
- **12c:** `activeFinishMoreTemplate` cited at `wardroom_copy.dart:239`.
- **12d:** the wardroom palette block now matches `colors.dart:99/106/110` for textPrimary, textMute, textGhost.
- **12e:** OI-370/371/376-382 entries arrive with `observations-a12-web`, which merges first (the release order).

## What the reviewer checked that returned clean
Lens 1: every Hive write vs every Train reader; IST keys; the dispatcher's set unchanged plus `lastPerformanceProvider`;
removed draft fields have no readers. Lens 2: no `.functions.invoke(`. Lens 3: nested CLAUDE.md edits do not match the
anchored root rule. Lens 4: no credentials. Lens 5: every async gap in `submitWorkoutDraft`, the notifier timer, the
card's post-frame callback. Lens 6: held draft, `!wasCompletedBefore`, partial day mark, auth flip (a token refresh to an
equal value notifies nothing), unmount, the edit sheet, the formatter. Lens 7: helpers, NBSP bytes. Lens 8: every copy
string, the NBSP strings, the 43-case count, the formatter table.

## Founder triage notes
All code and test findings fixed in this batch. The founder decided F6 (keep the saved card) and F3 (keep the layout)
on 2026-10-21. The cardio-duration bug is pre-existing and filed separately.
