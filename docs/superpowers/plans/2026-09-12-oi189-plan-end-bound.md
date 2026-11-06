# OI-189 — Every phase-layout writer stops at `plan_end`; every regen sweeps past it — Implementation Plan (v5, post round-4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the founder's phase-window rule structurally true for every phase-LAYOUT writer (A initial generation — rows already bounded by construction; B Edit-Profile regen — bounded since Unit 2; C AI-coach regen — bounded here), make BOTH regen paths sweep non-completed rows already past `plan_end`, and make the window itself DURABLE — every writer that moves `plan_end` or sweeps against it pushes `plan_json` immediately — so after any regen no planned row sits past the phase end on the phone or in the `plan_json` cloud copy, and a stale cloud window can no longer be mirrored back over a live one on the next launch. Closes **OI-189**. **OI-174 stays OPEN, narrowed** (founder decision A, 2026-09-12).

**Architecture:** One shared sweep helper on `WorkoutScheduleReadService` (key-scan, date-only comparison, keeps `completed`, removes `displaced_` shadows and rest rows too but COUNTS only workout rows — `type` neither `rest` nor `off`, the `_scheduledWorkoutDays` predicate, the number the user sees; no-op unless BOTH window keys are stored; `dryRun` for previews). Writer C's planner gets the literal-date bound writer B already has (`workout_schedule_read_service.dart:489`) and reports the bounded week count + the number of workouts the commit will clear. Both dispatcher commit sites and writer B call the sweep; B and both commit sites push `plan_json` via `SyncService.instance.pushWorkoutPlanForSyncDomain()` (the `holdWeek` durability precedent, `workout_schedule_write_service.dart:359-367`) on EVERY exit that follows a sweep — including the "nothing to write" branch, which now returns SUCCESS carrying `cleared: N` when the sweep removed something (so `execute()`'s invalidate/sync tail runs) and failure only when it removed nothing. Writer A pushes ONLY when its new `pushPlanWindow: true` argument is passed, which happens at exactly the two phase-advance sites (`autoGenerateNextPhaseIfNeeded`, `pro_phase_advance.dart`) — because A also runs on the reinstall / new-device sign-in path against a FRESH Hive, before the cloud `plan_json` is restored, and an unconditional push there would REPLACE the cloud's only copy with a history-free plan (round 3 F1). No schema, no Edge Function, no flag. Prod census 2026-09-12: 10 users, **0** rows past `plan_end_date` in `user_progress.plan_json` AND **0** in `scheduled_workouts`.

**Tech Stack:** Flutter/Dart, Hive (`workoutBox` `schedule_YYYY-MM-DD` rows + `displaced_YYYY-MM-DD` shadows, user-scoped `plan_start_date` / `plan_end_date` via `MigratedKey`), Riverpod `ToolDispatcher`, `flutter test` behavioural tests under `test/contracts/`, `setTestClockTo`/`resetTestClock` (`lib/core/utils/ist_date.dart:35,38`) for the `nowWall()` seam.

**Spec:** The founder's stated plan-lifecycle model, verified claim-by-claim against `main` @ `39111d1e` on 2026-09-12 and recorded in the harness memory `project_regen_alignment_brainstorm_inflight.md` ("2026-09-12 — OI-189 brainstorm", "LOCKED 2026-09-12"). Board entries are plan INPUTS: `docs/audit/open_issues.md` OI-189 (`:3830`), OI-174 (`:3285`), OI-190 (`:3846`), OI-166 (`:3220`), OI-175 (P1-A regression note). Parent diagnose: `docs/diagnoses/2026-09-11-oi166-unit2-regen-content-cycling-d7f3b2.md`. Stale-window precedent the sweep must not weaponise: diagnose `c9e4b7` / `a1d4f9`, documented at `workout_schedule_read_service.dart:1573-1585` (founder account, `current_phase=2`, `plan_start=2026-04-27`; `PlanWindowReanchor` mirrors cloud → local on every launch, `plan_window_reanchor.dart:45-60`).

**Founder decisions locked 2026-09-12:**
- **D1 — restore residual: option A.** Unit stays `account`. OI-174 remains OPEN, narrowed. No restore-path change here.
- **D2 — user-placed rows past `plan_end` are swept too.** The only writers that can CREATE such rows: `assignTemplateToDate` (`template_service.dart:204`), the coach hotel workout (`tool_dispatcher.dart:784`), the coach reschedule destination (`:702`). `swapDays`, `activateTravelMode`, `pauseRange` only modify EXISTING rows.

## Global Constraints

