---
bug_id: 24e630
date: 2026-11-10
batch: coach-workout-parity
status: fixed
blast_radius: account
symptom: >-
  OI-490: the chat workout card marked the day completed on ANY save: a partial day (2 of 5 planned exercises), a rest
  day, a moved or dropped day, and a day with no plan row at all. Since 1a (0ebfcb) every such mark also counted a
  workout, and the count is monotonic (restore max-wins, push GREATEST), so an over-count is permanent. The typed
  backstop marked a day dated in the FUTURE once every planned exercise was logged. Train showed nothing for a day
  logged through the coach until it was marked done (no "logged so far", no way to finish it from Train), a counted
  rest-type row still read as REST, and a past "X of Y" tile kept offering a Complete tap.
concept: coach_day_completion_rule
sot_registry_entry: coach_day_completion_rule
writers:
  - file: lib/features/train/services/coach_day_completion.dart
    method: decideCoachDay (the ONE pure coach-day rule, fed the RAW row)
    line: 61
  - file: lib/features/train/services/coach_day_completion.dart
    method: CoachDayCompletion.completeOnTap (the ONE tap path; tile door coachTap, Train door trainTap)
    line: 210
  - file: lib/features/ai_coach/services/conversational_log_handler.dart
    method: submitWorkoutDraft day decision (mark only on completeNow / repairDone; prompt on askToComplete today)
    line: 460
  - file: lib/features/ai_coach/services/tool_dispatcher.dart
    method: _maybeCompleteScheduledDay (backstop, now on decideCoachDay)
    line: 437
  - file: lib/core/services/completion_prompt_store.dart
    method: CompletionPromptStore.write / resolve (the one owner of completion_prompt_<date>)
    line: 32
