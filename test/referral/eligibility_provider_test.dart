import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/profile/providers/referral_eligibility_provider.dart';

void main() {
  group('ReferralEligibility', () {
    test('isEligible: signup within 7 days + no redemption', () {
      final state = ReferralEligibility(
        daysRemaining: 4,
        signupDate: DateTime.now().subtract(const Duration(days: 3)),
        hasRedeemed: false,
      );
      expect(state.isEligible, true);
    });

    test('not eligible: outside 7-day window', () {
      final state = ReferralEligibility(
        daysRemaining: 0,
        signupDate: DateTime.now().subtract(const Duration(days: 8)),
        hasRedeemed: false,
      );
      expect(state.isEligible, false);
    });

    test('not eligible: already redeemed', () {
      final state = ReferralEligibility(
        daysRemaining: 4,
        signupDate: DateTime.now().subtract(const Duration(days: 3)),
        hasRedeemed: true,
      );
      expect(state.isEligible, false);
    });

    test('daysRemaining calculation', () {
      final signedUp4DaysAgo = DateTime.now().subtract(const Duration(days: 4));
      final remaining = ReferralEligibility.computeDaysRemaining(signedUp4DaysAgo);
      expect(remaining, 3);
    });

    test('daysRemaining clamps to 0 when expired', () {
      final signedUp10DaysAgo =
          DateTime.now().subtract(const Duration(days: 10));
      final remaining =
          ReferralEligibility.computeDaysRemaining(signedUp10DaysAgo);
      expect(remaining, 0);
    });
  });
}
