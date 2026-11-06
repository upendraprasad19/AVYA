---
bug_id: b9e4d1
date: 2026-09-13
batch: oi189-plan-end-bound
status: fixed
blast_radius: platform
related_bugs: [d7f3b2, 9c3e7a, c9e4b7]
recurrence: >
  Sixth instance of the OI-166 schedule-row class (d7f3b2's own `recurrence` calls itself the
  fifth): a phase-layout writer bounded its ROWS by something other than the STORED phase window.
  d7f3b2 bounded writer B's WRITE range at plan_end; it left (a) writer C
  (`RegeneratePlanPlanner.plan()`) still writing its requested `weeks` from today with no plan_end
  reference at all, and (b) B's DELETE loop still stopping at plan_end — so a row already PAST
  plan_end was neither rewritten nor removed by any regen. Q7 of OI-166's round-3 review named
  exactly this and was lost across the Unit 2 re-plan (OI-189's `Identified` line). The
  sibling-writer asymmetry round 1 of THIS plan caught (a sweep on B only, not on C's two commit
  sites) is `feedback_mistake_guard_without_its_mirror` shape. The unconditional push that round 2
  added to writer A and round 3 had to make opt-in (a reinstall generates on a fresh Hive BEFORE the
  cloud restore) is the `feedback_plan_review_twice` "review #2 on the hardened plan" case.
symptom: >
  Three sentences, verified against `main` @ 39111d1e and the founder's stated lifecycle model
  (every phase is [plan_start, plan_end] = Monday..Monday+27; holds/redo extend plan_end by 7; the
  next phase starts the Monday after plan_end; a mid-phase regen keeps completed rows and rewrites
  today..plan_end):

  1. Writer C (AI-coach `regeneratePlanBlock` / `switchGoal`) laid out `weeks` (1-12) from today
     regardless of the stored plan_end, so a coach regen could CREATE rows past the phase end.
  2. Nothing swept rows already past plan_end: B's delete loop and both writers' write loops stop
     AT plan_end, so orphans from the pre-Unit-2 Edit-Profile loop, the pre-bound coach path, or the
     three user-directed writers that accept an arbitrary date (assignTemplateToDate, the coach
     hotel workout, the coach reschedule destination) survived every regen — keeping the OLD goal's
     workouts after a goal change.
  3. While any non-rest row existed on/after today, `isPhaseExpiredFrom` reported the phase alive
     (it filters by type, not status), so the next phase never auto-generated and the orphan rows
     were SERVED as the user's plan (OI-174's advance-delay half).

  Two durability defects sat underneath, found by rounds 2-4 of the plan review: writers that MOVE
  the window (`generateAndSchedule` on a phase advance, `redoWeek4` — the LIVE free-tier repeat
  path) pushed no plan_json until the next weeklyFullSync, while `_restoreWorkoutPlan` mirrors the
  cloud copy back on EVERY launch and `PlanWindowReanchor` treats a differing cloud window as
  authoritative (c9e4b7) — so a sweep that trusts the stored window could be handed a STALE one.
concept: >
  The design, now structurally true for every phase-layout writer: (1) the stored
  `[plan_start_date, plan_end_date]` bounds every row a regen WRITES (B since d7f3b2; C here, by
  the same literal-date comparison on local midnights, never a week-bucket one — d7f3b2 sub-defect
  1); (2) every regen SWEEPS non-completed rows already past plan_end through one shared helper,
  `WorkoutScheduleReadService.sweepNonCompletedRowsPastPlanEnd` (key scan, no horizon assumption;
  removes `schedule_*` rows of any non-completed status/type plus `displaced_*` shadows; returns
  `({workouts, removed})` — `workouts` is the `_scheduledWorkoutDays` predicate, i.e. exactly the
  set that keeps the phase looking alive, and is what the preview shows; `removed` is what the
  dispatcher branches on, because a rest-only sweep still changed Hive; no-op unless BOTH window
  keys are stored, since a restore writes them independently); (3) every writer that sweeps or
  MOVES the window pushes plan_json immediately via the holdWeek durability block — B, both coach
  commit sites (including the "nothing to write" branch), `redoWeek4`, and writer A ONLY at its
  two phase-advance sites through a new `pushPlanWindow` opt-in, because A is also the reinstall /
  new-device / lost-rows-repair generator and a push from those sites would REPLACE the only cloud
  copy holding the real plan's exercises and hold rows with a fresh one (`_syncWorkoutPlan` is a
  whole-blob REPLACE; the facade does not forward the flag, so those callers cannot opt in by
  accident); (4) `pushWorkoutPlanForSyncDomain` gains the `pausedForSimulation` guard every sibling
  entry point already had, because the dev year-sim now reaches it ~30 times per run through the
  advance site. The coach preview reports the bounded week count (`totalWeeks`), what was asked
  (`requestedWeeks`), the bound (`phaseEndsOn`) and what the commit will clear
  (`clearsPastPhaseEnd`); a regen whose sweep removed rows but had nothing to write returns SUCCESS
  with `count: 0, cleared: N` so `execute()`'s invalidate/sync tail runs (Home's expired-card gate
  reads the non-autoDispose todayWorkoutProvider), and is refused — cache kept, Retry repeats —
  only when the sweep removed nothing.
