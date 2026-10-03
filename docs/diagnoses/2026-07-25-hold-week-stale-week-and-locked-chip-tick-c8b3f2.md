---
bug_id: c8b3f2
date: 2026-07-25
batch: hold-display-fixes
blast_radius: account
status: fixed
symptom: >
  Two defects in the free-tier "Hold the Line" DISPLAY, both found by a LIVE
  walkthrough on test7 (flag flipped ON via the /dev Flags card, time-travelled to
  the day-29 wall, three holds taken) — the automated suite was green throughout
  and surfaced neither. (D1) The Train deployment banner
  (screens/train/screen.dart:225-226) rendered
  "DEPLOYMENT 01 · FOUNDATION · WK 4 OF 4" roughly 40px BELOW the "HOLDING · Hn"
  pill, in the same scroll view — two contradictory week statements on one screen.
  getCurrentWeekNumber() clamps to 1..4 and a hold always starts at plan_start+28
  or later, so it printed "WK 4 OF 4" for every hold at every ordinal, forever.
  (L1) completedWeekNumbers() (workout_schedule_read_service.dart:892-908 pure
  helper) maps date→week by walking plan_start + 7k with NO is_hold filter, so a
  COMPLETED hold day injected a phase-II/III week number into the returned set and
  credited a ✓ to a padlocked chip for a week never trained. It is invisible today
  only because _WeekChip suppresses the tick when isLocked and a holder is by
  definition free — and week_selector watches subscriptionInfoProvider, so the chip
  unlocks the INSTANT the holder upgrades, BEFORE any phase advance moves
  plan_start. In that window the ✓ shows and the now-unlocked chip is tappable
  straight into "Week 5 hasn't started yet".
concept: hold_display_read_path
sot_registry_entry: hold_display_read_path
writers:
  - { file: lib/core/services/workout_schedule_write_service.dart, line: 287, source: "holdWeek() — the ONLY writer of is_hold / hold_ordinal; places the hold in the calendar week containing TODAY via normalizeToMonday(nowWall()) at :248, so holds are NOT on the plan_start + 7k grid" }
  - { file: lib/core/services/workout_write_service.dart, line: 441, source: "markCompleted — merges the schedule row IN PLACE (status/completed_at_ms/completed_via), so is_hold + hold_ordinal survive completion; now pinned by the L3 test" }
readers:
  - { file: lib/features/train/screens/train/screen.dart, line: 225, source: "D1 FIX — deployment banner now ternaries on holdStatus.isHolding; the holding arm drops the WK n OF 4 segment, the non-holding arm is byte-identical" }
  - { file: lib/core/services/workout_schedule_read_service.dart, line: 896, source: "L1 FIX — completedWeekNumbers() predicate now returns false for rows with is_hold == true" }
  - { file: lib/features/train/widgets/week_selector.dart, line: 122, source: "the ONLY production caller of completedWeekNumbers(); feeds _PhaseGroup → _WeekChip hasCompletedDay" }
  - { file: lib/core/services/workout_schedule_read_service.dart, line: 845, source: "HoldWeekInfo.isCompleted — computes the H-chip ✓ INDEPENDENTLY via _holdDatesByOrdinal/getScheduleForDate, so the L1 exclusion costs hold chips nothing" }
hive_key_prefix: schedule_
hive_key_formula: "'schedule_' + formatDateKey(date)"
sync_methods: [syncWorkoutData, _syncScheduledWorkouts, _syncWorkoutPlan (via pushWorkoutPlanForSyncDomain)]
restore_methods: [_restoreScheduledWorkouts, _restoreWorkoutPlan]
cloud_table: scheduled_workouts + user_progress.plan_json
cloud_columns: [user_id, scheduled_date, week_number, day_of_week, status, completed_at]
contract_test_path: test/contracts/hold_display_read_path_test.dart
ist_handling:
  - { file: lib/core/services/workout_schedule_read_service.dart, line: 1423, fn: "_dateKey → formatDateKey (istDateStr) — the L1 predicate resolves rows through getScheduleForDate, which is IST-date-keyed" }
  - { file: lib/core/utils/ist_date.dart, line: 65, fn: "nowWall — seam-aware today; holdWeek's Monday normalization reads it, which is why the live walkthrough could time-travel" }
