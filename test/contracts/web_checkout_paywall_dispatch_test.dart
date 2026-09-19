// Source-grep pin for the paywall web-branch dispatch (plan-review round-1
// P1-2). Behavioral form is not feasible for the sheet render itself (the
// GoogleFonts/path_provider widget-test trap, common-pitfalls 2026-08-29);
// the kill-switch PREDICATE behavior is pinned behaviorally by
// razorpay_web_kill_switch_test.dart, and Mutation 5 makes the shared
// predicate non-vacuous.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const srcPath = 'lib/shared/widgets/paywall_sheet.dart';
  late String src;

  setUpAll(() {
    src = File(srcPath).readAsStringSync();
  });

  test('kill-switch branch reads the SHARED predicate (not a forked copy)', () {
    expect(src, contains('razorpayServiceProvider).webCheckoutDisabled'));
  });

  test('old mobile-only snackbar preserved verbatim (rollback path)', () {
    expect(src,
        contains('Payments are only available in the mobile app. Download ICANBEFITTER to upgrade.'));
  });

  test('rollback pop+snackbar+return live INSIDE the disabled branch (round-2 P3: a bare "pop after switch" assertion was near-vacuous — the disabled branch contains its own pop)', () {
    final start = src.indexOf('webCheckoutDisabled');
    final end = src.indexOf('// Web checkout active', start);
    expect(end, greaterThan(start),
        reason: 'the enabled-path comment must come AFTER the kill-switch block');
    final branch = src.substring(start, end);
    expect(branch, contains('Navigator.of(context).pop();'));
    expect(branch, contains('Payments are only available in the mobile app.'));
    expect(branch, contains('return;'));
  });
}
