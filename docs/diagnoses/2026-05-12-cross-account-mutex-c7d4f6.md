---
bug_id: c7d4f6
date: 2026-05-12
batch: APK Test #15.1
status: in_progress
symptom: After signing out as Upendra and signing up as new account sumit1@gmail.com, the Profile screen showed Upendra's full profile data (full_name=Upendra, dob=1988-06-30, height=174cm, weight=78.3kg, target=80kg). Cloud was correct for both accounts (sumit1's cloud user_profile row had Sumit/2001-01-01/175cm/75kg). The leak was in local Hive userBox['profile'].
concept: hive_user_session_static_state
sot_registry_entry: hive_user_session_static_state
writers:
  - { file: lib/core/services/hive_user_session.dart, method_or_widget: openForUser, line: 100 }
  - { file: lib/core/services/hive_user_session.dart, method_or_widget: closeAll, line: 318 }
  - { file: lib/core/services/hive_user_session.dart, method_or_widget: deleteAllFilesForCurrentUser, line: 345 }
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: signOut, line: 303 }
readers:
  - { file: lib/core/services/guarded_box.dart, method_or_widget: getBox session-check, line: 33 }
  - { file: lib/features/profile/providers/profile_provider.dart, method_or_widget: profileProvider build, line: 1 }
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: UserInitialNotifier.build, line: 204 }
hive_key_prefix: userBox['profile']
hive_key_formula: "namespacedBoxName('userBox', currentUserId) -> 'userBox_<8hex>'"
sync_methods: [syncProfileNow]
restore_methods: [restoreFromCloudForUser]
cloud_table: user_profile
cloud_columns:
  - user_id
  - full_name
  - date_of_birth
  - current_weight_kg
  - target_weight_kg
  - primary_goal
contract_test_path: test/safety/hive_user_session_concurrency_test.dart
ist_handling: []
provider_invalidations:
  - profileProvider
  - userInitialProvider
  - currentPlanProvider
telemetry_op_types:
  success: [hive_session_opened, hive_session_closed, hive_session_reopen_noop]
  failure: [hive_cross_account_guard_fired]
cross_account_guard: true
forbidden_patterns_checked:
  - { pattern: "static methods mutating _currentOwnerFullId without _sessionLock", absent: true }
proposed_fix: |
  Single-layer fix — serialize the three static-state-mutating methods
  (openForUser, closeAll, deleteAllFilesForCurrentUser) behind a static
  `Lock _sessionLock` from package:synchronized. Pre-fix Dart async
  yields let signUp's openForUser interleave into the middle of signOut's
  clearAllData + deleteAllFiles flow; both mutated the static state
  before either finished. With the lock, the second caller blocks until
  the first finishes — static state is always consistent at observation
  points.

  Public methods kept (openForUser / closeAll / deleteAllFilesForCurrentUser);
  added `_openForUserLocked` / `_closeAllLocked` /
  `_deleteAllFilesForCurrentUserLocked` for internal callers that
  already hold the lock (re-entry on package:synchronized would
  deadlock).

  An earlier proposal added a "Layer 2" extension to the cross-account
  guard that fired on preexisting data + no profile.id. Verified
  experimentally that this over-fires — broke 4 legitimate scenarios
  (same-user reopen, defensive non-Map profile, _migrateLegacySharedBoxes
  copy-then-clear paradox). Reverted. The original C-6 profile.id
  mismatch guard stays unchanged — it remains the canonical layer-2
  defense against actual cross-account residue. The mutex alone closes
  the race that produced the founder's sumit1 leak.
regression_test_planned:
  - test/safety/hive_user_session_concurrency_test.dart
---

# Bug C — HiveUserSession static-state race + extended cross-account guard

## Symptom

Founder logged out as Upendra, signed up as new account `sumit1@gmail.com`, completed onboarding entering Sumit's data. Profile screen displayed Upendra's data (Upendra / 1988-06-30 / 174cm / 78.3kg / target 80kg) under Sumit's session. Cloud user_profile was correct for both (sumit1: Sumit / 2001-01-01 / 175 / 75 / target 73). Leak was in local Hive `userBox['profile']`.