sot_registry_entry: workout_schedule_read_path
sot_registry_note: >
  The sweep helper is a new writer on the schedule-row concept the read service already owns; no
  new concept. `line_range`s the parity gate names are refreshed in this batch.
writers:
  - { file: lib/core/services/workout_schedule_read_service.dart, method: "sweepNonCompletedRowsPastPlanEnd — NEW shared helper, returns ({workouts, removed}), dryRun for previews", line: 1587 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method: "generateAndScheduleFromDate (B) — sweep after the delete loop", line: 415 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method: "generateAndScheduleFromDate (B) — plan_json push before `return plan;`", line: 610 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method: "generateAndSchedule (A) — `bool pushPlanWindow = false` parameter", line: 208 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method: "generateAndSchedule (A) — gated push after the rows", line: 344 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method: "autoGenerateNextPhaseIfNeeded — passes pushPlanWindow: true (phase advance #1)", line: 674 }
  - { file: lib/shared/services/pro_phase_advance.dart, method: "runGraduationPhaseAdvance — passes pushPlanWindow: true (phase advance #2; reads the read service directly, :515)", line: 585 }
  - { file: lib/core/services/workout_schedule_write_service.dart, method: "redoWeek4 — plan_json push after the plan_end move (the LIVE free-tier repeat path via runFreeTierRepeatWrite)", line: 228 }
  - { file: lib/core/services/sync/sync_workout.dart, method: "pushWorkoutPlanForSyncDomain — `if (SyncService.pausedForSimulation) return;` guard FIRST", line: 2103 }
  - { file: lib/features/ai_coach/services/regenerate_plan_planner.dart, method: "plan() — startDay/planEndDay/boundedWeeks + dry-run clears count; day loop skips every day past plan_end; result carries requestedWeeks/phaseEndsOn/clearsPastPhaseEnd", line: 256 }
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method: "_executeRegeneratePlanBlock — sweep, then empty branch: push + success-with-cleared (removed > 0) or failure (removed == 0); post-splice push; `cleared` on every success", line: 856 }
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method: "_executeSwitchGoal — sweep after the profile guard before patchProfile; post-splice push; `cleared` on every success", line: 1113 }
  - { file: lib/features/dev/simulation_service.dart, method: "review B-1 — end-of-run flush pushes plan_json too (pushWorkoutPlanForSyncDomain no-ops for the whole loop under pausedForSimulation; nothing else in the flush list carries plan_json)", line: 309 }
  - { file: lib/features/ai_coach/widgets/diff_preview/phase_note.dart, method: "review B-4 — phaseNote()/phaseDayLabel() extracted as shared pure functions (both widgets delegate); the only form that is directly unit-testable", line: 22 }
