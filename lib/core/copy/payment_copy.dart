/// Payment copy for a referral-trial user who buys PRO (OI-341 Piece B2b,
/// `docs/plans/oi341-piece-b2b-client.md` 2.1).
///
/// Const-only. No em dashes.
library;

class PaymentCopy {
  PaymentCopy._();

  /// Founder's wording, verbatim (2026-10-20). Shown on the paywall to a
  /// trial user and appended to the Razorpay checkout description when the
  /// order stacks after a trial.
  static const String trialStackingNotice =
      'Your paid plan starts when your free days end.';

  /// Shown when the purchase door is SHUT and a trial user tries to buy (the
  /// server answers 409 `already_pro` from the trial row). Proposed
  /// 2026-10-22; awaits the founder's sign-off (closure ledger).
  static const String trialUpgradeUnavailable =
      'Your free PRO days are still running. You can subscribe once they end.';
}
