---
bug_id: 7ad0ca
date: 2026-05-11
batch: audit-2026-05-11
status: shipped
symptom: `ProfileScreen._performSignOut` called `supabase.auth.signOut()` + `UserRepository.clearAllData()` directly, bypassing `AuthNotifier.signOut()` and — critically — skipping `HiveUserSession.deleteAllFilesForCurrentUser()`. Per-user namespaced Hive files survived on disk after sign-out → re-opens the cross-account leak class that CLAUDE.md §19 documents as closed by namespacing. Next sign-in's legacy migration sweep could re-import them.
concept: profile_signout_auth_notifier
sot_registry_entry: auth_signout
writers:
  - { file: lib/features/profile/screens/profile_screen.dart, method_or_widget: _performSignOut, line: 2197 }
readers:
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: AuthNotifier.signOut, line: 306 }
hive_key_prefix: "userBox_<8hex>, workoutBox_<8hex>, nutritionBox_<8hex>, healthBox_<8hex>, coachBox_<8hex>, customBox_<8hex>, notificationsBox_<8hex>"
hive_key_formula: "n/a — sign-out deletes the entire namespaced box files"
sync_methods: []
restore_methods: []
cloud_table: "n/a — sign-out is a local + auth-service action"
cloud_columns: []
contract_test_path: test/contracts/profile_signout_routes_through_auth_notifier_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: [auth_signed_out]
  failure: []
cross_account_guard: yes
forbidden_patterns_checked: ["profile_signout_direct_supabase_signout_bypass", "profile_signout_direct_clearAllData_without_namespaced_file_delete"]
proposed_fix: Route `_performSignOut` through `ref.read(authNotifierProvider.notifier).signOut()` so the canonical teardown sequence runs — telemetry → `UserRepository.clearAllData()` → `HiveUserSession.deleteAllFilesForCurrentUser()` (deletes the namespaced files, not just clears contents) → `supabase.auth.signOut()` → state reset to idle. Keep a defensive raw-supabase signOut as fallback if the notifier path throws. Add a regression test pinning the delegation + a sibling test that AuthNotifier.signOut() still calls `deleteAllFilesForCurrentUser` (else the canonical path silently drops the namespaced-file cleanup).
regression_test_planned:
  - test/contracts/profile_signout_routes_through_auth_notifier_test.dart
---
# Audit C-10: _performSignOut skipped HiveUserSession cleanup

## Bug

`ProfileScreen._performSignOut` (the only entry point for user-driven
sign-out) called:

```dart
await SupabaseService.instance.client.auth.signOut(scope: SignOutScope.global);
// ...
await UserRepository.instance.clearAllData();
context.go('/sign-in');
```

The canonical sign-out in `AuthNotifier.signOut()` does:

```dart
await UserRepository.instance.clearAllData();
await HiveUserSession.deleteAllFilesForCurrentUser();  // ← missing from profile path
await _supabase.client.auth.signOut();
state = const AuthState2(status: AuthStatus.idle);
```

The profile screen path skipped `deleteAllFilesForCurrentUser`. That
helper deletes the seven per-user namespaced box files entirely
(`userBox_<8hex>`, `workoutBox_<8hex>`, etc.). Without it, the files
stay on disk after sign-out. Next sign-in:

1. New auth user — `_ensureLocalUser` runs.
2. `HiveUserSession.openForUser(newUserId)` opens NEW namespaced boxes
   for the new user.
3. `_migrateLegacySharedBoxes` is gated by a migrationBox flag so it
   normally won't re-run — UNLESS the flag was cleared. In edge cases
   (clearAllData partial-failure, devices that haven't run v2
   migration), stale namespaced files for OTHER users on the same
   device could still leak across through the
   pre-namespacing path.

Same architectural class as C-6 (cross-account guard no-op): a
documented isolation boundary silently disabled by a single missing
call.

## Cause

`_performSignOut` predates `AuthNotifier.signOut()`. When the notifier
was added (Test #5 Plan A — HiveUserSession namespacing), 4+ call
sites were migrated; the profile screen was missed because the audit
sweep didn't include `features/profile/screens/`.

## Fix

```dart
Future<void> _performSignOut() async {
  try {
    await ref.read(authNotifierProvider.notifier).signOut();
  } catch (e) {
    debugPrint('[ProfileScreen._performSignOut] AuthNotifier.signOut: $e');
    // Defensive raw fallback in case the notifier path throws.
    try {
      await SupabaseService.instance.client.auth
          .signOut(scope: SignOutScope.local);
    } catch (e) {
      debugPrint('[ProfileScreen._performSignOut] fallback signOut: $e');
    }
  }
  if (mounted) context.go('/sign-in');
}
```

## Regression tests

`test/contracts/profile_signout_routes_through_auth_notifier_test.dart`
— 3 cases:

- `_performSignOut` delegates to `authNotifierProvider.signOut()`.
- `_performSignOut` does NOT call `UserRepository.clearAllData` directly
  (else drift risk if AuthNotifier evolves).
- `AuthNotifier.signOut()` still calls
  `HiveUserSession.deleteAllFilesForCurrentUser` (else the canonical
  path silently drops the namespaced-file cleanup → leak class re-opens).

## Related

- 7ad0c6 (C-6 — sibling cross-account guard architecture fix)
- CLAUDE.md §19 (cross-account leak class documentation)
- Test #5 Plan A (introduced HiveUserSession namespacing)
