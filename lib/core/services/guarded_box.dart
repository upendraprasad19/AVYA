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
  GuardedBox(this._box, this._ownerHash, this._ownerFullId);

  final Box _box;
  final String _ownerHash;
  final String _ownerFullId;

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

  // ── Box surface — every method asserts ownership first ────────

  T? get(dynamic key, {T? defaultValue}) {
    _assertOwnership();
    return _box.get(key, defaultValue: defaultValue) as T?;
  }

  Future<void> put(dynamic key, T value) async {
    _assertOwnership();
    await _box.put(key, value);
  }

  Future<void> putAll(Map<dynamic, T> entries) async {
    _assertOwnership();
    await _box.putAll(entries);
  }

  Future<void> delete(dynamic key) async {
    _assertOwnership();
    await _box.delete(key);
  }

  Future<void> deleteAll(Iterable keys) async {
    _assertOwnership();
    await _box.deleteAll(keys);
  }

  Future<int> clear() async {
    _assertOwnership();
    return _box.clear();
  }

  Iterable get keys {
    _assertOwnership();
    return _box.keys;
  }

  Iterable<T> get values {
    _assertOwnership();
    return _box.values.cast<T>();
  }

  bool containsKey(dynamic key) {
    _assertOwnership();
    return _box.containsKey(key);
  }

  int get length {
    _assertOwnership();
    return _box.length;
  }

  bool get isEmpty {
    _assertOwnership();
    return _box.isEmpty;
  }

  bool get isNotEmpty {
    _assertOwnership();
    return _box.isNotEmpty;
  }

  /// Escape hatch: callers that need the raw Hive Box (e.g. listenable
  /// for ValueListenableBuilder) should use this AND assert ownership
  /// at the listener tier themselves. Use sparingly.
  Box get rawBox {
    _assertOwnership();
    return _box;
  }

  String get debugOwnerHash => _ownerHash;
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