- **Branch / worktree:** `oi189-plan-end-bound` at `.claude/worktrees/oi189-plan-end-bound` (base `39111d1e`). Every edit and every `git add` happens THERE; use absolute paths in every command (cwd resets). Primary folder is integration-only (§4.13).
- **Blast radius:** **`platform`** — corrected 2026-09-13 at staging time: the plan said `account` (classified before round 4), but round 4 F3's one-line `pausedForSimulation` guard lives in `lib/core/services/sync/sync_workout.dart`, which `docs/blast_radius.yaml` pins `platform` (every other staged path is `account` or below; classified file-by-file via `scripts/blast_radius_from_diff.dart -`). Consequence: `bpass: accepted` in the plan-review record is now MANDATORY at the merge gate rather than advisory — it was being run regardless; `review_rounds: 5 ≥ 2`; no Hermes (that is catastrophic only). Record at `docs/plan-reviews/oi189-plan-end-bound.md` (`review_rounds: 5`, `ground_truth_verified: true`, `verdict: converged`), self-initiated `/code-review` B-pass BEFORE the `--no-ff` merge (§4.3). `bpass: accepted` only from the founder's explicit word.
- **Commits:** only `sh scripts/safe_commit.sh "<msg>"` and ONLY when the founder says "commit". Steps say **Stage**. One commit for the unit.
- **Commit subject:** `fix(regen): coach regen stops at plan_end; both regen paths sweep rows past it; window pushes are immediate — OI-189` with body lines `closes-diagnose: b9e4d1` and `closes-oi: OI-189` (OI-174 does NOT close).
- **Bound is a LITERAL DATE comparison** on date-only local midnights (`DateTime(d.year, d.month, d.day).isAfter(planEndDay)` — normalised on BOTH sides, F14), never a week-bucket comparison (`d7f3b2` sub-defect 1).
- **The bound applies to EVERY `plan()` call, explicit `startDate` included** (F5 (a)). Only the horizon is bounded; that branch's CONTENT selection (repeat-last) stays untouched.
- **Completed rows are never deleted or overwritten**, inside or outside the window.
- **Sweep ⇒ push, on every exit.** `pushSnapshot()` is the `daily-snapshot` EF and `syncWorkoutData()` runs `_syncScheduledWorkouts` only — neither carries `plan_json`; `_restoreWorkoutPlan` runs on EVERY returning-user launch (`sync_service.dart:1383` inside `restoreLightweightAlways`), so anything not pushed is mirrored back from cloud at the next launch. `_syncWorkoutPlan` rebuilds `schedules` from local keys (REPLACE, `sync/sync_workout.dart:1035-1043`) and is a silent no-op when `current_plan` is null (`:1028-1029`, F11). `_ensureSessionOpen` returns null with no session (`hive_user_session.dart:123-127`) so the hermetic harness is unaffected; `pausedForSimulation` guards this push FIRST (round 4 F3, below) and the null session is the second line of defence.
- **Window-move ⇒ push ONLY on a phase advance (round 3 F1).** Writer A is reached from FIVE call sites and three of them are boot/repair paths on a possibly-fresh Hive: `auth_session_bootstrapper.dart:653` (`hydrateFromCloud`, runs from `_ensureLocalUser` at sign-in, BEFORE `restoring_screen.dart:110-114` starts `restoreFromCloudForUser` — and `:536` writes `onboarding_completed` from the cloud row first, so `!hasPlan() && onboarding_completed` is TRUE on every reinstall), `train_provider.dart:669` (`_autoGeneratePlan`, from a provider build), `onboarding_provider.dart:554` (first plan). A push from any of those REPLACES cloud `plan_json` — the only cloud copy holding exercises and hold rows — with a fresh plan, and the restore that follows then mirrors that fresh plan back. So `generateAndSchedule` gains `bool pushPlanWindow = false` and pushes only when true; the facade (`workout_schedule_service.dart:78-104`) does NOT forward it (so the three sites above cannot opt in by accident), and `true` is passed at exactly two sites: `workout_schedule_read_service.dart:617` (`autoGenerateNextPhaseIfNeeded`, internal, guarded by `isPhaseExpired()` at `:588` which is false with no stored window) and `pro_phase_advance.dart:582` (reads the read service directly via `workoutScheduleReadServiceProvider`, `:515`; user-initiated). `simulation_service.dart:162` (dev) stays default. Writer B's only caller is `edit_profile_screen.dart:2029` (user-initiated) — its push stays unconditional. ⚠ `train_provider.dart`'s `_autoGeneratePlan` has TWO triggers — `:713` (no plan) and `:742` ("plan metadata exists but schedule is empty — regenerate", i.e. an EXISTING account whose week-1 rows were lost) — and the second moves the window on an existing account without a push. OFF is still right for it (a push would replace the cloud copy with a repair plan); it is named in the parameter comment and the diagnose-doc so nobody "fixes" it by opting in (round 4 F5).
- **`redoWeek4` is the one remaining window-mover and it pushes too (round 4 F2).** `workout_schedule_write_service.dart:178-215` moves `plan_end_date` at `:214` and pushes nothing, and it is the LIVE free-tier path — `runFreeTierRepeatWrite` (`lib/features/train/widgets/keep_training_phase1_action.dart:30-36`) routes to it whenever `enable_hold_weeks` is OFF, its default. A reinstall in the gap takes the stale cloud window verbatim (`PlanWindowReanchor.resolve`, fresh install ⇒ cloud authoritative), `_restoreScheduledWorkouts` brings the redo rows back PAST it, and the next regen's sweep would delete that week. It gets the identical durability block `holdWeek` already carries 150 lines below (`:359-367`), after `:214`; pinned (presence + order) with mutation M18. With this, every writer that MOVES the window on an existing account pushes: A at its two advance sites, B, `holdWeek`, `redoWeek4`. The restore-side window writers (`sync/sync_workout.dart:1126,1129`, `plan_integrity_reconciler.dart:286-287`) MIRROR the cloud window rather than move it — the OI-174 residual.
- **`pushWorkoutPlanForSyncDomain()` gains the `pausedForSimulation` guard its siblings have (round 4 F3).** The dev year-sim (`simulation_service.dart:550` → `autoGenerateNextPhaseIfNeeded` → `:617`, now `pushPlanWindow: true`) would otherwise perform an AWAITED whole-schedule `plan_json` upsert on every simulated advance (~30 per run) INSIDE the loop where `SyncService.pausedForSimulation = true` (`:213-288`) exists precisely to keep per-write pushes off the network. `syncWorkoutData` (`sync/sync_workout.dart:31`), `pushSnapshot` (`sync_service.dart:1055`) and `flushPendingSyncs` (`:363`) all guard FIRST; this entry point (`sync/sync_workout.dart:2096-2100`) did not. First line becomes `if (SyncService.pausedForSimulation) return;` — which also covers the existing `holdWeek` / `deload_evaluator` pushes during a sim. Pinned (order: guard before `_ensureSessionOpen`) with mutation M19. In the hermetic harness (`pausedForSimulation = true`) the guard now returns first; the null session is the second line of defence.
- **The push is AWAITED at every site** (holdWeek precedent, `write_service:359-367`; `deload_evaluator.dart:287` is the other precedent and is `unawaited` because it sits on cold-launch navigation — none of these sites does). `_syncWorkoutPlan` is self-catching (offline → failure into its own catch → telemetry). ⚠ Its upsert (`sync/sync_workout.dart:1045-1048`) carries no `.timeout()`, and at the two coach commit sites the await sits inside `execute()`, so the confirm card's spinner (`tool_confirm_card.dart:40-52`) waits on it — the same exposure `holdWeek` accepted (round 4 F6). Stated in the diagnose-doc; not wrapped here so the five sites keep one shape.
- **`sweepNonCompletedRowsPastPlanEnd` returns a record `({int workouts, int removed})`** (round 3 F5 + round 4 F4). `removed` = every key deleted (non-completed `schedule_*` rows of any type + `displaced_` shadows) — the dispatcher branches on it, because a sweep that removed only rest rows or shadows still changed Hive and must reach `execute()`'s invalidation tail. `workouts` = the subset whose `type` is neither `rest` nor `off` — the same predicate as `_scheduledWorkoutDays` (`:1500-1501`), i.e. exactly the set that keeps `isPhaseExpiredFrom` false — and it is what the preview shows the user ("N workouts … will be cleared") and what `cleared:` carries.
- **Source pins are PRESENCE-only and say so.** The five push sites (six blocks — the regen handler carries two) and the `pushPlanWindow` wiring cannot be observed behaviourally offline (`_syncWorkoutPlan` needs a live Supabase client; the OI-171 precedent `deload_eval_behavioral_test.dart:722-763` states the same limit). They are pinned by position (presence + order against a landmark) and each pin has a mutation leg (Task 6 M11-M19). The diagnose-doc says this in `regression_test_planned`.
- **Telemetry signature:** `ErrorTelemetry.recordNonFatal(Object error, StackTrace? stack, {required String reason, Map<String, String>? extra})` (`error_telemetry.dart:221-226`). Use `reason:`; there is no `context:` (F7).
- **No EF change.** `regeneratePlanBlock.ts:5-6,42,54` still tells the model "1-12 weeks … start a new phase" and authors the confirm card's summary line ("Regenerate next N weeks", rendered by `tool_confirm_card.dart:307` — F12). Catastrophic-tier deploy; founder decision; recorded on OI-190.
- **Copy** in the diff previews follows the existing sibling lines; no raw `GoogleFonts`; dates via `_dayLabel`. No "Your next phase is set up when this one ends" — false for free users (F4). When `totalWeeks == 0` the note REPLACES header+eyebrow (F9).
- **Tests:** every new assertion mutated once; NINETEEN legs (Task 6 Step 0 — ten behavioural M1-M10, nine source-pin M11-M19); a mutation must COMPILE and be semantically wrong; confirm applied with `grep -c`; record the FIRST-FAILING assertion as the run reports it (F10).
- **Test census** command in Task 6 Step 1 (basenames + `workout_schedule_service`, F13), not a hand list.
- **`flutter analyze lib/ test/`** → 0 warnings, counted with `grep -c "^\s*warning -"`. Note `dead_code` is a WARNING here (round 2 verified) — no dead statements after a `return`.
- **Line anchors re-derived 2026-09-13 after round 4** (`sync_workout.dart` lives at `lib/core/services/sync/`; `execute()`'s catch is `tool_dispatcher.dart:227`, not `:1482`); re-derive again from the working tree before every edit.

---

## File structure

| File | Responsibility in this unit |
|---|---|
| `lib/core/services/workout_schedule_read_service.dart` | **Modify.** (a) NEW `sweepNonCompletedRowsPastPlanEnd({bool dryRun = false})` above `_scheduledWorkoutDays` (`:1489`); (b) `generateAndScheduleFromDate`: sweep after the delete loop (`:377`), push between the write loop's brace (`:560`) and `return plan;` (`:562`); (c) `generateAndSchedule` (writer A): new `bool pushPlanWindow = false` parameter; push between its loop's brace (`:319`) and `return plan;` (`:321`) ONLY when true; (d) `autoGenerateNextPhaseIfNeeded` passes `pushPlanWindow: true` at `:617`. |
| `lib/shared/services/pro_phase_advance.dart` | **Modify.** `:582` `scheduleSvc.generateAndSchedule(` gains `pushPlanWindow: true`. |
| `lib/core/services/workout_schedule_write_service.dart` | **Modify.** `redoWeek4`: the holdWeek durability block after the `plan_end` write (`:214`), `reason: 'redo_week4_durability_push'`. |
| `lib/core/services/sync/sync_workout.dart` | **Modify.** `pushWorkoutPlanForSyncDomain()` (`:2096`): `if (SyncService.pausedForSimulation) return;` as its first statement. |
| `lib/features/ai_coach/services/regenerate_plan_planner.dart` | **Modify.** `plan()` reads `plan_end_date`, skips every day after it, reports `totalWeeks` (bounded), `requestedWeeks`, `phaseEndsOn`, `clearsPastPhaseEnd`. |
| `lib/features/ai_coach/services/tool_dispatcher.dart` | **Modify.** `_executeRegeneratePlanBlock`: sweep → on empty: push, then success-with-`cleared` (`swept.removed > 0`) or failure (`swept.removed == 0`) → writes → splice → push; `_executeSwitchGoal`: profile check → sweep → profile write → writes → splice → push. `execute()` is NOT touched (round 3 F2 supersedes round 2 F1: no failure path mutates Hive any more). |
| `lib/features/ai_coach/widgets/diff_preview/regenerate_plan_diff.dart`, `switch_goal_diff.dart` | **Modify.** `_phaseNote` (three forms); note replaces header when `totalWeeks == 0`. |
| `test/contracts/oi189_plan_end_bound_behavioral_test.dart` | **Create.** Eleven behavioural tests through the real paths + one source-pin group (eight pin tests: five push blocks by presence AND order, the sim guard by order, `pushPlanWindow` wired at exactly the two advance sites and nowhere else). Harness from `oi166_unit2_regen_content_cycling_behavioral_test.dart:25-129`. |
| `docs/diagnoses/2026-09-12-regen-writers-stop-at-plan-end-b9e4d1.md` | **Create.** `blast_radius: platform` (see Global Constraints); `sot_registry_entry: workout_schedule_read_path`. |
| `docs/audit/open_issues.md` | **Modify.** OI-189 CLOSED; OI-174 OPEN, rewritten narrowed (incl. the stale-window/offline residual); OI-190 (+ F12 EF-copy input), OI-166 refreshed. |
| `docs/plan-reviews/oi189-plan-end-bound.md` | **Create.** |
| `lib/features/train/CLAUDE.md:68`, `lib/features/ai_coach/CLAUDE.md:52-55` | **Modify.** One sentence each. |
| `docs/sot_registry.yaml` | **Refresh** the `line_range`s the parity gate names (round-1 Q7 list). |

**Interfaces shared across tasks**

- `WorkoutScheduleReadService.sweepNonCompletedRowsPastPlanEnd({bool dryRun = false}) → Future<({int workouts, int removed})>` — `removed` = every key deleted (or, dry-run, that would be): non-completed `schedule_*` rows of any type + `displaced_` shadows past `plan_end`; `workouts` = the subset with `type` neither `rest` nor `off`. `(workouts: 0, removed: 0)` and no writes unless BOTH `plan_start_date` and `plan_end_date` are stored.
- `WorkoutScheduleReadService.generateAndSchedule({…, bool pushPlanWindow = false})` — pushes `plan_json` after its rows only when true. The facade `WorkoutScheduleService.generateAndSchedule` does NOT gain the parameter.
- `RegeneratePlanResult` gains `requestedWeeks`, `phaseEndsOn`, `clearsPastPhaseEnd`; `totalWeeks` becomes the bounded count. One constructor site (`regenerate_plan_planner.dart:362`).
- `SyncService.instance.pushWorkoutPlanForSyncDomain()` (`sync/sync_workout.dart:2096`).
- `ToolExecutionResult.success(data:)` / `.failure(msg)` / `.errorMessage` (`tool_dispatcher.dart:47-58`); the regen block's and switch-goal's success `data` gain `'cleared': <int>` (= `swept.workouts`) on every success return.

**The shared durability block** (verbatim at five sites — A (inside `if (pushPlanWindow)`), B, `redoWeek4`, both commit sites — with the `reason:` string varying; `holdWeek` already carries it at `write_service:359-367`):

```dart
    try {
      await SyncService.instance.pushWorkoutPlanForSyncDomain();
    } catch (e, st) {
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: '<site>_plan_window_push'));
    }
```

`SyncService`, `ErrorTelemetry` and `dart:async` are already imported in both files (`workout_schedule_read_service.dart:21,26`; `tool_dispatcher.dart:8,14`).

---

### Task 1: The shared sweep helper + its tests

**Files:**
- Modify: `lib/core/services/workout_schedule_read_service.dart` — insert above `/// Dates of real (non-rest/off) scheduled workout days in the local schedule.` (`:1489`).
- Test: `test/contracts/oi189_plan_end_bound_behavioral_test.dart` (create).

- [ ] **Step 1: Create the test file with the harness and the first failing tests**

Copy lines 25-129 of `test/contracts/oi166_unit2_regen_content_cycling_behavioral_test.dart` verbatim (from `// ignore_for_file: invalid_use_of_visible_for_testing_member` through `scheduleRow`), change the temp-dir prefix to `test_oi189_plan_end_bound`, add `import 'package:icanbefitter/core/utils/ist_date.dart';` and `import 'package:icanbefitter/features/home/providers/home_provider.dart';` and `import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';`, and add `resetTestClock();` as the first line of `tearDown`. Then:

```dart
  Future<void> seedWindow(DateTime planStart, {int endOffset = 27}) async {
    await MigratedKey.write('plan_start_date', planStart.toIso8601String());
    await MigratedKey.write('plan_end_date',
        planStart.add(Duration(days: endOffset)).toIso8601String());
  }

  Future<void> seedRow(DateTime d,
      {String name = 'OLD_GOAL_ORPHAN',
      String status = 'planned',
      String type = 'workout'}) async {
    await HiveService.instance.workoutBox.put(scheduleKeyFor(d), {
      'date': svc.dateKey(d),
      'type': type,
      'workout_name': name,
      'status': status,
      'exercises': const <Map<String, dynamic>>[],
    });
  }

  group('sweepNonCompletedRowsPastPlanEnd — helper', () {
    test('removes planned + rest rows and displaced_ shadows past plan_end, '
        'keeps completed rows, never touches rows inside the window; dry run '
        'counts without deleting; idempotent', () async {
      final planStart = DateTime(2026, 6, 1); // Monday
      await seedWindow(planStart); // plan_end = +27
      final box = HiveService.instance.workoutBox;
      for (var offset = 20; offset <= 34; offset++) {
        await seedRow(planStart.add(Duration(days: offset)),
            status: offset == 30 ? 'completed' : 'planned');
      }
      // Overwrites the +33 planned row with a rest row (same key).
      await seedRow(planStart.add(const Duration(days: 33)),
          type: 'rest', status: 'rest', name: 'Rest Day');
      final displacedIn =
          'displaced_${svc.dateKey(planStart.add(const Duration(days: 25)))}';
      final displacedOut =
          'displaced_${svc.dateKey(planStart.add(const Duration(days: 29)))}';
      await box.put(displacedIn, {'shadow': true});
      await box.put(displacedOut, {'shadow': true});

      // Past plan_end: workout rows +28,+29,+31,+32,+34 = 5 `workouts` (+30
      // completed excluded); +33 is a rest row and displaced_+29 a shadow —
      // both REMOVED, so `removed` = 7. `workouts` is what the preview shows
      // the user and what _scheduledWorkoutDays keys the expiry on; `removed`
      // is what the dispatcher branches on (Hive changed ⇒ invalidate).
      final dry = await svc.sweepNonCompletedRowsPastPlanEnd(dryRun: true);
      expect(dry.workouts, 5);
      expect(dry.removed, 7);
      expect(scheduleRow(planStart.add(const Duration(days: 28))), isNotNull,
          reason: 'dry run must not delete');

      final swept = await svc.sweepNonCompletedRowsPastPlanEnd();
      expect(swept.workouts, 5);
      expect(swept.removed, 7);
      for (var offset = 20; offset <= 27; offset++) {
        expect(scheduleRow(planStart.add(Duration(days: offset))), isNotNull,
            reason: 'in-window row +$offset must survive');
      }
      for (var offset = 28; offset <= 34; offset++) {
        final row = scheduleRow(planStart.add(Duration(days: offset)));
        if (offset == 30) {
          expect(row, isNotNull, reason: 'completed history must survive');
          expect(row!['status'], 'completed');
        } else {
          expect(row, isNull, reason: 'row +$offset past plan_end must be swept');
        }
      }
      expect(box.containsKey(displacedIn), isTrue);
      expect(box.containsKey(displacedOut), isFalse);
      expect((await svc.sweepNonCompletedRowsPastPlanEnd()).removed, 0,
          reason: 'idempotent: nothing left to sweep');
    });

    // Behaviour-INVARIANT (a helper that always returned 0 would also pass
    // the first half) — the second half is the real pin: plan_end WITHOUT
    // plan_start must not count as a window (F10; restore writes the keys
    // independently, sync_workout.dart:1126-1131).
    test('no stored window (plan_end OR plan_start missing): no-op, returns 0',
        () async {
      final stray = DateTime(2027, 1, 4);
      await seedRow(stray, name: 'STRAY');
      expect((await svc.sweepNonCompletedRowsPastPlanEnd()).removed, 0);
      expect(scheduleRow(stray), isNotNull);
      await MigratedKey.write(
          'plan_end_date', DateTime(2026, 6, 28).toIso8601String());
      expect((await svc.sweepNonCompletedRowsPastPlanEnd()).removed, 0,
          reason: 'a half-restored window is not a window');
      expect(scheduleRow(stray), isNotNull);
    });
  });
```

- [ ] **Step 2: Run to verify it fails** — compile error, method undefined (Task 6 mutations are the behavioural reds).

- [ ] **Step 3: Implement the helper** (above `:1489`):

```dart
  /// OI-189 (diagnose b9e4d1): remove every NON-completed `schedule_*` row and
  /// every `displaced_*` shadow dated strictly after the STORED plan_end.
  /// Returns `removed` — every key deleted (or, when [dryRun], that would be)
  /// — and `workouts`, the subset of those rows whose type is neither rest
  /// nor off: the number the coach preview shows ("N workouts … will be
  /// cleared") and exactly the set [_scheduledWorkoutDays] keys the
  /// phase-expiry on. Callers that change UI state branch on `removed`
  /// (a rest-only sweep still changed Hive); copy uses `workouts`.
  ///
  /// Why: both regen writers stop their WRITE range at plan_end
  /// (generateAndScheduleFromDate :489; RegeneratePlanPlanner.plan()), so a
  /// row already past plan_end is neither rewritten nor deleted by a regen.
  /// Such rows exist(ed) from the pre-Unit-2 Edit-Profile write loop, the
  /// coach path before its own bound, and three user-directed writers that
  /// accept an arbitrary date (assignTemplateToDate, the coach hotel workout,
  /// the coach reschedule destination). Left alone they keep the OLD goal's
  /// workouts after a goal change AND keep [isPhaseExpiredFrom] reporting the
  /// phase alive, which blocks the next phase from ever generating (OI-174's
  /// advance-delay half). Founder decision 2026-09-12: user-placed rows past
  /// plan_end are swept too — the next phase's generation overwrites those
  /// dates regardless, and while they exist that generation never runs.
  ///
  /// Completed rows are history and stay — the same rule the in-window delete
  /// loop applies. Requires BOTH plan_start_date and plan_end_date: a restore
  /// writes the keys independently (sync_workout.dart:1126-1131) and that
  /// partial state is not a window. Key scan, not a date loop: no horizon
  /// assumption (the coach path could write up to 12 weeks); same shape as
  /// [_scheduledWorkoutDays]. Local Hive only — every caller pushes plan_json
  /// right after (SyncService.pushWorkoutPlanForSyncDomain, the holdWeek
  /// precedent), because _restoreWorkoutPlan mirrors cloud plan_json back on
  /// EVERY launch. The cloud `scheduled_workouts` copy is NOT pruned here
  /// (OI-174, open).
  ///
  /// ⚠ This makes `plan_end_date` DESTRUCTIVE. It trusts the stored window;
  /// a window mirrored back from a STALE cloud copy (diagnose c9e4b7 —
  /// PlanWindowReanchor treats cloud as authoritative on a phase advance,
  /// plan_window_reanchor.dart:54-57) would make the live phase's rows look
  /// like orphans. That is why the two phase-advance sites now push plan_json
  /// the moment they move the window (generateAndSchedule with the
  /// pushPlanWindow flag set — the ONLY callers that set it) — an advance
  /// that could not push (offline) leaves
  /// that revert window open until the next successful push; recorded on
  /// OI-174.
  Future<({int workouts, int removed})> sweepNonCompletedRowsPastPlanEnd(
      {bool dryRun = false}) async {
    const nothing = (workouts: 0, removed: 0);
    final startStr = MigratedKey.read<String>(_planStartKey);
    final endStr = MigratedKey.read<String>(_planEndKey);
    if (startStr == null || endStr == null) return nothing;
    final planEnd = DateTime.tryParse(endStr);
    if (planEnd == null) return nothing;
    final planEndDay = DateTime(planEnd.year, planEnd.month, planEnd.day);
    const displacedPrefix = 'displaced_';
    final box = _hive.workoutBox;
    final doomed = <dynamic>[];
    var workoutRows = 0;
    for (final key in box.keys) {
      final k = key.toString();
      final isSchedule = k.startsWith(_schedulePrefix);
      final isDisplaced = k.startsWith(displacedPrefix);
      if (!isSchedule && !isDisplaced) continue;
      final dateStr = isSchedule
          ? k.substring(_schedulePrefix.length)
          : k.substring(displacedPrefix.length);
      final d = DateTime.tryParse(dateStr);
      if (d == null) continue;
      if (!DateTime(d.year, d.month, d.day).isAfter(planEndDay)) continue;
      if (isSchedule) {
        final v = box.get(key);
        final status = v is Map ? (v['status'] as String? ?? '') : '';
        if (status == 'completed') continue;
        // Same predicate as _scheduledWorkoutDays (:1500-1501), so the count
        // is exactly the set that keeps isPhaseExpiredFrom false.
        final type = v is Map ? (v['type'] ?? '').toString() : '';
        if (type != 'rest' && type != 'off') workoutRows++;
      }
      doomed.add(key);
    }
    if (!dryRun) {
      for (final key in doomed) {
        await box.delete(key);
      }
    }
    return (workouts: workoutRows, removed: doomed.length);
  }

```

- [ ] **Step 4: Run — 2 PASS.**
- [ ] **Step 5: Stage** `git add lib/core/services/workout_schedule_read_service.dart test/contracts/oi189_plan_end_bound_behavioral_test.dart`

---

### Task 2: Writers A and B — sweep (B), push the window (B always; A only on a phase advance)

**Files:**
- Modify: `workout_schedule_read_service.dart` `generateAndSchedule` (A; signature `:170-185`, loop brace `:319`, `return plan;` `:321`), `generateAndScheduleFromDate` (B; delete-loop brace `:377`; write-loop brace `:560`, `return plan;` `:562`), `autoGenerateNextPhaseIfNeeded` (`:617`).
- Modify: `lib/shared/services/pro_phase_advance.dart:582`.
- Test: same file, new group.

- [ ] **Step 1: Write the failing tests**

```dart
  group('writer B — generateAndScheduleFromDate sweeps past plan_end', () {
    test('mid-window regen: orphans +28..+34 swept (completed kept), '
        'in-window planned row rewritten, plan_end unchanged', () async {
      final planStart = DateTime(2026, 6, 1);
      await seedWindow(planStart);
      setTestClockTo(planStart.add(const Duration(days: 10)));
      for (var offset = 28; offset <= 34; offset++) {
        await seedRow(planStart.add(Duration(days: offset)),
            status: offset == 30 ? 'completed' : 'planned');
      }
      final inWindow = planStart.add(const Duration(days: 20));
      await seedRow(inWindow, name: 'OLD_GOAL_IN_WINDOW');

      await svc.generateAndScheduleFromDate(
        goal: 'build_muscle', equipment: 'full_gym', daysPerWeek: 4,
        fromDate: planStart.add(const Duration(days: 10)),
      );

      for (var offset = 28; offset <= 34; offset++) {
        final row = scheduleRow(planStart.add(Duration(days: offset)));
        if (offset == 30) {
          expect(row, isNotNull, reason: 'completed history must survive');
          expect(row!['workout_name'], 'OLD_GOAL_ORPHAN');
        } else {
          expect(row, isNull, reason: 'planned orphan at +$offset must be swept');
        }
      }
      final rewritten = scheduleRow(inWindow);
      expect(rewritten, isNotNull);
      expect(rewritten!['workout_name'], isNot('OLD_GOAL_IN_WINDOW'));
      expect(svc.getPlanEndDate(), planStart.add(const Duration(days: 27)));
    });

    test('EXPIRED-phase regen (today > plan_end, orphans on/after today): '
        'writes nothing, sweeps the orphans, isPhaseExpired() flips false→true',
        () async {
      final planStart = DateTime(2026, 6, 1);
      await seedWindow(planStart);
      final today = planStart.add(const Duration(days: 29));
      setTestClockTo(today); // isPhaseExpired() reads nowWall()
      for (var offset = 29; offset <= 34; offset++) {
        await seedRow(planStart.add(Duration(days: offset)));
      }
      expect(svc.isPhaseExpired(), isFalse,
          reason: 'orphan workout rows on/after today keep the phase alive');

      await svc.generateAndScheduleFromDate(
        goal: 'lose_fat', equipment: 'full_gym', daysPerWeek: 4,
        fromDate: today,
      );

      for (var offset = 28; offset <= 41; offset++) {
        expect(scheduleRow(planStart.add(Duration(days: offset))), isNull,
            reason: 'nothing may exist past plan_end after the regen (+$offset)');
      }
      expect(svc.isPhaseExpired(), isTrue);
    });

    // Behaviour-INVARIANT (documents the first-generation boundary).
    test('first generation (no stored window): a stray far-future row is left '
        'alone — there is no horizon to sweep against', () async {
      final stray = DateTime(2027, 1, 4);
      await seedRow(stray, name: 'STRAY');
      await svc.generateAndScheduleFromDate(
        goal: 'general_fitness', equipment: 'full_gym', daysPerWeek: 4,
        fromDate: DateTime(2026, 6, 3),
      );
      expect(scheduleRow(stray), isNotNull);
    });
  });
```

- [ ] **Step 2: Run** — tests 1-2 fail on `must be swept`; test 3 passes.

- [ ] **Step 3: Implement B**

(a) After the delete loop's closing brace (`:377`, before the blank line and `final monday = _normalizeToMonday(today);`):

```dart
    // OI-189: the loop above reaches exactly plan_end and so does the write
    // loop below — a row PAST plan_end is neither deleted nor rewritten by
    // this regen. Sweep it (completed rows stay). No-op on first generation
    // (no stored window). See sweepNonCompletedRowsPastPlanEnd for the why.
    await sweepNonCompletedRowsPastPlanEnd();
```

(b) Between the write loop's closing brace (`:560`) and `return plan;` (`:562`) — NOT after the return (`dead_code` warning):

```dart
    // OI-189 durability: the coalesced syncWorkoutData fan-out above runs
    // _syncScheduledWorkouts only, and pushSnapshot is the daily-snapshot EF —
    // neither carries plan_json. _restoreWorkoutPlan mirrors cloud plan_json
    // back on EVERY launch (restoreLightweightAlways), so without this the
    // swept rows come back tomorrow. Same block holdWeek carries
    // (workout_schedule_write_service.dart:359-367). Self-catching inside;
    // the try/catch guards the _ensureSessionOpen await outside it so a push
    // hiccup can never surface a locally-committed regen as a failure.
    // Silent no-op when current_plan is null (_syncWorkoutPlan :1028).
    try {
      await SyncService.instance.pushWorkoutPlanForSyncDomain();
    } catch (e, st) {
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'regen_from_date_plan_window_push'));
    }
```

- [ ] **Step 4: Implement A — opt-in push**

(a) Add the parameter as the LAST named parameter of `generateAndSchedule`, after `bool applyPlateauEscalation = false,` (`:196`; the signature closes with `}) async {` at `:197`):

```dart
    // OI-189: push plan_json right after the rows ONLY on a phase advance.
    // This writer is also reached from three boot/repair paths —
    // auth_session_bootstrapper.dart:653 (reinstall / new-device sign-in on a
    // FRESH Hive, which runs BEFORE restoring_screen starts the cloud
    // restore), train_provider.dart:669 via _autoGeneratePlan (triggered at
    // :713 with no plan AND at :742 when an EXISTING account's week-1 rows are
    // lost — a repair, not an advance) and onboarding_provider.dart:554 — and
    // a push from any of them would REPLACE the cloud plan_json (the only copy
    // holding exercises + hold rows) with a fresh or repair plan that the
    // restore then mirrors back. The facade does not forward this flag, so
    // those callers cannot opt in by accident. Do NOT "fix" :742 by opting in.
    bool pushPlanWindow = false,
```

(b) Between the loop brace (`:319`) and `return plan;` (`:321`):

```dart
    // OI-189: a phase advance MOVES plan_start/plan_end (:225-226) and until
    // now pushed no plan_json — only weeklyFullSync did, ≤24h later. In
    // between, PlanWindowReanchor treats the CLOUD window as authoritative on
    // a phase advance (plan_window_reanchor.dart:54-57) and _restoreWorkoutPlan
    // runs on every launch, so a same-day relaunch could revert the window to
    // the previous phase (diagnose c9e4b7 — the founder account sat in that
    // state). Harmless while nothing trusted plan_end; now the regen sweep
    // does, and a reverted window would make this phase's rows look like
    // orphans. Push the window the moment an ADVANCE moves it. Offline advance
    // = residual on OI-174. Awaited (holdWeek precedent); _syncWorkoutPlan is
    // self-catching, the try/catch covers the _ensureSessionOpen await.
    if (pushPlanWindow) {
      try {
        await SyncService.instance.pushWorkoutPlanForSyncDomain();
      } catch (e, st) {
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'generate_and_schedule_plan_window_push'));
      }
    }
```

(c) The two phase-advance sites pass it. `workout_schedule_read_service.dart:617` (inside `autoGenerateNextPhaseIfNeeded`, whose `isPhaseExpired()` guard at `:588` is false whenever no window is stored — so it never fires on a fresh Hive):

```dart
    await generateAndSchedule(
      goal: goal,
      // … existing arguments unchanged …
      // OI-189: an advance moves the window — push it now (see the parameter).
      pushPlanWindow: true,
    );
```

and `lib/shared/services/pro_phase_advance.dart:582` (`scheduleSvc` is the READ service via `workoutScheduleReadServiceProvider`, `:515`; user-initiated from the Train screen):

```dart
      await scheduleSvc.generateAndSchedule(
        goal: goal,
        // … existing arguments unchanged …
        // OI-189: an advance moves the window — push it now.
        pushPlanWindow: true,
      );
```

`SyncService` and `ErrorTelemetry` imports: the read service already has both (`:21,26`); `pro_phase_advance.dart` needs nothing new (it only passes a bool).

(d) NOT changed, and pinned that way in Task 4 Step 4: the facade `workout_schedule_service.dart:78-104` (no `pushPlanWindow` anywhere in that file), `auth_session_bootstrapper.dart`, `train_provider.dart`, `onboarding_provider.dart`, `simulation_service.dart`.

- [ ] **Step 5: `redoWeek4` pushes (round 4 F2)** — `lib/core/services/workout_schedule_write_service.dart`, directly after `await MigratedKey.write(_planEndKey, newEnd.toIso8601String());` (`:214`, the last statement of the method, before its closing `}` at `:215`):

```dart
    // OI-189 durability: this is the LIVE free-tier repeat path
    // (runFreeTierRepeatWrite → redoWeek4 while enable_hold_weeks is OFF) and
    // it MOVES plan_end (line above) — the same shape holdWeek carries its own
    // push for (:359-367). Without it a reinstall in the ≤24h gap before
    // weeklyFullSync takes the stale cloud window verbatim (PlanWindowReanchor
    // fresh-install branch), the restore brings the redo rows back PAST it,
    // and the next regen's sweep deletes the week. Awaited; self-catching
    // inside; the try/catch guards the _ensureSessionOpen await.
    try {
      await SyncService.instance.pushWorkoutPlanForSyncDomain();
    } catch (e, st) {
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'redo_week4_durability_push'));
    }
```

`SyncService`, `ErrorTelemetry` and `unawaited` are already in scope in that file (holdWeek uses all three at `:360-367`). The two hermetic tests that call `redoWeek4()` (`hold_display_read_path_test.dart`, `hold_week_mechanic_behavioral_test.dart`) are unaffected: neither sets `pausedForSimulation`; `_ensureSessionOpen()` returns null with no Supabase session (`supabase_service.dart:81-84`), the same path `holdWeek()` already takes in `hold_week_mechanic_behavioral_test.dart:128,147,160` today (round 5 F2).

- [ ] **Step 6: the sim guard (round 4 F3)** — `lib/core/services/sync/sync_workout.dart:2096-2100`:

```dart
  Future<void> pushWorkoutPlanForSyncDomain() async {
    // OI-189: guard FIRST, like syncWorkoutData (:31) / pushSnapshot
    // (sync_service.dart:1055). The dev year-sim drives ~30 phase advances
    // inside its pausedForSimulation window and each now pushes plan_json via
    // generateAndSchedule(pushPlanWindow: true) — the exact per-write network
    // storm that flag exists to prevent. Also covers holdWeek / deload pushes
    // during a sim. Cloud catches up at the next weeklyFullSync, as before.
    if (SyncService.pausedForSimulation) return;
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _syncWorkoutPlan(userId);
  }
```

(Only the guard line + comment are new; the two lines below it are the existing body.)

- [ ] **Step 7: Run — 5 PASS.** Also run the ONE existing test that calls writer A directly (`grep -rln "\.generateAndSchedule(" test/` → `repeat_content_scheduling_test.dart`, round 3) — it passes no `pushPlanWindow`, so nothing changes for it; the two `redoWeek4()` tests above; and `test/contracts/` files naming `pro_phase_advance` (census in Task 6 Step 1).
- [ ] **Step 8: Stage** the read service, `pro_phase_advance.dart`, the write service, `sync/sync_workout.dart`, and the test file.

---

### Task 3: Writer C — bound `plan()`, report honestly

**Files:**
- Modify: `regenerate_plan_planner.dart:61-62` (`totalWeeks`), `:74-81` (ctor), after `:224` (window read), `:260` (day loop), `:362-368` (result).
- Test: same file, new group.

- [ ] **Step 1: Write the failing tests**

```dart
  group('writer C — RegeneratePlanPlanner.plan() stops at plan_end', () {
    ProviderContainer makeContainer() {
      final c = ProviderContainer(overrides: [
        authStateProvider.overrideWith((ref) => const Stream.empty()),
        // Makes todayWorkoutProvider resolvable hermetically: its Notifier
        // watches authUserIdTokenProvider (auth_invalidation_provider.dart:48)
        // which in production derives from the live session/owner edge.
        authUserIdTokenProvider.overrideWithValue(testUser),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    ToolIntent intentFor(String id, String type,
            [Map<String, dynamic> payload = const {'goal': 'general_fitness'}]) =>
        ToolIntent(
          id: id,
          type: type,
          payload: payload,
          confirmationClass: ConfirmationClass.reviewable,
          previewSummary: '',
          createdAt: DateTime.now(),
        );

    test('4 weeks requested, 10 days left: rows stop at plan_end (inclusive), '
        'totalWeeks 2, requestedWeeks 4, phaseEndsOn stamped, clears 0; '
        'dispatch lands nothing past plan_end', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final planStart = today.subtract(const Duration(days: 14));
      final planEnd = today.add(const Duration(days: 10));
      await seedWindow(planStart, endOffset: 24);

      final result = await RegeneratePlanPlanner.instance.plan(
        weeks: 4, goal: 'general_fitness', equipment: 'full_gym', daysPerWeek: 4,
      );
      expect(result.rawSchedules, isNotEmpty);
      for (final s in result.rawSchedules) {
        expect(DateTime.parse(s['date'] as String).isAfter(planEnd), isFalse,
            reason: 'row ${s['date']} is past plan_end ${svc.dateKey(planEnd)}');
      }
      expect(result.plan.totalWeeks, 2);
      expect(result.plan.requestedWeeks, 4);
      expect(result.plan.phaseEndsOn, svc.dateKey(planEnd));
      expect(result.plan.clearsPastPhaseEnd, 0);
      expect(result.rawSchedules.any((s) => s['date'] == svc.dateKey(planEnd)),
          isTrue, reason: 'every non-completed in-window day gets a row');

      const intentId = 'intent_oi189_c1';
      RegeneratePlanPlanner.instance.cache(intentId, result.plan,
          result.rawSchedules, result.phase, result.regenStartWeek);
      final res = await ToolDispatcher.instance.execute(
          makeContainer().read(_refProvider),
          intentFor(intentId, 'regenerate_plan_block'));
      expect(res.success, isTrue);
      for (var offset = 11; offset <= 28; offset++) {
        expect(scheduleRow(today.add(Duration(days: offset))), isNull,
            reason: 'no row may exist at today+$offset (past plan_end)');
      }
      expect(scheduleRow(planEnd), isNotNull);
    });

    test('block FITS the phase but rows exist past plan_end: clearsPastPhaseEnd '
        'reports them (D2: the preview must say what the commit sweeps)',
        () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      await seedWindow(today.subtract(const Duration(days: 7)), endOffset: 27);
      final planEnd = today.add(const Duration(days: 20));
      await seedRow(planEnd.add(const Duration(days: 3)), name: 'HOTEL_PAST_END');
      final result = await RegeneratePlanPlanner.instance.plan(
        weeks: 2, goal: 'general_fitness', equipment: 'full_gym', daysPerWeek: 4,
      );
      expect(result.plan.totalWeeks, 2);
      expect(result.plan.requestedWeeks, 2);
      expect(result.plan.clearsPastPhaseEnd, 1);
      expect(scheduleRow(planEnd.add(const Duration(days: 3))), isNotNull,
          reason: 'plan() is a preview — it must not sweep');
    });

    test('explicit startDate past plan_end: zero rows, totalWeeks 0 — the bound '
        'applies to every plan() call', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      await seedWindow(today.subtract(const Duration(days: 14)), endOffset: 24);
      final planEnd = today.add(const Duration(days: 10));
      final result = await RegeneratePlanPlanner.instance.plan(
        weeks: 2, goal: 'general_fitness', equipment: 'full_gym', daysPerWeek: 4,
        startDate: svc.dateKey(planEnd.add(const Duration(days: 1))),
      );
      expect(result.rawSchedules, isEmpty);
      expect(result.plan.totalWeeks, 0);
      expect(result.regenStartWeek, isNull,
          reason: 'explicit-startDate contract unchanged');
    });

    // Behaviour-INVARIANT (pre-existing behaviour, kept).
    test('no plan_end stored: block stays unbounded', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      await MigratedKey.write('plan_start_date',
          today.subtract(const Duration(days: 7)).toIso8601String());
      final result = await RegeneratePlanPlanner.instance.plan(
        weeks: 3, goal: 'general_fitness', equipment: 'full_gym', daysPerWeek: 4,
      );
      expect(result.plan.totalWeeks, 3);
      expect(result.plan.requestedWeeks, 3);
      expect(result.plan.phaseEndsOn, isNull);
      expect(result.plan.clearsPastPhaseEnd, 0);
      expect(
          result.rawSchedules.any((s) => DateTime.parse(s['date'] as String)
              .isAfter(today.add(const Duration(days: 14)))),
          isTrue, reason: 'week 3 rows exist when nothing bounds the block');
    });

    test('EXPIRED phase + orphans: plan() reports clearsPastPhaseEnd; dispatch '
        'sweeps them and returns SUCCESS with count 0 / cleared 7 (so the '
        'invalidate tail runs); a second dispatch (nothing left to sweep) is '
        'the failure; isPhaseExpired() flips', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      await seedWindow(today.subtract(const Duration(days: 35)), endOffset: 30);
      // plan_end = today-5; orphans today-4..today+3 (8 rows), the completed
      // one BEFORE today (a completed row can only be in the past; and
      // _scheduledWorkoutDays filters by type, not status, so a future-dated
      // completed row would itself keep the phase alive).
      for (var offset = -4; offset <= 3; offset++) {
        await seedRow(today.add(Duration(days: offset)),
            status: offset == -2 ? 'completed' : 'planned');
      }
      expect(svc.isPhaseExpired(), isFalse,
          reason: 'planned orphan rows on/after today keep the phase alive');

      final result = await RegeneratePlanPlanner.instance.plan(
        weeks: 4, goal: 'general_fitness', equipment: 'full_gym', daysPerWeek: 4,
      );
      expect(result.rawSchedules, isEmpty);
      expect(result.plan.totalWeeks, 0);
      expect(result.plan.firstWeek, isEmpty);
      expect(result.plan.clearsPastPhaseEnd, 7, reason: '8 rows, 1 completed');
      expect(scheduleRow(today), isNotNull,
          reason: 'plan() is a preview — it must not sweep');

      const intentId = 'intent_oi189_c2';
      RegeneratePlanPlanner.instance.cache(intentId, result.plan,
          result.rawSchedules, result.phase, result.regenStartWeek);
      final container = makeContainer();
      final ref = container.read(_refProvider);
      // The Home expired-card gate is `todayWorkoutProvider == null &&
      // isPhaseExpired()`; the provider is non-autoDispose, so the dispatch
      // that sweeps today's row must reach execute()'s invalidation tail or
      // the card never shows. That tail runs only on SUCCESS — which is why a
      // sweep that removed something returns success (round 3 F2).
      expect(container.read(todayWorkoutProvider), isNotNull,
          reason: 'today has an orphan row before dispatch');

      final res = await ToolDispatcher.instance.execute(
          ref, intentFor(intentId, 'regenerate_plan_block'));
      expect(res.success, isTrue,
          reason: 'the sweep changed Hive — success so the invalidate tail runs');
      final data = res.data as Map?;
      expect(data, isNotNull);
      expect(data!['count'], 0);
      expect(data['cleared'], 7);
      for (var offset = -4; offset <= 3; offset++) {
        final row = scheduleRow(today.add(Duration(days: offset)));
        expect(row, offset == -2 ? isNotNull : isNull,
            reason: 'commit sweeps planned orphans ($offset), keeps completed');
      }
      expect(svc.isPhaseExpired(), isTrue,
          reason: 'only the past completed row remains — nothing on/after today');
      expect(container.read(todayWorkoutProvider), isNull,
          reason: 'execute() invalidated the workout providers on success');

      // Nothing left to sweep AND nothing to write → the honest refusal.
      // Under a NEW intent id (round 4 F1): execute() writes
      // `intent_<id>_dispatched_at` to coachBox after every success
      // (tool_dispatcher.dart:215-219) and short-circuits a re-dispatch of the
      // SAME id to success before the handler runs (:103-110) — so re-using
      // intentId here would assert against the idempotency marker, not the
      // refusal. A new id is also what the real flow produces: the model
      // emits a fresh intent when the user re-asks. Re-cached first, exactly
      // as a re-opened preview does (the success above cleared the cache).
      const retryId = 'intent_oi189_c2b';
      RegeneratePlanPlanner.instance.cache(retryId, result.plan,
          result.rawSchedules, result.phase, result.regenStartWeek);
      final again = await ToolDispatcher.instance.execute(
          ref, intentFor(retryId, 'regenerate_plan_block'));
      expect(again.success, isFalse);
      expect(again.errorMessage, contains('Nothing left to regenerate'));
    });

    test('switch_goal on an expired phase with orphans: goal changes, orphans '
        'swept, success with count 0', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      await seedWindow(today.subtract(const Duration(days: 35)), endOffset: 34);
      // patchProfile merges into this map; its _fireSync short-circuits when
      // SupabaseService.currentUser is null (uninitialised, this harness).
      await HiveService.instance.userBox.put('profile', {
        'primary_goal': 'general_fitness',
        'days_per_week': 4,
        'fitness_experience': 'intermediate',
      });
      for (var offset = 0; offset <= 3; offset++) {
        await seedRow(today.add(Duration(days: offset)));
      }
      final result = await RegeneratePlanPlanner.instance.plan(
        weeks: 4, goal: 'build_muscle', equipment: 'full_gym', daysPerWeek: 4,
      );
      expect(result.rawSchedules, isEmpty);
      const intentId = 'intent_oi189_c3';
      RegeneratePlanPlanner.instance.cache(intentId, result.plan,
          result.rawSchedules, result.phase, result.regenStartWeek);
      final res = await ToolDispatcher.instance.execute(
          makeContainer().read(_refProvider),
          intentFor(intentId, 'switch_goal', const {'new_goal': 'build_muscle'}));
      expect(res.success, isTrue);
      final data = res.data as Map?;
      expect(data, isNotNull);
      expect(data!['count'], 0);
      expect(data['cleared'], 4);
      final profile = HiveService.instance.userBox.get('profile') as Map;
      expect(profile['primary_goal'], 'build_muscle');
      for (var offset = 0; offset <= 3; offset++) {
        expect(scheduleRow(today.add(Duration(days: offset))), isNull);
      }
      expect(svc.isPhaseExpired(), isTrue);
    });
  });
