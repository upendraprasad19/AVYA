---
plan: train-coach-log-refresh
revision: 11
date: 2026-10-21
blast_radius: account   # classifier on the planned file set (R1A-6); ai_coach service + train UI
tier: M                 # §4.12.6: ai_coach ⇒ M. ("CLAUDE.md" in the L list means the ROOT file; nested CLAUDE.md edits do not make this L, R3A-P3.) Not L: no sync writer/schema/EF change (the sync.md edit is a doc correction), no root CLAUDE.md edit (nested CLAUDE.md rows only)
execution_mode: inline  # §4.12.7; one worktree (.claude/worktrees/train-coach-log-refresh)
closes_oi: [OI-370, OI-371]
files_oi: [OI-376, OI-377, OI-378, OI-379, OI-380, OI-381]  # invalidation copies + dead hook; duplicate exlog reader; Riverpod assertion (upstream_blocked); coach logs skip total_workouts_done/rank; distance detail; remaining '1 sets' renderers. OI-382: logExercise accepts a negative durationSec
---

# A coach chat log shows on the Train tab at once, its card says it saved, and exercise names are readable

## Revision history
- **rev 1 → rev 2:** round 1 had two reviewers, ground truth (A) and exposure (B), with 3 P1s between them. Every finding is mapped in §7.
- **rev 2 → rev 3:** round 2 (A ground truth, B exposure) found 2 P0/P1 classes in B' (the saved state is unmounted by the chat list; a failed write would show it) and 1 P1 in the test design (the error collector). Mapped in §8.
- **rev 3 → rev 4:** round 3 (A, B) found 4 P1s: no runnable chat-slot test, two mutations that redden nothing, `markSaved`/`keepUnsaved` acting on whatever draft is current, and a false "Not saved" on a partial failure. The founder approved four copy decisions (2026-10-21, §2 B'). Mapped in §9.
- **rev 6 → rev 7:** round 6 (A, B): the same P1 from both (the card forgot an earlier partial save after a failed retry or an edit), plus the held card being invisible (B). Founder copy 2026-10-21: held notice `New workout waiting. Confirm or discard this one first.`; skipped line `Skipped: {names} (no sets).` Mapped in §12.
- **rev 10 → rev 11:** delta check of rev 10: CONVERGED; folded its test-precision P2s (a second test gate so the pre-`markCompleted` re-check is provable; a stored `dayNotMarked` flag so a partial card can render and keep the day line; fixture state for the direct id-guard case) and P3s. Mapped in §16.
- **rev 9 → rev 10:** round 9: BOTH reviewers CONVERGED (no P0/P1). Rev 10 folds their P2s (an auth flip mid-submit must also skip marking the day; three mutation→test claims that would redden nothing; a stale doc sentence) and P3s. Mapped in §15.
- **rev 8 → rev 9:** round 8 (A, B): rev-7 fixes confirmed (backspace probed). New: B P1, the day was left unmarked after a partial save and Train shows logs only on DONE days (`week_rows.dart:78`, `exercise_preview_sheet.dart:22`), so saved sets became invisible; A P1s, a stale edit sheet throws on a disposed ref before the id check, and the deletion clause lacked a length guard. Founder decisions 2026-10-21: an exercise with no usable set is SKIPPED (whether it has no sets or only unusable ones) and the approved line becomes `Skipped: {names} (no usable sets).`; the five TalkBack labels are approved. Mapped in §14.
- **rev 7 → rev 8:** round 7 (B; the A review was cut off by a container restart and re-runs in round 8): 1 P1 (the reject-not-trim filter blocked backspace on the seeded `-5.0`), 3 P2s (the Skipped line was neither announced nor held; the held-card announcement had no context to run in; a retry after IST midnight logged to the new day). Mapped in §13.
- **rev 5 → rev 6:** round 5: 4 P1s, all in B' (submitting flag not observable state; the draft-id guard unreachable once `setDraft` is queued; TalkBack cannot press the pencil; a same-failure retry cannot re-announce; a bad weight on a non-weighted row cannot be fixed). Founder decisions 2026-10-21: keep ONE batch (no B' split) and walk the blockers with the founder; a new workout card arriving while one is saving or failed is HELD until the current card resolves; DISCARD after a partial save asks first (`Discard the rest? {saved} stays logged.` with DISCARD / KEEP). Mapped in §11.
- **rev 4 → rev 5:** round 4: exposure CONVERGED (P2s only); ground truth 2 P1s (a scroll mutation no harness can run; the day-not-marked branch tested off the render path on a false "no seam" premise). The founder approved the pencil label `Edit {name}` 2026-10-21. Mapped in §10.
- **Founder decision 2026-10-21 (Fix A copy round):** `WorkoutLogConfirmCard` gets a saved state in this batch. It is a prerequisite for deploying the server batch `coach-log-truth`.

## 0. Evidence
- **Observation 3** (OI-370; founder, web, 2026-10-21):
  - After a coach chat log, the expanded DONE day row on the Train tab did not show Bench Press until a page reload.
  - The row was written at 13:29:36 IST, 12 s after a coach reply with `tool_calls = null`. So the writer was the legacy chat card: `WorkoutLogConfirmCard` → CONFIRM → `submitWorkoutDraft`.
  - Reproduced in a scratch test (real Hive, real `TrainScreen`, both visible and `Offstage` + `TickerMode(false)`): the index holds the key but the row is missing until `currentPlanProvider` is invalidated. The `ToolDispatcher` path refreshes correctly.
- **Observation 4** (OI-371; founder screenshot): the names render as `Barb…`, `Leg…`, `Benc…` at phone width.
- **Copy round, R1B-F3:** after CONFIRM · LOG WORKOUT the card vanishes with no saved signal (`workout_log_confirm_card.dart:45`).

## 1. Writers and readers (§4.1)

### Observation 3
- **Writer:** `conversational_log_handler.dart` `submitWorkoutDraft(WorkoutDraft draft, WidgetRef ref)` (`:282`).
  - It calls `logExercise` (`:303`; the Hive row plus the awaited index append happen at `workout_write_service.dart:244-252`) and then `markCompleted` (`:314`).
  - It invalidates only calendarWeek, streak and todayWorkout (`:326-328`).
  - Its comment at `:321-325` claims the dead `WorkoutWriteService.onInvalidate` hook does the rest. The hook is declared at `:86`, is never assigned, and is checked at 9 sites (`:269, 606, 687, 831, 1116, 1225, 1344, 1414, 1499`).
- **Reader:** `expanded_exercises.dart:6` `_buildExpandedExercises`.
  - It reads Hive synchronously in build via `WorkoutRepository.getExerciseLogsForDate` (`workout_repository.dart:730`) and redraws only when the Train screen rebuilds.
  - The Train screen rebuilds on `ref.watch(currentPlanProvider)` (`train/screen.dart:116`).
  - The only provider of the chat path's three that the Train tree watches is `streakProvider` (`plan_header.dart:118`). That is an `int`; Riverpod suppresses equal values, and a day that is already DONE leaves it unchanged.
- **Every UI-reachable `logExercise`/`markCompleted` caller (R1A-2):** only `submitWorkoutDraft` skips `currentPlanProvider`. The dispatcher, Active Workout `completeWorkout`, the edit sheet, day swap and `completeWorkoutFromPrompt` (via its screen handler) all refresh Train. The `WorkoutRepository.logExercise` shim (`:1368`) and `markWorkoutCompleted` (`:619`) have no callers.
- **Recurrence:** "a provider missing from a writer's invalidation set". Prior cases are `344121`, `69276a` and the `food_log_provider_invalidation` group. The known-good fix is one shared batch.

### Observation 4 (reader only)
- `expanded_exercises.dart:98-121` lays out `Row[Icon, SizedBox(8), Expanded(Text(name, ellipsis)), Text(detail)]`. The detail text has no width constraint, so it takes its full width first.
- Width available for the name at 320 dp is about 189 dp: 320 − 44 gutter − 2 border − 64 padding − 21 icon (R1B-1).
- Related but not a recurrence: `b2e9d4` (`ui_header_no_clip`).

### Saved signal (R1B-F3 of coach-log-truth)
- **Writer:** `submitWorkoutDraft` clears the draft (`:336`).
- **Reader:** `WorkoutLogConfirmCard.build` returns `SizedBox.shrink()` when the draft is null (`:45`). There is no snackbar and no saved state.
- The sibling cards both show a saved state: `ToolConfirmCard` at `:446,470` and `LogConfirmCard` with "LOGGED" + `check_circle` for 1.5 s.
- **The card's list slot exists only while the draft is non-null** (R2-1): `chat_area.dart:29` `hasWorkoutDraft = ref.watch(workoutDraftProvider) != null`, counted at `:39-42`, built at `:138-139`. Clearing the draft disposes the card's State, so a widget-local saved flag can never be seen. `LogConfirmCard` keeps its settled state in the provider (`markLogged`, then `removeSettled` after 1.5 s, `log_confirm_card.dart:62-67`).
- **Failure is invisible today** (R2-2): `logExercise` and `markCompleted` return `WriteResult.fail` and never throw (`workout_write_service.dart:281-286`, `:618-623`). `submitWorkoutDraft` ignores both results, then marks the day done and clears the draft. `_submit` (`workout_log_confirm_card.dart:29-36`) has no try/finally, so a throw leaves the spinner on. This is the false-success class `ai_coach/CLAUDE.md:74` forbids.
- **Retry is not idempotent:** `logExercise` MERGES new sets into an existing `exlog_<date>_<name>` row with only a 60 s identical-set duplicate window (`workout_write_service.dart:~130-165`). Re-submitting a whole draft after a partial failure doubles the exercises that did save once the 60 s window has passed or when the values differ (`isDuplicateWithin`, `write_result.dart:150-157`, R4A-P2-3).
- **`markCompleted` has its own failure seam** (R4A-P1-2, probe-verified): `logExercise` validates only weight and reps (`:119-121`), so a timed set with `durationSecs: -100` saves, while `markCompleted(durationSec: -100)` returns `fail('durationSec must be >= 0')`. `submitWorkoutDraft` sums timed `durationSecs` into `totalDurationSec`, so a draft `[Plank, timed, DraftSet(reps: 8, durationSecs: -100)]` drives "every exercise saved, day NOT marked" end to end. (That a negative duration reaches exlog at all is its own defect: filed as an OI, §5.)
- **Disposed-ref recurrence** (R4A-P2-5): the `StateError` at `clearDraft` after an unmount (R2A-proven) is a recurrence of `b7f3e2` (`docs/diagnoses/2026-09-27-food-log-invalidate-unmounted-ref-b7f3e2.md`).
- **Notifier lifetime (probe-verified 2026-10-21, R6A-P3):** on riverpod 3.2.1 the notifier instance is REUSED across rebuilds (one construction, two `build()` calls after an auth flip; `notifier_provider.dart:543` `classListenable.result ??=`; the CHANGELOG line is stale). `ref.mounted` stays true across a rebuild (it guards container disposal only). So `build()` resets the held data and the `onDispose`-registration flag, which is load-bearing; the hold TIMER is not reset in `build()` but cancelled only by the `onDispose` hook and by `discard()` (its callback is id-guarded), so the timer-cancel test proves the hook (R9A-P2-4).
- **A real validation failure exists with no new seam** (R3A-P1-2): `DraftSet(weightKg: -5, reps: 8)` passes `draftExerciseSets` (`conversational_log_handler.dart:249-257`, reps > 0) and `logExercise` returns `fail('weightKg must be >= 0')` before writing (`workout_write_service.dart:119-121`). The edit sheet can produce it (`double.tryParse`), so a retry of the same values always fails: the copy must say "fix the sets", not only "retry".

