import 'package:flutter/foundation.dart';

/// Which purchase surface this BINARY offers (ADR-0022, plan
/// `docs/plans/2026-11-20-android-play-billing.md` section 3).
///
/// A compile-time decision: `--dart-define=ANDROID_PURCHASE_MODE=<wire name>`.
/// It is a build constant, not state, so there is no provider; widgets read
/// [PurchaseMode.current] directly.
///
/// * [razorpay]: the Razorpay checkout (web, and the Android builds up to +49).
/// * [none]: no price, no plan card, no promo box and no purchase button.
/// * [playBilling]: reserved for the RevenueCat build (plan section 8). Until
///   that plan is built and accepted it behaves EXACTLY like [none]: no
///   reader of [showsPlayBilling] exists, and `/build-apk` refuses it.
enum PurchaseMode {
  razorpay('razorpay'),
  none('none'),
  playBilling('play_billing');

  const PurchaseMode(this.wireName);

  /// The value of the `ANDROID_PURCHASE_MODE` define.
  final String wireName;

  /// TRUE only in [razorpay]. Every purchase surface keys on this one getter.
  bool get showsPurchaseUi => this == PurchaseMode.razorpay;

  /// TRUE only in [razorpay]. `RazorpayService.openCheckout` refuses to start
  /// an order when this is false (defence in depth behind the paywall).
  bool get showsRazorpay => this == PurchaseMode.razorpay;

  /// TRUE only in [playBilling]. Deliberately has no reader yet.
  bool get showsPlayBilling => this == PurchaseMode.playBilling;

  /// Test seam. Null in every real run.
  @visibleForTesting
  static PurchaseMode? debugOverrideForTests;

  /// The mode of THIS binary.
  ///
  /// Reads `kIsWeb`, `dart.vm.product` and the define. Both `fromEnvironment`
  /// reads are `const`: Dart only guarantees them in a const context, and an
  /// ahead-of-time (release) build does not have the declarations at run time,
  /// so a non-const read would silently resolve every store build to
  /// `razorpay` (B-pass 2026-11-20, P1; precedent `ist_date.dart`
  /// `_isReleaseBuild`, `app_constants.dart`). It must NOT use `dart:io`
  /// `Platform` or `defaultTargetPlatform`: CI runs on Linux, so a platform
  /// check would put every existing test in [none] (pinned by
  /// `test/contracts/purchase_mode_current_wiring_test.dart`).
  static PurchaseMode get current =>
      debugOverrideForTests ??
      resolvePurchaseMode(
        isWeb: kIsWeb,
        isRelease: const bool.fromEnvironment('dart.vm.product'),
        raw: const String.fromEnvironment('ANDROID_PURCHASE_MODE'),
      );
}

/// Pure resolver. Truth table (plan section 3):
///
/// * web: always [PurchaseMode.razorpay] (the web checkout is unchanged,
///   ADR-0019; the define is ignored);
/// * not web, valid define (trimmed, case-insensitive): that value;
/// * not web, define absent or unrecognised: a RELEASE build is
///   [PurchaseMode.none] (so a forgotten define can never put a purchase UI
///   in a store build); debug, profile and tests are [PurchaseMode.razorpay].
PurchaseMode resolvePurchaseMode({
  required bool isWeb,
  required bool isRelease,
  required String raw,
}) {
  if (isWeb) return PurchaseMode.razorpay;
  final wanted = raw.trim().toLowerCase();
  for (final mode in PurchaseMode.values) {
    if (mode.wireName == wanted) return mode;
  }
  return isRelease ? PurchaseMode.none : PurchaseMode.razorpay;
}

/// Whether an upgrade call to action (a chip, a banner, a menu item) may be
/// drawn at all. One writer for the decision (plan section 5.3).
bool showsUpgradeAffordance() => PurchaseMode.current.showsPurchaseUi;