readers:
  - { file: lib/core/services/workout_schedule_read_service.dart, method_or_widget: "isPhaseExpired / isPhaseExpiredFrom / _scheduledWorkoutDays — the expiry gate the orphans defeated; the sweep's `workouts` count uses its exact predicate", line: 1516 }
  - { file: lib/shared/services/pro_phase_advance.dart, method_or_widget: "advanceProPhaseIfExpired — isPhaseExpired() gate", line: 144 }
  - { file: lib/features/home/screens/home_screen.dart, method_or_widget: "expired-card gate: todayWorkoutProvider == null && isPhaseExpired()", line: 770 }
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: "todayWorkoutProvider (non-autoDispose) — why the sweep-only regen must SUCCEED to reach the invalidation tail", line: 530 }
  - { file: lib/features/train/screens/train/screen.dart, method_or_widget: "isPhaseExpired() reader", line: 169 }
  - { file: lib/core/services/deload_evaluator.dart, method_or_widget: "isPhaseExpired() reader", line: 61 }
  - { file: lib/features/ai_coach/widgets/diff_preview/regenerate_plan_diff.dart, method_or_widget: "_phaseNote — three forms; replaces the header when totalWeeks == 0 (delegates to phase_note.dart, review B-4)", line: 182 }
  - { file: lib/features/ai_coach/widgets/diff_preview/switch_goal_diff.dart, method_or_widget: "_phaseNote — same; the week/day section is hidden when totalWeeks == 0 (delegates to phase_note.dart, review B-4)", line: 205 }
  - { file: lib/features/ai_coach/widgets/tool_confirm_card.dart, method_or_widget: "failed-intent card with Retry (:234-255); EF-authored previewSummary (:307); _executedMessage keys on TYPE (:409) — card copy residual on OI-190", line: 234 }
  - { file: lib/core/services/plan_window_reanchor.dart, method_or_widget: "PlanWindowReanchor.resolve — cloud window authoritative on a phase advance; why the window-movers must push immediately", line: 45 }
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_restoreWorkoutPlan — mirrors cloud plan_json back on EVERY returning launch (restoreLightweightAlways, sync_service.dart:1383)", line: 1131 }
hive_key_prefix: schedule_
hive_key_formula: >
  workoutBox['schedule_<yyyy-MM-dd>'] (istDateStr) — the sweep removes every such key dated after
  the stored plan_end whose 'status' != 'completed', plus the matching 'displaced_<yyyy-MM-dd>'
  shadow keys; it counts as `workouts` those rows whose 'type' is neither 'rest' nor 'off'.
  MigratedKey 'plan_start_date' / 'plan_end_date' (user-scoped ISO strings) — BOTH must be present
  for the sweep to act. workoutBox['current_plan'] — unchanged by the sweep; pushed as part of
  plan_json by every site below.
sync_methods: >
  `pushWorkoutPlanForSyncDomain → _syncWorkoutPlan` (whole-blob REPLACE of user_progress.plan_json
  rebuilt from local keys; silent no-op when current_plan is null; now returns FIRST on
  pausedForSimulation) — now called by B, both coach commit sites incl. the empty branch,
  redoWeek4, holdWeek (pre-existing) and A ONLY at the two phase-advance sites. Awaited at every
  site (holdWeek precedent); its upsert carries no .timeout(), so the coach card's spinner waits on
  it — the exposure holdWeek already accepted. `syncWorkoutData → _syncScheduledWorkouts` does NOT
  carry plan_json and is upsert-only (never deletes a cloud scheduled_workouts row — OI-174
  residual). `pushSnapshot` is the daily-snapshot EF, no plan_json.
restore_methods: >
  `_restoreWorkoutPlan` (sync/sync_workout.dart:1131, runs on EVERY returning-user launch via
  restoreLightweightAlways, sync_service.dart:1383), `_restoreScheduledWorkouts` (since 2020-01-01),
  `PlanIntegrityReconciler.reconcile` (plan_integrity_reconciler.dart:288-306) — all three
  UNBOUNDED by plan_end and unchanged here. Stated as the OI-174 residual, NOT as "self-heals": a
  row swept locally can return from the never-pruned cloud scheduled_workouts table on a restore
  until the next regen sweeps it again; the immediate plan_json pushes above close the plan_json
  half of that loop, not the scheduled_workouts half.
