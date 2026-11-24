// Plan section 6 / 7 test 6 (presence only): the `purchases_flutter` package is
// in pubspec so the Android build carries the Play Billing library. Since
// OI-519 (+51, docs/plans/2026-11-23-revenuecat-play-billing-51.md section 5)
// exactly ONE file imports and configures it: the Play store seam
// `lib/core/services/play_billing_service.dart`. Every other file talks to the
// `PlayStore` interface, so a `razorpay` or `none` build never reaches the SDK.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _seam = 'lib/core/services/play_billing_service.dart';

List<String> _filesContaining(String needle) => [
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        if (f.readAsStringSync().contains(needle))
          f.path.replaceAll(Platform.pathSeparator, '/'),
    ];

void main() {
  test('only the Play store seam imports purchases_flutter', () {
    expect(_filesContaining('package:purchases_flutter'), [_seam],
        reason: 'a second importer bypasses the PlayStore seam (OI-519)');
  });

  test('only the Play store seam calls Purchases.configure', () {
    expect(_filesContaining('Purchases.configure'), [_seam]);
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
