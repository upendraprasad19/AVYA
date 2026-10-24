/// Subscription plan names the client compares against server rows.
///
/// `kReferralTrialPlan` is the `subscriptions.plan` value of a referral grant.
/// It must equal `REFERRAL_TRIAL_PLAN` in
/// `supabase/functions/create-razorpay-order/index.ts` and the literal
/// `private.grant_referral_days` inserts (pinned by
/// `test/contracts/referral_trial_plan_parity_test.dart`): a drift silently
/// hides the paywall stacking line and the trial 409 copy (OI-341 Piece B2b).
library;

const String kReferralTrialPlan = 'referral_trial';
