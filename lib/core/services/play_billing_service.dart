// Google Play purchases through RevenueCat (OI-519, +51, ADR-0022; plan
// docs/plans/2026-11-23-revenuecat-play-billing-51.md section 5).
//
// The ONLY file under lib/ that imports `purchases_flutter`
// (test/contracts/purchases_package_dormant_test.dart). Everything else talks
// to the [PlayStore] interface, so widget tests use a fake and nothing in a
// `razorpay` or `none` build ever touches the SDK.
//
// Identity: the RevenueCat App User ID is the Supabase user id. [identify] is
// awaited before plans are shown (configure once, `logIn` on a different
// user), so the buy buttons stay disabled while it runs; [purchase] re-reads
// the SDK's id and refuses unless it equals the expected uid. Sign-out calls
// [releaseIdentity] (`logOut`, best effort) from
// `releaseDeviceSessionIdentity`.
//
// Restore is NOT `Purchases.restorePurchases()`: it could move a purchase
// between our accounts. Restore = `revenuecat-sync` + verifyFromServer.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/constants/payment_timing.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

/// The two base plans of the `avya_pro` subscription.
enum PlayPlanPeriod { monthly, yearly }

/// One plan card's data. [price] and [priceString] come from Google Play
/// (never from `AppConstants`); [handle] is the SDK package, opaque to callers.
@immutable
class PlayPlanOffer {
  final PlayPlanPeriod period;
  final String priceString;
  final double price;
  final Object? handle;

  const PlayPlanOffer({
    required this.period,
    required this.priceString,
    required this.price,
    this.handle,
  });

  /// The plan name the server rows use (`subscriptions.plan`).
  String get planId => period == PlayPlanPeriod.monthly ? 'monthly' : 'yearly';
}

/// What a purchase attempt ended in.
enum PlayPurchaseStatus {
  /// Google charged; the app now confirms through `revenuecat-sync`.
  purchased,

  /// The user closed the Google sheet. Not an error.
  cancelled,

  /// Google accepted the order but the payment is pending (e.g. cash).
  pending,

  /// This Google account already holds the subscription (another AVYA
  /// account bought it; transfer is "keep with original App User ID").
  ownedByOtherAccount,

  /// The SDK's user is not the signed-in user: refused before any charge.
  identityMismatch,

  /// Anything else (network, store problem, not allowed).
  failed,
}

@immutable
class PlayPurchaseOutcome {
  final PlayPurchaseStatus status;

  /// A fixed SDK error-code NAME for telemetry (never a message).
  final String? errorCode;

  const PlayPurchaseOutcome(this.status, {this.errorCode});
}

/// PURE. Maps an SDK error code name to the outcome the sheet shows.
PlayPurchaseStatus playStatusForErrorCode(String code) {
  switch (code) {
    case 'purchaseCancelledError':
      return PlayPurchaseStatus.cancelled;
    case 'paymentPendingError':
      return PlayPurchaseStatus.pending;
    case 'productAlreadyPurchasedError':
    case 'receiptAlreadyInUseError':
    case 'receiptInUseByOtherSubscriberError':
      return PlayPurchaseStatus.ownedByOtherAccount;
    default:
      return PlayPurchaseStatus.failed;
  }
}

/// PURE. The yearly plan's saving against twelve monthly payments, as a
/// whole percent, or null when it is not a real saving (a missing or
/// non-positive price, or a yearly price at or above 12 months).
int? yearlySavingPercent({required double monthly, required double yearly}) {
  if (!monthly.isFinite || !yearly.isFinite || monthly <= 0 || yearly <= 0) {
    return null;
  }
  final full = monthly * 12;
  if (yearly >= full) return null;
  final pct = ((full - yearly) / full * 100).floor();
  return pct >= 1 ? pct : null;
}

/// The store seam. One real implementation ([RevenueCatPlayStore]); tests
/// override [playStoreProvider] with a fake.
abstract class PlayStore {
  /// True when this build carries a usable public SDK key.
  bool get hasKey;

  /// Configure the SDK for [uid] (first call) or switch it to [uid].
  Future<void> identify(String uid);

  /// The two plans of the current offering, monthly first. Throws when the
  /// store cannot answer (the sheet shows its error state with retry).
  Future<List<PlayPlanOffer>> loadPlans();

  /// Buys [offer] for [expectedUid]. Never throws.
  Future<PlayPurchaseOutcome> purchase(PlayPlanOffer offer,
      {required String expectedUid});

  /// Best-effort `logOut` at sign-out. Never throws.
  Future<void> releaseIdentity();
}

class RevenueCatPlayStore implements PlayStore {
  RevenueCatPlayStore._();
  static final RevenueCatPlayStore instance = RevenueCatPlayStore._();

  /// The uid the SDK was last configured or logged in with (this process).
  String? _identified;

  @override
  bool get hasKey => AppConstants.revenueCatGoogleKey.startsWith('goog_');

  @override
  Future<void> identify(String uid) async {
    if (!hasKey) throw StateError('play_billing_key_missing');
    if (_identified == uid) return;
    if (!await Purchases.isConfigured) {
      await Purchases.configure(
          PurchasesConfiguration(AppConstants.revenueCatGoogleKey)
            ..appUserID = uid);
    } else if (await Purchases.appUserID != uid) {
      await Purchases.logIn(uid);
    }
    _identified = uid;
  }

