# Generator Unit 3C: the cardio finisher is shown, injury-safe and timed (OI-396)

Tier L (plan engine + Train UI). Blast radius platform. Execution mode: inline (one worktree,
`.claude/worktrees/generator-step3c`, one writer). Base: main 862f0bc2 (3B merged). Rev 7 (after review round 6, converged).

## 0. Decisions

| Id | Decision |
|---|---|
| OI-396 (2026-10-22) | Show the finisher after the main lifts, injury-safe: an injured user gets Stationary Bike Sprints in a gym and no finisher at home. |
| d56 | Rule 14: one `plan_generator.dart` argument, the user's injuries to the cardio finisher. |
| d61 | Rule 14: pick the 2 finisher days before sets are sized, so those days keep the finisher's time. |
| d74 | Any injury counts (any of the 9 canonical tokens). |
| d75 | Rule 14, inside d61: move the existing gym-cardio block (`hasGymOverride`) above the sizing step, word for word. Nothing else in the file changes. |
| d76 | Under 60 resolved minutes the finisher is a short 4-minute one (mini HIIT; injured gym users 4 rounds of bike sprints), timed inside the session; 60+ minutes the full finisher (§2.2 measurement). |
| d77 | An injury the user tells the AI coach about (accepting `modifyWorkoutForInjury`'s swaps) is also saved to `profile['injuries']` (canonical token; visible and removable in Edit Profile; later plans avoid it everywhere). |
| d78 | The profile is the ONLY injury signal (coach memory is not read). The coach's four parts with no token map to the nearest joint: quad -> knee, calf -> ankle, chest -> shoulder, upper_back -> shoulder; the preview names the entry. |
| d79 | `shortenDay` on a finisher day drops the finisher first, then lifts only if still over the target; the coach says so. |

## 1. What happens today (main 862f0bc2)

- **Writer.** `CardioFinisher.attach` (`lib/shared/repositories/plan_engine/cardio_finisher.dart:17`), called at Stage 6
  (`plan_generator.dart:369-381`) for goals whose spec has `cardio` (lose_fat, general_fitness, recompose), puts 1-3
  timed `PlannedExercise`s (`category: 'finisher'`) on day indices `_pickFinisherDays(dayCount)` ({0,1} / {0,2} /
  {0,3}) of EVERY week. Shape by `cardioPreference ?? _defaultForGoal(goal)`: lose_fat `hiit` (3 items, 120 s each,
  "60s rest after each full round"), general_fitness `cycling` (480 s), recompose `jump_rope` (450 s; mini HIIT without a
  rope), `hate_cardio` mini HIIT (3 x 60 s, "30s rest after each full round"). It takes no injuries.
- **Time.** Sizing runs at `plan_generator.dart:283-307`, BEFORE Stage 6. `SessionBudgetContext.finisherSeconds` exists,
  is always 0 and would be taken from EVERY day (`session_budget.dart:625-630`).
- **Storage.** `WorkoutDay.toMap` writes `finisher` when non-empty (`models.dart:115`). Schedule writers:
  `generateAndSchedule` (`workout_schedule_read_service.dart:316-318`) and the coach's `regenerate_plan_planner.dart:373-375`
  copy it; **`generateAndScheduleFromDate` (`:575-596`, Edit Profile's reschedule, `edit_profile_screen.dart:2201`) does
  not** (writer drift, fixed in §2.3). The restore merge copies whole rows; a day swap moves every content key
  (`day_swap_rules.dart:132`); `tool_dispatcher` and `swap_service` mutate `exercises` and keep the rest. A template
  assignment REPLACES the row with no finisher (intended: a template day is the user's own); the hotel planner
  (`hotel_workout_planner.dart:117-170`) copies `exercises` / `warmup` / `cooldown` only, so its days drop the finisher
  (fixed in §2.3: it copies it).
- **Readers.** None show it. `WorkoutDayData` (`train_provider.dart:236-280`) has `warmup` / `cooldown`; its two
  plan constructors (`:731-743`, `:943-965`; the `NO PLAN` placeholder at `:969` has no content) parse those two keys.
  Active workout (`active_workout/screen.dart:589`, `:796`), `planned_expansion.dart:66-95` and
  `exercise_preview_sheet.dart:292-325` render warm-up / cool-down only. The day minutes (`session_estimate.dart`
  `budgetedDaySeconds` -> `SessionBudget.estimateDaySecondsFromPlanDay`, `session_budget.dart:348`) count `warmup` /
  `cooldown` only; their readers are Train (`train_provider.dart:741`, `:958`), Home (`home_screen.dart:907`,
  `homeCardMinutes`) and the coach's `shortenDay` (`swap_service.dart:768`). The coach snapshot reads none of them.

## 2. Design

One kill switch `disable_cardio_finisher_shown` (`PlanEngineFlags.cardioFinisherShownEnabled`, default ON = new
behaviour) covers the injury rule, the reservation and the display. OFF = main byte for byte for generation and
today's screens.

### 2.1 The finisher plan (pure, decided before sizing)

`CardioFinisher.plan({goal, cardioPreference, equipmentList, hasGymEquipmentOverride, capability, injuries, dayCount,
shown, minutes})` returns `FinisherPlan{days, exercises, reserved}` (`FinisherPlan.none` when the goal has no cardio or
`dayCount < 2`). Rule:
- switch OFF: today's shape on today's days, `reserved: false`, injuries ignored;
- ON, no injury: today's shape; a circuit (HIIT, mini HIIT) stores its round rest on its last item (`restSeconds` 60 /
  30), so its time is honest;
- ON, under 60 resolved minutes (d76): the short finisher, 240 s: the mini HIIT with its round rest, or for an
  injured gym user 4 rounds of Stationary Bike Sprints (`_cyclingFinisher(true, rounds: 4)`); an injured user without
  gym cardio gets none at any length;
- ON, any injury (d74): gym cardio -> Stationary Bike Sprints (480 s); none -> no finisher. "Injured" is ONE
  predicate over the PROFILE only (d78), `FinisherSafety.isInjured(profileInjuries)` (pure, `finisher_safety.dart`):
  `InjuryVocab.normalize(InjuryVocab.fromProfile(profileInjuries)).isNotEmpty`, the engine's own `normalizedInjuries`
  test (`['none']`, `[]`, unmappable free text and a bare legacy String `'none'` are NOT injured). `generateV4` passes
  the plan and Stage 6 `attach` its existing `normalizedInjuries` (the prototype's argument; no new read in
  generation). Coach memory is NOT read anywhere (round 5: `pushSnapshot()` runs right after every tool,
  `tool_dispatcher.dart:263`, and the mirror `sync_service.dart:1266-1270` replaces the local `coach_memory`, so the
  tool's `{part}` entry is gone within seconds; and a server-extracted string there could never be cleared by the
  user). The coach's knowledge reaches the profile through d77 / d78 instead:
- **d77 / d78 coach writer.** `_executeModifyWorkoutForInjury` (`tool_dispatcher.dart:666-725`), after its swaps
  (also when every swap failed: the injury is real), maps `bodyPart` to a token by `InjuryVocab.coachPartToken`
  (new, `injury_vocab.dart`: the 9 canonical parts to themselves, `quad -> knee`, `calf -> ankle`, `chest ->
  shoulder`, `upper_back -> shoulder`; anything else -> null) and writes it with
  `ProfileWriteService.instance.patchProfileWith(build, stillOwner)` (`stillOwner`: the uid captured at the START of
  `_executeModifyWorkoutForInjury`, before the swap loop, tested as in `LegacyGoalHealer.owned()`: the live uid equals
  it AND `HiveUserSession.currentOwnerFullId` equals it; its return value, not a captured flag, decides the lock) (the decide-and-write under the profile lock that
  3B added; `build(current)` returns null, no write, when the profile is absent, the token is null, or the token is
  already in `InjuryVocab.normalize(InjuryVocab.fromProfile(current['injuries']))`; else `{'injuries': next}`, `next` =
  the stored list via `fromProfile` minus `none`, plus the token). The block is best-effort in its own try/catch like
  the coach-memory append beside it (a throw never turns applied swaps into a failure). When a token was written it
  then awaits `ToolDispatcher.lockFields(['injuries'])` (a `@visibleForTesting` static seam, default
  `UserRepository.lockCoachExtractionFields`) under `.timeout(const Duration(seconds: 4))`, caught and non-fatal
  (round 6 A-F2: the real call makes 2 RPC attempts with no timeout, and the handler runs before the invalidations
  and the dispatch stamp); awaited so the `pushSnapshot()` that follows the tool normally cannot run an extraction
  ahead of the lock. Accepted residue: after a timeout an extraction may run before the lock lands. Why lock: the user confirmed the line in the preview, as deliberate as an Edit Profile chip, and an unlocked server
  extraction could replace the list in the cloud and a restore would then drop the token. `severity` is not used (a
  mild injury is still an injury; the user removes it in Edit Profile). The tool result carries
  `profile_injury_added: <token>` on success AND on the all-swaps-failed failure (`ToolExecutionResult.failure(msg,
  data:)`, `:65`; that failure's text becomes "Couldn't change your workouts. Knee was added to your injuries.").
  `execute()` runs `_invalidateProfileProviders(ref)` and `_invalidateWorkoutProviders(ref)` for a
  `modify_workout_for_injury` result carrying a token BEFORE its `if (!result.success) return result;` (`:211`; round 6
  A-F1 / B-F1: the existing invalidation site `:251` sits after it), and the success path keeps its own; the confirm
  card (`tool_confirm_card.dart`) keeps the executed result's `data` in its State and its executed line reads
  `Workouts updated · Knee added to your injuries` (after a restart, without the data, the plain line). The diff preview
  (`injury_modify_diff.dart`) shows `Adds Knee to your injuries (change it in Edit Profile)` (the mapped token's
  label) in BOTH branches, the normal one and the early `_swaps!.isEmpty` one (`:75-85`, whose "record the injury
  anyway" text now names the profile), and no line when no token will be added (already present, or no profile).
`hasGymEquipment` is today's signal: `hasGymEquipmentOverride` (effective equipment holds `cardio machine`) or, with
`disable_equipment_exclusions` set, the old tier-string predicate, which is false on item tokens: an injured gym user
then gets no finisher (pinned as accepted). The injured branch does not consult `capability`; it is consistent because
both come from `cardio machine` (a `cardio machine` exclusion with an injury -> no finisher, pinned).

Accepted and pinned (round 2 A-F4): the gym signal reads the tier's items minus exclusions, not `equipment_owned`, so
an injured home user who owns a bike gets no finisher; the locked-week previews (`preview_plan_provider.dart:95-102`,
`phase2_preview_card.dart:94-101`) pass no exclusions, so a user who excluded `cardio machine` can see a bike finisher in
a preview their real plan will not hold (a preview of a future phase, shown through the reader rule, §2.3).

`attach` gains `injuries` (default `const []`) and `plan` (default null: built per week as today, unreserved and
without d76's minutes, for the direct test callers only; `generateV4` always passes its plan), so the direct callers
(`test/contracts/cardio_goal_default_test.dart`, `test/plan_engine_v4/shared_contracts_test.dart`, about 20 calls)
keep working. Test seam `CardioFinisher.debugReserve` (default true; false = the plan with `reserved: false` and no
`secondsByDay`) for the attribution oracle (§3).

**Time:** `CardioFinisher.secondsOf(items)` = sum of `durationSeconds` (each item's whole work time) + `sets x
restSeconds`. Cycling 480, running 450, jump rope 450, HIIT 360 + 3 x 60 = 540 (9 min; the comment says about 10),
mini HIIT 180 + 2 x 30 = 240. The display prices a stored finisher with the same rule
(`SessionBudget.finisherSecondsOfPlanDay`, below), so the reservation and the Train / Home minutes agree.

### 2.2 Reservation (d61)

`SessionBudgetContext.finisherSecondsByDay` (day index -> seconds, default empty) and `finisherSecondsOn(day)`;
`BudgetLedger`'s day budget is per day (`base - finisherSecondsOn(day) [+ allowance]`). Every ledger indexes days by
position in `populated` / `week.workoutDays` (allocator `_variant` `:919`, `_plainLedger` `:780`, periodization `:182`,
titration `:181`; sequencing and superset pairing reorder exercises only; the 6-day alias, deload weeks, Unit 2D's
appended accessories and the 2C-b allowance world use the same days). `generateV4`, after `pickV4` /
`buildPinnedDays` and the moved `hasGymOverride` block (d75), directly before `SessionBudgetContext`:
`finisherPlan = CardioFinisher.plan(..., injuries: normalizedInjuries, dayCount: populated.length)` (d56 / d61); the
context takes `finisherPlan.secondsByDay`; Stage 6 attaches `plan: finisherPlan`. Nothing else in the file changes.

The plan call also takes the resolved minutes (`SessionBudget.resolveMinutes(param: sessionDuration, profileValue:
TrainingHistoryAnalyzer.sessionMinutesFromProfile())`, the same expression the context uses) for d76.

**Cost (measured on the prototype, uninjured audit grid: Cut and Maintain x 3-6 days x 3 levels x 4 tiers x phases
1-3; week 1's finisher days, 288 per goal and length; "muscle-weeks" = a library primary muscle trained OFF in a week
1-3 with 0 sets ON):**

| Goal, minutes | Full finisher: exercises ON / OFF | below the count floor | muscle-weeks | Short finisher (d76): exercises | below the count floor | muscle-weeks |
|---|---|---|---|---|---|---|
| Cut 30 | 3.53 / 4.00 | 135 | 645 | 4.00 | 0 | 228 |
| Cut 45 | 5.01 / 5.74 | 0 | 198 | 5.34 | 0 | 84 |
| Cut 60 | 6.02 / 6.28 | 0 | 30 | (full) | 0 | 30 |
| Cut 90 | 6.28 / 6.28 | 0 | 0 | (full) | 0 | 0 |
| Maintain 30 | 3.71 / 4.00 | 84 | 330 | 4.00 | 0 | 216 |
| Maintain 45 | 5.06 / 5.72 | 0 | 132 | 5.38 | 0 | 66 |
| Maintain 60 | 6.02 / 6.20 | 0 | 30 | (full) | 0 | 30 |
| Maintain 90 | 6.20 / 6.20 | 0 | 0 | (full) | 0 | 0 |

The count floor and the day floor are NOT part of d76's cost: with the short finisher no finisher day falls below the
count floor (column above, measured), and the floors stay hard invariants of their gates.

The founder chose the short finisher (d76). The remaining cost (a lighter finisher day, some muscle-weeks at 0 under
60 minutes) is d76's accepted cost; the gates that assert "no group OFF trains is at 0 ON" (3A's `goal_training_gate`
item 5 and the like) compare with the finisher switch OFF on both sides or carry d76's excuse, named in §3.

### 2.3 Display

- **Reader rule (safety, round 1 B-F1).** The stored finisher is shown only when it is safe for the user's CURRENT
  injuries: ONE function on stored maps, `CardioFinisher.shownFinisherMaps(Object? raw, {required bool enabled,
  required bool injured}) -> List<Map<String, dynamic>>`. Switch off -> `[]`. No injury -> every map in `raw` (a
  non-list or non-map entries -> dropped). Injured -> `raw` only when it is non-empty and EVERY item's name
  (`exercise_name ?? name`, trimmed, lowercased) equals `stationary bike sprints`, else `[]` (an empty list or a
  nameless item -> hidden). Every other caller adapts to it: the `WorkoutDayData` constructors parse its result, the
  minutes path passes it, the preview passes `workoutDay.finisher.map((e) => e.toMap())` through it. So a plan made before an injury was added (Edit Profile without the reschedule, the coach's
  `modifyWorkoutForInjury`, which swaps `exercises[]` and, with d77 / d78, writes the profile; a pre-3C plan) never
  shows burpees to an injured user. The inputs come from ONE I/O reader, `FinisherShowContextReader.read()`
  (`finisher_show_context.dart`, kept apart from the pure `finisher_safety.dart` so the predicate tests need no Hive)
  -> `{enabled, injured}` (the switch and `UserRepository.instance.getProfile()?['injuries']` through `isInjured`;
  total: a read failure -> `enabled: true, injured: true`, the safe side, display only), called ONCE per build by every
  caller (both Train constructors, Home, the preview provider, `shortenDay`, `workoutDayForDate`), with
  `FinisherSafety.shownOfRow(row, ctx)` = `shownFinisherMaps(row['finisher'], ...)`. No caller reads the profile or the
  switch for this itself.
- **d77 / d78 writer:** §2.1.
- **Writer fixes.** `generateAndScheduleFromDate` writes `finisher` like `generateAndSchedule`; the hotel planner's
  row copies `workout.finisher` like warm-up / cool-down (round 3 A-F4: the engine reserved that time on the hotel
  plan's finisher days). Not gated: a stored key nothing shows with the switch OFF.
- **`WorkoutDayData.finisher`** (`List<ExerciseData>`) and **`finisherSeconds`** (`int`, `finisherSecondsOfPlanDay`
  of the same shown maps; round 5 B-F5: `ExerciseData` has no `duration_seconds`), set at both plan constructors; the
  context is read ONCE before each constructor's day loop. The section label is `'${(finisherSeconds / 60).round()}
  MIN'` like `budgetMinutes` (240 -> `4 MIN`, 450 -> `8 MIN`, 480 -> `8 MIN`, 540 -> `9 MIN`; pinned).
- **The rows' text (round 2 B-F1, round 3 B-F2).** `_parseExerciseMaps` turns a timed row's `reps` into seconds by
  `parseTimedDurationSecs`, which does not read `duration_seconds`, and both renderers
  (`warmup_cooldown_section.dart` ~`:145-160`, and `_buildPreviewExerciseRow`, defined in
  `exercise_preview_sheet.dart` and called by `planned_expansion.dart` too, round 4 B-F5) strip the digits of `ex.reps` on `loggingType == 'timed'`
  ("30s fast / 30s slow" -> 3030 -> "50m 30s"). Plumbing: `ExerciseData` gains a nullable `detailText`; finisher maps
  are parsed by their own `_parseFinisherMaps`, which sets `detailText = FinisherDisplay.detail(sets, reps)` =
  `'<sets> rounds · <reps>'` (`8 rounds · 30s fast / 30s slow`, `3 rounds · 10`, `2 rounds · 30s`,
  `5 rounds · 60s on / 30s rest`); each of the two renderers shows `ex.detailText` when it is non-null BEFORE its
  timed / reps branch (a one-line change per renderer; every other row has `detailText == null` and is unchanged).
  `_parseFinisherMaps` sets `muscleLabel` null and does no library lookup (a preview row prints `muscleLabel · detail`;
  `search("burpees")` would print whatever row it finds); `ExerciseData.copyWith` carries `detailText`.
  The section shows the finisher's minutes in a separate `trailingLabel` (`WorkoutDayData.finisherSeconds`, above),
  NOT in the title, so the check key stays `warmup_checks_<today>_finisher` (the key's slug is the title with
  `[^a-z]` stripped, `warmup_cooldown_section.dart:34-38`; round 3 B-F5). Widget test per finisher shape in both
  renderers (the active workout section, a Train preview row), exact strings.
- **Active workout:** a `FINISHER` section (`_WarmupCooldownSection`, colour `AppColors.accentHi`, collapsed when the
  workout is complete) between the last exercise card and COOL-DOWN; both sections take `ValueKey`s
  (`finisher_section`, `cooldown_section`) so the cool-down keeps its state when the finisher appears or goes. A
  checklist like the warm-up (its own per-day check key `warmup_checks_<date>_finisher`): not logged, never in sets,
  PRs, `finishGuard`, `hasSaveableSet` or completion (those key on `exercises[]` / `checkedSets`; pinned by a test).
  Its tick key is today's, like the warm-up's (`warmup_checks_<today>_finisher`, distinct from `_warmup` /
  `_cooldown`).
- **Train** `planned_expansion.dart` and `exercise_preview_sheet.dart`: a collapsible `FINISHER` section after the
  main exercises, before COOL-DOWN, same rows and detail; `_CollapsibleExerciseSection` (`collapsible_section.dart`)
  gains an optional `trailing` label so its header shows the same `9 MIN` (round 6 B-F5; `_WarmupCooldownSection`'s
  `trailingLabel` is likewise a new parameter). The locked-week preview (`preview_plan_provider.dart`) adds
  `finisher_count` = the length of `shownFinisherMaps(...)` (one `FinisherShowContextReader.read()` in the provider; OFF -> 0,
  injured -> only the bike counts) and `preview_workout_screen.dart:132-176` lists it between warm-up and cool-down
  in its joined line: `2 warm-up · 3 finisher · 3 cool-down exercises included` (exact string pinned, each part only
  when its count > 0, round 4 B-F6); the line's guard (`:170`) gains `|| finisherCount > 0` (a finisher-only day,
  test).
- **Minutes.** `budgetedDaySeconds(planDay, {required List<Map> finisher})` / `budgetedDayMinutes(...)` /
  `homeCardMinutes(...)`: a REQUIRED named argument (so the compiler finds every caller), the SHOWN finisher maps;
  `estimateDaySecondsFromPlanDay(..., {required finisher})` and `estimateDayMinutesFromPlanDay(..., {required
  finisher})` (both REQUIRED, round 4 B-F3, so the compiler lists every caller) add `SessionBudget.finisherSecondsOfPlanDay(finisher)`
  (§2.1's rule: `duration_seconds + sets x rest_seconds` per map; total: a non-map entry is skipped, an absent or
  unparseable `duration_seconds` is 0, `sets` absent 1, `rest_seconds` absent 0, numeric strings parsed, never
  throws). The raw row's `finisher` key is never read by the
  estimator. Train (both constructors), Home and the coach's `shortenDay` pass `shownOfRow(row, FinisherShowContext.read())`, so all
  three agree. Callers: lib `swap_service.dart:768`, `home_screen.dart:907`, `train_provider.dart:741`, `:958`; tests
  `session_estimate_display_test.dart` (~13 call sites, each given `finisher: const []` or a finisher fixture) and its
  two source-grep pins `:524` (`final estDuration = homeCardMinutes\(schedule\);`) and `:528`
  (`budgetMinutes: budgetedDayMinutes\(row\)`), REPOINTED to the new call shapes (never loosened; `grep -c` of each
  new call site checked).
- **`shortenDay`** (`swap_service.dart:615-700`, d79). Over the target with a SHOWN finisher, it first removes the
  finisher (the row is written without its `finisher` key, `scheduleMap.remove('finisher')` then
  `WorkoutWriteService.upsertScheduled`, the writer it uses for `exercises`, which writes the whole row; the cloud
  `scheduled_workouts` payload carries no content keys, so nothing changes there); if the
  day then fits, it stops there. Otherwise it drops exercises by its existing rules (down to its floor of the 2
  highest-priority ones; `ShortenDayException('target_too_low')`, writing nothing, when even those exceed the target,
  measured WITHOUT the finisher, so its user-facing text stays true). `ShortenDayResult` gains `finisherDropped`, the tool result
  `finisher_dropped`; the user sees it on the confirm card, whose executed line (kept result `data`, above) reads
  `Workout shortened · finisher removed` (round 6 B-F2: `_executedMessage` was static per type and nothing read the
  result). A hidden finisher (switch off, injured) is not counted, and its key is removed too whenever `shortenDay`
  writes the row (round 6 B-F3: else clearing the injury later would bring it back over the target the user set). A
  session already started keeps the finisher it started with (the active workout snapshots `workoutDay` at
  `startWorkout`, as for dropped exercises today; accepted). The unreadable-day fallback (`fallbackExerciseListSeconds`, like
  `homeCardMinutes`' fallback) ignores the finisher (accepted, pinned). Tests: finisher drop alone fits (row has no
  finisher, exercises untouched, `finisherDropped`); finisher drop plus exercise drops; `target_too_low` with the
  finisher already gone (no write); a hidden finisher untouched.
- **Copy:** `FINISHER` (Wardroom soul check: a plain section label like WARM-UP / COOL-DOWN; no motivational copy).

- **Accepted (round 6 A-F6):** the profile restore is cloud-non-null-wins per key (`sync_profile.dart:831-836`), so
  a coach token saved offline can be overwritten by a later restore of the cloud list (Edit Profile has the same
  class); the extraction lock is permanent and additive, so after the first coach injury chat extraction no longer
  updates `injuries` (the user owns the field from then on, as after an Edit Profile change).
- **Model-facing text (round 6 A-F4 / B-F2).** The tool descriptions `modifyWorkoutForInjury.ts` ("records the
  injury in the user's coach_memory") and `shortenWorkout.ts` ("drops accessory/isolation work") are rewritten to
  match (the injury goes to the profile; the finisher goes first). They ship in ai-proxy: `deno check`, then an EF
  deploy that needs the founder's go for that action (§4.3); the app half does not depend on it.
- **Accepted (round 4 B-F7), as warm-up / cool-down today:** a completed day's preview sheet lists the logs, not the
  plan, while its minutes include the finisher; Home's day detail sheet lists `exercises` only; `CurrentPlanNotifier`
  reads the context per rebuild, so a profile change made outside Edit Profile / the coach (a cloud restore) shows at
  the next rebuild.

### 2.4 Existing plans

A plan generated before 3C keeps its finisher rows (no reservation): with the switch ON an UNINJURED user now sees them
and the day's minutes grow by the finisher; an injured user sees none unless it is the bike (§2.3). The next
regeneration reserves the time. Pre-launch (every account is a test account): accepted, no migration.

## 3. Tests (behavioural unless stated)

- `test/contracts/cardio_finisher_injury_behavioral_test.dart`: real `generateV4`, Cut: uninjured gym -> HIIT (with
  round rests) on the plan's days; injured gym (each of the 9 tokens) -> Stationary Bike Sprints only; injured home ->
  none; `disable_equipment_exclusions` set + injured gym -> none (accepted); `cardio machine` excluded + injury -> none;
  switch OFF -> today's finisher for the injured user.
- `test/contracts/finisher_reservation_behavioral_test.dart`: on a finisher day the allocator's priced seconds stay
  within `minutes - warmCool - finisherSeconds` (+ the allowance / forcing bounds); a non-finisher day keeps the full
  budget; Build unchanged; the attached days equal `plan.days` in every week, phases 1 / 4 / 5 and a repeat-pin run.
- `test/contracts/finisher_display_behavioral_test.dart` (Hive through `setUpHiveForTests`): `shownFinisherMaps` /
  `isInjured` table (switch; profile `['none']`, `'none'`, `[]`, `['xyz free text']`, `['knee']`, `['back']`; bike /
  HIIT); a stored HIIT finisher + profile injury `knee` shows nothing on Train (real Hive row -> `WorkoutDayData`),
  Home's minutes or `shortenDay`; profile `['none']` keeps the HIIT (round 3 A-F1); `FinisherShowContextReader.read()` with
  the profile read failing gives `shown == []`.
- `test/contracts/coach_injury_profile_write_behavioral_test.dart` (d77 / d78): a real `ToolDispatcher.execute` of
  `modify_workout_for_injury` (`knee`) on a `['none']` profile writes `['knee']`, locks `injuries` (fake
  `lockCoachExtractionFields` seam, called before `pushSnapshot`), invalidates `userProfileProvider` (ProviderContainer;
  mutation: drop the condition); `quad` -> `knee`, `calf` -> `ankle`, `chest` / `upper_back` -> `shoulder`; a repeated
  or already-present token (`back` stored, `lower_back` token) writes nothing and does not lock; an absent profile
  writes nothing; a profile write that throws leaves the swaps' success intact; all swaps failed still writes the
  token; concurrent knee + shoulder intents (20 trials) keep both tokens; after a snapshot mirror replacing
  `coach_memory`, the profile still holds the token and the stored HIIT stays hidden; then `generateV4` attaches the
  bike (gym) or nothing (home). Also: the all-swaps-failed result carries the token and `execute()` invalidates the profile providers on it; a
  never-completing fake `lockFields` still lets the tool return (timeout); the lock call is recorded BEFORE a faked
  `pushSnapshot`; an owner change during the swap loop writes nothing. The existing callers keep passing:
  `coach_unique_exercise_names_test.dart:118` seeds no profile, so `quad` writes nothing (unchanged);
  `tool_dispatcher_telemetry_gaps_test.dart:138` (method order kept).
- Widget: the confirm card's executed line (`Workout shortened · finisher removed`, `Workouts updated · Knee added
  to your injuries`, the plain lines without data); `modifyWorkoutForInjury` is destructive, so its line shows on
  `ToolConfirmSheet` after the confirm (B-pass seat B F1); the injury diff preview shows `Adds Knee to your injuries (change it in Edit Profile)` in the normal and the
  empty-swaps branch, `Adds Knee` for `quad`, and no line when the token is already present.
- Display, both
  constructors; minutes include the shown finisher and not a hidden one; Train == Home; `shortenDay` on a finisher
  day; `generateAndScheduleFromDate` and the hotel planner write the finisher on the same days as
  `generateAndSchedule` (hotel: `plan.days` for n >= 2; n = 1 none; n = 7 wraps `workouts[i % length]`); a day swap keeps it; the finisher is not in sets / PRs / `finishGuard` / `hasSaveableSet` / completion.
- Widget tests: the active-workout FINISHER section (order, keys, collapsed when complete) and the planned expansion.
- **Golden and digests (round 2 A-F1 / A-F3).** Rule: a fixture or digest that names an OLDER main or an OFF world
  ("main X", "pre-2C", `_off`) sets `disable_cardio_finisher_shown` on that side and is NOT re-recorded; a digest of
  the live (ON) engine is re-recorded on the built tree. Known members:

  | Fixture / digest | Test | Action |
  |---|---|---|
  | `generator_golden_hashes_finisher_off.json` (new) | new `finisher_kill_switch_golden_test.dart` | switch set; equals main 862f0bc2 |
  | `generator_golden_hashes_goal_training_off.json` | `goal_training_kill_switch_golden_test.dart` | + switch |
  | `generator_golden_hashes_lead_first_off.json` | `lead_first_kill_switch_golden_test.dart` | + switch |
  | `generator_golden_hashes_balanced_week_off.json` | its kill-switch test | + switch |
  | `generator_golden_hashes_loaded_wins_off.json` | `loaded_wins_kill_switch_golden_test.dart` | + switch |
  | `day_floor_off_hashes.json` ("main 8a2e1c5a") | `day_floor_gate_lib.dart`, `day_floor_kill_switch_test.dart` | + switch |
  | `_offDigest` ("pre-2C") | `test/plan_generator/balanced_week_gate_test.dart` (anchor `_offDigest`) | + switch on the OFF side |
  | item-9 ON digest, 30-minute OFF digest | `test/plan_generator/weekly_minimum_gate_test.dart` (anchors) | ON re-record; OFF + switch |
  | `_onDigest`, `_focusDigest`, the OFF equality | `test/plan_generator/goal_training_gate_test.dart` (anchors) | ON re-record; OFF + switch |
  | the main golden | `generator_golden_test.dart` | re-record with the attribution test below |

  Any further plan digest the CI run turns red follows the same rule and is added to this table in the diagnose doc.
  Attribution test (re-record oracle, round 3 A-F2: the allocator's weekly ledger is shared, so a reservation on the
  finisher days can move a non-finisher day; the oracle splits the two claims): (1) with `CardioFinisher.debugReserve
  = false`, ON and OFF differ ONLY in each day's `finisher` maps for every golden persona (the attachment, the round
  rests and the injury rule; `exercises[]`, warm-up, cool-down byte-equal); (2) with the reservation, every
  build_muscle and strength persona equals OFF, and the moved cardio-goal personas are reported per goal and minutes
  with the share of changed days that are finisher days (into the diagnose doc; bounded by the §2.2 table, not
  asserted per day). Mutation: drop the switch from one OFF test and see it red; reserve on Build and see (2) red.
- **Gates that restate the day budget** take the per-day reservation from the stored day
  (`SessionBudget.finisherSecondsOfPlanDay`): `session_set_budget_gate_test.dart` (`daySeconds` `:267`, `limitMin`
  `:316`, display == oracle `:343-347`), `test/helpers/repeat_minutes_gate_lib.dart` (`:49`, `:138`),
  the day-floor and weekly-minimum libs, `quads_floor_6day_behavioral_test.dart:376`,
  `oi489_timed_hold_real_engine_test.dart:98`, and the `estimateDayMinutesFromPlanDay` callers
  `goal_training_gate_test.dart` (~`:147`), `weekly_minimum_gate_test.dart` (~`:154`), `plan_audit_dump_test.dart`
  (~`:152`) (round 4 B-F3; `swap_exercise_rest_follows_incoming_archetype_test.dart:75` passes `const []`): each passes the stored day's `finisher` maps to
  `estimateDaySecondsFromPlanDay(finisher:)` (a gate builds no profile, so it passes the raw stored finisher; the plan's
  own finisher is what the reservation priced). `session_estimate_display_test.dart` (Train == Home, the repointed pins
  above), `session_budget_test.dart` (the per-day ledger). Unchanged (bare contexts or fixtures with no finisher, round
  3 A-F5): `session_set_budget_consumers_test.dart:182`, `session_set_budget_wiring_test.dart:121`,
  `exercise_count_band_behavioral_test.dart:96,127`, `session_allowance_behavioral_test.dart:332`. Line numbers are
  re-derived from anchors at build time.
- d76: a 30 and a 45-minute Cut plan carry the mini HIIT (240 s), an injured 45-minute gym plan 4 bike rounds, a
  60-minute plan the full finisher; the measured table re-run on the built tree (numbers into the diagnose doc).
- Gates asserting "no group at 0 ON vs OFF" (`goal_training_gate_test.dart` item 5, `weekly_minimum_gate_test.dart`,
  `day_floor_gate_*`, `lead_first_gate_test.dart`, `balanced_week_gate_test.dart`, `core_list_pool_gate_test.dart`):
  each either sets `disable_cardio_finisher_shown` on both of its sides (when it measures another unit) or, if it
  measures the live plan, takes d76's cost as a named excuse with the counts. Decided per gate in the build, listed in
  the diagnose doc.
- **Injury sweeps (round 2 A-F2).** `injury_floor_sweep_lib.dart` (`kThinCeilings`, strict both ways), the
  `injury_sweep_{a..f}` blocks, the `r6_removed_runs_*` files and `injured_grid_dump_test` run the real engine on injured
  Cut / Maintain plans: run on the built tree, ceilings re-read (expected 0 / 0 by the day floor; any change recorded).
  `SweepTally` gains a finisher scan: every injured plan's finisher is only Stationary Bike Sprints (gym) or absent
  (home); the lib header's "out of scope: the cardio finisher" sentence is replaced. Mutation: the injury rule ignored
  turns the sweep red.
- **Pricing parity (round 2 B-F4):** for every finisher shape (bike 4 and 8 rounds, High Knees Intervals, running both,
  HIIT, mini HIIT, jump rope) `CardioFinisher.secondsOf(items) == SessionBudget.finisherSecondsOfPlanDay(items.map(toMap))`.
  Mutation: drop the rest term from one side.
- **Days (round 2 B-F6):** in the reservation test, `weekPlan.workoutDays.length == populated.length` for every week.
- `shownFinisherMaps` table: each input shape (list of maps, `name` vs `exercise_name`, case / spaces, empty, a
  nameless item, a non-list), switch, injured.
- Mutations: the injury rule inverted / ignored; the reservation on every day / none; the plan built after sizing; a
  constructor not reading the finisher; `shownFinisher` ignoring injuries; the display ignoring the switch; the
  reschedule writer dropping the finisher; the extra switch dropped from a kill-switch golden test.

## 4. Docs

Diagnose doc (full template: the reschedule writer drift is a writer/reader drift); SoT `cardio_finisher_shown`
(writers `CardioFinisher.plan` / `attach`, `generateV4`, the two schedule writers; readers `shownFinisher`, the two
constructors, three screens, `budgetedDaySeconds`' three callers); d77 / d78: a second coach writer of `profile['injuries']` (beside induction's backfill): SoT
`injury_vocabulary_contract` writer list (it writes a canonical token), `coach_extraction_locked_fields` writer list
(the coach lock), `InjuryVocab.coachPartToken`, `check_hive_map_field_drift` re-run (new field
`profile_injury_added`); `tool_dispatcher.dart` anchors in `docs/sot_registry.yaml` recomputed and the `ai_coach` CLAUDE.md `modifyWorkoutForInjury` row; nested CLAUDE.md (plan_engine Stage 7, train); the existing `hasGymOverride` anchors that d75's move shifts
(`docs/sot_registry.yaml`, the plan_engine CLAUDE.md WU-2 line) and every other `plan_generator.dart` range the added
lines shift, recomputed from anchors per commit;
`naming_conventions.md`; OI-396 closes after the founder's device check (t308).

## 5. Review log

- Round 6 (2026-11-16, two Sonnet seats, on rev 6): CONVERGED (both seats no P0/P1). Rev 7 settles the P2s / P3s in
  text: the all-swaps-failed path carries the token and invalidates before the early return, the user-facing failure
  and executed lines (A-F1, B-F1, B-F2); the lock timeout and seam, `stillOwner` captured at handler start (A-F2,
  A-F3, B-F4); the model-facing tool descriptions with their deploy gate (A-F4); the hidden-finisher key removed on a
  shorten, the Train header minutes, the mid-session snapshot and the restore / lock residues (B-F3, B-F5, B-F6,
  A-F6); `minutes` in the signature (A-F7); the existing-test sentence (A-F5).
- Round 5 (2026-11-16, two Sonnet seats, on rev 5): not converged; both P1s and most P2s were the coach-memory leg
  (seat A: the tool's `{part}` entry is erased by the mirror seconds after the tool, `pushSnapshot()` at
  `tool_dispatcher.dart:263`; seat B: a coach-memory injury can never be cleared by the user). The leg was REMOVED
  (founder d78: the profile is the only signal; the four unmapped parts map to the nearest joint), which deletes the
  fail-open / fail-closed split, the `coach:` tokens and both P1s. The d77 writer now uses `patchProfileWith` under the
  lock, is best-effort, locks `injuries` against extraction, invalidates the profile providers, and the preview line
  shows in both branches (round 5 A-F2 / A-F3 / A-F4, B-F2 / B-F3 / B-F6 / B-F8). `shortenDay` drops the finisher
  first (founder d79, B-F7). `WorkoutDayData.finisherSeconds` feeds the label (B-F5); the preview guard (B-F9).
- Round 4 (2026-11-16, two Sonnet seats, on rev 4): seat B converged (no P0/P1); seat A not: P1 the coach-memory
  signal is not durable (`pushSnapshotNow` replaces the local `coach_memory`, the coach tool's `{part}` entry is never
  pushed; and the server extractor writes plain strings) -> founder d77 (the coach injury goes to the profile), both
  entry shapes counted (§2.1). P2: the generation read's failure direction (fails open; display fails closed), Hive-less
  display tests (`setUpHiveForTests`, a failure pin), §2.2 vs §2.1 injuries argument (`finisherInjuries` at both call
  sites; `pickV4` keeps the plain list), the user never sees `shortenDay`'s message (new code
  `target_too_low_finisher` and the dispatcher string), `estimateDayMinutesFromPlanDay` and three callers (required
  argument on both estimators). P3: hotel n = 1 / 7, test directories, two renderers not three (`muscleLabel` null,
  `copyWith`), the preview line's grammar, accepted surfaces (§2.3).
- Round 3 (2026-11-16, two Sonnet seats, on rev 3): not converged; the digest table held (complete), the OFF
  byte-identity of every changed builder, the time arithmetic, the generateV4 callers. Both P1s were the injured
  signal: seat A F1 `fromProfile` keeps `['none']` (every uninjured user would lose the finisher), seat B F1 the coach's
  injury lives in `coach_memory` only (a stored HIIT shown to a user the coach knows is hurt); one predicate
  `FinisherSafety.isInjured` over both, used by generation and display (§2.1, §2.3). Seat A: P2 the attribution oracle
  (b) not checkable (week-shared ledger; split with `debugReserve`, §3), P2 the short finisher's count-floor figure
  (measured 0, §2.2), P2 the hotel planner drops the reserved finisher (copies it, §2.3), P3 test citations (§2.1, §3),
  P3 SoT / CLAUDE.md anchors (§4). Seat B: P2 the detail-line plumbing (`detailText`, §2.3), P2 the pins and test call
  sites of the required argument (§2.3), P2 `shortenDay`'s refusal text (§2.3), P3 the tick key vs the title (§2.3),
  P3 one context reader (§2.3), P3 the preview screen and `finisherSecondsOfPlanDay` defaults (§2.3).
- Round 2 (2026-11-16, two Sonnet seats, on rev 2): not converged; the engine design held (day indices, the OFF
  arithmetic, d76's minutes, every generateV4 caller checked clean). Seat A: P1 seven more plan digests and fixtures
  embed the finisher (§3 table), P2 the injury sweeps and r6 gates plus a finisher-safety scan (§3), P2 a checkable
  re-record oracle (§3 attribution test), P3 the preview's missing exclusions and the `equipment_owned` signal (accepted,
  §2.1). Seat B: P1 timed finisher rows would show wrong durations (`parseTimedDurationSecs` ignores
  `duration_seconds`; own parse and detail line, §2.3), P2 `shortenDay`'s real floor (2 exercises, `target_too_low`,
  §2.3), P2 one map-based reader function (§2.3), P2 a pricing parity test (§3), P2 the preview through the reader rule
  (§2.3), P2 the days-length assertion (§3), P3 the tick-key wording, P3 a required minutes argument (§2.3).
- Measurement and d76 (2026-11-16): the table in §2.2 (prototype, then a 4-minute variant under 60); the founder chose
  the short finisher under 60 minutes.
- Round 1 (2026-11-16, two Sonnet seats, context-blind): not converged. Seat A: P1 the four kill-switch golden tests
  would redden (fixed §3), P1 the reservation's cost at 30 / 45 minutes unmeasured (measured, §2.2, founder), P2 the
  gate oracles that restate the day budget (§3), P2 the HIIT time understated (round rests, §2.1), P2 `shortenDay`
  (§2.3), P3 day count and position (§2.2), P3 edge cases (§2.1, §3). Seat B: P1 a stored finisher shown to a user
  injured after generation (the reader rule, §2.3), P2 `shortenDay`, P2 the switch read per row (once per build, §2.3),
  P2 test gaps (§3), P2 the coach snapshot (it reads no minutes, §1), P3 section keys, colour, pricing, §2.4 wording.
