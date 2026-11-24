/// Copy for the purchase surfaces of a build with NO purchase UI
/// (`PurchaseMode.none`, ADR-0022, plan sections 4 and 5.2).
///
/// Const-only. New copy has no em dashes; the purchase-mode strings returned by
/// the functions below are the ORIGINAL texts, kept byte for byte. No price, no website, no store name: Play's
/// steering rules. DRAFT wording: the Wardroom voice and psychology pass
/// (board card p06) runs before the no-purchase build ships. The card sentence
/// and the CLOSE word are the founder's (Q4b, 2026-11-20).
library;

class PurchaseCopy {
  PurchaseCopy._();

  /// Paywall letterhead eyebrow when nothing can be bought (the purchase build
  /// says `GO PRO`).
  static const String eyebrow = 'PRO';

  /// Label above the benefit list (the purchase build says `WHAT YOU UNLOCK`).
  static const String benefitsLabel = 'WHAT PRO INCLUDES';

  /// Subtitle for the generic paywall (the purchase build says "Upgrade to PRO
  /// and unlock your full potential."). Per-feature subtitles are descriptive
  /// and stay.
  static const String defaultSubtitle = 'Here is what PRO includes.';

  /// The neutral card (founder wording, Q4b).
  static const String card =
      "PRO isn't available to buy in this app yet. Already PRO? Sign in with the same account.";

  /// Re-reads the server-verified subscription (the old RESTORE).
  static const String checkStatusButton = 'CHECK MY PRO STATUS';

  /// Body of the Profile "MANAGE SUBSCRIPTION" sheet. It names no payment
  /// provider and promises no renewal: the same words are true for a web
  /// purchase, a free-days code and a store purchase (ADR-0022, U4a).
  static const String manageSubscription =
      'Your PRO plan is managed by our team. To cancel, change plans, or '
      'request a refund, reach out to us and we\'ll sort it within 24 hours.';

  /// Dismiss (the old MAYBE LATER implied a later purchase).
  static const String closeButton = 'CLOSE';

  /// Screen-reader label of the free user's PRO pill in a no-purchase build
  /// (the pill reads the same word as a PRO user's).
  static const String proPillFreeLabel = 'PRO plan details, not active';

  /// Shown INSIDE the neutral card when CHECK MY PRO STATUS cannot reach the
  /// server. A snackbar would render behind the modal sheet, and this button
  /// is the card's only action, so the failure has to be visible in place.
  static const String checkStatusFailed =
      "Couldn't check your PRO status. Check your connection and try again.";

  /// A free user's entry pill (Profile, AI Coach) when nothing can be bought:
  /// information, not a call to action. The purchase build says `GO PRO` /
  /// `UPGRADE`.
  static const String proInfo = 'PRO';

  /// The locked-content overlay button (the purchase build says
  /// `Upgrade to PRO`).
  static const String seeWhatProIncludes = 'See what PRO includes';

  /// The phase roadmap and workout preview buttons (the purchase build says
  /// `UPGRADE TO PRO  →`). They open the neutral sheet.
  static const String seeWhatProIncludesCta = 'SEE WHAT PRO INCLUDES  →';

  /// The coach composer hint at the daily limit (the purchase build says
  /// `Daily limit reached — Go PRO`).
  static const String dailyLimitReached = 'Daily limit reached';

  /// Weekly report card, locked (the purchase build says
  /// `Upgrade for weekly reports` / `Upgrade for Reports`).
  static const String weeklyReportsLocked = 'Weekly reports are a PRO feature';

  static String predictionLocked({required bool purchaseUi}) => purchaseUi
      ? 'Prediction refresh is a PRO feature. Upgrade in Profile \u2192 Subscription'
      : 'Prediction refresh is a PRO feature.';

  static String foodAnalysisLimit({required bool purchaseUi}) => purchaseUi
      ? 'Daily food analysis limit reached. Try again tomorrow or upgrade to PRO.'
      : 'Daily food analysis limit reached. Try again tomorrow.';

  static String photoAnalysisProRequired({required bool purchaseUi}) =>
      purchaseUi
          ? 'Photo analysis is a PRO feature. Upgrade to unlock it.'
          : 'Photo analysis is a PRO feature.';

  static String featureProRequired({required bool purchaseUi}) => purchaseUi
      ? 'This feature requires PRO. Upgrade to unlock it.'
      : 'This feature requires PRO.';

  /// The plan-expired card's button.
  static String deployToPhase(int nextPhase, {required bool purchaseUi}) =>
      purchaseUi
          ? 'Deploy to Phase $nextPhase \u2014 go PRO \u2192'
          : 'Deploy to Phase $nextPhase \u2192';

  // ── Google Play build (`PurchaseMode.playBilling`, OI-519, +51) ──────────
  // Plan section 5. No website, no outside price: every price shown comes
  // from Google Play. No em dashes.

  /// The Play body's buy button (same words as the web build's button).
  static const String playBuyButton = 'UPGRADE TO PRO';

  /// Plan card labels.
  static const String playMonthly = 'MONTHLY';
  static const String playYearly = 'YEARLY';
  static const String playPerMonth = 'PER MONTH';
  static const String playPerYear = 'PER YEAR';

  /// The yearly card's saving line, computed from the two Play prices.
  static String playYearlySaving(int percent) => 'SAVE $percent%';

  /// Subscription terms under the buy button (Play subscriptions policy).
  static const String playRenewalTerms =
      'Renews automatically until you cancel. Cancel anytime in Google Play.';

  /// A referral-days user buying: Play starts a subscription today.
  static const String playReferralStartsToday =
      'Your paid plan starts the day you buy. Your free days end then.';

  static const String playLoading = 'Loading plans';
  static const String playConfirming = 'Confirming your PRO with Google Play';
  static const String playLoadFailed =
      "Couldn't load the plans. Check your connection and try again.";
  static const String playRetry = 'TRY AGAIN';

  /// Google `PENDING` (e.g. a cash payment not yet made).
  static const String playPending =
      'Payment pending. PRO unlocks once Google confirms it.';

  /// This Google account's subscription belongs to another AVYA account.
  static const String playOwnedByOtherAccount =
      'This Google account already has PRO on another AVYA account. '
      'Sign in with that account, or manage it in Google Play.';

  /// The store's user is not (yet) the signed-in user: nothing was charged.
  static const String playAccountNotReady =
      'Your account is still loading. Try again in a moment.';

  static const String playPurchaseFailed =
      "The purchase didn't go through. Try again.";

  /// Google took the order but our server has not confirmed PRO yet.
  static const String playConfirmSlow =
      'Google took your order. PRO is still being confirmed: tap '
      'CHECK MY PRO STATUS in a minute.';

  static const String playRestored = 'PRO restored.';
  static const String playWelcome = 'You are PRO. Every feature is unlocked.';
  static const String playNothingToRestore =
      'No active PRO found for this account.';

  /// Already PRO: no plan cards, no buy button.
  static String proUntil(String date) => 'PRO until $date';

  static const String playManageButton = 'MANAGE IN GOOGLE PLAY';

  /// Delete account, Play row: cancel in Google Play before deleting.
  static const String playDeleteCancelFirst =
      'Your Google Play subscription keeps renewing until it is cancelled. '
      'Cancel it in Google Play before you delete your account.';

  /// Delete account, Play variant of the receipts line.
  static const String playReceiptsKept =
      'Google Play keeps your purchase receipts.';
}