cloud_table: scheduled_workouts
cloud_columns: [scheduled_date, status, week_number, day_of_week]
contract_test_path: test/contracts/oi189_plan_end_bound_behavioral_test.dart
ist_handling:
  - { file: lib/core/services/workout_schedule_read_service.dart, line: 389, fn: "today = istMidnight(fromDate) — B; unchanged; the sweep compares date-only local midnights parsed from the stored ISO window and the schedule_ key" }
  - { file: lib/features/ai_coach/services/regenerate_plan_planner.dart, line: 495, fn: "_today() = DateTime.now() local midnight — PRE-EXISTING (not istMidnight(nowWall())): on a device EAST of IST istDateStr(localMidnight) lags one day; invisible on IST dev / UTC CI; noted, not fixed here. The new bound normalises `start` to startDay before comparing." }
  - { file: lib/features/ai_coach/services/regenerate_plan_planner.dart, line: 500, fn: "_fmt = istDateStr — identical to WorkoutScheduleReadService.dateKey, which phaseEndsOn uses" }
  - { file: lib/core/utils/ist_date.dart, line: 62, fn: "nowWall() — read by isPhaseExpired; the B tests pin the flip through setTestClockTo/resetTestClock (:35,:38)" }
provider_invalidations: >
  None added. `ToolDispatcher.execute()`'s existing success tail (`_invalidateWorkoutProviders`:
  todayWorkoutProvider, currentPlanProvider, calendarWeekProvider, …) is REACHED for the
  sweep-only regen because that branch now returns success — the behavioural test asserts
  todayWorkoutProvider non-null → null across the dispatch. Edit-Profile's own invalidation after
  generateAndScheduleFromDate is unchanged.
telemetry_op_types:
  success: []
  failure: [generate_and_schedule_plan_window_push, regen_from_date_plan_window_push, regenerate_plan_block_refusal_plan_window_push, regenerate_plan_block_plan_window_push, switch_goal_plan_window_push, redo_week4_durability_push]
cross_account_guard: >
  not_applicable — every read/write flows through the existing user-scoped box layer
  (HiveService.workoutBox via wrapUserScopedBox, MigratedKey user-scoped keys); the sweep reads
  and deletes only the current owner's workoutBox.
forbidden_patterns_checked: >
  - No raw `Hive.box(` — the helper uses `_hive.workoutBox`; the dispatcher reuses its already-open
    box/wbox locals.
  - No `unawaited(` push without a sink — every push is awaited inside try/catch with a
    recordNonFatal `reason:`; the only unawaited calls are the telemetry sinks themselves.
  - No week-bucket comparison in the new bound — `DateTime(d.year, d.month, d.day).isAfter(planEndDay)`
    on both sides (d7f3b2 sub-defect 1).
  - `pushPlanWindow` appears in exactly two call sites and NOT in the facade
    (workout_schedule_service.dart), auth_session_bootstrapper.dart, train_provider.dart,
    onboarding_provider.dart or simulation_service.dart — pinned by a source test.
  - `check_single_schedule_row_builder.dart` (§4.11 gate) still passes — no third row-layout
    implementation; the helper deletes rows, it does not lay them out.
  - No `dead_code` — the pushes sit BEFORE `return plan;` (rule: dead_code is a WARNING here).
proposed_fix: >
  Implemented as planned (docs/superpowers/plans/2026-09-12-oi189-plan-end-bound.md v5, five
  context-blind review rounds): (1) the shared sweep helper; (2) B sweeps after its delete loop and
  pushes before returning; A pushes only when `pushPlanWindow: true`, passed at
  autoGenerateNextPhaseIfNeeded and the PRO advance; redoWeek4 pushes after moving plan_end;
  pushWorkoutPlanForSyncDomain guards on pausedForSimulation first; (3) C's plan() bounds every
  day at the stored plan_end and reports totalWeeks (bounded) / requestedWeeks / phaseEndsOn /
  clearsPastPhaseEnd; (4) both dispatcher commit sites sweep, push, and carry `cleared`; the
  empty-set branch is success-with-cleared when the sweep removed anything, failure otherwise;
  (5) both diff previews render the phase note (three forms) and hide the week section when
  totalWeeks == 0. Founder decisions: D1 restore residual stays on OI-174 (unit stays `account`);
  D2 user-placed rows past plan_end are swept too.
