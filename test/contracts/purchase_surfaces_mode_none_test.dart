// ADR-0022 / plan section 7 test 4: every surface in plan 5.2 that carries
// upgrade wording shows none of it in a binary that sells nothing, and is
// UNCHANGED in the Razorpay binary.
//
// Two kinds of row, said plainly:
//  * BEHAVIOURAL: the pure copy functions, ProPillButton, ProLockedOverlay and
//    the build stamp are pumped or called in both modes.
//  * SOURCE (presence only): the surfaces that are `part of` a large screen
//    (the coach status pill, input bar and overflow menu, the Profile chip,
//    the website row, the report and phase buttons) cannot be pumped alone.
//    For each, the legacy literal must sit in the POSITIVE branch of the
//    guard in its exact code shape (an adjacency regex, so an inverted
//    `!showsUpgradeAffordance()` or a swapped ternary fails). The on-device
//    walk (board card v5-device) is the behavioural proof for them.
//  * The Home expiry banner is behavioural, in
//    purchase_expiry_banner_mode_none_test.dart.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/purchase_mode.dart';
import 'package:icanbefitter/core/copy/purchase_copy.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/profile/widgets/build_stamp.dart';
import 'package:icanbefitter/shared/widgets/pro_locked_overlay.dart';
import 'package:icanbefitter/shared/widgets/pro_pill_button.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_button.dart';

String _strip(String src) {
  final noBlock = src.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return noBlock
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i >= 0 ? l.substring(0, i) : l;
      })
      .join('\n');
}

