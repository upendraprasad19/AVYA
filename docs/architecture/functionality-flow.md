---
title: Functionality Flow — Intended-Behaviour Source of Truth & Test Charter
created: 2026-05-31
status: active
scope: cross-cutting
---

# Functionality Flow — Intended Behaviour & Test Charter

This is the **intended-behaviour source of truth** and **test charter** for ICANBEFITTER.
Where `business-rules.md` states *rules* (the free/PRO matrix, calorie formulas) and the
nested `CLAUDE.md` files state *contracts* (writer/reader file:line pairs), this document
states *flow* — how every feature is **intended to behave**, written as numbered, testable
assertions so we can test the running app against it. Each assertion is phrased
"WHEN … THEN …" wherever a trigger exists. If an assertion's intended behaviour and the
code diverge, the code is the bug (unless the assertion is marked `(unverified — confirm)`,
in which case confirm against code first). Treat this file as the canonical charter that
contract tests, integration flows, and manual QA passes are measured against.

## Legend

Each assertion has the form:

> **`SECTION-NN`** — intended behaviour (WHEN … THEN …).
> **Verify:** how to test it. A path under `test/` means a test obviously matches today;
> `needs test` means no obvious test exists yet (collected in *Coverage gaps* at the end);
> `(unverified — confirm)` means I could not fully confirm the behaviour from code and a
> reader should confirm before relying on it.

Section prefixes: `ONB-`/`AUTH-` onboarding & auth · `HOME-` home dashboard ·
`TRAIN-` train/workout/rank · `NUT-` nutrition · `COACH-` AI coach · `PROF-` profile ·
`XC-` cross-cutting invariants.

---

## 1. ONBOARDING & AUTH (`ONB-` / `AUTH-`)

### Sign-in surface & session

- **`AUTH-01`** — WHEN a signed-out user opens the app THEN `splash_screen.dart` routes to the Welcome screen; WHEN a session already exists THEN it routes to `/restoring`. **Verify:** `test/contracts/splash_post_auth_session_gate_test.dart`.
- **`AUTH-02`** — The sign-in surface (`sign_in_screen.dart`) offers Email, Google OAuth, and Phone OTP entry. **Verify:** needs test (widget).
- **`AUTH-03`** — WHEN a user requests forgot-password THEN `forgot_password_sheet.dart` sends a reset link via `Supabase.auth.resetPasswordForEmail` with `redirectTo` set to the prod Web origin (never localhost). **Verify:** needs test.
- **`AUTH-04`** — Phone OTP is NOT wired in prod (Twilio account created but not connected to Supabase Auth) — it fails silently; Email + Google OAuth work normally. **Verify:** `(unverified — confirm)` per `project_pending_twilio_setup.md`; needs prod smoke check.
- **`AUTH-05`** — WHEN sign-up succeeds THEN a `users` row is created and the user is routed to `/restoring`; `users.full_name` lives on the auth-adjacent `users` table, NOT `user_profile`. **Verify:** `test/contracts/user_full_name_writer_to_reader_test.dart`, `test/contracts/full_name_backfill_test.dart`.
- **`AUTH-06`** — WHEN the user accepts Terms at sign-up THEN acceptance is persisted. **Verify:** `test/contracts/terms_signup_writes_test.dart`.

### Post-auth decision tree

- **`AUTH-07`** — WHEN `/restoring` mounts THEN it runs `AuthSessionBootstrapper.hydrateFromCloud()` and `SyncService.restoreFromCloud()` in parallel; the restore is cancellable. **Verify:** needs test (widget); pure-logic side covered by `test/contracts/auth_session_bootstrapper_test.dart`.
- **`AUTH-08`** — WHEN `resolveDestination(row)` sees `onboarding_completed_at != NULL` THEN destination is `GoHome`. **Verify:** `test/contracts/auth_session_bootstrapper_test.dart`.
- **`AUTH-09`** — WHEN `onboarding_completed_at` is NULL AND the Hive profile is populated THEN destination is `GoHome` with Plan-A self-heal (re-stamp `onboarding_completed_at = NOW`). **Verify:** `test/contracts/auth_session_bootstrapper_test.dart`.
- **`AUTH-10`** — WHEN `onboarding_completed_at` is NULL AND the Hive profile is partially populated THEN destination is `ResumeOnboarding(firstMissingStep)` resuming at Identity→Goal→Stats→Details→Plan in that order. **Verify:** `test/contracts/auth_session_bootstrapper_test.dart`.
- **`AUTH-11`** — WHEN there is no `user_profile` row at all (new sign-up) THEN destination is `StartMissionBrief` and the in-flight restore is cancelled. **Verify:** `test/contracts/auth_session_bootstrapper_test.dart`.
- **`AUTH-12`** — WHEN restore does not complete within 15 seconds THEN a CONTINUE button surfaces and the user can reach Home while restore continues in the background. **Verify:** needs test (widget/integration).
- **`AUTH-13`** — `restoreFromCloud()` pulls FULL history (`since='2020-01-01'`), NOT a 30/90-day window. **Verify:** needs test (assert the `since` constant); guard against the `feedback_mistake_restore_window.md` regression.

### Cross-account isolation guard

- **`AUTH-14`** — WHEN Supabase `currentUser.id` disagrees with `HiveUserSession.currentOwnerFullId` THEN `wrapUserScopedBox` (Layer A) returns `GuardedBox.empty(authUid)` so all user-scoped reads serve null/empty/0/false. **Verify:** `test/contracts/wrap_user_scoped_box_disagreement_test.dart`, `test/contracts/auth_hive_owner_agreement_behavioral_test.dart`.
- **`AUTH-15`** — WHEN the auth owner disagrees THEN `authUserIdTokenProvider` returns `'<anon>'`; the 56 user-scoped providers watch it and render empty during disagreement, rebuilding once `openForUser` completes (Layer B). **Verify:** `test/contracts/auth_invalidation_timing_test.dart`, `test/contracts/user_scoped_provider_rebuilds_on_auth_change_test.dart`.
- **`AUTH-16`** — Layers A and B are intentionally redundant; user A's data MUST NOT leak into user B's session across a live sign-out→sign-in race. **Verify:** `test/contracts/auth_hive_owner_agreement_behavioral_test.dart`.
- **`AUTH-17`** — No widget reads user-scoped Hive without going through `wrapUserScopedBox`. **Verify:** `test/contracts/write_service_bypass_detector_test.dart` + `test/lints/` (no raw `Hive.box(`).
- **`AUTH-18`** — WHEN the user is mid-session and `isPro` is read THEN the cross-account isProGuard prevents serving a prior owner's PRO status. **Verify:** `test/contracts/subscription_state_writer_to_reader_test.dart` (cross-account); needs test if not covered.

### Stepped onboarding funnel