```

If `todayWorkoutProvider` cannot resolve in this harness even with the `authUserIdTokenProvider` override, the two provider assertions are DROPPED and the record says so — do NOT substitute `currentPlanProvider`: its notifier's build calls `_autoGeneratePlan` (`train_provider.dart:713,742` → writer A) and would generate a plan inside the test (round 3 F6). The `execute()` success tail's invalidation is then covered only by its pre-existing behaviour, which this unit does not change.

- [ ] **Step 2: Run** — compile error on the new fields (expected red).

- [ ] **Step 3: Extend `RegeneratePlanResult`** (`:61-62`, `:74-81`):

```dart
  /// Weeks this block actually covers AFTER the phase-window bound
  /// (0..requestedWeeks). 0 means the requested start is already past the
  /// stored plan_end — nothing to lay out. OI-189.
  final int totalWeeks;

  /// Weeks the user asked for (1-12) — kept so the preview can say honestly
  /// when the block was shortened to fit the phase. OI-189.
  final int requestedWeeks;

  /// `YYYY-MM-DD` of the stored plan_end_date the block was bounded to, or
  /// null when no window is stored (plan-less user: block is unbounded).
  final String? phaseEndsOn;

  /// Non-completed rows dated after plan_end that the COMMIT will remove
  /// (dry-run of WorkoutScheduleReadService.sweepNonCompletedRowsPastPlanEnd).
  /// Preview-only number; plan() itself never deletes. OI-189.
  final int clearsPastPhaseEnd;

  /// Effective goal used for generation (resolved from arg or profile).
  final String resolvedGoal;

  /// Effective equipment tier used for generation.
  final String resolvedEquipment;

  /// Effective training frequency used for generation.
  final int resolvedDaysPerWeek;

  const RegeneratePlanResult({
    required this.firstWeek,
    required this.additionalDaysCount,
    required this.totalWeeks,
    required this.requestedWeeks,
    required this.phaseEndsOn,
    required this.clearsPastPhaseEnd,
    required this.resolvedGoal,
    required this.resolvedEquipment,
    required this.resolvedDaysPerWeek,
  });