regression_test_planned: >
  test/contracts/oi189_plan_end_bound_behavioral_test.dart — 27 tests, all green:
  ELEVEN behavioural through the real paths (Hive boxes + the real plan() → cache() → execute()
  dispatch): helper (7 keys past plan_end: 5 workouts + 1 rest + 1 shadow; dry-run counts without
  deleting; idempotent; plan_end-only is not a window), B1 mid-window regen sweeps +28..+34 and
  keeps the completed row, B2 EXPIRED regen writes nothing and flips isPhaseExpired false→true,
  B3 first generation leaves a stray row (no horizon), C1 4 weeks requested with 10 days left →
  totalWeeks 2 / requestedWeeks 4 / phaseEndsOn / no row past plan_end after dispatch, C2 fitting
  block still reports clearsPastPhaseEnd 1 without sweeping, C3 explicit startDate past plan_end →
  0 rows, C4 no plan_end → unbounded (invariant), C5 EXPIRED + orphans → dispatch SUCCESS with
  count 0 / cleared 7, todayWorkoutProvider non-null→null, then a FRESH-id second dispatch is the
  refusal (a same-id re-dispatch hits execute()'s idempotency marker — round 4 F1), C6 switch_goal
  → goal changed, cleared 4, phase expired.
  EIGHT source pins (presence AND order against landmarks — the last row write, the window write,
  the splice, clearCache, patchProfile, _ensureSessionOpen), stated as pins because
  _syncWorkoutPlan needs a live Supabase client so no offline test can observe a push (the OI-171
  precedent, deload_eval_behavioral_test.dart:722-763): writer A gated push after the rows, writer
  B sweep-before-window-write + push after the rows, pushPlanWindow: true at exactly the two
  advance sites, pushPlanWindow absent from the facade + four boot/repair callers, regen block two
  pushes in order, switch_goal sweep-before-patchProfile + push in order, redoWeek4 push after the
  plan_end move, the pausedForSimulation guard before _ensureSessionOpen.
  ONE more behavioural, added by B-pass review finding B-2: a `displaced_*` shadow carrying
  `status: 'completed'` past plan_end survives the sweep (removed 0) — the completed-row exemption
  used to only ever look at `isSchedule` rows.
  SIX unit tests on the shared `phaseNote()`/`phaseDayLabel()` pure functions extracted from both
  diff-preview widgets' identical private methods (B-pass review finding B-4 — the methods were
  library-private on private State classes with zero test coverage before this): the three message
  forms (no note / "ends on" / "Stops at" / "ended on ... nothing left"), the clears==0 vs >0
  branch, singular vs plural "workout(s)", and the day-label format.
  ONE more source pin, added by B-pass review finding B-1: `simulation_service.dart`'s end-of-run
  flush now includes a `pushWorkoutPlanForSyncDomain` call (every in-loop phase advance runs with
  `pausedForSimulation == true`, so the push guard no-ops on all of them, and nothing else in the
  flush list carries `plan_json` — the sim harness never calls `weeklyFullSync` either).
  MUTATED AND RUN — 22 legs, each confirmed applied, run against the file, restored (first
  failing assertion as the runner reported it):
  M1 helper 'completed' → 'completed_': 3 red (helper-1 `dry.workouts` 5 vs 6, B1, C5).
  M2 helper drops the plan_start requirement: 1 red (helper-2 `.removed == 0` vs 1).
  M3 B sweep deleted: 3 red (B1 "+28", B2 "+29", pin writer B).
  M4 planner `continue` block deleted: 4 red (C1 per-row past plan_end, C3, C5, C6).
  M5 planner `+ 1` → `+ 0`: 1 red (C1 totalWeeks 2 vs 1).
  M6 dispatcher `removed > 0` → `>= 0`: 1 red (C5 second dispatch `again.success isFalse`).
  M7 switch_goal sweep → const zero: 2 red (C6 `cleared` 4 vs 0, pin switch_goal).
  M8 regen sweep → const zero: 2 red (C5 `res.success isTrue`, pin regen block — the pin needed an
  `isNonNegative` on the sweep index first: with the sweep absent, `-1 < emptyBranch` had been
  vacuously true; fixed in-batch, the reddens-nothing-is-not-coverage lesson).
  M9 dryRun guard → always delete: 4 red (helper-1 "dry run must not delete", C2/C5 "plan() is a
  preview", C6).
  M10 count everything: 1 red (helper-1 `dry.workouts` 5 vs 6; `removed` stays 7).
  M11 `pushPlanWindow: true` removed at the auto-advance: 1 red (pin two-sites).
  M12 facade forwards the flag: 1 red (pin not-reachable).
  M13 A's push moved above the rows: 1 red (pin writer A `> lastIndexOf(rowWrite)`).
  M14 B's push moved above the window write: 1 red (pin writer B).
  M15 empty-branch push deleted: 1 red (pin regen block `allMatches == 2`).
  M16 post-splice push moved above the splice: 1 red (pin regen block).
  M17 switch_goal push moved above patchProfile: 1 red (pin switch_goal).
  M18 redoWeek4 push moved above the plan_end write: 1 red (pin redoWeek4).
  M19 pausedForSimulation guard deleted: 1 red (pin guard `isNonNegative`).
  M20 (B-pass B-2) displaced-row completed check removed: 1 red (new "displaced_ shadow with
  status: completed" test — `swept.removed` 0 vs 1).
  M21 (B-pass B-1) sim flush's plan-window push line removed: 1 red (new sim source pin).
  M22 (B-pass B-4) phaseNote's singular/plural swapped (`clears == 1 ? 's' : ''`): 2 red (the
  totalWeeks==0 singular/plural test AND the "ends on" clears=2 test — the only leg in this table
  that reddens on two assertions by design, both checking the same inverted ternary).
  Census: `grep -rl` over test/ for TEN basenames — the 8 edited lib/ files, the facade
  `workout_schedule_service.dart` (deliberately NOT forwarding pushPlanWindow, per M12 + the
  "pushPlanWindow absent from the facade" pin — not itself edited, but exercised by name in the
  fixture list), and the test file itself. (`phase_note.dart` is a new file with no name of its
  own to search for — every test that reaches it does so by importing one of the three files
  already in this list.) → 92 files. Reproducible:
  `for n in sync_workout workout_schedule_read_service workout_schedule_write_service
  workout_schedule_service pro_phase_advance regenerate_plan_planner tool_dispatcher
  regenerate_plan_diff switch_goal_diff oi189_plan_end_bound_behavioral_test; do grep -rl "$n"
  test/; done | sort -u | wc -l` → 92; `flutter test` on that file set → `+857: All tests passed!`
  (the 8 new B-pass-review tests raised this from the pre-review 849; 1 skipped, unrelated — a
  live-Supabase-only test with no env vars in this harness).
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze lib/ test/ — 0 errors, 0 warnings (counted with ^\\s*warning -, the width-safe anchor); 248 pre-existing infos, none in the 11 edited/new files (re-run after the B-pass review fixes: unchanged)." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "oi189_plan_end_bound_behavioral_test.dart seeds real Hive boxes and asserts schedule_* / displaced_* keys, plan_end_date, isPhaseExpired and todayWorkoutProvider directly; 27/27 green; 22/22 mutations reddened as designed." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change; user_progress.plan_json and scheduled_workouts are unchanged in shape." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Read-only census on dedsavbjuwgarrhphgnl 2026-09-13, both cloud copies: (A) user_progress.plan_json — `with snap as (select user_id, (plan_json->>'plan_end_date')::date as plan_end, plan_json->'schedules' as schedules from public.user_progress where plan_json is not null and plan_json->>'plan_end_date' is not null) select count(distinct s.user_id), count(k.key) filter (where substring(k.key from 10)::date > s.plan_end), count(k.key) from snap s left join lateral jsonb_object_keys(coalesce(s.schedules,'{}'::jsonb)) k(key) on k.key like 'schedule\\_%' escape '\\'` → users 10, rows_past_plan_end 0, total 369. (B) scheduled_workouts — same snap CTE, `count(w.id) filter (where w.scheduled_date > s.plan_end and coalesce(w.status,'') <> 'completed')` → 0 (any status → 0), total 369. Zero live instances today; the fix is forward-only protection." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration in this batch." }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "Client-only change. The EF tool text regeneratePlanBlock.ts:5-6,42,54 ('1-12 weeks … start a new phase'; previewSummary 'Regenerate next N weeks') is deliberately NOT changed — catastrophic-tier deploy, recorded on OI-190 as an input." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron path touches any writer here." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy change; the plan_json upsert is the pre-existing user-scoped one." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No storage object touched." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No secret read or written." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service involved." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "C5/C6 drive the REAL ToolDispatcher.execute(ref, intent) path end-to-end (plan() → cache() → dispatch → sweep → push attempt → splice → invalidation tail); the push itself is a hermetic no-op (pausedForSimulation guard first, null session second) and is pinned by position instead." }
impact_analysis: >
  Free + PRO, every user who regenerates via Edit Profile or the AI coach, and every user who
  advances a phase or taps the free-tier "keep training" (redoWeek4). Zero prod users affected
  today (both censuses 0/369) — this is forward-only protection for exactly the states the founder's
  lifecycle model forbids. After the fix: a coach regen can no longer create a row past plan_end;
  any regen removes non-completed rows already past it (D2: including user-placed ones — the next
  phase's generation overwrites those dates regardless, and while they exist it never runs); the
  preview says when the block was shortened and what will be cleared; a sweep-only regen shows
  "Done" and Home's expired card appears (the invalidate tail runs); every window move is pushed
  immediately so the sweep is never handed a stale window online.

  Stated residuals, each owned:
  - OI-174 (OPEN, narrowed): the cloud scheduled_workouts table is never pruned
    (_syncScheduledWorkouts is upsert-only) and the three restore writers are unbounded, so a swept
    row can return on a restore until the next regen; an OFFLINE phase advance still leaves the
    PlanWindowReanchor revert window open until the next successful push — the immediate pushes
    mitigate, not eliminate. Fix design on the entry (a cloud delete issued by the sweep + a
    freshness guard on the reanchor; platform tier).
  - Round-3 F1 (why the push is opt-in on A): auth_session_bootstrapper.dart:653 generates on a
    fresh Hive from _ensureLocalUser at sign-in, BEFORE restoring_screen starts the restore, and
    train_provider.dart's _autoGeneratePlan fires at :713 (no plan) AND :742 (an EXISTING account's
    week-1 rows lost — a repair); a push from either would replace the cloud copy. Do NOT "fix"
    :742 by opting in.
  - Round-3 F4: a Hive throw AFTER the sweep (patchProfile rethrow, upsertScheduled, the splice put)
    escapes to execute()'s catch (:227) with no push and no invalidation — pre-existing
    half-applied-tool behaviour, healed by the next launch's restore.
  - Round-4 F6: the awaited push has no .timeout(); the coach card's spinner waits on it — the
    exposure holdWeek already accepted; kept so all six blocks share one shape.
  - Round-4 F7 + round-2 F12 (OI-190 inputs): the executed card says "Plan regenerated" for a
    sweep-only success (tool_confirm_card.dart:409 keys on TYPE; carrying data to the card needs a
    ToolIntent field) and the confirm card's summary line is EF-authored ("Regenerate next N
    weeks") — the coach card's copy for the bounded-regen case is decided once there.
  - holdWeek/redoWeek4 write their rows and THEN move plan_end (7 awaits apart); a sweep
    interleaved there would delete the just-written week — unreachable from one user's UI
    (different screens, no shared trigger; autoGenerateNextPhaseIfNeeded calls A, not B).
  - RegeneratePlanPlanner._today() is DateTime.now(), not istMidnight(nowWall()) — pre-existing.
  - B-pass review B-3: a FUTURE-dated `completed` row past plan_end is correctly PRESERVED by the
    sweep (it is history) but `_scheduledWorkoutDays()` (isPhaseExpiredFrom's own predicate,
    workout_schedule_read_service.dart:1642, PRE-EXISTING and untouched by this unit) filters only
    by `type`, never by `status` — so that one row keeps `isPhaseExpired()` false exactly the way
    an un-swept orphan used to. The new test file's own comment at the "helper" group's fixture
    already names this and sidesteps it by dating its completed row in the PAST. Not fixed here:
    `isPhaseExpiredFrom`/`_scheduledWorkoutDays` are outside this unit's writer-C-bound-plus-sweep
    contract and carry their own blast radius; tracked on OI-174 alongside the other bound-adjacent
    residuals rather than expanded into.