- **`ONB-01`** — The default new-user funnel is 6 numbered screens: Mission Brief (00), Identity (01), Goal (02), Stats (03), Details (04), Plan (05), preceded by an unnumbered Welcome. **Verify:** needs test (integration flow).
- **`ONB-02`** — WHEN navigating to any `/onboarding/*` sub-route THEN `GoRouter._authRedirect` matches via `location.startsWith('/onboarding')` (NOT `==`) so sub-routes are not bounced to Welcome. **Verify:** needs test (router); regression fixed in `17faa86`.
- **`ONB-03`** — State is passed between screens via `GoRouter` `state.extra` Map; each screen spreads `...widget.initial` so every upstream field survives to Plan. NO provider commits happen before the final tap. **Verify:** needs test (integration).
- **`ONB-04`** — Identity captures `full_name`, `date_of_birth`, `sex`. `age` is computed on the fly from DOB and is NEVER stored. Name field auto-focuses, title-cases input, enforces 2–40 chars via `_nameAllowed` regex with inline error; min DOB age 13. **Verify:** needs test (widget).
- **`ONB-05`** — Goal captures `primary_goal` ∈ {build_muscle, lose_fat, general_fitness, strength}. **Verify:** `test/contracts/plan_generator_inputs_test.dart` (goal enum).
- **`ONB-06`** — Stats captures `current_weight_kg`, `target_weight_kg`, `height_cm`, `body_fat_pct` (optional, blank default), `activity_level`. WHEN body fat is blank THEN BMR falls back to Mifflin-St Jeor and the copy reads "Skipping body fat — using weight + height." (no false "we'll estimate 18%"). **Verify:** needs test (widget).
- **`ONB-07`** — Details captures `fitness_experience`, `pace_preference`, `days_per_week` ∈ {3,4,5,6}, `equipment_access`; renders as chip rows with defaults pre-selected (Intermediate/Balanced/4/Basic Gym) so CONTINUE always works. CTA label is `CONTINUE →` (not `CALIBRATE PLAN →`). **Verify:** needs test (widget).
- **`ONB-08`** — The Plan screen preview targets are computed by `plan_screen._computeTargets` calling canonical `BmrCalculator.calculateTargets` with every real input; the preview `dailyCalories`/`proteinGrams` exactly match what `completeOnboarding` writes (no drift). **Verify:** `test/contracts/plan_screen_targets_match_completeOnboarding_test.dart`.
- **`ONB-09`** — WHEN the user taps REPORT FOR DUTY on the Plan screen THEN `OnboardingNotifier.completeOnboarding()` runs once, writing the consolidated profile map to `userBox['profile']`, stamping `onboarding_completed_at` (Hive + cloud `user_profile`), and firing the initial sync fan-out. **Verify:** `test/contracts/onboarding_completed_at_writer_to_reader_test.dart`.
- **`ONB-10`** — `completeOnboarding` persists the four defaulted fields (`lifestyle_activity` from `activity_level`, `diet_preference='veg'`, `injuries=['none']`, `start_date='this_monday'`) into the final profile map; `city` is optional/uncollected. **Verify:** needs test (assert profile map keys post-complete).
- **`ONB-11`** — WHEN onboarding completes THEN the initial Phase 1 plan is generated locally (`PlanGenerator.generateV4`) from the user's profile and scheduled from `start_date` IST midnight (`phase_started_at`). **Verify:** `test/plan_generator/v4_diagnostic_test.dart` (generation); needs integration test for scheduling.
- **`ONB-12`** — Phase 1 is ALWAYS free and induction grants rank SD2 immediately. **Verify:** `test/services/rank_service_test.dart` (SD2 default); `business-rules.md` Phase-1-free invariant.
- **`ONB-13`** — Muster answers (Q3..Q5) bridge into profile fields via `InductionService.recordMusterAnswer` → `_bridgeToProfile` (`known_injuries→injuries`, `typical_wake_time→wake_up_time`, `preferred_workout_time→preferred_workout_time`, `body_part_priorities[0]→physique_focus`). **Verify:** `test/contracts/muster_profile_bridge_test.dart`, `test/contracts/muster_bridge_backfill_test.dart`, `test/contracts/muster_question_count_test.dart`.
- **`ONB-14`** — The legacy chat onboarding (`/onboarding/chat`) remains reachable for rollback only; the stepped flow is the default path and the inference fallback must never become the default. **Verify:** needs test.

---

## 2. HOME (`HOME-`)

### Layout & data sourcing

- **`HOME-01`** — Home renders a priority-ordered card stack: Header → Weekly calendar strip → Quick actions → Today's workout → Nutrition snapshot → AI coach insight → Weight sparkline → PR snapshot → Recent foods → Step counter. **Verify:** needs test (widget).
- **`HOME-02`** — Every Home card is read-only with respect to data: each reads from a Riverpod provider wrapping a ReadService, never raw Hive or in-widget cached state. **Verify:** `test/lints/` (no raw `Hive.box(`).
- **`HOME-03`** — WHEN the device day rolls over (cold start tick) THEN `day_rollover_service.dart` invalidates `todayWorkoutProvider`, `homeNutritionProvider`, `streakProvider` on splash/home mount so the day's cards reset. **Verify:** `test/contracts/day_rollover_provider_invalidation_writer_to_reader_test.dart`, `test/contracts/cold_start_day_rollover_test.dart`.

### Streak

- **`HOME-04`** — The streak is schedule-aware: it counts consecutive completed scheduled-workout days; rest days are invisible (not counted, not breaking); it resets only on a missed SCHEDULED workout. **Verify:** `test/contracts/streak_currentstreak_is_pure_test.dart`, `test/contracts/streaks_writer_to_reader_test.dart`.
- **`HOME-05`** — `WorkoutRepository.calculateCurrentStreak()` is a pure READ and MUST NOT consume a freeze as a side effect of rank/splash/post-workout evaluation. **Verify:** `test/contracts/streak_currentstreak_is_pure_test.dart`.
- **`HOME-06`** — WHEN a new week begins THEN streak freezes refill (`StreakFreezeNotifier._refillIfNewWeek`), the available count is clamped on read, and the refill is race-safe. **Verify:** `test/contracts/streak_freeze_refill_race_behavioral_test.dart`, `test/contracts/streak_freeze_value_clamped_on_read_test.dart`, `test/contracts/streak_freeze_refill_telemetry_test.dart`.
- **`HOME-07`** — WHEN a scheduled day is missed AND a freeze is available THEN the freeze is consumed and that day is protected; a spent freeze protects its day PERMANENTLY across recompute (no later collapse). **Verify:** `test/contracts/streak_frozen_day_persists_protection_test.dart`.
- **`HOME-08`** — Freeze state (`streak_freezes_{available, used_dates, last_refill}`) syncs to `user_progress` via `SyncService.syncFreezes()` and restores on reinstall, clamped. **Verify:** `test/contracts/streak_freeze_restore_clamps_test.dart`, `test/contracts/streak_freeze_clamp_migrator_wired_test.dart`.
- **`HOME-09`** — WHEN it is between 18:00–23:00 local AND today's scheduled workout is incomplete THEN the streak-warning banner may show; the threshold is clamped to `[18,23]` (evening-only) in BOTH `StreakWarningBanner.shouldShow` and `home_provider.StreakWarningEligibilityNotifier._evaluate`. **Verify:** `test/contracts/streak_warning_banner_threshold_test.dart`.

### Cards

