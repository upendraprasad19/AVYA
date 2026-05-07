// APK Test #12.7 — regression test for the GuardedBox session-closed
// race that caused fire-and-forget syncs to silently no-op.
//
// Root cause (pre-fix): when `HiveUserSession` had been closed (logout
// handshake briefly nulls _currentOwnerFullId, or cold-start path lands
// before `_ensureLocalUser` ran), `wrapUserScopedBox(...)` threw
// `StateError: HiveUserSession not opened ...`. Most call sites are
// fire-and-forget syncs wrapped in `unawaited(...)` — the StateError
// was swallowed and the cloud silently received nothing.
//
// Fix: when the session pointer is null but a Supabase session is live
// AND the namespaced box file is already open in this process, wrap
// the existing box with the live auth uid as owner. The truly-pre-auth
// case (no Supabase user at all) still throws — that's a real bug.
//
// These tests pin the invariant via source-grep + structural assertions.
// Production singletons (Supabase, HiveService) can't be DI'd from a
// pure-VM unit test, so we assert the SHAPE of the fix code path.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String relativePath) {
  final file = File('${Directory.current.path}/$relativePath');
  return file.readAsStringSync();
}

void main() {
  group('Test #12.7 — GuardedBox auto-open at the wrapper layer', () {
    test('imports Supabase from supabase_flutter', () {
      final src = _src('lib/core/services/guarded_box.dart');
      expect(
        src,
        contains("import 'package:supabase_flutter/supabase_flutter.dart'"),
        reason: 'wrapUserScopedBox must read the live auth uid from '
            'Supabase.instance to pick up the close-race window.',
      );
    });

    test(
      'wrapUserScopedBox falls through to live-auth path when session is closed',
      () {
        final src = _src('lib/core/services/guarded_box.dart');

        final fnIdx = src.indexOf('GuardedBox<T> wrapUserScopedBox<T>');
        expect(fnIdx, greaterThan(0));

        final endIdx = src.indexOf('\n}', fnIdx);
        final body = src.substring(fnIdx, endIdx > 0 ? endIdx : src.length);

        // Must read the live auth uid.
        expect(
          body,
          contains('Supabase.instance.client.auth.currentUser?.id'),
          reason: 'wrapUserScopedBox must consult the live Supabase '
              'session as a fallback when HiveUserSession is closed.',
        );

        // Must check Hive.isBoxOpen — the synchronous fast path that
        // recovers from a brief close-race without forcing every sync
        // caller to await an async openForUser.
        expect(
          body,
          contains('Hive.isBoxOpen('),
          reason: 'wrapUserScopedBox should reuse an already-open '
              'namespaced box when HiveUserSession was briefly closed '
              'but the underlying file is still open.',
        );
      },
    );

    test(
      'wrapUserScopedBox still throws when no auth user exists',
      () {
        final src = _src('lib/core/services/guarded_box.dart');

        final fnIdx = src.indexOf('GuardedBox<T> wrapUserScopedBox<T>');
        final endIdx = src.indexOf('\n}', fnIdx);
        final body = src.substring(fnIdx, endIdx > 0 ? endIdx : src.length);

        // The StateError surface must remain — truly-pre-auth callers
        // shouldn't silently no-op, they should fail loudly so we
        // notice the call-ordering bug.
        expect(
          body,
          contains('throw StateError('),
          reason: 'pre-auth callers (no Supabase user yet) must still '
              'throw — silent no-op would hide a real call-ordering '
              'bug elsewhere.',
        );
      },
    );
  });

  group('Test #12.7 — SyncService bootstraps HiveUserSession', () {
    test(
      '_ensureSessionOpen helper exists and is called at every public sync entry',
      () {
        final src = _src('lib/core/services/sync_service.dart');

        // Helper is declared.
        expect(
          src,
          contains('Future<String?> _ensureSessionOpen()'),
          reason: 'SyncService must expose a single bootstrap helper '
              'so every entry point inherits the fix without per-call '
              'edits.',
        );

        // Helper calls openForUser (idempotent).
        final helperIdx = src.indexOf('Future<String?> _ensureSessionOpen()');
        final helperEnd = src.indexOf('\n  }', helperIdx);
        final helperBody = src.substring(helperIdx, helperEnd);
        expect(
          helperBody,
          contains('HiveUserSession.openForUser'),
          reason: '_ensureSessionOpen must call openForUser to '
              'idempotently open the per-user namespaced boxes.',
        );

        // Each public sync entry awaits _ensureSessionOpen before any
        // user-scoped Hive read.
        for (final method in const [
          'syncWorkoutData',
          'syncNutritionData',
          'pushSnapshot',
          'checkAndSync',
          '_backfillCustomEntityIds',
        ]) {
          final mIdx = src.indexOf('Future<void> $method()');
          expect(mIdx, greaterThan(0),
              reason: '$method() must exist as a Future<void> entry point.');
          final mEnd = src.indexOf('\n  Future<', mIdx + 10);
          final mBody = src.substring(
              mIdx, mEnd > mIdx ? mEnd : (mIdx + 4000).clamp(0, src.length));
          expect(
            mBody,
            contains('_ensureSessionOpen()'),
            reason: '$method must call _ensureSessionOpen before '
                'reading any user-scoped Hive box (closes the cold-start '
                'silent-sync race).',
          );
        }
      },
    );
  });
}
