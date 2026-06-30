// Test #12.6 — regression test for the restore-before-HiveUserSession-open
// race that was producing 30+ `client_errors` rows per cold start
// (`restore_workout_logs`, `restore_nutrition_logs`,
// `restore_user_profile`, `push_snapshot`, `check_and_sync`, etc., each
// throwing `HiveUserSession not opened — cannot wrap user-scoped box "<X>"`).
//
// Root cause: cold-start path is splash → `/restoring`, which calls
// `SyncService.instance.restoreFromCloudForUser()` BEFORE
// `HiveUserSession.openForUser(userId)` (the fresh-sign-in path runs the
// open inside `_ensureLocalUser`, but cold start skips it).
//
// Fix: `restoreFromCloudForUser` is now defensive — it opens
// `HiveUserSession` for the current auth.uid before any restore op runs.
// `openForUser` is documented as idempotent for the same id (see
// `hive_user_session.dart` line 67-94), so this is safe even when an
// upstream caller already opened it.
//
// These tests pin the invariant via source-grep, the same pattern used in
// `test/sync/sync_gap_test.dart` (production singletons can't be DI'd).

import 'package:flutter_test/flutter_test.dart';

import '../contracts/_sync_service_source.dart';

void main() {
  group('Test #12.6 — restoreFromCloudForUser opens HiveUserSession', () {
    test('imports HiveUserSession', () {
      final src = loadSyncServiceSource().readAsStringSync();
      expect(
        src,
        contains("import 'package:icanbefitter/core/services/hive_user_session.dart'"),
        reason: 'sync_service.dart must import HiveUserSession to run the '
            'defensive open before any user-scoped box read.',
      );
    });

    test(
      'calls HiveUserSession.openForUser inside restoreFromCloudForUser, '
      'before any restore op',
      () {
        final src = loadSyncServiceSource().readAsStringSync();

        // Locate the method body.
        final methodSig = 'Future<RestoreResult> restoreFromCloudForUser()';
        final methodIdx = src.indexOf(methodSig);
        expect(methodIdx, greaterThan(0),
            reason: 'restoreFromCloudForUser method not found.');

        // Find the openForUser call.
        final openIdx = src.indexOf('HiveUserSession.openForUser', methodIdx);
        expect(openIdx, greaterThan(methodIdx),
            reason:
                'restoreFromCloudForUser must call HiveUserSession.openForUser '
                '(defensive bootstrap so cold-start callers do not race the '
                'auth-provider _ensureLocalUser path).');

        // Find the first restore op (`_safeRestoreOp(`).
        final firstRestoreOpIdx = src.indexOf('_safeRestoreOp(', methodIdx);
        expect(firstRestoreOpIdx, greaterThan(methodIdx),
            reason: '_safeRestoreOp invocations not found in method.');

        // The open MUST come before the first restore op.
        expect(
          openIdx < firstRestoreOpIdx,
          isTrue,
          reason: 'HiveUserSession.openForUser must be invoked BEFORE the '
              'first _safeRestoreOp; otherwise the user-scoped boxes throw '
              '`HiveUserSession not opened` during the restore writes.',
        );
      },
    );
  });

  group('Test #12.6 — coach_memory column rename (coaching_notes → coach_notes)',
      () {
    test(
      'sync_service.dart no longer selects coach_memory.coaching_notes',
      () {
        final src = loadSyncServiceSource().readAsStringSync();

        // The `coach_memory` table query must NOT request `coaching_notes`.
        // Find the `_restoreCoachMemory` method and inspect the select string.
        // Match the DEFINITION (return-type prefix), not the orchestrator's
        // callsite — and tolerate the C3 `{preFetched}` param.
        final methodIdx = src.indexOf('Future<void> _restoreCoachMemory(');
        expect(methodIdx, greaterThan(0),
            reason: '_restoreCoachMemory method not found.');

        // Window of ~600 chars covers the .from('coach_memory').select(...)
        final endIdx = methodIdx + 800;
        final window =
            src.substring(methodIdx, endIdx > src.length ? src.length : endIdx);

        expect(window, contains("from('coach_memory')"),
            reason: '_restoreCoachMemory must query coach_memory.');
        expect(window, contains('coach_notes'),
            reason: 'Cloud column is `coach_notes` (singular table); the '
                '.select() must request that column.');
        expect(
          window.contains("'coaching_notes'") ||
              window.contains(', coaching_notes'),
          isFalse,
          reason: 'coach_memory.coaching_notes does NOT exist in the cloud '
              'schema; the correct column is `coach_notes`. The SELECT must '
              'not list `coaching_notes` inside the coach_memory query.',
        );
      },
    );

    test(
      'Hive field-name contract preserved — coachBox stores under '
      '`coaching_notes` key',
      () {
        // The cloud column was renamed but the Hive coachBox key stays
        // `coaching_notes` so existing readers (AiCoachRepository,
        // tool_dispatcher, coach_memory.dart) keep working unchanged.
        final src = loadSyncServiceSource().readAsStringSync();
        expect(
          src,
          contains("await coach.put('coaching_notes', notes)"),
          reason: 'Hive write key must stay `coaching_notes` — only the cloud '
              'select column changed (CLAUDE.md §15 Hive field-name contract).',
        );
      },
    );
  });

  group('Test #12.6 — realtime JWT refresh', () {
    test(
      'subscribeToRealtimeSync refreshes the session before subscribing',
      () {
        final src = loadSyncServiceSource().readAsStringSync();

        // The method must be async (returns Future) and must call
        // refreshSession on the auth client.
        expect(
          src,
          contains('Future<void> subscribeToRealtimeSync()'),
          reason: 'subscribeToRealtimeSync must be async so it can refresh '
              'the JWT before opening the realtime channel.',
        );

        // Locate the method body and verify refreshSession is called.
        final methodIdx = src.indexOf('Future<void> subscribeToRealtimeSync()');
        expect(methodIdx, greaterThan(0));
        final endIdx = methodIdx + 1500;
        final window =
            src.substring(methodIdx, endIdx > src.length ? src.length : endIdx);

        expect(
          window,
          contains('refreshSession()'),
          reason: 'subscribeToRealtimeSync must call '
              '_supabase.client.auth.refreshSession() before subscribing — '
              'otherwise stale JWTs surface as '
              '`RealtimeSubscribeException: Token has expired`.',
        );
      },
    );

    test(
      'realtime stream onError reconnects with refreshed JWT on token-expired',
      () {
        final src = loadSyncServiceSource().readAsStringSync();

        // The reconnect helper exists.
        expect(
          src,
          contains('_reconnectRealtimeWithRefreshedJwt'),
          reason: 'There must be a reconnect helper that refreshes the JWT '
              'and re-attaches the realtime stream after a token-expired '
              'error.',
        );

        // The onError handler checks for token-expired markers.
        expect(
          src,
          contains('token has expired'),
          reason: 'onError must detect "Token has expired" messages so it '
              'can trigger the JWT-refresh reconnect path.',
        );
      },
    );
  });
}