- **`HOME-10`** — WHEN today's workout is not yet done THEN the Today's Workout card shows "Start Workout"; WHEN it is done THEN it shows a green DONE badge + gold "View Card >" + best lift + total volume. **Verify:** `test/contracts/today_workout_reads_logged_contract_test.dart`.
- **`HOME-11`** — `todayWorkoutProvider` is the single source for the Home "DONE + View Card" state, always derived from Hive schedule + exercise logs. **Verify:** `test/contracts/today_card_vs_calendar_strip_same_source_test.dart`.
- **`HOME-12`** — WHEN the user taps "View Card" THEN `WorkoutReceiptData.fromExerciseLogs(DateTime.now())` reconstructs the receipt from Hive `exlog_*` rows (dedup by name, sum sets, max weight) and opens `WorkoutReceiptSheet`. **Verify:** `test/contracts/workout_receipt_rendering_writer_to_reader_test.dart`, `test/contracts/receipt_scoping_test.dart`.
- **`HOME-13`** — The weekly calendar strip shows 7 days color-coded by completion, sourced from the same provider as the Today card (no divergence). **Verify:** `test/contracts/today_card_vs_calendar_strip_same_source_test.dart`.
- **`HOME-14`** — Quick actions are Log Workout / Log Meal / Hydration / Sleep and route into Train / Nutrition / health logging respectively. **Verify:** needs test (widget).
- **`HOME-15`** — The nutrition snapshot shows today's calories + protein vs target, sourced from `homeNutritionProvider` summing `nlog_*` items. **Verify:** `test/contracts/nutrition_total_calories_writer_to_reader_test.dart`.
- **`HOME-16`** — The weight sparkline shows the last 7 entries forward-filled (no drop to 0 on un-weighed days). **Verify:** `test/contracts/weight_logs_writer_to_reader_test.dart`; forward-fill needs explicit test.
- **`HOME-17`** — WHEN key lifts (bench/squat/deadlift/OHP) have no data THEN the PR snapshot falls back to the top 4 exercises by volume; the unit is derived from `logging_type`; layout adapts 1→full / 2→row / 3→2+1 / 4→2+2. **Verify:** needs test (widget).
- **`HOME-18`** — The AI coach insight card is computed from local schedule data (next workout, consistency tips), not a live API call. **Verify:** needs test.
- **`HOME-19`** — The Future Prediction card truncates to 4 lines + "Read More →" on Home (full sheet on tap); the shareable card caps at 500 chars. **Verify:** needs test (widget).
- **`HOME-20`** — Steps/sleep cards filter health data by BOTH date AND type (`step_log`/`sleep_log`); chat-logged sleep is read from the `sleep_logs` list as fallback. **Verify:** `test/contracts/sleep_logs_writer_to_reader_test.dart`.

### Plan expiry & promotion

- **`HOME-21`** — WHEN a FREE user reaches day 29 (`WorkoutScheduleService.isPhaseExpired()` true) AND `todayWorkoutProvider` is null THEN Home renders `PlanExpiredCard` with 3 doors: Upgrade / Build custom / Re-do Week 4. **Verify:** `test/contracts/phase_unlock_end_to_end_test.dart`; needs explicit PlanExpiredCard widget test.
- **`HOME-22`** — WHEN a PRO user opens the app after Phase 1 THEN `splash_screen._autoGenerateNextPhaseForPro()` generates the next phase so they never land on `PlanExpiredCard`. **Verify:** needs test (integration).
- **`HOME-23`** — WHEN a rank promotion was stamped (pending celebration flag in `userBox`) THEN Home reads + clears it on next mount/resume and pushes `PromotionCelebrationScreen`. **Verify:** `test/contracts/promotion_celebration_wiring_test.dart`.

---

## 3. TRAIN (`TRAIN-`)

### Phase plan, week selector, preview

- **`TRAIN-01`** — The Train screen shows the phase plan + a 12-week / 3-phase week selector with PHASE I / II (PRO) / III (PRO) headers. **Verify:** needs test (widget).
- **`TRAIN-02`** — WHEN a FREE user views weeks 5–12 THEN those weeks show a lock glyph; tapping a locked week opens `/train/preview?phase=…&week=…&day=…` rendering a REAL workout via `previewPlanProvider` → `PlanGenerator.generateV4()` with the user's actual profile. **Verify:** `test/contracts/preview_plan_default_test.dart`, `test/contracts/preview_screen` (needs widget test).
- **`TRAIN-03`** — The locked-week preview shows a state-aware banner ("Complete Phase I to unlock Phase II …") + an UPGRADE TO PRO CTA + a cross-link to `/train/roadmap`. **Verify:** needs test.
- **`TRAIN-04`** — WHEN past completed phases exist THEN `week_selector.dart` walks `workoutBox` `schedule_*` keys with `date < planStart`, buckets by 28-day phases, and renders one read-only `_PastPhaseGroup` per past phase to the LEFT of the current phase (✓ glyph on weeks with ≥1 completed day). Tapping opens a read-only `_PastWeekSheet`. **Verify:** `test/contracts/week_selector_past_phases_test.dart` `(unverified — confirm path)`.
- **`TRAIN-05`** — Past `schedule_*` entries are protected from plan-generator overwrite (Theme H) so scroll-back shows real data, not clobbered data. **Verify:** needs test (assert generator skips `date < planStart`).

### Active workout logging

- **`TRAIN-06`** — The active workout UI is driven by each exercise's `logging_type`: `weight_reps` → Weight+Reps+Sets; `bodyweight_reps` → Reps+Sets; `weighted_bodyweight` → Added Weight+Reps+Sets; `timed` → Sets+Duration+rest timer; `cardio` → Duration+Distance; `distance` → Distance+load. **Verify:** `test/contracts/workout_write_logging_type_library_test.dart`, `test/contracts/timed_exercise_render_contract_test.dart`.
- **`TRAIN-07`** — WHEN a set is logged THEN `WorkoutWriteService.logExercise` writes the `exlog_${istDateStr}_${nameHash}` Hive row (canonical key formula), recomputing `volume_kg = weight_kg × reps_completed` and stamping `workout_log_id`. **Verify:** `test/contracts/exercise_logs_read_path_writer_to_reader_test.dart`, `test/contracts/exlog_key_canonical_test.dart`.
- **`TRAIN-08`** — `WorkoutWriteService` is the SINGLE writer for `exlog_*`/`wlog_*` rows; it acquires a per-exercise mutex, invalidates the full provider batch, and fires `unawaited(syncWorkoutData())` + `pushSnapshot()`. **Verify:** `test/contracts/workout_write_to_read_contract_test.dart`, `test/contracts/sync_fanout_contract_test.dart`.
- **`TRAIN-09`** — `completedSets` filters out warm-up set keys; exercise-name matching is exact-first, fuzzy only for names ≥ 6 chars. **Verify:** `test/contracts/sets_count_3rd_fallback_test.dart`.
- **`TRAIN-10`** — WHEN the workout is completed THEN `WorkoutWriteService.completeWorkout` writes the completion status read by the Train completed-day expanded view and the Home Today card. **Verify:** `test/contracts/workout_completion_status_test.dart`.
- **`TRAIN-11`** — A Workout Receipt PNG is offered after every completed workout (all users — growth engine), reconstructed from Hive, never hand-built from widget state. **Verify:** `test/contracts/workout_receipt_rendering_writer_to_reader_test.dart`.
- **`TRAIN-12`** — WHEN a day has multiple sessions THEN `WorkoutReceiptData.fromExerciseLogs` scopes by `workout_log_id`; legacy rows without it pass through (with a `date == dateKey` fallback). **Verify:** `test/contracts/receipt_scoping_test.dart`, `test/contracts/receipt_legacy_rows_fallback_test.dart`.

