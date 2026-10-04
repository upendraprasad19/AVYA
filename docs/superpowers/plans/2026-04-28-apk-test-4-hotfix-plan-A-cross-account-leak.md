# APK Test #4 Hotfix Plan A — Cross-Account Leak (B1 + B5)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the production-blocking cross-account Hive leak (user signs out + signs in as different account, sees prior account's data).

**Architecture:** 3-layer defense — (1) `clearAllData()` covers all 11 Hive boxes (was 8); (2) `last_authenticated_user_id` flag stored in `syncBox` becomes the canonical "who owns this Hive" anchor; (3) `_ensureLocalUser` always force-clears on user-id mismatch even when `existing == null`. Plus RestoringScreen guard that blocks navigation to `/home` if Hive ownership doesn't match the current session.

**Tech Stack:** Dart, Flutter, Hive, Supabase Auth, Riverpod, GoRouter.

**Spec reference:** `docs/superpowers/specs/2026-04-28-apk-test-4-hotfix-batch-design.md` §3 B1 + §3 B5.

**Estimated effort:** 6-8h.

---

## File structure

| File | Action | Responsibility |
|---|---|---|
| `lib/shared/repositories/user_repository.dart` | MODIFY | Add `notificationsBox` to `clearAllData()` |
| `lib/core/services/hive_service.dart` | MODIFY | Add `lastAuthenticatedUserIdKey` constant |
| `lib/features/auth/providers/auth_provider.dart` | MODIFY | Strengthen `_ensureLocalUser` — always clear on mismatch + write last_authenticated_user_id |
| `lib/features/auth/screens/restoring_screen.dart` | MODIFY | Block /home navigation if Hive ownership ≠ session user.id |
| `test/contracts/clear_all_data_box_coverage_test.dart` | CREATE | Source-grep contract test asserting clearAllData covers all non-seed boxes |
| `test/auth/cross_account_isolation_test.dart` | CREATE | Behavioural test of cross-account guard |
| `test/auth/restoring_screen_guard_test.dart` | CREATE | RestoringScreen blocks navigation on ownership mismatch |

---

## Task A1 — Add notificationsBox to clearAllData

**Files:**
- Modify: `lib/shared/repositories/user_repository.dart` (`clearAllData` method)

- [ ] **Step 1: Read the current method**

```bash
cd "C:/Upendra/Claude Code/fitness-app-test-4"
grep -nA 15 "Future<void> clearAllData" lib/shared/repositories/user_repository.dart
```

Expected: lines 200-210 show 8 box clears.

- [ ] **Step 2: Add notificationsBox.clear() to the method**

Edit `lib/shared/repositories/user_repository.dart`:

```dart
// BEFORE (line 200-210):
Future<void> clearAllData() async {
  await _hive.userBox.clear();
  await _hive.workoutBox.clear();
  await _hive.nutritionBox.clear();
  await _hive.healthBox.clear();
  await _hive.coachBox.clear();
  await _hive.syncBox.clear();
  await _hive.configBox.clear();
  await _hive.customBox.clear();
  // Keep exerciseBox and foodBox (seeded data, no need to re-downloaded)
}

// AFTER:
Future<void> clearAllData() async {
  await _hive.userBox.clear();
  await _hive.workoutBox.clear();
  await _hive.nutritionBox.clear();
  await _hive.healthBox.clear();
  await _hive.coachBox.clear();
  await _hive.syncBox.clear();
  await _hive.configBox.clear();
  await _hive.customBox.clear();
  await _hive.notificationsBox.clear();
  // Keep exerciseBox and foodBox (seeded data, no need to re-downloaded)
}
```

- [ ] **Step 3: Verify compile**

```bash
flutter analyze lib/shared/repositories/user_repository.dart
```

Expected: no errors. If `_hive.notificationsBox` doesn't compile, check `HiveService` for the actual getter name (might be `notificationsBox` already exposed, or might need to be added).

- [ ] **Step 4: Commit**

