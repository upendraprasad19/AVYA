// Contract test — Monday +1 refill restore race (2026-05-19).
//
// Pins the two-layer fix for the splash-time refill vs cloud restore race:
//   B0a — `_restoreFreezes` uses max-merge on (available, last_refill),
//         not blind overwrite of cloud → local.
//   B0b — `splash_screen.dart` re-invokes `refillIfNewWeek()` from the
//         existing `onRestoreComplete` listener as defence-in-depth.
//
// Source-grep with comment-stripping per
// `feedback_source_grep_strip_comments_first.md` — the fix's explanatory
// comments quote the pre-fix patterns and would false-positive otherwise.

import 'dart:io';
import 'package:test/test.dart';

String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  group('B0a — _restoreFreezes max-merge', () {
    final src = File('lib/core/services/sync/sync_restore_completeness.dart')
        .readAsStringSync();
    final stripped = _stripComments(src);

    test('declares cloudWins variable for max-merge decision', () {
      expect(
        stripped.contains('cloudWins'),
        isTrue,
        reason: '_restoreFreezes must compute cloudWins via last_refill '
            'compareTo to decide which side wins on (available, last_refill). '
            'Pre-fix did a blind overwrite that clobbered fresh local refills.',
      );
    });

    test('compares last_refill with compareTo (lexical YYYY-MM-DD)', () {
      expect(
        RegExp(r'cloudLastRefill\.compareTo\(localLastRefill\)')
            .hasMatch(stripped),
        isTrue,
        reason: 'max-merge must compare last_refill via String.compareTo so '
            'the side stamped with the newer Monday wins both available + '
            'last_refill.',
      );
    });

    test('local-wins branch schedules SyncService.syncFreezes', () {
      expect(
        RegExp(r'SyncService\.instance\.syncFreezes\(\)').hasMatch(stripped),
        isTrue,
        reason: 'when local refill is fresher than cloud, _restoreFreezes '
            'must schedule a syncFreezes() so cloud catches up.',
      );
    });

    test('blind unconditional overwrite of available is gone', () {
      // Pre-fix shape: `existingMap['streak_freezes_available'] = rawAvailable.clamp(0, 3);`
      // OUTSIDE any conditional. The fix puts it inside `if (cloudWins)`.
      // Strip comments so the explanatory block doesn't false-positive.
      final blind = RegExp(
          r"^\s*existingMap\['streak_freezes_available'\]\s*=\s*rawAvailable",
          multiLine: true);
      expect(
        blind.hasMatch(stripped),
        isFalse,
        reason:
            'unconditional `existingMap[streak_freezes_available] = rawAvailable` '
            'must NOT appear in code (it does in comments — comments are stripped). '
            'Use the cloudWins/local-wins branch instead.',
      );
    });
  });

  group('B0b — splash re-invokes refillIfNewWeek on onRestoreComplete', () {
    final src = File('lib/features/auth/screens/splash_screen.dart')
        .readAsStringSync();
    final stripped = _stripComments(src);

    test('imports StreakProgressService', () {
      expect(
        stripped.contains(
            "import 'package:icanbefitter/core/services/streak_progress_service.dart'"),
        isTrue,
        reason: 'splash must import StreakProgressService for the post-restore '
            'refill re-invocation.',
      );
    });

    test('onRestoreComplete listener calls refillIfNewWeek', () {
      expect(
        RegExp(r'onRestoreComplete\.listen[\s\S]*?'
                r'StreakProgressService\.instance\.refillIfNewWeek\(\)')
            .hasMatch(stripped),
        isTrue,
        reason: 'splash._restoreSub listener must invoke '
            'StreakProgressService.instance.refillIfNewWeek() so the '
            'weekly refill is re-applied after cloud restore lands.',
      );
    });

    test('listener invalidates streakFreezeProvider for badge refresh', () {
      expect(
        RegExp(r'onRestoreComplete\.listen[\s\S]*?'
                r'ref\.invalidate\(streakFreezeProvider\)')
            .hasMatch(stripped),
        isTrue,
        reason: 'after re-refill the streakFreezeProvider badge must be '
            'invalidated so the 0/3 badge updates without a manual reload.',
      );
    });
  });

  group('B3 — splash cold-start clears stale streak_freeze_just_used', () {
    final src = File('lib/features/auth/screens/splash_screen.dart')
        .readAsStringSync();
    final stripped = _stripComments(src);

    test('cold-start path writes streak_freeze_just_used: false', () {
      // The clear is a defensive UI-flag reset. After comment-strip the only
      // remaining occurrence of the literal key with value `: false` must be
      // the clear. Pre-fix the file had no such write at all.
      expect(
        RegExp(r"'streak_freeze_just_used'\s*:\s*false").hasMatch(stripped),
        isTrue,
        reason: 'splash._runDeferredInit must clear the stale '
            'streak_freeze_just_used Hive flag on cold start to prevent '
            'banner-leak from prior sessions.',
      );
    });
  });
}
