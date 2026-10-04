import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

/// Behavioral + structural regression tests for diagnose e5c2d1 — an account
/// swap left the OUTGOING user's restore and write fan-out still running
/// against the INCOMING user's session.
///
/// On 2026-08-06 that produced, in one session: 22 x 42501 "new row violates
/// row-level security policy for table nutrition_logs" over ~9 seconds, then
/// 14 x "HiveError: Box has already been closed" across seven restore ops.
/// Both are silent to the user.
///
/// TWO properties are under test and they need different instruments:
///
///   1. WHAT the predicate decides — pure logic, tested directly below.
///   2. WHERE the guard is called — at the write SINK, not at function entry.
///      A predicate test cannot see placement, and placement IS the bug
///      (`feedback_pause_flag_guard_the_sink`: an in-flight call already past
///      an entry check still reaches the sink). The second group pins that
///      structurally, with comments stripped first so a commented-out guard
///      cannot satisfy it (`feedback_source_grep_strip_comments_first`).
void main() {
  group('e5c2d1 — the predicate', () {
    test('same owner, live session unchanged → do NOT abort', () {
      expect(SyncService.ownerChangedFrom('user-a', 'user-a'), isFalse);
      expect(SyncService.restoreAborted(false, 'user-a', 'user-a'), isFalse);
    });

    test('owner swapped mid-flight → abort', () {
      // The exact 2026-08-06 shape: captured d7a67a37 at entry, session had
      // advanced to 9e6bde97 by the time the sink was reached.
      expect(SyncService.ownerChangedFrom('d7a67a37', '9e6bde97'), isTrue);
      expect(SyncService.restoreAborted(false, 'd7a67a37', '9e6bde97'), isTrue);
    });

    test('live owner UNREADABLE (null) → abort, i.e. fails SAFE', () {
      // Signed out mid-restore, or Supabase not initialised. The dangerous
      // reading of null is "nobody owns this, carry on".
      expect(SyncService.ownerChangedFrom('user-a', null), isTrue,
          reason: 'an unknown live owner must never be treated as a match');
      expect(SyncService.restoreAborted(false, 'user-a', null), isTrue);
    });

    test('explicit cancellation aborts even when the owner still matches', () {
      expect(SyncService.restoreAborted(true, 'user-a', 'user-a'), isTrue);
    });

    test('ownerChangedFrom IGNORES the cancellation flag', () {
      // Deliberate asymmetry. Cancelling a RESTORE says nothing about whether
      // an unrelated write fan-out may still push its rows; conflating them
      // would silently stop syncing after any cancelled restore.
      expect(SyncService.ownerChangedFrom('user-a', 'user-a'), isFalse);
      expect(SyncService.restoreAborted(true, 'user-a', 'user-a'), isTrue,
          reason: 'restoreAborted honours cancellation; ownerChangedFrom must '
              'not, or one cancelled restore mutes all later syncing');
    });
  });

  group('e5c2d1 — the guard sits at the SINK', () {
    /// Comments stripped so a commented-out guard cannot satisfy the check.
    String strippedNutritionSync() {
      final raw = File('lib/core/services/sync/sync_nutrition.dart')
          .readAsStringSync();
      return raw
          .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
          .split('\n')
          .map((l) {
            final i = l.indexOf('//');
            return i == -1 ? l : l.substring(0, i);
          })
          .join('\n');
    }

    test('every network write is preceded by an owner re-check', () {
      final lines = strippedNutritionSync().split('\n');
      final sinkRe = RegExp(r'\.upsert\(|\.delete\(\)');
      final guardRe = RegExp(r'ownerChangedSince\(');

      final unguarded = <String>[];
      for (var i = 0; i < lines.length; i++) {
        if (!sinkRe.hasMatch(lines[i])) continue;
        // Look back a bounded window — "at the sink" means adjacent, not
        // "somewhere in the function".
        final from = (i - 12).clamp(0, lines.length);
        final window = lines.sublist(from, i).join('\n');
        if (!guardRe.hasMatch(window)) {
          unguarded.add('line ${i + 1}: ${lines[i].trim()}');
        }
      }

      expect(unguarded, isEmpty,
          reason: 'PRE-FIX ALL of these were unguarded. Each is a network '
              'write that can execute after an account swap has already '
              'advanced the session. RLS caught the 2026-08-06 direction, but '
              'the opposite interleaving (captured id == NEW user, rows from '
              'the OLD user\'s Hive box) satisfies auth.uid() = user_id and '
              'would be WRITTEN. Unguarded sinks:\n${unguarded.join('\n')}');
    });

    test('the three sibling fan-out methods each guard independently', () {
      // Round-1 review finding R1-P1-5: a `return` in _syncNutritionLogs does
      // not stop _syncWaterLogs and _syncSavedMeals, which run as siblings
      // under Future.wait. One guard in one sibling is not coverage.
      final src = strippedNutritionSync();
      for (final fn in [
        '_syncNutritionLogs',
        '_syncWaterLogs',
        '_syncSavedMeals',
      ]) {
        final start = src.indexOf('Future<void> $fn(');
        expect(start, isNot(-1), reason: '$fn must exist');
        final next = src.indexOf('\n  Future<', start + 1);
        final body = src.substring(start, next == -1 ? src.length : next);
        expect(body.contains('ownerChangedSince('), isTrue,
            reason: '$fn runs under the same Future.wait as its siblings, so '
                'it needs its OWN sink guard — a return elsewhere cannot stop '
                'it');
      }
    });
  });
}