Future<void> _pump(WidgetTester tester, Widget w) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: w))));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  tearDown(() => PurchaseMode.debugOverrideForTests = null);

  testWidgets('typography warmup — GoogleFonts caches every family first',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Text('a', style: AppTypography.h3),
          Text('b', style: AppTypography.bodySm),
          Text('c', style: AppTypography.monoXs),
          Text('d', style: AppTypography.body),
          Text('e', style: AppTypography.h1),
          Text('f', style: AppTypography.mono),
          const WardButton(label: 'x', onPressed: null),
        ]),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('a'), findsOneWidget);
  });

  group('BEHAVIOURAL: ProPillButton', () {
    testWidgets('razorpay: a free user sees GO PRO', (tester) async {
      PurchaseMode.debugOverrideForTests = PurchaseMode.razorpay;
      await _pump(tester, ProPillButton(isPro: false, onTap: () {}));
      expect(find.text('GO PRO'), findsOneWidget);
    });
    for (final mode in [PurchaseMode.none, PurchaseMode.playBilling]) {
      testWidgets('${mode.wireName}: a free user sees PRO, still tappable',
          (tester) async {
        PurchaseMode.debugOverrideForTests = mode;
        var taps = 0;
        await _pump(tester, ProPillButton(isPro: false, onTap: () => taps++));
        expect(find.text('GO PRO'), findsNothing);
        expect(find.text('PRO'), findsOneWidget);
        await tester.tap(find.text('PRO'));
        expect(taps, 1, reason: 'the pill still opens the neutral sheet');
      });
    }
  });

  group('BEHAVIOURAL: the PRO pill is labelled for a screen reader', () {
    testWidgets('none: a free user gets an explicit "not active" label',
        (tester) async {
      final handle = tester.ensureSemantics();
      PurchaseMode.debugOverrideForTests = PurchaseMode.none;
      await _pump(tester, ProPillButton(isPro: false, onTap: () {}));
      expect(find.bySemanticsLabel(PurchaseCopy.proPillFreeLabel),
          findsOneWidget);
      handle.dispose();
    });
    testWidgets('none: a PRO user does NOT get the free label',
        (tester) async {
      final handle = tester.ensureSemantics();
      PurchaseMode.debugOverrideForTests = PurchaseMode.none;
      await _pump(tester, ProPillButton(isPro: true, onTap: () {}));
      expect(find.bySemanticsLabel(PurchaseCopy.proPillFreeLabel), findsNothing);
      handle.dispose();
    });
    testWidgets('razorpay: no extra label (the widget is unchanged)',
        (tester) async {
      final handle = tester.ensureSemantics();
      PurchaseMode.debugOverrideForTests = PurchaseMode.razorpay;
      await _pump(tester, ProPillButton(isPro: false, onTap: () {}));
      expect(find.bySemanticsLabel(PurchaseCopy.proPillFreeLabel), findsNothing);
      handle.dispose();
    });
  });

  group('BEHAVIOURAL: ProLockedOverlay default button text', () {
    Widget overlay() => ProLockedOverlay(
          featureLabel: 'Progress Photos',
          onUpgradeTap: () {},
          child: const SizedBox(height: 200, width: 300),
        );
    testWidgets('razorpay: Upgrade to PRO', (tester) async {
      PurchaseMode.debugOverrideForTests = PurchaseMode.razorpay;
      await _pump(tester, overlay());
      expect(find.text('Upgrade to PRO'), findsOneWidget);
    });
    testWidgets('none: See what PRO includes', (tester) async {
      PurchaseMode.debugOverrideForTests = PurchaseMode.none;
      await _pump(tester, overlay());
      expect(find.text('Upgrade to PRO'), findsNothing);
      expect(find.text(PurchaseCopy.seeWhatProIncludes), findsOneWidget);
    });
    testWidgets('an explicit ctaText still wins in every mode', (tester) async {
      PurchaseMode.debugOverrideForTests = PurchaseMode.none;
      await _pump(
          tester,
          ProLockedOverlay(
            featureLabel: 'x',
            ctaText: 'Custom',
            onUpgradeTap: () {},
            child: const SizedBox(height: 200, width: 300),
          ));
      expect(find.text('Custom'), findsOneWidget);
    });
  });

  group('BEHAVIOURAL: build stamp', () {
    for (final mode in PurchaseMode.values) {
      testWidgets('shows the mode ${mode.wireName}', (tester) async {
        PurchaseMode.debugOverrideForTests = mode;
        await _pump(tester, const BuildStamp());
        expect(find.byKey(const ValueKey('build-stamp')), findsOneWidget);
        expect(BuildStamp.label(), contains('purchases: ${mode.wireName}'));
        expect(BuildStamp.label(), startsWith('v'));
      });
    }
  });

  group('BEHAVIOURAL: copy functions', () {
    test('purchase wording is the ORIGINAL text, byte for byte', () {
      expect(PurchaseCopy.predictionLocked(purchaseUi: true),
          'Prediction refresh is a PRO feature. Upgrade in Profile → Subscription');
      expect(PurchaseCopy.foodAnalysisLimit(purchaseUi: true),
          'Daily food analysis limit reached. Try again tomorrow or upgrade to PRO.');
      expect(PurchaseCopy.photoAnalysisProRequired(purchaseUi: true),
          'Photo analysis is a PRO feature. Upgrade to unlock it.');
      expect(PurchaseCopy.featureProRequired(purchaseUi: true),
          'This feature requires PRO. Upgrade to unlock it.');
      expect(PurchaseCopy.deployToPhase(3, purchaseUi: true),
          'Deploy to Phase 3 — go PRO →');
    });

    test('no-purchase wording has no upgrade verb, price or arrow to buy', () {
      final all = <String>[
        PurchaseCopy.predictionLocked(purchaseUi: false),
        PurchaseCopy.foodAnalysisLimit(purchaseUi: false),
        PurchaseCopy.photoAnalysisProRequired(purchaseUi: false),
        PurchaseCopy.featureProRequired(purchaseUi: false),
        PurchaseCopy.deployToPhase(3, purchaseUi: false),
        PurchaseCopy.proInfo,
        PurchaseCopy.seeWhatProIncludes,
        PurchaseCopy.seeWhatProIncludesCta,
        PurchaseCopy.dailyLimitReached,
        PurchaseCopy.weeklyReportsLocked,
        PurchaseCopy.card,
        PurchaseCopy.defaultSubtitle,
        // Every other member of the copy file (a new member must be listed).
        PurchaseCopy.manageSubscription,
        PurchaseCopy.eyebrow,
        PurchaseCopy.benefitsLabel,
        PurchaseCopy.checkStatusButton,
        PurchaseCopy.closeButton,
        PurchaseCopy.checkStatusFailed,
        PurchaseCopy.proPillFreeLabel,
      ];
      for (final t in all) {
        final l = t.toLowerCase();
        expect(l.contains('upgrade'), isFalse, reason: t);
        expect(l.contains('go pro'), isFalse, reason: t);
        expect(l.contains('renew'), isFalse, reason: t);
        expect(l.contains('₹'), isFalse, reason: t);
        expect(l.contains('subscribe'), isFalse, reason: t);
      }
    });
  });

  group('SOURCE (presence only): the legacy literal sits in the POSITIVE '
      'branch of the guard, in its exact shape', () {
    // file -> [description, regex over the comment-stripped source]. Each
    // regex ties the guard to the literal by ADJACENCY and polarity, so
    // `!showsUpgradeAffordance()`, a swapped ternary or a guard that sits
    // above some other widget cannot satisfy it (B-pass 2026-11-20, F2).
    final table = <String, List<RegExp>>{
      'lib/shared/widgets/pro_pill_button.dart': [
        RegExp(r"\(isPro \|\| !showsUpgradeAffordance\(\)\) \? PurchaseCopy\.proInfo : 'GO PRO'"),
      ],
      'lib/features/profile/screens/profile/subscription_section.dart': [
        RegExp(r"if \(showsUpgradeAffordance\(\)\)\s*GestureDetector\([\s\S]{0,800}?child: Text\('UPGRADE',"),
      ],
      'lib/features/ai_coach/screens/ai_coach/input_bar.dart': [
        RegExp(r"if \(showsUpgradeAffordance\(\)\) \.\.\.\[[\s\S]{0,700}?'GO PRO',"),
        RegExp(r"\(showsUpgradeAffordance\(\)\s*\? 'Daily limit reached — Go PRO'\s*: PurchaseCopy\.dailyLimitReached\)"),
      ],
      'lib/features/ai_coach/screens/ai_coach/compact_header.dart': [
        RegExp(r"if \(!isPro && showsUpgradeAffordance\(\)\)\s*PopupMenuItem\(\s*value: 'upgrade',"),
      ],
      'lib/features/ai_coach/screens/ai_coach/status_pill.dart': [
        RegExp(r"showsUpgradeAffordance\(\) \? 'UPGRADE' : PurchaseCopy\.proInfo"),
        RegExp(r"if \(showsUpgradeAffordance\(\)\) \.\.\.const \[\s*Icon\(Icons\.arrow_upward"),
      ],
      'lib/features/profile/widgets/weekly_report_card.dart': [
        RegExp(r"showsUpgradeAffordance\(\)\s*\? 'Upgrade for weekly reports'\s*: PurchaseCopy\.weeklyReportsLocked"),
        RegExp(r"showsUpgradeAffordance\(\)\s*\? 'Upgrade for Reports'\s*: PurchaseCopy\.seeWhatProIncludes"),
      ],
      'lib/features/train/screens/phase_roadmap_screen.dart': [
        RegExp(r"showsUpgradeAffordance\(\)\s*\? 'UPGRADE TO PRO  →'\s*: PurchaseCopy\.seeWhatProIncludesCta"),
      ],
      'lib/features/train/screens/preview_workout_screen.dart': [
        RegExp(r"showsUpgradeAffordance\(\)\s*\? 'UPGRADE TO PRO  →'\s*: PurchaseCopy\.seeWhatProIncludesCta"),
      ],
      'lib/features/profile/screens/profile/profile_content.dart': [
        RegExp(r"if \(showsUpgradeAffordance\(\)\)\s*ProfileRow\([\s\S]{0,160}?title: 'icanbefitter\.com'"),
      ],
      'lib/shared/widgets/pro_locked_overlay.dart': [
        RegExp(r"ctaText \?\?\s*\(showsUpgradeAffordance\(\)\s*\? 'Upgrade to PRO'\s*: PurchaseCopy\.seeWhatProIncludes\)"),
      ],
    };

    table.forEach((path, patterns) {
      for (var i = 0; i < patterns.length; i++) {
        test('$path #$i', () {
          final src = _strip(File(path).readAsStringSync());
          expect(patterns[i].hasMatch(src), isTrue,
              reason: 'the guard/literal shape changed or was inverted in '
                  '$path: ${patterns[i].pattern}');
        });
      }
    });

    test('no source file passes a hard-coded `purchaseUi: true`', () {
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final src = _strip(f.readAsStringSync());
        expect(RegExp(r'purchaseUi:\s*true').hasMatch(src), isFalse,
            reason: f.path);
      }
    });

    test('the legacy sentences left the files that now call the copy '
        'functions, and each call passes showsUpgradeAffordance()', () {
      // file -> [old text that must be gone, expected number of
      // `purchaseUi: showsUpgradeAffordance()` arguments].
      const gone = <String, (String, int)>{
        'lib/features/profile/screens/profile/prediction_card.dart':
            ('Upgrade in Profile', 1),
        'lib/features/nutrition/providers/nutrition_provider.dart':
            ('or upgrade to PRO.', 1),
        'lib/features/ai_coach/providers/ai_coach_provider.dart':
            ('Upgrade to unlock it.', 2),
        'lib/features/train/widgets/plan_expired_card.dart':
            ('— go PRO →', 1),
      };
      gone.forEach((path, spec) {
        final src = _strip(File(path).readAsStringSync());
        expect(src.contains(spec.$1), isFalse, reason: '${spec.$1} in $path');
        expect(src.contains('PurchaseCopy.'), isTrue, reason: path);
        expect(
            RegExp(r'purchaseUi:\s*showsUpgradeAffordance\(\)')
                .allMatches(src)
                .length,
            spec.$2,
            reason: '$path: every copy call must take the mode from '
                'showsUpgradeAffordance()');
      });
    });

    test('the Profile footer line is mounted', () {
      final src = _strip(File(
              'lib/features/profile/screens/profile/profile_content.dart')
          .readAsStringSync());
      expect(src.contains('const BuildStamp()'), isTrue);
    });
  });
}