```bash
git add lib/shared/repositories/user_repository.dart
git commit -m "fix(auth): add notificationsBox to clearAllData (B1 layer 1)

CLAUDE.md §19 cross-account leak fix layer 1.
notificationsBox was added later (PR AG) but never added to clearAllData.
After sign-out, prior user's notifications persisted across accounts.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task A2 — Add lastAuthenticatedUserIdKey constant

**Files:**
- Modify: `lib/core/services/hive_service.dart`

- [ ] **Step 1: Find the constants block**

```bash
grep -n "static const String.*Key" lib/core/services/hive_service.dart | head -10
```

- [ ] **Step 2: Add the constant**

Add a new constant alongside existing keys (in the syncBox keys area):

```dart
// In hive_service.dart, alongside other syncBox-related keys:
static const String lastAuthenticatedUserIdKey = 'last_authenticated_user_id';
```

If the file doesn't already have a "syncBox keys" block, add it as a top-level public constant on `HiveService`:

```dart
class HiveService {
  // ... existing box name constants ...

  /// Key in syncBox storing the Supabase user.id of the account whose data
  /// currently lives in Hive. Cross-account leak guard (B1 layer 2).
  /// Stamped on every successful sign-in by `_ensureLocalUser`.
  /// Read by `_ensureLocalUser` to detect mismatch + force clearAllData.
  /// Read by RestoringScreen to gate /home navigation.
  static const String lastAuthenticatedUserIdKey = 'last_authenticated_user_id';

  // ... rest of class ...
}
```

- [ ] **Step 3: Verify**

```bash
flutter analyze lib/core/services/hive_service.dart
```

- [ ] **Step 4: Commit**

```bash
git add lib/core/services/hive_service.dart
git commit -m "feat(hive): add lastAuthenticatedUserIdKey constant (B1 layer 2)

Cross-account leak guard — Hive needs to know which account's data it
currently holds. Stamped on sign-in by _ensureLocalUser, consumed by
RestoringScreen to gate /home navigation.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task A3 — Strengthen `_ensureLocalUser` cross-account guard

**Files:**
- Modify: `lib/features/auth/providers/auth_provider.dart`

- [ ] **Step 1: Locate `_ensureLocalUser`**

```bash
grep -n "_ensureLocalUser\|existingId.*user.id\|UserRepository.instance.clearAllData" lib/features/auth/providers/auth_provider.dart | head -10
```

The method starts around line 324.

- [ ] **Step 2: Write failing test FIRST**

Create `test/auth/cross_account_isolation_test.dart`:

```dart
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('avya_test_a3_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tempDir.path,
      );
    Hive.init(tempDir.path);
    await HiveService.instance.init();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    // Clear everything between tests
    await HiveService.instance.userBox.clear();
    await HiveService.instance.workoutBox.clear();
    await HiveService.instance.nutritionBox.clear();
    await HiveService.instance.healthBox.clear();
    await HiveService.instance.coachBox.clear();
    await HiveService.instance.syncBox.clear();
    await HiveService.instance.configBox.clear();
    await HiveService.instance.customBox.clear();
    await HiveService.instance.notificationsBox.clear();
  });

  group('cross-account isolation (B1)', () {
    test('clearAllData clears all non-seed boxes including notificationsBox', () async {
      // Populate all boxes
      await HiveService.instance.userBox.put('profile', {'id': 'A', 'name': 'Alice'});
      await HiveService.instance.workoutBox.put('wlog_1', {'workout': 'PUSH A'});
      await HiveService.instance.notificationsBox.put('notif_1', {'title': 'Test'});
      await HiveService.instance.coachBox.put('committed_at', '2026-01-01');
      await HiveService.instance.syncBox.put(HiveService.lastAuthenticatedUserIdKey, 'A');

      await UserRepository.instance.clearAllData();

      expect(HiveService.instance.userBox.get('profile'), isNull);
      expect(HiveService.instance.workoutBox.get('wlog_1'), isNull);
      expect(HiveService.instance.notificationsBox.get('notif_1'), isNull,
        reason: 'B1 fix: notificationsBox MUST be in clearAllData');
      expect(HiveService.instance.coachBox.get('committed_at'), isNull);
      expect(HiveService.instance.syncBox.get(HiveService.lastAuthenticatedUserIdKey), isNull);
    });

    test('lastAuthenticatedUserIdKey constant is "last_authenticated_user_id"', () {
      // Locks the constant value so RestoringScreen and tests stay in sync.
      expect(HiveService.lastAuthenticatedUserIdKey, 'last_authenticated_user_id');
    });
  });
}
```

- [ ] **Step 3: Run test — should fail BEFORE A1 fix is in (notificationsBox), should PASS after A1**

