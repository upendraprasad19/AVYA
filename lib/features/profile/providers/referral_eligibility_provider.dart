import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/profile/repositories/referral_repository.dart';

class ReferralEligibility {
  final int daysRemaining;
  final DateTime signupDate;
  final bool hasRedeemed;

  const ReferralEligibility({
    required this.daysRemaining,
    required this.signupDate,
    required this.hasRedeemed,
  });

  bool get isEligible => daysRemaining > 0 && !hasRedeemed;

  static int computeDaysRemaining(DateTime signupDate) {
    final daysSinceSignup = DateTime.now().difference(signupDate).inDays;
    final remaining = 7 - daysSinceSignup;
    return remaining.clamp(0, 7);
  }
}

final referralEligibilityProvider =
    FutureProvider<ReferralEligibility>((ref) async {
  ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
  final user = SupabaseService.instance.currentUser;

  if (user == null) {
    return ReferralEligibility(
      daysRemaining: 0,
      signupDate: DateTime.now(),
      hasRedeemed: false,
    );
  }

  final signupDate = DateTime.parse(user.createdAt);
  final daysRemaining = ReferralEligibility.computeDaysRemaining(signupDate);

  // Audit A5 (2026-05-21): direct `.from('referral_redemptions')` call
  // moved into `ReferralRepository.hasRedeemed`. Repository swallows +
  // telemeters errors and returns `false` on any failure (matches the
  // pre-A5 inline behaviour: assume not redeemed).
  final hasRedeemed =
      await ReferralRepository.instance.hasRedeemed(user.id);

  return ReferralEligibility(
    daysRemaining: daysRemaining,
    signupDate: signupDate,
    hasRedeemed: hasRedeemed,
  );
});
