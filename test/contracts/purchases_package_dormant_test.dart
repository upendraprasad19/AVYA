// Plan section 6 / 7 test 6 (presence only): the `purchases_flutter` package is
// in pubspec so the Android build carries the Play Billing library (the Play
// Console unlocks Subscriptions on it), but NOTHING under lib/ imports or
// configures it until the RevenueCat plan (section 8) is built and accepted.
// That is what "dormant" means: build +50 behaves as +49 as far as billing goes.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no file under lib/ imports purchases_flutter', () {
    final offenders = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final text = f.readAsStringSync();
      if (text.contains('package:purchases_flutter')) offenders.add(f.path);
    }
    expect(offenders, isEmpty,
        reason: 'Importing the package starts section 8, which needs its own '
            'plan, review and hermes pass (docs/plans/2026-11-20-android-play-billing.md).');
  });

  test('nothing under lib/ calls Purchases.configure', () {
    final offenders = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      if (f.readAsStringSync().contains('Purchases.configure')) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty);
  });

  test('pubspec pins purchases_flutter to an exact version', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.trim().startsWith('purchases_flutter:'),
            orElse: () => '');
    expect(line, isNotEmpty, reason: 'the dependency must be present');
    expect(line.trim(), matches(RegExp(r'^purchases_flutter:\s*\d+\.\d+\.\d+$')),
        reason: 'exact version, no caret or range');
  });

  test('the web cost of the dormant package is recorded (B-pass 2026-11-20)',
      () {
    // The package is NOT inert on web: its web plugin registers at app start
    // and appends a ~1 MB script (purchases_js_hybrid_mappings.js). PRESENCE
    // only: the decision is the founder's, and it must stay written down in
    // the ADR and in the closure ledger until it is made.
    final adr = File(
            'docs/adr/0022-android-play-billing-via-revenuecat-web-stays-razorpay.md')
        .readAsStringSync();
    expect(adr.contains('purchases_js_hybrid_mappings'), isTrue);
    final ledger =
        File('docs/audit/2026-11-20-android-play-billing.closure.yaml')
            .readAsStringSync();
    expect(ledger.contains('id: WEB-SCRIPT'), isTrue);
  });
}
