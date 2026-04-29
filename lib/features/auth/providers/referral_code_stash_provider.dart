import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stashes a referral code entered on the Welcome screen so it can be
/// applied via redeem-referral Edge Function AFTER signup + onboarding
/// completes (when the user has a public.users row).
///
/// Cleared after a successful or failed redemption attempt so the code
/// is never replayed on subsequent onboarding runs.
class ReferralCodeStashNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setCode(String code) => state = code;
  void clear() => state = '';
}

final referralCodeStashProvider =
    NotifierProvider<ReferralCodeStashNotifier, String>(
        ReferralCodeStashNotifier.new);
