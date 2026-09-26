# APK Test #15.4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Commit discipline note:** Per founder's CLAUDE.md global rule, every `git commit` step requires explicit founder approval at execution time. Plan-level approval does NOT cascade to commit-level approval. Pause before each commit step and confirm.

**Goal:** Close the cross-account Riverpod cache race (B1) and bridge muster answers into `userBox['profile']` (B2) so Edit Profile + plan generator see them. Ship as one batch.

**Architecture:** Two-layer fix for B1 — Layer A: read-side disagreement guard at `wrapUserScopedBox` returns an empty `GuardedBox` when Supabase auth uid ≠ `HiveUserSession.currentOwnerFullId`. Layer B: event-side rebuild trigger via `ValueNotifier<String?>` on `HiveUserSession` exposed through `hiveSessionOwnerProvider`; `authUserIdTokenProvider` returns `<anon>` until auth and Hive agree. B2 drops two essay questions from `MusterScreen`, converts Q5 to single-select matching `physique_focus` enum, and bridges every muster answer into `userBox['profile']` inside `InductionService.recordMusterAnswer`. Migration 063 adds `preferred_workout_time` to `user_profile`. One-shot backfill on `_ensureLocalUser` mirrors existing coachBox muster answers into profile defaults.

**Tech Stack:** Flutter (Riverpod, Hive, Supabase, GoRouter), Dart `flutter_test`, Supabase MCP for migration apply.

**Spec:** [`docs/superpowers/specs/2026-05-12-cross-account-race-and-muster-bridge-design.md`](../specs/2026-05-12-cross-account-race-and-muster-bridge-design.md)

---

## File Structure

### Created
- `lib/core/services/hive_session_owner_provider.dart` — Riverpod provider wrapping `HiveUserSession.currentOwnerListenable`.
- `supabase/migrations/063_add_preferred_workout_time.sql` — DDL for new profile column.
- `test/contracts/auth_invalidation_timing_test.dart` — disagreement-window token behaviour.
- `test/contracts/wrap_user_scoped_box_disagreement_test.dart` — `GuardedBox.empty` semantics.
- `test/contracts/muster_profile_bridge_test.dart` — coachBox + profile dual-write per muster key.
- `test/contracts/muster_question_count_test.dart` — MusterScreen renders exactly 3 questions.
- `test/contracts/muster_bridge_backfill_test.dart` — one-shot backfill idempotency + non-clobber.

### Modified
- `lib/core/services/hive_user_session.dart` — add `currentOwnerListenable`; set from 3 locked methods.
- `lib/core/services/guarded_box.dart` — add `GuardedBox.empty` factory + disagreement guard in `wrapUserScopedBox`.
- `lib/features/auth/providers/auth_invalidation_provider.dart` — rewire token to gate on agreement.
- `lib/features/ai_coach/screens/muster_screen.dart` — drop Q1+Q2; Q5 single-select.
- `lib/features/ai_coach/services/induction_service.dart` — `_bridgeToProfile` method.
- `lib/core/services/sync_service.dart` — `preferred_workout_time` in `_syncUserProfile` projection (line 2389 area).
- `lib/features/profile/screens/edit_profile_screen.dart` — `preferred_workout_time` picker tile.
- `lib/features/auth/providers/auth_provider.dart` — `_backfillMusterToProfileIfNeeded` call in `_ensureLocalUser`.
- `backups/applied_migrations.json` — append `"063"` entry.

### Not modified (called out for safety)
- The 56 user-scoped Riverpod providers from c4055a — they already watch `authUserIdTokenProvider`; rewiring the token gives them disagreement detection for free.
- `InductionService._allowedMusterKeys` — keep `why_now` + `definition_of_winning` so legacy reads don't throw.

---

## Phase 0: Branch setup

### Task 0.1: Create feature branch

**Files:** none (git only)

- [ ] **Step 1: Verify current state**

Run: `git status && git branch --show-current && git log --oneline -3`

Expected: clean working tree, branch `claude/brave-grothendieck-b61a0e` (or `main`), HEAD at `5c4cbbe chore(apk): record 1.0.0+23`.

- [ ] **Step 2: Create feature branch**

Run: `git checkout -b feat/apk-test-15-4-batch`

Expected: `Switched to a new branch 'feat/apk-test-15-4-batch'`.

If git refuses because the worktree's branch is locked, run `git checkout main` first, then create.

---

## Phase 1: Bug 1 — Cross-account Riverpod cache race

### Task 1.1: Add observable listenable to HiveUserSession

**Files:**
- Modify: `lib/core/services/hive_user_session.dart`

- [ ] **Step 1: Add the listenable field**

Open `lib/core/services/hive_user_session.dart`. Above the existing `static String? _currentOwnerHash;` field (line ~39), add:

```dart
/// APK Test #15.4 / B1 Layer B — observable mirror of
/// [_currentOwnerFullId]. Flutter `ValueNotifier` so Riverpod's
/// `hiveSessionOwnerProvider` can watch it without polling.
///
/// Mutated under [_sessionLock] from [_openForUserLocked],
/// [_closeAllLocked], and [_deleteAllFilesForCurrentUserLocked].
/// Always reflects the latest value of [_currentOwnerFullId].
///
/// Test code may NOT mutate this directly — go through the three
/// locked methods so the lock invariant is preserved.
static final ValueNotifier<String?> currentOwnerListenable =
    ValueNotifier<String?>(null);
```

- [ ] **Step 2: Add the `flutter/foundation.dart` import**

At the top of the file (after the existing `dart:async` + `package:hive_flutter/hive_flutter.dart` imports), confirm or add:

```dart
import 'package:flutter/foundation.dart';
```

(File already imports it on line 3 — verify with Grep, don't duplicate.)

- [ ] **Step 3: Mutate listenable from `_openForUserLocked`**

In `_openForUserLocked`, find the existing line:
```dart
_currentOwnerHash = hash;
_currentOwnerFullId = userId;
```
(line ~165-166)

Immediately after, add:

```dart
// APK Test #15.4 / B1 Layer B — mirror static field into listenable
// so Riverpod providers re-emit. Mutated under _sessionLock.
currentOwnerListenable.value = userId;
```

- [ ] **Step 4: Mutate listenable from `_closeAllLocked`**

In `_closeAllLocked`, find:
```dart
_currentOwnerHash = null;
_currentOwnerFullId = null;
```
(line ~349-350)

Immediately after, add:

```dart
// APK Test #15.4 / B1 Layer B — mirror cleared state.
currentOwnerListenable.value = null;
```

- [ ] **Step 5: Mutate listenable from `_deleteAllFilesForCurrentUserLocked`**

In `_deleteAllFilesForCurrentUserLocked`, find:
```dart
_currentOwnerHash = null;
_currentOwnerFullId = null;
```
(line ~385-386)

Immediately after, add:

```dart
// APK Test #15.4 / B1 Layer B — mirror cleared state.
currentOwnerListenable.value = null;
```

- [ ] **Step 6: Run analyzer to catch typos**

Run: `flutter analyze lib/core/services/hive_user_session.dart`

Expected: `No issues found!` (or warnings unrelated to the listenable).

- [ ] **Step 7: Pause for commit approval**

Ask founder: *"Commit Phase 1.1 — add ValueNotifier to HiveUserSession + mirror writes from 3 locked methods?"* Wait for approval before running:

```bash
git add lib/core/services/hive_user_session.dart
git commit -m "$(cat <<'EOF'
feat(hive): observable currentOwnerListenable on HiveUserSession

B1 Layer B foundation. Riverpod consumers (next task) can watch the
listenable to re-emit when the box owner actually swaps. Mutated under
_sessionLock from openForUser/closeAll/deleteAllFilesForCurrentUser so
the listenable can never disagree with _currentOwnerFullId.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 1.2: New hiveSessionOwnerProvider

**Files:**
- Create: `lib/core/services/hive_session_owner_provider.dart`

- [ ] **Step 1: Create the provider file**

Write to `lib/core/services/hive_session_owner_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'hive_user_session.dart';

/// Riverpod wrapper around [HiveUserSession.currentOwnerListenable].
///
/// Returns the current Hive owner's full user.id, or `null` when no
/// user-scoped boxes are open (cold start before sign-in, post-sign-out
/// before next sign-in).
///
/// Consumers watching this rebuild automatically when the listenable
/// fires (i.e. when `openForUser` or `closeAll` finishes mutating
/// `_currentOwnerFullId`).
///
/// Used by `authUserIdTokenProvider` to gate on agreement between
/// Supabase auth and Hive box owner. See APK Test #15.4 / B1 Layer B.
final hiveSessionOwnerProvider = Provider<String?>((ref) {
  final notifier = HiveUserSession.currentOwnerListenable;
  void listener() => ref.invalidateSelf();
  notifier.addListener(listener);
  ref.onDispose(() => notifier.removeListener(listener));
  return notifier.value;
});
```

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze lib/core/services/hive_session_owner_provider.dart`

Expected: `No issues found!`.

- [ ] **Step 3: Pause for commit approval**

Ask founder. On approval:

```bash
git add lib/core/services/hive_session_owner_provider.dart
git commit -m "$(cat <<'EOF'
feat(state): hiveSessionOwnerProvider exposes HiveUserSession to Riverpod

B1 Layer B. Wraps HiveUserSession.currentOwnerListenable as a Provider
so consumers re-emit when the box owner swaps. Used next by
authUserIdTokenProvider to detect auth/Hive disagreement.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 1.3: Failing test — token disagreement returns `<anon>`

**Files:**
- Create: `test/contracts/auth_invalidation_timing_test.dart`

- [ ] **Step 1: Write the failing test**

Write to `test/contracts/auth_invalidation_timing_test.dart`:

```dart
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/hive_session_owner_provider.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';

void main() {
  // Reset the static listenable between tests so cross-test leakage can't
  // give a false pass.
  setUp(() {
    HiveUserSession.currentOwnerListenable.value = null;
  });

  tearDown(() {
    HiveUserSession.currentOwnerListenable.value = null;
  });

  test('token returns <anon> when authUid and hiveOwner disagree', () {
    // Simulate: Supabase has flipped to sumitId but openForUser hasn't
    // caught up yet — Hive still owned by upendraId.
    HiveUserSession.currentOwnerListenable.value = 'upendra-id-aaaa-bbbb';

    final container = ProviderContainer(overrides: [
      // Pretend Supabase says sumit.
      currentUserProvider.overrideWithValue(_FakeUser('sumit-id-cccc-dddd')),
      // authStateProvider is a StreamProvider — override with a finished
      // stream so it doesn't error out under test.
      authStateProvider.overrideWith((ref) => const Stream.empty()),
    ]);
    addTearDown(container.dispose);

    final token = container.read(authUserIdTokenProvider);
    expect(token, '<anon>',
        reason: 'Disagreement must produce <anon>, not the auth uid.');
  });

  test('token returns authUid when authUid and hiveOwner agree', () {
    HiveUserSession.currentOwnerListenable.value = 'sumit-id-cccc-dddd';

    final container = ProviderContainer(overrides: [
      currentUserProvider.overrideWithValue(_FakeUser('sumit-id-cccc-dddd')),
      authStateProvider.overrideWith((ref) => const Stream.empty()),
    ]);
    addTearDown(container.dispose);

    final token = container.read(authUserIdTokenProvider);
    expect(token, 'sumit-id-cccc-dddd');
  });

  test('token flips from <anon> to authUid when openForUser completes', () async {
    HiveUserSession.currentOwnerListenable.value = 'upendra-id-aaaa-bbbb';

    final container = ProviderContainer(overrides: [
      currentUserProvider.overrideWithValue(_FakeUser('sumit-id-cccc-dddd')),
      authStateProvider.overrideWith((ref) => const Stream.empty()),
    ]);
    addTearDown(container.dispose);

    expect(container.read(authUserIdTokenProvider), '<anon>');

    // Simulate openForUser completing — listenable flips.
    HiveUserSession.currentOwnerListenable.value = 'sumit-id-cccc-dddd';
    // Pump microtasks so the listener can fire and providers re-emit.
    await Future<void>.delayed(Duration.zero);

    expect(container.read(authUserIdTokenProvider), 'sumit-id-cccc-dddd');
  });
}

/// Minimal fake matching only the `.id` accessor used by
/// `authUserIdTokenProvider`. Avoids pulling Supabase's full User class
/// into the test.
class _FakeUser implements Object {
  _FakeUser(this.id);
  final String id;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #id) return id;
    return super.noSuchMethod(invocation);
  }
}
```

Note: `_FakeUser` uses `noSuchMethod` because the real `User` from supabase_flutter has many fields. We override the provider type via `overrideWithValue` which Riverpod accepts as long as `.id` works. If the compiler rejects the override because of strict type checks, the alternate approach is to use a `Override.provider` mock. The TDD steps below verify with `expect`, not compilation tricks — if Step 2's failure mode reveals a type problem, the fallback is to mock `currentUserProvider` with a `Provider.overrideWith((ref) => _FakeUser(...) as User)`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/contracts/auth_invalidation_timing_test.dart -r expanded`

