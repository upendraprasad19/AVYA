---
plan: coach-workout-parity-1a
revision: 4
date: 2026-11-10
blast_radius: account   # blast_radius_from_diff on the planned existing files; the new file is under lib/features/train/services (re-classify once written, 2026-09-04 pitfall)
tier: M                 # §4.12.6: ai_coach ⇒ M
execution_mode: inline  # §4.12.7; one worktree (.claude/worktrees/coach-workout-parity)
closes_oi: [OI-379]
files_oi: []            # minted in the 1a commit, see D7
---

# Slice 1a: one "workout completed" step for every completion path

## Revision history
- **rev 3 → rev 4:** round 3 was a delta check by one reviewer, both lenses, and returned **CONVERGED** (no P0/P1). Its P2/P3 findings are folded in:
  - `newlyCompleted` also requires that no `wlog_<date>` existed before the write, so a re-completed stranded day is not +1 on top of a heal that already counts it (R3-F4).
  - The owner is re-checked before steps 4-5 (R3-F3).
  - The offline cost of the restore gate is stated (R3-F1).
  - 1b gets its own ×2 review, and the record lists both plans (R3-F2).
  - Test seams and the settled marker in setUp (R3-F5).
  - The date check follows the precedent (R3-F6).
  - Mapping in §9.
- **rev 2 → rev 3:** round 2 had two reviewers, A (ground truth) and B (exposure); both said `needs-changes`. Folded:
  - **Merge order (B-R2-P1):** 1a and 1b ship in ONE merge. On its own, 1a would let the chat card's mark-on-any-save count a one-exercise day, and the count, the weekly streak and the marker are all monotonic (max-wins restore, `GREATEST` on push), so the over-count would be permanent.
  - **Distinct-date heal (A-R2-P1):** legacy `wlog_<ms>` duplicates must not double a day.
  - **Owner captured at each door's ENTRY (A-R2-P1):** not before the mark, which comes after the `logExercise` awaits.
  - **Restore unsettled (B-R2-P2):** only the monotonic count runs.
  - **The heal helper lives in core** (`WorkoutReadService`), and `BadgeService` uses it too (A-R2-P2).
  - **The `check_writeservice_only.dart` allowlist** moves with the streaks put (A-R2-P2-1).
  - **Active Workout keeps minting progress** when none exists (A-R2-P2-3).
  - **The kill-switch reason is restated** (B-R2-P2-3).
  - **Test cases that the heal would mask are fixed** (B-R2-P2-1).
  - **Smaller items:** a `num` cast, stranded wlogs accepted, path and line fixes.
  - Mapping in §8.
- **rev 1 → rev 2:** round 1 had two reviewers, A (ground truth) and B (exposure); both said `needs-changes`. Folded:
  - `newlyCompleted` now means "the day was not completed before", with no rest, paused or terminal exclusions (A-F1 and B-F1/F7 were both P1: the old rule stopped Active Workout counting on a rest, paused or moved today-row).
  - A crash-proof count: increment first, then heal to the number of completed days on record (B-F2, P1).
  - An owner and null-progress guard (B-F3).
  - Every door gates on `result.success` (A-F7, B-F4).
  - The kill switch is dropped (A-F6, B-F5).
  - Dates normalised to the IST day, with backdated behaviour stated (B-F6, A-F10).
  - The hold-gate contract is amended on purpose (A-F5).
  - The repoint list is complete (A-F4).
  - The mutation that could not be observed is replaced (B-F9).
  - The full mapping is in §7.

Founder approval 2026-11-10 (chat):
- (1) Same result whichever way a workout is logged.
- (2) A coach day is done only when every planned exercise is logged or the user taps Complete workout.
- (3) One workout per IST day, in the app and on the server.
- (4) Workouts first, nutrition next.
- (A) Train "Logged so far".
- (B) Active Workout shows coach-logged exercises as done.
- (C) "I'm done" re-shows the Complete tile.
- (D) A Complete button on Train's today row.
- (E) Evening reminder "1 exercise left, finish and tap Complete".
- (F) A forgotten day stays not done.

The unit ships as four slices so each review converges (§4.12.1):
- **1a**: this plan.
- **1b**: the stricter chat-card rule, the Train "Logged so far" view, the Complete button, rest/terminal guards on the card and the tap, and the plan-day name. These must ship together: without the Train view a partial log is invisible (5aa251 R8B-P1-1). The card copy the founder approved on 2026-10-21 changes, so 1b brings new copy for approval.
- **1c**: Active Workout pre-log.
- **2**: server. Coach "I'm done", the evening reminder, and the rank cron counting completed days.

1a changes no completion RULE: every door completes exactly the days it completes today. It changes what a completion RECORDS.

**Merge-order constraint (rev 3, B-R2-P1, §4.3 "sequential slices of one feature with no standalone value share one push"):** 1a is committed on this branch but is NOT merged to `main` without 1b in the same PR. Until 1b lands, `submitWorkoutDraft` marks a day done on ANY saved exercise (`conversational_log_handler.dart:402-416`). That writes a `wlog_` row, which the heal counts, and the count, `current_streak_weeks` and `last_counted_week_key` can never be walked back (`user_repository.dart:440` max-wins restore; migration 156 `GREATEST` on push; `weekly-recalc` `Math.max`). Guarding only the call in 1a would not be enough, because the heal counts the `wlog_` row that the partial mark already wrote. The D4.6 interim therefore never reaches `main`.