```

- [ ] **Step 4: Window read, bound, report**

After the `regenStartWeek` statement — it spans `:224-226` and ends with `: 1;` at `:226` — insert:

```dart
    // OI-189: the stored phase window is authoritative for EVERY plan() call,
    // explicit startDate included — the same literal-date bound
    // generateAndScheduleFromDate applies at workout_schedule_read_service
    // .dart:489. A null window (plan-less user) keeps the old unbounded block.
    // Date-only comparison on local midnights on BOTH sides (`start` is a
    // local midnight from _today() or a date-only parse, but normalise anyway
    // so a future caller cannot hand in a timestamp), never a week-bucket one
    // (diagnose d7f3b2 sub-defect 1).
    final readSvc = WorkoutScheduleReadService.instance;
    final startDay = DateTime(start.year, start.month, start.day);
    final rawPlanEnd = readSvc.getPlanEndDate();
    final planEndDay = rawPlanEnd == null
        ? null
        : DateTime(rawPlanEnd.year, rawPlanEnd.month, rawPlanEnd.day);
    final boundedWeeks = planEndDay == null
        ? n
        : (startDay.isAfter(planEndDay)
            ? 0
            : ((planEndDay.difference(startDay).inDays ~/ 7) + 1).clamp(1, n));
    // Preview number only — the commit sites run the real sweep. `.workouts`
    // is the user-facing count (rest rows and shadows go too, uncounted).
    final clearsPastPhaseEnd =
        (await readSvc.sweepNonCompletedRowsPastPlanEnd(dryRun: true)).workouts;
