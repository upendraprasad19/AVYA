---
bug_id: b6e1c3
date: 2026-06-09
batch: apk34-obs-2026-06-09
status: fixed
blast_radius: feature
symptom: >
  APK +34 obs 1/6 — the Train week strip highlighted a wrong/last week as TODAY
  (image 1: Phase II W1 marked current while W2-W6 showed completed ticks; image
  4: Phase IV W12 highlighted as TODAY with "No workouts scheduled"). Unlike
  Home, the Train screen had NO plan-expired state, so it always rendered a
  "current" week + a hero/empty card even when the phase had run out.
concept: plan_phase_expiry
sot_registry_entry: plan_phase_expiry
writers: >
  not_applicable (UI reader change). Depends on isPhaseExpired() (BUG-A a1d4f9),
  which now honors the materialized schedule rather than a stale plan_json
  plan_end_date.
readers: >
  lib/features/train/screens/train/screen.dart _buildContent — the hero slot now
  renders PlanExpiredCard (already used by Home, lives in train/widgets/) when
  isPhaseExpired() is true and the user is viewing the current week, instead of
  _buildTodayHeroCard. Past-week browsing (selectedWeek != currentWeek) is
  unchanged. onRedoComplete invalidates currentPlanProvider + selectedWeekProvider.
hive_key_prefix: schedule_
hive_key_formula: schedule_${istDateStr(date)}
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: user_progress
cloud_columns: plan_json
contract_test_path: test/contracts/train_expired_state_test.dart
ist_handling: not_applicable (delegates to isPhaseExpired which is seam/IST aware)
provider_invalidations:
  - currentPlanProvider
  - selectedWeekProvider
telemetry_op_types: not_applicable
cross_account_guard: not_applicable
forbidden_patterns_checked:
  - "The Train screen must gate the current-week hero slot on isPhaseExpired() and surface PlanExpiredCard when expired (not always a hero/empty card). Pinned by test/contracts/train_expired_state_test.dart."
proposed_fix: >
  In train screen _buildContent, when viewing the current week, render
  PlanExpiredCard if WorkoutScheduleService.instance.isPhaseExpired() else the
  today hero card. Import PlanExpiredCard. The expiry decision is now correct
  (BUG-A) so this no longer false-fires while future workouts are scheduled.
regression_test_planned: >
  test/contracts/train_expired_state_test.dart — comment-stripped source-grep:
  train screen references isPhaseExpired AND PlanExpiredCard (neither present on
  main). The decision semantic is pinned by plan_expiry_respects_schedule_test.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "train screen hero slot gated on isPhaseExpired -> PlanExpiredCard; PlanExpiredCard imported; dart analyze clean on the train screen library; train_expired_state_test green" }
impact_analysis: >
  Feature blast radius — the Train tab's plan-expired UX. Reuses Home's
  PlanExpiredCard so the recovery path (generate next phase / redo) is consistent
  across tabs. Pairs with BUG-A (correct isPhaseExpired) so the card only appears
  when the plan has genuinely run out, not while scheduled_workouts still extends
  into the future. No new widget, schema, or auth surface.
---

# Train screen had no plan-expired state (highlighted a bogus current week)

## What happened
APK +34 obs 1/6: the Train week strip highlighted a wrong/last week as TODAY
with no workouts, contradicting the completed-week ticks. Home handled plan
expiry (PlanExpiredCard); Train did not.

## Root cause
`train/screen.dart` `_buildContent` always rendered `_buildTodayHeroCard` (or an
empty "viewing week" card) for the current week — it never consulted
`isPhaseExpired()`. So past plan-end it still showed a "current" week.

## Fix
Render `PlanExpiredCard` (the existing recovery widget Home uses) in the hero
slot when `isPhaseExpired()` is true and the user is on the current week. Paired
with BUG-A so it only fires when the plan has genuinely run out.

## Verification
`dart analyze` clean; `train_expired_state_test.dart` (Train references
isPhaseExpired + PlanExpiredCard); decision pinned by
`plan_expiry_respects_schedule_test.dart`.

## See also
- BUG-A (a1d4f9) — isPhaseExpired now honors the materialized schedule.
- `lib/features/train/widgets/plan_expired_card.dart` (shared recovery card).
