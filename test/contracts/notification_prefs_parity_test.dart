// test/contracts/notification_prefs_parity_test.dart
//
// Two guarantees the arc CLAIMED but did not have. Both were found by the
// B-pass, and both are the kind of gap that lets the feature quietly revert to
// the state it started in.
//
// 1. PARITY. NotificationPrefsRepository's docstring said key parity was
//    "pinned by test/contracts/notification_prefs_parity_test.dart" — a file
//    that did not exist. A key present client-side but absent server-side is a
//    toggle that does nothing; a key server-side but never emitted falls
//    through to absent-means-SEND and is unreachable.
//
// 2. THE EMISSION ITSELF. Nothing pinned the one line that makes the whole arc
//    work. Deleting the emission from compileDailySnapshot left all 27 other
//    new tests green — including the TRAP-1 test, which proves the trimmer
//    WOULD drop the key but says nothing about where it is emitted.
//
// Run: flutter test test/contracts/notification_prefs_parity_test.dart

import 'dart:io';

import 'package:icanbefitter/features/profile/services/notification_prefs_repository.dart';
import 'package:test/test.dart';

const _dedup = 'supabase/functions/_shared/proactive_dedup.ts';
const _syncService = 'lib/core/services/sync_service.dart';

String _strip(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');

void main() {
  group('client registry <-> server ProactiveType parity', () {
    test('every client key exists in the server vocabulary', () {
      final union = _strip(File(_dedup).readAsStringSync());
      // The union members that carry a preference toggle. Two server types
      // (morning_brief, workout_window, protein_gap, streak_protection,
      // subscription_expiry) use the legacy N8 names — that rename is its own
      // unit, so map them here rather than pretend the sets are already equal.
      const legacyServerName = <String, String>{
        'morning_checkin': 'morning_brief',
        'workout_reminders': 'workout_window',
        'protein_alerts': 'protein_gap',
        'streak_alerts': 'streak_protection',
        'subscription_reminders': 'subscription_expiry',
      };

      final missing = <String>[];
      for (final key in NotificationPrefsRepository.allKeys) {
        final serverName = legacyServerName[key] ?? key;
        if (!union.contains('"$serverName"')) missing.add('$key ($serverName)');
      }
      expect(missing, isEmpty,
          reason: 'These client keys have no counterpart in ProactiveType, so '
              'the toggle cannot be honoured:\n  ${missing.join("\n  ")}');
    });

    test('the registry has exactly the 10 keys the UI and server agree on', () {
      expect(NotificationPrefsRepository.allKeys.length, 10);
      expect(NotificationPrefsRepository.allKeys.toSet().length, 10,
          reason: 'a duplicate key would silently shadow itself in emissionMap');
    });

    test('rank_promotion is in the union but is NOT day-deduped', () {
      final src = File(_dedup).readAsStringSync();
      expect(_strip(src).contains('"rank_promotion"'), isTrue);
      // Round-3 F8: shouldSendProactive compares a SINGLE last_proactive_type
      // slot, so stamping a promotion would overwrite whatever was last sent
      // and let a same-day pr_celebration fire again. The reasoning must stay
      // written down next to the type, or someone will "complete" the pattern.
      expect(src.contains('markProactiveSent'), isTrue,
          reason: 'sanity — the helper still exists');
      final promo = File('supabase/functions/proactive-coach-promotion/index.ts')
          .readAsStringSync();
      expect(_strip(promo).contains('markProactiveSent'), isFalse,
          reason: 'proactive-coach-promotion must NOT stamp the shared dedup '
              'slot — doing so weakens dedup for every other proactive type.');
    });
  });

  group('the emission itself is pinned', () {
    test('compileDailySnapshot emits notification_preferences', () {
      final src = _strip(File(_syncService).readAsStringSync());
      expect(src.contains("'notification_preferences':"), isTrue,
          reason: 'THE line that makes the arc work. Without it the key never '
              'reaches the snapshot and every server guard falls through to '
              'send — the exact state this batch started from (0 of 91 rows).');
      expect(src.contains('NotificationPrefsRepository.emissionMap()'), isTrue,
          reason: 'must go through the repository — it owns the session check, '
              'the normalisation and the never-throw contract.');
    });

    test('it is emitted AFTER the trimmed aiContext spread', () {
      final src = _strip(File(_syncService).readAsStringSync());
      final spread = src.indexOf('...aiContext');
      final emit = src.indexOf("'notification_preferences':");
      expect(spread, greaterThan(-1));
      expect(emit, greaterThan(spread),
          reason: 'buildAiContext returns an ALREADY-trimmed map, and this key '
              'is not in the trimmer keep-set. Emitted before/inside the '
              'spread it becomes trimmable again, and a trimmed key reads to '
              'the server as absent — which means SEND. Order is the fix.');
    });
  });
}