---

# b9e4d1 — Every phase-layout writer stops at `plan_end`; every regen sweeps past it; every window move is pushed

Closes **OI-189** (`closes-oi: OI-189`). OI-174 stays OPEN, narrowed (founder decision D1).
Plan: `docs/superpowers/plans/2026-09-12-oi189-plan-end-bound.md` (v5 after five context-blind
review rounds — the Review log at its foot is the round-by-round record).

## The one-paragraph version

The founder's phase model says a phase is `[plan_start, plan_end]` and nothing planned sits past
`plan_end`. Unit 2 (d7f3b2) made Edit-Profile regen honour that for the rows it WRITES; the AI-coach
regen did not, and nothing removed rows already past the end. Those orphans kept the old goal's
workouts after a goal change and kept the phase looking alive, so the next phase never generated.
This unit gives the coach writer the same bound, gives both regen paths one shared sweep, and makes
every writer that moves or trusts the window push `plan_json` immediately — with writer A's push
opt-in, because the reinstall path generates a plan on a fresh Hive before the cloud restore and a
push there would overwrite the only real copy.

## What the five review rounds changed, in one line each

1. Sweep on B only → shared helper + both coach commit sites; `pushSnapshot` ≠ `plan_json`.
2. Refusal returned before the push/invalidation; writer A moved the window and pushed nothing.
3. Round 2's unconditional A push fires on the reinstall path → `pushPlanWindow` opt-in at the two
   advance sites; sweep-only regen must SUCCEED to reach the invalidate tail; no test covered the
   pushes → source pins.