```

In the day loop after `final d = weekStart.add(Duration(days: dayOfWeek));` (`:260`):

```dart
        // OI-189: never lay out a day past the stored plan_end. Normalised on
        // both sides (F14). Trailing-only by construction, so skipping cannot
        // desynchronise workoutDayIndex for an earlier day.
        if (planEndDay != null &&
            DateTime(d.year, d.month, d.day).isAfter(planEndDay)) {
          continue;
        }
```

Result (`:362-368`):

```dart
    final result = RegeneratePlanResult(
      firstWeek: firstWeekDisplay,
      additionalDaysCount: additionalWorkoutDayCount,
      totalWeeks: boundedWeeks,
      requestedWeeks: n,
      phaseEndsOn: planEndDay == null ? null : readSvc.dateKey(planEndDay),
      clearsPastPhaseEnd: clearsPastPhaseEnd,
      resolvedGoal: resolvedGoal,
      resolvedEquipment: resolvedEquipment,
      resolvedDaysPerWeek: resolvedDays,
    );
```

- [ ] **Step 5: Run** — tests C1-C4 green; C5-C6 red on the dispatcher assertions (Task 4).
- [ ] **Step 6: Stage** the planner + test file.

---

### Task 4: Dispatcher — sweep at both commit sites, push on every post-sweep exit, success when the sweep did the work

**Files:**
- Modify: `tool_dispatcher.dart` `_executeRegeneratePlanBlock` (after `:848`; after the splice's brace `:928`), `_executeSwitchGoal` (after the `Profile not found` check `:1041-1043`; after its splice's brace `:1121`; its two success returns at `:1126-1131` and `:1140-1145`). `execute()` (`:162`) is NOT touched.
- Test: same file — the source-pin group (Step 4).

- [ ] **Step 1: `_executeRegeneratePlanBlock`** — directly after the `rawSchedules == null` guard (`:842-848`):

```dart
    // OI-189: sweep non-completed rows past plan_end BEFORE anything else —
    // including the empty-set branch below — so an expired-phase user whose
    // orphan rows keep isPhaseExpired() false gets them cleared even when
    // there is nothing to write (OI-175 P1-A shape). Idempotent. No-op
    // without a stored window. `removed` = every key deleted; `workouts` =
    // the number the preview showed as clearsPastPhaseEnd.
    final swept = await WorkoutScheduleReadService.instance
        .sweepNonCompletedRowsPastPlanEnd();

    // OI-189: an EMPTY cached set means plan() had nothing to lay out — the
    // requested start is past plan_end, or every remaining day is completed.
    // Before this the loop ran zero times and the tool reported success with
    // count 0. The sweep above may have changed Hive, so the window push runs
    // HERE too (_restoreWorkoutPlan would otherwise mirror the swept rows back
    // from cloud on the next launch). Then:
    //   swept.removed > 0  → SUCCESS with count 0 + cleared N. The sweep WAS
    //                the work the preview promised, and execute() runs its
    //                invalidate/sync/marker tail only on success — Home's
    //                expired-card gate reads the non-autoDispose
    //                todayWorkoutProvider, so a failure here would leave the
    //                pre-sweep row on screen (round 3 F2). Keyed on `removed`,
    //                not `workouts`: a rest-only sweep still changed Hive and
    //                the calendar strip must re-read (round 4 F4).
    //   swept.removed == 0 → failure, nothing changed. The cache is
    //                deliberately NOT cleared on this branch (reject() never
    //                clears either): the intent stays actionable and Retry
    //                reproduces this message instead of "Open the diff
    //                preview first".
    if (rawSchedules.isEmpty) {
      try {
        await SyncService.instance.pushWorkoutPlanForSyncDomain();
      } catch (e, st) {
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'regenerate_plan_block_refusal_plan_window_push'));
      }
      if (swept.removed > 0) {
        RegeneratePlanPlanner.instance.clearCache(intent.id);
        return ToolExecutionResult.success(data: {
          'schedules': const <Map<String, dynamic>>[],
          'count': 0,
          'cleared': swept.workouts,
        });
      }
      return const ToolExecutionResult.failure(
        'Nothing left to regenerate in this phase.',
      );
    }
```

After the `current_plan` splice block's closing `}` (`:928`, before `RegeneratePlanPlanner.instance.clearCache(intent.id);`) the shared durability block with `reason: 'regenerate_plan_block_plan_window_push'` — it precedes every end-of-method return. And add `'cleared': swept.workouts,` to BOTH success `data` maps at the end of the method (`:933-936` and `:951-955`) so the field is present on every success.

⚠ Exception residual, documented not fixed (round 3 F4): a `box.put` / `upsertScheduled` throw AFTER the sweep escapes to `execute()`'s catch (`:227`) — no push, no invalidation. That needs Hive itself to fail; the next successful launch's `_restoreWorkoutPlan` mirrors the cloud copy back, which is the pre-existing behaviour for any half-applied tool. Stated in the diagnose-doc `impact_analysis`.

⚠ Executed-card copy residual (round 4 F7): `tool_confirm_card.dart:409-410` `_executedMessage` says "Plan regenerated" for a sweep-only success — it keys on the intent TYPE and never sees `data`; carrying the result to the card needs a new `ToolIntent` field. Same class as the EF-authored `previewSummary` (round 2 F12): the coach card's copy for the bounded-regen case is authored outside this diff. Recorded on OI-190 with F12, where the card copy is decided once.

- [ ] **Step 2: `_executeSwitchGoal`** — directly after the `Profile not found` guard (`:1041-1043`), BEFORE `patchProfile`:

```dart
    // OI-189: same sweep as _executeRegeneratePlanBlock, placed after the
    // last early return and before the profile write, so a goal change on an
    // expired phase never leaves old-goal orphan rows behind. No refusal here:
    // the goal change is the primary effect and zero rows is a legitimate
    // outcome the preview already explained. A patchProfile throw after this
    // point escapes to execute()'s catch without a push (round 3 F4) — same
    // Hive-failure class as above.
    final swept = await WorkoutScheduleReadService.instance
        .sweepNonCompletedRowsPastPlanEnd();
