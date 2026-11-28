/// Copy for the progress-photo free weekly cap (OI-348 Landing 3c, founder
/// call 2026-11-26: 1 free photo per IST week, no cap for PRO).
/// No line says "unlimited": the paywall surfaces ban the word
/// (`chat_limit_part_b_client_test.dart`).
///
/// Const-only, no em dashes. Every line except [goPro] is neutral and safe in
/// a build that sells nothing (`PurchaseMode.none`, ADR-0022); [goPro] is
/// drawn only when `showsUpgradeAffordance()` is true.
library;

class ProgressPhotoCopy {
  ProgressPhotoCopy._();

  /// Snackbar when a free user already holds this IST week's photo (the
  /// client pre-check, or the server's refusal).
  static const String weeklyUsed =
      "This week's free photo is in. Next one from Monday. PRO has no weekly limit.";

  /// The snackbar's action in a build that can sell PRO.
  static const String goPro = 'GO PRO';

  /// Caption shown to a free user above the gallery and in the empty state.
  static const String freeCaption = 'FREE · 1 PHOTO A WEEK';

  /// The Photos hub's Progress subtitle for a user who is not PRO.
  static const String hubSubtitleFree =
      '1 free photo a week · no limit with PRO';

  /// The paywall feature label (letterhead: "<label> is a PRO feature").
  static const String paywallFeature = 'No-Limit Progress Photos';

  /// The paywall subtitle for [paywallFeature].
  static const String paywallSubtitle =
      'One free photo a week. PRO has no weekly limit, so every check-in counts.';
}
