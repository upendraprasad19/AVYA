// test/contracts/paywall_generic_upgrade_title_behavioral_test.dart
//
// OI-97 (payment-surface half) — the paywall letterhead rendered
// "PRO is a PRO feature".
//
// WHY THIS IS A USER-VISIBLE BUG, NOT A COPY NIT
// ----------------------------------------------
// `paywall_sheet.dart` renders its `feature` verbatim into the hero letterhead
// as "<feature> is a PRO feature". Three call sites are NOT feature gates —
// they are general "go PRO" affordances, and each passed a bare label:
//
//   lib/features/home/screens/home_screen.dart:568          'PRO'
//     → the subscription-EXPIRY renew banner
//   lib/features/profile/screens/profile/subscription_section.dart:195  'PRO'
//     → the Profile FREE PLAN → UPGRADE chip
//   lib/features/profile/screens/profile/profile_content.dart:221  'PRO Upgrade'
//
// So the three highest-intent surfaces in the app — the two places a user goes
// specifically to hand over money, plus the renew prompt for a lapsed
// subscriber — were headed:
//
//     "PRO is a PRO feature"
//     "PRO Upgrade is a PRO feature"
//
// The board rated this P3 on "no user sees a wrong claim, only a weak one".
// That rating was made without reading the rendered letterhead.
//
// WHY THIS TEST IS BEHAVIORAL, NOT A SOURCE GREP
// ----------------------------------------------
// Its sibling `paywall_feature_label_test.dart` is a source-grep (presence)
// test and says so. Per §4.4 r21 a source-grep proves PRESENCE only: it would
// still pass if the template were reverted, because the call sites would look
// fine while the rendering was wrong again.
//
// This test calls the real production function that produces the string, with
// the exact inputs the real call sites pass. Reverting `paywallLetterheadTitle`
// to the old unconditional `'$feature is a PRO feature'` reddens the
// "MUTATION GUARD" group below.
//
// Run: flutter test test/contracts/paywall_generic_upgrade_title_behavioral_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';

void main() {
  group('OI-97 — a general upgrade prompt does not name itself a feature', () {
    test('the sentinel the three payment surfaces pass renders a real headline',
        () {
      final title = paywallLetterheadTitle(PaywallSheet.genericUpgrade);

      expect(title, 'Unlock every PRO feature');
      expect(
        title,
        isNot(contains('PRO is a PRO')),
        reason: 'the exact tautology this contract exists to prevent',
      );
    });

    test('legacy bare labels are still caught if a call site regresses', () {
      // These are the literal strings the three sites passed before the fix.
      // A future call site copy-pasting one must not resurrect the tautology.
      for (final legacy in <String>[
        'PRO',
        'PRO Upgrade',
        'pro',
        '  PRO  ',
        PaywallSheet.genericUpgradeProfile,
      ]) {
        expect(
          paywallLetterheadTitle(legacy),
          'Unlock every PRO feature',
          reason: 'generic label "$legacy" must not name itself a feature',
        );
      }
    });

    test('an empty or whitespace label degrades to the generic headline', () {
      for (final blank in <String>['', '   ']) {
        expect(paywallLetterheadTitle(blank), 'Unlock every PRO feature');
      }
      // Guards the specific ugly failure: "' ' is a PRO feature".
      expect(paywallLetterheadTitle(''), isNot(contains(' is a PRO feature')));
    });
  });

  group('a genuinely gated feature still names itself', () {
    test('real feature labels keep the "<feature> is a PRO feature" form', () {
      // Drawn from `_featureSubtitle`'s switch — these are real gate labels.
      const gated = <String>[
        'Progress Photos',
        'Phases 2-12',
        'Unlimited AI Coach',
        'Weekly AI Report',
        'Photo Analysis',
        'Protein Alerts',
        'Plateau Check',
      ];

      for (final f in gated) {
        expect(
          paywallLetterheadTitle(f),
          '$f is a PRO feature',
          reason: 'the fix must not flatten specific gates into generic copy',
        );
        expect(isGenericUpgradeLabel(f), isFalse);
      }
    });

    test('a label merely CONTAINING "pro" is not treated as generic', () {
      // "Progress Photos" and "Protein Alerts" both start with "Pro". A
      // substring match instead of an equality match would silently strip the
      // feature name off two real gates.
      expect(isGenericUpgradeLabel('Progress Photos'), isFalse);
      expect(isGenericUpgradeLabel('Protein Alerts'), isFalse);
      expect(
        paywallLetterheadTitle('Progress Photos'),
        'Progress Photos is a PRO feature',
      );
    });
  });

  group('THE RENDER SITE — the pure function must actually be used', () {
    // Hermes L37/P2. Every other test here exercises `paywallLetterheadTitle`
    // in isolation. That is necessary and NOT sufficient: reverting the single
    // line `title: _featureTitle` back to `title: '${widget.feature} is a PRO
    // feature'` restores the tautology on all three payment surfaces while the
    // pure function stays correct — and correct-but-unused. Every test above
    // would still pass. This is the "follow the return value to its CALL SITE"
    // failure the repo has hit repeatedly.
    //
    // A widget test would be stronger, but pumping PaywallSheet needs Riverpod
    // + Hive + a telemetry-firing initState. This pins the wiring instead.
    //
    // ⚠ KNOWN COST, stated so it is not a surprise: this greps for the literal
    // identifiers `_featureTitle` and `paywallLetterheadTitle`, so a purely
    // COSMETIC rename of either — correctness fully intact — will redden this
    // group. That is a false positive, not a caught regression. If you rename,
    // update these two strings in the same commit. The trade is deliberate: a
    // brittle-to-rename guard beats no guard on the one line whose reversion
    // silently restores the tautology on every payment surface.
    late String src;
    setUpAll(() => src =
        File('lib/shared/widgets/paywall_sheet.dart').readAsStringSync());

    test('WardLetterhead takes the computed title, not an interpolation', () {
      expect(src, contains('title: _featureTitle'),
          reason: 'the letterhead must render the computed title; if this is '
              'an inline interpolation again, every payment surface is '
              'showing "PRO is a PRO feature" and no other test can see it');

      // The old template must not reappear anywhere as a live expression.
      final live = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(
        live.contains(r"'${widget.feature} is a PRO feature'"),
        isFalse,
        reason: 'the unconditional template is back in live code',
      );
    });

    test('_featureTitle delegates to the tested pure function', () {
      expect(src, contains('paywallLetterheadTitle(widget.feature)'),
          reason: 'if _featureTitle stops delegating, the pure function this '
              'file tests is no longer what the user sees');
    });
  });

  group('MUTATION GUARD — these fail if the old template returns', () {
    test('no generic input can produce a self-referential headline', () {
      for (final generic in <String>[
        PaywallSheet.genericUpgrade,
        'PRO',
        'PRO Upgrade',
        'pro upgrade',
        '',
      ]) {
        final title = paywallLetterheadTitle(generic);
        expect(
          title.toLowerCase().contains('is a pro feature'),
          isFalse,
          reason:
              'input "$generic" produced "$title" — the unconditional template '
              'has been restored and the tautology is back on the money screens',
        );
      }
    });
  });
}
