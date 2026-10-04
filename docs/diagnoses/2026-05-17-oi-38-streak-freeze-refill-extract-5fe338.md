---
bug_id: 5fe338
date: 2026-05-17
batch: Hermes audit 2026-05-17 — Phase C (P2 process)
status: shipped
symptom: |
  `StreakFreezeNotifier.build()` called `_refillIfNewWeek()` which
  eventually called `StreakProgressService.instance.commitRefill(...)`.
  Riverpod write-on-read anti-pattern: every provider rebuild (auth
  change, invalidation, app refresh, hot reload) re-entered the path.
  Idempotency guard (`lastRefill compareTo thisMondayStr`) made it
  safe in practice but the pattern is wrong — `build()` should be
  read-only.
concept: streak_freeze_refill_extract
sot_registry_entry: streak_refill_owner
writers:
  - { file: lib/core/services/streak_progress_service.dart, method: refillIfNewWeek orchestrator, line: 110 }
  - { file: lib/core/services/day_rollover_service.dart, method: invokes refillIfNewWeek per rollover, line: 145 }
  - { file: lib/features/home/providers/home_provider.dart, method: build is now read-only, line: 256 }
readers:
  - { file: test/contracts/phase_c_oi_closures_test.dart, method_or_widget: OI-38 group (3 cases), line: 92 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: [syncFreezes]
restore_methods: [_restoreFreezes]
cloud_table: user_progress
cloud_columns: [streak_freezes_available, streak_freezes_last_refill, streak_freeze_used_dates]
contract_test_path: test/contracts/phase_c_oi_closures_test.dart
ist_handling:
  - { file: lib/core/utils/ist_date.dart, line: 51, fn: mondayOfIst }
provider_invalidations: [streakFreezeProvider]
telemetry_op_types:
  success: []
  failure: [day_rollover_streak_freeze_refill]
cross_account_guard: "user_progress is user-scoped via auth.uid()"
forbidden_patterns_checked:
  - { pattern: "_refillIfNewWeek call inside StreakFreezeNotifier.build", absent: true }
  - { pattern: "commitRefill call inside StreakFreezeNotifier.build", absent: true }
proposed_fix: |
  Moved the refill orchestration into a new
  `StreakProgressService.refillIfNewWeek()` method (idempotent,
  returns new available count or null if already refilled). Invoked
  from `day_rollover_service._doRolloverWithRef` (every rollover).
  Splash post-restore is already covered indirectly via cold-start
  rollover. `StreakFreezeNotifier.build()` is now a pure read.

  Lens L26 (CQRS / pure-function discipline) — the second-oldest
  documented lens (in feedback_audit_methodology_lenses.md since
  2026-05-11) finally being applied.
regression_test_planned:
  - test/contracts/phase_c_oi_closures_test.dart
---

# Bug 5fe338 — StreakFreezeNotifier.build wrote on read

closes-oi: OI-38

CQRS violation. Idempotency guard kept it safe-in-practice but the pattern was wrong + invisible in the SoT model. Now refill lives in the service + fires from day rollover; build is read-only.
