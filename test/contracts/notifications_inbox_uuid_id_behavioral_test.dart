// Behavioral regression test for diagnose a4f1c8 — the welcome notification
// could NEVER sync, on every install, forever.
//
// `notification_inbox_service.dart` minted `local-welcome-<microseconds>` and
// `syncNotificationsInboxEntry` forwards `entry['id']` verbatim into
// `notifications_inbox.id`, which is a Postgres `uuid` column. Every attempt
// returned 22P02 `invalid input syntax for type uuid` — observed 6× in a
// single 1.0.0+38 session, because it retries.
//
// Two halves, both asserted here:
//   1. the WRITER now mints a real uuid, and
//   2. the SYNC SEAM refuses to forward an id that cannot cast, so pre-fix
//      installs (which still hold a `local-welcome-…` row in Hive) stop
//      retrying a write that is guaranteed to fail.
//
// Half 2 is what makes this non-vacuous for existing users: fixing only the
// writer would leave every already-seeded install failing forever.

import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/features/profile/services/notification_inbox_service.dart';

void main() {
  group('notifications_inbox id must be castable to uuid (a4f1c8)', () {
    test('the exact legacy id shape is rejected', () {
      // Verbatim from the live telemetry row that motivated this fix:
      // PostgrestException(message: invalid input syntax for type uuid:
      //   "local-welcome-1786019702890010", code: 22P02)
      expect(
        isUuidShaped('local-welcome-1786019702890010'),
        isFalse,
        reason: 'THE REGRESSION: this id reached a uuid column and produced '
            '22P02 on every retry. The seam must not forward it.',
      );
    });

    test('a real uuid is accepted', () {
      // Hardcoded on purpose: INDEPENDENT ground truth, not something minted
      // by the same code under test. This case must keep meaning even if the
      // writer's mint changes.
      const id = '3f2504e0-4f89-11d3-9a0c-0305e82c3301';
      expect(
        isUuidShaped(id),
        isTrue,
        reason: 'DISCRIMINATOR: a guard that rejected everything would also '
            'make the first assertion pass while silently dropping every '
            'legitimate notification sync.',
      );
    });

    test('the WRITER produces an id the seam will forward', () {
      // Calls the PRODUCTION mint, not a uuid the test makes itself.
      //
      // The first version of this case did `final seededId = const Uuid().v4()`
      // — which is circular: it re-implemented the writer and then checked its
      // own work, so reverting `notification_inbox_service.dart` to
      // 'local-welcome-<micros>' left all four cases GREEN (round-1 review,
      // P1-4). Binding to `newLocalNotificationId()` is what makes that
      // mutation fail here.
      final seededId = NotificationInboxService.newLocalNotificationId();
      expect(
        isUuidShaped(seededId),
        isTrue,
        reason: 'writer and seam are ONE contract; the bug was that they '
            'disagreed. Reverting the writer must break this.',
      );
    });

    test('near-miss shapes are rejected, not coerced', () {
      // Guards against a lazy `contains('-')`-style predicate that would let
      // a malformed id through to Postgres and reintroduce 22P02.
      const cases = <String>[
        '',
        'local-welcome-1786019702890010',
        '1786019702890010',
        'not-a-uuid',
        // right group count, wrong widths
        'abcdefg-1234-5678-9abc-def012345678',
        // trailing junk after an otherwise valid uuid
        '3f2504e0-4f89-11d3-9a0c-0305e82c3301x',
        // non-hex character in the final group
        '3f2504e0-4f89-11d3-9a0c-0305e82c330g',
      ];
      for (final c in cases) {
        expect(isUuidShaped(c), isFalse, reason: 'must reject: "$c"');
      }
    });
  });
}