## 2. Design

### B: one workout invalidation batch for the coach write paths
New file `lib/features/train/providers/workout_surface_invalidation.dart`:
```dart
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
void invalidateWorkoutSurfaces(void Function(ProviderOrFamily) invalidate, {required String source})
```
- **API:** verified by R1A on flutter_riverpod 3.3.1 / riverpod 3.2.1. `Ref`, `WidgetRef` and `ProviderContainer` all expose `invalidate(ProviderOrFamily, {bool asReload})`. A probe compiled clean with tear-offs from both `Ref` and `WidgetRef`.
- **What it invalidates:** a fixed list, in this order:
  - currentPlanProvider
  - workoutStatsProvider
  - calendarWeekProvider
  - streakProvider
  - todayWorkoutProvider
  - allExercisePRsProvider
  - **lastPerformanceProvider** (the whole family; R1B-6a: the "last time" values in the Train preview, Active Workout prefill and overload indicator otherwise keep pre-log data for the session)
- **Not in the list: `aiInsightProvider`** (R2A-5). Active Workout `completeWorkout` and `check_mutation_invalidation_set.dart` include it; it watches `todayWorkoutProvider` (`home_provider.dart:661`, c7e3a9), so it refreshes through that entry (corrected by B-pass fb5048e68fae F9; the earlier "reads the latest coach response" was wrong). Omitted on purpose; `sync.md` and the unit test name the omission, and the test pins the watch.
- **Visible effect of the `lastPerformanceProvider` invalidation** (R2B-9): an open Active Workout keeps its prefill (`exercise_card.dart:116` reads in `initState`), but the watched `LAST: …` hint (`:1119`) and `_OverloadIndicator` (`overload_indicator.dart:24`) re-derive from Hive and re-baseline on the sets just logged through the coach, because `logsForExercise` does not exclude today (R3B-P3): mid-session, "LAST" then means "latest", not "previous session". Named in the copies OI together with `completeWorkout` not invalidating the family.
- **Error handling:** each entry gets its own try/catch → `debugPrint` + `ErrorTelemetry.recordNonFatal(e, st, reason: 'workout_surface_invalidate_<source>')`. Precedent: `tool_dispatcher.dart:191` and `day_swap_provider.dart:88`. A bare `debugPrint` is invisible in release builds (L34).
- **Callers changed in this batch** (the coach feature, same class):
  1. `ToolDispatcher._invalidateWorkoutProviders` delegates with `source: 'tool_dispatcher'`. Its false "no common upper bound" comment (`:1840-1844`) is removed.
  2. `submitWorkoutDraft` replaces its three invalidations, and the false `onInvalidate` comment becomes one true line. The signature `submitWorkoutDraft(WorkoutDraft draft, WidgetRef ref)` is kept, because `conversational_log_handler_uses_write_service_test.dart:50,74,91` pins it.
  3. The coach completion-prompt handler `_onCompleteWorkoutFromPrompt` (`ai_coach/screens/ai_coach/screen.dart:364-399`, 5 hand-written entries) delegates. Its false comment (`:374-376`) is removed.
- **Disposed `WidgetRef`** (R1A-10, R2A-2, precedent b7f3e2). `submitWorkoutDraft` runs several awaits after the card's tap, and the card really is disposed mid-submit on a channel switch to Telegram (OI-232 unmounts the chat subtree). R2A proved today's code throws `StateError: Using "ref" when a widget is about to or has been unmounted` at `clearDraft` (`:336`), leaving the draft alive so CONFIRM can log the workout twice.
  - At entry, before the first await: `final container = ProviderScope.containerOf(ref.context, listen: false);` (verified on flutter_riverpod 3.3.1, `WidgetRef.context` at `widget_ref.dart:43`).
  - EVERY provider use after the first await goes through `container`: the invalidations, the draft notifier (`markSaved` / `keepUnsaved`), nothing via `ref`.
  - The `ref` that `logExercise`/`markCompleted` accept only feeds the dead `onInvalidate` hook; the handler passes NO ref (B-pass fb5048e68fae F8: a card disposed mid-submit would hand a dead `WidgetRef` to that hook the day OI-376 wires it). The helper invalidates through the container.
- **Not changed, filed as an OI:**
  - the dead `onInvalidate` hook (9 sites, platform-tier file);
  - the hand-written copies in `edit_workout_log_sheet.dart:293-298`, `train_provider.dart` `completeWorkout` (`:2320-2326`, also aiInsight), `day_swap_provider.dart:75-82`, `day_rollover_service.dart` (~`:274-279`, `lib/core`) and `TemplatesNotifier` delete (`:2515-2519`). None of them misses `currentPlanProvider`, so users see no defect from these today.
- **`sync.md` wording (R1A-2, R1B-5):** "canonical helper `invalidateWorkoutSurfaces`; the coach paths use it; legacy copies remain at … (OI-…)". It never claims "one implementation".
- **The canonical-set drift is noted in that OI:** `check_mutation_invalidation_set.dart` expects 7 providers including `aiInsightProvider`, while `sync.md` lists 6.

### B': WorkoutLogConfirmCard saved state and honest failure (founder 2026-10-21; copy and behaviour approved 2026-10-21)
**Outcome type.** `submitWorkoutDraft` becomes `Future<DraftSubmitOutcome> submitWorkoutDraft(WorkoutDraft draft, WidgetRef ref)`. `DraftSubmitOutcome` (same file, immutable): `savedIndices`, `failedIndices` (`logExercise` returned fail), `skippedIndices` (`draftExerciseSets(e).isEmpty`: no sets, only blank or unusable sets such as `DraftSet(reps: -3)`, or a cardio entry with neither duration nor distance; a cardio entry WITH a duration has its synthetic set and is logged, `conversational_log_handler.dart:244-247`, R8A-P2-2) (founder 2026-10-21), `dayMarked`, `nothingToLog`, `started` (false when `beginSubmit` refused). `keptIndices` = failed only: a failed exercise still has a loggable set, so CONFIRM is enabled and "tap CONFIRM to retry" is true (R8B-P2-1). The three signature pins at `conversational_log_handler_uses_write_service_test.dart:50,74,91` are REPOINTED to the new signature string, never loosened; `WorkoutWriteService.instance.logExercise(` and `WriteSource.aiCoach` stay INSIDE `submitWorkoutDraft`'s own body (`:48-67` reads signature to the next `\n}\n`). `zero_set_completion_behavioral_test.dart:165,182` ignore the return.
- OI-361 guard (nothing loggable): `nothingToLog: true`, no write (CONFIRM is disabled on the same predicate).
- `final draftId = draft.id;` and the container are captured before any await. **`DateTime? beginSubmit(draftId, DateTime now)`** runs first (the handler passes `DraftSubmitDebug.clock()`, `@visibleForTesting static DateTime Function() clock = DateTime.now`, so the provider file does not import the handler file, which already imports it, R8A-P3): it returns null when `state?.id != draftId` or `state!.isSubmitting`; then the handler returns `started: false` and writes nothing (double tap, R5A-P1-1 / R5B-P1-2). Otherwise it sets `isSubmitting` and returns the draft's **attempt date**: `firstAttemptAt ??= now`, stored on the draft and kept through `updateSet` and `keepFailed`. The handler uses that date as `now` for every `logExercise`, the prior-status read and `markCompleted` (today `DateTime.now()`, `conversational_log_handler.dart:283`), so a retry after IST midnight writes to the day the first attempt wrote to and never marks the new day (R7B-P2-3). A held draft starts with `firstAttemptAt: null`.
- **Every exercise is attempted.** Index-based, so a repeated name keeps the right entry. Before EACH write, and again directly before the prior-status read and `markCompleted`, the handler re-checks `container.read(workoutDraftProvider)?.id == draftId`; when it changed it RETURNS at once: no further `logExercise`, no prior-status read, no `markCompleted`, no invalidation, no `pushSnapshot` (an auth flip mid-submit must not write the old account's sets, or mark a day done, in the new account's box; R8A-P3, R9A-P2-1, R9B-P2-1).
- **The day is marked as soon as anything saved** (R8B-P1-1): Train shows logged sets only for days marked done (`week_rows.dart:78` builds the expanded row only when `isDone`; `exercise_preview_sheet.dart:22` loads logs only when `isDone`; a past not-done day shows as missed, `:134-140`), and the draft is memory-only, so a partial save followed by DISCARD, a restart or an auth change would otherwise leave saved sets invisible on Train for good. Today `markCompleted` runs unconditionally (`:314`). So after the writes, when the CUMULATIVE `savedNames` is non-empty, the handler reads the prior status through `WorkoutScheduleService.instance.getScheduleForDate(now)` (same attempt date) in try/catch → `false` on error (`getScheduleForDate` has no catch, `workout_schedule_read_service.dart:946-960`; reading it after `markCompleted` would see the status that call writes first, `:553-569`), and calls `markCompleted` only when `!wasCompletedBefore` (R8A-P2-3: `markCompleted` REPLACES `wlog_<date>` wholesale, `workout_write_service.dart:599`, dropping an earlier workout's name, duration and `rpe`; its own contract, `:541-550`, says callers skip completed days, as `_maybeCompleteScheduledDay` does, `tool_dispatcher.dart:439,446`, R9A-P3-2). Pre-existing and unchanged: `getScheduleForDate` hides moved/dropped rows, so a coach log on such a day still stamps it completed (class e8f4a3; today's behaviour, added to OI-376). The first attempt's `totalDurationSec` sums only the exercises that SAVED in it (today it sums every exercise, `:284-293`; R9A-P3-1, R9B-P3-1); a retry re-marks the day only when the first `markCompleted` failed (then with that retry's saved durations); otherwise retried timed or cardio durations do not reach `wlog_` (R10-P3). `dayMarked = wasCompletedBefore || result.success`. Failed exercises stay on the card and a retry writes into that same day. `Sets saved. Day not marked done.` therefore appears only when `markCompleted` itself fails. `keepFailed(id, failed, savedThisAttempt, {required bool dayMarked})` is called ONLY when `failedIndices` is non-empty; otherwise `markSaved` (with the skipped names, if any). A partial card whose `markCompleted` failed shows the same `warn` day line `Sets saved. Day not marked done.` above its note, inside the live region (R9A-P3-3, R9B-P3-1).
- Invalidation (the helper) and `pushSnapshot` run when at least one exercise saved OR this attempt marked the day (B-pass fb5048e68fae F1: a retry that saves nothing new but marks the day changes what Train shows). "Already done" means the schedule status is `completed` AND `wlog_<date>` exists; a completed status with no `wlog_` still gets one, as on origin/main (F5).
- `finally`: `container.read(workoutDraftProvider.notifier).endSubmit(draftId)` clears `isSubmitting` if still set (defensive; presence-pinned, reason: no reachable path throws past `markSaved`/`keepFailed`).