### Edit log & swap

- **`TRAIN-13`** — `edit_workout_log_sheet.dart` is the ONLY edit surface; all 4 entry points (receipt Edit, Home View Card, calendar day detail, Train expanded view) route through it. **Verify:** `test/contracts/workout_log_edit_surface_writer_to_reader_test.dart`.
- **`TRAIN-14`** — WHEN an edit is saved THEN it (1) rewrites the Hive map in place, (2) recomputes `volume_kg`, (3) chronologically rescans `is_pr` (sort by `date+created_at`, strict `>`), (4) invalidates `currentPlanProvider`/`workoutStatsProvider`/`calendarWeekProvider`/`streakProvider`/`todayWorkoutProvider`/`allExercisePRsProvider`, (5) fires `syncWorkoutData()`+`pushSnapshot()`. **Verify:** `test/contracts/edit_workout_log_sets_field_contract_test.dart`, `test/contracts/edit_log_field_normalization_test.dart`, `test/contracts/edit_log_id_injection_test.dart`.
- **`TRAIN-15`** — Edit-log reads tolerate dual field names for restore back-compat (`sets[]` OR `sets_detail`; `duration_sec` OR `duration_seconds`). **Verify:** `test/contracts/edit_log_field_normalization_test.dart`, `test/contracts/duration_seconds_aggregate_populated_test.dart`.
- **`TRAIN-16`** — WHEN an exercise is swapped THEN `WorkoutScheduleService.swapExerciseInDay` routes through `WorkoutWriteService.upsertScheduled` (mutex + fan-out). **Verify:** `test/contracts/workout_schedule_service_uses_write_service_test.dart` `(unverified — confirm path)`.

### Templates & schedule mutations

- **`TRAIN-17`** — The template builder is PRO-gated; `WorkoutWriteService.saveTemplate`/`deleteTemplate` are the writers, `tmpl_*` rows the contract; multi-day AI templates split into N rows tagged with `group_id`/`group_day_index`/`group_total_days`. **Verify:** `test/contracts/workout_templates_writer_to_reader_test.dart`, `test/contracts/template_exercises_upsert_test.dart`, `test/contracts/templates_unique_constraint_test.dart`.
- **`TRAIN-18`** — Copy-week and all 9 schedule mutations (markCompleted, markSkipped, activateTravelMode, swapExerciseInDay, shortenDay, copy week ×2, assignTemplateToDate, unscheduleTemplateFromDate) route through `WorkoutScheduleService` → `WorkoutWriteService.upsertScheduled`; `WorkoutScheduleService` is the ONLY writer of `schedule_YYYY-MM-DD` keys. **Verify:** `test/contracts/workout_schedule_service_uses_write_service_test.dart` `(unverified — confirm path)`.
- **`TRAIN-19`** — Scheduled-workout rows upsert with `onConflict: 'user_id,scheduled_date'` (one schedule per user per date); templates sync BEFORE schedules (FK ordering). **Verify:** `test/contracts/sync_onconflict_natural_key_test.dart`, `test/contracts/sync_template_before_schedule_order_test.dart`, `test/contracts/scheduled_workouts_fk_resilience_test.dart`.

### Phase generation & post-12 deployment cycles

- **`TRAIN-20`** — Phase unlock formula: `canUnlock = completionRate >= 0.8 AND weeksElapsed >= 4`. **Verify:** `test/contracts/phase_unlock_end_to_end_test.dart`, `test/contracts/phase_unlock_start_date_test.dart`.
- **`TRAIN-21`** — The Phase Unlock card surfaces from Thursday of phase-week 4 (gate: `plan.currentWeek != 4 || DateTime.now().weekday < DateTime.thursday`); the copy gate (locked "PHASE 2 AVAILABLE" vs unlocked "PHASE 1 COMPLETE!") is driven by `completionRate >= phaseUnlockCompletionRate`. **Verify:** `test/contracts/phase_unlock_card_thursday_gate_test.dart`.
- **`TRAIN-22`** — WHEN a PRO user unlocks the next phase THEN `PlanGenerator.generateV4` generates phases 2–12 locally (zero API cost), querying Hive `exerciseBox`. Phase generation is local Dart only. **Verify:** `test/plan_generator/v4_diagnostic_test.dart`, `test/contracts/plan_generator_inputs_test.dart`.
- **`TRAIN-23`** — WHEN the user passes phase 12 THEN phases keep generating indefinitely as "Deployment N" cycles, recycling advanced phase-9–12 content with continued progressive overload (no dead-end). **Verify:** needs test (assert generation succeeds for `phase > 12`).
- **`TRAIN-24`** — 1 deployment = 1 completed phase, i.e. `deployments_complete = current_phase − 1`. **Verify:** needs test (assert the deployments derivation).
- **`TRAIN-25`** — Graduation Phase-2 preview is dynamic: `graduation_screen` dry-runs `PlanGenerator.generateV4` with the user's real `days_per_week` + derived `nextPhase` (no hardcoded "5 DAYS/WEEK"). **Verify:** `test/contracts/graduation_phase2_preview_dynamic_test.dart` `(unverified — confirm path)`.

### Personalization (from phase 2)

- **`TRAIN-26`** — Personalization is active from phase 2 onward: autoregulated load from logged history, custom-exercise inclusion, weak-point targeting. Phase 1 uses baseline progressive-overload defaults. **Verify:** `(unverified — confirm)` — needs test asserting phase-2 generation consumes logged history while phase 1 does not.
- **`TRAIN-27`** — The V4 pipeline picks exercises via a 5-attempt cascade within movement patterns (never crossing pattern boundaries), targeting per-day exercise counts by experience × days; target output has 0 attempt3/universalPool/none picks. **Verify:** `test/plan_generator/sample_plans_report.dart`, `test/plan_engine_v4/`.
- **`TRAIN-28`** — Phase 1 beginner pools require BOTH `suitable_for` contains "Beginner" AND `is_foundational: true`. **Verify:** `test/plan_engine_v4/` (exercise selector) + `sample_plans_report.dart`.

### Rank / deployment progression (full ladder)

