// Slice U6 (ledger F8; diagnose a5e3c7): the words Home shows when a Streak
// Freeze is spent, and the explainer sheet's freeze rules.
//
// Rule kept (founder 2026-10-06): a freeze is a KEPT stock (+1 each Monday),
// spent on a missed scheduled day, and still spent when the streak breaks
// anyway. The old words ("Streak Freeze used! N remaining this week.", "keep
// your streak alive", "per week") described a weekly allowance and a rescue
// the rule does not give.
//
// Three layers, so none of them rests on a source-grep alone:
//   1. the pure copy table (every approved row, argument order, edge inputs);
//   2. `streakFreezeNoticeFromProgress` over real progress maps, including the
//      STALE-SNAPSHOT case that printed "0 remaining" while one freeze was held;
//   3. the explainer sheet RENDERED (a widget test), free and PRO;
// plus a wiring group that is PRESENCE-ONLY by design (it only proves the two
// edited files call the helpers; the behaviour is layers 1 to 3 and
// `streak_freeze_notice_behavioral_test.dart`).
//
// Run: flutter test test/contracts/streak_freeze_notice_copy_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/streak_freeze_copy.dart';
import 'package:icanbefitter/core/services/streak_progress_service.dart';
import 'package:icanbefitter/features/home/widgets/streak_explainer_sheet.dart';

import '../helpers/read_screen_source.dart';

String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((l) => l.replaceFirst(RegExp(r'(?<!:)//.*$'), ''))
    .join('\n');