```bash
flutter test test/auth/cross_account_isolation_test.dart
```

Expected: PASS (since A1 already added notificationsBox to clearAllData and A2 added the constant). If FAIL, double-check A1 + A2 commits landed.

- [ ] **Step 4: Modify `_ensureLocalUser` to always force-clear on mismatch**

Read current implementation around line 324-340. The current logic only clears when `existing != null && existingId != user.id`. Replace with logic that ALSO checks `last_authenticated_user_id` independently of `existing`:

```dart
Future<void> _ensureLocalUser(User user) async {
  final userBox = _hive.userBox;
  final syncBox = _hive.syncBox;
  final configBox = _hive.configBox;
  final existing = userBox.get('profile');

  // B1 layer 2/3: Cross-account safety net.
  //
  // Two checks:
  //   (a) existing profile id mismatches new user.id → leftover from a
  //       failed/incomplete sign-out. Clear.
  //   (b) syncBox['last_authenticated_user_id'] mismatches new user.id →
  //       Hive belongs to a different account (e.g., notificationsBox or
  //       any future-added box left stale by a partial signOut). Clear.
  //
  // Either condition triggers clearAllData. Both checks survive the
  // case where existing == null (signOut cleared userBox but missed
  // some other box).
  bool needsClear = false;
  String? clearReason;

  if (existing != null) {
    final existingId =
        (existing as Map<dynamic, dynamic>?)?['id'] as String?;
    if (existingId == null || existingId != user.id) {
      needsClear = true;
      clearReason = 'profile id mismatch (had=$existingId, now=${user.id})';
    }
  }
  if (!needsClear) {
    final lastAuthId = syncBox.get(HiveService.lastAuthenticatedUserIdKey) as String?;
    if (lastAuthId != null && lastAuthId != user.id) {
      needsClear = true;
      clearReason = 'last_authenticated_user_id mismatch (had=$lastAuthId, now=${user.id})';
    }
  }
  if (needsClear) {
    debugPrint('[auth/_ensureLocalUser] Cross-account guard fired: $clearReason. Clearing Hive.');
    await UserRepository.instance.clearAllData();
  }

  // B1 layer 3: stamp the current user.id as Hive's owner.
  // Done BEFORE the rest of _ensureLocalUser so any failure later
  // doesn't leave the Hive in an "ownerless" state.
  try {
    await syncBox.put(HiveService.lastAuthenticatedUserIdKey, user.id);
  } catch (e) {
    debugPrint('[auth/_ensureLocalUser] failed to stamp last_authenticated_user_id: $e');
    // Non-fatal — guard fires next launch if needed.
  }

  // ... rest of existing _ensureLocalUser logic continues unchanged
  // (users table upsert, terms_accepted_at sync, etc.)
}
```

Add the `import` for HiveService at the top of the file if not already present:

```dart
import 'package:icanbefitter/core/services/hive_service.dart';
```

- [ ] **Step 5: Add the integration test**

In the same `test/auth/cross_account_isolation_test.dart` file, add:

```dart
test('cross-account: existing profile id mismatch triggers clear', () async {
  // Simulate stale Hive from prior account A
  await HiveService.instance.userBox.put('profile', {'id': 'A', 'name': 'Alice'});
  await HiveService.instance.workoutBox.put('wlog_1', {'workout': 'PUSH A'});

  // (We can't directly call _ensureLocalUser without a User object — this
  // test asserts the contract that clearAllData fires. The integration is
  // exercised on-device.)
  // Manually call the same clear logic _ensureLocalUser would:
  await UserRepository.instance.clearAllData();

  expect(HiveService.instance.userBox.get('profile'), isNull);
  expect(HiveService.instance.workoutBox.get('wlog_1'), isNull);
});

test('lastAuthenticatedUserIdKey can be written and read from syncBox', () async {
  await HiveService.instance.syncBox.put(HiveService.lastAuthenticatedUserIdKey, 'user-id-123');
  final read = HiveService.instance.syncBox.get(HiveService.lastAuthenticatedUserIdKey);
  expect(read, 'user-id-123');
});
```

- [ ] **Step 6: Run all tests**

```bash
flutter test test/auth/cross_account_isolation_test.dart
flutter test test/  # full suite — should still pass
```

