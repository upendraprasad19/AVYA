// Day-swapper + sync-load Task 19, spec §5.12 / plan D2 — the last 3
// (of 14) now()-fallback sites: onboarding replay's phase_started_at /
// plan_generated_at, and the 2 notifications-inbox sites (push + restore).
// A sync payload never sends "now" as a fallback for a past timestamp: the
// resolution order is the recorded value, then a derived *_ms/key value,
// then OMIT the field. All three sites here have no *_ms sibling to derive
// from, so the third rung applies directly.
//
// Deviation from the task brief's literal test text, recorded here because
// it changes what a reader would expect: the onboarding-replay "omitted"
// assertion below checks `body['p_phase_started_at']` is null rather than
// `body.containsKey('p_phase_started_at')` is false. Reason: the omission
// fix in `_replayPendingOnboardingSync` only removes the key from the
// `progressData` map it builds. That map passes through
// `UserRepository.syncOnboardingToSupabase` -> `_sanitize` (which correctly
// drops keys absent from its input) -> `SyncService.pushOnboardingProgressSnapshot`,
// whose `rpcParams` is a Dart map LITERAL:
//   'p_phase_started_at': progressData['phase_started_at'],
// A map-literal key is always present in the built map regardless of
// whether the source map had it — accessing a missing key just yields
// `null`. `postgrest`'s `PostgrestRpcBuilder.rpc` sends that map verbatim as
// the JSON body (`postgrest_rpc_builder.dart` `body: params`, encoded via
// plain `jsonEncode` in `postgrest_builder.dart` with no null-stripping), so
// the wire body always carries the key. Functionally this is harmless —
// PostgREST treats an explicit JSON `null` and an absent key identically as
// a NULL function argument, and migration 115's `update_user_progress_snapshot`
// COALESCEs a NULL parameter to the existing column on UPDATE — so checking
// for `isNull` proves the "never sends now()" contract precisely, while
// `containsKey` would assert a wire-level detail this call chain can't
// deliver no matter how `_replayPendingOnboardingSync` is fixed.
@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import 'sync_domain_skip_harness.dart';

void main() {
  final h = SyncHarness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  group('onboarding replay (_replayPendingOnboardingSync)', () {
    Future<void> seed({
      String? phaseStartedAt,
      String? planGeneratedAt,
    }) async {
      await HiveService.instance.userBox.put('profile', {
        'full_name': 'Test User',
      });
      await HiveService.instance.userBox.put('progress', {
        'current_phase': 1,
        'total_workouts_done': 0,
        'current_streak_weeks': 0,
        if (phaseStartedAt != null) 'phase_started_at': phaseStartedAt,
        if (planGeneratedAt != null) 'plan_generated_at': planGeneratedAt,
      });
      await HiveService.instance.configBox
          .put('pending_onboarding_sync', true);
    }

    test('a recorded phase_started_at / plan_generated_at is sent verbatim',
        () async {
      h.server.getResponders['users'] = (_) => [];
      await seed(
          phaseStartedAt: '2026-09-01T00:00:00.000Z',
          planGeneratedAt: '2026-09-01T00:05:00.000Z');
      await SyncService.instance
          .replayPendingOnboardingSyncForTest('test-user-1');
      final rpc = h.server.requests
          .singleWhere((r) => r.path == '/rest/v1/rpc/update_user_progress_snapshot');
      final body = rpc.body! as Map;
      expect(body['p_phase_started_at'], '2026-09-01T00:00:00.000Z');
      expect(body['p_plan_generated_at'], '2026-09-01T00:05:00.000Z');
    });

    test(
        'a missing phase_started_at / plan_generated_at is sent as null, '
        'never fabricated as "now" (a retry-until-success replay must not '
        're-stamp a moving target on every failed retry)', () async {
      h.server.clear(); // shared server across tests in this file.
      h.server.getResponders['users'] = (_) => [];
      await seed(); // neither field present
      await SyncService.instance
          .replayPendingOnboardingSyncForTest('test-user-2');
      final rpc = h.server.requests
          .singleWhere((r) => r.path == '/rest/v1/rpc/update_user_progress_snapshot');
      final body = rpc.body! as Map;
      expect(body['p_phase_started_at'], isNull);
      expect(body['p_plan_generated_at'], isNull);
    });
  });

  group('notifications inbox push (syncNotificationsInboxEntry)', () {
    test('a present created_at is sent verbatim; read_at mirrors it when read',
        () async {
      h.server.clear(); // shared server across tests in this file.
      await SyncService.instance.syncNotificationsInboxEntry({
        'id': '11111111-1111-1111-1111-111111111111',
        'category': 'coach',
        'title': 't',
        'body': 'b',
        'created_at': '2026-09-20T10:00:00.000Z',
        'priority': 'normal',
        'read': true,
      });
      final write = h.server.writesTo('notifications_inbox').single;
      expect(write.rows.single['created_at'], '2026-09-20T10:00:00.000Z');
      expect(write.rows.single['read_at'], '2026-09-20T10:00:00.000Z');
    });

    test(
        'a missing created_at omits BOTH created_at and read_at — never '
        'fabricates "now" (the NOT NULL DEFAULT now() column applies on '
        'insert; an update keeps what it has)', () async {
      h.server.clear(); // shared server across tests in this file.
      await SyncService.instance.syncNotificationsInboxEntry({
        'id': '22222222-2222-2222-2222-222222222222',
        'category': 'system',
        'title': 't',
        'body': 'b',
        'priority': 'normal',
        'read': true,
      });
      final write = h.server.writesTo('notifications_inbox').single;
      expect(write.rows.single.containsKey('created_at'), isFalse);
      expect(write.rows.single.containsKey('read_at'), isFalse);
    });
  });

  group('notifications inbox restore (_restoreNotificationsInbox)', () {
    test('a missing cloud created_at omits the Hive field (leaves '
        "AppNotification.fromJson's own DateTime.now() fallback as the only "
        'stand-in, rather than baking a wrong value into Hive)', () async {
      h.server.clear(); // shared server across tests in this file.
      h.server.getResponders['notifications_inbox'] = (_) => [
            {
              'id': '33333333-3333-3333-3333-333333333333',
              'notif_type': 'coach',
              'title': 't',
              'body': 'b',
              'payload': {'priority': 'normal', 'read': false},
              'read_at': null,
              // created_at deliberately absent
            }
          ];
      await SyncService.instance.restoreNotificationsInboxForSyncDomain();
      final stored = HiveService.instance.notificationsBox
          .get('33333333-3333-3333-3333-333333333333') as Map;
      expect(stored.containsKey('created_at'), isFalse);
    });

    test('a present cloud created_at round-trips into Hive verbatim',
        () async {
      h.server.clear(); // shared server across tests in this file.
      h.server.getResponders['notifications_inbox'] = (_) => [
            {
              'id': '44444444-4444-4444-4444-444444444444',
              'notif_type': 'pr',
              'title': 't',
              'body': 'b',
              'payload': {'priority': 'gold', 'read': true},
              'read_at': '2026-09-20T11:00:00.000Z',
              'created_at': '2026-09-20T10:00:00.000Z',
            }
          ];
      await SyncService.instance.restoreNotificationsInboxForSyncDomain();
      final stored = HiveService.instance.notificationsBox
          .get('44444444-4444-4444-4444-444444444444') as Map;
      expect(stored['created_at'], '2026-09-20T10:00:00.000Z');
    });
  });
}