void main() {
  group('streakFreezeUsedNotice: the approved table', () {
    test('1 spent, n left (n >= 1)', () {
      expect(streakFreezeUsedNotice(used: 1, remaining: 2),
          'Streak Freeze used on a missed day. 2 left.');
      expect(streakFreezeUsedNotice(used: 1, remaining: 1),
          'Streak Freeze used on a missed day. 1 left.');
    });

    test('1 spent, none left', () {
      expect(
        streakFreezeUsedNotice(used: 1, remaining: 0),
        'Streak Freeze used on a missed day. None left. '
        'A new one arrives next Monday.',
      );
    });

    test('k >= 2 spent, n left', () {
      expect(streakFreezeUsedNotice(used: 2, remaining: 1),
          '2 Streak Freezes used on missed days. 1 left.');
      expect(streakFreezeUsedNotice(used: 3, remaining: 2),
          '3 Streak Freezes used on missed days. 2 left.');
    });

    test('k >= 2 spent, none left', () {
      expect(
        streakFreezeUsedNotice(used: 3, remaining: 0),
        '3 Streak Freezes used on missed days. None left. '
        'A new one arrives next Monday.',
      );
    });

    test('live count unknown: no claim about the rest', () {
      expect(streakFreezeUsedNotice(used: 1, remaining: null),
          'Streak Freeze used on a missed day.');
      expect(streakFreezeUsedNotice(used: 2, remaining: null),
          '2 Streak Freezes used on missed days.');
    });

    test('used below 1 reads as 1; a negative remaining reads as none left',
        () {
      expect(streakFreezeUsedNotice(used: 0, remaining: 1),
          'Streak Freeze used on a missed day. 1 left.');
      expect(streakFreezeUsedNotice(used: -4, remaining: 1),
          'Streak Freeze used on a missed day. 1 left.');
      expect(
        streakFreezeUsedNotice(used: 1, remaining: -1),
        'Streak Freeze used on a missed day. None left. '
        'A new one arrives next Monday.',
      );
    });

    test('used and remaining are not interchangeable (argument order pinned)',
        () {
      // used 2 / remaining 1 and used 1 / remaining 2 must read differently.
      final a = streakFreezeUsedNotice(used: 2, remaining: 1);
      final b = streakFreezeUsedNotice(used: 1, remaining: 2);
      expect(a, isNot(b));
      expect(a, startsWith('2 Streak Freezes used'));
      expect(b, startsWith('Streak Freeze used on a missed day'));
    });

    test('no em dash, no "!", and no weekly-allowance wording in any row', () {
      final rows = <String>[
        streakFreezeUsedNotice(used: 1, remaining: 2),
        streakFreezeUsedNotice(used: 1, remaining: 0),
        streakFreezeUsedNotice(used: 3, remaining: 0),
        streakFreezeUsedNotice(used: 2, remaining: null),
        kStreakFreezeRuleMissed,
        streakFreezeRuleRefill(1),
        streakFreezeRuleRefill(3),
        streakFreezeProNote(freeMax: 1, proMax: 3),
      ];
      for (final r in rows) {
        expect(r.contains('—'), isFalse, reason: 'em dash in "$r"');
        expect(r.contains('!'), isFalse, reason: 'exclamation in "$r"');
        expect(r.toLowerCase().contains('per week'), isFalse,
            reason: 'weekly allowance wording in "$r"');
        expect(r.toLowerCase().contains('this week'), isFalse,
            reason: 'weekly allowance wording in "$r"');
        expect(r.toLowerCase().contains('keep your streak alive'), isFalse,
            reason: 'a rescue promise the kept rule does not give: "$r"');
      }
    });
  });

  group('explainer rules', () {
    test('rule 3 and rule 4 and the PRO note read as approved', () {
      expect(kStreakFreezeRuleMissed,
          'Miss a scheduled workout and a Streak Freeze is used for that day automatically.');
      expect(streakFreezeRuleRefill(1),
          'You earn one new Streak Freeze every Monday and can keep up to 1 in reserve.');
      expect(streakFreezeRuleRefill(3),
          'You earn one new Streak Freeze every Monday and can keep up to 3 in reserve.');
      expect(streakFreezeProNote(freeMax: 1, proMax: 3),
          'PRO users can keep up to 3 freezes in reserve instead of 1.');
    });

    test('the PRO note FOLLOWS the caps it is given (nothing hard-coded)', () {
      expect(streakFreezeProNote(freeMax: 2, proMax: 5),
          'PRO users can keep up to 5 freezes in reserve instead of 2.');
    });
  });

  group('streakFreezeNoticeFromProgress: real progress maps', () {
    test('null map, absent flag and a false flag give no notice', () {
      expect(streakFreezeNoticeFromProgress(null), isNull);
      expect(streakFreezeNoticeFromProgress(<String, dynamic>{}), isNull);
      expect(
        streakFreezeNoticeFromProgress(<String, dynamic>{
          'streak_freeze_just_used': false,
          'streak_freezes_available': 2,
        }),
        isNull,
      );
      // Only a real `true` counts (a stray string must not raise a notice).
      expect(
        streakFreezeNoticeFromProgress(<String, dynamic>{
          'streak_freeze_just_used': 'true',
          'streak_freezes_available': 2,
        }),
        isNull,
      );
    });

    test('flag with no count reads as one freeze (a pre-count build)', () {
      expect(
        streakFreezeNoticeFromProgress(<String, dynamic>{
          'streak_freeze_just_used': true,
          'streak_freezes_available': 1,
        }),
        'Streak Freeze used on a missed day. 1 left.',
      );
    });

    test('the count key selects the plural row', () {
      expect(
        streakFreezeNoticeFromProgress(<String, dynamic>{
          'streak_freeze_just_used': true,
          'streak_freeze_just_used_count': 2,
          'streak_freezes_available': 0,
        }),
        '2 Streak Freezes used on missed days. None left. '
        'A new one arrives next Monday.',
      );
    });

    test(
        'STALE SNAPSHOT: the snapshot says 0 but the live count is 1 (a Monday '
        'refill landed between the debit and the notice) -> "1 left"', () {
      expect(
        streakFreezeNoticeFromProgress(<String, dynamic>{
          'streak_freeze_just_used': true,
          'streak_freeze_just_used_count': 1,
          'streak_freeze_remaining_after_use': 0,
          'streak_freezes_available': 1,
        }),
        'Streak Freeze used on a missed day. 1 left.',
      );
      // And the mirror: snapshot says 2, live says 0 -> "None left".
      expect(
        streakFreezeNoticeFromProgress(<String, dynamic>{
          'streak_freeze_just_used': true,
          'streak_freeze_remaining_after_use': 2,
          'streak_freezes_available': 0,
        }),
        'Streak Freeze used on a missed day. None left. '
        'A new one arrives next Monday.',
      );
    });

    test('the snapshot is used only when the live key is absent', () {
      expect(
        streakFreezeNoticeFromProgress(<String, dynamic>{
          'streak_freeze_just_used': true,
          'streak_freeze_remaining_after_use': 2,
        }),
        'Streak Freeze used on a missed day. 2 left.',
      );
    });

    test('neither count present: the notice claims nothing about the rest',
        () {
      expect(
        streakFreezeNoticeFromProgress(<String, dynamic>{
          'streak_freeze_just_used': true,
        }),
        'Streak Freeze used on a missed day.',
      );
    });

    test('non-numeric junk in a count key is ignored, never thrown on', () {
      expect(
        streakFreezeNoticeFromProgress(<String, dynamic>{
          'streak_freeze_just_used': true,
          'streak_freeze_just_used_count': 'two',
          'streak_freezes_available': 'many',
          'streak_freeze_remaining_after_use': 1,
        }),
        'Streak Freeze used on a missed day. 1 left.',
      );
    });

    test('NaN and infinity in a count key read as unknown, never thrown on',
        () {
      for (final bad in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity
      ]) {
        expect(
          streakFreezeNoticeFromProgress(<String, dynamic>{
            'streak_freeze_just_used': true,
            'streak_freeze_just_used_count': bad,
            'streak_freezes_available': bad,
            'streak_freeze_remaining_after_use': 2,
          }),
          'Streak Freeze used on a missed day. 2 left.',
          reason: '$bad must read as "unknown", not throw in toInt()',
        );
      }
    });
  });

  group('freezeNoticeCountAfterConsume: the accumulation rule', () {
    int count(Map<String, dynamic>? p, int newly) =>
        StreakProgressService.freezeNoticeCountAfterConsume(p,
            newlySpent: newly);

    test('no prior progress or a shown notice starts again from this debit',
        () {
      expect(count(null, 1), 1);
      expect(count(<String, dynamic>{}, 1), 1);
      expect(
        count(<String, dynamic>{
          'streak_freeze_just_used': false,
          'streak_freeze_just_used_count': 5,
        }, 1),
        1,
        reason: 'a stale count behind a FALSE flag must not carry over',
      );
    });

    test('an unshown notice carries its count over', () {
      expect(
        count(<String, dynamic>{
          'streak_freeze_just_used': true,
          'streak_freeze_just_used_count': 2,
        }, 1),
        3,
      );
    });

    test('an unshown notice with no count (or a non-positive one) reads as 1',
        () {
      expect(count(<String, dynamic>{'streak_freeze_just_used': true}, 1), 2);
      expect(
        count(<String, dynamic>{
          'streak_freeze_just_used': true,
          'streak_freeze_just_used_count': 0,
        }, 1),
        2,
      );
      expect(
        count(<String, dynamic>{
          'streak_freeze_just_used': true,
          'streak_freeze_just_used_count': -3,
        }, 1),
        2,
      );
    });

    test(
        'a stored count of the wrong TYPE never throws (the writer side of the '
        'reader tolerance above): it reads as 1, so the debit that is being '
        'assembled is never lost', () {
      for (final bad in <Object>['two', true, double.nan, double.infinity]) {
        expect(
          count(<String, dynamic>{
            'streak_freeze_just_used': true,
            'streak_freeze_just_used_count': bad,
          }, 1),
          2,
          reason: '$bad (${bad.runtimeType}) must read as a carried 1',
        );
      }
    });

    test('a debit that names several dates counts them all; none counts as 1',
        () {
      expect(count(null, 2), 2);
      expect(count(null, 3), 3);
      expect(count(null, 0), 1);
      expect(
        count(<String, dynamic>{
          'streak_freeze_just_used': true,
          'streak_freeze_just_used_count': 1,
        }, 2),
        3,
      );
    });
  });

  group('StreakExplainerSheet renders the approved rules', () {
    Future<void> pumpSheet(WidgetTester tester,
        {required bool isPro, required int freezes}) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StreakExplainerSheet(freezesAvailable: freezes, isPro: isPro),
        ),
      ));
      await tester.pump();
    }

    testWidgets('free user: rule 3, rule 4 with 1, the live count, the PRO note',
        (tester) async {
      await pumpSheet(tester, isPro: false, freezes: 1);
      expect(find.text(kStreakFreezeRuleMissed), findsOneWidget);
      expect(find.text(streakFreezeRuleRefill(1)), findsOneWidget);
      expect(find.text('You have 1 freeze available right now.'),
          findsOneWidget);
      expect(
          find.text('PRO users can keep up to 3 freezes in reserve instead of 1.'),
          findsOneWidget);
    });

    testWidgets('PRO user: rule 4 with 3 and no PRO note', (tester) async {
      await pumpSheet(tester, isPro: true, freezes: 2);
      expect(find.text(streakFreezeRuleRefill(3)), findsOneWidget);
      expect(find.text(streakFreezeRuleRefill(1)), findsNothing);
      expect(find.text('You have 2 freezes available right now.'),
          findsOneWidget);
      expect(find.textContaining('PRO users can keep up to'), findsNothing);
    });

    testWidgets('the weekly-allowance and rescue wording is gone from the page',
        (tester) async {
      for (final isPro in [false, true]) {
        await pumpSheet(tester, isPro: isPro, freezes: 1);
        expect(find.textContaining('per week'), findsNothing);
        expect(find.textContaining('keep your streak alive'), findsNothing);
        expect(find.textContaining('refill every Monday'), findsNothing);
      }
    });

    testWidgets('the sibling rules (1, 2, live count) are unchanged',
        (tester) async {
      await pumpSheet(tester, isPro: false, freezes: 0);
      expect(
        find.text('You earn +1 for every scheduled training day you complete. '
            'Rest days never count against you.'),
        findsOneWidget,
      );
      expect(find.text('Rest days and off days don\'t count against you.'),
          findsOneWidget);
      expect(find.text('You have 0 freezes available right now.'),
          findsOneWidget);
    });
  });

  // PRESENCE-ONLY by design: it proves the edited files call the helpers and
  // that the old literals are gone from THOSE TWO FILES. A global `per week`
  // pin cannot pass (other screens carry the words legitimately). The
  // behaviour is the groups above and the behavioral companion file.
  group('wiring (presence-only)', () {
    final home =
        readSourceFileStripped('lib/features/home/screens/home_screen.dart');
    final sheet = readSourceFileStripped(
        'lib/features/home/widgets/streak_explainer_sheet.dart');
    // Head file AND its part files (restoring_screen.dart is near Gate 43's
    // 800-line cap, so a future extraction moves code into a part).
    final restoring = _stripComments(readRestoringScreenSource());

    test('Home takes the notice through takeFreezeNotice and shows exactly it',
        () {
      expect(home.contains('StreakProgressService.instance.takeFreezeNotice()'),
          isTrue);
      // The snackbar's Text takes the notice, nothing else.
      expect(RegExp(r'Text\(\s*notice\s*,').hasMatch(home), isTrue,
          reason: 'the SnackBar content must be Text(notice, ...)');
      // The read-and-clear lives in takeFreezeNotice (behavioural test), so
      // Home must not read the keys itself.
      expect(home.contains('streak_freeze_remaining_after_use'), isFalse,
          reason: 'Home must read the LIVE count through the service, never '
              'the stale snapshot key');
      expect(home.contains('streak_freeze_just_used'), isFalse);
      expect(home.contains('Streak Freeze used!'), isFalse);
      expect(home.contains('remaining this week'), isFalse);
    });

    test('the explainer sheet no longer carries the weekly wording', () {
      expect(sheet.contains('per week'), isFalse);
      expect(sheet.contains('keep your streak alive'), isFalse);
    });

    test('the cold-start clear in restoring_screen goes through the helper', () {
      expect(restoring.contains('clearStreakFreezeNotice()'), isTrue);
      expect(
        RegExp(r"'streak_freeze_just_used'\s*:\s*false").hasMatch(restoring),
        isFalse,
        reason: 'the literal flag write moved into '
            'UserRepository.clearStreakFreezeNotice (one clearer)',
      );
    });

    test('NO file under lib/ writes the flag false except the one clearer', () {
      final offenders = <String>[];
      // Both write forms: the map literal and an indexed assignment.
      final literal = RegExp(r"'streak_freeze_just_used'\s*:\s*false");
      final indexed =
          RegExp(r"""\[\s*['"]streak_freeze_just_used['"]\s*\]\s*=(?!=)""");
      var clearerFile = 0;
      var clearerWrites = 0;
      for (final e in Directory('lib').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final path = e.path.replaceAll('\\', '/');
        final src = _stripComments(e.readAsStringSync());
        if (path.endsWith('lib/shared/repositories/user_repository.dart')) {
          clearerFile++;
          clearerWrites =
              literal.allMatches(src).length + indexed.allMatches(src).length;
          continue;
        }
        if (literal.hasMatch(src) || indexed.hasMatch(src)) {
          offenders.add(path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'only UserRepository.clearStreakFreezeNotice may write the '
              'flag false (it clears the three notice keys together)');
      // The clearer's own file is skipped above, so count its writes: a second
      // write there would be a second clearer that forgets the count.
      expect(clearerFile, 1);
      expect(clearerWrites, 1,
          reason: 'user_repository.dart holds exactly one write of the flag '
              '(the clearer); a second one clears the flag but not the count');
    });

    test(
        'the sheet and EVERY other statement of the freeze caps agree (a '
        'one-sided change reddens this)', () {
      // The caps (free 1, PRO 3) are stated in four places outside the sheet.
      // Presence-only: each file must still say `isPro ? 3 : 1` exactly as
      // many times as it does today, so changing ONE of two copies in a file
      // reddens this too.
      const capSites = <String, (int, String)>{
        'lib/core/services/streak_progress_service.dart':
            (1, 'the weekly refill (refillIfNewWeek)'),
        'lib/features/home/providers/home_provider.dart':
            (2, 'the Home badge and the cap provider'),
        'lib/features/profile/widgets/rank_service_record_sheet.dart':
            (1, 'the Profile service-record tile'),
      };
      capSites.forEach((path, site) {
        expect('isPro ? 3 : 1'.allMatches(readSourceFileStripped(path)).length,
            site.$1,
            reason: '${site.$2} caps PRO at 3 and free at 1 (${site.$1} '
                'statement(s)); the explainer sheet must state the same '
                'numbers');
      });
      expect(sheet.contains('const freeMax = 1;'), isTrue);
      expect(sheet.contains('const proMax = 3;'), isTrue);
    });
  });
}