- **`TRAIN-29`** — The ladder has 11 rungs in fixed order (ordinal 0..10): SD2 → SD1 → LS → PO → CPO → MCPO → SubLt → Lt → LtCdr → Cdr → Capt; Captain is terminal. **Verify:** `test/rank_service/rank_gate_fields_test.dart`, `test/services/rank_service_test.dart`.
- **`TRAIN-30`** — Ranks are STRICTLY SEQUENTIAL — `_qualifiedRankCode` walks from the bottom and STOPS at the first failing gate; no rung can be skipped or leap-frogged. So an officer-track completion-rate qualifier CANNOT bypass the deployment-gated PO/CPO rungs. **Verify:** `test/contracts/rank_year_simulation_test.dart`, `test/services/rank_service_test.dart` (sequential walk).
- **`TRAIN-31`** — Rank is PERMANENT (monotonic): `shouldPromote(currentCode, qualified)` returns true only when `qualified.ordinal > currentOrdinal`. Breaking a sailor-track streak gate MUST NOT demote (e.g. SD1 must not fall back to SD2). **Verify:** `test/contracts/rank_no_demotion_behavioral_test.dart`.
- **`TRAIN-32`** — SD2 gate: earned at induction (empty gate). **Verify:** `test/services/rank_service_test.dart`.
- **`TRAIN-33`** — SD1 gate: `streak ≥ 7` AND `weeksSinceSignup ≥ 1`. **Verify:** `test/rank_service/rank_gate_fields_test.dart`.
- **`TRAIN-34`** — LS gate: `streak ≥ 14` AND `weeks ≥ 4`. **Verify:** `test/rank_service/rank_gate_fields_test.dart`.
- **`TRAIN-35`** — PO gate: `streak ≥ 30` AND `weeks ≥ 12` AND `deploymentsComplete ≥ 2`. **Verify:** `test/rank_service/rank_gate_fields_test.dart`.
- **`TRAIN-36`** — CPO gate: `streak ≥ 50` AND `weeks ≥ 26` AND `deploymentsComplete ≥ 3`. **Verify:** `test/rank_service/rank_gate_fields_test.dart`.
- **`TRAIN-37`** — MCPO gate (transition rank): `weeks ≥ 52` AND `completionRate ≥ 0.80` over rolling 12 weeks AND `maxGapDays ≤ 14`. **Verify:** `test/rank_service/rank_gate_fields_test.dart`.
- **`TRAIN-38`** — SubLt gate: `weeks ≥ 104` AND `completionRate ≥ 0.80` over rolling 26 weeks (officer track, no streak requirement). **Verify:** `test/rank_service/rank_gate_fields_test.dart`.
- **`TRAIN-39`** — Lt gate (reaching Lieutenant): `weeks ≥ 130` (~2.5 years tenure) AND `completionRate ≥ 0.80` over rolling 26 weeks AND (sequentially) the full sailor track + SubLt already earned. **Verify:** `test/rank_service/rank_gate_fields_test.dart`, `test/contracts/rank_year_simulation_test.dart`.
- **`TRAIN-40`** — LtCdr `weeks ≥ 156` / rate ≥ 0.80 over 52w; Cdr `weeks ≥ 208` / rate ≥ 0.80 over 52w; Capt `weeks ≥ 260` / rate ≥ 0.85 over 104w (terminal). **Verify:** `test/rank_service/rank_gate_fields_test.dart`.
- **`TRAIN-41`** — `completionRate` = fraction of scheduled workout days completed in the rolling window; rest days + pre-onboarding days excluded from the denominator. **Verify:** needs test (`completionRateOverWindow` denominator semantics).
- **`TRAIN-42`** — `weeksSinceSignup` is measured from `phase_started_at` (IST onboarding midnight) when present, else `auth.users.created_at`; the clock is seam-aware via `nowWall()` for the year-sim harness. **Verify:** `test/contracts/clock_seam_nowwall_test.dart`.
- **`TRAIN-43`** — WHEN qualification advances THEN `evaluateAndPromote` upserts every newly-qualified `rank_promotions` row (UNIQUE `user_id,rank_code`), updates the `user_profile.current_rank_code` denormalization only upward, mirrors to local Hive, invalidates rank widgets, and stamps a pending celebration. **Verify:** `test/contracts/rank_service_idempotent_test.dart`, `test/contracts/rank_service_local_profile_update_test.dart`, `test/contracts/rank_promotion_repository_only_test.dart`.
- **`TRAIN-44`** — Rank evaluation is a READ for streak/freeze purposes — it MUST NOT consume a freeze. **Verify:** `test/contracts/streak_currentstreak_is_pure_test.dart`.
- **`TRAIN-45`** — The server `evaluate-rank-promotions` cron mirrors the same sequential + monotonic logic as the client (`_shared/rank_engine.ts` in lockstep with `rank_ladder_data.dart`). **Verify:** needs test (server/client ladder parity) + Edge Function deploy smoke.
- **`TRAIN-46`** — "Days to next rank" (`daysUntilNextRank`) is always non-negative (clamped `[0,365]`) and shares one value between the chip header and the profile RANK card. **Verify:** `test/profile/rank_card_eta_test.dart`.

---

## 4. NUTRITION (`NUT-`)