**State lives in the provider and is WATCHED** (R2-1, R5A-P1-1, R5B-P1-2). `WorkoutDraft` gains immutable fields: `isSubmitting` (bool), `status` (`DraftCardStatus.pending | saved | savedDayNotMarked | partial | noneSaved`), `savedNames` (for the notes), `note` (rendered line or null), `failedAttempt` (int), `firstAttemptAt` (`DateTime?`, above; the existing `date` field is the draft's creation time and stays unused by the submit), `skippedNames` (cumulative across attempts, shown on partial, none-saved and saved cards), `appliedFromHold` (bool, below), `dayNotMarked` (bool: the day line on a partial or none-saved card). Every state write goes through one private `_emit(WorkoutDraft d)` that sets `hasHeldDraft: _heldDraftData != null`, so no transition (`keepFailed`, `markSaved`, `endSubmit`, `updateSet`) can drop the notice (R8A-P2-1). The unused mutable `isSubmitted`/`isCancelled` (`ai_coach_provider.dart:1746-1747`) are removed (no readers anywhere). `WorkoutDraftNotifier`:
- `beginSubmit(id)` / `endSubmit(id)` as above; both id-guarded.
- `markSaved(id, {required bool dayMarked, List<String> skippedNames = const []})` (skipped names merged into the cumulative list): guarded; `status` saved or savedDayNotMarked, `isSubmitting: false`, starts the hold timer (`@visibleForTesting static Duration Function(bool hasNote) savedHoldFor`: 1500 ms; 4000 ms when `hasNote` = the day-not-marked line OR a Skipped line is shown, R7B-P2-1). The callback returns early when `!ref.mounted`, and when it fires on the same id it applies the HELD draft if one is waiting, else clears.
- `keepFailed(id, failedIndices, savedThisAttempt, {required bool dayMarked})`: guarded; sets the watched field `dayNotMarked: !dayMarked` (kept through `updateSet`; `markSaved` replaces it; a later successful mark clears it, R10-P2-2); keeps only the kept exercises; `savedNames` becomes the UNION of the draft's earlier `savedNames` and this attempt's (cumulative across attempts on the same id, kept through `updateSet`); `status` = partial when the cumulative `savedNames` is non-empty, else noneSaved; `note` rendered by the pure `formatDraftNote(...)` from the cumulative names; `failedAttempt + 1`; `isSubmitting: false` (R6A-P1-1, R6B-P1-2).
- **Held draft (founder 2026-10-21) and its notice (founder copy 2026-10-21):** `setDraft(data)` applies at once only when the current draft is null, or `pending` with `failedAttempt == 0` and empty `savedNames`, and not submitting. Otherwise (submitting, in the saved hold, partial, noneSaved, or a failed draft the user has since edited) it stores `data` as `_heldDraftData` (a later arrival replaces an earlier held one) and sets the WATCHED field `hasHeldDraft: true` on the current draft (R6B-P1-1). Whenever `hasHeldDraft && !isSubmitting` and `status` is not a saved state (R9A-P3-9), the card shows a `warn` line inside the live region: `coachWorkoutHeldNotice = 'New workout waiting. Confirm or discard this one first.'` (founder 2026-10-21). The held draft is applied when the saved hold ends, when the current draft is discarded, or when a retry succeeds and its hold ends; on apply, the notifier sets `appliedFromHold: true` on the new draft; the notifier has no `BuildContext`, so the ANNOUNCEMENT is sent by the card: `WorkoutLogConfirmCard.initState` (the card is keyed `ValueKey(draft.id)`, so it is a new State per draft) checks `appliedFromHold` in a post-frame callback and calls `SemanticsService.sendAnnouncement(View.of(context), <header>, TextDirection.ltr)` (precedent `active_workout/screen.dart:179-183`), then `consumeHoldAnnouncement(id)` (id-guarded) sets `appliedFromHold: false`, so scrolling the card out and back in never repeats it. If the chat is not mounted when the held draft applies (OI-232), the first mount of its card announces it then (R7B-P2-2). `build()` clears `_heldDraftData` (an auth change drops it, so it cannot cross accounts).
- `updateSet(draftId, exerciseIndex, setIndex, set)` (R7B-P3-5): does nothing when `state?.id != draftId` (the edit sheet captures the id when it opens, so a sheet left open across a new draft cannot write A's values into B by index), while `isSubmitting`, or while saved; otherwise copies with `note: null` only. `status`, `savedNames`, `failedAttempt`, `firstAttemptAt` and `hasHeldDraft` are KEPT (R6A-P1-1: an edit must not forget the partial save).
- `discard()`: clears the draft, then applies a held draft if any.
- Timer: `_cancelTimer` registered with `ref.onDispose` once per notifier instance (flag reset in `build()`); `discard()` cancels it; `hasPendingClear => _holdTimer?.isActive ?? false`. A held-draft apply happens when the timer fires, so `setDraft` never needs to cancel it (R6A-P2-2). `@visibleForTesting bool get hasPendingClear`.

**Draft ids are unique** (R8A-P3): `setDraft` builds `wdraft_<ms>_<counter>` (a static counter), because two `confirm_workout_log` actions in one response (`:1529`) (`ai_coach_provider.dart:1543`) can land in the same millisecond (`:1772`) and the `ValueKey` and every id guard would be blind.

**The draft-id guard's reachable path** (R5A-P1-2): with `setDraft` held, the only way the id changes mid-submit is an auth change (`build()` reruns on `authUserIdTokenProvider`, `:1761`). The guard test drives exactly that.

**The chat slot is a public widget** (R3A-P1-1): `lib/features/ai_coach/widgets/workout_draft_slot.dart` `WorkoutDraftSlot` builds `WorkoutLogConfirmCard(key: ValueKey(draft.id))` while the draft is non-null; `hasWorkoutDraftSlot(d) => d != null` feeds `chat_area:29`'s count; `chat_area:138-139` builds `const WorkoutDraftSlot()`.

**Scroll** (R4A-P1-1): pure `workoutDraftChangeScrolls(prev, next) => next != null && prev?.id != next.id`, called by `screen.dart:454-456`.

**Card** — `cardStateFor(WorkoutDraft d)` (pure; reads `status` and `isSubmitting`) is CALLED by `build`:
| state | header (`:67-70`) | bottom row | rows |
|---|---|---|---|
| pending | `Workout ready to log` | CONFIRM / DISCARD | pencils live |
| submitting | unchanged | spinner; DISCARD without a tap action | pencil slots kept, pencils hidden (`Visibility(maintainSize…)` + `ExcludeSemantics`, so wrapped rows do not reflow, R5B-P3) |
| saved | `coachWorkoutLoggedHeader = 'Workout logged'` | `coachWorkoutLogged = 'WORKOUT LOGGED'` + trailing `Icons.check_circle` (size 18, `AppColors.ok`), mono, letterSpacing 1.6 | only exercises with a loggable set, and the `N EX` chip counts only those (R5B-P2-4); pencils hidden |
| saved, day not marked | `Workout logged` | `warn` line `coachWorkoutDayNotMarked = 'Sets saved. Day not marked done.'` above the saved row | as saved |
| partial with `dayNotMarked` | unchanged | the same day line above the partial note, inside the live region | as partial |
| partial | unchanged | `warn` note `coachWorkoutLogPartialTemplate = 'Partly logged: {saved}. Not saved: {names}. Fix the sets or tap CONFIRM to retry.'` above CONFIRM / DISCARD | kept exercises; pencils live |
| none saved | unchanged | `warn` note `coachWorkoutLogFailed = 'Not saved. Fix the sets or tap CONFIRM to retry.'` above CONFIRM / DISCARD | failed exercises; skipped ones are not kept; pencils live |
| DISCARD tapped while the cumulative `savedNames` is non-empty (any status) | unchanged | the button row swaps (card-local state) for the confirm row: the line `coachWorkoutDiscardRestTemplate = 'Discard the rest? {saved} stays logged.'` at full width inside its own live region, then DISCARD / KEEP (`coachWorkoutKeepLabel = 'KEEP'`), 44 dp each, stacked on the same large-text rule; KEEP sits where the original DISCARD was, so a quick double tap lands on KEEP (R6B-P2-1) — AS BUILT (measured by B-pass fb5048e68fae F3): the question line pushes this row down, so the second tap lands on that inert line, never on DISCARD; the widget test pins that property at 1.0 / 1.5 / 2.0, and the founder kept this layout (2026-10-21); DISCARD discards, KEEP restores the row | unchanged |
- `{saved}` / `{names}` (pure `formatDraftNote` and `formatDiscardRest`): names joined `, `, de-duplicated within each list, at most five then `activeFinishMoreTemplate` (`wardroom_copy.dart:239`). With two or more saved names the discard line reads `… stay logged.` (verb agreement only; checked correct for every count including `+N more`, R6B-P2-1). `Not saved:` names only FAILED exercises. Skipped exercises are never kept on the card; whenever the cumulative `skippedNames` is non-empty the card shows, in `textDim` under the note (partial, none saved) or the saved row (saved states) and INSIDE the live region, `coachWorkoutSkippedTemplate = 'Skipped: {names} (no usable sets).'` (founder 2026-10-21, reworded from `(no sets)` so it is true for an exercise that has only unusable sets, R7B-P3-2 / R8B-P2-1), with the 4 s hold in the saved states. To log a skipped exercise the user asks the coach again (a held card if this one is still open).
- DISCARD closes at once only when the cumulative `savedNames` is empty (nothing was ever saved from this card) (R6B-P1-2).
- **Re-announce every failure** (R5B-P1-3): the live region (`Semantics(liveRegion: true, container: true)`) wraps the note, the held notice, and in the saved states the day line, the Skipped line and the saved row (so TalkBack hears `Sets saved. Day not marked done.` and `Skipped: Plank (no usable sets).` too, R6B-P2-4, R7B-P2-1). It is keyed `ValueKey(failedAttempt)`, so each `keepFailed` makes a new live node even when the text is the same. The note fades in over 200 ms with the `FadeTransition` INSIDE the `Semantics` container (a fade at opacity 0 outside it would drop the node, R6B-P3).
- **What to fix is visible and fixable** (R4B-P2-1, R5B-P1-4): `_ExerciseRow._summary` (`workout_log_confirm_card.dart:173`) names the bad set (the first set that `draftExerciseSets` drops or that carries a negative value, R8B-P3) when one exists (`set 2: 8 @ -5.0kg`), else keeps today's summary, with any non-zero weight shown (R6A-P3). The edit sheet shows its weight field when the exercise is weighted OR any set carries a non-zero weight (`:378-379` today shows it only for `weight_reps` / `weighted_bodyweight`, while `_save` still writes the hidden controller's seeded value back, `:313-316,338`). Input (R6B-P2-2, probe-measured: a trimming formatter silently changes `1.2.5` to `1.2` and `8.5` to `85`): a pure `TextInputFormatter` that returns `newValue` unchanged when `newValue.text == oldValue.text` (a composing commit, so Gboard never loops, `editable_text.dart:4528-4533`, R8B-P3), ACCEPTS the new value when it is a DELETION of the old one (`new.length < old.length` FIRST, then common prefix `p` and `old.substring(p + old.length - new.length) == new.substring(p)`; without the length guard `'' → 'a'` throws `RangeError` and `'1' → '11'` passes as a deletion, R8A-P1-2), or when it fully matches `^\d*\.?\d*$` (weight, `,` mapped to `.`) or `^\d*$` (reps); anything else returns `oldValue`, so a bad keystroke or paste is rejected, not trimmed. The deletion clause is what lets backspace walk the seeded `-5.0` down to `-5.`, `-5`, `-` and empty (R7B-P1-1, probe 2026-10-21: the regex alone returned the old text on every backspace). Intermediate values parse as `_save` expects (`double.tryParse('-5.')` = -5.0, `'-'` = null, probe 2026-10-21); a still-negative value saves as it is and fails again with the note, which is the honest outcome. A negative seeded value is shown as-is so the user can see and replace it. Odd but honest outcomes, stated (R8B-P3): after backspacing to `-`, a typed digit is rejected (clear the `-` first); deleting the `.` of `-5.0` gives `-50`, which fails again with the note; `-.0` parses to `-0.0`, which passes the `>= 0` check and logs 0 kg.
- **The edit sheet holds no `WidgetRef` across a rebuild** (R8A-P1-1): `_save` today calls `widget.parentRef.read(workoutDraftProvider.notifier)` (`workout_log_confirm_card.dart:334-335`) with `_ExerciseRow`'s ref, which throws `StateError` once a new draft has replaced the card (riverpod `consumer.dart:454-461`; class `b7f3e2`). `_ExerciseEditSheetState.initState` captures `_draftId` and `_notifier = parentRef.read(workoutDraftProvider.notifier)` (safe: the notifier instance is reused, §1), and `_save` uses only those two.
- Known, stated: the edit sheet has no duration field for timed sets (pre-existing, `:376-447`); an unusable timed set is skipped, and a failed timed exercise is retried as it is.
- **Pencil** (R4B-P2-1, R5B-P1-1): exactly the `log_undo_toast.dart:92-104` shape: `Semantics(button: true, label: 'Edit {name}' (WardroomCopy.coachWorkoutEditSemanticsTemplate, founder-approved), onTap: () => _showEditSheet(...), excludeSemantics: true)` → `GestureDetector(behavior: HitTestBehavior.opaque)` → `ConstrainedBox(minWidth: 44, minHeight: 44)`. DISCARD and KEEP get the same 44 dp minimum height (R5B-P3).
- **Button styles and labels** (R7B-P3-1, R7B-P3-4): the confirm row's DISCARD (left, where the solid CONFIRM was) uses the Wardroom danger look (`bad` text and a 1 px `bad` border, `wardroom/CLAUDE.md:42`, `WardButtonVariant.danger`), never the solid accent; KEEP keeps today's DISCARD look (`textDim` mono). Each button's `Semantics` has an explicit `label` because the child is excluded: CONFIRM `'Confirm and log workout'` (`coachWorkoutConfirmSemantics`), while submitting `'Saving workout'` (`coachWorkoutSavingSemantics`), DISCARD `'Discard'`, the confirm row's DISCARD `'Discard the rest'`, KEEP `'Keep'` (TalkBack would otherwise read the middle dot). These five labels were approved by the founder 2026-10-21.
- **Buttons at large text** (R4B-P2-4): `MediaQuery.textScalerOf(context).scale(10) >= 15` stacks CONFIRM full width above DISCARD (1.5× and up; probe: 1.5 is 5 lines, 2.0 is 11 lines in the test font today).
- `HapticFeedback.lightImpact()` only on `saved` / `savedDayNotMarked`.
- The typed `log_set` pill stays ~2 min (`screen.dart:105-110`); this card's saved state 1.5 s (4 s with the day line), like `LogConfirmCard` (evidence for the founder, not a change).
- `_ExerciseRow` drops `overflow: TextOverflow.ellipsis` on the name (`:236`).
- Known, stated: `wlog_`'s duration covers the first attempt's saved exercises only (durations count only for timed and cardio).
- Known, stated (R9B-P3-3): an edit clears the partial note (`note: null`); the card keeps the Skipped line, the kept rows and the DISCARD confirm, and `status` stays partial.
- Known, stated (R10-P3): `logExercise`/`markCompleted` resolve the raw `HiveService.instance.workoutBox` (`hive_service.dart:227`) after `await _acquireLock`; an auth flip inside that await is not covered by the re-check, and the immediate return leaves sets already written to the old account on an unmarked day. Narrow window; stated.
- Known, stated (R9B-P3-5): DISCARD is disabled while submitting and no path hangs (the write locks release in `finally`, `workout_write_service.dart:288,625`), so no watchdog is added.
- Known, pre-existing (R9B-P3-6): on a day Train treats as rest, the rest row is shown before the done check (`week_rows.dart:131-133`, `plan_engine_flags.dart:499-503`), so coach-logged sets there stay hidden after `Workout logged`, as today; and a dropped set inside a logged exercise is not named on the saved card.
- Known, stated (R7B-P3-6): the held notice says "Confirm or discard" even when CONFIRM is disabled because no kept exercise has a loggable set; DISCARD is always there, so the line is never a trap.
- Known, stated (R8B-P3): a retry after IST midnight writes to the first attempt's day, and the saved card does not name that day; Train shows that day done and nothing new for today.
- Known, stated: after a partial save, if the user edits a failed exercise down to no usable set, CONFIRM disables and the existing `coachDraftNoSets` line shows (`:92-98`); DISCARD (with its confirm) still exits.
- Known, stated (R7B-P3-7): when the prior-status read throws it counts as not done, so `Sets saved. Day not marked done.` can show for a day that was already done; the read throws only when the schedule box is unavailable, the same case in which `markCompleted` fails.

### C: readable rows in the expanded day
- **Extraction (R1A-4):** the row becomes a public top-level widget in the part file, `ExpandedExerciseLogRow({required String name, required String detail, required bool isPr})`. Precedent: `daySwapRowTrailingSlot`, `week_rows.dart:28`. This makes it testable in isolation.
- **Layout:**
  - `Row(crossAxisAlignment: start)`
  - `[Padding(top: 2, Icon), SizedBox(8), Expanded(Column(mainAxisSize: min, crossAxisAlignment: start, [Text(name), SizedBox(2), Text(detail)]))]`
- **Name:** no `maxLines` and NO `overflow` (R2A-6: ellipsis without `maxLines` still clips to one line, `didExceedMaxLines=true`). It wraps fully (R1B-1). The row sits in an unbounded Column inside a scroll view, so height costs nothing, and coach-made names have no length cap.
- **Detail:** also wraps (no `maxLines`). Number and unit are joined with a non-breaking space (U+00A0) and each separator is U+00A0 + `·` + a normal space, so a wrap falls only AFTER a dot, never between `12` and `reps` and never at the start of a line (R2B-7, R3B-P3). `setCountLabel`/`repCountLabel` return the non-breaking form (`1\u00a0set`); the preview sheet gets the same strings, harmless there (R3A-P2-4). The rule applies to EVERY branch, named: timed `N sets · best 1m 30s` (`expanded_exercises.dart:83-84`), cardio `N min · X km` (`:88-89`), weight (`:92`), reps-only (`:94`) (R4B-P3).
- **Styles:**
  - name: bodySm 11 (DM Sans via AppTypography);
  - detail: monoXs, textDim, letterSpacing 1.2. This is the existing mono style; the plan does not call it DM Sans.
  - no new colours.
- **Icon:** size `MediaQuery.textScalerOf(context).scale(13)` so it tracks the first line at 2.0; the test asserts its centre is within 3 px of the name's first-line centre at 1.0, 1.3 and 2.0 (R2B-7).
- **Accessibility (R1B-3, R2-5):** the trophy gets `semanticLabel: WardroomCopy.personalRecordSemantics` (`'Personal record'`; TalkBack strings in `WardroomCopy` use the `…Semantics` suffix, `activeLoggedSemantics` at `:160`, R4B-P3), and the row is wrapped in `MergeSemantics`. The real merged order is PR first: `Personal record`, newline, the name, newline, the detail (measured by R2B); the test asserts that exact label, building the expected detail with `String.fromCharCode(0xA0)` (§4.9 invisible-character row).
- **Plural (R1B-8, R2-6):** a shared pure helper `lib/features/train/utils/set_count_label.dart` (`setCountLabel(int)` → `1 set` / `N sets`; `repCountLabel(int)` → `1 rep` / `N reps`), used at the two branches that need it in `expanded_exercises.dart` (weight `:92`, reps-only `:94`; the timed branch `:83-84` already omits the count at 1) and the same logged-history lines in `exercise_preview_sheet.dart:178,180` (`:170` is the timed branch, already guarded by `sets > 1`; R3A-P3). Planned-prescription and receipt renderers (`exercise_card.dart:753-772`, `workout_receipt_card.dart:813-828`, `preview_workout_screen.dart:400`, ...) are listed in the "1 sets" OI.
- **Spacing (R1B-9):** row gap 6 → 8.
- **Doc fix (R1B-7, R2B-8):** `lib/shared/widgets/wardroom/CLAUDE.md:121` wrongly says `WardSetChips` is used by the Train expanded view, and its `:35` lists `textDim = 0xFF8A9BAA` while `colors.dart:103` is `0xFFB5BDCB`. Correct both. Adopting `WardSetChips` here is a design change and is not proposed.

## 3. Tests (each fails before the fix; mutation-proven, rule 21)

### B behavioural: `test/contracts/coach_chat_log_train_refresh_behavioral_test.dart`
This is promoted from the scratch reproduction. **`test/scratch_obs3/` is deleted in this batch**, because its offstage case is red today.
- Setup: real Hive, the real `TrainScreen`, today already DONE with two logged exercises, today's row expanded.
- Cases:
  - **chat path:** `submitWorkoutDraft` (Bench 3×8×60), with the provider SEEDED with the same draft through the seed notifier in EVERY chat-path case (otherwise `beginSubmit` refuses and nothing is written, R6A-P3). Assert the row is visible after `pump`, with no manual invalidate.
    - Train visible.
    - Train inside `Offstage` + `TickerMode(false)`, then shown again.
  - **tool path control:** the same through `ToolDispatcher.execute` with a log_set intent.
  - **disposed card:** the card is unmounted mid-submit, and the row still refreshes.
- **disposed card** (R2A-2 recipe; the provider is SEEDED with `d` through the seed notifier so the draft-id guard does not make the assertions vacuous, R4A-P2-4; assert `status == DraftCardStatus.saved` before the hold and null after): `await tester.runAsync(() async { f = submitWorkoutDraft(d, ref); await Future<void>.delayed(Duration.zero); });` → unmount the Consumer → `pump` → `await tester.runAsync(() => f)`; assert no throw and the row refreshed; then `await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1600)))` + `pump` (the hold timer is a REAL timer because the submit ran inside `runAsync`, R3A-P1-1) and assert the draft is null. Every chat-path case ends the same way so no timer outlives the container (R3B-P3).
- **Riverpod debug assertion (R1A-1, R2A-3):**
  - In the offstage cases, Riverpod 3.2.1 raises `actualPausedCount == expectedPausedCount` on resume. R1A reproduced it with pure Riverpod and no app code, so it is upstream. Today only the tool path raises it offstage; the chat path starts raising it once it invalidates `currentPlanProvider`.
  - Riverpod reports it through `Zone.current.handleUncaughtError` captured when the container is built (`provider_container.dart:679-688,753`), and overriding `FlutterError.onError` trips the binding's `_pendingExceptionDetails` assertion. So the container is built inside a zone (R2A-verified, 5/5 green):
    ```dart
    final testZone = Zone.current; late ProviderContainer c;
    runZonedGuarded(() { c = ProviderContainer(overrides: [...]); }, (e, st) {
      if ('$e'.contains('actualPausedCount == expectedPausedCount')) pausedAsserts.add(e);
      else testZone.handleUncaughtError(e, st);
    });
    ```
    `ProviderContainer(onError:)` is `@internal` (analyzer warning blocks a push), so it is not used.
  - **Collector self-test:** an unrelated error thrown inside the zone is forwarded to the test zone and fails a guarded probe (proves the filter is narrow).
  - The offstage tool-path case asserts the assertion fired (a tripwire: a Riverpod bump that fixes it turns the case red, which is the OI's `reopen_when`, said in the test comment); every other error fails the test.
  - The OI is minted `upstream_blocked` (`reopen_when: riverpod > 3.2.1`) with the roughly 25-line pure-Riverpod repro.
  - The offstage cases are never skipped.

### B unit: `test/contracts/workout_surface_invalidation_test.dart`
- A recording callback shows the helper invalidates exactly the seven providers, and that one throwing invalidation does not stop the rest.
- A source pin shows that the dispatcher, `submitWorkoutDraft` and the prompt handler all call the helper.

### B' widget, through the real slot: `test/ai_coach/workout_log_confirm_card_saved_signal_test.dart`
Harness: fonts first; **seed notifier** (R8A-P2-4): a test subclass of `WorkoutDraftNotifier` whose `build()` calls `super.build()` (so it watches auth and resets every private field) and returns the seed only on its FIRST build, null afterwards; the existing `_SeededDraft.build() => seed` (`zero_set_completion_behavioral_test.dart:28-33`) skips `super.build()` and cannot drive the auth-flip cases. Auth flips use `container.updateOverrides` (riverpod `provider_container.dart:1035`); `setUp` clears `workoutBox` only once Hive is open; the closed-box case reopens with `Hive.openBox(HiveUserSession.namespacedBoxName(HiveService.workoutBoxName, kTestUserId))` inside `runAsync` (`openForUser` is a no-op for the current owner, `hive_user_session.dart:158-166`; R5A-P2-1). A `ListView` builds `const WorkoutDraftSlot()` at a fixed index over a real Hive temp dir; taps that write run in `tester.runAsync`; `savedHoldFor` is shortened in setUp and restored in tearDown. Mid-submit states are observed through `@visibleForTesting static Completer<void>? debugSubmitGate`, a static on `ConversationalLogHandler`'s file-level holder `DraftSubmitDebug` in `conversational_log_handler.dart`, awaited right after `beginSubmit` (null in production) (R5A-P3, R6A-P3).
- **Saved:** header `Workout logged`, `WORKOUT LOGGED` + tick in the same frame, a live-region container node, pencils hidden; after the hold the slot is empty.
- **Submitting (gate held):** spinner shown; CONFIRM's button node reads `Saving workout` and is disabled and DISCARD reports `isEnabled == false` (both wrapped in `Semantics(button: true, enabled: …, onTap: …, excludeSemantics: true)`, the `log_undo_toast.dart:92-104` shape, R6B-P2-3); pencils hidden with their slots kept (`Visibility(maintainSize: true, maintainAnimation: true, maintainState: true)` + `ExcludeSemantics`). **Second submit** (R6A-P2-1): a direct `submitWorkoutDraft(d2, ref)` with the same id but reps 9, while the gate is held → `started == false`; after release each exlog row holds only the original 8-rep sets.
- **Partial:** draft [Bench 3×8×60, X `DraftSet(weightKg: -5, reps: 8)`, Row 3×10×40] → Bench and Row exlog rows, one `wlog_` (the day is marked, R8B-P1-1), draft holds only X (the `keepFailed` detector), note text exact, X's row shows `-5.0kg`, its pencil node is labelled `Edit X` and HAS `SemanticsAction.tap`, performing it opens the sheet. Retry with -5 still in place → `failedAttempt` 1→2 and the live-region node's key changes. Edit X to 5 kg → note clears → CONFIRM → saved, still one `wlog_`, unchanged.
- **Bodyweight bad weight** (R5B-P1-4): `[Pull-up, bodyweight_reps, DraftSet(weightKg: -20, reps: 8)]` → fails; the sheet shows the weight field; set it to 0 → retry saves.
- **None saved:** box closed → `Not saved…` note, all kept, no rows.
- **Day not marked, end to end:** `[Plank, timed, DraftSet(reps: 8, durationSecs: -100)]` → saved header, the day line, one exlog row, no `wlog_`, 4 s-class hold (OI-382 note in the comment). Already-completed today → no day line.
- **Held draft** (founder): (a) `setDraft(B)` while A's gate is held → A finishes saved, A's hold, then B appears and its header is announced; (b) `setDraft(B)` while A is partial → A stays with the held notice visible; DISCARD → confirm row → DISCARD → B appears; (c) KEEP restores A's buttons; (d) two arrivals while held → only the latest applies; (e) A partial, the user edits X, then `setDraft(B)` → B is held and the notice shows.
- **Cumulative save memory** (R6A-P1-1, R6B-P1-2): partial (Bench, Row saved) → retry with -5 still in place → note still `Partly logged: Bench Press, Row. Not saved: X. …` and DISCARD asks first; partial → edit X → DISCARD asks first.
- **Skipped leftover:** [Bench ok, Plank with zero sets] → `saved` with `Skipped: Plank (no usable sets).` inside the live-region node (exact label), the 4 s-class hold, no partial note, CONFIRM not shown, one `wlog_` (R7B-P2-1).
- **Unusable sets are skipped** (founder 2026-10-21): [Bench ok, X `DraftSet(reps: -3)`] → `saved` with `Skipped: X (no usable sets).`; X not kept.
- **Cardio is not skipped** (R8A-P2-2): [Bench ok, Run cardio 20 min] → both logged, no Skipped line.
- **Skipped survives a retry** (R8A-P2-2): [Bench ok, X failed (-5 kg), Plank empty] → partial with `Not saved: X` and `Skipped: Plank (no usable sets).`; edit X; CONFIRM → saved, and the Skipped line still shows.
- **Partial marks the day** (R8B-P1-1): the partial case above → one `wlog_` after the FIRST attempt; the retry does not rewrite it (its `workout_name` and `completed_at` unchanged).
- **Already-done day is not overwritten** (R8A-P2-3): seed a `wlog_` for today with `workout_name: 'Push Day'` and status completed → submit → `wlog_` unchanged, no day line.
- **Auth flip mid-submit** (R8A-P3, R9A-P2-1): gate held (it sits right after `beginSubmit`, before any write); flip auth; release → no `exlog_` and no `wlog_`/`schedule_` for the date in the box (the token override does not switch the Hive owner, so both "accounts" share one box; the assertion is on that box, R10-P3).
- **Auth flip on a retry, after the writes** (R9A-P2-1, R10-P2-1): a second test hook `DraftSubmitDebug.debugBeforeMarkGate` (a `Completer<void>?`, null in production) is awaited after the write loop and BEFORE the pre-`markCompleted` re-check. Seed a partial draft (`savedNames: ['Bench Press']`, X failed, no `wlog_`); fix X to 5 kg; CONFIRM; while `debugBeforeMarkGate` is held, flip auth; release → X's exlog row exists, and there is no `wlog_`/`schedule_` for the date.
- **Partial, day not marked** (R10-P2-2): `[Plank timed durationSecs -100 reps 8, X -5 kg]` → partial card with `Sets saved. Day not marked done.` inside the live region; edit X → the line stays; fix X, retry → the day is marked and the line is gone.
- **Id guards, direct** (R9A-P2-2, R10-P2-3): B is applied from the hold (`appliedFromHold: true`) and its `debugSubmitGate` is held (so `isSubmitting` is true); call `markSaved`, `keepFailed`, `endSubmit` and `consumeHoldAnnouncement` with A's id; call `updateSet` with A's id while B is NOT submitting (the stale-sheet case also covers it); after each → `identical(state, before)`.
- Auth flips use `authUserIdTokenProvider.overrideWithValue(...)` in `container.updateOverrides` with the full, same-length override list (`overrideWith` does not rebuild, probe R9A).
- **Held during a submit that ends partial** (R8A-P2-1): `setDraft(B)` while A's gate is held; A ends partial → the held notice is visible.
- **Retry after IST midnight** (R7B-P2-3): `DraftSubmitDebug.clock` returns D 23:59 IST; partial (X failed) → clock moves to D+1 00:05 IST; edit X; CONFIRM → X's exlog row and the `wlog_` are dated D; nothing is written for D+1.
- **Stale edit sheet** (R7B-P3-5, R8A-P1-1): B has an exercise at X's index with at least as many sets (so `updateSet`'s bounds checks, `ai_coach_provider.dart:1781-1783`, cannot hide the mutation); open X's sheet on draft A, `setDraft(B)` applies (A discarded), save the sheet → NO exception (`tester.takeException()` is null) and B unchanged (`identical`).
- **Held announcement** (R7B-P2-2): in held case (a), the `SystemChannels.accessibility` mock receives exactly one `announce` message with B's header; scrolling B's card out and back in sends no second one.
- **Live regions:** the confirm row's line, the held notice and the day line each surface as a live-region node with the exact label (asserted after the first pump, so the fade cannot hide them).
- **Draft-id guard via auth** (R5A-P1-2): gate held; flip the overridden `authUserIdTokenProvider` → `build()` reruns, draft null; `setDraft(B)` on the fresh state; release the gate → B is NOT saved-styled and keeps CONFIRM.
- **Discard after partial:** confirm line text exact for one and for two saved names.
- **Timer cancel** (R6A-P2-2): `discard()` during the hold → `hasPendingClear` false; an auth flip during the hold → read `workoutDraftProvider` (the rebuild is lazy) → `hasPendingClear` false (through `onDispose`). The harness uses `UncontrolledProviderScope` so a `ProviderScope` rebuild cannot reapply the old overrides (R10-P3).
- **Formatter** (pure): 7 names → five + ` +2 more`; repeated names de-duplicated; skipped exercises never appear under `Not saved:`.
- **Input formatters:** typing `.` into `12.5` keeps `12.5`; typing `-` keeps the old text; reps keeps `8` when `.5` is typed; `,` becomes `.`; pasting `a` over a selected `12.5` keeps `12.5`; clearing the field is allowed. **Backspace from a seeded negative** (R7B-P1-1): with the sheet open on `-5.0`, `tester.testTextInput.updateEditingValue` to `-5.` then `-5` then `-` then empty → each value is kept (driven key by key; `enterText` also runs the formatters but jumps straight to the final text); the same for reps `-3` → `-` → empty. Guard cases (R8A-P1-2): `''` → `'5'` kept, `''` → `'a'` rejected with no exception, `'-'` → `'--'` rejected, `'1'` → `'11'` kept (regex). A composing commit with unchanged text on `-5.0` returns it unchanged (R8B-P3).
- **Held card tap guard** (B-pass fb5048e68fae F4): a card applied from hold ignores CONFIRM for `kHeldCardTapGuard` (500 ms, real time), so the second tap of a double tap on the wide left "Discard the rest" cannot log a card the user never saw.
- **Button labels:** the semantics labels of CONFIRM, the submitting state, DISCARD, the confirm row's DISCARD and KEEP are the exact strings above.
- **`cardStateFor` truth table** (pure) and **scroll truth table** (pure) as rev 5; pins: `chat_area.dart` has `const WorkoutDraftSlot()` and `hasWorkoutDraftSlot(`; `screen.dart`'s listener calls `workoutDraftChangeScrolls(`.
- **Large text:** the card at 320 dp × {1.0, 1.3, 1.5, 2.0} (expectations written against the test font): no exception; at 1.5 and 2.0 CONFIRM is stacked full width. The densest state (partial note with five saved and five failed names + the Skipped line + the held notice) at 320 dp × {1.0, 1.3, 2.0}: no overflow and `didExceedMaxLines == false` on every line (R9B-P3-4; the no-overflow check is the real assertion, `didExceedMaxLines` is a tripwire against a future `maxLines`).

### C widget: `test/features/train/expanded_exercise_log_row_test.dart`
- Cases: at 320 dp × {1.0, 1.3, 2.0}, for `Barbell Overhead Press`, `Thoracic Extension (Foam Roller)` and a 60-character custom name.
- Assertions:
  - the name's `RenderParagraph.didExceedMaxLines` is false and its text is complete;
  - the detail is present and wraps at 2.0;
  - no overflow exception;
  - the icon's top is within 4 px of the name's top;
  - the icon centre is within 3 px of the first-line centre at each scale;
  - semantics: the merged label equals `"Personal record\nBench Press\n3 sets · 8 reps · 60.0 kg"` exactly when `isPr`;
  - `1 set` / `3 sets`, `1 rep` / `8 reps`, through both the weight and the reps-only branches;
  - at 2.0, `12\u00a0reps` never splits across lines.
- Unit test `test/features/train/set_count_label_test.dart` for the helper.

### Other test work
- **Source-grep sweep (§4.9):**
  - `sync_gap_test.dart:46`: the comment about `onInvalidate` is updated.
  - `tool_dispatcher_day_swap_invalidation_test.dart`: it is behavioural, so it survives.
  - SoT ranges use `1-9999`, so lines can move.
- **Mutations:**
  - `submitWorkoutDraft` back to its 3 invalidations → behavioural red;
  - helper missing `currentPlanProvider` → behavioural + unit red;
  - helper missing `lastPerformanceProvider` → unit red;
  - dispatcher or prompt handler not delegating → pin red;
  - container capture removed → disposed-card case red;
  - saved state removed or shown on failure → B' slot test red;
  - `maxLines: 2` re-added → C red at 2.0;
  - detail back on the name's line → C red at 320 dp;
  - `semanticLabel` removed → C red;
  - `overflow: ellipsis` re-added to the name → C red;
  - saved state back to a widget-local flag (slot renders shrink once the provider clears) → B' saved case red;
  - `submitWorkoutDraft` ignores the `logExercise` result → B' partial case red (no note, draft cleared);
  - `keepFailed` not called (whole draft kept) → B' partial case red (draft holds 3, retry duplicates Bench/Row);
  - `markCompleted` NOT run on a partial save → partial-marks-the-day case red (no `wlog_`);
  - `!wasCompletedBefore` gate removed → already-done case red (`workout_name` becomes `Chat Workout`);
  - deletion clause without the length guard → guard cases red (`RangeError`, `'-'` → `'--'` accepted);
  - `_save` reading `widget.parentRef` → stale-sheet case red (exception);
  - `_emit` not deriving `hasHeldDraft` in `keepFailed` → held-during-partial case red;
  - per-write id re-check removed → auth-flip-mid-submit case red;
  - cardio classified by `sets.isEmpty` → cardio case red;
  - any id guard removed (`markSaved`, `keepFailed`, `endSubmit`, `consumeHoldAnnouncement`, `updateSet`) → id-guards-direct case red;
  - id re-check before `markCompleted` removed → auth-flip-on-a-retry-after-the-writes case red;
  - `keepFailed` ignoring `dayMarked` → partial-day-not-marked case red;
  - `savedNames` per attempt instead of cumulative → cumulative-memory case red;
  - `updateSet` resetting `status` → edit-then-DISCARD case red (it asserts `status == DraftCardStatus.partial` after the edit) (R9A-P2-3);
  - held notice not rendered (or `hasHeldDraft` a private field) → held case (b)/(e) red;
  - skipped leftover routed to `keepFailed` → Skipped-leftover case red;
  - trimming input formatter → input case red (asserts the old text is kept);
  - formatter deletion clause dropped → backspace-from-negative case red;
  - retry uses `clock()` instead of `firstAttemptAt` → retry-after-midnight case red;
  - Skipped line outside the live region (or `hasNote` ignoring it) → Skipped-leftover case red;
  - `consumeHoldAnnouncement` not called → held-announcement case red (second message);
  - `updateSet` without the draft-id check → stale-sheet case red;
  - an unusable-set exercise kept on the card instead of skipped → unusable-sets case red;
  - DISCARD/CONFIRM without `enabled:` semantics → submitting case red;
  - submitting as a notifier field instead of draft state → B' submitting case red;
  - `beginSubmit` not refusing a second submit → second-tap case red;
  - pencil `Semantics` without `onTap` → partial case red (no tap action);
  - live region not keyed by `failedAttempt` → re-announce assertion red;
  - weight field still hidden on a non-weighted row with a weight → bodyweight case red;
  - held draft applied immediately (not held) → held-draft cases red;
  - discard-after-partial without the confirm → discard case red;
  - `clearDraft`/`markSaved` through `ref` instead of `container` → disposed-card case red;
  - per-entry try/catch collapsed into one → unit test red (one throwing entry stops the rest);
  - collector accepts any error → a deliberately injected unrelated error is swallowed → collector self-test red;
  - `onDispose` cancel removed → timer-cancel auth-flip case red;
  - `updateSet` allowed while saved → B' saved case red: `identical(c.read(workoutDraftProvider), before)` after `updateSet(draft.id, 0, 0, DraftSet(weightKg: 99, reps: 1))` on a saved draft (R4A-P2-1);
  - `workoutDraftChangeScrolls` back to `next != null` → scroll truth-table red (R4A-P1-1);
  - day-not-marked note passed when `dayMarked` (or not passed when `!dayMarked`) → B' day-not-marked case red;
  - `dayMarked` ignores an already-completed day → the already-completed case red;
  - names not de-duplicated → repeated-name case red;
  - plural helper reverted → helper + C red.

## 4. Docs and ledgers
- **Diagnose docs:**
  - `2026-10-21-coach-chat-log-train-stale-<id>.md`: full template, recurrence; closes OI-370.
  - `2026-10-21-expanded-row-name-truncation-<id>.md`: FULL template (an M batch; avoids relying on the validator accepting `tier: s_fix` here, R4A-P3); closes OI-371.
  - `2026-10-21-coach-workout-card-false-success-<id>.md`: FULL template, recurrence (`related_bugs: [b7f3e2]` for the disposed-ref `StateError`), writers/readers of the ignored `WriteResult` (`:303/:314`) and of `clearDraft` after an unmount, `touched_layers_checked` (R4A-P2-5).
- **SoT registry:**
  - `workout_surface_invalidation`: new, with `behavioral_test_path`.
  - `exercise_logs_read_path`: add the second coach writer's refresh, and stop calling `getExerciseLogsForDate` the "Canonical reader" (`sot_registry.yaml:376-383`; it is the duplicate tracked by OI-377, R4A-P3).
  - Line ranges in existing entries (`conversational_log_handler.dart` `50-55`, `97-125`, `125-160` at `sot_registry.yaml:7502`; `chat_area.dart` `46-61`; `screen.dart` `509-516` at `:16045`) shift with new imports: `check_sot_registry_parity.dart` is re-run and the ranges repointed, not assumed free (R4A-P3).
  - `coach_workout_card_saved_state`: new (writers `WorkoutDraftNotifier.markSaved`/`keepFailed`, reader `WorkoutLogConfirmCard.build` via `WorkoutDraftSlot`, behavioral test the B' slot test).
- **Doc corrections** (R1A-11): `lib/features/train/CLAUDE.md:55` and `lib/core/services/CLAUDE.md:43` stop claiming every exlog reader delegates to `exerciseLogsForIstDate` (R2A-9: `sync.md:508` already lists `getExerciseLogsForDate` as a consumer and makes no delegation claim; it only gains the helper wording). Each names `WorkoutRepository.getExerciseLogsForDate` as a duplicate and points to its OI.
- **Feature docs:**
  - `lib/features/ai_coach/CLAUDE.md`: the saved state, the helper, and the 5-second auto-confirm note shared with the server batch.
  - `lib/shared/widgets/wardroom/CLAUDE.md:121`: the WardSetChips correction.
- **Naming** (§4.7): `workout_surface_invalidation`, `ExpandedExerciseLogRow`, `coachWorkoutLogged`, `coachWorkoutLoggedHeader`, `coachWorkoutLogFailed`, `coachWorkoutLogPartialTemplate`, `coachWorkoutDayNotMarked`, `coachWorkoutDiscardRestTemplate`, `coachWorkoutKeepLabel`, `coachWorkoutHeldNotice`, `coachWorkoutSkippedTemplate`, `hasHeldDraft`, `DraftCardStatus`, `formatDraftNote`, `beginSubmit`, `endSubmit`, `debugSubmitGate`, `personalRecordSemantics`, `coachWorkoutEditSemanticsTemplate`, `workoutDraftChangeScrolls`, `cardStateFor`, `isSubmitting`, `formatDiscardRest`, `setCountLabel`, `repCountLabel`, `markSaved`, `keepFailed`, `WorkoutDraftSlot`, `DraftSubmitOutcome`, `firstAttemptAt`, `appliedFromHold`, `consumeHoldAnnouncement`, `skippedNames`, `unloggableIndices`, `emptyIndices`, `coachWorkoutConfirmSemantics`, `coachWorkoutSavingSemantics`, `skippedIndices`, `_emit`, `dayNotMarked`, `debugBeforeMarkGate`.
- **Doc:** `lib/features/ai_coach/CLAUDE.md` gains the `submitWorkoutDraft` result contract (every exercise attempted; failures stay on the card by index with an in-card note; a new card is held while one saves or has failed; DISCARD after a partial save confirms first; draft-id guarded; submitting is draft state; a retry writes to the first attempt's date; the day is marked as soon as anything saved and an already-done day is not overwritten; unusable or empty exercises are skipped and named; the edit sheet captures the notifier and draft id at open, R8A-P1-1 / R8B-P1-1) next to the `:74` row.
- **Closure ledger:** `docs/audit/train-coach-log-refresh.closure.yaml` (B, B', C, docs: ≥4 units).
- **Plan-review record:** `docs/plan-reviews/train-coach-log-refresh.md`.
- **B-pass** `/code-review` before the merge (account, §4.3; R1A-6). It needs a tuning-history entry, and the founder's triage before `bpass: accepted`.
- **Full gate loop** before every review that carries a diff (§4.12.8).

## 5. Out of scope, each with an OI (being minted 2026-10-21)
- The dead `onInvalidate` hook, plus the remaining hand-written invalidation copies and the 6-versus-7 canonical-set drift; also `completeWorkout` not invalidating `lastPerformanceProvider`, the prompt handler skipping every invalidation on `!mounted` (`screen.dart:370`, same disposed-ref class), and `exerciseHistoryProvider` (weight sparkline) not refreshed by any coach path.
- The remaining `1 sets` renderers: OI-381.
- `WorkoutWriteService.logExercise` accepts a negative `durationSec` (only weight and reps are validated, `:119-121`): OI-382. NOTE: the day-not-marked test uses exactly this gap as its seam; when that OI is fixed, the test moves to another `markCompleted` seam (said in the test comment).
- The duplicate exlog reader `getExerciseLogsForDate`.
- The Riverpod paused-count assertion (`upstream_blocked`).
- Coach-logged workouts never increment `total_workouts_done` and never run the rank check. Invalidating `userStatsProvider` would not help, because nothing writes the count (R1B-6b).
- A distance-type row in the expanded day shows `N sets · 0 reps · X kg` (R1B-10).
- The weekly report sparkline does not refresh on a log: already OI-267 (R1B-6c).
- The two parallel coach write paths: filed by the `coach-log-truth` batch.

## 6. Release order
1. This batch merges first. The web deploy of `main` carries B, B' and C.
2. The server batch `coach-log-truth` deploys after it, because it depends on B'.
3. An APK is only built when the founder asks.

## 7. Round-1 finding map

| finding | action |
|---|---|
| R1A-1 Riverpod assertion is upstream | §3: narrow collector, keep the offstage cases, upstream_blocked OI |
| R1A-2 "one implementation" false; enumeration | §1 enumeration; §2 three callers + sync.md wording; copies OI |
| R1A-3 API signature, telemetry, false comments | §2 signature; recordNonFatal; comments removed |
| R1A-4 C test infeasible | `ExpandedExerciseLogRow` extraction |
| R1A-5 scratch dir | deleted in this batch |
| R1A-6 B-pass | §4 |
| R1A-7 layout details, monoXs | §2 C |
| R1A-8 source-grep contracts | §3 sweep; signature kept |
| R1A-9 9 hook sites | §1; OI |
| R1A-10 disposed WidgetRef | §2 container capture + test |
| R1A-11 doc drift | §4 corrections; drift noted in the OI |
| R1A-12 OIs, naming | OI-370/371 minted; §4 naming |
| R1A-13 tier reasoning | frontmatter |
| R1B-1 maxLines 2 still clips | no maxLines; tests at 1.0/1.3/2.0 with long names; mutation |
| R1B-2 icon alignment | `crossAxisAlignment: start` + top inset; test |
| R1B-3 PR semantics | semanticLabel + MergeSemantics; test |
| R1B-4 prompt-tap handler | caller 3 |
| R1B-5 sync.md wording | §2 |
| R1B-6a lastPerformanceProvider | added to the helper |
| R1B-6b totals/rank | OI |
| R1B-6c sparkline | OI-267 cited |
| R1B-7 WardSetChips doc | corrected |
| R1B-8 "1 sets" | fixed |
| R1B-9 spacing | 8 |
| R1B-10 distance detail | OI |

## 8. Round-2 finding map

| finding | action |
|---|---|
| R2A-1 / R2B-1 (P0/P1) saved flag unmounted with the chat slot | saved state in `WorkoutDraftNotifier` (`isSaved`, `markSaved`, 1.5 s timer); chat_area unchanged; test through the chat slot; mutation |
| R2A-2 (P1) disposed ref also breaks `clearDraft` | every post-await provider use via the captured container; R2A test recipe; mutation |
| R2A-3 (P1) `FlutterError.onError` collector trips the binding | container built in `runZonedGuarded`; `onError:` not used (internal) |
| R2A-4 / R2B-2 (P1/P2) no failure path, `Future<void>` | `Future<WriteResult>`; stop at first fail; `keepUnsaved` (retry not idempotent); snackbar; try/finally; pins repointed |
| R2A-5 aiInsightProvider | omitted on purpose, documented |
| R2A-6 ellipsis still clips | `overflow` removed; mutation |
| R2A-7 / R2B-5 semantics order | exact label, PR first; `WardroomCopy.personalRecordA11y` |
| R2A-8 / R2B-6 plural branches + sibling | shared helper at `:92,:94` and `exercise_preview_sheet.dart:170,178,180`; rest in an OI |
| R2A-9 sync.md:508 not false | removed from the correction list; corrections are `train/CLAUDE.md:55` and `core/services/CLAUDE.md:43` |
| R2A-10 missing mutations | added (§3) |
| R2A-11 tripwire | stated in the test comment and the OI |
| R2A-12 / R2B-9 prompt handler `!mounted`, completeWorkout lastPerformance | copies OI |
| R2B-3 scroll jump, copy shape | card frame kept, row swapped, trailing icon, live region |
| R2B-4 disposed-ref beyond invalidation | same as R2A-2 |
| R2B-7 wrap/readability at 2.0 | non-breaking spaces; scaled icon; centre test |
| R2B-8 colour drift in wardroom CLAUDE.md | corrected |
| R2B-10 stale surfaces | exerciseHistoryProvider added to the copies OI |

## 9. Round-3 finding map

| finding | action |
|---|---|
| R3A-P1-1 chat-slot test not runnable; real timer under `runAsync` | public `WorkoutDraftSlot` + `hasWorkoutDraftSlot`; ListView harness; injectable hold; real-delay waits |
| R3A-P1-2 two mutations redden nothing | negative-weight partial failure through the real `submitWorkoutDraft` (`writeDraftExercises` dropped); `hasPendingClear` |
| R3A-P2-1 / R3B-P1-1 no draft-id guard; DISCARD live mid-submit | `markSaved(draftId)`, `keepFailed(draftId, …)`; DISCARD disabled, pencils hidden while submitting/saved; test + mutation |
| R3B-P1-2 false "Not saved" on partial | in-card notes, founder copy; note in the provider (survives unmount) |
| R3A-P2-2 / R3B-P2-1 edit during saved window | `updateSet` no-op while saved; edit clears a stale note |
| R3A-P2-3 timer cleanup with overridden `build` | `ref.onDispose` inside `markSaved`; `!ref.mounted` early return |
| R3A-P2-4 NBSP vs exact label | helper output stated; expected strings via `String.fromCharCode` |
| R3A-P2-5 retry copy; first-failure stop | every exercise attempted; "Fix the sets or tap CONFIRM to retry" (founder) |
| R3A-P2-6 body pins | stated in §2 B' |
| R3B-P2-2 header contradiction | `Workout logged` header (founder) |
| R3B-P2-3 name-keyed `keepUnsaved` | indices |
| R3B-P2-4 day not marked, Train shows planned | amber line `Sets saved. Day not marked done.` (founder); 4 s hold with a note |
| R3B-P3 scroll, live region container, icon size, LAST hint wording, separator wrap, chat card name clip, timers in B tests | §2 B', §2 B, §2 C, §3 |
| R3A-P3 preview `:170`, `:619`, tier note, collector self-test | fixed |

## 10. Round-4 finding map

| finding | action |
|---|---|
| R4A-P1-1 scroll mutation unreachable | pure `workoutDraftChangeScrolls` + truth table + pin |
| R4A-P1-2 `cardStateFor(outcome)` off-path; false "no seam" | dropped; timed `durationSecs: -100` drives day-not-marked end to end; `cardStateFor(draft, submitting)` called by `build` |
| R4A-P2-1 updateSet assertion | `identical(...)` after an update on a saved draft |
| R4A-P2-2 case isolation | `setUp` clears the box; closed-box reopen |
| R4A-P2-3 retry-duplicate evidence vacuous in 60 s | draft-length is the detector; §1 corrected |
| R4A-P2-4 disposed case vacuous | provider seeded; `isSaved` then null |
| R4A-P2-5 no diagnose doc for B' | third FULL doc, `related_bugs: [b7f3e2]` |
| R4B-P2-1 bad value hidden; pencil unlabelled | `_summary` shows non-zero weights; input formatters; `Edit {name}` (founder) + 44 dp |
| R4B-P2-2 same-failure retry silent | note hidden while submitting |
| R4B-P2-3 submitting state per widget | `submittingId` in the notifier; `ValueKey(draft.id)`; `setDraft` queued during a submit |
| R4B-P2-4 CONFIRM 7 lines at 2.0 | stacked buttons at large text; test |
| R4A-P3 / R4B-P3 line drift, SoT ranges, exact label, blank exercises, repeated names, onDispose once, registry "canonical", negative duration OI, OI-371 template, queued draft note, already-DONE day, name cap, live-region scope, haptic only on all-saved, NBSP in every branch, `…Semantics` naming | folded in |

## 11. Round-5 finding map

| finding | action |
|---|---|
| R5A-P1-1 / R5B-P1-2 submitting not observable, no double-tap guard | `isSubmitting` on the draft; `beginSubmit` refuses; gate-held test; second-tap case |
| R5A-P1-2 guard unreachable once held; contradictory tests | founder: HOLD the new card; the guard tested through an auth flip; the contradictory case removed |
| R5B-P1-1 pencil not pressable by TalkBack | `log_undo_toast` shape with `onTap`, 44 dp; test performs the tap |
| R5B-P1-3 same-failure retry not announced | `failedAttempt` keys the live region; fade-in; hide-while-submitting dropped |
| R5B-P1-4 bad weight on a bodyweight row | weight field shown when any set carries a weight; bodyweight case |
| R5A-P2-1 box reopen | `Hive.openBox(namespacedBoxName(...))` |
| R5A-P2-2 prior status read | `getScheduleForDate(now)` right before `markCompleted`, try/catch |
| R5A-P2-3 partial vs none indistinct | `DraftCardStatus` on the draft |
| R5A-P2-4 `ValueKey` mutation | key kept for remount identity; its mutation claim dropped |
| R5A-P2-5 split | founder: keep one batch |
| R5B-P2-1 queued data across accounts | `build()` clears the held draft |
| R5B-P2-2 dropped draft invisible | founder: held until the current card resolves; nothing dropped |
| R5B-P2-3 formatters | digits-only reps; single-dot weight |
| R5B-P2-4 saved state shows blank rows | saved rows and chip count only exercises with a loggable set |
| founder: DISCARD after partial | confirm line with DISCARD / KEEP |
| R5A-P3 / R5B-P3 `keptIndices`, cap test, `_submit` vs handler `finally`, mid-submit seam, SoT ranges, `_summary` first bad set, DISCARD 44 dp, slot kept when hidden, large-text scales, held during the hold, `_disposeHooked` reset, shim `:1368` | folded in |

## 12. Round-6 finding map

| finding | action |
|---|---|
| R6A-P1-1 / R6B-P1-2 the card forgets an earlier partial save (failed retry, edit) | cumulative `savedNames` kept through `updateSet`; status, hold and discard-confirm keyed on it; three cases; two mutations |
| R6B-P1-1 held card invisible | watched `hasHeldDraft`; founder notice `New workout waiting. Confirm or discard this one first.`; announce on apply |
| R6A-P2-1 second-tap test could not catch the mutation | direct second call, same id, different reps |
| R6A-P2-2 timer cancel in `setDraft` unreachable | dropped; cancel tested via `discard()` and an auth flip |
| R6A-P2-3 blank exercises cannot be fixed | blank-only goes to saved with founder line `Skipped: {names} (no sets).` |
| R6B-P2-1 confirm row silent; double tap discards | live region; KEEP in DISCARD's place; 44 dp; stacked rule |
| R6B-P2-2 formatters trim | reject-not-trim formatter; tests assert the old text |
| R6B-P2-3 no button semantics | `Semantics(button, enabled, onTap)` on CONFIRM/DISCARD/KEEP |
| R6B-P2-4 day line not announced | inside the live region |
| R6A-P3 / R6B-P3 notifier reuse (probe), `_SeededDraft` everywhere, `beginSubmit` in saved states (already guarded by status), `_summary` names the bad set, `debugSubmitGate` host, node id assertion, NBSP label, fade inside semantics, `Visibility` flags, blank rows silent on full save, test font, repeated names | folded in |

## 13. Round-7 finding map (rev 8)

| finding | action |
|---|---|
| R7B-P1-1 the filter blocks backspace on the seeded `-5.0` | deletion clause (one contiguous range removed) accepted; `updateEditingValue` backspace test; mutation |
| R7B-P2-1 Skipped line not announced, 1.5 s | inside the saved live region; `hasNote` includes it (4 s); exact-label assertion |
| R7B-P2-2 held announcement has no context | `appliedFromHold` on the draft; the card's `initState` announces with `View.of`; `consumeHoldAnnouncement` makes it once; test + mutation |
| R7B-P2-3 retry after IST midnight | `firstAttemptAt` from `beginSubmit` with a `clock` seam; every write of a retry uses it; test + mutation |
| R7B-P3-1 confirm-row DISCARD style | danger look; KEEP keeps the dim look |
| R7B-P3-2 "(no sets)" false for unloggable sets | only `sets.isEmpty` goes to Skipped; unloggable kept and named under `Not saved:`; test |
| R7B-P3-3 DISCARD after partial leaves the day unmarked | stated in `ai_coach/CLAUDE.md` |
| R7B-P3-4 button labels | five explicit labels (new copy, shown to the founder) |
| R7B-P3-5 `updateSet` writes by index into a new draft | `updateSet(draftId, …)`; stale-sheet test; mutation |
| R7B-P3-6 held notice when CONFIRM is disabled | stated (DISCARD always exits) |
| R7B-P3-7 prior-status read throws | stated |
| R7A | cut off by a container restart before a verdict; re-run in round 8 |

## 14. Round-8 finding map (rev 9)

| finding | action |
|---|---|
| R8B-P1-1 partial save leaves the day unmarked; Train hides logs on not-done days | the day is marked once anything saved (dated to the first attempt); the false §4 sentence replaced; partial case asserts `wlog_`; mutation inverted |
| R8A-P1-1 stale edit sheet throws on a disposed ref | sheet captures `_draftId` and `_notifier` in `initState`; test asserts no exception then `identical`; `b7f3e2` in `related_bugs` |
| R8A-P1-2 deletion clause without a length guard | `new.length < old.length` first; four guard cases; mutation |
| R8B-P2-1 "tap CONFIRM" false when the kept exercise has no usable set; no seconds field | founder: unusable exercises are skipped, line `Skipped: {names} (no usable sets).`; only failed exercises are kept (always loggable); seconds field stated as known |
| R8A-P2-1 `hasHeldDraft` lost in `keepFailed` | one `_emit` derives it on every write; held-during-partial case |
| R8A-P2-2 cardio and Skipped-across-retry | skipped = `draftExerciseSets(e).isEmpty`; cumulative `skippedNames` on every card state; cardio and retry cases |
| R8A-P2-3 re-completion overwrites `wlog_` | `markCompleted` only when `!wasCompletedBefore`; already-done case; mutation |
| R8A-P2-4 seed helper cannot drive auth flips | seed notifier calling `super.build()`; `container.updateOverrides` |
| founder: TalkBack labels | approved |
| R8A-P3 / R8B-P3 `updateSet` arity, CONFIRM label while submitting, circular import (`beginSubmit(id, now)`), `enterText` claim, citations `:6`/`:173`, draft-id counter, auth flip mid-submit, timed sets, composing commit, formatter odd outcomes, bad-set definition, midnight retry seen next day | all folded in |

## 15. Round-9 finding map (rev 10; both reviewers converged)

| finding | action |
|---|---|
| R9A-P2-1 / R9B-P2-1 auth flip mid-submit could still mark the day in the new account | return at once on an id change (no status read, `markCompleted`, invalidation, `pushSnapshot`); re-check before `markCompleted`; two cases; mutation |
| R9A-P2-2 guard mutation reddens nothing | direct id-guard case over five methods |
| R9A-P2-3 `updateSet` status mutation reddens nothing | assert `status` after the edit; held predicate reads `status` |
| R9A-P2-4 timer mutation vacuous | `build()` does not reset the timer; `hasPendingClear` from `_holdTimer` |
| R9A-P2-5 stale "day marked only when none failed" | removed from the §4 doc bullet |
| R9A-P3 / R9B-P3 retry duration line; first-attempt duration over saved only; precedent `_maybeCompleteScheduledDay`; moved/dropped class to OI-376; partial + failed day mark shows the day line; override recipe; stale-sheet fixture; `confirm_workout_log`; `isSaved`; case names; held predicate; edit keeps Skipped line; densest large-text case; no watchdog (stated); rest-day and dropped-set gaps (stated) | folded in |

## 16. Rev-10 delta-check map (rev 11; converged)

| finding | action |
|---|---|
| R10-P2-1 pre-`markCompleted` re-check unprovable (flip always hits the per-write check first) | `debugBeforeMarkGate` after the write loop; retry case flips there; mutation now reddens |
| R10-P2-2 `keepFailed(dayMarked)` had no field, row or test | `dayNotMarked` watched field; table row; partial-day-not-marked case; mutation |
| R10-P2-3 direct id-guard fixture state | B applied from hold with its gate held; `updateSet` with B not submitting |
| R10-P3 held case (e) claim; retry re-mark wording; raw-box await window; lazy rebuild + `UncontrolledProviderScope`; one Hive box; `:541-550`; `didExceedMaxLines` as tripwire | folded in |