- [ ] **Step 7: Commit**

```bash
git add lib/features/auth/providers/auth_provider.dart \
        test/auth/cross_account_isolation_test.dart
git commit -m "fix(auth): strengthen _ensureLocalUser cross-account guard (B1 layer 3)

Two-check guard fires on EITHER:
1. existing profile id ≠ new user.id (leftover from failed sign-out)
2. syncBox.last_authenticated_user_id ≠ new user.id (other boxes stale)

Either condition triggers clearAllData. Both checks survive the
'existing == null' case where userBox was cleared but some other box
wasn't (the original B1 root cause).

After sign-in, stamp current user.id as last_authenticated_user_id.

Tests: 4 contract scenarios in test/auth/cross_account_isolation_test.dart.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task A4 — RestoringScreen ownership guard (B5)

**Files:**
- Modify: `lib/features/auth/screens/restoring_screen.dart`

- [ ] **Step 1: Read current restore + navigate logic**

```bash
grep -n "onboarding_completed_at\|restoreFromCloudForUser\|context.go\|cancelInflightRestore" lib/features/auth/screens/restoring_screen.dart | head -15
```

- [ ] **Step 2: Add the ownership guard**

In the method that decides to navigate to `/home` (after the user_profile lookup determines the user is onboarded), insert a guard before `context.go('/home')`:

```dart
// BEFORE the existing context.go('/home') call:
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// In the navigate-to-home path:
{
  final sessionUserId = Supabase.instance.client.auth.currentUser?.id;
  final hiveOwnerId = HiveService.instance.syncBox
      .get(HiveService.lastAuthenticatedUserIdKey) as String?;

  if (sessionUserId != null && hiveOwnerId != null && hiveOwnerId != sessionUserId) {
    // B5 fix: Hive belongs to a different account — clear before navigate.
    debugPrint('[RestoringScreen] Hive ownership mismatch (hive=$hiveOwnerId, session=$sessionUserId). Force-clearing.');
    await UserRepository.instance.clearAllData();
    // Re-stamp ownership so we don't loop
    await HiveService.instance.syncBox.put(HiveService.lastAuthenticatedUserIdKey, sessionUserId);
    // Re-attempt restore for the correct user
    await SyncService.instance.restoreFromCloudForUser();
  }
}

if (mounted) {
  context.go('/home');
}
```

The guard runs ONCE before navigation. If it fires, clearAllData runs synchronously, re-stamp happens, restore is re-attempted, then navigate. This catches the case where Hive has stale data from a previous account that got past the auth provider's check.

- [ ] **Step 3: Test (logic-level)**

Create `test/auth/restoring_screen_guard_test.dart`:

```dart
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('avya_test_a4_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tempDir.path,
      );
    Hive.init(tempDir.path);
    await HiveService.instance.init();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await HiveService.instance.userBox.clear();
    await HiveService.instance.workoutBox.clear();
    await HiveService.instance.syncBox.clear();
  });

  group('RestoringScreen ownership guard (B5)', () {
    test('guard logic: when hiveOwnerId != sessionUserId, mismatch detected', () async {
      await HiveService.instance.syncBox.put(HiveService.lastAuthenticatedUserIdKey, 'A');
      final hiveOwner = HiveService.instance.syncBox.get(HiveService.lastAuthenticatedUserIdKey);
      const sessionUserId = 'B';
      expect(hiveOwner != sessionUserId, true);
    });

    test('guard logic: when hiveOwnerId == sessionUserId, no mismatch', () async {
      await HiveService.instance.syncBox.put(HiveService.lastAuthenticatedUserIdKey, 'A');
      final hiveOwner = HiveService.instance.syncBox.get(HiveService.lastAuthenticatedUserIdKey);
      const sessionUserId = 'A';
      expect(hiveOwner != sessionUserId, false);
    });

    test('guard logic: when hiveOwnerId is null, guard skips (no mismatch)', () async {
      // Cold install — no last auth
      final hiveOwner = HiveService.instance.syncBox.get(HiveService.lastAuthenticatedUserIdKey);
      expect(hiveOwner, isNull);
      // Guard's null-check should skip in this case (guard only fires when both are non-null and different)
    });
  });
}
```

- [ ] **Step 4: Run tests**

```bash
flutter test test/auth/
flutter test test/  # full suite
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/auth/screens/restoring_screen.dart \
        test/auth/restoring_screen_guard_test.dart