- **`NUT-01`** — The nutrition screen shows daily targets (calories + protein) computed from the profile via the canonical `BmrCalculator`. **Verify:** needs test (widget); BMR covered by `test/bmr_calculator_test.dart`.
- **`NUT-02`** — BMR is hybrid: Katch-McArdle (`370 + 21.6 × lean_mass_kg`) when body-fat % is available, else Mifflin-St Jeor; both apply −50 BMR and −100 TDEE offsets; activity level derives from lifestyle + training days. **Verify:** `test/bmr_calculator_test.dart` `(unverified — confirm path)`.
- **`NUT-03`** — The MY TARGETS projection reads `current_weight_kg`, `target_weight_kg`, `pace_preference` and shows only for `lose_fat`/`build_muscle` goals with a non-zero gap. **Verify:** `test/contracts/nutrition_screen_layout_test.dart`.
- **`NUT-04`** — Log Food is a 2-tab surface: AI text analysis ("2 chapatis and dal") + Scan meal (camera). **Verify:** `test/contracts/log_food_sheet_test.dart`.
- **`NUT-05`** — WHEN AI text analysis runs THEN `food_logger_section._analyse` calls `food-text-analysis` Edge Function; the daily counter increments at the API-call site (NOT at save). Server caps 50/day free, 200/day PRO. **Verify:** `test/contracts/food_text_analysis_daily_cap_test.dart`.
- **`NUT-06`** — WHEN a meal is logged THEN `total_calories` is summed from `items[]` with per-item Atwater fallback (`raw > 0 ? raw : 4P+4C+9F`); never read top-level `result['total_calories']`. **Verify:** `test/contracts/nutrition_total_calories_writer_to_reader_test.dart`, `test/contracts/food_log_notifier_to_nutrition_log_items_test.dart`.
- **`NUT-07`** — `NutritionWriteService.logMeal` is the single writer of `nlog_${istDateStr}_${hash}` rows; it invalidates the nutrition providers and fires `syncNutritionData()` + `pushSnapshot()`. **Verify:** `test/contracts/nutrition_write_to_read_contract_test.dart`, `test/contracts/food_log_id_and_name_test.dart`.
- **`NUT-08`** — Scan meal: client cap 3/day free, 10/day PRO (soft warning at 7/10); server abuse cap 15/day; results are fully editable via `_ScanResultEditor` (meal name, per-item name/kcal/P/C/F/Fi, +Add/X Delete) with totals recomputing on every keystroke. **Verify:** needs test (widget); caps via `business-rules.md`.
- **`NUT-09`** — Cart Auditor: client cap 1/day free, 10/day PRO; counts via `cart_auditor_section.analyseCart` at the API-call site. **Verify:** needs test.
- **`NUT-10`** — Food search reads the ~1.4K-row Hive `food_database` box, does per-serving math, and saves to a meal slot. **Verify:** `test/contracts/your_foods_section_test.dart`, `test/contracts/log_food_sheet_test.dart`.
- **`NUT-11`** — WHEN a custom food is added THEN it syncs to Supabase immediately (community contribution). **Verify:** `test/contracts/sync_fanout_contract_test.dart`.
- **`NUT-12`** — WHEN any AI/save action mutates data THEN the user gets an explicit confirmation signal (snackbar "Meal saved ✓" + haptic), and a `_saving` guard prevents double-tap. **Verify:** needs test (widget) — pattern from Test #11 L1.
- **`NUT-13`** — Saved meals: `NutritionWriteService.saveMeal` is the writer; quick-log reads from `saved_meals_section`. **Verify:** `test/contracts/saved_meals_writer_to_reader_test.dart`.
- **`NUT-14`** — WHEN a food log is deleted THEN `deleteWithUndo` soft-deletes with a 5s timer + restore-on-tap. **Verify:** `test/contracts/food_log_delete_with_undo_writer_to_reader_test.dart`.
- **`NUT-15`** — Water tracking renders a `WardGlassGrid` 8-cell tracker; `HealthWriteService.logWater` is the writer with `onConflict: 'user_id,date'` (one row per user per day). **Verify:** `test/contracts/water_logs_writer_to_reader_test.dart`.
- **`NUT-16`** — The water target is read ONLY via `WaterTargetService.currentTargetMl()`: override → computed (`weight×35 + 500 if 4+ training days + 300 if active`, clamped 2500–4000) → 2500 floor; never hardcode 3000. Widgets `ref.watch(waterTargetProvider)` to rebuild on override change. **Verify:** `test/contracts/water_target_writer_to_reader_test.dart`.
- **`NUT-17`** — The diet plan generator is local (no AI): preview + swap + save to device + share as PDF; FREE users can save & reload. **Verify:** `test/contracts/diet_plan_saved_loaded_writer_to_reader_test.dart`.
- **`NUT-18`** — Generated diet-plan protein lands in the [95%, 115%] band of target across all archetypes (anchor cap + filler exclusion + surplus trim). **Verify:** `test/contracts/diet_plan` (protein-band assertions) `(unverified — confirm exact path)`.
- **`NUT-19`** — WHEN a plan is saved THEN `diet_plan_screen._savePlan` writes `configBox['saved_diet_plan']`, invalidates `dietPlanProvider`, and syncs via `syncSavedDietPlan`; `TodaysMealsCard` then renders "FROM YOUR DIET PLAN" hints on empty slots with tap-to-log pre-fill (`initialQuery`). **Verify:** `test/contracts/diet_plan_saved_loaded_writer_to_reader_test.dart`.

---

## 5. AI COACH (`COACH-`)