Expected: tests FAIL because `authUserIdTokenProvider` currently doesn't watch `hiveSessionOwnerProvider`. The current implementation returns `user?.id ?? '<anon>'` based on auth alone — so in the first test it would return `'sumit-id-cccc-dddd'` instead of `'<anon>'`.

If the test fails to compile because `_FakeUser` doesn't satisfy `User`, replace the `currentUserProvider.overrideWithValue(_FakeUser(...))` line with:

```dart
currentUserProvider.overrideWith((ref) => _FakeUser('sumit-id-cccc-dddd') as dynamic),
```

Re-run; the test should now fail at the `expect` line, not at compile time.

### Task 1.4: Rewire authUserIdTokenProvider

**Files:**
- Modify: `lib/features/auth/providers/auth_invalidation_provider.dart`

- [ ] **Step 1: Update the provider**

Open `lib/features/auth/providers/auth_invalidation_provider.dart`. Replace the entire `authUserIdTokenProvider` definition (lines 25-31) with:

```dart
import 'package:icanbefitter/core/services/hive_session_owner_provider.dart';

final authUserIdTokenProvider = Provider<String>((ref) {
  // Subscribe to the auth state stream so this provider rebuilds on every
  // sign-in / sign-out / token refresh.
  ref.watch(authStateProvider);
  final authUid = ref.watch(currentUserProvider)?.id;

  // APK Test #15.4 / B1 Layer B — gate on agreement with HiveUserSession.
  // Auth-state-changed alone is not the moment user-scoped Hive becomes
  // safe to read. _ensureLocalUser awaits openForUser AFTER auth fires,
  // so this provider returns '<anon>' until the listenable confirms the
  // box swap completed for the same user id.
  //
  // Cold start: hiveOwner is set by splash bootstrap before UI mounts →
  // agreement on first read → token = authUid.
  // Live signOut+signUp: hiveOwner lags auth by a tick → token = '<anon>'
  // → 56 user-scoped providers render empty for ~100ms → listenable
  // fires when openForUser completes → token = authUid → providers
  // re-render with correctly-namespaced data.
  final hiveOwner = ref.watch(hiveSessionOwnerProvider);
  if (authUid == null || hiveOwner == null || authUid != hiveOwner) {
    return '<anon>';
  }
  return authUid;
});
```

Place the `import` line at the top of the file alongside the existing imports.

- [ ] **Step 2: Run the failing test — now passes**

Run: `flutter test test/contracts/auth_invalidation_timing_test.dart -r expanded`

Expected: all 3 tests PASS.

- [ ] **Step 3: Run full analyzer**

Run: `flutter analyze lib/features/auth/ lib/core/services/`

Expected: `No issues found!`.

- [ ] **Step 4: Pause for commit approval**

Ask founder. On approval:

```bash
git add lib/features/auth/providers/auth_invalidation_provider.dart test/contracts/auth_invalidation_timing_test.dart
git commit -m "$(cat <<'EOF'
fix(state): authUserIdTokenProvider gates on HiveUserSession agreement

B1 Layer B. authStateProvider fires the moment Supabase emits signedIn,
but _ensureLocalUser awaits openForUser AFTER that — so providers were
rebuilding against the previous user's namespaced Hive for ~100ms and
caching the wrong data.

Token now returns '<anon>' until Supabase authUid matches HiveUserSession
owner. The 56 user-scoped providers already watch this token (from
c4055a) — they automatically benefit from the new gate.

Contract test pins: disagreement -> '<anon>', agreement -> authUid,
listenable flip triggers re-emit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 1.5: Failing test — wrapUserScopedBox returns empty on disagreement

**Files:**
- Create: `test/contracts/wrap_user_scoped_box_disagreement_test.dart`

- [ ] **Step 1: Write the failing test**

Write to `test/contracts/wrap_user_scoped_box_disagreement_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;

  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

void main() {
  late String tmpDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmpDir = Directory.systemTemp.createTempSync('apk154_').path;
    PathProviderPlatform.instance = _FakePathProvider(tmpDir);
    Hive.init(tmpDir);
  });

  setUp(() async {
    HiveUserSession.currentOwnerListenable.value = null;
  });

  tearDown(() async {
    await Hive.close();
    HiveUserSession.currentOwnerListenable.value = null;
  });

  test('GuardedBox.empty returns null on get and throws on put', () async {
    final empty = GuardedBox<dynamic>.empty('some-auth-uid');
    expect(empty.get('any_key'), isNull);
    expect(empty.length, 0);
    expect(empty.keys, isEmpty);
    expect(empty.isEmpty, isTrue);
    expect(empty.isNotEmpty, isFalse);
    expect(() => empty.put('k', 'v'), throwsA(isA<StateError>()));
    expect(() => empty.delete('k'), throwsA(isA<StateError>()));
  });
}
```

Note: this test asserts the `.empty` factory's contract. The cross-account fallback path inside `wrapUserScopedBox` is covered by an integration smoke later (Task 6.2 manual verification).

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/contracts/wrap_user_scoped_box_disagreement_test.dart -r expanded`

Expected: FAIL — `GuardedBox.empty` factory doesn't exist yet.

### Task 1.6: Implement GuardedBox.empty factory

**Files:**
- Modify: `lib/core/services/guarded_box.dart`

- [ ] **Step 1: Add the empty factory**

Open `lib/core/services/guarded_box.dart`. Inside the `GuardedBox<T>` class, immediately after the existing constructor `GuardedBox(this._box, this._ownerHash, this._ownerFullId);` (line 34), add:

