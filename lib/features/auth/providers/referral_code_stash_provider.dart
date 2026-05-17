import 'package:flutter_riverpod/flutter_riverpod.dart';

// AUTH_INVALIDATION_EXEMPT: intentionally shared pre-auth surface per
// CLAUDE.md §15. The referral code is stashed BEFORE the user signs up
// (so there's no auth identity yet) and must survive across the
// signed-out → signed-in transition. Watching authUserIdTokenProvider
// would clear the stash exactly when we need to preserve it.

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
