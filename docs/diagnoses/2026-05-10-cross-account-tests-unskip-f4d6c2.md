---
bug_id: f4d6c2
date: 2026-05-10
batch: backlog cleanup (post-Test-#15)
status: in_progress
symptom: 3 cross-account isolation tests in test/auth/cross_account_isolation_test.dart were stubbed with `skip:` referencing HiveService.lastAuthenticatedUserIdKey — a constant from an abandoned Plan A namespacing prototype. The test file added zero coverage to the actually-shipped HiveUserSession + GuardedBox surface.
concept: cross_account_isolation
sot_registry_entry: cross_account_isolation
writers:
  - { file: lib/core/services/hive_user_session.dart, method_or_widget: HiveUserSession.openForUser, line: 70 }
  - { file: lib/core/services/hive_user_session.dart, method_or_widget: HiveUserSession.closeAll, line: 201 }
  - { file: lib/shared/repositories/user_repository.dart, method_or_widget: UserRepository.clearAllData, line: 232 }
readers:
  - { file: lib/core/services/guarded_box.dart, method_or_widget: GuardedBox cross-user check, line: 33 }
  - { file: lib/core/services/hive_service.dart, method_or_widget: _userScopedBoxNames list, line: 61 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/auth/cross_account_isolation_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "true (this entire suite pins the guard)"
forbidden_patterns_checked:
  - { pattern: "_hive\\.exerciseBox\\.clear\\(\\)", absent: true }
  - { pattern: "_hive\\.foodBox\\.clear\\(\\)", absent: true }
  - { pattern: "_hive\\.migrationBox\\.clear\\(\\)", absent: true }
proposed_fix: |
  Replace the 3 stubs with 9 source-grep contracts pinning the actually-
  shipped cross-account isolation surface: HiveUserSession.openForUser /
  closeAll exist, GuardedBox class + actionable error message present,
  UserRepository.clearAllData clears 7 user-scoped boxes + syncBox +
  configBox, and explicitly does NOT clear exerciseBox / foodBox (seeds)
  / migrationBox (one-shot device-lifetime flags). HiveService.
  _userScopedBoxNames excludes seed boxes and contains the 7 per-user
  boxes.
regression_test_planned:
  - test/auth/cross_account_isolation_test.dart
---

# Cross-account isolation tests — unskipped + rewritten

## Symptom

`test/auth/cross_account_isolation_test.dart` shipped 3 placeholder tests with `skip: 'Deferred to follow-up — HiveService.lastAuthenticatedUserIdKey constant does not exist on this branch (likely renamed/removed during Plan A namespacing). Test references obsolete API; rewrite needed against the current cross-account-isolation surface (HiveUserSession + GuardedBox + clearAllDataForCurrentUser).'`

The file added zero protection against the cross-account leak class — the same class of bug that bit the founder pre-Test-#11.1 (PRO pill + templates + coach memory cross-session leakage).

## Root cause

The original test author was working off a different namespacing design (Plan A) that introduced a `lastAuthenticatedUserIdKey` constant in `HiveService`, written to `syncBox`. That design was superseded during Plan A → final implementation by:

- **`HiveUserSession`** — class managing per-user box opening / closing
- **`GuardedBox<T>`** — wrapper that throws on cross-user access
- **`UserRepository.clearAllData()`** — sign-out / cross-account guard cleanup

The constant was never added; the tests were left as `skip` stubs against the abandoned API.

## Fix

Rewrote the file (9 source-grep contracts replacing 3 stubs) pinning the current surface:

1. `HiveUserSession.openForUser(String userId)` exists.
2. `HiveUserSession.closeAll()` exists.
3. `GuardedBox<T>` class exists with the actionable error message `Call HiveUserSession.openForUser(userId)` — telemetry greps on this string.
4. `clearAllData()` clears all 7 user-scoped boxes (userBox, workoutBox, nutritionBox, healthBox, coachBox, customBox, notificationsBox).
5. `clearAllData()` clears shared mutable boxes (syncBox, configBox) — the pre-Test-#10.1 PRO-pill leak class.
6. **Forbidden** `_hive.exerciseBox.clear()` — seed data, must survive sign-out.
7. **Forbidden** `_hive.foodBox.clear()` — seed data, must survive sign-out.
8. **Forbidden** `_hive.migrationBox.clear()` — one-shot device-lifetime flags MUST survive sign-out.
9. `HiveService._userScopedBoxNames` excludes seed boxes and contains exactly the 7 per-user mutable boxes.

## Verification

All 9 tests pass via `flutter test test/auth/cross_account_isolation_test.dart`. No production code changes.

## Related

- `feedback_main_is_source_of_truth.md` — the migrationBox-survives-clear contract is foundational to that rule
- `feedback_no_setup_confirmations.md`
- `project_apk_test_11_1_full_config_migration.md` — the cross-account leak class this suite protects against
