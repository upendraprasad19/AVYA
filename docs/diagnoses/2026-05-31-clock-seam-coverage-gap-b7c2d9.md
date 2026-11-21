---
bug_id: b7c2d9
date: 2026-05-31
batch: year-simulation-2026-05-31
status: fixed
symptom: >
  The /dev time-travel buttons (and the injectable clock seam in ist_date.dart)
  did not actually move phase / rank / streak logic: jumping the clock +12 weeks
  left the Train week selector, isPhaseExpired, rank weeks-since-signup, and the
  streak walk-back all reading the REAL system clock. Surfaced while building the
  year-simulation harness — a clock-seam-driven sim could not trigger the real
  isPhaseExpired→autoGenerateNextPhase path or advance rank by simulated time.
concept: ist_date_clock_seam
sot_registry_entry: n/a
blast_radius: account
writers:
  - { file: lib/core/utils/ist_date.dart, method: nowWall() public seam accessor (== DateTime.now() in release), line: 65 }
readers:
  - { file: lib/core/services/workout_schedule_read_service.dart, method: isPhaseExpired / getCurrentWeekNumber / getCurrentCalendarWeek / nextPhaseStartDate via nowWall(), line: 487 }
  - { file: lib/core/services/rank_service.dart, method: _readEvaluationState weeksSinceSignup via nowWall(), line: 434 }
  - { file: lib/features/train/repositories/workout_repository.dart, method: _calculateStreak today via nowWall(), line: 198 }
  - { file: lib/core/services/streak_progress_service.dart, method: refillIfNewWeek mondayOfIst(nowWall()), line: 144 }
hive_key_prefix: "n/a (time source, not a Hive key)"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: n/a
cloud_columns: []
contract_test_path: test/contracts/clock_seam_nowwall_test.dart
ist_handling:
  - { site: ist_date.dart nowWall, helper: _wallNow, status: ok }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: >
  n/a — nowWall() is a wall-clock source. The override is a hard no-op in
  release (setTestClock returns immediately when dart.vm.product is true), so
  production behaviour is byte-identical to DateTime.now().
forbidden_patterns_checked:
  - { pattern: "schedule/rank/streak read raw DateTime.now() ignoring the seam", absent: true }
proposed_fix: >
  The clock seam (setTestClock in ist_date.dart) overrode only istNow()/
  istTodayStr() via _wallNow(); the phase/rank/streak code read raw
  DateTime.now() and ignored it. Added a public seam-aware nowWall() (returns
  _wallNow(); identical to DateTime.now() in release) and routed the time-gate
  reads through it: workout_schedule_read_service.dart (isPhaseExpired,
  getCurrentWeekNumber, getCurrentDayInPhase, getCurrentCalendarWeek,
  nextPhaseStartDate), rank_service.dart (weeksSinceSignup), workout_repository
  .dart (_calculateStreak today, getTodaySchedule, completionRateOverWindow),
  and streak_progress_service.dart (refillIfNewWeek mondayOfIst). Behavior-
  preserving in production; makes /dev time-travel + the year-sim harness drive
  phase/rank/streak correctly.
regression_test_planned:
  - test/contracts/clock_seam_nowwall_test.dart
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "nowWall() added (ist_date.dart); 11 raw DateTime.now() time-gate sites routed through it across schedule/rank/streak; flutter analyze clean" }
  - { tier: 2, layer: hive_local_state, status: verified, evidence: "clock_seam_nowwall_test.dart: setTestClock override honored by nowWall + istTodayStr; reset restores real clock" }
impact_analysis: >
  No production behaviour change — nowWall() == DateTime.now() in release builds
  (the seam setter is a hard no-op under dart.vm.product). The bug was latent:
  the /dev time-travel panel and the injectable clock seam (shipped 2026-05-29)
  silently failed to move phase/rank/streak logic, so any debug/QA time-travel
  gave misleading results and the year-simulation harness could not exercise the
  real phase-rollover or rank-by-time paths. Fixing it makes both the dev panel
  and the committed year-sim harness faithful to production code paths.
---

# b7c2d9 — clock-seam coverage gap (phase/rank/streak ignored the test clock)

## What happened
`ist_date.dart`'s `setTestClock` override fed only `istNow()` / `istTodayStr()`
(via the private `_wallNow()`). But the phase-rollover, rank-eligibility, and
streak-walk-back code all called **raw `DateTime.now()`**, so they ignored the
override entirely. The `/dev` time-travel buttons (shipped 2026-05-29) appeared
to "move time" but left `isPhaseExpired`, `getCurrentWeekNumber`, rank
`weeksSinceSignup`, the streak walk-back, and the weekly freeze refill all
anchored to the real system clock.

## Why it mattered
The year-simulation harness drives the calendar via the seam. With the gap, a
seam-driven sim could not trigger the real `isPhaseExpired → autoGenerateNext`
path, could not advance rank by simulated weeks, and the streak/freeze logic ran
against real "today" while data was dated to simulated days.

## Fix
Added a public seam-aware `nowWall()` (`ist_date.dart`) — `_wallNow()` exposed,
byte-identical to `DateTime.now()` in release (the override can never be set when
`dart.vm.product` is true). Routed the time-gate reads through it across
`workout_schedule_read_service.dart`, `rank_service.dart`,
`workout_repository.dart`, and `streak_progress_service.dart`.

## Verification
`test/contracts/clock_seam_nowwall_test.dart` passes: `nowWall()` honors a fixed
+ forward-jumping override and matches `DateTime.now()` when reset;
`istTodayStr()` still applies the IST conversion under override. Live: `/dev`
+12-week jump now moves the Train week selector + rank "days to next"; the
year-sim's `isPhaseExpired` fires at simulated phase boundaries.