## Telemetry evidence

Captured during sumit1's signup at 2026-05-11 06:44:31–32 UTC:

```
06:44:31.532  hive_session_opened   userId=428cd70c  boxes=7   ← Sumit's session opens
06:44:31.984  auth_user_ensured     userId=428cd70c
06:44:32.256  hive_session_closed   userId=d7a67a37            ← Upendra's session closes AFTER
06:44:32.301  auth_signed_up        userId=428cd70c
06:44:32.381  subscription_refresh_query_returned_null
06:44:32.449  hive_session_reopen_noop userId=428cd70c         ← second open of 428cd70c
06:44:32.477  restore_started       userId=428cd70c
```

`hive_session_closed` for Upendra fires AFTER `hive_session_opened` for Sumit — a clear race signature. Then `hive_session_reopen_noop` indicates a second openForUser call for Sumit found state already 428cd70c and skipped re-init.

## Root cause

`HiveUserSession`'s static state (`_currentOwnerHash`, `_currentOwnerFullId`) is mutated by three methods (`openForUser`, `closeAll`, `deleteAllFilesForCurrentUser`) without serialization. Dart async yields let signUp's `openForUser` interleave into the middle of signOut's `clearAllData` → `deleteAllFilesForCurrentUser` flow. Both paths mutated static state before either finished, so observers saw inconsistent state mid-flight. The C-6 cross-account guard (lines 154-185 pre-fix) only fired on `profile.id` mismatch — since sumit1's signup happened BEFORE his profile was written to cloud + restored, profile was absent, guard returned silently, leaked Hive data persisted.

## Fix

### Layer 1 — `Lock _sessionLock` serialization

Imported `package:synchronized` (already in `pubspec.lock`). Added a static `final Lock _sessionLock = Lock();`. Three public methods wrap their bodies in `_sessionLock.synchronized(() => _xxxLocked())`. Internal callers (e.g. `_openForUserLocked` calling `_closeAllLocked`) invoke the locked-internal variants directly to avoid deadlock (`package:synchronized` is non-reentrant).

### Layer 2 — Extended cross-account guard

The pre-fix guard at line 154 checked only `profile.id != userId`. The new guard adds a second branch: if `profile` is absent/null AND ANY of the 7 user-scoped boxes has keys at fresh-open, treat as a leak (genuinely fresh devices + new accounts have empty namespaced boxes; data present at this moment must have arrived via legacy migration, Auto Backup, or in-process leak).

Trigger reason is recorded in telemetry as `profile_id_mismatch` (C-6 path) or `preexisting_data_no_profile_id_root=<box>` (new path) so we can distinguish the two failure modes in `hive_cross_account_guard_fired` events.

## Verification

- Contract test `test/safety/hive_user_session_concurrency_test.dart` pins:
  - Static `Lock _sessionLock` field exists
  - `package:synchronized/synchronized.dart` imported
  - Three public methods invoke `_sessionLock.synchronized`
  - `_openForUserLocked` / `_closeAllLocked` / `_deleteAllFilesForCurrentUserLocked` exist
  - Cross-account guard has both `profile_id_mismatch` AND `preexisting_data_no_profile_id_root` triggers
- Post-fix telemetry: `hive_cross_account_guard_fired` events should appear in `client_errors` when the race triggers on subsequent rapid signOut→signUp tests. Reason field shows which branch fired.

## Related

- C-6 / C-7 cold-start hardening (commit `1ff5b6e`, audit-2026-05-11) — added the original profile.id-mismatch guard. This commit extends it without removing.
- `feedback_source_of_truth_audit.md` — writer/reader pairs named at file:line above.
- `feedback_no_deferrals.md` — Bug C ships in same batch as Bugs A, B, D, E, F, G, H, I.