- **`COACH-01`** — All chat goes through ONE server endpoint `ai-proxy` → Gemini 2.5 Flash; there is no client-side model routing. FREE: `FREE_DAILY_LIMIT = 10` msg/UTC-day, no trial window (OQ-1). PRO: unlimited. Gate is server-side. **Verify:** `test/contracts/ai_proxy_*` + Edge Function smoke.
- **`COACH-02`** — WHEN a chat turn is sent THEN `ai_coach_repository.appendInteraction` writes the interaction to Hive + syncs `coach_interactions`; the renderer reads from Hive. **Verify:** `test/contracts/coach_interactions_writer_to_reader_test.dart`, `test/contracts/coach_replies_test.dart`.
- **`COACH-03`** — Chat dedup is 3-layered: 60s client-side dedup ring + `ai-proxy` placeholder dedup + a 3-strike circuit breaker; none may be disabled. **Verify:** `test/contracts/ai_proxy_placeholder_resolution_test.dart`, `test/contracts/sync_coach_cross_channel_dedup_test.dart`.
- **`COACH-04`** — The snapshot is built by the single builder `ai_snapshot_builder.buildAiContext` (recent logs + today's targets + plan day + coach-memory excerpt + PRs + today_workout); `AiService._compactContext` is the single trimmer targeting <9,500 bytes. **Verify:** `test/contracts/ai_snapshot_building_writer_to_reader_test.dart`, `test/contracts/ai_snapshot_builder_only_test.dart`.
- **`COACH-05`** — WHEN the model emits a `tool_call` THEN `tool_dispatcher.dart` validates the name against the allowlist, calls the canonical WriteService (never raw Hive), fires `unawaited(syncDomain())`, and returns a structured `ToolResult`. **Verify:** `test/contracts/conversational_log_handler_uses_write_service_test.dart`, `test/contracts/write_service_bypass_detector_test.dart`.
- **`COACH-06`** — **Derive-only tool surface (2026-05-31):** the AI logs RAW input only; the app COMPUTES derived state. There is NO `logPR` tool (PRs derive from `logSet`'s auto-rescan → `loadAllExercisePRs`), NO `markWorkoutComplete` tool (completion derives — a coach `logSet` on a scheduled day calls the canonical `markCompleted`), NO `adjustCaloricTarget` tool (calorie target stays derived), and NO `prelog` tool (no future-meal pre-logging). **Verify:** `test/contracts/derive_only_tool_surface_test.dart`, `test/contracts/coach_derived_pr_and_completion_test.dart`. ADR: derive-only tool-surface integrity.
- **`COACH-07`** — `logMealByText` tool increments the AI-text counter at the API-call site like the UI path. **Verify:** `test/contracts/food_text_analysis_daily_cap_test.dart`.
- **`COACH-08`** — 20 tools exist across 5 families (down from 24 after the 2026-05-31 derive-only prune of `logPR`/`adjustCaloricTarget`/`prelog`/`markWorkoutComplete`); tier filtering shows FREE users 9 tools and PRO all 20. WRITE tools emit a typed `ToolIntent` confirmed client-side (trivial 5s auto-confirm / reviewable inline card / destructive bottom-sheet diff); READ tools execute server-side in the same turn. Intents carry a 1-hour TTL + concurrent-edit guard. **Verify:** `test/contracts/derive_only_tool_surface_test.dart` (registry tier count + removal); intent TTL needs test.
- **`COACH-09`** — WHEN a chat turn is processed THEN the message is embedded and `match_memories(user_id, embedding, 5, 0.65)` injects top-5 semantically similar memories; on 0 matches / timeout (3s) / error it falls back to the full `coaching_notes` dump (zero regression). **Verify:** needs test (memory retrieval fallback paths).
- **`COACH-10`** — `coach_memory.coach_notes` (cloud, singular word, DIFFERENT from Hive's `coaching_notes`) is populated by `SyncService.syncCoachMemoryNow` projecting Hive `coachBox['coaching_notes']`; this preserves AI memory across reinstall. **Verify:** `test/contracts/coach_notes_upward_sync_test.dart`, `test/contracts/coaching_notes_writer_to_reader_test.dart`.
- **`COACH-11`** — coaching_notes are extracted daily at 11PM IST (batch, not per-message) from that day's conversations. **Verify:** needs test (cron) + `daily-snapshot` smoke.
- **`COACH-12`** — Photo/video upload is PRO-only via `ai-media-proxy` (`verify_jwt: true` + manual JWT + PRO check); it is SSRF-allowlisted to `${SUPABASE_URL}/storage/v1/object/` (`progress-photos` + `chat-attachments` buckets only); image max 5MB. **Verify:** `test/contracts/chat_media_signed_url_test.dart`, `test/contracts/ai_media_proxy_status_code_classification_test.dart`, `test/contracts/ai_media_proxy_telemetry_test.dart`, `test/contracts/edge_function_safety_test.dart`.
- **`COACH-13`** — `ai-media-proxy` classifies failures into 400 (user input) / 502 (upstream) / 500 (server) and the chat bubble renders a distinct "photo-failed" state. **Verify:** `test/contracts/ai_media_proxy_status_code_classification_test.dart`.
- **`COACH-14`** — Server errors map to actionable user copy (`Message too long` → "shorten it", `Snapshot too large` → "shorter question", `Image too large` → "max 5 MB", `502/503/504` → "temporarily unavailable"); the copy "restart the app" is NEVER used. **Verify:** `test/contracts/coach_replies_test.dart`; needs explicit error-mapping test.
- **`COACH-15`** — Voice (mic) input is FREE: on-device transcription via `speech_to_text` with `pauseFor:5s`, `listenFor:60s`, dictation mode, partial results. **Verify:** needs test.
- **`COACH-16`** — Quick-prompt chips are available; the reasoning tab is PRO-only. **Verify:** needs test (widget).
- **`COACH-17`** — A Telegram toggle exists; the Telegram bot is a separate project (free 30 days). **Verify:** needs test.
- **`COACH-18`** — Server-side input limits are enforced on all AI endpoints: message ≤ 5,000 chars, snapshot ≤ 10,000 chars. **Verify:** `test/contracts/edge_function_safety_test.dart`.
- **`COACH-19`** — 8 proactive cron triggers (Morning Brief, Workout Window Closing, Protein Gap [PRO], Streak Guardian, PR Detection, Plateau [PRO], Weekly Recap, Re-engagement) each dedup once per IST day via `_shared/proactive_dedup.ts`. **Verify:** needs test (cron dedup) + `cron.job_run_details` audit.

---

## 6. PROFILE (`PROF-`)

- **`PROF-01`** — The Profile tab shows: rank pill (top) + bio stats + goal card + nutrition targets + ladder + entries for Edit / Progress photos / Reports / Submissions / Subscription / Referrals / Settings / Logout. **Verify:** needs test (widget).
- **`PROF-02`** — Every Profile screen reads profile fields via `userProfileProvider` (never raw Hive). **Verify:** `test/lints/`.
- **`PROF-03`** — Edit Profile is the full editor for all user_profile fields; WHEN saved THEN `ProfileWriteService` writes `userBox['profile']`, fires `syncOnboarding()`, and invalidates `userProfileProvider`/`homeProvider`/`dietPlanProvider` (on goal/weight change)/`nutritionTargetsProvider`. **Verify:** `test/contracts/user_full_name_writer_to_reader_test.dart`; needs explicit invalidation test.
- **`PROF-04`** — The `usageWeeks` counter reads `users.created_at` from Supabase, NOT a Hive key. **Verify:** `test/contracts/usage_weeks_signup_date_test.dart`.
- **`PROF-05`** — Health sync (Google Fit / Health Connect / Samsung Health) imports steps + sleep; the toggle lives in Settings. **Verify:** needs test (integration).
- **`PROF-06`** — Weight edits route through `HealthWriteService`; the weekly report weight series is forward-filled (no zero-dips between weigh-ins). **Verify:** `test/contracts/weight_logs_writer_to_reader_test.dart`, `test/contracts/weekly_report_data_writer_to_reader_test.dart`.
- **`PROF-07`** — The Weekly AI Report is PRO (`gemini-2.5-pro`); FREE users get the first report only (after Week 1), then it is gated. Sparklines: calories/protein/workouts zero-fill (genuine no-activity), weight forward-fills. **Verify:** `test/contracts/weekly_report_data_writer_to_reader_test.dart`.
- **`PROF-08`** — The service record / rank-ladder screen shows the 11-rung lifetime ladder with `WardRankInsignia`; earned rungs (`ordinal ≤ current`) render filled, unearned show human-readable gate text. **Verify:** `test/profile/rank_ladder_gate_text_test.dart`, `test/wardroom/ward_rank_insignia_test.dart`, `test/wardroom/ward_rank_pill_test.dart`.
- **`PROF-09`** — Progress photos are PRO-gated with a server-verified gate (`progress_photos` ∈ high-value set); `ProgressPhotoRepository.capture` enforces the daily cap BEFORE pick (2/day free, 5/day PRO) and uploads to the user-scoped `progress_photos` Storage bucket; quality tier-gated 2048/85 free, 3000/95 PRO; `PhotoQuotaException` surfaces a paywall (free) or "come back tomorrow" (PRO). **Verify:** `test/contracts/progress_photo_quota_test.dart`.
- **`PROF-10`** — Subscription is ₹349/month or ₹2,999/year; the PaywallSheet is the ONLY paywall UI; `subscription.gate()` is the ONLY entry point for PRO features. **Verify:** `test/subscription/high_value_features_test.dart`, `test/contracts/subscription_state_writer_to_reader_test.dart`.
- **`PROF-11`** — `isPro()` reads Hive `configBox` {isPro, expiresAt, plan}, checks local expiry, refreshes from Supabase on launch; null expiry grants PRO only in `kDebugMode` (release = free); expired+offline downgrades immediately (no grace period) to a soft-lock keeping data. **Verify:** `test/contracts/subscription_payment_grace_window_writer_to_reader_test.dart`.
- **`PROF-12`** — High-value features (`phases_2_to_12`, `ai_coach_unlimited`, `progress_photos`) call `verifyFromServer()` (5-min TTL cache) in `gate()`; other features use the local check only. `active_workout_mode` is NOT gated (always free). **Verify:** `test/subscription/high_value_features_test.dart`.
- **`PROF-13`** — Clients never write the `subscriptions` table directly — entitlement flows server-side from Razorpay webhook → Supabase → poll → Hive. **Verify:** `test/contracts/no_client_subscriptions_writes_test.dart`, `test/contracts/razorpay_409_already_pro_test.dart`.
- **`PROF-14`** — WHEN a referral is applied THEN `apply_referral_sheet` → `redeem-referral`/`validate-referral` Edge Function grants 7-day PRO read by `isPro()`. **Verify:** needs test (referral grant) + Edge Function smoke.
- **`PROF-15`** — WHEN the user signs out THEN the Hive session swaps owners and the cross-account guard prevents stale-owner reads (`logout_in_progress` stays in shared `configBox`). **Verify:** `test/contracts/auth_hive_owner_agreement_behavioral_test.dart`.
- **`PROF-16`** — WHEN the user deletes their account THEN `delete_account_screen` → `delete-account` Edge Function performs the DPDP §17 hard-delete + pseudonymization; FK columns are `ON DELETE SET NULL` so community signal survives, and read consumers tolerate `user_id = NULL`. **Verify:** `test/contracts/delete_account_safety_contract_test.dart`.
- **`PROF-17`** — Shareable cards (workout receipt, future prediction, beat-my-coach) are all FREE and embed the ICANBEFITTER wordmark + QR → icanbefitter.com. **Verify:** needs test (share-card content).
- **`PROF-18`** — Notifications inbox is written via `NotificationInboxService.record` and synced via `syncNotificationsInboxEntry`; theme is locked dark. **Verify:** needs test (inbox sync).

---

## 7. CROSS-CUTTING (`XC-`)

- **`XC-01`** — All reads/writes hit Hive first; the UI NEVER blocks on a Supabase response; Supabase writes are background/`unawaited`. **Verify:** `test/contracts/sync_fanout_contract_test.dart`, `test/lints/`.
- **`XC-02`** — Every PRO feature is gated through `subscription.gate()`; no inline `isPro` checks in widgets; Phase 1 is never gated. **Verify:** `scripts/check_subscription_gate.dart`, `test/subscription/high_value_features_test.dart`.
- **`XC-03`** — `SyncService.syncWorkoutData()` fans out to every workout-domain prefix (`_syncWorkoutLogs/_syncExerciseLogs/_syncScheduleCompletions/_syncWorkoutTemplates/_syncScheduledWorkouts/_syncStreaks`) and `syncNutritionData()` to every nutrition prefix (`_syncNutritionLogs/_syncWaterLogs/_syncSavedMeals`); adding a prefix updates the matching method + contract test. **Verify:** `test/contracts/sync_fanout_contract_test.dart`.
- **`XC-04`** — Restore completeness: every Hive-only surface a paying user would lose on reinstall has a cloud table + `syncX()` + `_restoreX()` called from `restoreFromCloudForUser` + a contract test. Restore pulls freezes, notifications inbox, saved diet plan, rank_promotions (last 20), coach_memory/coaching_notes, and folds `verifyFromServer(force:true)` last. **Verify:** `test/contracts/restore_completeness_test.dart`, `test/contracts/restore_template_schedule_test.dart`, `test/contracts/restore_non_destructive_test.dart`.
- **`XC-05`** — Restore reads paginate at 1,000 rows/page with a 50,000-row safety ceiling; no hardcoded `.limit(5000)` (full history for all users). **Verify:** `test/contracts/restore_non_destructive_test.dart`; needs explicit pagination assertion.
- **`XC-06`** — Sync dedup uses natural keys: streaks `user_id,week_start`; water `user_id,date`; scheduled workouts `user_id,scheduled_date`; workout logs/exercises by deterministic UUID. Never dedup by cloud `id` alone. **Verify:** `test/contracts/sync_onconflict_natural_key_test.dart`, `test/contracts/sync_natural_key_guard_test.dart`.
- **`XC-07`** — All date keys, cloud `date` columns, and counter resets use IST (UTC+5:30) via `istDateStr` / `_shared/ist_date.ts`; no `DateTime.now().toIso8601String()` substring for keys. **Verify:** `test/contracts/ist_sweep_no_utc_substring_test.dart`, `test/contracts/format_date_key_ist_test.dart`.
- **`XC-08`** — Every catch block records a non-fatal via `ErrorTelemetry.recordNonFatal` with a canonical `op_type`; fire-and-forget failures never bubble to the UI but always reach telemetry; no silent `debugPrint`-only swallows in services. **Verify:** `test/contracts/error_telemetry_helper_writer_to_reader_test.dart`, `test/contracts/error_telemetry_payload_contract_test.dart`, `test/contracts/no_silent_debugprint_in_services_test.dart`, `test/contracts/log_client_error_payload_writer_to_reader_test.dart`.
- **`XC-09`** — Every WriteService method returns a `WriteResult` so callers distinguish "Hive succeeded" from "cloud succeeded". **Verify:** `test/contracts/write_service_bypass_detector_test.dart`.
- **`XC-10`** — Release error handling is `kDebugMode`-guarded: detailed errors in debug, generic message in release; Edge Functions never leak raw exceptions/stack traces (8-hex request_id returned + logged). **Verify:** `test/contracts/edge_function_safety_test.dart`, `test/contracts/error_widget_records_test.dart`.
- **`XC-11`** — Lifetime/monotonic fields (rank, lifetime workout count, longest streak, peak weight, `deployments_complete`, badge unlock) have an only-increment writer guard; recompute-from-current-state writers must not silently demote. **Verify:** `test/contracts/rank_no_demotion_behavioral_test.dart`.
- **`XC-12`** — All screens handle loading (skeleton), error (retry), and empty states. **Verify:** needs test (per-screen widget).
- **`XC-13`** — `plan_generator.dart` is never modified without explicit instruction; it calls no API and queries only Hive `exerciseBox`. **Verify:** `test/contracts/plan_generator_inputs_test.dart`; `scripts/` gate.
- **`XC-14`** — The SoT registry (`docs/sot_registry.yaml`) is complete: every registered concept has a writer/reader and a behavioral test path. **Verify:** `test/contracts/sot_registry_completeness_test.dart`.

---

## Coverage gaps / needs-test

The following assertions have no obvious existing test and should get one (or be confirmed against code where marked `(unverified — confirm)`):

- **Auth/Onboarding:** `AUTH-02`, `AUTH-03`, `AUTH-04` (unverified — Twilio prod), `AUTH-07` (widget), `AUTH-12`, `AUTH-13` (assert `since` constant), `AUTH-18`, `ONB-01`, `ONB-02`, `ONB-03`, `ONB-04`, `ONB-06`, `ONB-07`, `ONB-10`, `ONB-11` (scheduling), `ONB-14`.
- **Home:** `HOME-01`, `HOME-14`, `HOME-16` (forward-fill), `HOME-17`, `HOME-18`, `HOME-19`, `HOME-21` (PlanExpiredCard widget), `HOME-22`.
- **Train:** `TRAIN-01`, `TRAIN-03`, `TRAIN-04` (confirm path), `TRAIN-05`, `TRAIN-16`/`TRAIN-18`/`TRAIN-25` (confirm paths), `TRAIN-23` (post-12 cycles), `TRAIN-24` (deployments derivation), `TRAIN-26` (unverified — phase-2 personalization), `TRAIN-41` (completionRate denominator), `TRAIN-45` (server/client ladder parity).
- **Nutrition:** `NUT-01`, `NUT-02` (confirm path), `NUT-08`, `NUT-09`, `NUT-12`, `NUT-18` (confirm protein-band path).
- **Coach:** `COACH-08` (tier count + intent TTL), `COACH-09` (retrieval fallback), `COACH-11` (cron), `COACH-14` (error mapping), `COACH-15`, `COACH-16`, `COACH-17`, `COACH-19` (cron dedup).
- **Profile:** `PROF-01`, `PROF-03` (invalidation set), `PROF-05`, `PROF-14`, `PROF-17`, `PROF-18`.
- **Cross-cutting:** `XC-05` (pagination assertion), `XC-12` (per-screen loading/error/empty).