4. C5's second dispatch hit `execute()`'s idempotency marker (my test bug — fresh id); `redoWeek4`
   moves the window without a push; the year-sim reaches the push unguarded; branch on `removed`.
5. Wording only — converged.

## B-pass (`docs/reviews/oi189-plan-end-bound-bpass.md`) — finding disposition

Two fresh context-blind reviewers, read-only lenses split from mutation lenses per that skill's
own tuning history. 11 findings total (0 P0, 0 P1-blocking-code, 6 P2, 5 P3), 0 false_alarm.

- **Fixed in this batch** (each mutation-proven, 1 red on the predicted assertion except the
  singular/plural one, 2 red by design): B-1 sim year-run never pushed `plan_json`
  (`simulation_service.dart` flush list) — M21. B-2 a `displaced_*` shadow's own `status` was
  never read, so a completed one would be swept like any orphan (unreachable via the current
  single writer's own discipline, but the sweep should not depend on a DIFFERENT file for its own
  safety property) — M20. B-4 `_phaseNote`'s three forms + the zero-week branch had zero test
  coverage (library-private on a private widget State, unreachable from any test) — extracted to
  shared pure `phaseNote()`/`phaseDayLabel()` in a new `phase_note.dart`, both widgets delegate,
  6 new unit tests — M22.
