import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;

  if (user == null) {
    return ReferralEligibility(
      daysRemaining: 0,
      signupDate: DateTime.now(),
      hasRedeemed: false,
    );
  }

  final signupDate = DateTime.parse(user.createdAt);
  final daysRemaining = ReferralEligibility.computeDaysRemaining(signupDate);

  // Check for existing redemption
  Map<String, dynamic>? redemption;
  try {
    redemption = await supabase
        .from('referral_redemptions')
        .select('id')
        .eq('referee_id', user.id)
        .maybeSingle();
  } catch (_) {
    // Non-fatal — assume not redeemed if query fails
    redemption = null;
  }

  return ReferralEligibility(
    daysRemaining: daysRemaining,
    signupDate: signupDate,
    hasRedeemed: redemption != null,
  );
});