```dart
/// APK Test #15.4 / B1 Layer A — null-object factory used during the
/// auth/Hive disagreement window. All read methods return null/empty
/// without touching disk; all writes throw [StateError] so inflight
/// fire-and-forget syncs fail loudly instead of leaking into the wrong
/// box.
///
/// Returned from [wrapUserScopedBox] when Supabase's current user.id
/// disagrees with [HiveUserSession.currentOwnerFullId].
factory GuardedBox.empty(String pendingAuthUid) {
  return GuardedBox<T>._empty(pendingAuthUid);
}

GuardedBox._empty(this._ownerFullId)
    : _box = _EmptyBoxStub(),
      _ownerHash =
          _ownerFullId.replaceAll('-', '').padRight(8, '0').substring(0, 8),
      _isEmptyStub = true;

final bool _isEmptyStub;
```

Wait — the existing class declares `final Box _box;` etc. as final fields initialised in the main constructor. Adding `_isEmptyStub` requires it be final too. Restructure: change the existing constructor signature to also initialise `_isEmptyStub = false`. Replace the first constructor block (lines 33-38) with:

```dart
class GuardedBox<T> {
  GuardedBox(this._box, this._ownerHash, this._ownerFullId)
      : _isEmptyStub = false;

  /// APK Test #15.4 / B1 Layer A — null-object factory used during the
  /// auth/Hive disagreement window. All read methods return null/empty
  /// without touching disk; all writes throw [StateError] so inflight
  /// fire-and-forget syncs fail loudly instead of leaking into the wrong
  /// box.
  ///
  /// Returned from [wrapUserScopedBox] when Supabase's current user.id
  /// disagrees with [HiveUserSession.currentOwnerFullId].
  factory GuardedBox.empty(String pendingAuthUid) {
    return GuardedBox<T>._empty(pendingAuthUid);
  }

  GuardedBox._empty(String pendingAuthUid)
      : _box = _EmptyBoxStub(),
        _ownerHash = pendingAuthUid.replaceAll('-', '').padRight(8, '0').substring(0, 8),
        _ownerFullId = pendingAuthUid,
        _isEmptyStub = true;

  final Box _box;
  final String _ownerHash;
  final String _ownerFullId;
  final bool _isEmptyStub;
```

Then update every read method to short-circuit on `_isEmptyStub` and every write to throw. Replace each method body. Find the `_assertOwnership()` call at the start of each method and prefix it with the stub check. For reads:

```dart
T? get(dynamic key, {T? defaultValue}) {
  if (_isEmptyStub) return defaultValue;
  _assertOwnership();
  return _box.get(key, defaultValue: defaultValue) as T?;
}
```

For writes:

```dart
Future<void> put(dynamic key, T value) async {
  if (_isEmptyStub) {
    throw StateError(
      'GuardedBox.empty: refusing write during auth/Hive disagreement window',
    );
  }
  _assertOwnership();
  await _box.put(key, value);
}
```

Apply the same pattern to: `put`, `putAll`, `delete`, `deleteAll`, `clear` (writes throw); `get`, `keys`, `values`, `containsKey`, `length`, `isEmpty`, `isNotEmpty`, `rawBox` (reads return null/empty/0/true/false).

For `rawBox`, throw — callers using it for `ValueListenableBuilder` must not silently get a stub:

```dart
Box get rawBox {
  if (_isEmptyStub) {
    throw StateError(
      'GuardedBox.empty: rawBox unavailable during auth/Hive disagreement',
    );
  }
  _assertOwnership();
  return _box;
}
```

Specific overrides (return values to use):
- `keys` → `const <dynamic>[]`
- `values` → `const Iterable<Never>.empty().cast<T>()` — actually use `const Iterable<dynamic>.empty().cast<T>()` (Dart requires the cast)
- `containsKey` → `false`
- `length` → `0`
- `isEmpty` → `true`
- `isNotEmpty` → `false`

- [ ] **Step 2: Add `_EmptyBoxStub` helper**

At the bottom of `guarded_box.dart`, before the `wrapUserScopedBox` function, add:

```dart
/// Internal Hive [Box] placeholder used by [GuardedBox._empty]. Never
/// reached by any read/write because [GuardedBox] short-circuits before
/// delegating. Exists only to satisfy the `final Box _box;` non-null
/// constraint.
class _EmptyBoxStub implements Box<dynamic> {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw StateError(
      '_EmptyBoxStub: should never be invoked — GuardedBox.empty must '
      'short-circuit before delegating to _box.',
    );
  }
}
```

- [ ] **Step 3: Run the empty-factory test**

Run: `flutter test test/contracts/wrap_user_scoped_box_disagreement_test.dart -r expanded`

Expected: PASS.

- [ ] **Step 4: Run analyzer**

Run: `flutter analyze lib/core/services/guarded_box.dart`

Expected: `No issues found!`. If analyzer complains about `Iterable<Never>.empty()`, switch to `Iterable<T>.empty()`.

- [ ] **Step 5: Verify no existing tests broken**

Run: `flutter test test/safety/ test/contracts/`

Expected: all green. The existing `GuardedBox` tests use the main constructor — they shouldn't notice the new branch.

- [ ] **Step 6: Pause for commit approval**

Ask founder. On approval:

```bash
git add lib/core/services/guarded_box.dart test/contracts/wrap_user_scoped_box_disagreement_test.dart
git commit -m "$(cat <<'EOF'
feat(state): GuardedBox.empty null-object for disagreement window

B1 Layer A foundation. New factory returns a GuardedBox that short-
circuits reads to null/empty and throws on writes. Next task wires it
into wrapUserScopedBox so the disagreement window can't leak prior
user's data into the new session.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 1.7: Wire disagreement guard into wrapUserScopedBox

**Files:**
- Modify: `lib/core/services/guarded_box.dart` (the `wrapUserScopedBox` function at line ~162)

- [ ] **Step 1: Add the disagreement check**

Open `lib/core/services/guarded_box.dart`. In `wrapUserScopedBox<T>(String root)`, at the very top of the function body before the existing `var fullId = HiveUserSession.currentOwnerFullId;` line, add:

```dart
GuardedBox<T> wrapUserScopedBox<T>(String root) {
  // APK Test #15.4 / B1 Layer A — disagreement guard.
  // If Supabase has a user but Hive owner is different (or null), refuse
  // to serve data. The race window is short (~50–500ms during
  // signOut+signUp transitions) — during it, providers get an empty box
  // and render an empty state. Layer B's hiveSessionOwnerProvider
  // triggers a rebuild as soon as openForUser completes.
  String? supabaseAuthUid;
  try {
    supabaseAuthUid = Supabase.instance.client.auth.currentUser?.id;
  } catch (_) {
    // Supabase not initialised — fall through to existing logic.
  }
  final hiveOwner = HiveUserSession.currentOwnerFullId;
  if (supabaseAuthUid != null &&
      hiveOwner != null &&
      supabaseAuthUid != hiveOwner) {
    unawaited(ErrorTelemetry.logEvent(
      'guarded_box_disagreement',
      message:
          'root=$root authUid=${supabaseAuthUid.substring(0, 8)} '
          'hiveOwner=${hiveOwner.substring(0, 8)}',
    ));
    return GuardedBox<T>.empty(supabaseAuthUid);
  }

  // ── existing cold-start fallback path follows ──
  var fullId = HiveUserSession.currentOwnerFullId;
  var hash = HiveUserSession.currentOwnerHash;
  // ... rest of existing function unchanged
```

Keep every line of the existing function below `var fullId = ...`. The new guard sits ahead of it.

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze lib/core/services/guarded_box.dart`

Expected: `No issues found!`.

- [ ] **Step 3: Re-run full contract tests**

Run: `flutter test test/contracts/`

Expected: all green. The new guard doesn't fire in unit tests because they typically don't have a Supabase session active.

- [ ] **Step 4: Pause for commit approval**

Ask founder. On approval:

```bash
git add lib/core/services/guarded_box.dart
git commit -m "$(cat <<'EOF'
fix(state): wrapUserScopedBox returns empty on auth/Hive disagreement

B1 Layer A complete. When Supabase auth.currentUser.id != HiveUserSession
.currentOwnerFullId (the live signOut+signUp race window), return
GuardedBox.empty so reads serve null and writes throw StateError. Pairs
with B1 Layer B (hiveSessionOwnerProvider) — A is correctness, B is
liveness.

Telemetry event 'guarded_box_disagreement' fires per disagreement so we
can measure how often the race actually hits production.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 2: Bug 2a + 2d — MusterScreen surgery (drop Q1/Q2, Q5 single-select)

### Task 2.1: Failing test — MusterScreen renders 3 questions

**Files:**
- Create: `test/contracts/muster_question_count_test.dart`

- [ ] **Step 1: Write the failing test**

Write to `test/contracts/muster_question_count_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/screens/muster_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tmp = Directory.systemTemp.createTempSync('muster_count_').path;
    PathProviderPlatform.instance = _FakePathProvider(tmp);
    Hive.init(tmp);
    await Hive.openBox(HiveService.coachBoxName);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
  });

  tearDown(() async {
    await HiveService.instance.coachBox.clear();
  });

  testWidgets('MusterScreen renders exactly 3 progress dots', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: MusterScreen()),
      ),
    );

    // Wait for the typing indicator to finish (1100ms).
    await tester.pump(const Duration(milliseconds: 1200));

    // The progress bar uses Expanded children, one per question. Count them.
    final progressContainers = find.descendant(
      of: find.byType(MusterScreen),
      matching: find.byWidgetPredicate(
        (w) => w is Container &&
            w.decoration is BoxDecoration &&
            (w.constraints?.maxHeight == 3 || (w.decoration as BoxDecoration?)?.borderRadius != null && w.padding == null),
      ),
    );

    // Looser assertion: progress row has exactly 3 Expanded children.
    final expandedInProgress = find.descendant(
      of: find.byType(Row).first,
      matching: find.byType(Expanded),
    );
    expect(expandedInProgress, findsNWidgets(3),
        reason: 'Progress bar must show exactly 3 dots, one per remaining muster question.');
  });

  testWidgets('First question prompt is the injuries question', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: MusterScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1200));

    expect(find.textContaining('injuries or niggles'), findsOneWidget,
        reason: 'After dropping Q1+Q2, the first question must be injuries.');
    expect(find.textContaining('Why now'), findsNothing,
        reason: 'why_now question must be removed.');
    expect(find.textContaining('winning look'), findsNothing,
        reason: 'definition_of_winning question must be removed.');
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/contracts/muster_question_count_test.dart -r expanded`

Expected: tests FAIL because MusterScreen currently has 5 questions and Q1 prompt is "Why now?...".

### Task 2.2: Drop Q1 + Q2 from MusterScreen

**Files:**
- Modify: `lib/features/ai_coach/screens/muster_screen.dart`

- [ ] **Step 1: Remove Q1/Q2 controllers**

In `_MusterScreenState`, delete these field declarations (lines 33-37):

```dart
// Q1
final _whyNowCtrl = TextEditingController();
// Q2
final _winningCtrl = TextEditingController();
```

Keep the rest of the controllers (`_injuriesCtrl`, `_wakeTime`, `_workoutTime`, `_bodyParts`).

- [ ] **Step 2: Remove their disposes**

In the `dispose()` method (lines 73-79), remove:

```dart
_whyNowCtrl.dispose();
_winningCtrl.dispose();
```

Leave `_injuriesCtrl.dispose()`.

- [ ] **Step 3: Remove _onSubmitQ1 + _onSubmitQ2 methods**

Delete `_onSubmitQ1` (lines 83-91) and `_onSubmitQ2` (lines 93-101) entirely.

- [ ] **Step 4: Remove _buildQ1 + _buildQ2 widgets**

Delete `_buildQ1` (lines 267-285) and `_buildQ2` (lines 289-308) entirely.

- [ ] **Step 5: Renumber switch and progress bar**

In `_buildCurrentQ` (lines 226-241), replace the switch with:

```dart
Widget _buildCurrentQ() {
  switch (_qIdx) {
    case 0:
      return _buildQ3();  // injuries (now first)
    case 1:
      return _buildQ4();  // wake/workout time
    case 2:
      return _buildQ5();  // body part focus (single-select after Task 2.3)
    default:
      return const SizedBox.shrink();
  }
}
```

In `_buildProgress` (lines 208-224), replace `List.generate(5, ...)` with `List.generate(3, ...)`:

```dart
Widget _buildProgress() {
  return Row(
    children: List.generate(3, (i) {
      final filled = i <= _qIdx;
      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          height: 3,
          decoration: BoxDecoration(
            color: filled ? AppColors.accent : AppColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
    }),
  );
}
```

- [ ] **Step 6: Update _onSubmitQ3 / _onSubmitQ4 to advance to next index**

`_onSubmitQ3` currently calls `_showTypingThen(3)` (advancing to old Q4). With the new numbering, Q3 is now index 0 and the next question (Q4 → wake) is index 1:

```dart
Future<void> _onSubmitQ3({bool skipped = false}) async {
  // ... existing injuries logic ...
  await InductionService.instance.recordMusterAnswer('known_injuries', injuries);
  await _showTypingThen(1);  // was _showTypingThen(3) — renumbered to index 1
}
```

`_onSubmitQ4` currently calls `_showTypingThen(4)` — change to `_showTypingThen(2)`:

```dart
Future<void> _onSubmitQ4() async {
  // ... existing wake/workout logic ...
  await _showTypingThen(2);  // was _showTypingThen(4) — renumbered to index 2
}
```

- [ ] **Step 7: Run the failing test from Task 2.1**

Run: `flutter test test/contracts/muster_question_count_test.dart -r expanded`

Expected: both tests now PASS. If the dot count test fails because the Row layout is different than expected, inspect the rendered widget tree with `tester.printToConsole()` and adjust the matcher.

- [ ] **Step 8: Pause for commit approval**

Ask founder. On approval:

```bash
git add lib/features/ai_coach/screens/muster_screen.dart test/contracts/muster_question_count_test.dart
git commit -m "$(cat <<'EOF'
refactor(muster): drop why_now and definition_of_winning questions

B2a. Per founder direction — these two essay questions added high
friction with low AI-context value. Renumbered remaining 3 questions
(injuries, wake/workout time, body parts). Progress bar shows 3 dots.

coach_memory columns and _allowedMusterKeys retained so legacy data
still round-trips. Cloud schema not touched.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 2.3: Q5 single-select matching physique_focus enum

**Files:**
- Modify: `lib/features/ai_coach/screens/muster_screen.dart`

- [ ] **Step 1: Replace _bodyPartOptions with physique_focus enum values**

In `_MusterScreenState`, replace `_bodyPartOptions` (lines 45-54) and `Set<String> _bodyParts = {}` (line 43) with:

```dart
// Q5 — single-select matching profile.physique_focus enum
// (see edit_profile_screen.dart _buildPhysiqueFocusSelector line ~980).
static const _physiqueFocusOptions = <(String, String)>[
  ('balanced', 'Balanced — all-round'),
  ('glutes_legs', 'Glutes & Legs'),
  ('chest_shoulders_arms', 'Chest, Shoulders & Arms'),
  ('strength', 'Strength — heavy compounds'),
];
String? _physiqueFocus;
```

- [ ] **Step 2: Replace _toggleBodyPart with _setPhysiqueFocus**

Delete `_toggleBodyPart` (lines 483-498). Add:

```dart
void _setPhysiqueFocus(String key) {
  setState(() => _physiqueFocus = key);
}
```

- [ ] **Step 3: Update _onSubmitQ5**

Replace `_onSubmitQ5` (lines 135-141) with:

```dart
Future<void> _onSubmitQ5() async {
  if (_physiqueFocus == null) {
    _toast('Pick one focus, Recruit.');
    return;
  }
  // Wrap single value in 1-element List so the existing coachBox key
  // shape (List<String>) is preserved. ai_coach_repository reads this
  // as `(coach.get('body_part_priorities') as List?) ?? const <String>[]`
  // — no consumer change needed.
  await InductionService.instance.recordMusterAnswer(
    'body_part_priorities',
    [_physiqueFocus!],
  );
  await _completeMuster();
}
```

- [ ] **Step 4: Update _buildQ5 to render single-select chips**

Replace `_buildQ5` (lines 437-481) with:

```dart
Widget _buildQ5() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _buildBubble(
          'Where do you want to put extra emphasis? Pick one — your plan '
          'will weight that area.'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _physiqueFocusOptions.map((opt) {
          final selected = _physiqueFocus == opt.$1;
          return GestureDetector(
            onTap: () => _setPhysiqueFocus(opt.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? AppColors.accent : AppColors.card,
                border: Border.all(
                  color: selected ? AppColors.accent : AppColors.border,
                ),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                opt.$2,
                style: TextStyle(
                  color: selected ? AppColors.bgDeep : Colors.white,
                  fontWeight:
                      selected ? FontWeight.w800 : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }).toList(),
      ),
      const SizedBox(height: 16),
      WardButton(
        label: 'COMPLETE MUSTER',
        onPressed: _physiqueFocus == null ? null : _onSubmitQ5,
      ),
    ],
  );
}
```

- [ ] **Step 5: Run analyzer**

Run: `flutter analyze lib/features/ai_coach/screens/muster_screen.dart`

Expected: `No issues found!`.

- [ ] **Step 6: Re-run muster_question_count_test**

Run: `flutter test test/contracts/muster_question_count_test.dart -r expanded`

Expected: still passes.

- [ ] **Step 7: Pause for commit approval**

Ask founder. On approval:

```bash
git add lib/features/ai_coach/screens/muster_screen.dart
git commit -m "$(cat <<'EOF'
refactor(muster): Q5 single-select matching physique_focus enum

B2d. Replaced 8-chip multi-select body parts with 4-chip single-select
matching profile.physique_focus values (balanced / glutes_legs /
chest_shoulders_arms / strength). Stored as 1-element List in coachBox
key body_part_priorities so AI context reader shape is preserved.
Enables identity 1:1 bridge to profile (next task).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 3: Bug 2b — Bridge muster answers into userBox['profile']

### Task 3.1: Failing test — bridge writes both buckets

**Files:**
- Create: `test/contracts/muster_profile_bridge_test.dart`

- [ ] **Step 1: Write the failing test**

Write to `test/contracts/muster_profile_bridge_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/services/induction_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tmp = Directory.systemTemp.createTempSync('muster_bridge_').path;
    PathProviderPlatform.instance = _FakePathProvider(tmp);
    Hive.init(tmp);
    await Hive.openBox(HiveService.userBoxName);
    await Hive.openBox(HiveService.coachBoxName);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
  });

  setUp(() async {
    await HiveService.instance.userBox.clear();
    await HiveService.instance.coachBox.clear();
    // Seed a minimal profile so updateProfileFields doesn't error.
    await UserRepository.instance.saveProfile({'id': 'test-uid'});
  });

  test('known_injuries → profile.injuries', () async {
    await InductionService.instance
        .recordMusterAnswer('known_injuries', ['shoulders', 'lower back']);

    expect(HiveService.instance.coachBox.get('known_injuries'),
        ['shoulders', 'lower back']);
    final profile = UserRepository.instance.getProfile()!;
    expect(profile['injuries'], ['shoulders', 'lower back']);
  });

  test('typical_wake_time → profile.wake_up_time', () async {
    await InductionService.instance
        .recordMusterAnswer('typical_wake_time', '06:30');

    expect(HiveService.instance.coachBox.get('typical_wake_time'), '06:30');
    expect(UserRepository.instance.getProfile()!['wake_up_time'], '06:30');
  });

  test('preferred_workout_time → profile.preferred_workout_time', () async {
    await InductionService.instance
        .recordMusterAnswer('preferred_workout_time', '07:15');

    expect(HiveService.instance.coachBox.get('preferred_workout_time'),
        '07:15');
    expect(UserRepository.instance.getProfile()!['preferred_workout_time'],
        '07:15');
  });

  test('body_part_priorities single → profile.physique_focus', () async {
    await InductionService.instance
        .recordMusterAnswer('body_part_priorities', ['glutes_legs']);

    expect(HiveService.instance.coachBox.get('body_part_priorities'),
        ['glutes_legs']);
    expect(UserRepository.instance.getProfile()!['physique_focus'],
        'glutes_legs');
  });

  test('body_part_priorities multi (legacy) → no profile write', () async {
    // Pre-B2d data shape: 2+ elements. Bridge must skip to avoid
    // arbitrary picks.
    await UserRepository.instance
        .updateProfileFields({'physique_focus': 'balanced'});
    await InductionService.instance
        .recordMusterAnswer('body_part_priorities', ['legs', 'glutes']);

    expect(HiveService.instance.coachBox.get('body_part_priorities'),
        ['legs', 'glutes']);
    // Profile field stays at the pre-existing value — no fuzzy guess.
    expect(UserRepository.instance.getProfile()!['physique_focus'],
        'balanced');
  });

  test('why_now / definition_of_winning → no profile write', () async {
    await InductionService.instance
        .recordMusterAnswer('why_now', 'October wedding');
    await InductionService.instance
        .recordMusterAnswer('definition_of_winning', 'Feel strong');

    expect(HiveService.instance.coachBox.get('why_now'), 'October wedding');
    expect(HiveService.instance.coachBox.get('definition_of_winning'),
        'Feel strong');
    final profile = UserRepository.instance.getProfile()!;
    // No bridged fields landed.
    expect(profile['injuries'], isNull);
    expect(profile['wake_up_time'], isNull);
    expect(profile['preferred_workout_time'], isNull);
    expect(profile['physique_focus'], isNull);
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/contracts/muster_profile_bridge_test.dart -r expanded`

Expected: all 4 bridge-write tests FAIL because `InductionService.recordMusterAnswer` only writes to coachBox today. The "no profile write" tests should PASS (no-op already correct).

### Task 3.2: Implement _bridgeToProfile in InductionService

**Files:**
- Modify: `lib/features/ai_coach/services/induction_service.dart`

- [ ] **Step 1: Add imports**

At the top of `lib/features/ai_coach/services/induction_service.dart`, add:

```dart
import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
```

- [ ] **Step 2: Replace recordMusterAnswer body**

Replace the existing `recordMusterAnswer` method (lines 46-52) with:

```dart
/// Records a single muster answer to [HiveService.coachBox] AND bridges
/// the value to [userBox['profile']] for keys that map to profile
/// fields. Per CLAUDE.md §15 "Source of Truth Rules" — the muster is
/// the SoT for these facts; profile reads from a mirrored copy so Edit
/// Profile and plan generator see the values.
///
/// Throws [ArgumentError] on unknown key. Profile-bridge failures are
/// logged via [ErrorTelemetry] but do not throw — the coachBox write
/// already succeeded; the bridge re-runs on next attempt.
Future<void> recordMusterAnswer(String key, dynamic value) async {
  if (!_allowedMusterKeys.contains(key)) {
    throw ArgumentError('Unknown muster key: $key');
  }
  await HiveService.instance.coachBox.put(key, value);

  // B2b — bridge into userBox['profile'].
  try {
    await _bridgeToProfile(key, value);
  } catch (e, st) {
    debugPrint('[InductionService._bridgeToProfile] $key failed: $e');
    unawaited(ErrorTelemetry.recordNonFatal(e, st,
        reason: 'muster_bridge_to_profile'));
  }
}

Future<void> _bridgeToProfile(String musterKey, dynamic value) async {
  final Map<String, dynamic> fields;
  switch (musterKey) {
    case 'known_injuries':
      fields = {'injuries': (value as List).cast<String>()};
    case 'typical_wake_time':
      fields = {'wake_up_time': value as String};
    case 'preferred_workout_time':
      fields = {'preferred_workout_time': value as String};
    case 'body_part_priorities':
      final v = (value as List).cast<String>();
      // Only bridge single-select (B2d). Multi-select legacy data
      // (length > 1) is left in coachBox without a fuzzy guess.
      if (v.length != 1) return;
      fields = {'physique_focus': v.first};
    default:
      // why_now / definition_of_winning — no profile mapping.
      return;
  }

  await UserRepository.instance.updateProfileFields(fields);

  final uid = SupabaseService.instance.currentUser?.id;
  if (uid != null) {
    unawaited(SyncService.instance.syncProfileNow(uid));
    unawaited(SyncService.instance.pushSnapshot());
  }
}
```

- [ ] **Step 3: Run the failing test**

Run: `flutter test test/contracts/muster_profile_bridge_test.dart -r expanded`

Expected: all 6 tests PASS.

- [ ] **Step 4: Run analyzer**

Run: `flutter analyze lib/features/ai_coach/services/induction_service.dart`

Expected: `No issues found!`.

- [ ] **Step 5: Run full contract test suite**

Run: `flutter test test/contracts/`

Expected: all green.

- [ ] **Step 6: Pause for commit approval**

Ask founder. On approval:

```bash
git add lib/features/ai_coach/services/induction_service.dart test/contracts/muster_profile_bridge_test.dart
git commit -m "$(cat <<'EOF'
fix(coach): bridge muster answers into userBox['profile']

B2b. recordMusterAnswer now writes both coachBox (existing) AND mirrors
the value into userBox['profile'] for keys that map to profile fields:
  known_injuries        -> injuries
  typical_wake_time     -> wake_up_time
  preferred_workout_time-> preferred_workout_time
  body_part_priorities  -> physique_focus (single-element only)

Closes the writer/reader drift that left Edit Profile + plan generator
seeing defaults despite the user answering the muster. Bridge failures
are logged + telemetered but never throw — coachBox write already
succeeded; bridge retries on next muster turn.

Fire-and-forget syncProfileNow + pushSnapshot per CLAUDE.md §15.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 4: Bug 2c — preferred_workout_time profile field

### Task 4.1: Migration 063 SQL file

**Files:**
- Create: `supabase/migrations/063_add_preferred_workout_time.sql`

- [ ] **Step 1: Write the migration**

Write to `supabase/migrations/063_add_preferred_workout_time.sql`:

```sql
-- APK Test #15.4 / B2c — new profile column to capture muster Q4's
-- preferred_workout_time answer. Stored as "HH:MM" text matching the
-- existing wake_up_time column shape.
--
-- closes-diagnose: 2026-05-12-apk-test-15-4-batch
ALTER TABLE user_profile
  ADD COLUMN IF NOT EXISTS preferred_workout_time TEXT;

COMMENT ON COLUMN user_profile.preferred_workout_time IS
  'User-stated preferred workout start time. Format "HH:MM" 24-hour. '
  'Captured by muster Q4 (post-onboarding). NULL = not yet collected.';
```

- [ ] **Step 2: Apply migration via Supabase MCP**

Run the Supabase MCP `apply_migration` tool against project `dedsavbjuwgarrhphgnl`:

- name: `add_preferred_workout_time`
- query: contents of the file above

Expected: migration succeeds. If the column already exists, `IF NOT EXISTS` makes the call idempotent.

- [ ] **Step 3: Verify column exists in live schema**

Run via Supabase MCP `execute_sql`:

```sql
SELECT column_name, data_type FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'user_profile'
  AND column_name = 'preferred_workout_time';
```

Expected: one row, `preferred_workout_time | text`.

- [ ] **Step 4: Update applied_migrations.json**

Open `backups/applied_migrations.json`. The list currently has `"062"` followed by some date-based strings — but no `"063"`. Insert `"063"` between `"062"` and `"20260328000001"` so the array stays in roughly chronological order. Result:

```json
  "062",
  "063",
  "20260328000001",
```

- [ ] **Step 5: Pause for commit approval**

Ask founder. On approval (per `memory/feedback_migration_apply_record_pair.md` — apply + record in same commit):

```bash
git add supabase/migrations/063_add_preferred_workout_time.sql backups/applied_migrations.json
git commit -m "$(cat <<'EOF'
feat(db): migration 063 add user_profile.preferred_workout_time

B2c. New TEXT column mirrors muster Q4's preferred_workout_time answer.
"HH:MM" 24-hour, NULL allowed (legacy users have no value). Applied to
prod via Supabase MCP; backups/applied_migrations.json updated per pair-
update discipline (feedback_migration_apply_record_pair.md).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 4.2: Add preferred_workout_time to sync projection

**Files:**
- Modify: `lib/core/services/sync_service.dart` (line 2389 area)

- [ ] **Step 1: Add the projection line**

Open `lib/core/services/sync_service.dart`. Find line 2389:

```dart
if (_hasValue(p['wake_up_time'])) 'wake_up_time': p['wake_up_time'],
```

Immediately after, add:

```dart
if (_hasValue(p['preferred_workout_time']))
  'preferred_workout_time': p['preferred_workout_time'],
```

Also update the second projection site at line 771 — find:

```dart
'wake_up_time': p['wake_up_time'],
```

And add right after:

```dart
'preferred_workout_time': p['preferred_workout_time'],
```

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze lib/core/services/sync_service.dart`

Expected: `No issues found!`.

- [ ] **Step 3: Run full test suite to catch regressions**

Run: `flutter test test/sync/ test/contracts/`

Expected: all green.

- [ ] **Step 4: Pause for commit approval**

Ask founder. On approval:

```bash
git add lib/core/services/sync_service.dart
git commit -m "$(cat <<'EOF'
feat(sync): project preferred_workout_time into user_profile upsert

B2c sync wiring. Sync now ships the new column to cloud alongside
wake_up_time. _hasValue gate keeps legacy rows (NULL field) from
overwriting cloud with NULL.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 4.3: Add Edit Profile picker tile for preferred_workout_time

**Files:**
- Modify: `lib/features/profile/screens/edit_profile_screen.dart`

- [ ] **Step 1: Add state field**

In `_EditProfileScreenState`, near the existing `TimeOfDay? _wakeUpTime` (search for that line — should be around line 88), add a sibling:

```dart
TimeOfDay? _preferredWorkoutTime;
```

- [ ] **Step 2: Initialize from profile in initState**

In `initState`, find the existing wake_up_time parsing block (around line 188-198):

```dart
final wakeStr = (profile['wake_up_time'] as String?)?.trim() ?? '';
if (wakeStr.isNotEmpty) {
  final parts = wakeStr.split(':');
  if (parts.length >= 2) {
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h != null && m != null) {
      _wakeUpTime = TimeOfDay(hour: h, minute: m);
    }
  }
}
```

Immediately after this block, add:

```dart
final workoutStr =
    (profile['preferred_workout_time'] as String?)?.trim() ?? '';
if (workoutStr.isNotEmpty) {
  final parts = workoutStr.split(':');
  if (parts.length >= 2) {
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h != null && m != null) {
      _preferredWorkoutTime = TimeOfDay(hour: h, minute: m);
    }
  }
}
```

- [ ] **Step 3: Include in save map**

Find the `_save` method's field map (around line 1530-1552). Add a `preferred_workout_time` entry near the existing `wake_up_time` write:

Find where `wake_up_time` gets written in the save map. It's likely written as `if (_wakeUpTime != null) 'wake_up_time': _formatTimeOfDay(_wakeUpTime!)` or similar. Mirror it:

```dart
if (_preferredWorkoutTime != null)
  'preferred_workout_time':
      '${_preferredWorkoutTime!.hour.toString().padLeft(2, '0')}:'
      '${_preferredWorkoutTime!.minute.toString().padLeft(2, '0')}',