readers:
  - file: lib/core/services/workout_schedule_read_service.dart
    method_or_widget: rawScheduleRow (no terminal filter, no completed-past demotion)
    line: 999
  - file: lib/features/train/services/coach_day_completion.dart
    method_or_widget: canCompleteOnTap (Train's COMPLETE WORKOUT gate; same rule as the tap)
    line: 178
  - file: lib/features/train/screens/train/week_rows.dart
    method_or_widget: _buildCompactRow (IN PROGRESS / LOGGED chips; counted rest-type row is DONE)
    line: 125
  - file: lib/features/train/screens/train/planned_expansion.dart
    method_or_widget: _buildPlannedExpansion (LOGGED SO FAR + COMPLETE WORKOUT)
    line: 6
  - file: lib/features/train/screens/train/exercise_preview_sheet.dart
    method_or_widget: not-done day's logs above its plan
    line: 30
  - file: lib/features/ai_coach/providers/ai_coach_provider.dart
    method_or_widget: ChatHistoryNotifier.build (past-dated prompt filtered, pure read)
    line: 200
  - file: lib/features/ai_coach/widgets/workout_log_confirm_card.dart
    method_or_widget: awaitingCompleteLine / savedNotCounted line
    line: 51
hive_key_prefix: schedule_
hive_key_formula: "workoutBox['schedule_<yyyy-MM-dd IST>'] status/type/exercises[]; workoutBox['exlog_<date>_<uuid5 8 hex>']; workoutBox['wlog_<date>']; coachBox['completion_prompt_<date>'] (local only)"
sync_methods:
  - WorkoutWriteService.markCompleted -> scheduled_workouts.status + workout_logs
restore_methods:
  - sync_workout restore (unchanged; the prompt row is local-only and never restored)
cloud_table: scheduled_workouts
cloud_columns: [status, completed_at]
contract_test_path: test/contracts/coach_day_completion_behavioral_test.dart
ist_handling:
  - decideCoachDay compares IST yyyy-MM-dd strings (dateStr vs istTodayStr()); future = dateStr > today
  - completeOnTap refuses any date that is not istTodayStr(); utcDateFromIstDateStr round-trips on any host zone
  - the chat build filter compares the prompt's date with istTodayStr()
provider_invalidations:
  - invalidateWorkoutSurfaces (source chat_draft, completion_prompt, train_complete)
  - chatHistoryProvider.refreshFromHive after a card prompt write or resolve
telemetry_op_types:
  success: []
  failure:
    - coach_day_complete_on_tap
    - chat_card_owner_changed
    - derived_completion_owner_changed
    - tool_dispatch_derived_completion_failed
cross_account_guard: true
forbidden_patterns_checked:
  - getScheduleForDate as a decision input (terminal rows read as absent; completed past rows demoted)
proposed_fix: >-
  Coach workout parity slice 1b (plan docs/plans/coach-workout-parity-1b.md rev 4, three review rounds): ONE pure rule
  decideCoachDay over the RAW schedule row (future, noPlan, alreadyDone, repairDone, terminal, rest, completeNow,
  askToComplete), shared by the chat card, the typed backstop, the tile tap and Train's Complete button. The card marks
  only on completeNow (with the plan day's name) or repairDone; a partial day today writes the "X of Y" tile (shown at
  once) and the card says how many are saved; a partial past day stays not done; rest, moved, dropped and no-plan days
  are saved but not counted, with their own line. The tap path CoachDayCompletion.completeOnTap is today-only and
  refuses rest / terminal / no-plan / no-log days. Train shows IN PROGRESS, LOGGED SO FAR and COMPLETE WORKOUT on
  today's partial row (hidden while an Active Workout session for today is in progress), a counted rest-type row as
  DONE, a not-done rest row's logs as LOGGED, and a past not-done day's logs in its sheet. Owner guards before the
  decision in the card and the backstop. A past prompt is filtered in the chat build (pure) and resolved by the next
  write's sweep.
regression_test_planned:
  - test/contracts/coach_day_completion_behavioral_test.dart
  - test/contracts/train_logged_so_far_behavioral_test.dart
  - test/ai_coach/workout_log_confirm_card_saved_signal_test.dart
  - test/contracts/coach_completion_counts_behavioral_test.dart
  - test/contracts/coach_day_completion_rule_writer_to_reader_test.dart
related_bugs:
  - 0ebfcb  # 1a: every completion door counts through one shared step (made an over-mark a permanent over-count)
  - 280c4d  # Unit 1: the all-logged backstop + tap tile (the rule the card now shares)
  - e8f4a3  # terminal (moved / dropped) rows must never be re-marked
recurrence: |
  Writer drift between two writers of the same field: the typed backstop (280c4d) completed a day only when every
  planned exercise was logged, while the chat card (OI-370) completed it on any save. Each door carried its own copy of
  the rule, so they diverged. Same class as 280c4d (one coach log completing a whole day). The fix applies the known
  good shape: one pure decision function, fed the raw row, that every door calls.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "decideCoachDay + completeOnTap shared by four doors (conversational_log_handler.dart:454, tool_dispatcher.dart:461, ai_coach_provider.dart:379, planned_expansion.dart _CompleteTodayButton); 44 rule/door tests + 12 Train widget tests; mutation table below." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "Behavioural tests on real Hive read schedule_/exlog_/wlog_ rows and coachBox completion_prompt_ rows after each door; rest/moved/dropped rows keep their status, no row is synthesised for a no-plan day." }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "No schema change. scheduled_workouts has no completed_via column (backups/live_schema_columns.json: id, user_id, template_id, scheduled_date, week_number, day_of_week, status, completed_at, created_at); completed_via, including the new 'train_tap', is a local Hive stamp that no code branches on (grep of lib/ and supabase/functions/)." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "Pre-launch, testers only (CLAUDE.md §1). No data repair: a day the old card over-marked stays marked." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function change in 1b. The server-side 'I'm done' path is OI-492, with its own deploy go." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron touched." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy touched; markCompleted's existing sync path." }
  - { tier: 9, name: storage_buckets_and_objects, status: not_applicable, evidence: "No storage." }
  - { tier: 10, name: secrets_and_api_keys, status: not_applicable, evidence: "No secret." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service." }
  - { tier: 12, name: client_to_server_contract, status: verified, evidence: "Only markCompleted writes the cloud row (unchanged path); the prompt row stays local. The snapshot's today_workout_completion uses the same loggedPlannedExerciseCount, so the coach's 'X of Y' matches the card and Train." }
impact_analysis: >-
  A chat-logged partial day no longer counts as a workout; it shows as IN PROGRESS on Train with its logs and a
  COMPLETE WORKOUT button, and the coach tile offers the same tap. A day where every planned exercise is logged
  completes from any door, once. Rest, moved, dropped and no-plan days never count from the coach paths (Active Workout
  from a template on a rest row still does, unchanged). A past partial day stays not done. A completed rest-type row
  shows as DONE on Train.
---

# The chat card marks days the rule says are not done (24e630)

## Root cause
`submitWorkoutDraft` (`conversational_log_handler.dart`) called `markCompleted` whenever any exercise from the card
saved, regardless of the schedule row. The typed backstop (`ToolDispatcher._maybeCompleteScheduledDay`) had its own
copy of the all-logged rule, and the tile tap a third check. With 1a counting every first mark, the card's rule became
a permanent over-count on partial, rest, moved, dropped and no-plan days. The backstop also had no future-date branch.

## Fix
- `decideCoachDay` (`lib/features/train/services/coach_day_completion.dart`): the one pure rule, in this order:
  future, noPlan, completed (alreadyDone / repairDone), terminal, rest (`type == 'rest'`), completeNow (planned > 0 and
  every planned exercise logged, swap-tolerant), else askToComplete. Fed `WorkoutScheduleReadService.rawScheduleRow`,
  never the display read (which hides moved/dropped rows and demotes completed past rows).
- The card, the backstop, the tile and Train all call it. The card's owner guard comes before the decision
  (`chat_card_owner_changed`), the backstop's likewise (`derived_completion_owner_changed`).
- `CoachDayCompletion.completeOnTap`: the one tap path (doors `coachTap` and `trainTap`, `completed_via` 'tap' and
  'train_tap'), today-only, refusing rest / terminal / no-plan / no-log days with a `CoachTapResult` and one line per
  result.
- `CompletionPromptStore` owns `completion_prompt_<date>`; a write resolves older unresolved rows; the chat build only
  filters past prompts.
- Train: IN PROGRESS chip, LOGGED SO FAR, COMPLETE WORKOUT (gate `canCompleteOnTap`, hidden during today's in-progress
  Active Workout session), counted rest-type row as DONE, LOGGED chip on a not-done rest row with logs, logs in a past
  not-done day's sheet.

## Mutation evidence (rule 21)
Run by a script (`run1b.py` in the session scratchpad) that applied each mutation by exact text (count checked),
ran the named test files under `TZ=Asia/Kolkata`, restored the file and compared it with `cmp`. Files: R =
`coach_day_completion_behavioral_test.dart`, T = `train_logged_so_far_behavioral_test.dart`, S =
`workout_log_confirm_card_saved_signal_test.dart`, P = `coach_completion_prompt_test.dart`, C =
`coach_completion_counts_behavioral_test.dart`. Every one of the 41 files was restored byte-identical, and `lib/` was
compared with a snapshot taken before the run.

| mutation | red (first run) | red (after the added tests) |
|---|---|---|
| R01 card marks on any save (old rule) | R 10; S 4 | — |
| R02 completeNow without plannedCount > 0 | R 1 | — |
| R03 future branch removed | R 2 | — |
| R04a tap fed the display read | **0 (survivor)** | R 1 |
| R04b card fed the display read | **0 (survivor)** | R 1 |
| R04c backstop fed the display read | **0 (survivor)** | R 1 |
| R05 tap terminal guard removed | R 2 | — |
| R06 tap rest guard removed | R 1 | — |
| R06b tap no-plan guard removed | R 1 | — |
| R07 tap no-log guard removed | R 1 | — |
| R08 tap today-only guard removed | R 1 | — |
| R09 plan name replaced by kChatWorkoutName | R 1 | — |
| R10 no refreshFromHive after the card prompt write | **0 (survivor)** | R 1 |
| R11 savedAwaitingComplete dropped from isSavedDraftStatus | R 1 | — |
| R12 hasNote false for awaiting | R 1 | — |
| R13 status ladder isRest first | T 1 | — |
| R14 onTap isRest first | T 1 | — |
| R15 canCompleteOnTap today gate inverted | R 1; T 5 | — |
| R16 preview sheet not-done logs hidden | **0 (survivor)** | T 1 |
| R17 swapped_from read dropped | R 1; P 1 | — |
| R18 trainTap mapped to tap | R 1; T 1 | — |
| R19 in-progress session hide removed | T 1 | — |
| R20 in-progress hide date check removed | T 5 | — |
| R20b in-progress hide null-date treated as today | T 1 | — |
| R21 button gate askToComplete only | T 1 | — |
| R22 Hive write in the build past-prompt filter | R 2 (file timed out after the reds) | — |
| R23 pastNotMarked mapped to awaitingComplete | R 1 | — |
| R24 card owner guard removed | C 2 | — |
| R25 backstop owner guard removed | R 1 | — |
| R26 store write sweep removed | R 1 | — |
| R27 build past-prompt filter removed | R 1 | — |
| R28 backstop prompt on a past date | R 1 | — |
| R29 rule rest branch removed | R 3 | — |
| R30 rule terminal branch removed | R 5 | — |
| R31 IN PROGRESS chip label dropped | T 2 | — |
| R32 logged rest row tap opens the rest sheet | T 1 | — |
| R33 tap message: no-logs shows the failed line | R 1 | — |
| R34 Complete button no longer scales down | **0 (survivor)** | T 1 |
| R35 awaiting line count-free branch dropped | R 1 | — |
| R36 counted rest row named Rest | T 1 | — |
| R37 card repairDone not re-marked | R 1 | — |

**Survivors of the first run, and what each exposed.**
- **R04a/b/c (the decision fed the display read).** On a moved or dropped row the display read gives null, and
  `noPlan` and `terminal` lead to the same outcome at every door, so those cases cannot tell the reads apart. The case
  that does is a row completed EARLY (`completed_at` before its date), which the display read demotes to `planned`.
  Three tests added (backstop, card, tap); each now reddens its own mutant.
- **R10 (no chat refresh after the card's prompt write).** The partial test read `chatHistoryProvider` for the first
  time after the submit, so a first build showed the tile anyway. The test now builds the thread before the submit, as
  the open chat screen has it.
- **R16 (the sheet's not-done logs hidden).** The assertions matched the week list's LOGGED chip and the planned Pull
  Up row. They are now scoped to the sheet (heading, one `ExpandedExerciseLogRow`, the PLANNED EXERCISES label).
- **R34 (the Complete button no longer scales down).** At 360 dp and text scale 1.0 the label fits, so scaling is a
  no-op there. A 360 dp, text scale 2.0 case added; it reddens.

**Equivalence noted, not hidden.** R21 survives in R (no rule test has a `completeNow` day that is still unmarked) and
reddens in T (the Train case for exactly that day). R22's file hit the 400 s timeout after its two reds (a Hive write
during the key iteration); the reds are real.

**The Gate 9 writer→reader test** (`coach_day_completion_rule_writer_to_reader_test.dart`, 3 tests, added when the
pre-commit loop asked for it) was mutated by hand, one mutant at a time, each restored and checked with `cmp`: the tap
stamping `'tap'` for the Train door (1 red), the rest guard removed from `decideCoachDay` (1 red), and
`CompletionPromptStore.write` no longer resolving older rows (1 red).

## B-pass fixes (2026-11-10, `docs/reviews/coach-workout-parity-bpass.md`)
Three context-blind Sonnet seats reviewed `ea37ed59..ca96e754` (1a + 1b). Fixed in this batch:
- **The prompt resolve moved into `afterCompletion`** (seat A F1, F3, F4). Writers: the backstop resolved
  `completion_prompt_<date>` even after a FAILED mark (`tool_dispatcher.dart`, the `completeNow` branch), the card and
  the tap resolved it after awaits with no owner re-check, and Active Workout never resolved it. Reader:
  `ChatHistoryNotifier.build` (`ai_coach_provider.dart:193`). Now step 0b of `afterCompletion` resolves it, after a
  successful mark only and owner-checked; a tap refusal still resolves it in `completeOnTap`.
- **The card's decision block is guarded** (seat A F2): a throw from the decision to the last write maps to
  `markFailed` (or `completed` when the day was already marked), reported as `chat_card_day_decision_failed`.
- **The backstop names the day by the parsed date** (seat A F6): `istDateStr(date)`, not the payload string; a
  mismatch logs `derived_completion_date_normalised`.
- **`markCompleted` keeps a stored duration** when a 0 s mark (tap, backstop) follows a timed one (seat A F5).
- **Train** (seat C F1, F5, F6): the provider container is captured before the tap's await, so a row collapsed
  mid-tap still refreshes every surface; LOGGED SO FAR and COMPLETE WORKOUT show only when the rows list is not
  empty (the rows read the index, then the stamped date; the key scan alone could disagree).
- **Blast radius** (seat C F2): `coach_day_completion.dart` and `workout_completion_bookkeeping.dart` pinned at
  `account`. Registry ranges (seat C F3) and the diagnose cites (seat C F4) recomputed; the Gate 19 baseline lines
  explained in `0ebfcb` (seat C F7).

### B-pass mutations
Run by `scratchpad/mutbp/run.py` (each mutant applied by exact text with its count checked, the named test file run
under `TZ=Asia/Kolkata`, the file restored and compared with `cmp`; `lib/` compared with a snapshot afterwards).
B = `workout_completion_bookkeeping_behavioral_test.dart`, R = `coach_day_completion_behavioral_test.dart`,
T = `train_logged_so_far_behavioral_test.dart`.

| mutant | red |
|---|---|
| M01 the restore gate returns after the count (the old step 1b) | B 1 |
| M02 no owner check after the count | **0, equivalent** (below) |
| M03 no owner check after the progress write | B 1 |
| M04 no owner check after the prompt resolve | B 1 |
| M05 no prompt resolve in the step | B 1 |
| M06 the backstop resolves after a failed mark (the old code) | R 1 |
| M07 the backstop uses the payload string | R 1 (0 on the first run, see below) |
| M08 the card's catch rethrows | R 1 |
| M09 a 0 s mark overwrites the stored duration | R 1 |
| M10 the invalidation waits for `mounted` (the old code) | T 1 |
| M11 no `_busy` guard | T 1 (see below) |
| M12 the heading follows the key scan | T 1 |

- **M02 is equivalent, not untested.** `restoreSettledForCurrentUser` compares the marker with the LIVE owner, so
  after a switch the streak steps (2, 3) are skipped anyway and the 3a check stops the progress write. Under the
  kill switch (`disable_streak_reckon_user_gate`, restore-tick gate) the reckon would run, but only on the new
  account's own rows, which is what that account's own reckon does at boot. The check stays as defence in depth.
- **M07's first test was vacuous on the day it was written.** On 2026-11-10 an "unpadded" `y-m-d` string equals the
  padded one (two-digit month and day). The test now passes `<today>T00:00:00`, which sorts after today on any day.
- **M11's first red was a timing artefact.** The snackbar's dismiss timer is a real timer (the tap ran in
  `runAsync`), so fake pumps never hid the first snackbar and the test failed with or without the guard. The test now
  removes the first snackbar by hand and asserts that no queued second one appears; that is green on the code and red
  under M11 (the failure is the second "Workout marked complete." line).
