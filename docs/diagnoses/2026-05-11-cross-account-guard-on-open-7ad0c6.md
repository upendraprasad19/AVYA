---
bug_id: 7ad0c6
date: 2026-05-11
batch: audit-2026-05-11
status: shipped
symptom: splash_screen.dart cross-account Hive leak guard was a no-op on every cold start. `HiveService.instance.userBox` is a `GuardedBox` that throws `HiveUserSession not opened` before any `openForUser` has run; the try/catch swallowed it and the guard never executed. Android Auto Backup restores / dev-build Hive copies / legacy migration races could leave a foreign profile.id inside the new user's namespaced box and the safety net CLAUDE.md §19 promises did not actually run.
concept: cross_account_guard_on_open
sot_registry_entry: cross_account_guard_on_open
writers:
  - { file: lib/core/services/hive_user_session.dart, method_or_widget: openForUser, line: 70 }
readers:
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: _ensureLocalUser, line: 367 }
hive_key_prefix: "userBox_<8hex>"
hive_key_formula: "profile (key='profile')"
sync_methods: []
restore_methods: []
cloud_table: "n/a — guard runs entirely client-side at session open"
cloud_columns: []
contract_test_path: test/safety/cross_account_guard_on_open_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: [hive_cross_account_guard_fired]
  failure: [hive_cross_account_guard_error]
cross_account_guard: yes
forbidden_patterns_checked: ["splash_userbox_get_profile_with_try_catch_swallow"]
proposed_fix: Lift the guard into `HiveUserSession.openForUser` itself. After opening the 7 namespaced boxes for `userId`, read `userBox['profile']`; if `profile.id` is present and mismatches `userId`, clear all 7 boxes in place + log telemetry. Remove the no-op splash_screen.dart try/catch block. The `auth_provider._ensureLocalUser` heavier ClearResult / force-signOut check stays in place as a second layer for partial-clear failures.
regression_test_planned:
  - test/safety/cross_account_guard_on_open_test.dart
  - test/contracts/splash_post_auth_session_gate_test.dart (asserts splash legacy read is gone)
---
# Audit C-6: cross-account Hive leak guard was a no-op

## Bug

`splash_screen.dart:119-131` (pre-fix) ran a defensive cross-account
guard during `_runDeferredInit` BEFORE `auth_provider._ensureLocalUser`
opened the per-user namespaced boxes. The guard read
`HiveService.instance.userBox.get('profile')` — but `userBox` is a
`GuardedBox` that throws `HiveUserSession not opened` whenever no
session has been opened in the current process. The surrounding
`try/catch` swallowed the throw with a debugPrint, so the guard never
actually fired.

The leak class the guard was supposed to catch:

1. Android Auto Backup restores Hive files from another device.
2. Pre-namespacing, those files have shared box names (`userBox`,
   `workoutBox`, etc.).
3. `HiveUserSession._migrateLegacySharedBoxes` copies them into the
   namespaced box for the current user.
4. The namespaced box now contains a profile belonging to userIdC
   even though userIdA just signed in.

`auth_provider._ensureLocalUser` does run the same check at line 367
and would clear, but a single defensive layer at the storage entry
point is the documented architecture per CLAUDE.md §19. Splash being a
no-op silently halved that defense.

## Cause

`HiveUserSession.openForUser` was added in Test #5 to namespace boxes
per user. After that change, every read of `HiveService.instance.userBox`
goes through `GuardedBox._resolve`, which throws when
`HiveUserSession.currentOwnerFullId == null`. The splash guard was
never updated to reflect the new lifecycle.

## Fix

Two parts:

1. **Lift the check into `HiveUserSession.openForUser`.** After opening
   the 7 namespaced boxes for `userId`, read `Hive.box(userBox_<hash>).get('profile')`. If `profile.id` is non-null and
   mismatches `userId`, clear all 7 namespaced boxes in place via
   `.clear()` and log `hive_cross_account_guard_fired` telemetry.

2. **Remove the no-op splash_screen.dart block.** The check now lives
   inside `openForUser`, which runs on every code path that opens a
   session (auth_provider._ensureLocalUser, SyncService._ensureSessionOpen,
   RestoringScreen). `auth_provider._ensureLocalUser`'s heavier
   ClearResult / force-signOut check stays in place as a second layer
   for partial-clear failures.

## Regression test

`test/safety/cross_account_guard_on_open_test.dart` — 4 cases:

- mismatched `profile.id` in namespaced box → cleared on `openForUser`
- matching `profile.id` → untouched
- absent profile → no-op (fresh box for new user)
- non-Map profile value → no-op (defensive, never seen in prod)

Plus `test/contracts/splash_post_auth_session_gate_test.dart` pins
that the splash legacy read is gone (string-grep on
`HiveService.instance.userBox.get('profile')`).

## Related

- 7ad0c7 (C-7 — sibling fix for the 4 splash post-auth mutations that
  raced the session)
- CLAUDE.md §19 (cross-account leak class documentation)
