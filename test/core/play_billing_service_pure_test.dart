// OI-519 (+51): the pure halves of the Play store seam
// (lib/core/services/play_billing_service.dart).
//
// Run: flutter test test/core/play_billing_service_pure_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/play_billing_service.dart';

void main() {
  group('playStatusForErrorCode', () {
    test('cancel, pending and already-owned map to their own states', () {
      expect(playStatusForErrorCode('purchaseCancelledError'),
          PlayPurchaseStatus.cancelled);
      expect(playStatusForErrorCode('paymentPendingError'),
          PlayPurchaseStatus.pending);
      for (final c in [
        'productAlreadyPurchasedError',
        'receiptAlreadyInUseError',
        'receiptInUseByOtherSubscriberError',
      ]) {
        expect(playStatusForErrorCode(c), PlayPurchaseStatus.ownedByOtherAccount,
            reason: c);
      }
    });

    test('everything else is failed (never purchased)', () {
      for (final c in [
        'networkError',
        'storeProblemError',
        'purchaseNotAllowedError',
        'unknownError',
        '',
      ]) {
        expect(playStatusForErrorCode(c), PlayPurchaseStatus.failed, reason: c);
      }
    });
  });

  group('yearlySavingPercent', () {
    test('Play prices 449 / 3,499 save 35 percent (floor, never rounded up)',
        () {
      // 449 * 12 = 5,388; (5,388 - 3,499) / 5,388 = 35.06 %.
      expect(yearlySavingPercent(monthly: 449, yearly: 3499), 35);
    });

    test('no saving line when yearly is not cheaper or a price is unusable',
        () {
      expect(yearlySavingPercent(monthly: 449, yearly: 5388), isNull);
      expect(yearlySavingPercent(monthly: 449, yearly: 6000), isNull);
      expect(yearlySavingPercent(monthly: 0, yearly: 3499), isNull);
      expect(yearlySavingPercent(monthly: 449, yearly: 0), isNull);
      expect(yearlySavingPercent(monthly: double.nan, yearly: 3499), isNull);
      // Under one percent reads as noise: no line.
      expect(yearlySavingPercent(monthly: 100, yearly: 1195), isNull);
    });
  });

  test('planId is the server plan name', () {
    const m = PlayPlanOffer(
        period: PlayPlanPeriod.monthly, priceString: 'x', price: 1);
    const y =
        PlayPlanOffer(period: PlayPlanPeriod.yearly, priceString: 'x', price: 1);
    expect(m.planId, 'monthly');
    expect(y.planId, 'yearly');
  });
}
