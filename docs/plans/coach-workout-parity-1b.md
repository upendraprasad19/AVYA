# Coach workout parity, slice 1b (OI-490): the chat card follows the stricter rule; Train shows "Logged so far" with a Complete workout button

- **Status:** rev 4, converged (round 1 §9, round 2 §10, round 3 §11)
- **Branch:** `coach-workout-parity` (1a committed as `9c6eaebf`; 1a and 1b merge in ONE PR, 1a plan §4)
- **Blast radius:** account
- **Execution mode (§4.12.7):** inline, single worktree, decided at batch start (same as 1a)
- **Founder decisions it implements (2026-11-10):**
  - 1: the stored and counted result is the same whichever way you log; only the entry UI differs.
  - 2: a coach-logged day is done only when every planned exercise is logged, or the user taps Complete workout.
  - A: Train's today row shows "Logged so far".
  - D: a Complete workout button on Train's today row, phone and web.
  - F: a forgotten day stays not done. It was put to the founder as "5 of 6 logged and midnight passes", and the answer was "stays not done", costing a freeze or the streak.
  - The approved board item: rest-day and moved-day protection on the card and the tap. On the coach paths a rest day, a moved day or a day with no plan never becomes a counted workout. The founder re-confirmed this on 2026-11-10 with the copy "Not a planned workout day, so it doesn't count as a workout".
  - Copy approved 2026-11-10 (§4).