## 0. Evidence
- OI-379 (`docs/audit/open_issues.md`), filed 2026-10-21 by the round-1 exposure review of `train-coach-log-refresh` (R1B-6b).
- Survey 2026-11-10: two read-only Sonnet agents, re-verified by hand. Only `ActiveWorkoutNotifier.completeWorkout` does the after-completion bookkeeping. The three coach completion paths call `markCompleted` and stop.
- Root cause: ADR-0012 (`docs/adr/0012-derive-only-ai-coach-tool-surface.md:54-57`) assumed `markCompleted` "feeds streak / deployment / rank with zero new completion logic". It does not. The count, the weekly streak, the streak row, badges and the rank check all live in `_persistCompletion` (`train_provider.dart:2050`, bookkeeping `:2263-2368`).

## 1. Writers and readers (§4.1; line numbers verified by round-1 A, ±1-3)

### Completion writer (every door)
`WorkoutWriteService.markCompleted` (`lib/core/services/workout_write_service.dart:581`). Under the per-date lock (`:597`) it does three things:
- reads `schedule_<date>` (`:615`);
- sets `status='completed'`, or synthesises a `type:'logged'` row (`:620-627`);
- upserts `wlog_<date>` with `type:'workout_log'` (`:641-656`).

It has no early return; a re-call re-stamps. It does not touch progress, streaks, badges or rank.

### Bookkeeping writer (Active Workout only today)
`_persistCompletion`:
- `total_workouts_done` is read at `:2264` and written as +1 at `:2317`, unconditionally on every session.
- The reckon at `:2278`.
- The hold ordinal comes from `ref.read(holdStatusProvider)` (`:2297`).
- `resolveStreakWeekState` (`:2298`) feeds `weeklyStreakAfterCompletion` (`:2306`).
- One `updateProgress` (~`:2316`) writes `total_workouts_done`, `current_streak_days`, `last_workout_date` (assign) and `current_streak_weeks`, then `last_counted_week_key`.
- The `healthBox['streaks']` row (`:2327-2353`).
- `checkAll` (`:2359`), `syncProgressNow` (`:2364`) and `evaluateAndPromote` (`:2368`).
- The `markCompleted` result at `:2257` is ignored.

### Coach doors that skip all of it
1. `submitWorkoutDraft` (`conversational_log_handler.dart:334`): `markCompleted` at `:412` when `!wasCompletedBefore` (`:400-421`).
2. `ToolDispatcher._maybeCompleteScheduledDay` (`tool_dispatcher.dart:427`): auto `markCompleted` at `:463`. The result is ignored.
3. `ChatHistoryNotifier.completeWorkoutFromPrompt` (`ai_coach_provider.dart:373`): `markCompleted` at `:409`.

The only other non-test caller is `simulation_service.dart:510`, which is dev only. `WorkoutRepository.markWorkoutCompleted` (`workout_repository.dart:739`) is dead.