```

After its splice's closing `}` (`:1121`, before `clearCache`) the shared block with `reason: 'switch_goal_plan_window_push'`, and `'cleared': swept.workouts,` in both of its success `data` maps (`:1126-1131`, `:1140-1145`).

- [ ] **Step 3: Run the file — 11 PASS.** Then run `test/contracts/oi166_unit2_regen_content_cycling_behavioral_test.dart` (its "all rows already-completed race" test has a non-empty cache and no stored `plan_end` → the empty branch does not fire, sweep is a no-op → still green).

- [ ] **Step 4: Source pins — presence AND order (round 3 F3), one group at the end of the test file**

Add `import 'dart:io';` if the harness copy does not already have it. Every pin says why it is a pin (the OI-171 precedent's rationale, `deload_eval_behavioral_test.dart:722-763`): `_syncWorkoutPlan` needs a live Supabase client, so the push is unobservable offline; what CAN be pinned is position, which is the defect class itself (a push above the write it is meant to carry is a no-op).

```dart
  // ── OI-189 — the plan_json pushes (five sites, six blocks) exist, sit AFTER
  // the writes they carry, and writer A pushes ONLY on a phase advance ─────
  //
  // Source pins, not behavioural assertions: SyncService.instance is a live
  // singleton whose _syncWorkoutPlan needs a Supabase client, so no offline
  // test can observe the push (OI-171 precedent, deload_eval_behavioral_test
  // .dart:722-763). Position IS the defect class — a push placed above the
  // rows/blob it must carry snapshots the pre-write state — and the
  // pushPlanWindow wiring is a contract about WHICH call sites push, which is
  // a census of source, not a runtime state.
  group('OI-189 — plan_json push placement + pushPlanWindow wiring', () {
    final readSrc = File('lib/core/services/workout_schedule_read_service.dart')
        .readAsStringSync();
    final aStart = readSrc.indexOf('Future<Phase> generateAndSchedule({');
    final bStart = readSrc.indexOf('Future<Phase> generateAndScheduleFromDate({');
    final autoStart = readSrc.indexOf('autoGenerateNextPhaseIfNeeded({');
    final aBody = readSrc.substring(aStart, bStart);
    final bBody = readSrc.substring(bStart, autoStart);
    const push = 'pushWorkoutPlanForSyncDomain()';
    const rowWrite = 'source: WriteSource.planGenerator';

    test('writer A: push exists, is gated on pushPlanWindow, and sits after '
        'the last row write', () {
      expect(aBody.contains('bool pushPlanWindow = false'), isTrue);
      expect(push.allMatches(aBody).length, 1);
      final gate = aBody.indexOf('if (pushPlanWindow)');
      final pushAt = aBody.indexOf(push);
      expect(gate, isNonNegative);
      expect(pushAt, greaterThan(gate),
          reason: 'the push must be INSIDE the pushPlanWindow gate');
      expect(pushAt, greaterThan(aBody.lastIndexOf(rowWrite)),
          reason: 'a push above the rows snapshots the previous phase');
    });

    test('writer B: sweep sits after the delete loop and before the window '
        'write; push sits after the last row write', () {
      final sweep = bBody.indexOf('await sweepNonCompletedRowsPastPlanEnd()');
      final windowWrite = bBody.indexOf('MigratedKey.write(_planEndKey');
      final pushAt = bBody.indexOf(push);
      expect(sweep, isNonNegative);
      expect(push.allMatches(bBody).length, 1);
      expect(sweep, lessThan(windowWrite),
          reason: 'the sweep reads the STORED window, so it must run before a '
              'first generation writes a new one');
      expect(pushAt, greaterThan(bBody.lastIndexOf(rowWrite)));
    });

    test('pushPlanWindow: true at exactly the two phase-advance sites', () {
      final autoBody = readSrc.substring(autoStart);
      expect('pushPlanWindow: true'.allMatches(autoBody).length, 1,
          reason: 'autoGenerateNextPhaseIfNeeded is a phase advance');
      final pro = File('lib/shared/services/pro_phase_advance.dart')
          .readAsStringSync();
      expect('pushPlanWindow: true'.allMatches(pro).length, 1,
          reason: 'the PRO advance is the other phase advance');
    });

    test('pushPlanWindow is NOT reachable from the facade or the boot/repair '
        'callers of writer A', () {
      for (final path in [
        'lib/core/services/workout_schedule_service.dart',
        'lib/core/services/auth_session_bootstrapper.dart',
        'lib/features/train/providers/train_provider.dart',
        'lib/features/onboarding/providers/onboarding_provider.dart',
        'lib/features/dev/simulation_service.dart',
      ]) {
        expect(File(path).readAsStringSync().contains('pushPlanWindow'), isFalse,
            reason: '$path: a push from a fresh-Hive generation REPLACES the '
                'cloud plan_json before the restore reads it (round 3 F1)');
      }
    });

    final dispSrc = File('lib/features/ai_coach/services/tool_dispatcher.dart')
        .readAsStringSync();
    final regenStart =
        dispSrc.indexOf('Future<ToolExecutionResult> _executeRegeneratePlanBlock(');
    final pauseStart =
        dispSrc.indexOf('Future<ToolExecutionResult> _executePausePlan(');
    final switchStart =
        dispSrc.indexOf('Future<ToolExecutionResult> _executeSwitchGoal(');
    final templateStart = dispSrc
        .indexOf('Future<ToolExecutionResult> _executeCreateCustomTemplate(');
    final regenBody = dispSrc.substring(regenStart, pauseStart);
    final switchBody = dispSrc.substring(switchStart, templateStart);
    const splice = "box.put('current_plan', splicedBlob)";
    const wSplice = "wbox.put('current_plan', splicedBlob)";
    const clear = 'RegeneratePlanPlanner.instance.clearCache(intent.id)';

    test('regen block: two pushes — one inside the empty branch after the '
        'sweep, one after the splice and before clearCache', () {
      expect(push.allMatches(regenBody).length, 2);
      final sweep = regenBody.indexOf('.sweepNonCompletedRowsPastPlanEnd()');
      final emptyBranch = regenBody.indexOf('if (rawSchedules.isEmpty)');
      final firstPush = regenBody.indexOf(push);
      final lastPush = regenBody.lastIndexOf(push);
      expect(sweep, isNonNegative,
          reason: 'a missing sweep would make lessThan(emptyBranch) vacuous');
      expect(sweep, lessThan(emptyBranch),
          reason: 'the sweep must run even when there is nothing to write');
      expect(firstPush, greaterThan(emptyBranch));
      expect(firstPush, lessThan(regenBody.indexOf('Nothing left to regenerate')));
      expect(lastPush, greaterThan(regenBody.indexOf(splice)),
          reason: 'a push above the splice snapshots the pre-splice blob');
      expect(lastPush, lessThan(regenBody.lastIndexOf(clear)));
    });

    test('switch_goal: sweep before patchProfile; push after the splice and '
        'before clearCache', () {
      expect(push.allMatches(switchBody).length, 1);
      final sweep = switchBody.indexOf('.sweepNonCompletedRowsPastPlanEnd()');
      expect(sweep, isNonNegative);
      expect(sweep, greaterThan(switchBody.indexOf("'Profile not found.'")),
          reason: 'after the last early return');
      expect(sweep, lessThan(switchBody.indexOf('patchProfile(')));
      final pushAt = switchBody.indexOf(push);
      expect(pushAt, greaterThan(switchBody.indexOf(wSplice)));
      expect(pushAt, lessThan(switchBody.indexOf(clear)));
    });

    test('redoWeek4 (the live free-tier window-mover) pushes AFTER moving '
        'plan_end — the holdWeek shape', () {
      final writeSrc =
          File('lib/core/services/workout_schedule_write_service.dart')
              .readAsStringSync();
      final redoStart = writeSrc.indexOf('Future<void> redoWeek4()');
      final holdStart = writeSrc.indexOf('Future<void> holdWeek()');
      final redoBody = writeSrc.substring(redoStart, holdStart);
      expect(push.allMatches(redoBody).length, 1,
          reason: 'round 4 F2: a reinstall in the ≤24h gap takes the stale '
              'cloud window and the next regen sweeps the redo week');
      final endWrite = redoBody.indexOf('MigratedKey.write(_planEndKey');
      expect(endWrite, isNonNegative);
      expect(redoBody.indexOf(push), greaterThan(endWrite),
          reason: 'a push above the window write carries the OLD plan_end');
    });

    test('pushWorkoutPlanForSyncDomain is guarded by pausedForSimulation '
        'BEFORE it opens a session', () {
      final syncSrc = File('lib/core/services/sync/sync_workout.dart')
          .readAsStringSync();
      final start =
          syncSrc.indexOf('Future<void> pushWorkoutPlanForSyncDomain() async {');
      expect(start, isNonNegative);
      final body = syncSrc.substring(start);
      final guard = body.indexOf('if (SyncService.pausedForSimulation) return;');
      final session = body.indexOf('_ensureSessionOpen()');
      expect(guard, isNonNegative,
          reason: 'round 4 F3: the year-sim drives ~30 advances inside its '
              'paused window and each now reaches this push');
      expect(guard, lessThan(session), reason: 'guard FIRST, like :31');
    });
  });
```

- [ ] **Step 5: Run the file — 19 PASS** (11 behavioural + 8 pins).
- [ ] **Step 6: Stage** `git add lib/features/ai_coach/services/tool_dispatcher.dart test/contracts/oi189_plan_end_bound_behavioral_test.dart`

---

### Task 5: Diff previews — honest header, one note (three forms)

**Files:** `regenerate_plan_diff.dart:95-147` + a helper by `_dayLabel` (`:225`); `switch_goal_diff.dart:153-183` + helper by `:264`.

No widget test (pure conditionals on four fields Task 3 pins; the widget's `plan()` call needs the Hive harness inside `testWidgets` — §4.9 traps). Said in the record; a reviewer may demand one.

- [ ] **Step 1: helper (both widgets, `_plan!` in the switch-goal one)**

```dart
  /// OI-189: the phase-window note — null when the block fits the phase AND
  /// nothing past plan_end will be cleared (nothing to say).
  String? _phaseNote(RegeneratePlanResult plan) {
    final end = plan.phaseEndsOn;
    if (end == null) return null;
    final clears = plan.clearsPastPhaseEnd;
    final fits = plan.totalWeeks >= plan.requestedWeeks;
    if (fits && clears == 0) return null;
    final clearsLine = clears == 0
        ? ''
        : ' $clears workout${clears == 1 ? '' : 's'} scheduled after that '
            'date will be cleared.';
    if (plan.totalWeeks == 0) {
      return 'This phase ended on ${_dayLabel(end)} — nothing left to '
          'regenerate.$clearsLine';
    }
    if (fits) {
      return 'This phase ends on ${_dayLabel(end)}.$clearsLine';
    }
    return 'Stops at this phase\'s end on ${_dayLabel(end)}.$clearsLine';
  }
