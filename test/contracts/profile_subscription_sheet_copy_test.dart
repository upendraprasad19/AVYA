// U4a / ADR-0022: the Profile "MANAGE SUBSCRIPTION" sheet used to say the PRO
// plan "is handled by Razorpay and auto-renews by default", which is false for
// every store build and unproven for the web one. The sentence now lives in
// PurchaseCopy.manageSubscription and names no provider.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/purchase_copy.dart';

String _strip(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i >= 0 ? l.substring(0, i) : l;
    })
    .join('\n');

void main() {
  test('BEHAVIOURAL: the sheet sentence names no provider and promises no renewal',
      () {
    final t = PurchaseCopy.manageSubscription.toLowerCase();
    expect(t.contains('razorpay'), isFalse);
    expect(t.contains('auto-renew'), isFalse);
    expect(t.contains('google'), isFalse);
    expect(t, contains('refund'));
  });

  test('SOURCE (presence only): the screen renders that sentence, not its own',
      () {
    final src = _strip(File('lib/features/profile/screens/profile/screen.dart')
        .readAsStringSync());
    expect(src.contains('PurchaseCopy.manageSubscription'), isTrue);
    expect(src.contains('handled by Razorpay'), isFalse);
    expect(src.contains('auto-renews by default'), isFalse);
  });
}
