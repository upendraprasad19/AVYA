// Contract test — Monday +1 refill restore race (2026-05-19).
//
// Pins the two-layer fix for the refill vs cloud restore race:
//   B0a — `_restoreFreezes` uses max-merge on (available, last_refill),
//         not blind overwrite of cloud → local.
//   B0b — `restoring_screen.dart` invokes `refillIfNewWeek()` from inside
//         `_ensureOwnershipBeforeHome` post-openForUser as defence-in-depth.
//
// Relocation note (2026-05-22 / diagnose dc52a4):
//   The B0b refill call + B3 just_used clear ORIGINALLY lived in
//   splash_screen.dart `_runDeferredInit` and were re-invoked via an
//   `onRestoreComplete` listener. That placement hit a pre-openForUser
//   race: splash touched `userBox` BEFORE HiveUserSession.openForUser ran
//   inside restoreFromCloudForUser → `streak_freeze_refill_check` died
//   with "HiveUserSession not opened" on every cold start since at least
//   2026-05-06. Both calls relocated into restoring_screen post-openForUser.
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
    // Refactor 2026-06-11 / diagnose a8f3d1 — the (available, last_refill)
    // max-merge that lived inline in _restoreFreezes moved into the pure
    // StreakProgressService.mergeFreezeProgress, which ALSO unions the PER-WEEK
    // used_dates leg the inline version clobbered (a freeze consumed during the
    // bg-restore window was wiped + refunded → spurious streak break). The
    // cloudWins/compareTo/clamp patterns now live in the helper; _restoreFreezes
    // DELEGATES to it. The grep targets follow the code to its new home.
    final svc = File('lib/core/services/streak_progress_service.dart')
        .readAsStringSync();
    final svcStripped = _stripComments(svc);

    test('_restoreFreezes delegates to StreakProgressService.mergeFreezeProgress',
        () {
      expect(
        stripped.contains('StreakProgressService.mergeFreezeProgress('),
        isTrue,
        reason: '_restoreFreezes must route the local↔cloud reconciliation '
            'through the pure mergeFreezeProgress helper (a8f3d1) instead of an '
            'inline overwrite that clobbered the just-consumed used_dates leg.',
      );
    });

    test('mergeFreezeProgress declares cloudWins variable for the decision', () {
      expect(
        svcStripped.contains('cloudWins'),
        isTrue,
        reason: 'mergeFreezeProgress must compute cloudWins via last_refill '
            'compareTo to decide which side wins on (available, last_refill). '
            'Pre-fix _restoreFreezes did a blind overwrite that clobbered fresh '
            'local refills.',
      );
    });

    test('mergeFreezeProgress compares last_refill with compareTo (lexical)', () {
      expect(
        RegExp(r'cloudLastRefill\.compareTo\(localLastRefill\)')
            .hasMatch(svcStripped),
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
        reason: 'when local refill is fresher than cloud (merged.scheduleSyncUp), '
            '_restoreFreezes must schedule a syncFreezes() so cloud catches up.',
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

  group('B0b — restoring_screen invokes refillIfNewWeek post-openForUser', () {
    final src = File('lib/features/auth/screens/restoring_screen.dart')
        .readAsStringSync();
    final stripped = _stripComments(src);

    test('imports StreakProgressService', () {
      expect(
        stripped.contains(
            "import 'package:icanbefitter/core/services/streak_progress_service.dart'"),
        isTrue,
        reason: 'restoring_screen must import StreakProgressService for the '
            'post-openForUser refill invocation (diagnose dc52a4).',
      );
    });

    test('_ensureOwnershipBeforeHome calls refillIfNewWeek', () {
      expect(
        stripped.contains(
            'StreakProgressService.instance.refillIfNewWeek()'),
        isTrue,
        reason: 'restoring_screen must call '
            'StreakProgressService.instance.refillIfNewWeek() inside '
            '_ensureOwnershipBeforeHome so the weekly refill runs AFTER '
            'HiveUserSession.openForUser. Pre-fix this lived in splash and '
            'died with "HiveUserSession not opened" on every cold start.',
      );
    });

    test('refill call is wrapped in try/catch with telemetry', () {
      // The refill MUST be defensive — failures are non-fatal because the
      // user must still reach home. Pre-fix the splash listener swallowed
      // errors silently with no telemetry; the post-fix shape records
      // non-fatal so we can detect regressions.
      expect(
        RegExp(r'refillIfNewWeek\(\)[\s\S]{0,400}?'
                r'recordNonFatal\([^)]*reason:\s*'
                r"'restoring_post_restore_refill'")
            .hasMatch(stripped),
        isTrue,
        reason: 'refillIfNewWeek call must be wrapped in try/catch with '
            'ErrorTelemetry.recordNonFatal(reason: '
            "'restoring_post_restore_refill') so we get telemetry on "
            'silent failure (the pre-fix splash listener had none).',
      );
    });
  });

  group('B3 — restoring_screen clears stale streak_freeze_just_used', () {
    final src = File('lib/features/auth/screens/restoring_screen.dart')
        .readAsStringSync();
    final stripped = _stripComments(src);

    test('cold-start path writes streak_freeze_just_used: false', () {
      // The clear is a defensive UI-flag reset. Relocated from splash to
      // restoring_screen 2026-05-22 / diagnose dc52a4 — must run AFTER
      // HiveUserSession.openForUser to avoid the pre-openForUser race that
      // killed the clear on every cold start.
      expect(
        RegExp(r"'streak_freeze_just_used'\s*:\s*false").hasMatch(stripped),
        isTrue,
        reason: 'restoring_screen._ensureOwnershipBeforeHome must clear the '
            'stale streak_freeze_just_used Hive flag after openForUser '
            'returns. Pre-fix this lived in splash and silently failed.',
      );
    });
  });
}
