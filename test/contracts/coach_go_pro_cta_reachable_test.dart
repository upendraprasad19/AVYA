// FC8 (coach-memory-snapshot) — the Go-PRO paywall CTA must be REACHABLE at the
// 10/10 daily limit.
//
// THE BUG (founder-reported 2026-07-04): from 10/10 there was NO reachable
// paywall CTA at the precise moment of upgrade intent:
//   1. the only tappable "GO PRO" link was gated `isWarning && !isLimitReached`,
//      which HID it at exactly the limit (isLimitReached => isWarning); and
//   2. the limit-state composer is a DISABLED TextField (a dead placeholder
//      showing "Daily limit reached — Go PRO") with no gesture.
//
// THE FIX (input_bar.dart): (a) the counter-row predicate is `if (isWarning)`
// (keeps the tappable GO PRO link visible AT the limit); (b) at the limit the
// composer is wrapped in a GestureDetector -> showPaywallSheet, so the gold hint
// the user actually taps opens the paywall.
//
// input_bar.dart is a `part of screen.dart` PRIVATE extension on the screen
// state — it cannot be pumped in isolation, and a full-screen pump needs the
// whole provider graph. So this is a SOURCE-anchored regression (comment-
// stripped per feedback_source_grep_strip_comments_first) that FAILS if the
// predicate is re-narrowed OR the limit-state tap target is removed; the
// behavioral confirmation is the on-device tap at end-of-batch APK verify.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _stripComments(String src) {
  final noBlock = src.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return noBlock
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i >= 0 ? l.substring(0, i) : l;
      })
      .join('\n');
}

void main() {
  final src = _stripComments(
      File('lib/features/ai_coach/screens/ai_coach/input_bar.dart')
          .readAsStringSync());

  test('the counter-row GO PRO link is shown for the whole warning band '
      '(including AT the limit), not hidden by !isLimitReached', () {
    expect(src.contains('if (isWarning) ...['), isTrue,
        reason: 'the GO PRO link predicate must be `isWarning` so it stays '
            'visible at the 10/10 limit');
    expect(src.contains('isWarning && !isLimitReached'), isFalse,
        reason: 'the old predicate HID the only paywall CTA at exactly the limit');
  });

  test('the limit-reached composer is a tappable paywall affordance', () {
    // At the limit the disabled composer is wrapped in a GestureDetector that
    // opens the paywall.
    expect(
        RegExp(r'isLimitReached\s*\?\s*GestureDetector').hasMatch(src), isTrue,
        reason: 'the limit-state composer must be wrapped in a GestureDetector');
    expect(src.contains('HitTestBehavior.opaque'), isTrue,
        reason: 'the composer tap target must be opaque so the disabled '
            'TextField cannot swallow the tap');
    // showPaywallSheet is now wired in BOTH the counter GO PRO link AND the
    // limit-state composer wrap (was only the counter link pre-fix).
    expect("showPaywallSheet(context,".allMatches(src).length,
        greaterThanOrEqualTo(2),
        reason: 'both the GO PRO link and the limit-state composer open the paywall');
  });
}