```

- [ ] **Step 2: `regenerate_plan_diff.dart` build** — when `plan.totalWeeks == 0` render ONLY the note; otherwise the existing header card (`'${plan.totalWeeks}-week plan'` stays — bounded count), eyebrow, day cards, footer, then the note if non-null:

```dart
        if (plan.totalWeeks == 0) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(
              _phaseNote(plan)!,
              style: AppTypography.bodySm.copyWith(
                  color: AppColors.textSecondary, fontStyle: FontStyle.italic),
            ),
          ),
        ] else ...[
          // existing header Container, eyebrow Padding, day cards, footer —
          // unchanged, moved inside this branch
          if (_phaseNote(plan) != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                _phaseNote(plan)!,
                style: AppTypography.bodySm.copyWith(
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ],
```

(`totalWeeks == 0` implies `planEndDay != null` and `0 < requestedWeeks`, so `_phaseNote` is non-null there — round 2 Q7.)

- [ ] **Step 3: `switch_goal_diff.dart`** — replace the sentence at `:155-156`:

```dart
              Text(
                _plan!.totalWeeks == 0
                    ? 'Profile will be updated. ${_phaseNote(_plan!)!}'
                    : 'Profile will be updated and the next ${_plan!.totalWeeks} '
                        'week${_plan!.totalWeeks == 1 ? '' : 's'} regenerated.',
                style: AppTypography.body.copyWith(fontSize: 11, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
              ),
              if (_plan!.totalWeeks > 0 && _phaseNote(_plan!) != null) ...[
                const SizedBox(height: 4),
                Text(
                  _phaseNote(_plan!)!,
                  style: AppTypography.body.copyWith(fontSize: 11, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                ),
              ],
```

and wrap the `NEW WEEK 1` eyebrow, day cards and footer (`:163-183`) in `if (_plan!.totalWeeks > 0) ...[ … ]`.

- [ ] **Step 4: Analyze** — `flutter analyze lib/ test/`, warnings count 0.
- [ ] **Step 5: Stage** both widgets.

---

### Task 6: Mutations, census, gate loop, docs, board, record, B-pass — then hand back for "commit"

- [ ] **Step 0: Mutations (nineteen legs)** — each confirmed applied (`grep -c`), run against `test/contracts/oi189_plan_end_bound_behavioral_test.dart`, first-failing assertion RECORDED AS REPORTED, restored, re-run green.

| # | Mutation | Compiles | Expected red (which tests) |
|---|---|---|---|
| M1 | helper: `if (status == 'completed') continue;` → `'completed_'` | yes | helper 1 (first fails at `dry.workouts == 5`, gets 6), B1, C5 (first fails at `clearsPastPhaseEnd 7`) |
| M2 | helper: `if (startStr == null \|\| endStr == null) return nothing;` → `if (endStr == null) return nothing;` (F5 — the `&&` form does NOT compile; leaves `startStr` unused → a WARNING, still compiles — mutation run only) | yes | helper 2 (the plan_end-only `.removed == 0`) |
| M3 | B: delete `await sweepNonCompletedRowsPastPlanEnd();` | yes | B1 "+28", B2 "+29"; pin "writer B" |
| M4 | planner: delete the `continue` block | yes | C1 per-row, C3, C5, C6 `rawSchedules isEmpty` |
| M5 | planner: `~/ 7) + 1)` → `~/ 7) + 0)` | yes | C1 `totalWeeks 2` |
| M6 | dispatcher: `if (swept.removed > 0) {` → `if (swept.removed >= 0) {` (the empty branch always succeeds) | yes | C5 `again.success isFalse` (the fresh-id second dispatch — under the SAME id this leg could never redden, round 4 F1) |
| M7 | dispatcher: delete the sweep call in `_executeSwitchGoal` (`swept` → `const (workouts: 0, removed: 0)`) | yes | C6 `isNull`; pin "switch_goal" |
| M8 | dispatcher: delete the sweep call in `_executeRegeneratePlanBlock` (`swept` → `const (workouts: 0, removed: 0)`) | yes | C5 `res.success isTrue` (falls to the failure branch), then "commit sweeps planned orphans"; pin "regen block" |
| M9 | helper: `if (!dryRun) {` → `if (true) {` | yes | helper 1 "dry run must not delete", C2 and C5 "plan() is a preview" |
| M10 | helper: `if (type != 'rest' && type != 'off') workoutRows++;` → `workoutRows++;` (count everything) | yes | helper 1 `dry.workouts == 5` (gets 6: the rest row is counted); `dry.removed` stays 7 — which is the point of pinning both |
| M11 | A: delete `pushPlanWindow: true,` at `:617` | yes | pin "exactly the two phase-advance sites" |
| M12 | facade: add `bool pushPlanWindow = false,` + forward it (`workout_schedule_service.dart:78-104`) | yes | pin "NOT reachable from the facade" |
| M13 | A: move the `if (pushPlanWindow) { … }` block to directly after `:227` (`await workoutBox.put(_planKey, plan.toMap());`, before the rows) | yes | pin "writer A" (`greaterThan(lastIndexOf(rowWrite))`) |
| M14 | B: move its push block to directly after the sweep call (before the window write and the rows) | yes | pin "writer B" (`pushAt > lastIndexOf(rowWrite)`) |
| M15 | regen block: delete the push inside the empty branch | yes | pin "regen block" (`allMatches … 2`) |
| M16 | regen block: move the post-splice push to directly after the sweep (above the splice) | yes | pin "regen block" (`lastPush > indexOf(splice)`) |
| M17 | switch_goal: move the push to directly after the sweep (above `patchProfile`) | yes | pin "switch_goal" (`pushAt > indexOf(wSplice)`) |
| M18 | `redoWeek4`: move its push block to directly BEFORE `final newEnd = …` (above the window write) | yes | pin "redoWeek4" (`indexOf(push) > endWrite`) |
| M19 | `pushWorkoutPlanForSyncDomain`: delete the `if (SyncService.pausedForSimulation) return;` line | yes | pin "guarded by pausedForSimulation" (`guard isNonNegative` — or, if a later method carries the same line, `guard lessThan(session)`) |

Every mutation compiles and is semantically wrong (rule 21). M12 is the only one that ADDS code; confirm it applied by `grep -c pushPlanWindow lib/core/services/workout_schedule_service.dart` → non-zero before the run.

- [ ] **Step 1: Test census (F4 + F13)**

```bash
cd "<worktree>" && for b in regenerate_plan_planner tool_dispatcher regenerate_plan_diff switch_goal_diff workout_schedule_read_service workout_schedule_service workout_schedule_write_service pro_phase_advance sync_workout; do grep -rl "$b" test/; done | sort -u > "<scratchpad>/census.txt"; wc -l "<scratchpad>/census.txt"; flutter test $(tr '\n' ' ' < "<scratchpad>/census.txt") test/contracts/oi189_plan_end_bound_behavioral_test.dart
```
All green. A pre-existing test asserting rows past `plan_end` survive a regen was asserting the defect — REPOINT (strengthen), never delete/loosen.

- [ ] **Step 2:** `git status --porcelain | grep -E '^(MM|AM|MD|AD) '` → nothing; `flutter analyze lib/ test/` → 0 warnings.

- [ ] **Step 3: Diagnose-doc** — copy the frontmatter skeleton of `docs/diagnoses/2026-09-11-oi166-unit2-regen-content-cycling-d7f3b2.md` (every key from `scripts/validate_diagnose_doc_lib.dart:8-16` + `blast_radius`), no `TBD`/`TODO`/`<...>`:
- `bug_id: b9e4d1`, `date: 2026-09-13`, `batch: oi189-plan-end-bound`, `status: fixed`, `blast_radius: platform` (corrected at staging time — see Global Constraints above), `related_bugs: [d7f3b2, 9c3e7a, c9e4b7]`, `sot_registry_entry: workout_schedule_read_path`.
- `recurrence:` sixth instance of the OI-166 schedule-row class — a writer bounded its ROWS by something other than the stored phase window (C: the request length; B's delete: the window only); the sibling-writer asymmetry round 1 caught (sweep on B, not C) is `feedback_mistake_guard_without_its_mirror` shape.
- `symptom:` the three sentences from the brainstorm (C unbounded; nothing sweeps; rows past plan_end keep the phase alive and get served — old goal after a goal change).
- `writers:` re-derive from the final diff: `regenerate_plan_planner.dart plan()` (start `:151-153`, bound in the day loop), `tool_dispatcher.dart _executeRegeneratePlanBlock` (sweep + empty-branch push + success-with-`cleared` / failure + post-splice push), `_executeSwitchGoal` (sweep + push), `workout_schedule_read_service.dart sweepNonCompletedRowsPastPlanEnd` (new), `generateAndScheduleFromDate` (delete loop `:362-377`, sweep call, write bound `:489+`, push), `generateAndSchedule` (`pushPlanWindow` opt-in push), `autoGenerateNextPhaseIfNeeded :617` and `pro_phase_advance.dart:582` (pass `pushPlanWindow: true`), `workout_schedule_write_service.dart redoWeek4` (push after the `plan_end` move `:214` — round 4 F2), `sync/sync_workout.dart pushWorkoutPlanForSyncDomain` (`pausedForSimulation` guard — round 4 F3). NOT writers of the push, stated because a reviewer will ask: `auth_session_bootstrapper.dart:653`, `train_provider.dart:669` (both its triggers, `:713` no-plan and `:742` lost-rows repair on an EXISTING account), `onboarding_provider.dart:554` (facade callers, default false — round 3 F1, round 4 F5).
- `readers:` `isPhaseExpiredFrom` / `isPhaseExpired`, `pro_phase_advance.dart:144`, `home_screen.dart:770-771` + `home_provider.dart:518-532` (`todayWorkoutProvider`, non-autoDispose), `train/screen.dart:169`, `deload_evaluator.dart:61`, both diff-preview widgets, `tool_confirm_card.dart:234-255` (failed-intent card with Retry) and `:307` (EF-authored summary), `plan_window_reanchor.dart:45-60`.
- `sync_methods:` `syncWorkoutData` (does NOT push plan_json), `pushSnapshot` (daily-snapshot EF, does NOT push plan_json), `pushWorkoutPlanForSyncDomain → _syncWorkoutPlan` (whole-blob REPLACE, now called by B, both C commit sites incl. the empty branch, `redoWeek4`, `holdWeek` (pre-existing) and A ONLY at the two phase-advance sites; silent no-op when `current_plan` is null; returns FIRST on `pausedForSimulation`), `_syncScheduledWorkouts` (upsert-only; NEVER deletes cloud rows — OI-174 residual).
- `restore_methods:` `_restoreWorkoutPlan` (`sync/sync_workout.dart:1131-1148`, runs on EVERY returning-user launch via `restoreLightweightAlways`, `sync_service.dart:1383`), `_restoreScheduledWorkouts` (`:1811-2040`, since `2020-01-01`), `PlanIntegrityReconciler.reconcile` (`plan_integrity_reconciler.dart:288-306`) — all three UNBOUNDED by plan_end; stated as the OI-174 residual, NOT "self-heals".
- `cloud_table: scheduled_workouts`, `cloud_columns: [scheduled_date, status, week_number, day_of_week]` (and `user_progress.plan_json`).
- `contract_test_path: test/contracts/oi189_plan_end_bound_behavioral_test.dart`; `regression_test_planned:` the eleven behavioural tests by name, the eight source pins WITH the sentence that they are presence/order pins because the push is unobservable offline (round 3 F3), plus the nineteen-leg mutation table with the ACTUAL first-failing assertions.
- `ist_handling:` `workout_schedule_read_service.dart:357 istMidnight(fromDate)`; `regenerate_plan_planner.dart:442 _today()` (`DateTime.now()` local — pre-existing; on a device EAST of IST `istDateStr(localMidnight)` lags one day, invisible on IST dev / UTC CI — noted, not fixed here); `:447 _fmt = istDateStr` (identical to `dateKey`); `ist_date.dart:62 nowWall` (read by `isPhaseExpired`).
- `touched_layers_checked:` tier 1 `fixed_in_this_batch`; tier 2 `fixed_in_this_batch`; tier 4 `verified` — paste BOTH census queries (plan_json and `scheduled_workouts`, 10 users, 0 rows past `plan_end` each); tier 12 `verified` (dispatcher-driven tests); tiers 3/5/6/7/8/9/10/11 `not_applicable` with one clause each.
- `impact_analysis:` free + PRO; zero prod users affected today; forward-only protection; D2 (user-placed rows past plan_end are swept — the three creators named); the OI-174 residual (restore can re-materialise from the never-pruned cloud table until the next regen); F2 (the sweep makes `plan_end_date` destructive; `PlanWindowReanchor` makes it revertible from a stale cloud copy; the two phase-advance sites' immediate push closes the online case; an OFFLINE advance leaves the revert window open until the next successful push — OI-174 residual); round-3 F1 (why the push is opt-in: the reinstall path generates on a fresh Hive BEFORE the restore, and a push there would replace the cloud plan_json); round-3 F4 (a Hive throw after the sweep escapes to `execute()`'s catch with no push — pre-existing half-applied-tool behaviour, healed by the next launch's restore); round-4 F6 (the awaited push has no `.timeout()`; the coach card's spinner waits on it — the exposure `holdWeek` already accepted); round-4 F7 (the executed card says "Plan regenerated" for a sweep-only success — card copy is decided once on OI-190 with F12); F12 (confirm-card summary line is EF-authored); the F11 `holdWeek`/`redoWeek4` write-then-move window (7 awaits between the rows and the `plan_end` move; a sweep interleaved there would delete the just-written week; unreachable from one user's UI — different screens, no shared trigger, `autoGenerateNextPhaseIfNeeded` calls A not B).
Run: `dart run scripts/validate_diagnose_doc.dart docs/diagnoses/2026-09-12-regen-writers-stop-at-plan-end-b9e4d1.md` → `OK`.

- [ ] **Step 4: Board** — OI-189: `- **Status**: CLOSED (2026-09-13, \`oi189-plan-end-bound\`) — diagnose \`b9e4d1\`` + closing bullet (D1/D2, both censuses, test path). OI-174: stays `OPEN`; REWRITE the body to the narrowed scope: (i) creation past `plan_end` is now impossible from A/B/C; any regen sweeps locally + pushes `plan_json`; (ii) RESIDUALS — cloud `scheduled_workouts` never pruned (`_syncScheduledWorkouts` upsert-only) + the three restore writers unbounded (rows return from that table on a restore until the next regen); an OFFLINE phase advance can still be reverted by `PlanWindowReanchor` on the next launch and the sweep would then delete the live phase's rows — mitigated by the two advance sites' immediate push (`pushPlanWindow: true`), not eliminated; (iii) its "completed orphan" question is ANSWERED (kept); (iv) fix design: a cloud delete issued by the sweep (check the RLS delete policy on `scheduled_workouts` first) + a freshness guard on the reanchor; platform tier; a restore-side filter was REJECTED (hides the stale rows, does not remove them). Update `Blocked on` / `Verified` lines (`build_oi_index.dart` fails closed without them). OI-190: "OI-189 is CLOSED; the horizon rule is `plan_end` for every writer — the shared builder must carry the same bound and the same sweep"; add the F12 input (EF `previewSummary` "Regenerate next N weeks" contradicts a bounded diff; `regeneratePlanBlock.ts:54`; a client-side substitution would not rebuild when the planner cache fills) and the round-4 F7 input (`tool_confirm_card.dart:409-410` `_executedMessage` says "Plan regenerated" for a sweep-only success `count: 0, cleared: N` — it keys on intent TYPE; carrying `data` to the card needs a `ToolIntent` field) — the coach card's copy for the bounded-regen case is decided ONCE there. OI-166: "what is left … lives in OI-175, OI-189 and OI-190" → OI-175 and OI-190. Run `dart run scripts/build_oi_index.dart` and `dart run scripts/check_oi_numbering_unique.dart`.

- [ ] **Step 5: Nested CLAUDE.md** — `lib/features/train/CLAUDE.md:68`, after "… anchored to the phase's real `plan_start`)." add: "**And since OI-189 (`b9e4d1`, 2026-09-13) every phase-layout writer is bounded by the stored `plan_end`; both regen paths sweep non-completed rows past it (`sweepNonCompletedRowsPastPlanEnd`); and every writer that MOVES the window on an existing account pushes `plan_json` immediately — B, both coach commit sites, `holdWeek`, `redoWeek4`, and the two PHASE-ADVANCE calls of A (`pushPlanWindow: true` — never the reinstall/boot/repair callers, which would replace the cloud copy) — because `_restoreWorkoutPlan` mirrors the cloud window back on every launch and the sweep now trusts that window. Residuals on OI-174.**" `lib/features/ai_coach/CLAUDE.md:52-58` — append to the END of that bullet, after its last sentence "See ADR-0012." at `:58` (NOT after "plus the read tools)." — that phrase is mid-line at `:55` and the bullet continues; round 4 F8): " `switchGoal` / `regeneratePlanBlock` never write past the stored `plan_end` (OI-189, `b9e4d1`): `RegeneratePlanResult.totalWeeks` is the bounded count, `requestedWeeks` what was asked, `clearsPastPhaseEnd` what the commit will sweep; both commit sites sweep then push `plan_json`; an empty regen whose sweep removed rows returns SUCCESS with `count: 0, cleared: N` (so the invalidate tail runs), and is refused — cache kept, Retry repeats the message — only when the sweep removed nothing."

- [ ] **Step 6:** `dart run scripts/check_sot_registry_parity.dart` — refresh every `line_range` it names (expected: round-1 Q7 list — registry `:6746, :6862, :7673, :8005, :9247, :9644-9652` for the read service; `:8020, :2800` for the dispatcher). Stage `docs/sot_registry.yaml` only if it changed.
- [ ] **Step 7:** `sh scripts/pre-commit.sh` from the worktree — the full loop, not a subset; fix everything it names; stage what the index regens produce.
- [ ] **Step 8:** Plan-review record `docs/plan-reviews/oi189-plan-end-bound.md` with `---` frontmatter: `branch: oi189-plan-end-bound`, `blast_radius: platform` (corrected at staging time — see Global Constraints above), `review_rounds: <real count>`, `ground_truth_verified: true`, `verdict: converged`, `bpass: pending` until the founder's word, `bpass_review: docs/reviews/<hash>-review.md`. Body: each round's findings and how each closed (the Review log below is the source).
- [ ] **Step 9:** `/code-review` B-pass on the staged diff (account tier); triage every finding; append the Tuning-history entry (`check_skill_tuning_history.dart`); stage the review file + SKILL.md. Re-run Steps 2 and 7 after any fix.
- [ ] **Step 10:** Hand back: files staged, tests (11 + mutations with counts), analyze, gate loop, review findings and statuses. Ask the founder for the one word on the B-pass verdict and for "commit"; then `sh scripts/safe_commit.sh "$(cat <scratchpad>/commit_msg.txt)"` → `/update-docs` → `sh scripts/safe_merge.sh oi189-plan-end-bound` (primary) → `sh scripts/safe_push.sh`, each only on the founder's explicit word.

---

## Review protocol (§4.12)

Rounds 1-4 done (Review log). Round 3's P1 was a defect INTRODUCED by round 2's own correction (the unconditional push on writer A); round 4's P1 was a test that could not discriminate (same-id re-dispatch hits the idempotency marker) and its two P2s were completeness gaps of the class already being fixed (one more window-mover without a push; the sim loop reaching the push through the new flag). None changed the design: helper + bound + two sweeps + pushes at every window-mover. The unit is not splittable further: the sweeps are unsafe without the pushes (the restore mirrors swept rows back), and the bound without the sweep leaves OI-189's orphans in place. **Round 5 runs on THIS plan** with a charge limited to the round-4 deltas: (1) C5's fresh-id second dispatch — does anything else in `execute()` short-circuit it (the `_dispatched_at` marker is per id; is there any per-TYPE or per-payload guard); (2) the `redoWeek4` block — placement after `:214` inside the method, imports in scope, the two hermetic `redoWeek4()` tests unaffected; (3) the `pausedForSimulation` guard — is any CALLER relying on the push happening while paused (grep `pushWorkoutPlanForSyncDomain` callers + `pausedForSimulation = true` sites incl. tests); (4) the record return type across all four call sites (B ignores, planner `.workouts`, both dispatcher sites `.removed` / `.workouts`) and the M7/M8 substitution `const (workouts: 0, removed: 0)` compiles; (5) the two new pins' landmarks and M18/M19. Converged when a round returns only compile-slip-class items; a material finding of a NEW class ⇒ stop and split per `feedback_plan_review_twice`.

## Not in this unit (stated, owned, not deferred)

- **OI-174 residual (D1):** cloud `scheduled_workouts` never pruned; three restore writers unbounded; offline-advance revert window (F2). Owner: OI-174 (OPEN, narrowed, design on the entry).
- **EF tool copy** (`regeneratePlanBlock.ts:5-6,42,54` — schema text AND the confirm-card `previewSummary`, F12): catastrophic-tier deploy. Founder decision; recorded on OI-190.
- **Hold cap** / **`enable_hold_weeks` OFF**: OI-60.
- **`progress.phase_started_at` vs `plan_start_date`** (≤6 days apart): reported; not filed unless the founder says so.
- **`RegeneratePlanPlanner._today()` is `DateTime.now()`** not `istMidnight(nowWall())`: pre-existing; noted in the diagnose-doc.
- **OI-190**: unchanged; stricter inputs (bound + sweep + the F12 EF-copy question).

## Review log

**Round 1 — 2026-09-12, context-blind, `material-issues`, 11 findings (2 P1, 5 P2, 4 P3), all verified against the code before folding.** F1 P1 sweep only on B → shared helper + both commit sites. F2 P1 `pushSnapshot` ≠ `plan_json`; restore resurrects → push after sweep (B, C), second census, OI-174 narrowed (D1 = A). F3 P2 over-claim + silent deletion of user-placed rows → wording narrowed, D2 = sweep, `clearsPastPhaseEnd`. F4 P2 census vs hand list. F5 P2 explicit-startDate → (a), tested. F6 P2 Retry loop → no `clearCache`, tested. F7 P2 unobservable flip → test clock / real-now fixtures. F8 anchors. F9 "0-week plan" → note replaces header. F10 BOTH keys required. F11 hold/redo write-then-move window documented.

**Round 2 — 2026-09-13, context-blind on v2, `material-issues`, 14 findings (2 P1, 4 P2, 8 P3), all verified against the code before folding.**
- F1 P1: refusal returned BEFORE the push and before `execute()`'s invalidation tail (`:162`); `_restoreWorkoutPlan` runs EVERY launch, not only on reinstall. **Folded:** push inside the refusal branch; `execute()` invalidates workout providers on non-nutrition failures; C5 asserts `todayWorkoutProvider` before/after; wording corrected everywhere.
- F2 P1: writer A moves the window and pushes nothing; `PlanWindowReanchor` mirrors a stale cloud window back on the next launch (documented on the founder account, `c9e4b7`); the sweep would then delete the live phase's rows. **Folded:** A pushes `plan_json` immediately (Task 2 Step 4); offline residual recorded on OI-174; helper doc-comment names the hazard.
- F3 P2: `_phaseNote` silent when the block fits but rows past `plan_end` will be cleared. **Folded:** three-form note; C2 pins `clearsPastPhaseEnd 1` on a fitting block.
- F4 P2: "Your next phase is set up when this one ends" false for free users. **Folded:** sentence removed.
- F5 P2: M2 did not compile. **Folded:** `if (endStr == null) return 0;`.
- F6 P2: no mutation for the regen-block sweep or the dry-run guard. **Folded:** M8, M9.
- F7 P3: `recordNonFatal` has `reason:`, not `context:`. **Folded** everywhere.
- F8 P3: B push placement was after `return plan;`. **Folded:** between `:560` and `:562`; same shape for A (`:319`/`:321`).
- F9 P3: fabricated pointer to `coach_regen_phase_stamp` for switch-goal. **Folded:** removed; `currentUser == null` short-circuit stated.
- F10 P3: first-failing assertions mis-named. **Folded:** record as reported.
- F11 P3: push is a no-op when `current_plan` is null. **Folded:** stated in comments + diagnose-doc.
- F12 P3: confirm-card summary is EF-authored. **Folded:** recorded on OI-190 (a client-side substitution would not rebuild when the cache fills — the card's `build` runs before the diff widget's async `plan()`).
- F13 P3: census misses facade-only tests. **Folded:** `workout_schedule_service` added.
- F14 P3: planner bound compared an un-normalised `d`. **Folded.**

**Round 3 — 2026-09-13, context-blind on v3, `material-issues`, 6 findings (1 P1, 2 P2, 3 P3), all verified against the code before folding.**
- F1 P1: round 2's F2 fold (writer A pushes unconditionally) fires on the reinstall / new-device sign-in path: `auth_session_bootstrapper.dart:653` calls the facade's `generateAndSchedule` when `!hasPlan() && onboarding_completed` — and `:536` writes `onboarding_completed` from the cloud row FIRST, so on every reinstall a fresh Hive generates a plan from `_ensureLocalUser` (sign-in), BEFORE `restoring_screen.dart:110-114` starts `restoreFromCloudForUser`. `_syncWorkoutPlan` is a whole-blob REPLACE, so that push would overwrite the only cloud copy holding the real plan's exercises and hold rows, and the restore would then mirror the history-free plan back. `train_provider.dart:669` (`_autoGeneratePlan`) and `onboarding_provider.dart:554` are the same shape. **Folded:** `bool pushPlanWindow = false` on the READ service's `generateAndSchedule`; `true` at exactly `:617` (`autoGenerateNextPhaseIfNeeded`, whose `isPhaseExpired()` guard is false with no stored window) and `pro_phase_advance.dart:582` (reads the read service directly, `:515`); the facade does not forward it; pinned both ways (Task 4 Step 4) with mutation legs M11-M13.
- F2 P2: a regen whose sweep removed rows but had nothing to write returned FAILURE, so `execute()`'s success-only tail (invalidate / sync / marker) never ran — round 2's F1 fold patched that with a failure-path invalidation, which was the wrong layer. **Folded:** the empty branch returns SUCCESS with `count: 0, cleared: N` when `swept > 0` (cache cleared like every other success) and failure only when `swept == 0` (cache kept, Retry repeats); the `execute()` change is DROPPED; C5 asserts success + `cleared 7` + the provider flip via the ordinary success tail, then a re-cached second dispatch hits the failure; C6 asserts `cleared 4`; `'cleared'` present on every success return of both commit sites.
- F3 P2: the four push blocks had no test at all (the OI-171 class — a reviewer deleting the line would redden nothing). **Folded:** one source-pin group (six tests: presence AND order against landmarks — the last row write, the window write, the splice, `clearCache`, `patchProfile`; plus the `pushPlanWindow` census both ways), each stated as a pin because the push is unobservable offline; mutation legs M11-M17.
- F4 P3: a Hive throw after the sweep (`patchProfile` rethrow, `upsertScheduled`, the splice `put`) reaches `execute()`'s catch with no push. **Folded as documentation** (Task 4, diagnose-doc `impact_analysis`): pre-existing half-applied-tool class, healed by the next launch's restore.
- F5 P3: `clearsPastPhaseEnd` counted rest rows and `displaced_` shadows while the copy said "workouts". **Folded:** the helper still REMOVES all three kinds but RETURNS only rows whose `type` is neither `rest` nor `off` — the `_scheduledWorkoutDays` predicate (`:1500-1501`), i.e. exactly the set that keeps `isPhaseExpiredFrom` false; helper-1 literals 7 → 5; mutation M10.
- F6 P3 (slips): "after `:224`" → after the statement ending at `:226`; `start` normalised to `startDay` for the bound; the `currentPlanProvider` fallback STRUCK (its notifier's build calls `_autoGeneratePlan`, `train_provider.dart:713,742`); "two tests call writer A" → one (`repeat_content_scheduling_test.dart`); awaited-vs-unawaited push DECIDED (awaited, holdWeek precedent, `_syncWorkoutPlan` self-catching); `pausedForSimulation` does not guard the push — the hermetic proof is the null session, stated.
- Round 3 also confirmed: the four push placements reach every non-exception exit; every one of the eleven tests' literals follows from its fixture; compile-level symbols resolve; census = 56 files (now 66 with `pro_phase_advance` added).

**Round 4 — 2026-09-13, context-blind on v4, `material-issues`, 8 findings (1 P1, 2 P2, 5 P3), all verified against the code before folding.**
- F1 P1: C5's second dispatch re-used `intent_oi189_c2` — `execute()` writes `intent_<id>_dispatched_at` after every success (`tool_dispatcher.dart:215-219`) and short-circuits a same-id re-dispatch to `success()` before the handler runs (`:103-110`), so `expect(again.success, isFalse)` would redden on the CORRECT implementation and M6 could never discriminate. **Folded:** the refusal is dispatched under a fresh id (`intent_oi189_c2b`), re-cached first — which is also what the real flow produces.
- F2 P2: "every window-mover pushes" was contradicted by `redoWeek4` (`write_service.dart:214` moves `plan_end`, pushes nothing), the LIVE free-tier path (`runFreeTierRepeatWrite`, `keep_training_phase1_action.dart:30-36`, `enable_hold_weeks` OFF by default); a reinstall in the ≤24h gap takes the stale cloud window and the next regen's sweep deletes the redo week. **Folded:** the holdWeek durability block after `:214` (Task 2 Step 5), pin + M18.
- F3 P2: `pushWorkoutPlanForSyncDomain()` has no `pausedForSimulation` guard (every sibling entry does — `sync/sync_workout.dart:31`, `sync_service.dart:363,1055`), and the dev year-sim (`simulation_service.dart:550` → `autoGenerateNextPhaseIfNeeded` → `:617`) would now push `plan_json` ~30 times inside its paused loop. **Folded:** guard-FIRST line (Task 2 Step 6), pin + M19; hermetic proof restated (guard first, null session second).
- F4 P3: the success/failure split keyed on the WORKOUT count, so a rest-only / shadow-only sweep returned failure and skipped the invalidation tail. **Folded:** the helper returns `({int workouts, int removed})`; the dispatcher branches on `removed`, reports `workouts`; helper-1 pins both (5 / 7).
- F5 P3: `train_provider.dart` reaches writer A from `:713` AND `:742` (lost-rows repair on an EXISTING account). **Folded:** named in the parameter comment, the constraints and the diagnose-doc — OFF stays right for it.
- F6 P3: "never a hang" was unverified — the upsert has no `.timeout()` and the coach card's spinner waits on it. **Folded:** wording corrected to "the exposure holdWeek accepted"; diagnose-doc.
- F7 P3: `_executedMessage` says "Plan regenerated" for a sweep-only success. **Recorded on OI-190** with F12 (card copy decided once; needs a `ToolIntent` field to carry `data`).
- F8 P3: the ai_coach CLAUDE.md append point was mid-bullet. **Folded:** after "See ADR-0012." (`:58`).
- Line-anchor corrections applied: `execute()`'s catch `:227` (not `:1482`); `RegeneratePlanResult` field `:63`, ctor `:74-79`; restore window writes `:1126,1129`.
- Round 4 also confirmed: writer-A census complete and correctly classified; `autoGenerateNextPhaseIfNeeded` has exactly two external callers (`pro_phase_advance.dart:174`, `simulation_service.dart:550`); no consumer reads `count`/`schedules` from a success (`ToolExecutionResult` is referenced by 2 files, both read only `success`/`errorMessage`); every pin landmark occurs once at the expected position and M11-M17 each redden the named pin; the count predicate matches `_scheduledWorkoutDays` for Map rows; every behavioural literal re-derived; compile-level symbols resolve (`int.clamp` yields `int`, `cache()` 5-arity, `rawWeekNumberFor` static, `scheduleKeyFor` + `dart:io` in the harness).

**Round 5 — 2026-09-13, context-blind on v5 (round-4 deltas only), `converged`, 4 findings (0 P0-P2, 4 P3), all folded.** F1 stale round-3 clause about `pausedForSimulation` in the "Sweep ⇒ push" constraint — struck. F2 the two hermetic `redoWeek4()` tests never set the flag; the null session alone protects them (the path `holdWeek()` already takes in `hold_week_mechanic_behavioral_test.dart:128,147,160`) — reworded. F3 "four push blocks" → five sites, six blocks. F4 the holdWeek block cited four ways → `:359-367`; `redoWeek4` is `:178-215`. Confirmed: `execute()` has exactly two pre-handler guards (`isExpired` `:96`, per-id marker `:103-111`), so the fresh-id second dispatch reaches the empty branch; `cache()` under a new id makes `getCachedRawSchedules` return the (empty, non-null) list; `coachBox` is opened by the harness (`hive_user_session.dart:88-96`; the copied harness's dispatch tests pass today — 44/44 across the three files run); `:214` is `redoWeek4`'s last statement and its only early return (`:181`) precedes any window move; the year-sim flips `pausedForSimulation` false at `:288` BEFORE its flush, and `weeklyFullSync` calls `_syncWorkoutPlan` directly (`sync_service.dart:1201`) so the guard cannot starve the cloud copy; every record-type shape in the plan (incl. `const (workouts: 0, removed: 0)`) analyzes clean on SDK `^3.11.1`; both new pins' literals are absent inside their scan ranges today (cannot pass vacuously) and M18/M19 each redden the named pin; all counts (11 + 8 tests, 19 legs, census basenames, stage lists) consistent.

**Implementation starts on v5.**

**Implementation notes (2026-09-13, after the code was written):** `res.data as Map` tripped `cast_nullable_to_non_nullable` (a WARNING here) → `as Map?` + `isNotNull`; the regen-block pin needed `expect(sweep, isNonNegative)` because M8 showed `-1 < emptyBranch` passing vacuously with the sweep absent (found by the mutation, exactly the reddens-nothing class); `dart format` was NOT run on the eight lib files — they are not format-clean at base and formatting them produced a 1,700-line diff that hid the real 403-line change.