  @override
  Future<List<PlayPlanOffer>> loadPlans() async {
    final offering = (await Purchases.getOfferings()).current;
    final monthly = offering?.monthly;
    final annual = offering?.annual;
    if (monthly == null || annual == null) {
      throw StateError('play_offering_incomplete');
    }
    PlayPlanOffer of(PlayPlanPeriod p, Package pkg) => PlayPlanOffer(
          period: p,
          priceString: pkg.storeProduct.priceString,
          price: pkg.storeProduct.price,
          handle: pkg,
        );
    return [
      of(PlayPlanPeriod.monthly, monthly),
      of(PlayPlanPeriod.yearly, annual),
    ];
  }

  @override
  Future<PlayPurchaseOutcome> purchase(PlayPlanOffer offer,
      {required String expectedUid}) async {
    final pkg = offer.handle;
    if (pkg is! Package) {
      return const PlayPurchaseOutcome(PlayPurchaseStatus.failed,
          errorCode: 'no_package');
    }
    try {
      if (await Purchases.appUserID != expectedUid) {
        return const PlayPurchaseOutcome(PlayPurchaseStatus.identityMismatch);
      }
      await Purchases.purchase(PurchaseParams.package(pkg));
      return const PlayPurchaseOutcome(PlayPurchaseStatus.purchased);
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e).name;
      return PlayPurchaseOutcome(playStatusForErrorCode(code), errorCode: code);
    } catch (e) {
      return PlayPurchaseOutcome(PlayPurchaseStatus.failed,
          errorCode: e.runtimeType.toString());
    }
  }

  @override
  Future<void> releaseIdentity() async {
    try {
      if (_identified == null || !await Purchases.isConfigured) return;
      _identified = null;
      await Purchases.logOut();
    } catch (e) {
      // logOut throws for an anonymous SDK user; never surfaced.
      unawaited(ErrorTelemetry.logEvent('play_billing_logout_failed',
          message: 'type=${e.runtimeType}'));
    }
  }
}

/// The store the paywall uses. Overridden in tests.
final playStoreProvider = Provider<PlayStore>((ref) => RevenueCatPlayStore.instance);

/// Google Play's own subscriptions page for AVYA PRO (cancel, change plan,
/// payment method). The only link a Play build opens for a subscription.
const String kPlayManageUrl =
    'https://play.google.com/store/account/subscriptions'
    '?sku=avya_pro&package=com.icanbefitter.icanbefitter';

/// PURE. The signed-in user may buy only when the auth uid and the Hive
/// owner agree (`auth_hive_owner_agreement`): a purchase is bound to the
/// RevenueCat App User ID, so a half-switched account must never buy.
String? playBuyerUid({required String? authUid, required String? hiveOwner}) =>
    (authUid != null && authUid.isNotEmpty && authUid == hiveOwner)
        ? authUid
        : null;

/// One `revenuecat-sync` answer.
enum PlaySyncAnswer {
  /// The body says `is_pro: true`.
  pro,

  /// Not PRO (yet), or a failure worth one more try.
  notPro,

  /// Rate limited (429): stop asking.
  stop,
}

/// PURE loop. Asks `revenuecat-sync` up to [attempts] times until it answers
/// [PlaySyncAnswer.pro] (or [PlaySyncAnswer.stop]), then ALWAYS ends with
/// [verify] (`verifyFromServer(force: true)`), which writes Hive: the sync
/// answer alone never makes the app PRO.
Future<bool> confirmPlayPro({
  required Future<PlaySyncAnswer> Function() syncOnce,
  required Future<bool> Function() verify,
  required int attempts,
  required Future<void> Function(int attempt) wait,
}) async {
  for (var i = 0; i < attempts; i++) {
    final answer = await syncOnce();
    if (answer != PlaySyncAnswer.notPro) break;
    if (i < attempts - 1) await wait(i);
  }
  return verify();
}

/// One `revenuecat-sync` call. Never throws: every failure is logged with
/// its status and error code (never a message) and becomes an answer.
Future<PlaySyncAnswer> revenueCatSyncOnce() async {
  try {
    final res = await SupabaseService.instance
        .callFunction('revenuecat-sync', spendsQuotaPerCall: true);
    final data = res.data;
    return data is Map && data['is_pro'] == true
        ? PlaySyncAnswer.pro
        : PlaySyncAnswer.notPro;
  } on FunctionException catch (e) {
    final details = e.details;
    final code = details is Map ? details['error_code'] : null;
    unawaited(ErrorTelemetry.logEvent('revenuecat_sync_failed',
        message: 'status=${e.status} code=$code'));
    return e.status == 429 ? PlaySyncAnswer.stop : PlaySyncAnswer.notPro;
  } catch (e) {
    unawaited(ErrorTelemetry.logEvent('revenuecat_sync_failed',
        message: 'type=${e.runtimeType}'));
    return PlaySyncAnswer.notPro;
  }
}

/// Polls after a purchase (Google can take a few seconds to hand RevenueCat
/// the receipt); one ask on RESTORE / CHECK MY PRO STATUS. Each ask spends
/// one of the user's 20 hourly `revenuecat-sync` units.
const int kPlayConfirmAttemptsAfterPurchase = 4;

typedef PlayProConfirmer = Future<bool> Function({required bool afterPurchase});

/// The confirm step the paywall uses. Overridden in tests.
final playProConfirmerProvider = Provider<PlayProConfirmer>((ref) {
  return ({required bool afterPurchase}) => confirmPlayPro(
        syncOnce: revenueCatSyncOnce,
        verify: () =>
            SubscriptionService.instance.verifyFromServer(force: true),
        attempts: afterPurchase ? kPlayConfirmAttemptsAfterPurchase : 1,
        wait: (i) => Future<void>.delayed(Duration(seconds: pollDelaySeconds(i))),
      );
});