```

(Use whatever format helper exists for wake_up_time — grep for `_wakeUpTime!.hour` in this file.)

- [ ] **Step 4: Add picker tile in build()**

Find the existing wake-up-time picker tile (search for `'WAKE UP TIME'` or `_wakeUpTime` rendering — around the personal-info section of the form). Duplicate it for `_preferredWorkoutTime` immediately below, with these substitutions:

- Label: `'PREFERRED WORKOUT TIME'`
- Value: `_preferredWorkoutTime`
- onTap: opens `showTimePicker` initialized to `_preferredWorkoutTime ?? const TimeOfDay(hour: 7, minute: 0)` and `setState`s `_preferredWorkoutTime` on result.

If the existing tile is a private method like `_buildWakeUpTimeTile`, create a sibling `_buildPreferredWorkoutTimeTile` with the same structure.

- [ ] **Step 5: Run analyzer**

Run: `flutter analyze lib/features/profile/screens/edit_profile_screen.dart`

Expected: `No issues found!`.

- [ ] **Step 6: Smoke test compile**

Run: `flutter analyze`

Expected: no new errors across the whole project.

- [ ] **Step 7: Pause for commit approval**

Ask founder. On approval:

```bash
git add lib/features/profile/screens/edit_profile_screen.dart
git commit -m "$(cat <<'EOF'
feat(profile): preferred_workout_time picker tile in Edit Profile