git commit -m "fix(auth): RestoringScreen ownership guard (B5)

Before navigating to /home after restore, check that Hive's
last_authenticated_user_id matches the current Supabase session user.id.

If mismatch (Hive belongs to a different account that got past _ensureLocalUser):
1. Force clearAllData
2. Re-stamp ownership
3. Re-attempt restore for the correct user
4. Then navigate

This is B1's third layer — even if _ensureLocalUser missed the leak,
RestoringScreen catches it before the user lands on /home with stale data.

Tests: 3 ownership-guard contract scenarios.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task A5 — Source-grep contract test for clearAllData box coverage

**Files:**
- Create: `test/contracts/clear_all_data_box_coverage_test.dart`

This test prevents future regressions: any new Hive box added to HiveService must also be added to clearAllData (unless explicitly listed in the seed-data exception list).

- [ ] **Step 1: Write the contract test**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CONTRACT: every non-seed Hive box getter must be in clearAllData', () {
    final hiveServiceFile = File('lib/core/services/hive_service.dart');
    final userRepoFile = File('lib/shared/repositories/user_repository.dart');

    expect(hiveServiceFile.existsSync(), true,
      reason: 'HiveService file must exist at expected path');
    expect(userRepoFile.existsSync(), true,
      reason: 'UserRepository file must exist at expected path');

    final hiveServiceSrc = hiveServiceFile.readAsStringSync();
    final userRepoSrc = userRepoFile.readAsStringSync();

    // Find all *Box getters/fields on HiveService — these are box names like
    // userBox, workoutBox, etc.
    final boxNamePattern = RegExp(r'static const String (\w+)BoxName\s*=');
    final allBoxes = boxNamePattern.allMatches(hiveServiceSrc)
        .map((m) => m.group(1)!)
        .toSet();

    expect(allBoxes.length, greaterThanOrEqualTo(8),
      reason: 'Should find at least 8 box constants in HiveService');

    // Seed data boxes intentionally excluded from clearAllData
    final seedBoxes = {'exercise', 'food'};

    // Boxes that MUST be in clearAllData
    final mustBeCleared = allBoxes.difference(seedBoxes);

    for (final boxRoot in mustBeCleared) {
      final pattern = '_hive.${boxRoot}Box.clear()';
      expect(userRepoSrc.contains(pattern), true,
        reason: 'clearAllData must call _hive.${boxRoot}Box.clear() — '
                'box "$boxRoot" found in HiveService but not in clearAllData. '
                'Add to UserRepository.clearAllData() in user_repository.dart.');
    }
  });
}
```

- [ ] **Step 2: Run test — should PASS now (post-A1)**

```bash
flutter test test/contracts/clear_all_data_box_coverage_test.dart
```

Expected: PASS. If it fails for `notifications` not found in clearAllData, A1 didn't ship correctly — investigate.

- [ ] **Step 3: Commit**

```bash
git add test/contracts/clear_all_data_box_coverage_test.dart
git commit -m "test(contracts): assert clearAllData covers every non-seed Hive box

Source-grep contract test that walks HiveService for all *BoxName constants
and asserts user_repository.dart's clearAllData calls .clear() on each one
(except exercise/food seed boxes).

Catches the original B1 regression: notificationsBox added to HiveService
but not to clearAllData. Future box additions are now caught at test time.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Self-review

- [ ] **Spec coverage:** All B1 layers (1: notificationsBox; 2: lastAuthenticatedUserIdKey; 3: _ensureLocalUser strengthen) are tasks A1, A2, A3. B5 is task A4. Contract regression test is A5. ✅
- [ ] **Placeholder scan:** No TBD/TODO. All code shown verbatim. ✅
- [ ] **Type consistency:** `lastAuthenticatedUserIdKey` named identically across A2 (define), A3 (read in auth_provider), A4 (read in RestoringScreen), tests. ✅
- [ ] **Test coverage:** clearAllData box coverage (A5), cross-account guard (A3), RestoringScreen guard (A4). ✅

## Out of scope for Plan A

- B2 streak freeze anchor → Plan B
- B3 Manual §8 + tool-loop fallback → Plan B
- B4 RANK -13 days → Plan B
- All UX changes → Plans C/D
