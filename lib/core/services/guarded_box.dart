import 'dart:async';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'error_telemetry.dart';
import 'hive_user_session.dart';

/// Thrown when a user-scoped Hive box is accessed with a session that
/// doesn't own it. Caught by the global error handler installed in
/// `main.dart`, which force-signs-out + clears local state + redirects
/// to /sign-in.
class HiveOwnershipException implements Exception {
  HiveOwnershipException(this.message);
  final String message;
  @override
  String toString() => 'HiveOwnershipException: $message';
}

/// Wraps a Hive [Box] of type [T] with an ownership assertion on every
/// read/write/key/delete operation.
///
/// Construction captures the owner's 8-hex hash + full id at the moment
/// `HiveUserSession.openForUser` ran. Every operation checks that the
/// CURRENT Supabase session's user.id still starts with the captured
/// hash. Mismatch → throw `HiveOwnershipException`.
///
/// This is defense-in-depth on top of the namespaced-box layer (Task
/// A-5/6/7). Even if a namespaced box is somehow handed to a different
/// session (race condition, bug in HiveUserSession), the wrapper
/// catches the misuse at the call site instead of silently leaking
/// data.
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
        _ownerHash = pendingAuthUid
            .replaceAll('-', '')
            .padRight(8, '0')
            .substring(0, 8),
        _ownerFullId = pendingAuthUid,
        _isEmptyStub = true;

  final Box _box;
  final String _ownerHash;
  final String _ownerFullId;
  final bool _isEmptyStub;

  /// Test-only escape hatch. When `true`, [_assertOwnership] is a no-op.
  /// Production code must NEVER set this. Intended for unit tests that
  /// don't initialise Supabase — without this flag, every guarded box
  /// access throws because `Supabase.instance` isn't available.
  ///
  /// Reset to `false` in test tearDown so a leak across tests can't grant
  /// ownership-bypass to subsequent suites.
  static bool testBypassOwnership = false;

  void _assertOwnership() {
    if (testBypassOwnership) return;
    final session = Supabase.instance.client.auth.currentUser?.id;
    if (session == null) {
      throw HiveOwnershipException(
        'No active session for user-scoped box (owner=$_ownerHash)',
      );
    }
    if (session != _ownerFullId) {
      throw HiveOwnershipException(
        'Box owner $_ownerHash != session ${session.substring(0, 8)}',
      );
    }
  }

  StateError _emptyStubWriteError(String op) {
    return StateError(
      'GuardedBox.empty: refusing $op during auth/Hive disagreement window',
    );
  }

  // ── Box surface — every method asserts ownership first ────────

  T? get(dynamic key, {T? defaultValue}) {
    if (_isEmptyStub) return defaultValue;
    _assertOwnership();
    return _box.get(key, defaultValue: defaultValue) as T?;
  }

  Future<void> put(dynamic key, T value) async {
    if (_isEmptyStub) throw _emptyStubWriteError('put');
    _assertOwnership();
    await _box.put(key, value);
  }

  Future<void> putAll(Map<dynamic, T> entries) async {
    if (_isEmptyStub) throw _emptyStubWriteError('putAll');
    _assertOwnership();
    await _box.putAll(entries);
  }

  Future<void> delete(dynamic key) async {
    if (_isEmptyStub) throw _emptyStubWriteError('delete');
    _assertOwnership();
    await _box.delete(key);
  }

  Future<void> deleteAll(Iterable keys) async {
    if (_isEmptyStub) throw _emptyStubWriteError('deleteAll');
    _assertOwnership();
    await _box.deleteAll(keys);
  }

  Future<int> clear() async {
    if (_isEmptyStub) throw _emptyStubWriteError('clear');
    _assertOwnership();
    return _box.clear();
  }

  Iterable get keys {
    if (_isEmptyStub) return const <dynamic>[];
    _assertOwnership();
    return _box.keys;
  }

  Iterable<T> get values {
    if (_isEmptyStub) return Iterable<T>.empty();
    _assertOwnership();
    return _box.values.cast<T>();
  }

  bool containsKey(dynamic key) {
    if (_isEmptyStub) return false;
    _assertOwnership();
    return _box.containsKey(key);
  }

  int get length {
    if (_isEmptyStub) return 0;
    _assertOwnership();
    return _box.length;
  }

  bool get isEmpty {
    if (_isEmptyStub) return true;
    _assertOwnership();
    return _box.isEmpty;
  }

  bool get isNotEmpty {
    if (_isEmptyStub) return false;
    _assertOwnership();
    return _box.isNotEmpty;
  }

  /// Escape hatch: callers that need the raw Hive Box (e.g. listenable
  /// for ValueListenableBuilder) should use this AND assert ownership
  /// at the listener tier themselves. Use sparingly.
  Box get rawBox {
    if (_isEmptyStub) {
      throw StateError(
        'GuardedBox.empty: rawBox unavailable during auth/Hive disagreement',
      );
    }
    _assertOwnership();
    return _box;
  }

  String get debugOwnerHash => _ownerHash;
}

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