- **Not in 1b:**
  - Active Workout showing coach-logged exercises as done (1c, OI-491).
  - "I'm done" re-showing the tile, and the evening reminder (server, OI-492).
  - Nutrition (OI-493).
  - Active Workout still counts a rest-type row completed from a template, by founder decision, recorded in the 1a plan discussion (finishing the week's leftover workout on a rest day).

## 1. Why 1b must ship with 1a

1a makes every door count. The chat card (`submitWorkoutDraft`) still marks the day done as soon as ANY exercise from it saves (`conversational_log_handler.dart:395-438`). With 1a, one exercise logged through the card would earn a whole day, permanently: the count, `current_streak_weeks` and `last_counted_week_key` are monotonic (restore max-wins at `user_repository.dart:440`, `GREATEST` on push, `weekly-recalc` `Math.max`). The card also stamps `completed` over a rest row, a `moved`/`dropped` row and a date with no row. On a date with no row, `markCompleted` synthesises a `type:'logged'` completed row. Over a moved row it resurrects the workout on the old date, the e8f4a3 class.

The card's stated reason for marking is real: Train shows a day's logs only once it is done.
- Train expands logs only on a DONE row (`week_rows.dart:78-80`).
- The today expansion shows only the plan (`planned_expansion.dart`).
- A rest row opens the rest sheet (`week_rows.dart:148-149`).
- The past-day sheet loads logs only when done (`exercise_preview_sheet.dart:22-24`).

So 1b makes a not-done day's logs visible in the same change.

## 2. Writers and readers (current, by file:line)

| What | Writer / decider | Readers |
|---|---|---|
| Chat card completion | `conversational_log_handler.dart:336` `submitWorkoutDraft`. The mark block `:395-438` marks on any save (`everSaved` includes earlier attempts' names). F5 re-marks a completed row with no `wlog_`. Its "was completed" check uses the display read `getScheduleForDate`. | `DraftSubmitOutcome.dayMarked` → `ai_coach_provider.dart:1905` `markSaved` (`hasNote` → hold 4 s vs 1.5 s, `savedHoldFor` `:1817`) and `:1932` `keepFailed` (`dayNotMarked: !dayMarked`) → `DraftCardStatus` (`:1726`), `isSavedDraftStatus` (`:1729`, read by `beginSubmit` `:1891`, `updateSet` `:1990`, the card's haptic listener `workout_log_confirm_card.dart:112`) → `cardStateFor` (`:26`), `WorkoutCardState` (`:17-24`), the card's `saved` boolean (`:120-121`, which drives the header, the exercise filter, `below` and hiding the actions), the lines at `:136-140` |
| Typed all-logged backstop | `tool_dispatcher.dart:433` `_maybeCompleteScheduledDay`. Reads the RAW row `workoutBox.get('schedule_$dateStr')`. Order: no row or completed → return; terminal → return; rest → return; `allLogged = plannedCount > 0 && loggedCount >= plannedCount` → `markCompleted(completedVia:'auto')`; else `_writeCompletionPrompt`. The dispatcher refreshes `chatHistoryProvider` after a `log_set` (`:206-215`) so the tile shows. | the prompt row, below |
| "Planned exercise has a log" | `tool_dispatcher.dart:518` `_exerciseLogged` (swap-tolerant, `exlogKey`, which only lowercases and trims, `workout_write_service.dart:1704`). Duplicate: `ai_snapshot_builder.dart:1287` `_plannedExerciseHasLog`. | the backstop count; the snapshot `today_workout_completion` |
| Completion prompt row (`coachBox['completion_prompt_<date>']`, local only, excluded from sync at `sync_coach.dart:170`) | `tool_dispatcher.dart:537` `_writeCompletionPrompt`; `:564` `_resolveCompletionPromptIfPresent` (also called by the move/drop paths `:832`, `:864`); `ai_coach_provider.dart:358` `resolveCompletionPrompt` | `ai_coach_provider.dart:187-225` `ChatHistoryNotifier.build` → `completion_prompt_card.dart`; `coach_interaction_repository.dart:376` |
| Tap completion | `ai_coach_provider.dart:375` `completeWorkoutFromPrompt`. Uses the DISPLAY read `getScheduleForDate`, so a terminal row reads as null and is refused (no row → fail). Completed or rest → resolve, ok. Then `markCompleted(completedVia:'tap')` + the 1a `afterCompletion`. Accepts ANY date. | `ai_coach/screen.dart:354-367` |
| Tile copy | `completion_prompt_card.dart:88` hard-codes "Recruit — log more exercises?" | — |
| Train week data | `train_provider.dart:~907-955`: `getWeek` → `getScheduleForDate` (`workout_schedule_read_service.dart:1323`), so terminal dates have NO row. `isRest = isRestDayConsideringLogged(type)` (`type != 'workout' && != 'custom_template'`). `isDone = status == 'completed'`. | `week_rows.dart:65-160`: the status ladder checks `isRest` BEFORE `isDone`, so a counted rest-type row shows as rest. `planned_expansion.dart`; `expanded_exercises.dart:6`; `exercise_preview_sheet.dart:22` |

`completed_via` has no reader in lib or supabase; only tests assert its values (`coach_completion_prompt_test.dart:221,256`). It is stamped on the `schedule_` and `wlog_` rows only and never pushed, so a new value is local metadata.

## 3. Design

### D1. One coach-day completion rule

- **`lib/core/services/completion_prompt_store.dart`** (new). It owns `coachBox['completion_prompt_<date>']`.
  - Methods: `write(dateStr, planned, logged)` and `resolve(dateStr)`.
  - The bodies move verbatim from `ToolDispatcher._writeCompletionPrompt` / `_resolveCompletionPromptIfPresent`: same key, same row shape, same supersede rule.
  - `write` also resolves any OLDER unresolved prompt row in the same call, so the sweep lives in a write path.
  - The dispatcher (including the move/drop paths `:832`, `:864`) and `ChatHistoryNotifier.resolveCompletionPrompt` call it.
  - It lives in core so Train can use it without importing ai_coach. Train has no ai_coach import today, and none is added.
- **`WorkoutScheduleReadService.rawScheduleRow(DateTime date)`**: `workoutBox.get(scheduleKey(date))` as a Map. No terminal filter and no completed-in-the-past demotion. That is exactly the dispatcher's read (`tool_dispatcher.dart:436`). `getScheduleRowForDate` is NOT used, because its demotion (`workout_schedule_read_service.dart:1004-1017`) makes a row completed early for a later date read `planned`.
- **`WorkoutReadService.loggedPlannedExerciseCount(DateTime date, Map row)`**: the exact body of `_exerciseLogged`, summed over `row['exercises']`. The dispatcher and the snapshot builder call it, and their private copies are deleted.
- **`WorkoutReadService.datesWithExerciseLogs()`**: one pass over `workoutBox.keys`, collecting the IST date of every `exlog_<date>_…` key. No row reads, and no `toMap()` fallback scan (`exerciseLogsForIstDate` falls back to one when its index is empty, `workout_read_service.dart:~338`). Train computes it once per build. `hasExerciseLogsFor(String istDate)` is membership in it. The tap guard uses `hasExerciseLogsFor`. The NEW `LOGGED` / `LOGGED SO FAR` blocks render `exerciseLogsForIstDate` (`:325`). The existing DONE expansion keeps `WorkoutRepository.getExerciseLogsForDate` (the OI-377 duplicate, untouched).
- **Pure `decideCoachDay({required Map? rawRow, required int loggedCount, required bool hasWlog, required String dateStr, required String istToday})`** in `lib/features/train/services/coach_day_completion.dart` returns `CoachDayDecision`. Every caller passes `rawScheduleRow`, never `getScheduleForDate`, where `terminal` would collapse into `noPlan`. Branches, in this order:

  | Decision | When |
  |---|---|
  | `future` | `dateStr > istToday`. A coach `log_set` can carry any date (`tool_dispatcher.dart:367-370`), and with 1a a full future day would count permanently. No mark, no prompt. |
  | `noPlan` | no row |
  | `alreadyDone` | `completed` and `hasWlog` |
  | `repairDone` | `completed` and no `wlog_` |
  | `terminal` | `moved` / `dropped` |
  | `rest` | `type == 'rest'` |
  | `completeNow` | `plannedCount > 0 && loggedCount >= plannedCount` |
  | `askToComplete` | anything else: a partial, `paused`/`skipped`/`travel`, an empty non-rest `exercises[]` |

  - **Backstop parity.** The order after `future` is the backstop's. The backstop gains only `future`: a real 1a+1b exposure, mutation-tested. It treats `alreadyDone` and `repairDone` alike (return), as today. Only the card re-marks `repairDone` (its F5). This asymmetry is deliberate and tested, including `type:'rest'` + `completed` + no `wlog_`.
  - **`rest` is `type == 'rest'`** (the backstop's rule, kept for parity). Train's `isRest` is wider (`type != 'workout' && != 'custom_template'`). The divergence, a non-done row of another non-workout type, is pinned in the decision-table test, and Train's button additionally requires `!day.isRest`.
  - **`paused`** follows the backstop and Active Workout: it can complete. 1a counts a paused today-row through Active Workout.
  - **A past day** still auto-completes in the backstop and the card when every planned exercise is logged (decision 2: all logged), never through a tap or a prompt (decision F). A past-date `askToComplete` in the backstop (a partial `log_set` dated yesterday) writes NO prompt row and leaves the day unmarked; today it writes one (R3-F1).
  - **`skipped` / `travel`** rows, like `paused`, reach `completeNow` / `askToComplete` (backstop and tile parity), so the Train button can complete them (R3-F4).
- **`CoachDayCompletion.completeOnTap({required String date, required CompletionDoor door})`** is the ONE tap path, used by the chat tile and the Train button. It captures the Hive owner first, then:
  - It refuses (no write, prompt resolved) when `date != istTodayStr()` (F: a past partial day stays not done; a future day is not done yet), on `noPlan`, `rest` or `terminal`, and when `!hasExerciseLogsFor(date)`. The log guard is ANY log for the date, not only planned names: a tap is an explicit "I'm done" (decision 2/D), and names can differ (D2).
  - On `alreadyDone` / `repairDone`, it resolves the prompt and returns success with no write (today's tap behaviour for a completed row).
  - Otherwise it calls `markCompleted(workoutName: <plan name or 'Workout'>, completedVia: door == coachTap ? 'tap' : 'train_tap')`, then `afterCompletion(door: door, mintProgressIfMissing: false)`, then resolves the prompt. Only Active Workout mints.
  - The `alreadyDone` read runs outside `markCompleted`'s per-date lock. A race only re-stamps `wlog_` metadata, never the count: `newlyCompleted` is decided under the lock.
  - It returns `CoachTapResult` {completed, alreadyDone, refusedNotToday, refusedNotCountable, refusedNoLogs, failed}. `completeWorkoutFromPrompt` becomes a thin call (`door: coachTap`) returning it.
  - New `CompletionDoor.trainTap`. The enum is used only for telemetry and the test recorder; its doc comment `:24-27` is updated.
  - **Result to copy, for the tile (`ai_coach/screen.dart:354-398`, which today shows one "try again" line for any non-success) and Train. Approved lines only:**

    | Result | What the user sees |
    |---|---|
    | `completed` / `alreadyDone` | success: the tile resolves, the Train row turns DONE |
    | `refusedNoLogs` | `Couldn't complete. Log at least one exercise first.` |
    | `refusedNotToday` / `refusedNotCountable` | `Sets saved. Day not marked done.` |
    | `failed` | `Couldn't save. Try again.` |

- **Prompts are today-only.** `CompletionPromptStore.write` is called only for IST today (backstop and card). `ChatHistoryNotifier.build` stays a pure read: it FILTERS out unresolved prompts dated before today, and never writes inside a provider build. The filtered rows are inert, because `completeOnTap` refuses them. This is consistent with F, and with the prompt being local-only: it never survives a restore or reaches a second device. Train's button reads local logs and the raw row, so it works after a restore.

### D2. The chat card follows the rule

In `submitWorkoutDraft`, after the saves (owner captured at entry, unchanged), when `everSaved` (this attempt's saves or an earlier attempt's), it reads `rawScheduleRow` and decides. The decision runs whether or not some exercises failed this attempt, because what was saved is on disk. The card's date is the FIRST attempt's date (`beginSubmit`, `ai_coach_provider.dart:1892`; deliberate, b7f3e2), so a retry after IST midnight decides for yesterday.

| Decision | Action | `dayState` |
|---|---|---|
| `completeNow` (any date up to today) | `markCompleted(workoutName: row workout_name (non-placeholder) else kChatWorkoutName, durationSec: saved duration)` + `afterCompletion(door: chatCard)` + resolve the prompt | `completed` |
| `repairDone` | today's F5 re-mark (no count: `newlyCompleted` is false for a completed status) | `completed` |
| `alreadyDone` | none | `completed` |
| `askToComplete`, IST today | `CompletionPromptStore.write` + `chatHistoryProvider.notifier.refreshFromHive()` (guarded, as the dispatcher does at `:206-215`, so the tile shows at once) | `awaitingComplete` with `planned` / `logged` |
| `askToComplete`, before today | none (F) | `pastNotMarked` |
| `rest` / `terminal` / `noPlan` / `future` | none | `notCounted` |
| a failed mark | — | `markFailed` |

State change, with every reader:
- `DraftSubmitOutcome.dayMarked` (bool) becomes `dayState` (enum `completed | awaitingComplete | notCounted | pastNotMarked | markFailed | none`) plus `plannedCount` / `loggedCount`.
- `markSaved(id, dayState:, ...)` and `keepFailed(id, ..., dayState:)` replace `dayMarked:`. `WorkoutDraft.dayNotMarked` becomes `dayState`. `keepFailed` shows the not-marked line only for `markFailed` / `pastNotMarked`.
- `DraftCardStatus` gains `savedAwaitingComplete` and `savedNotCounted`; `savedDayNotMarked` covers `markFailed` and `pastNotMarked`. All are in `isSavedDraftStatus`, so a saved card cannot be re-submitted or edited (`beginSubmit`, `updateSet`) and the haptic fires.
- `WorkoutCardState` gains the same two. The card's `saved` boolean includes them, so the header reads "Workout logged" (the sets were logged) and the action row hides.
- The card's lines: awaiting gets the approved partial line; notCounted gets the approved not-counted line; markFailed and pastNotMarked get `Sets saved. Day not marked done.` (approved, unchanged).
- `markSaved`'s `hasNote` is true for every state but `completed`, so the line holds for the 4 s hold, not 1.5 s.
- **Count shown:** `logged` is the planned-name match count. The card logs under the model's draft names (`exlogKey` only lowercases and trims), so a full card under different names can match 0 of N. When `logged == 0` the line drops the count: "Saved. Log the rest, or tap Complete workout when you're done." The tile is the fallback, now visible at once.

### D3. Train shows a not-done day's logs and offers Complete on today

The week computes `datesWithExerciseLogs()` once per build. Train rebuilds after a card save through `invalidateWorkoutSurfaces` (`currentPlanProvider`, `calendarWeekProvider`), and after its own button through the same helper.

**Today, not rest, not done, with logs, `decideCoachDay` ∈ {`completeNow`, `askToComplete`}.** "Not rest" means `!day.isRest`. `completeNow` covers a day whose logs are complete but whose mark never ran: a backstop exception, an owner-change refusal, or logs from before this release.
- The chip reads `IN PROGRESS` instead of `TODAY`.
- The expansion shows `LOGGED SO FAR` (rows from `exerciseLogsForIstDate`, rendered with the existing `ExpandedExerciseLogRow`, plus `EDIT LOG`) above the plan preview, then START/RESUME WORKOUT (unchanged).
- It then shows `COMPLETE WORKOUT`, which calls `completeOnTap(door: trainTap)`:
  - Disabled while in flight.
  - Hidden while an Active Workout session is in progress FOR TODAY (`hasInProgressSession && workoutDay.date != null && istDateStr(workoutDay.date!) == istTodayStr()`; a null date does not hide, R3-F2). `hasInProgressSession` alone has no date (`train_provider.dart:1377`), so a stale session from another day must not hide today's button. RESUME is there, and finishing it completes the day.
  - Snackbar per `CoachTapResult` (D1 table).
- An Active Workout finished after a Train completion re-marks with the real session values, with no count (`newlyCompleted` false). Pinned by a test.

**Done before rest, everywhere in the row.** A counted rest-type row (template on a rest day, a synthesised `logged` row) is a DONE row. In `week_rows.dart`:
- The status ladder checks `isDone` first.
- `onTap` checks `isDone` first and toggles the expansion. It opens the rest sheet only for `isRest && !isDone`. Today `:148-149` routes every `isRest` tap to the sheet.
- The name (`isRest ? 'Rest' : name`), the `EX` count and the day-label colour/dimming (`:185`, `:191`) use `isRest && !isDone` (R3-F3).

The hero already checks done first (`hero_cards.dart:39-40`). This changes how existing counted rest-type and `logged` rows look: they are now DONE, named and expandable. That goes in the founder summary.

**A rest row, not done, with logs (any date).**
- The chip reads `LOGGED`.
- A tap expands inline to the logs with "Rest day. Not counted as a workout." instead of opening the rest sheet.
- There is no Complete button.

**A past planned row, not done, with logs.** The preview sheet also loads the logs (`exercise_preview_sheet.dart:22` drops the `isDone` condition; rows from `exerciseLogsForIstDate`) and shows them under `LOGGED` above the plan. The row keeps `MISSED` (F). There is no Complete button.

**Dates with no live row (moved away, or outside the plan), today or past.** Train has no row for such a date (`getWeek` → `getScheduleForDate`, `workout_schedule_read_service.dart:1323`).
- This is today's behaviour for typed logs, so the card now matches the typed path (decision 1).
- The logs still feed PRs and the coach snapshot.
- Before 1b, the card's mark made such a date reappear as DONE, which was itself the moved-day resurrection bug (e8f4a3).
- The rev-2 `LOGGED TODAY` block is dropped: its predicate drew a P1 (B2-F3), and it covered only rare days. This is raised with the founder in the 1b summary as a parity decision.

**Home and the Train hero: unchanged.**
- The hero has no label to replace (`hero_cards.dart:44`, eyebrow removed 2026-11-01) and is one row by design. Its START/RESUME agrees with the row.
- Home's Start opens Active Workout, where 1c shows the logged exercises.

**No logs:** every row renders exactly as today. **Web:** the same widgets (no `kIsWeb` branch in Train). Widget tests run at 360 dp and 1024 dp. The new "today" gates use IST only.

**The tile after a Train completion:** a live chat may still show today's tile until it rebuilds. Tapping it then returns `alreadyDone` (resolve, success), which is harmless.

### D4. The tile

`completion_prompt_card.dart:88` becomes `WardroomCopy.coachCompletionPromptBody` = "Log more exercises, or complete the workout?" (approved). There is no rank read. OI-375 (the server lines) keeps its own scope.

### D5. What does NOT change

- The typed backstop's decisions, apart from the new `future` branch and the past-date prompt skip (R3-F1).
- Active Workout (1a), `markCompleted`, the bookkeeping step, the Train hero, Home, the screen order.
- The metadata re-stamp race (D1) is accepted and noted.

## 4. Copy (approved by the founder 2026-11-10)

| Where | Text |
|---|---|
| Card, partial planned day (today) | `Saved {logged} of {planned}. Log the rest, or tap Complete workout when you're done.` (`logged == 0`: the same line without `{logged} of {planned}.`) |
| Card, rest / moved / no plan | `Saved. Not a planned workout day, so it doesn't count as a workout.` |
| Card, mark failed; card, past-day partial; tap refused (not today / not countable) | `Sets saved. Day not marked done.` (existing) |
| Tile body | `Log more exercises, or complete the workout?` (buttons unchanged: `Log more` / `Complete`) |
| Train today chip with logs | `IN PROGRESS` |
| Train today expansion heading | `LOGGED SO FAR` |
| Train today button | `COMPLETE WORKOUT` |
| Tap refused, no logs / write failed | `Couldn't complete. Log at least one exercise first.` / `Couldn't save. Try again.` |
| Rest row with logs | chip `LOGGED`; line `Rest day. Not counted as a workout.` |
| Past not-done sheet heading | `LOGGED` |

No copy beyond the approved set. The `logged == 0` variant is the approved line without its count.

## 5. Tests (each mutation-proven, rule 21)

New `test/contracts/coach_day_completion_behavioral_test.dart` (real Hive, as T1/T3).

**Decision table (pure):** every branch, including:
- `future` (tomorrow with the full plan logged gives no mark);
- `paused` gives `askToComplete` / `completeNow`;
- `type:'rest'` + `completed` + no `wlog_` gives `repairDone`;
- a non-done row of type `none` (the pinned divergence from Train's `isRest`);
- a row completed early for this date (raw read gives `alreadyDone`);
- a swapped row (`swapped_from`);
- an empty non-rest `exercises[]`;
- missing status;
- parity with `_maybeCompleteScheduledDay` for every shape, with `future` the one deliberate change.

**Backstop, end to end:** a full-plan `log_set` dated tomorrow gives +0 and the row stays `planned`; a partial `log_set` dated yesterday writes no prompt row and leaves the day unmarked (re-check `coach_completion_prompt_test.dart` fixtures that expect a prompt on a past date).

**Card, end to end (`submitWorkoutDraft`):**
- **Partial planned day today:** no mark; a prompt row with the counts, present in `chatHistoryProvider` state right after the submit; +0; `savedAwaitingComplete`; 4 s hold.
- **All planned:** marked with the PLAN name; +1; prompt resolved.
- **Different names:** `askToComplete`, `logged == 0`, the count-free line.
- **Rest:** logs saved; no mark, no prompt; +0; `savedNotCounted`.
- **Moved and dropped:** status unchanged; +0.
- **No row:** +0, no `logged` row synthesised.
- **Completed with no `wlog_`:** re-marked (F5).
- **Partial card, then the remaining exercise typed:** the backstop completes; +1 total.
- **Partial card, then the tile tap:** +1.
- **Partial with one exercise failing:** the decision runs on what saved; no not-marked line.
- **A saved card:** cannot be re-submitted or edited.
- **Retry after IST midnight, partial:** `pastNotMarked`; no prompt; +0.
- **Retry after midnight completing every planned exercise:** completed on the first attempt's date; +1.

**Tap path (`completeOnTap`, both doors):**
- **Refused, with the exact `CoachTapResult`:** a moved raw row (stays `moved`, +0); rest; no row; no log; yesterday (+0); tomorrow.
- **Already done:** no write.
- **Train tap on a partial day:** completed, +1, `completed_via: 'train_tap'`, door `trainTap`, no progress minted.
- **Owner change before the mark:** nothing written.
- **Train tap, then Active Workout finished:** +1 total.
- **Past-date prompt row:** not in `chatHistoryProvider` state, and `ChatHistoryNotifier.build` leaves the box unchanged.
- **`CompletionPromptStore.write`:** resolves an older unresolved row.
- **The tile:** maps each `CoachTapResult` to its line.

**Train widgets:**
- **Today partial:** `IN PROGRESS`, `LOGGED SO FAR`, `COMPLETE WORKOUT`. Tapping the button turns the row `DONE` and adds +1.
- **Sessions:** an in-progress session for TODAY hides the button; a stale session for yesterday does not; a session with a null date does not.
- **A `completeNow`-but-unmarked day:** shows the button.
- **A counted rest-type row:** `DONE`, and tapping it expands its logs, not the rest sheet.
- **A rest row with logs:** logs inline, no Complete.
- **A past not-done row with logs:** the sheet shows them, no Complete.
- **No logs:** the current widgets.
- Each at 360 dp and 1024 dp.

**Tile:** the body is the WardroomCopy constant and has no `Recruit`.

**Planned mutations:**
- The card marks on any save (the old rule).
- `completeNow` without `plannedCount > 0`.
- The `future` branch removed.
- `decideCoachDay` fed the display read (terminal collapses).
- The terminal, rest, no-log and today-only guards, each removed from `completeOnTap`.
- The plan name replaced by `kChatWorkoutName`.
- No `refreshFromHive` after the card's prompt write.
- `savedAwaitingComplete` dropped from `isSavedDraftStatus`.
- `hasNote` false for awaiting.
- The ladder back to `isRest` first.
- `onTap` back to `isRest` first.
- The today gate inverted.
- The preview sheet's `isDone` restored.
- The `swapped_from` read dropped.
- `trainTap` mapped to `'tap'`.
- The in-progress hide removed.
- The in-progress hide's date check removed.
- The button gate back to `askToComplete` only.
- A Hive write added to `ChatHistoryNotifier.build`'s past-prompt filter.
- `pastNotMarked` mapped to `awaitingComplete`.

**Repoint or reseed, never loosen:**

Source pins:
- `derive_only_tool_surface_test.dart:111-125` pins `_maybeCompleteScheduledDay(`, `markCompleted(` and `raw['type'] == 'rest'` in the dispatcher. The method and the mark stay; the rest literal moves to `coach_day_completion.dart`, where the pin is repointed.
- `coach_derived_completion_writer_to_reader_test.dart`.
- `coach_completion_prompt_test.dart` (also asserts `completed_via` 'auto'/'tap' at `:221,256`).
- `terminal_row_display_read_path_test.dart`.
- `completed_title_follows_log_test.dart:444-473` (the per-file `markCompleted(` census: `ai_coach_provider.dart` loses its site, `coach_day_completion.dart` gains one).
- `conversational_log_handler_uses_write_service_test.dart:71-82`.
- `workout_surface_invalidation_test.dart:92-108`.
- `test/sync/sync_gap_test.dart:48-82` and `hive_key_contracts_test.dart:~330` (pin `markCompleted(` in `conversational_log_handler.dart`, which stays).
- `coach_chat_history_replay_writer_to_reader_test.dart:152`.
- `train_screen_compact_layout_test.dart:48-114` (screen order and hero pins; rev 3 changes neither, so it must stay green unchanged).

Behavioural:
- `test/ai_coach/workout_log_confirm_card_saved_signal_test.dart`:
  - About 30 `DraftCardStatus.saved` assertions sit on days with no schedule row. They are RESEEDED with a planned row holding exactly the card's exercises, so they stay `saved` with their meaning intact.
  - New no-row cases assert `savedNotCounted`.
  - The bad-plank case (`:595-612`) gets a planned row, so its mark is attempted.
  - The `markSaved`/`keepFailed` calls at `:1094-1096` move to `dayState`.
- `coach_completion_counts_behavioral_test.dart` (`out.dayMarked` `:285`, `:314` move to `dayState`; its card days hold all planned exercises).
- `coach_chat_log_train_refresh_behavioral_test.dart:319`.
- `zero_set_completion_behavioral_test.dart`.
- `test/features/ai_coach/coach_single_confirm_per_log_intent_test.dart`.
- `test/widgets/completion_prompt_card_test.dart`.
- `reschedule_week_terminal_row_test.dart:554-619`.
- `tool_dispatcher_day_swap_invalidation_test.dart` (through the moved prompt resolver).

## 6. Docs, registry, gates

**SoT registry:**
- Update `coach_derived_completion` and `workout_completion_bookkeeping` (the `trainTap` door), plus the registry anchors at `sot_registry.yaml:3891`, `4107`, `6552-6571`, `16929-16947`.
- Add a new concept `coach_day_completion_rule`. Writers: `CoachDayCompletion` and `CompletionPromptStore`. Readers: the card, the backstop, the tile, Train. Behavioural test path as §5.
- Recompute ranges from anchors per commit.

**Prose that names the moved symbols:**
- `lib/features/ai_coach/CLAUDE.md:25,36,77`
- `lib/features/train/CLAUDE.md:58`
- `docs/architecture/ai.md`, `ai-coach-detail.md`, `sync.md`
- `log_workout_sheet.dart:9`
- the `ai_coach/screen.dart` comments
- `ai_snapshot_builder.dart:1277`
- `workout_write_service.dart:575-583` (the `completedVia` values: add `'train_tap'`) and `:608`

**Naming glossary:** `CoachDayCompletion`, `CompletionPromptStore`, `rawScheduleRow`, `trainTap`, `IN PROGRESS`.

**ADR-0012 amendment:** the card follows the rule, and the tile copy changes. The quoted old copy at ADR `:135` and diagnose `280c4d:148` is history and stays.

**Diagnose doc:** its own doc, `2026-11-10-coach-card-marks-uncountable-days-<id>.md`.
- `related_bugs: [0ebfcb, 280c4d, e8f4a3]`.
- Covers the card's mark of partial, rest, moved and no-plan days, plus the backstop's future-date completion. 1a made both permanent.
- There is no "tap terminal bug".

**Gates:**
- The full gate loop runs before each review dispatch with a diff (§4.12.5/8).
- Device check before the merge:
  - a partial chat log → Train `IN PROGRESS` → COMPLETE WORKOUT → DONE, count +1;
  - a rest-day chat log;
  - the same on web.

## 7. Questions for the reviewers (round 3, delta)

1. Do the rev-3 changes (§10) close the round-2 P1s without opening a new path that marks or counts a day the rule excludes?
2. Is any reader of the changed draft state, the prompt row, `rawScheduleRow` or `datesWithExerciseLogs` missed?

## 9. Round-1 changes (rev 1 → rev 2)

- **A-F1 / B-F2:** the "tap terminal bug" was false (the display read refuses terminal rows). The claim is dropped. Every decision uses the RAW row so `terminal` is live.
- **A-F2 (P1):** the card refreshes `chatHistoryProvider` after writing the prompt.
- **A-F3 (P1):** the full draft-state reader list: `isSavedDraftStatus`, `saved`, `hasNote`, `keepFailed`, `everSaved`, `WorkoutCardState`.
- **B-F1 (P1):** the tap and prompts are today-only (decision F).
- **B-F3 (P1):** the `LOGGED TODAY` block; past no-row dates stated as typed-path parity; the hero shows `IN PROGRESS`.
- **B-F4 (P1):** the ladder checks `isDone` first, so a counted rest-type row shows DONE; the "not counted" line applies only to rest rows that are not done.
- **A-F4:** the count-free line when `logged == 0`.
- **A-F5:** no-plan = not counted, founder-confirmed by the approved copy.
- **A-F6:** `repairDone` asymmetry, deliberate and tested.
- **A-F7 / B-F6:** the button is hidden during an in-progress session and disabled in flight; Train tap then Active Workout is pinned.
- **A-F8:** one log source (`WorkoutReadService`).
- **A-F9 / A-F10:** the full repoint/reseed and docs lists.
- **A-F11:** the prompt store in core (no train → ai_coach edge); `'train_tap'` added to the `markCompleted` doc comment; the tile copy goes to `WardroomCopy`.
- **B-F5:** button visibility from the decision (`askToComplete` only); per-reason refusal; `paused` stated.
- **B-F7:** the prompt is local-only and today-only, stated.
- **B-F8:** a regenerated plan can read 0 of N (the count-free line); one unrelated log is enough for an explicit tap (decision D).
- **B-F9:** the past row keeps `MISSED` (F).

## 10. Round-2 changes (rev 2 → rev 3)

Rev 3 removes two rev-2 mechanisms rather than patching their edges: the `LOGGED TODAY` block and the hero chip. It also reuses approved copy instead of adding lines.

- **B2-F1 (P1):** a `future` branch in the rule and the backstop (a future-dated full `log_set` counted permanently).
- **A2-F1 / B2-F6 (P1):** done-before-rest now covers the tap routing, the name and the EX count, not only the chip. Tested by tapping.
- **A2-F2 / B2-F2 (P1):** a past-date partial (a retry after midnight) is `pastNotMarked`, shown with the approved "Sets saved. Day not marked done.". The card no longer points at a Complete control that does not exist.
- **A2-F3 (P1):** no write in `ChatHistoryNotifier.build`. It only filters; the sweep is in `CompletionPromptStore.write`.
- **B2-F3 (P1):** the `LOGGED TODAY` block is dropped (parity with typed logs; in the founder summary).
- **A2-F4:** a `CoachTapResult` → copy mapping for the tile and Train, using approved lines only.
- **A2-F5:** the hero change is dropped.
- **A2-F6:** one raw read (`rawScheduleRow`, no demotion), the same as the dispatcher's.
- **A2-F7:** `datesWithExerciseLogs()` (a key pass, once per build). The new blocks render `exerciseLogsForIstDate`.
- **A2-F8:** the test list is completed, and the `completed_via` test readers are named.
- **A2-F9:** `mintProgressIfMissing: false` for `trainTap`.
- **A2-F10 / B2-F5:** the in-progress hide is date-scoped.
- **B2-F4:** the button also shows for `completeNow`.
- **B2-F7:** row-less days are raised with the founder.
- **B2-F8:** the `rest` divergence is pinned; the button also requires `!isRest`.
- **B2-F9:** the lock window is stated.

## 11. Round-3 changes (rev 3 → rev 4)

Round 3 (delta, both lenses) CONVERGED: the five round-2 P1s are closed as written, the parity claim for row-less dates is true, and the helpers are implementable (`rawScheduleRow` via `_hive.workoutBox` + `_schedulePrefix`; every exlog key comes from `exlogKey` = `exlog_<istDate>_<8hex>`, restore and the migrator included; `workoutDay.date` is `DateTime?`). Small points folded:
- **R3-F1 (P2):** a past-date `askToComplete` in the backstop writes no prompt; stated and tested.
- **R3-F2 (P3):** the null `workoutDay.date` rule.
- **R3-F3 (P3):** the day-label colour uses `isRest && !isDone`.
- **R3-F4 (P3):** `skipped` / `travel` stated.

## 12. As built (implementation notes, not a design change)

- **`loggedPlannedExerciseCount` lives in `coach_day_completion.dart`, not `WorkoutReadService`.** `WorkoutWriteService` imports `WorkoutReadService`, so the read service cannot call `WorkoutWriteService.exlogKey` without an import cycle. The body is the planned one.
- **Two owner guards added (found by the T3 account-change tests):** the card checks `currentOwnerFullId` after the mark gate and before the day decision (`chat_card_owner_changed`); the backstop checks it first (`derived_completion_owner_changed`). Without them the decision read the NEW account's row. This supersedes 1a's M6a evidence for the card (the guard now runs earlier).
- **The tap keeps the raw `?? 'Workout'` name** (not `planWorkoutName`): a blank stored name still fails `markCompleted` exactly as before, as the backstop does. The card marks with `planWorkoutName(raw, fallback: kChatWorkoutName)`.
- **The card's awaiting / not-counted lines show only once the card is saved** (a partial-failure card keeps its failure note; the live-region test (b) pins the order).
- **COMPLETE WORKOUT is full width when it fits and scales down when it does not** (`LayoutBuilder` → `FittedBox(scaleDown)` → `ConstrainedBox(minWidth: row)` → `WardButton(fullWidth: false)`). A `WardButton` label neither wraps nor ellipsizes, and `fullWidth: true` inside a `FittedBox` is an infinite width.
- **`completed_via` has no cloud column** (`scheduled_workouts` has none, `backups/live_schema_columns.json`); `'train_tap'` is a local Hive stamp no code branches on.