provider_invalidations: [currentPlanProvider, selectedWeekProvider, holdStatusProvider]
telemetry_op_types:
  success: [sync_scheduled_workouts]
  failure: [train_screen_build_failed]
cross_account_guard: >
  Unchanged. Both fixes are pure READ-path changes — no new Hive write, no new box
  access. completedWeekNumbers routes through getScheduleForDate → HiveService
  workoutBox (wrapUserScopedBox), and holdStatusProvider already watches
  authUserIdTokenProvider transitively via currentPlanProvider. No new
  cross-account surface introduced.
forbidden_patterns_checked: >
  No raw Hive.box( added. No inline isPro check added (the L1 masking analysis
  READS week_selector's existing isPaywalled/!isLocked logic but does not change
  it). No setState for shared state. The D1 non-holding ternary arm preserves the
  literal 'WK ${plan.currentWeek} OF 4' that
  test/contracts/phase_relative_week_label_test.dart greps for after stripping
  comments — verified green. Verified the L1 exclusion is INERT when
  enable_hold_weeks is OFF: is_hold has exactly one writer (holdWeek), whose only
  call sites are flag-gated (keep_training_phase1_action.dart:31-34,
  plan_expired_card), and the OFF path routes to redoWeek4() which never stamps it.
proposed_fix: >
  D1 — branch the banner on holdStatus.isHolding (already in scope at
  screen.dart:111); the holding arm renders the phase name WITHOUT a week counter,
  applying the rule plan_header.dart already established ("a hold week has no
  honest WK n OF m — it sits OUTSIDE the phase's m weeks"), so the HOLDING · Hn
  pill is the sole week identity during a hold. L1 — exclude rows with
  is_hold == true from the completedWeekNumbers() completed-day predicate, leaving
  the pure completedWeekNumbersFrom helper untouched and still testable. Hold weeks
  keep their own ✓ through HoldWeekInfo.isCompleted.
regression_test_planned: >
  test/contracts/hold_display_read_path_test.dart — 7 new cases across 3 groups.
  L1 is PARAMETERIZED OVER THE HOLD START DATE at reviewer mandate, because the
  pre-fix bug was intermittent rather than deterministic: CONTIGUOUS (plan_end+1 →
  would have injected week 5), LATE RETURN (a user who lapses and returns 3 weeks
  later → ordinal 1 lands on DATE-week 8, proving ordinal is a label not a date
  offset), and a CHARACTERIZATION case beyond maxWeek:12 (explicitly labelled — the
  B-pass reverted the fix and proved it passes either way, so it documents why the
  bug was intermittent rather than guarding a regression). Plus a non-hold
  regression case proving ordinary week completions still tick, an L3 case driving
  the REAL WorkoutWriteService.markCompleted on a hold row to pin that
  is_hold/hold_ordinal survive completion, and two D1 comment-stripped source-greps
  pinning both ternary arms.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze clean on both touched files; 20 tests in hold_display_read_path_test.dart + 40 across the pinned neighbours (phase_relative_week_label, week_selector_past_phases, week_completion_check, hold_week_mechanic_behavioral, phase_unlock_card_thursday_gate) all green" }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "L1 predicate reads is_hold off schedule_<date> rows; L3 test drives the real markCompleted and asserts is_hold/hold_ordinal survive in Hive" }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "read-path-only change; no schema touched. is_hold/hold_ordinal are deliberately Hive+plan_json only — the scheduled_workouts push hand-picks its column set" }
  - { tier: 4, name: postgres_data, status: verified, evidence: "live query on test7 during the walkthrough confirmed the three holds synced as week_number 5/6/7 with 4 planned + 3 rest days each, and plan_json carried is_hold/hold_ordinal/7 exercises with plan_end extended to 2026-08-23" }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "no migration in this batch" }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function touched; grep over supabase/functions for is_hold/hold_ordinal returns 0 hits" }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "no cron reads either field or completedWeekNumbers" }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "no policy change; no new table access" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no storage surface touched" }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "secrets_in_tree lens returned 0 matches over the staged diff" }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "no Razorpay/OneSignal/Firebase surface touched" }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "full flow walked live on test7: tap Hold → holdWeek writes → UI renders → sync pushes → verified in Postgres. Both fixes are client-read-only, so the contract is unchanged" }