/// Helper used by HiveService getters to construct a guarded wrapper
/// for a user-scoped box. Throws StateError if no session is active
/// (caller bug — same surface as Task A-6's `_userScopedBox`).
///
/// APK Test #12.7 — class fix for the "HiveUserSession not opened"
/// silent-sync regression. Previously this method was strictly assertive:
/// any caller that hit a user-scoped box before `openForUser` had run
/// would throw, and most callers (sync, snapshot, backfill, gate) wrap
/// their work in `unawaited(...)` so the StateError was swallowed and
/// the operation silently no-op'd.
///
/// The new behaviour: if the session is closed BUT a Supabase session
/// is active AND the namespaced box file has previously been opened in
/// this process lifetime (so it's already in Hive's open-box registry),
/// wrap it with the current auth uid as owner. This handles the race
/// where `_ensureLocalUser` opened the boxes but a subsequent
/// `closeAll`/`signOut` handshake briefly nulled `_currentOwnerFullId`
/// while a fire-and-forget sync was inflight.
///
/// For the cold-start case (boxes never opened), the SyncService entry
/// points (`syncWorkoutData`, `syncNutritionData`, `pushSnapshot`,
/// `checkAndSync`, `backfillCustomEntityIds`) call
/// `HiveUserSession.openForUser` defensively before any box read. That
/// async ensure is the canonical bootstrap; this synchronous fallback
/// covers only the close-race window.
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
  final hiveOwnerCheck = HiveUserSession.currentOwnerFullId;
  if (supabaseAuthUid != null &&
      hiveOwnerCheck != null &&
      supabaseAuthUid != hiveOwnerCheck) {
    unawaited(ErrorTelemetry.logEvent(
      'guarded_box_disagreement',
      message:
          'root=$root authUid=${supabaseAuthUid.substring(0, 8)} '
          'hiveOwner=${hiveOwnerCheck.substring(0, 8)}',
    ));
    return GuardedBox<T>.empty(supabaseAuthUid);
  }

  // ── existing cold-start fallback path follows ──
  var fullId = HiveUserSession.currentOwnerFullId;
  var hash = HiveUserSession.currentOwnerHash;

  if (fullId == null || hash == null) {
    String? authUid;
    try {
      authUid = Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      // Supabase singleton not initialised (very early cold start /
      // pure-VM unit test). Fall through to the StateError surface.
    }

    if (authUid != null) {
      final boxName = HiveUserSession.namespacedBoxName(root, authUid);
      if (Hive.isBoxOpen(boxName)) {
        // Box still open from a prior session — wrap it with the
        // current auth uid as owner so the ownership assertion in
        // subsequent ops uses the live session. This closes the
        // close-race window without forcing every caller to await an
        // async openForUser.
        // APK Test #12.8 — surface every fallback fire so we can
        // measure how often the close-race actually hits in production.
        // High count = upstream caller ordering bug; near-zero =
        // defensive guard rarely needed (good).
        unawaited(ErrorTelemetry.logEvent('guarded_box_auto_open_fallback',
            message: 'box=$root userId=${authUid.substring(0, 8)}'));
        final box = Hive.box(boxName);
        final localHash = authUid.replaceAll('-', '').substring(0, 8);
        return GuardedBox<T>(box, localHash, authUid);
      }
    }
  }

  if (fullId == null || hash == null) {
    throw StateError(
      'HiveUserSession not opened — cannot wrap user-scoped box "$root". '
      'Call HiveUserSession.openForUser(userId) after sign-in.',
    );
  }
  final boxName = HiveUserSession.namespacedBoxName(root, fullId);
  final box = Hive.box(boxName);
  return GuardedBox<T>(box, hash, fullId);
}