B2c UI. Renders below wake-up-time picker, same TimeOfDay UX. Saves to
profile.preferred_workout_time which now mirrors to cloud (migration
063 + sync projection). Muster Q4 also writes here directly (bridge
from B2b).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 5: One-shot backfill for existing users

### Task 5.1: Failing test — backfill copies coachBox into profile defaults

**Files:**
- Create: `test/contracts/muster_bridge_backfill_test.dart`

- [ ] **Step 1: Write the failing test**

Write to `test/contracts/muster_bridge_backfill_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/services/induction_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tmp = Directory.systemTemp.createTempSync('muster_backfill_').path;
    PathProviderPlatform.instance = _FakePathProvider(tmp);
    Hive.init(tmp);
    await Hive.openBox(HiveService.userBoxName);
    await Hive.openBox(HiveService.coachBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
  });

  setUp(() async {
    await HiveService.instance.userBox.clear();
    await HiveService.instance.coachBox.clear();
    await HiveService.instance.migrationBox.clear();
    await UserRepository.instance.saveProfile({
      'id': 'test-uid',
      'injuries': ['none'],
      'physique_focus': 'balanced',
    });
  });

  test('backfill copies coachBox into profile defaults', () async {
    await HiveService.instance.coachBox
        .put('known_injuries', ['shoulders']);
    await HiveService.instance.coachBox
        .put('typical_wake_time', '06:30');
    await HiveService.instance.coachBox
        .put('preferred_workout_time', '07:15');
    await HiveService.instance.coachBox
        .put('body_part_priorities', ['glutes_legs']);

    await InductionService.instance.backfillMusterToProfileIfNeeded();

    final profile = UserRepository.instance.getProfile()!;
    expect(profile['injuries'], ['shoulders']);
    expect(profile['wake_up_time'], '06:30');
    expect(profile['preferred_workout_time'], '07:15');
    expect(profile['physique_focus'], 'glutes_legs');

    // Flag is set so re-run is a no-op.
    expect(
      HiveService.instance.migrationBox
          .get('muster_bridge_backfill_v1_done'),
      true,
    );
  });

  test('backfill is no-op when flag already set', () async {
    await HiveService.instance.migrationBox
        .put('muster_bridge_backfill_v1_done', true);
    await HiveService.instance.coachBox
        .put('known_injuries', ['shoulders']);

    await InductionService.instance.backfillMusterToProfileIfNeeded();

    // Injuries stayed at the seeded default — backfill did not run.
    expect(UserRepository.instance.getProfile()!['injuries'], ['none']);
  });

  test('backfill does not clobber user-edited values', () async {
    // User manually edited injuries to a real value post-muster.
    await UserRepository.instance
        .updateProfileFields({'injuries': ['lower back']});
    // CoachBox has an older value that should NOT overwrite the edit.
    await HiveService.instance.coachBox
        .put('known_injuries', ['shoulders']);

    await InductionService.instance.backfillMusterToProfileIfNeeded();

    expect(UserRepository.instance.getProfile()!['injuries'],
        ['lower back']);
  });

  test('backfill skips multi-select legacy body_part_priorities',
      () async {
    await HiveService.instance.coachBox
        .put('body_part_priorities', ['legs', 'glutes']);

    await InductionService.instance.backfillMusterToProfileIfNeeded();

    // physique_focus stays at default — no fuzzy guess for multi-pick.
    expect(UserRepository.instance.getProfile()!['physique_focus'],
        'balanced');
  });

  test('backfill skips when body_part_priorities[0] is balanced (default)',
      () async {
    await HiveService.instance.coachBox
        .put('body_part_priorities', ['balanced']);

    await InductionService.instance.backfillMusterToProfileIfNeeded();

    // No-op — already at default.
    expect(UserRepository.instance.getProfile()!['physique_focus'],
        'balanced');
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/contracts/muster_bridge_backfill_test.dart -r expanded`

Expected: FAIL — `backfillMusterToProfileIfNeeded` doesn't exist yet.

### Task 5.2: Implement backfillMusterToProfileIfNeeded

**Files:**
- Modify: `lib/features/ai_coach/services/induction_service.dart`

- [ ] **Step 1: Add the method**

At the end of the `InductionService` class (just before the closing brace), add:

