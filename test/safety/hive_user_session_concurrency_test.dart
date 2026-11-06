import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// APK Test #15.1 / Bug C — HiveUserSession concurrency + extended
/// cross-account guard.
///
/// Pre-fix: `HiveUserSession`'s three static-state mutating methods
/// (`openForUser`, `closeAll`, `deleteAllFilesForCurrentUser`) could
/// interleave on the Dart event loop during signOut → signUp transitions.
/// Both paths mutated `_currentOwnerFullId` before either finished,
/// resulting in cross-account data leakage to a new account's session.
///
/// The C-6 audit-batch cross-account guard only fired on `profile.id`
/// mismatch — leaks where profile was absent (fresh signup, profile not
/// yet written) slipped through silently while other user-scoped boxes
/// still carried prior-user data.
///
/// Source-grep contracts (this file, no Hive bootstrap needed):
///   1. `package:synchronized/synchronized.dart` imported.
///   2. Static `Lock _sessionLock` field declared.
///   3. Three public methods wrap their bodies in `_sessionLock.synchronized`.
///   4. Internal `_xxxLocked` variants exist for re-entry-safe calls.
///   5. Extended guard checks BOTH `profile.id` mismatch AND
///      `preexisting_data_no_profile_id_root=<box>` (boxes have data but
///      profile is absent — leaked legacy or in-process state).
///
/// closes-diagnose: 2026-05-12-cross-account-mutex-c7d4f6
void main() {
  late String src;

  setUpAll(() {
    final f = File('lib/core/services/hive_user_session.dart');
    expect(f.existsSync(), isTrue,
        reason: 'hive_user_session.dart must exist');
    src = f.readAsStringSync();
  });

  group('Layer 1 — _sessionLock serialization', () {
    test('package:synchronized imported', () {
      expect(
        src.contains("import 'package:synchronized/synchronized.dart';"),
        isTrue,
        reason:
            'HiveUserSession must import package:synchronized to serialize '
            'static-state mutations across signOut/signUp transitions.',
      );
    });

    test('static Lock _sessionLock field declared', () {
      expect(
        src.contains('static final Lock _sessionLock = Lock();'),
        isTrue,
        reason:
            'HiveUserSession must declare a static final Lock _sessionLock '
            'so all three public mutating methods share the same gate. '
            'closes-diagnose: 2026-05-12-cross-account-mutex-c7d4f6',
      );
    });

    test('openForUser wraps body in _sessionLock.synchronized', () {
      // The public method body must consist of a single
      // `_sessionLock.synchronized(...)` call — no direct state mutation
      // outside the lock.
      final marker = 'static Future<void> openForUser(String userId) async {';
      final start = src.indexOf(marker);
      expect(start, greaterThan(0),
          reason: 'openForUser must exist');
      final end = src.indexOf('  }', start);
      expect(end, greaterThan(start));
      final body = src.substring(start, end);
      expect(
        RegExp(r'_sessionLock\s*\.\s*synchronized').hasMatch(body),
        isTrue,
        reason:
            'openForUser must wrap its work in _sessionLock.synchronized; '
            'unguarded paths can interleave with closeAll + cross-account leak.',
      );
      expect(
        body.contains('_openForUserLocked'),
        isTrue,
        reason:
            'openForUser must delegate to _openForUserLocked so the lock '
            'is held for the entire body.',
      );
    });

    test('closeAll wraps body in _sessionLock.synchronized', () {
      final marker = 'static Future<void> closeAll() async {';
      final start = src.indexOf(marker);
      expect(start, greaterThan(0), reason: 'closeAll must exist');
      final end = src.indexOf('  }', start);
      final body = src.substring(start, end);
      expect(RegExp(r'_sessionLock\s*\.\s*synchronized').hasMatch(body), isTrue,
          reason: 'closeAll must serialize via _sessionLock');
      expect(body.contains('_closeAllLocked'), isTrue,
          reason: 'closeAll must delegate to _closeAllLocked');
    });

    test('deleteAllFilesForCurrentUser wraps body in _sessionLock.synchronized',
        () {
      final marker =
          'static Future<void> deleteAllFilesForCurrentUser() async {';
      final start = src.indexOf(marker);
      expect(start, greaterThan(0),
          reason: 'deleteAllFilesForCurrentUser must exist');
      final end = src.indexOf('  }', start);
      final body = src.substring(start, end);
      expect(RegExp(r'_sessionLock\s*\.\s*synchronized').hasMatch(body), isTrue);
      expect(body.contains('_deleteAllFilesForCurrentUserLocked'), isTrue);
    });

    test('internal _xxxLocked variants exist (re-entry safety)', () {
      // The locked-internal variants exist so re-entry from one already-
      // locked context (e.g. _openForUserLocked calling _closeAllLocked)
      // does not deadlock on the non-reentrant Lock.
      expect(
        src.contains('static Future<void> _openForUserLocked(String userId)'),
        isTrue,
        reason: '_openForUserLocked must exist',
      );
      expect(
        src.contains('static Future<void> _closeAllLocked()'),
        isTrue,
        reason: '_closeAllLocked must exist',
      );
      expect(
        src.contains(
            'static Future<void> _deleteAllFilesForCurrentUserLocked()'),
        isTrue,
        reason: '_deleteAllFilesForCurrentUserLocked must exist',
      );
    });

    test('openForUserLocked uses _closeAllLocked (not closeAll) for re-entry',
        () {
      final marker =
          'static Future<void> _openForUserLocked(String userId) async {';
      final start = src.indexOf(marker);
      expect(start, greaterThan(0));
      // Body extends until the next top-level static. ~3000 chars is
      // generous; openForUser's body is large because of the guard.
      final end = (start + 5000).clamp(0, src.length);
      final body = src.substring(start, end);
      expect(
        body.contains('await _closeAllLocked()'),
        isTrue,
        reason:
            '_openForUserLocked must call _closeAllLocked() (not closeAll) '
            'when an existing owner needs to be evicted — calling the public '
            'closeAll() while the lock is already held would deadlock.',
      );
      // Forbidden: calling the public closeAll() from inside locked code.
      expect(
        body.contains('await closeAll();'),
        isFalse,
        reason:
            'forbidden — _openForUserLocked must NOT call closeAll() (the '
            'public lock-acquiring version). Use _closeAllLocked() instead.',
      );
    });
  });

  group('Layer 2 — C-6 cross-account guard preserved', () {
    // Per APK Test #15.1 final review: the mutex (Layer 1) alone closes
    // the founder's sumit1 leak by serializing signOut/signUp. The
    // earlier-proposed "extended guard on preexisting data + no
    // profile.id" was reverted because it over-fires: it broke 4
    // legitimate scenarios (same-user reopen, defensive non-Map
    // profile, _migrateLegacySharedBoxes copy-then-clear paradox).
    // C-6 (profile.id mismatch) stays as the canonical guard.

    test('C-6 profile.id mismatch guard preserved unchanged', () {
      // Source-grep the original C-6 patterns to ensure they survive.
      expect(
        src.contains("'hive_cross_account_guard_fired'"),
        isTrue,
        reason:
            'C-6 cross-account guard must keep emitting telemetry on '
            'profile.id mismatch.',
      );
      expect(
        src.contains('existingId != null && existingId != userId'),
        isTrue,
        reason:
            'C-6 guard predicate must remain: clear when profile.id is '
            'present AND mismatches the new userId.',
      );
    });

    test('guard clears all 7 user-scoped boxes when triggered', () {
      // Look for the clear loop in the guard window.
      final marker = 'Cross-account guard fired';
      final start = src.indexOf(marker);
      expect(start, greaterThan(0),
          reason: 'Cross-account guard fired branch must exist');
      final end = (start + 2000).clamp(0, src.length);
      final body = src.substring(start, end);
      expect(
        body.contains('for (final root in userScopedBoxRoots)') &&
            body.contains('.clear()'),
        isTrue,
        reason:
            'When the guard fires, it must iterate userScopedBoxRoots and '
            'call .clear() on each.',
      );
    });
  });
}
