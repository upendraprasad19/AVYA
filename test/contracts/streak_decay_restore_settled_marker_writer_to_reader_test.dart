// b4e7a1 — writer -> reader contract for the per-account RESTORE-SETTLED MARKER
// that gates the streak-decay persist (SoT concept
// `streak_decay_restore_settled_marker`; Gate 9 requires this file by name).
//
// SOURCE-GREP, so it proves PRESENCE ONLY
// (`feedback_source_grep_false_confidence`). The behaviour — the marker is set
// only by a settled restore, cleared on a swap, withheld on a reported failure —
// is `streak_reckon_restore_settled_behavioral_test.dart`, which carries the
// mutation proof. What this file adds is a MANIFEST: who may write the marker
// and who may read it. A new writer (a second place that "also" marks a restore
// settled) or a new reader (another decision keyed on the marker) must be a
// deliberate edit HERE, not a drive-by. The old gate was a process-wide counter
// that three screens read for three purposes; that is how it came to gate
// something it was never meant to.
//
// Comments are stripped before every assertion
// (`feedback_source_grep_strip_comments_first`).
//
// Run: flutter test test/contracts/streak_decay_restore_settled_marker_writer_to_reader_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _stripComments(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), ' ')
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i == -1 ? l : l.substring(0, i);
    })
    .join('\n');

Iterable<File> _dartFilesUnder(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

String _norm(String p) => p.replaceAll('\\', '/');

void main() {
  const syncService = 'lib/core/services/sync_service.dart';

  group('writers of the marker', () {
    test('only sync_service.dart assigns _restoreSettledUserId, at exactly '
        'three sites (clear on swap, settle, test seam)', () {
      final assigners = <String>[];
      var sites = 0;
      for (final f in _dartFilesUnder('lib')) {
        final src = _stripComments(f.readAsStringSync());
        final n = RegExp(r'_restoreSettledUserId\s*=[^=]').allMatches(src).length;
        if (n > 0) {
          assigners.add(_norm(f.path));
          sites += n;
        }
      }
      expect(assigners, [syncService],
          reason: 'the marker is private to SyncService; a part file or a '
              'second library assigning it is a second writer');
      expect(sites, 3,
          reason: 'expected the _onUserChanged clear, _settleRestoreMarker and '
              'the debugSetRestoreSettledUserIdForTest seam; a fourth is a new '
              'place that can mark a restore settled');
    });

    test('the settle write sits behind shouldSettleRestoreMarker', () {
      final src = _stripComments(File(syncService).readAsStringSync());
      final at = src.indexOf('void _settleRestoreMarker(');
      expect(at, isNonNegative);
      final body = src.substring(at, src.indexOf('\n  }\n', at));
      final guard = body.indexOf('shouldSettleRestoreMarker(');
      final write = body.indexOf('_restoreSettledUserId = uid');
      expect(guard, isNonNegative);
      expect(write, greaterThan(guard),
          reason: 'the marker would be written before the decision is taken');
    });
  });

  group('readers of the marker', () {
    test('the getter is read by exactly its definition, the reckon gate and the '
        'post-restore reckon', () {
      final readers = <String>{};
      for (final f in _dartFilesUnder('lib')) {
        if (_stripComments(f.readAsStringSync())
            .contains('restoreSettledForCurrentUser')) {
          readers.add(_norm(f.path));
        }
      }
      expect(readers, {
        syncService,
        'lib/features/train/repositories/workout_repository.dart',
        'lib/core/services/day_rollover_service.dart',
      },
          reason: 'a new file deciding on the marker must be added here on '
              'purpose (the dev simulator only MENTIONS it, in a comment)');
    });

    test('the gate (reckonStreakDecayAndPersist) reads the marker, not the tick, '
        'except behind the kill switch', () {
      final src = _stripComments(
          File('lib/features/train/repositories/workout_repository.dart')
              .readAsStringSync());
      final at = src.indexOf('int reckonStreakDecayAndPersist(');
      expect(at, isNonNegative);
      final body = src.substring(at, src.indexOf('\n  }\n', at));
      expect(body, contains('SyncFlags.streakReckonUserGateEnabled'));
      expect(body, contains('SyncService.instance.restoreSettledForCurrentUser'));
      // The tick may appear ONLY as the kill-switch arm of the ternary.
      final tick = RegExp(r'restoreCompletedTick').allMatches(body).length;
      expect(tick, 1,
          reason: 'the tick is the kill-switch fallback only; a second read is '
              'the process-wide gate coming back');
    });

    test('the getter requires the marker, the live account AND the Hive owner',
        () {
      final src = _stripComments(File(syncService).readAsStringSync());
      final at = src.indexOf('bool get restoreSettledForCurrentUser');
      expect(at, isNonNegative);
      final body = src.substring(at, src.indexOf('\n  }\n', at));
      expect(body, contains('marker == _liveUserId'));
      expect(body, contains('HiveUserSession.currentOwnerFullId'));
    });
  });
}