```dart
/// Migration flag key for the one-shot bridge backfill. Stored in
/// [HiveService.migrationBox] which is NEVER cleared by clearAllData()
/// — keeps the backfill from re-running after a sign-out + sign-in.
static const String _backfillFlagKey =
    'muster_bridge_backfill_v1_done';

/// APK Test #15.4 / B2 — one-shot backfill of pre-bridge muster
/// answers into [userBox['profile']]. Called from
/// `auth_provider._ensureLocalUser` after `HiveUserSession.openForUser`
/// succeeds.
///
/// Idempotency rules:
/// - Gated by [_backfillFlagKey] in `migrationBox` — runs at most once
///   per device lifetime per migration version.
/// - Only writes to a profile field if the field is currently at its
///   default value. User-edited values are NEVER clobbered.
/// - Skips multi-select legacy `body_part_priorities` (length > 1) —
///   no fuzzy guess; user can re-pick via Edit Profile.
///
/// Non-fatal on failure: logs + telemeters; flag stays unset so the
/// backfill retries on next launch. Never throws.
@visibleForTesting
Future<void> backfillMusterToProfileIfNeeded() async {
  try {
    final mig = HiveService.instance.migrationBox;
    if (mig.get(_backfillFlagKey) == true) return;

    final coach = HiveService.instance.coachBox;
    final profile = UserRepository.instance.getProfile() ?? {};
    final updates = <String, dynamic>{};

    // injuries
    final cbInjuries = coach.get('known_injuries');
    if (cbInjuries is List && cbInjuries.isNotEmpty) {
      final existing = profile['injuries'];
      final isDefault = existing == null ||
          (existing is List &&
              (existing.isEmpty ||
                  (existing.length == 1 && existing.first == 'none')));
      if (isDefault) {
        updates['injuries'] = cbInjuries.cast<String>();
      }
    }

    // wake_up_time
    final cbWake = coach.get('typical_wake_time');
    if (cbWake is String && cbWake.isNotEmpty) {
      final existing = profile['wake_up_time'];
      if (existing == null || (existing is String && existing.isEmpty)) {
        updates['wake_up_time'] = cbWake;
      }
    }

    // preferred_workout_time
    final cbWorkout = coach.get('preferred_workout_time');
    if (cbWorkout is String && cbWorkout.isNotEmpty) {
      if (profile['preferred_workout_time'] == null) {
        updates['preferred_workout_time'] = cbWorkout;
      }
    }

    // physique_focus — single-select legacy data only.
    final cbBodyParts = coach.get('body_part_priorities');
    if (cbBodyParts is List && cbBodyParts.length == 1) {
      final v = cbBodyParts.first as String;
      const validEnum = {
        'balanced', 'glutes_legs', 'chest_shoulders_arms', 'strength',
      };
      final currentDefault =
          (profile['physique_focus'] as String?) == 'balanced';
      if (validEnum.contains(v) && currentDefault && v != 'balanced') {
        updates['physique_focus'] = v;
      }
    }

    if (updates.isNotEmpty) {
      await UserRepository.instance.updateProfileFields(updates);
      final uid = SupabaseService.instance.currentUser?.id;
      if (uid != null) {
        unawaited(SyncService.instance.syncProfileNow(uid));
        unawaited(SyncService.instance.pushSnapshot());
      }
    }

    await mig.put(_backfillFlagKey, true);
  } catch (e, st) {
    debugPrint('[InductionService.backfillMusterToProfileIfNeeded] $e');
    unawaited(ErrorTelemetry.recordNonFatal(e, st,
        reason: 'muster_bridge_backfill'));
    // Don't set the flag on failure — retry next launch.
  }
}
```

- [ ] **Step 2: Run the backfill test**

Run: `flutter test test/contracts/muster_bridge_backfill_test.dart -r expanded`

Expected: all 5 tests PASS.

- [ ] **Step 3: Run full test suite**

Run: `flutter test`

Expected: all green (or only pre-existing failures unrelated to this batch).

- [ ] **Step 4: Pause for commit approval**

Ask founder. On approval:

```bash
git add lib/features/ai_coach/services/induction_service.dart test/contracts/muster_bridge_backfill_test.dart
git commit -m "$(cat <<'EOF'
feat(coach): one-shot muster -> profile backfill for existing users

B2 backfill. Mirrors coachBox muster values into profile defaults on
first run post-deploy. Gated by migrationBox flag (runs once per device
lifetime), idempotent, never clobbers user-edited values, skips legacy
multi-select body_part_priorities.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 5.3: Call backfill from _ensureLocalUser

**Files:**
- Modify: `lib/features/auth/providers/auth_provider.dart`

- [ ] **Step 1: Add import**

At the top of `lib/features/auth/providers/auth_provider.dart`, add:

```dart
import 'package:icanbefitter/features/ai_coach/services/induction_service.dart';
```

- [ ] **Step 2: Call backfill after openForUser succeeds**

In `_ensureLocalUser`, after the existing `UserConfigMigrator.runIfNeeded()` call (around line 430-435), add:

```dart
// APK Test #15.4 / B2 backfill — one-shot mirror of pre-bridge muster
// answers into userBox['profile']. Gated by migrationBox flag.
try {
  await InductionService.instance.backfillMusterToProfileIfNeeded();
} catch (e) {
  debugPrint('[auth/_ensureLocalUser] muster backfill failed: $e');
  // Non-fatal — backfill is idempotent and retries on next launch.
}
```

Place it after `UserConfigMigrator.runIfNeeded()` so it runs only after the cross-account guard + user-config migration have settled.

- [ ] **Step 3: Run analyzer**

Run: `flutter analyze lib/features/auth/providers/auth_provider.dart`

Expected: `No issues found!`.

- [ ] **Step 4: Run full test suite**

Run: `flutter test`

Expected: all green.

- [ ] **Step 5: Pause for commit approval**

Ask founder. On approval:

```bash
git add lib/features/auth/providers/auth_provider.dart
git commit -m "$(cat <<'EOF'
fix(auth): run muster -> profile backfill on _ensureLocalUser

B2 backfill wiring. Called after UserConfigMigrator so it runs only on
a stable per-user session. Non-fatal on failure; idempotent; gated by
migrationBox flag so it executes once per device.

Existing sumit + upendra accounts surface their muster injuries +
physique focus in Edit Profile on first launch after this APK ships.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 6: Documentation + sot_registry updates

### Task 6.1: CLAUDE.md updates

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add §19 Common Bugs entries**

Open `CLAUDE.md`. Scroll to §19 Common Bugs. At the end of the existing rows in the Common Bugs table, add two new rows. Find a good insertion point — the most recent entries are at the bottom of the long entry list, just before the final closing pipe. Add:

```markdown
| Cross-account profile leak during live signOut+signUp | Closed in APK Test #15.4 / B1 `<commit_sha>` (2026-05-12). Two-layer fix: `wrapUserScopedBox` returns `GuardedBox.empty` during the disagreement window (Layer A — correctness), and `authUserIdTokenProvider` gates on `hiveSessionOwnerProvider` via `HiveUserSession.currentOwnerListenable` (Layer B — liveness). Token returns `<anon>` while authUid ≠ hiveOwner. Cold start unaffected (splash awaits `openForUser` before UI mounts); only the in-session sign-out+sign-up race window is fixed. c4055a (Test #15.3 Bug 5) addressed cache invalidation alone but left the box-swap timing unaddressed. Pinned by `test/contracts/auth_invalidation_timing_test.dart` + `test/contracts/wrap_user_scoped_box_disagreement_test.dart`. |
| Muster answers don't reach Edit Profile / plan generator | Closed in APK Test #15.4 / B2 `<commit_sha>` (2026-05-12). `InductionService.recordMusterAnswer` now writes coachBox AND mirrors specific keys into `userBox['profile']` via `_bridgeToProfile`. Mappings: `known_injuries→injuries`, `typical_wake_time→wake_up_time`, `preferred_workout_time→preferred_workout_time` (new column, migration 063), `body_part_priorities[0]→physique_focus` (single-select Q5 matching enum). Existing users get one-shot backfill on `_ensureLocalUser`. Same writer/reader drift class as Test #8 / Theme D. Pinned by `test/contracts/muster_profile_bridge_test.dart` + `test/contracts/muster_bridge_backfill_test.dart`. |
```

(Replace `<commit_sha>` with the actual SHA of the relevant fix commit when this update lands.)

- [ ] **Step 2: Add §15 Source of Truth Rules entry**

Find §15 Source of Truth Rules. Add this bullet to the existing list:

```markdown
- **Muster answers:** `InductionService.recordMusterAnswer` is the ONLY writer for the 6 muster keys in `coachBox`. It also bridges 4 of those keys into `userBox['profile']`: `known_injuries→injuries`, `typical_wake_time→wake_up_time`, `preferred_workout_time→preferred_workout_time`, `body_part_priorities[0]→physique_focus`. Never write any of these coachBox keys from anywhere else. Adding a new muster question requires updating `_bridgeToProfile` if it maps to a profile field, plus the backfill in `backfillMusterToProfileIfNeeded`.
```

- [ ] **Step 3: Update §7 column-type notes for migration 063**

Find §7 "Column-type notes (post-migration):". Add:

```markdown
- `user_profile.preferred_workout_time TEXT` (migration 063, 2026-05-12). Captures muster Q4 "preferred workout time" answer. "HH:MM" 24-hour. NULL when not collected. Written by muster bridge (B2b) and Edit Profile picker; read by AI context (rolling-context Edge Function reads via `user_profile`) and Edit Profile.
```

- [ ] **Step 4: Pause for commit approval**

Ask founder. On approval:

```bash
git add CLAUDE.md
git commit -m "$(cat <<'EOF'
docs(claude): §19 §15 §7 — APK Test #15.4 cross-account race + muster bridge

§19 two new common-bugs entries (B1 cross-account leak, B2 muster bridge
SoT drift).
§15 new SoT rule pinning InductionService as the only writer of muster
keys + the 4 bridged profile fields.
§7 column-type note for user_profile.preferred_workout_time.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 6.2: sot_registry.yaml updates

**Files:**
- Modify: `docs/sot_registry.yaml`

- [ ] **Step 1: Add 4 new bridged-key entries**

Open `docs/sot_registry.yaml`. Add a new entry block for each bridged key. Mirror the existing entry shape (search the file for an existing entry like `injuries` or `wake_up_time` to copy the pattern). Example for `injuries`:

```yaml
- concept: profile.injuries
  writers:
    - lib/features/ai_coach/services/induction_service.dart:_bridgeToProfile (case 'known_injuries')
    - lib/features/profile/screens/edit_profile_screen.dart:_save
    - lib/features/onboarding/providers/onboarding_provider.dart:completeOnboarding
  readers:
    - lib/features/profile/screens/edit_profile_screen.dart:initState
    - lib/features/profile/providers/profile_completeness_provider.dart
    - lib/shared/repositories/plan_engine/exercise_selector.dart (injury exclusion mask)
  regression_tests:
    - test/contracts/muster_profile_bridge_test.dart
  class_constraints:
    - List<String> stored in Hive; serialised as text[] in cloud per migration 033
```

Add similar entries for: `wake_up_time`, `preferred_workout_time`, `physique_focus`.

If the registry doesn't already track these concepts (the registry is selective), just add the muster-related writer rows under whatever convention is used in the file.

- [ ] **Step 2: Pause for commit approval**

Ask founder. On approval:

```bash
git add docs/sot_registry.yaml
git commit -m "$(cat <<'EOF'
docs(sot): register muster -> profile bridge writers

Adds InductionService._bridgeToProfile as a writer of profile.injuries,
wake_up_time, preferred_workout_time, physique_focus. Per APK Test
#15.4 / B2.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 7: Diagnose docs + merge prep

### Task 7.1: Write diagnose docs

**Files:**
- Create: `docs/diagnoses/2026-05-12-cross-account-cache-race-b1.md`
- Create: `docs/diagnoses/2026-05-12-muster-profile-bridge-b2.md`

- [ ] **Step 1: Write B1 diagnose doc**

Write to `docs/diagnoses/2026-05-12-cross-account-cache-race-b1.md`. Use the shape required by `dart run scripts/validate_diagnose_doc.dart` — check an existing diagnose file in the same directory (e.g. `2026-05-12-cross-account-mutex-c7d4f6.md`) for the exact stanza format. Required sections include: bug-id, symptom, root cause (file:line citations), fix (file:line citations), regression test, follow-ups.

Key content:

- **bug-id:** something like `2026-05-12-cross-account-race-b1`
- **Symptom:** "signOut as Upendra + signUp as sumit shows Upendra's profile in Edit Profile (174 cm / 77.8 kg / DOB 1988-06-30) until force-kill+reopen."
- **Root cause:** Sequence table from spec §"Root cause (sequence of events)". Cite `lib/features/auth/providers/auth_provider.dart:24-30` (authStateProvider) and `auth_provider.dart:365` (openForUser call inside `_ensureLocalUser`).
- **Fix:** Layer A guard in `lib/core/services/guarded_box.dart:wrapUserScopedBox`; Layer B token rewire in `lib/features/auth/providers/auth_invalidation_provider.dart`; listenable in `lib/core/services/hive_user_session.dart`.
- **Regression test:** `test/contracts/auth_invalidation_timing_test.dart`, `test/contracts/wrap_user_scoped_box_disagreement_test.dart`.

- [ ] **Step 2: Write B2 diagnose doc**

Write to `docs/diagnoses/2026-05-12-muster-profile-bridge-b2.md`. Same shape.

Key content:

- **bug-id:** `2026-05-12-muster-profile-bridge-b2`
- **Symptom:** "After completing the post-onboarding muster, Edit Profile shows `injuries=['none']` and `physique_focus='balanced'` even though user picked shoulders + legs."
- **Root cause:** `InductionService.recordMusterAnswer` (line 47-52 pre-fix) writes only to `coachBox`. Edit Profile reads from `userBox['profile']`. Cite `muster_screen.dart` Q3/Q5 answer paths and `edit_profile_screen.dart:105` (where `userProfileProvider` is read in initState).
- **Fix:** `_bridgeToProfile` in `induction_service.dart`; one-shot backfill in `backfillMusterToProfileIfNeeded` called from `auth_provider.dart:_ensureLocalUser`; migration 063 for new column; Q5 single-select; sync projection update.
- **Regression test:** `test/contracts/muster_profile_bridge_test.dart`, `test/contracts/muster_bridge_backfill_test.dart`, `test/contracts/muster_question_count_test.dart`.

- [ ] **Step 3: Validate diagnose docs**

Run: `dart run scripts/validate_diagnose_doc.dart docs/diagnoses/2026-05-12-cross-account-cache-race-b1.md`

Expected: validation passes.

Run: `dart run scripts/validate_diagnose_doc.dart docs/diagnoses/2026-05-12-muster-profile-bridge-b2.md`

Expected: validation passes. If either fails, the error message specifies which required section is missing — add it and re-run.

- [ ] **Step 4: Pause for commit approval**

Ask founder. On approval:

```bash
git add docs/diagnoses/
git commit -m "$(cat <<'EOF'
docs(diagnoses): APK Test #15.4 — B1 cache race + B2 muster bridge

Per CLAUDE.md rule 22 — every fix commit on main needs a diagnose-doc.
Both bugs land as one batch but each gets its own doc for grep-ability.

closes-diagnose: 2026-05-12-cross-account-race-b1
closes-diagnose: 2026-05-12-muster-profile-bridge-b2

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 7.2: Final pre-merge verification

**Files:** none

- [ ] **Step 1: Full test suite**

Run: `flutter test`

Expected: all tests green. Pre-existing failures (if any) should match what's documented in CLAUDE.md as deferred — do not add new failures.

- [ ] **Step 2: Full analyzer**

Run: `flutter analyze`

Expected: `No issues found!` or only pre-existing warnings.

- [ ] **Step 3: Verify migration applied**

Via Supabase MCP `execute_sql`:

```sql
SELECT column_name FROM information_schema.columns
WHERE table_schema='public' AND table_name='user_profile'
  AND column_name='preferred_workout_time';
```

Expected: 1 row.

- [ ] **Step 4: Verify applied_migrations.json contains "063"**

Run: `grep '"063"' backups/applied_migrations.json`

Expected: one match.

### Task 7.3: Merge to main

**Files:** none

- [ ] **Step 1: Pause for merge approval**

Ask founder: *"All phases complete and tests green. Merge `feat/apk-test-15-4-batch` to main with `--no-ff`?"* (per `memory/feedback_main_is_source_of_truth.md`).

- [ ] **Step 2: On approval, merge**

```bash
git checkout main
git pull origin main
git merge --no-ff feat/apk-test-15-4-batch -m "$(cat <<'EOF'
Merge APK Test #15.4 — cross-account race + muster profile bridge

B1: signOut+signUp on same session no longer leaks prior user's profile.
Two-layer fix: GuardedBox.empty during disagreement window (Layer A) +
authUserIdTokenProvider gates on HiveUserSession (Layer B).

B2: Muster answers now bridge into userBox['profile']. Q1/Q2 dropped.
Q5 single-select matching physique_focus enum. Migration 063 adds
preferred_workout_time column. One-shot backfill for existing users.

5 new contract tests pin both bugs against regression.

closes-diagnose: 2026-05-12-cross-account-race-b1
closes-diagnose: 2026-05-12-muster-profile-bridge-b2

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 3: Push to remote**

Ask founder again before pushing (push is a separate explicit-approval action per global rules):

```bash
git push origin main
```

- [ ] **Step 4: Do NOT build APK yet**

Per `memory/feedback_apk_build_explicit_approval.md` — APK build requires explicit founder approval each time, even after merge. Stop here. Founder will say "build apk" when ready.

---

## Self-review checklist (for plan author)

- [x] Every spec section maps to a task — B1 Layer A (1.5-1.7), B1 Layer B (1.1-1.4), B2a drop Q1/Q2 (2.2), B2b bridge (3.1-3.2), B2c migration + sync + UI (4.1-4.3), B2d Q5 single-select (2.3), backfill (5.1-5.3), docs (6.1-6.2), diagnose docs (7.1).
- [x] No placeholders — every code block is the actual implementation.
- [x] Type consistency — `GuardedBox.empty`, `currentOwnerListenable`, `_bridgeToProfile`, `backfillMusterToProfileIfNeeded` names used consistently across tasks.
- [x] Test command consistency — `flutter test <path> -r expanded` everywhere.
- [x] Migration number is 063 (062 already taken by `workout_logs_dedupe_and_unique`).
- [x] Founder's discipline rules respected — every commit step has an explicit "pause for approval" beat before the `git commit` command; founder approves each commit individually per global rule.
- [x] Per CLAUDE.md rule 22 — diagnose docs explicitly created (Task 7.1) before final merge.
- [x] APK build deferred per `memory/feedback_apk_build_explicit_approval.md`.

---

## Estimated effort

- Phase 1 (B1): ~3 hours (4 commits, includes 2 contract tests)
- Phase 2 (muster surgery): ~1.5 hours (2 commits, 1 contract test)
- Phase 3 (bridge): ~1 hour (1 commit, 1 contract test)
- Phase 4 (migration + UI): ~1.5 hours (3 commits)
- Phase 5 (backfill): ~1 hour (2 commits, 1 contract test)
- Phase 6 (docs): ~30 min (2 commits)
- Phase 7 (diagnose + merge): ~45 min (2-3 commits + merge)

**Total: ~9 hours of focused work, 16-18 commits.**