- **Corrected, no behaviour change** (stale citations, found by A's lens 10 plus two more I found
  re-deriving every citation after the fixes above shifted lines): writer B's push line (613→610),
  writer A's bundled param+push citation split into two (208 / 344), switch_goal's sweep citation
  (1069, which pointed at a doc-comment above the function, → 1113, the real call), both
  `_phaseNote` reader citations (moved by the extraction), the plan doc's two stale
  `blast_radius: account` task bullets (pre-dating the round-4 correction to platform), and the
  census line (92/849 was CORRECT — reviewer B's independent reproduction used 9 of the actual 10
  basenames and got a smaller but still-green 87/784; the missing tenth is
  `workout_schedule_service.dart`, the facade M12 tests but this batch does not edit — now named
  explicitly so the claim is reproducible by a third party without guessing).
- **Documented residual, not fixed** (B-3, out of this unit's scope): see the "Stated residuals"
  bullet above — a future-dated `completed` row keeps `isPhaseExpiredFrom` false, a PRE-EXISTING
  function this unit does not touch.
- **Escalated to the founder, not resolved by the agent** (A-1, P1): `docs/blast_radius.yaml:25`
  requires `feature_flag` at platform tier for changes touching sync/plan-generator paths (§4.6),
  and this batch ships neither a kill-switch nor a written waiver. See the hand-back message for
  the two options put to the founder.