### Readers
- **`total_workouts_done`:**
  - `rank_service.dart:412`
  - `badge_service.dart:115` (fallback only; the primary count is the number of `type=='workout_log'` rows, `:98-101`)
  - `profile_provider.dart:313` (`userStatsProvider`, which watches `weekIdentityProvider` → `currentPlanProvider`, so it refreshes lazily after any door's invalidation)
  - `ai_snapshot_builder.dart:126/141`
  - `prediction_service.dart:142`
  - `pattern_detector.dart:499`
  - `sync_profile.dart:112/359` and `sync_service.dart:1462` (push)
  - `ai_coach_repository.dart:295` (stub list)
  - `user_repository.dart:440` `mergeCloudProgress` (restore, max-wins)
- **Weekly streak + marker:** `badge_service.dart:92-136`, `pattern_detector.dart:110-125`, `ai_snapshot_builder.dart`, `sync_profile.dart:634` `_pushStreakWeekMarker`.
- **`last_workout_date`:** `evaluate-rank-promotions/index.ts:236` (MCPO gap gate), `user_repository.dart:125` `laterIsoDate` (restore).
- **The server count is NOT changed in 1a** (slice 2). `evaluate-rank-promotions/index.ts:219` counts `workout_logs` rows; there is one per `(user_id, date, workout_name)` (`sync_workout.dart:187`). It already counts coach-completed days.

### Recurrence
Yes. This is the "second door skips the writer's side effects" class. Prior instances:
- 280c4d: the coach door completed too early.
- e3a6c1: the zero-set door gave credit.
- f1c8e4: A-13 moved completion into `markCompleted` and dropped `type` / `completed_at`.
- e2a418: the chat door skipped invalidations.

Known-good fix: ONE shared function that every door calls, as `invalidateWorkoutSurfaces` did for e2a418.

## 2. Design

### D1. `markCompleted` reports a first completion
- `WriteResult` gains `final bool newlyCompleted` (default `false`). Only `markCompleted` sets it.
- `newlyCompleted = ((no schedule_<date> row) || row.status != 'completed') && (no wlog_<date> row existed before this write)`. Both reads happen inside the per-date lock (`:615`, plus `box.get(wKey)`) before any write. The wlog clause means a stranded day (a day whose wlog survived a reset to `planned` or `skipped`, D4.8) is not +1 again: the heal already counts its wlog (R3-F4).
- There are no rest, paused, travel or terminal exclusions. That matches what Active Workout counts today (A-F1, B-F1).
- A re-call on a completed day returns `false`. The cases are: a second Active Workout session, a chat-card retry, and the auto backstop racing the tap. Because the decision happens inside the lock, two doors cannot both see `true`.
- `newlyCompleted` is `false` on every failed write. `WriteResult.ok` gains an optional `newlyCompleted` parameter (default `false`).
- In practice the heal (D2 step 1) is the primary count, and `newlyCompleted` is the tie-break for accounts whose stored count is ahead of their completed-day count (legacy two-session days). It still decides D4.2: a second session on the same day adds nothing (B-R2-P3-3).
- Known edge, accepted: a raw row that says `completed` with a FUTURE `completed_at` (clock skew) is shown as planned by `getScheduleRowForDate` but returns `false` here. The heal in D2 counts the day anyway once the wlog row exists (B-F8).

### D2. One shared step: `WorkoutCompletionBookkeeping.afterCompletion`
- **Where:** a new file, `lib/features/train/services/workout_completion_bookkeeping.dart`.
  - It must be feature-level, because it uses the public `resolveStreakWeekState` and `weeklyStreakAfterCompletion` in `train_provider.dart`.
  - It is ref-free.
  - The import cycle `train_provider.dart` ↔ the new file is allowed in Dart and accepted. There is precedent for logic files imported by `train_provider.dart`, but those do not import back. If the analyzer or a gate objects, move the two pure functions plus `calendarWeekKey` and `lastCountedWeekKeyFrom` into `lib/features/train/services/streak_week_logic.dart` and re-`export` them from `train_provider.dart` (A-F9).
- **Signature:** `Future<void> afterCompletion({required DateTime workoutDate, required bool newlyCompleted, required String? expectedOwner, required bool mintProgressIfMissing})`. `mintProgressIfMissing` is `true` only for Active Workout, which keeps today's behaviour (`getProgress() ?? {}` at `:2264` and the default map in `updateProgress`). The coach doors pass `false` (A-R2-P2-3).
- **Day normalisation (B-F6):**
  - `dateStr = istDateStr(workoutDate)`, the same key `markCompleted` used.
  - `day = DateTime.utc(y, m, d)` is parsed from `dateStr` and passed to `resolveStreakWeekState` / `calendarWeekKey`. Those read `.year/.month/.day`, so on a device west of IST the week key now follows the IST day, not the device-local day.
- **Steps, in order. Each step is wrapped in its own try/catch, so a throw in one never skips a later one (B-F2):**
  0. **Guards:**
     - If `HiveUserSession.currentOwnerFullId != expectedOwner`, stop with `completion_bookkeeping_owner_changed` (B-F3). Each door captures `expectedOwner` before its `markCompleted` call, as `prediction_service.dart:130` does.
     - If `UserRepository.instance.getProgress() == null` and `!mintProgressIfMissing`, stop with `completion_bookkeeping_no_progress`. Never mint a default map from a coach door (B-F3).
  1. **COUNT FIRST, alone.**
     - `stored = (progress['total_workouts_done'] as num?)?.toInt() ?? 0`. Read it as `num`: a restored double must not throw and silently skip the count every time (A-R2-P3-1; precedent `_persistCurrentStreakDays`).
     - `days = WorkoutReadService.instance.completedWorkoutDayCount()`. The helper lives in core (`lib/core/services/workout_read_service.dart`) because `BadgeService` is in core and must not import features (A-R2-P2-2).
       - It iterates `workoutBox` keys with prefix `wlog_`. Every `type == 'workout_log'` row lives under a `wlog_` key; round 2 A checked every writer, including the dead `saveWorkoutLog` and the b3f9d1 synthesis.
       - It counts DISTINCT IST dates among rows with `type == 'workout_log'`. The date is the row's `date` field when it is a String matching the prefix `^\d{4}-\d{2}-\d{2}` (`substring(0,10)`, precedent `workout_repository.dart:239-245`), otherwise the key suffix when that matches the same prefix. A row with neither is skipped and reported once per call as `completed_day_count_undated_row`.
       - Counting distinct dates means a legacy `wlog_<epoch-ms>` sibling (`workout_repository.dart:759`, `sync_workout.dart:921-925`; `WlogTypeBackfillMigrator` stamps both) never doubles a day (A-R2-P1-1).
     - `BadgeService.checkAll` switches to the same helper (`badge_service.dart:98-101`). Its workout count can only go down or stay the same for an account with legacy duplicates. Badge unlocks are already persisted, so nothing that was unlocked is taken away.
     - `next = max(stored + (newlyCompleted ? 1 : 0), days)`.
     - If `next != stored`, write `updateProgress({'total_workouts_done': next})`. The `getProgress()` read is on the line before the call, with no `await` between, so the update is atomic in the isolate (`user_repository.dart:1005-1011`).
     - The heal means a lost `+1` (an app kill or a throw between `markCompleted` and here) is restored on the next completion. It also corrects every tester account whose coach days were never counted.
     - The heal only raises the count, never lowers it. `stored` stays when it is higher, for example a legacy two-session day (3a7b9f, d1f6b3).
  3a. **Owner re-check (R3-F3):** before step 4, re-check `HiveUserSession.currentOwnerFullId == expectedOwner`, because step 1 awaited `updateProgress`.
  1b. **Restore gate (B-R2-P2-2):** if `!SyncService.instance.restoreSettledForCurrentUser`, stop after step 1 with the event `completion_bookkeeping_restore_unsettled`.
     - `reckonStreakDecayAndPersist` would return a read-only streak computed from a partial schedule (`workout_repository.dart:340-353`), and `current_streak_days` is not monotonic, so writing it would push a low value. The weekly `completedCount` would under-credit.
     - The next completion after the restore settles does the rest.
     - This applies to every door, including Active Workout. That is a change: today Active Workout writes the partial value. It is stated in D4.
     - **Offline cost (R3-F1), accepted.** The marker is in memory and is set only by a restore that succeeded. A cold start that stays offline the whole session leaves it unset, so that session writes only the count.
       - The daily streak already behaves this way today: `reckonStreakDecayAndPersist` is read-only without the marker.
       - The weekly credit is forward-only. A week completed entirely in offline sessions, with no successful launch restore before Monday, loses its weekly credit.
       - This is accepted as rare (every online launch runs the restore) in exchange for never pushing a partial-schedule credit, which would be permanent (`GREATEST`).
       - Under the `disable_streak_reckon_user_gate` kill switch, the reckon falls back to `restoreCompletedTick > 0` (`workout_repository.dart:340`) while this gate keeps the marker. They diverge only with that switch on, which is harmless.
  2. `streakDays = WorkoutRepository.instance.reckonStreakDecayAndPersist()`. It is synchronous (`workout_repository.dart:336`), and its own restore-settled gate stays. When it runs from a coach door, it can consume a freeze for a missed earlier day at that moment rather than at the next rollover. The outcome is the same and the notice flag is the same (B-R2-P3-2; T1 case).
  3. **Weekly:**
     - `holdOrdinal = WorkoutScheduleReadService.instance.activeHoldOrdinalFor(nowWall())`. Round 1 A proved this equals `holdStatusProvider`'s `isHolding ? todayHoldOrdinal : null` in every case: flag OFF, holds exist but today is not one, and today is a hold day. The only difference is that the provider can be cached across midnight, so the direct read is fresher.
     - The pinned contract ("the ordinal comes from `holdStatusProvider`, the single flag-OFF guarantee point": `train_provider.dart:~568`, the `resolveStreakWeekState` doc, `hold_week_streak_identity_behavioral_test.dart:~490`, registry `hold_display_read_path`) is **amended on purpose**. The new wording: the flag-OFF guarantee point is `activeHoldWeeks()` / `activeHoldOrdinalFor()`, which `holdStatusProvider` also calls. The test pin moves to the new file and keeps asserting the flag-gated read (A-F5).
     - Then `streakWeek = resolveStreakWeekState(...)` and `weekly = weeklyStreakAfterCompletion(...)`, reading progress AFTER steps 1 and 2 (d5c8a3).
  4. **One `updateProgress`:**
     - `current_streak_days`.
     - `last_workout_date` = the LATER of the stored value and `dateStr` (`laterIsoDate` semantics, 47de4f).
     - `current_streak_weeks` and `last_counted_week_key`.
     - `updateProgress` fires `syncProgressNow` (`user_repository.dart:1018`), so the explicit call at `:2364` is dropped. The `sync_gap_test.dart:22-33` pin is repointed: the new file calls `updateProgress`, and `updateProgress` calls `syncProgressNow`.
  5. The `healthBox['streaks']` row, moved verbatim. `scripts/check_writeservice_only.dart` keys its allowlist by file, class and op (`:116-118`). In the same commit, replace the entry `train_provider.dart:ActiveWorkoutNotifier:healthBox.put` with `workout_completion_bookkeeping.dart:WorkoutCompletionBookkeeping:healthBox.put`. Before removing the old entry, check that `ActiveWorkoutNotifier` has no other `healthBox.put`. Also check the new file against `scripts/check_hive_map_field_drift.dart` (Gate 19) (A-R2-P2-1).
  6. `BadgeService.instance.checkAll()` (synchronous) and `unawaited(RankService.instance.evaluateAndPromote())`.
- Steps 2-6 run on every successful completion, first or not. Each is idempotent: the reckon, the marker-guarded weekly rule (b7d3e5), the recomputed streak row, badges, and the monotonic rank (`shouldPromote`). Only the `+1` in step 1 is gated.
- **Backdated completions** (a typed `logSet` dated in the past; B-F6, A-F10):
  - The count, the heal and `last_workout_date` are correct: the date only moves later.
  - A day in a previous calendar week gets `weekIsCurrent=false`, so no weekly credit. The weekly rule is forward-only, as today.
  - The streak row is recomputed for the current plan week, which is harmless; the past week's row is not touched.
  - The hold gate follows today, as today.
  - These are stated behaviours, not new rules, and T1 pins them.

### D3. Every door calls it, gated on success
Each door captures `final owner = HiveUserSession.currentOwnerFullId` (`hive_user_session.dart:85`; precedent `prediction_service.dart:132` captures it and `:166` compares) as the FIRST statement of its entry point. It must come before any `await`, because the `logExercise` loops come before the mark (A-R2-P1-2). The capture points:
- Active Workout: the top of `_persistCompletion`.
- Chat card: right after `beginSubmit`, before `DraftSubmitDebug.debugSubmitGate`.
- Typed sets: the start of `_executeLogSet`, threaded as a parameter into `_maybeCompleteScheduledDay`, with the test seam at `:556`/`:564` updated.
- Prompt tap: the first line of `completeWorkoutFromPrompt`.

Each door calls `afterCompletion` only when `result.success`, passing the exact `DateTime` it gave `markCompleted` (A-F7, B-F4).

1. **`_persistCompletion`:**
   - `final mark = await markCompleted(...)`. On success, `await afterCompletion(workoutDate: workoutDate, newlyCompleted: mark.newlyCompleted, expectedOwner: owner)`. This replaces `:2263-2353` and `:2358-2368`.
   - The notifier keeps the state update and its invalidations (`:2355`, `:2372-2378`). Since `afterCompletion` runs first, `userStatsProvider` (lazy via `currentPlanProvider`) reads the new count.
   - **Change:** on a failed `markCompleted`, Active Workout no longer adds `+1`. Today it counts a day that was never recorded. It still shows the completed state and records `active_workout_mark_completed_failed`.
   - **Change:** a bookkeeping throw no longer reaches `_persistCompletion`'s rethrow (`:2040-2046`). The steps catch and report. The workout is saved and the user sees success; the count self-heals on the next completion (A-F11).
2. **`submitWorkoutDraft`:** after a successful `markCompleted` at `:412`, before `invalidateWorkoutSurfaces` at `:425`.
   - The draft-id re-check before the mark already exists. The owner check covers an auth change between the mark and the step.
   - The "completed status with no wlog" re-mark (`:400-421`) returns `newlyCompleted: false`. The heal counts it, because the wlog row now exists (B-F2).
3. **`_maybeCompleteScheduledDay`:** keep the auto `markCompleted` result. On success, call the step. The method's best-effort catch stays.
4. **`completeWorkoutFromPrompt`:** after a successful `markCompleted` at `:409`.

### D4. Behaviour changes (all intended)
1. A coach-completed day counts +1, updates the stored daily streak, the weekly streak and the streak row, checks badges and runs the rank check. This is the OI-379 fix.
2. A second Active Workout session on a day already completed no longer counts +1 (founder decision 3). Today it does (`:2265`). Per round 1 A §6 Q3, no reader expects per-session growth: badges already count per day, and the rank cron counts per day-and-name.
3. Heal: on the first completion after this ships, a tester account whose stored count is below its completed-day count jumps up to that count.
4. `last_workout_date` is later-wins in every door, including Active Workout. This has no effect for today-dated sessions.
5. Active Workout does not count a completion whose write failed (D3.1).
6. **No interim on `main` (rev 3).** 1a and 1b merge together (the merge-order constraint above), so the chat card's mark-on-any-save and the unguarded rest/moved flips by the card and the tap never run with counting on.
7. **Restore unsettled:** every door, including Active Workout, writes only the count (D2 step 1b). Today Active Workout also writes the partial-restore `current_streak_days`.
8. **Stranded wlogs (A-R2-P3-2), accepted:** a day later set to `skipped` (`workout_schedule_write_service.dart:97`) or overwritten to `planned` by copy/roll week (`:214`, `:318`, `:446`) keeps its `wlog_` row, so it stays counted. There is no wlog delete path. That already matches the badge count and the server's `workout_logs` count. The heal never lowers anything.
9. **`last_workout_date`:** the cloud RPC already takes the later value, so Active Workout was already later-wins in the cloud. A clock set forward and then corrected leaves the future date locally, as it does today. `evaluate-rank-promotions/index.ts:236-242` reads a future date as a negative gap, which passes (B-R2-P3-1).

### D5. No kill switch (rev 2; reason restated in rev 3, B-R2-P2-3)
**The deciding reason:** every value this step raises is monotonic and cannot be recovered: the count, `current_streak_weeks`, `last_counted_week_key`, and rank (max-wins restore; `GREATEST` on push; `weekly-recalc` `Math.max`). A switch cannot undo a write that has already been pushed, and flipping it mid-day would itself cause a permanent double count. §4.6 lists "sync", and this change does route three new callers into `updateProgress` → `syncProgressNow`. §4.6 is therefore knowingly not applied here, for that reason. The protection is instead the ×2 review, the B-pass and a pre-merge device check of 1a+1b. The founder approved this scope on 2026-11-10, and the founder is asked to confirm the no-switch call when 1a+1b are presented for merge.

Rev 2 also gave these reasons:
Rev 1's `disable_completion_bookkeeping_parity` was dropped for three reasons:
- It could not restore today's behaviour exactly (A-F6, B-F5): the hold source, later-wins and the success gate all differ.
- Flipping it mid-day makes the next Active Workout session count a day the coach already counted. With max-wins restore, that over-count is permanent.
- §4.6 lists payment, sync, auth, AI prompt and the plan generator. This change writes `userBox['progress']` through the existing `updateProgress` → `syncProgressNow` path and adds no new sync writer.

The app is pre-launch, with tester accounts only (root CLAUDE.md §1). Rollback is a revert of the 1a merge. The heal is idempotent, so a revert leaves only correctly-raised counts.

### D6. Docs and registry (§4)
- A diagnose doc (full template, recurrence class) at `docs/diagnoses/2026-11-10-coach-completion-skips-bookkeeping-<id>.md`, with `closes-diagnose:` in the commit.
- `docs/sot_registry.yaml`:
  - A new concept `workout_completion_bookkeeping`: writer = the new file, readers as in §1, `behavioral_test_path` T3.
  - Update `workout_completion_status` (`newlyCompleted`), `weekly_streak_counter`, `streaks` and `hold_display_read_path` (amended contract). Recompute the ranges from anchors after the move.
  - Update `coach_derived_completion` and `progress_last_workout_date` (the new writer).
- `lib/features/train/CLAUDE.md` and `lib/features/ai_coach/CLAUDE.md` rows. An ADR-0012 amendment note: the "zero new completion logic" assumption was wrong, and there is now one shared step.

### D7. OIs minted in the 1a commit (`sh scripts/mint_oi.sh`)
1. **1b:** the stricter chat rule, Train "Logged so far" and the Complete button, rest/terminal guards on the card and the tap, and the plan-day name. Includes the D4.6 interim.
2. **1c:** Active Workout shows coach-logged exercises as done.
3. **2:** server. The coach "I'm done" tile, the evening reminder, and the rank cron counting distinct completed days.
4. **Nutrition parity.** The survey of 2026-11-10 found 20 differences.
5. **Food-search IST double shift:** `nutrition_provider.dart:1056` passes `istNow()` into `logMeal`, which applies `istDateStr` again.

Close OI-379 and archive it to `closed_issues.md` (append only).

## 3. Tests (each mutated once, rule 21; `TZ=Asia/Kolkata`)

### New, behavioural
- **T1** `test/contracts/workout_completion_bookkeeping_behavioral_test.dart`, driving `afterCompletion` directly on real Hive:
  - `newlyCompleted` true adds 1 and false adds 0.
  - The heal raises `stored` to the number of `workout_log` days and never lowers it.
  - The owner changed: no write.
  - Null progress: with `mintProgressIfMissing: false`, no write and no minted map. With `true` (Active Workout), today's minted map.
  - Restore unsettled: only the count is written. `current_streak_days`, the weekly fields and the streak row stay unchanged.
  - The heal over distinct dates: one `wlog_2026-11-03` row plus one legacy `wlog_<ms>` row with `date: 2026-11-03` count as 1. A row with no usable date is skipped.
  - A `total_workouts_done` stored as a double (`12.0`) is read as 12 and counted. It does not throw.
  - Freeze: a missed yesterday with one freeze, run from a coach-door call, gives exactly one debit, and no second debit on the following rollover reckon.
  - A heal-off variant: `completedWorkoutDayCount` is stubbed to 0 through the seam, so `newlyCompleted` is observable on its own (B-R2-P2-1).
  - A throw injected in step 2 and then in step 3: the count from step 1 still lands, and step 6 still runs.
  - `last_workout_date` stays at a later stored date.
  - The weekly streak credits a week whose 80% includes this day and stamps the marker once.
  - A backdated completion in the same week and in the previous week, each with its expected streak and marker.
  - Normalisation to the IST day: a DateTime at 22:00 UTC (the next IST day) gives that IST week.
  - The streak row is written.
- **T2** `test/workout_write_service/mark_completed_test.dart`, the `newlyCompleted` matrix:
  - No row: true.
  - `planned`, `paused`, `skipped`, `travel`, `rest`-type, `moved` and `dropped` rows: true.
  - A `completed` row: false.
  - A failed write: false.
  - Two concurrent calls on one date: exactly one true.
- **T3** `test/contracts/coach_completion_counts_behavioral_test.dart`, end to end per door:
  - The chat card through the real `submitWorkoutDraft`, reusing the rendered-slot harness in `test/ai_coach/workout_log_confirm_card_saved_signal_test.dart`: Hive inside `tester.runAsync`, fonts rendered first, a file-level `@Timeout`.
  - The 1b rule changes the card's behaviour. Every T3 card case uses a day whose planned exercises are all on the card, so the case means the same before and after 1b.
  - Cases:
    - CONFIRM completing the day: +1.
    - A second CONFIRM: still +1. It is short-circuited by `wasCompletedBefore`, so it never reaches the mark.
    - The "completed status, no wlog" re-mark (`conversational_log_handler.dart:400-421`): `newlyCompleted` false, and the heal counts it: +1 total. This case and the next one are the only T3 cases where a repeat reaches `markCompleted` (B-R2-P2-1).
    - A second Active Workout session on the same day: +0.
    - Typed all-logged auto: +1.
    - Prompt tap: +1.
    - Auto, then tap: +1.
    - Active Workout, then the chat card: +1.
    - The chat card, then Active Workout: +1.
    - Active Workout on a rest-type, a `paused` and a `moved` today-row: +1 each, as today.
    - A failed `markCompleted` in each door: +0.
    - An auth change between the mark and the step (chat card), and an auth change during the `logExercise` loop (Active Workout and chat card): no write to the new owner (A-R2-P1-2).
    - `userStatsProvider.totalWorkouts` reflects the new count after the door's invalidation (A §6 Q4).
  - A `@visibleForTesting` call recorder on `afterCompletion` proves which door reached the step and with which `newlyCompleted` value.

### Mutations (each must redden a named test)
- Drop the `newlyCompleted` gate (always +1): T3, the "completed, no wlog" re-mark and the second Active Workout session. T1's heal-off variant also reddens.
- Delete the heal's `max`: T1 heal.
- Remove the call in each of the four doors, one at a time: T3, that door's case.
- Make `newlyCompleted` false for `paused`: T2 only. The heal masks it end to end, so T3 is not expected to redden (B-R2-P2-1).
- Count rows instead of distinct dates: T1 distinct-date case.
- Capture the owner just before the mark instead of at entry: T3, the auth change during the `logExercise` loop.
- Drop the restore-settled gate: T1, the restore-unsettled case.
- Read `total_workouts_done` as `int?`: T1, the double case.
- Assign `last_workout_date` instead of later-wins: T1.
- Remove the owner guard: T1 and T3 auth.
- Merge steps 1 and 2 into one try: T1 throw injection.
- Drop the IST normalisation: T1 22:00 UTC case.

### Existing tests to repoint (never loosen)
- `weekly_streak_counter_writer_to_reader_test.dart:203-222` (every pin moves to the new file).
- `hold_week_streak_identity_behavioral_test.dart:~490` (amended contract, D2.3).
- `test/sync/sync_gap_test.dart:22-33` (D2.4).
- `scripts/check_writeservice_only.dart` allowlist entry (D2 step 5).
- `badge_service` tests touching `checkAll` totals (grep `test/` for `checkAll`) after the switch to the distinct-date helper.
- `streaks_writer_to_reader_test.dart:47-57`. It would pass vacuously, so repoint it to the new file's `healthBox.put('streaks'`.
- `completed_title_follows_log_test.dart` (scans `markCompleted` call sites).
- `log_exercise_flip_behavioral_test.dart:442-456`: +1 for the first session stays.
- `user_repository_progress_stale_snapshot_test.dart`.
- `conversational_log_handler_uses_write_service_test.dart`.
- `coach_derived_completion_writer_to_reader_test.dart`.
- `derive_only_tool_surface_test.dart:107-125`.
- `coach_completion_prompt_test.dart`.
- `test/ai_coach/workout_log_confirm_card_saved_signal_test.dart`. Note: 1b rewrites it, and 1a must keep it green on its own commit.
- `last_workout_date_latest_wins_behavioral_test.dart`: the comment naming the single writer.
- Also check, not assume, the tests that drive `completeWorkout` end to end: `cardio_complete_workout_behavioral_test`, `active_workout_*`, `session_date_and_home_start_behavioral_test`, `log_exercise_*`.

Before the move, run `grep -rn` across `test/` and the docs for every moved literal (§4.9 "Extracting or moving code"): `total_workouts_done`, `weeklyStreakAfterCompletion`, `resolveStreakWeekState`, `healthBox.put('streaks'`, `BadgeService.instance.checkAll`, `syncProgressNow`, `evaluateAndPromote` and `holdStatusProvider`.

### Harness notes (R3-F5)
- `maybeCompleteScheduledDayForTest(date, dateStr)` keeps its signature, with the owner parameter optional (captured inside the seam), so its 5 call sites in 2 files stay valid.
- Every T1/T3 case that asserts streak, weekly or streak-row writes sets `debugSetRestoreSettledUserIdForTest` in setUp, so those cases are not vacuous. The restore-unsettled case clears it.
- T2 adds: a `planned` row with a pre-existing `wlog_<date>` gives `newlyCompleted` false.

## 4. Gate loop and review
Run the full loop before each review dispatch (§4.12.8): `flutter analyze --no-fatal-infos`, `TZ=Asia/Kolkata flutter test --exclude-tags golden`, then the pre-commit gate loop. The plan is reviewed ×2 (context-blind Sonnet, exhaustive command list). The B-pass `/code-review` runs before the merge (≥account). The plan-review record goes in `docs/plan-reviews/coach-workout-parity.md`. It covers BOTH plans, 1a and 1b (1b's own ×2 review rounds are recorded there before the 1a+1b PR is opened). The branch is not pushed, and no PR is opened, until the 1b commit exists on it (R3-F2, §5 Q4).

## 5. Questions for round 3 (delta check)
1. Does the distinct-date helper handle every `wlog_` row shape that exists, including legacy keys, a missing `date`, and a non-string `date`?
2. Is the restore-settled gate's read (`SyncService.instance.restoreSettledForCurrentUser`) safe to call from all four doors? Is it the same signal `reckonStreakDecayAndPersist` uses?
3. Does switching `BadgeService.checkAll` to the helper change any badge outcome beyond legacy-duplicate accounts?
4. Is the merge-order constraint enforceable as written, given that 1a and 1b sit on one branch and one PR?

## 7. Round-1 mapping
- **A-F1 / B-F1 / B-F7 (P1):** D1, no exclusions.
- **A-F2:** moot. No rest predicate is used.
- **A-F3:** D1 keeps Active Workout counting. T3 adds rest, paused and moved cases.
- **A-F4:** §3 repoint list.
- **A-F5:** D2.3, amended contract.
- **A-F6 / B-F5:** D5, no switch.
- **A-F7 / B-F4:** D3, success gate.
- **A-F8:** §1 readers.
- **A-F9:** D2, the cycle is accepted, with a fallback.
- **A-F10 / B-F6:** D2, normalisation and backdated behaviour.
- **A-F11:** D3.1.
- **B-F2 (P1):** D2 step 1 and the per-step try.
- **B-F3:** D2 step 0.
- **B-F8:** D1 edge and D4.6 interim.
- **B-F9:** §3 mutations.
- **B-F10:** D2 step 1 cites the atomicity lines.
- **A §6 answers** were folded into §1 and D2.3.

## 8. Round-2 mapping
- **B-R2-P1-1:** the merge-order constraint (D4.6).
- **A-R2-P1-1:** D2 step 1, the distinct-date helper. T1 case.
- **A-R2-P1-2:** D3, entry capture. T3 loop case.
- **A-R2-P2-1:** D2 step 5, the gate allowlist.
- **A-R2-P2-2:** the helper in core. `BadgeService` shares it.
- **A-R2-P2-3:** `mintProgressIfMissing`.
- **B-R2-P2-1:** §3 cases and mutations.
- **B-R2-P2-2:** D2 step 1b.
- **B-R2-P2-3:** D5 reworded.
- **A-R2-P3-1:** the `num` cast.
- **A-R2-P3-2:** D4.8.
- **A-R2-P3-3:** the paths fixed in §3.
- **B-R2-P3-1:** D4.9.
- **B-R2-P3-2:** D2 step 2, plus the T1 freeze case.
- **B-R2-P3-3:** D1 note.
- **B-R2-P3-4:** D3. The dispatcher's invalidation runs after the awaited step.

## 9. Round-3 mapping (delta check, CONVERGED)
- **R3-F1:** D2 step 1b, offline cost.
- **R3-F2:** §4 record scope and push order.
- **R3-F3:** D2 step 3a.
- **R3-F4:** D1 wlog clause, plus the T2 case.
- **R3-F5:** §3 harness notes.
- **R3-F6:** D2 step 1 date check.
- **R3-F7:** noted. No non-`wlog_` `workout_log` row exists today.


## 10. Implementation notes (after rev 4, during the build)
- **`last_workout_date`:** step 4 uses the existing pure rule `laterIsoDate` (`user_repository.dart`) rather than a second comparison, because the SoT entry `progress_last_workout_date` requires ONE date rule (constraint 1). Same "later wins" result for every real date; a stored date after IST today + 1 is treated as malformed and replaced, as the restore merge already does. T1 pins both.
- **Test seam:** `ActiveWorkoutNotifier.debugBeforeMarkGate` (awaited after the `logExercise` loop, right before the mark; null in production), so T3 can switch account deterministically for the Active Workout door, as `DraftSubmitDebug.debugBeforeMarkGate` already allows for the chat card.
- **Step 1b mirrors the reckon's kill switch:** the full suite showed that the restore-settled marker's reader manifest (`streak_decay_restore_settled_marker_writer_to_reader_test`) lists every deciding reader by name, so the new step was added there as the sixth. Step 1b reads exactly the reckon's expression (`SyncFlags.streakReckonUserGateEnabled ? restoreSettledForCurrentUser : restoreCompletedTick > 0`), so `disable_streak_reckon_user_gate` moves both gates together instead of leaving the bookkeeping stricter than the reckon it calls. T1 pins both arms (mutations M7, M13).
- **Mutation M1** did not redden the "completed status, no wlog_" card case the plan predicted (+1 and the heal both give 1 there); the second Active Workout session separates them. Recorded in the diagnose doc.