impact_analysis: >
  User-visible impact is currently ZERO because enable_hold_weeks is default OFF —
  no user can be in a hold week, so neither defect can fire in production today.
  Both are flip-on-blocking correctness bugs. D1 would have shipped a screen that
  contradicts itself to every holder on every visit. L1 is the more dangerous of
  the two despite being invisible: it is latent-until-conversion, and the cohort it
  fires on is exactly the commercially important one — a free user who held, then
  upgraded. At that moment the padlocked chip unlocks, a ✓ appears on a PHASE II/III
  week they never trained, and tapping it lands on "Week 5 hasn't started yet",
  which reads as the app losing their data at the precise moment they paid. Neither
  fix widens blast radius: both key on hold state, and is_hold cannot exist on a
  flag-OFF install (single writer, flag-gated call sites, OFF path routes to
  redoWeek4). Scope note — four FURTHER fixes proposed alongside these were
  returned NOT CONVERGED by two independent context-blind plan reviews (4 P0s,
  including that my streak fix was built on `4 + ordinal` as if holds sat on the
  plan_start + 7k grid, which would have silently written no streak row at all for
  a lapsed returning user). Per §4.12.1 the unit was split; those are recorded as
  hard flip-on preconditions FOB-1..FOB-7 in docs/ship_dark_pending_review.yaml,
  which the flip-on's own ×2 review must show closed.
---

# Hold weeks printed a stale week number and ticked a locked chip (c8b3f2)

## How these were found

Neither came from a test. Both came from **running the app**: a live walkthrough on
`test7` on 2026-07-25 with `enable_hold_weeks` flipped ON through the new `/dev` Flags
card, time-travelled forward to the day-29 wall, three holds taken (H1/H2/H3), and the
resulting state verified in Postgres.

D1 was visible to the eye — the screenshot shows `HOLDING · H1` and `WK 4 OF 4` in the
same frame. L1 came out of the ground-truth investigation that walkthrough triggered:
"does logging inside a hold week save, sync, and tick correctly?" The answer was mostly
yes — and one no.

## Why L1 was invisible

`completedWeekNumbersFrom` walks `w = 1..12`, computing `weekStart = plan_start + (w-1)*7`
and asking "was any day that week completed?". A hold week is not on that grid:
`holdWeek()` uses `normalizeToMonday(nowWall())`, so it occupies the calendar week
containing *today*. A completed hold day therefore lands on whatever week index its date
happens to hit.

The only thing hiding it is `week_selector.dart`'s tick guard,
`hasCompletedDay && !isLocked`, plus the fact that a holder is always free so PHASE II/III
chips are locked. `week_selector` watches `subscriptionInfoProvider` — so on upgrade the
chip unlocks immediately, well before any phase advance moves `plan_start`. The guard was
never a fix; it was a coincidence.

## The two-`getWeek` trap (recorded because it nearly caused a P0)

While planning the wider batch I asserted "`getWeek(5)` returns empty". That is true of
`CurrentPlanData.getWeek` (`train_provider.dart:436` — indexes `weeks`, capped at 4 for
phase 1) and **false** of `WorkoutScheduleReadService.getWeek`
(`workout_schedule_read_service.dart:911` — date-based and unbounded).
`WorkoutRepository.getWeek` delegates to the read-service one. A proposed streak fix built
on that conflation, plus `4 + ordinal` treated as a date offset, would have read
unmaterialized dates and silently produced no streak increment and no `streaks` row for a
lapsed returning user — while passing under time travel. Caught by independent review, not
by me. See `memory/feedback_mistake_hold_ordinal_is_a_label_not_a_date_offset.md`.

## Verification

- `test/contracts/hold_display_read_path_test.dart` — 20 tests green.
- Pinned neighbours untouched and green (40 tests).
- `flutter analyze` — no new issues.
- Live: prod `scheduled_workouts` for test7 shows `week_number` 5/6/7; `plan_json` carries
  `is_hold: true`, `hold_ordinal: 3`, 7 exercises; `plan_end` extended to 2026-08-23.

## Related

Slice 1 mechanic: `docs/diagnoses/2026-07-21-free-tier-hold-mechanic-d7f3a9.md`.
Reviews: `docs/plan-reviews/hold-display-fixes.md`, `docs/reviews/hold-display-fixes-bpass.md`.
Closure: `docs/audit/hold-display-fixes.closure.yaml`.
Flip-on gate: `docs/ship_dark_pending_review.yaml` (FOB-1..FOB-7).
