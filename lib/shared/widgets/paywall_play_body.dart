import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/copy/purchase_copy.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/play_billing_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart'
    show authUserIdTokenProvider;
import 'package:icanbefitter/features/profile/providers/profile_provider.dart'
    show SubscriptionInfoData, subscriptionInfoProvider;
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import 'package:url_launcher/url_launcher.dart';

/// What [PaywallSheet] shows in a Google Play build (`PurchaseMode.playBilling`,
/// OI-519, plan section 5). Still inside `PaywallSheet` (CLAUDE.md rule 7).
///
/// Every price comes from Google Play (`StoreProduct.priceString`), never from
/// `AppConstants`. No promo box, no stacking line, no website. An active paid
/// plan (any store) shows "PRO until" a date and no buy button; a Play row
/// also gets MANAGE IN GOOGLE PLAY.
///
/// RESTORE is `revenuecat-sync` + `verifyFromServer(force: true)`
/// ([playProConfirmerProvider]); never `Purchases.restorePurchases()`.

/// The uid allowed to buy now, or null (no session, or the auth uid and the
/// Hive owner disagree). Overridden in tests.
final playBuyerUidProvider = Provider<String?>((ref) {
  ref.watch(authUserIdTokenProvider);
  return playBuyerUid(
    authUid: SupabaseService.instance.currentUser?.id,
    hiveOwner: HiveUserSession.currentOwnerFullId,
  );
});

/// Opens Google Play's subscriptions page. Overridden in tests.
final playManageOpenerProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final ok = await launchUrl(Uri.parse(kPlayManageUrl),
        mode: LaunchMode.externalApplication);
    if (!ok) {
      unawaited(ErrorTelemetry.logEvent('play_manage_open_failed'));
    }
  };
});

const List<String> _kMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// PURE. A shown PRO date, as the IST calendar day (`24 Dec 2026`).
String istShortDate(DateTime t) {
  final d = istDateOf(t);
  return '${d.day} ${_kMonths[d.month - 1]} ${d.year}';
}

enum _PlayPhase { loading, ready, purchasing, confirming, pending, error }

class PaywallPlayBody extends ConsumerStatefulWidget {
  final String title;
  final String subtitle;
  final List<String> benefits;

  /// The paywall's `feature` (telemetry only).
  final String feature;

  /// Called once when the buy button is tapped (the sheet's dismiss
  /// telemetry tells "closed without trying" from "tried").
  final VoidCallback onUpgradeTapped;
  final VoidCallback onClose;

  const PaywallPlayBody({
    super.key,
    required this.title,
    required this.subtitle,
    required this.benefits,
    required this.feature,
    required this.onUpgradeTapped,
    required this.onClose,
  });

  @override
  ConsumerState<PaywallPlayBody> createState() => _PaywallPlayBodyState();
}

class _PaywallPlayBodyState extends ConsumerState<PaywallPlayBody> {
  _PlayPhase _phase = _PlayPhase.loading;
  List<PlayPlanOffer> _plans = const [];
  PlayPlanPeriod _selected = PlayPlanPeriod.yearly;
  String? _message;
  bool _messageOk = false;
  bool _showManage = false;

  @override
  void initState() {
    super.initState();
    // An active paid plan never loads offerings (no buy button to fill).
    if (!ref.read(subscriptionInfoProvider).hasActivePaidPlan) {
      unawaited(_load());
    }
  }

  void _say(String? text, {bool ok = false}) {
    _message = text;
    _messageOk = ok;
  }

  Future<void> _load() async {
    setState(() {
      _phase = _PlayPhase.loading;
      _say(null);
    });
    final uid = ref.read(playBuyerUidProvider);
    if (uid == null) {
      setState(() {
        _phase = _PlayPhase.error;
        _say(PurchaseCopy.playAccountNotReady);
      });
      return;
    }
    try {
      final store = ref.read(playStoreProvider);
      // Awaited: no plan card (so no buy button) until the store's user is
      // this user.
      await store.identify(uid);
      final plans = await store.loadPlans();
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _phase = _PlayPhase.ready;
      });
    } catch (e) {
      unawaited(ErrorTelemetry.logEvent('play_offerings_failed',
          message: 'type=${e.runtimeType}'));
      if (!mounted) return;
      setState(() {
        _phase = _PlayPhase.error;
        _say(PurchaseCopy.playLoadFailed);
      });
    }
  }

  PlayPlanOffer? get _selectedOffer {
    for (final p in _plans) {
      if (p.period == _selected) return p;
    }
    return null;
  }

  Future<void> _buy() async {
    final offer = _selectedOffer;
    final uid = ref.read(playBuyerUidProvider);
    if (offer == null || _phase != _PlayPhase.ready) return;
    widget.onUpgradeTapped();
    unawaited(ErrorTelemetry.logEvent('paywall_upgrade_tapped',
        message: 'feature=${widget.feature} plan=${offer.planId} store=play'));
    if (uid == null) {
      setState(() => _say(PurchaseCopy.playAccountNotReady));
      return;
    }
    setState(() {
      _phase = _PlayPhase.purchasing;
      _showManage = false;
      _say(null);
    });
    final outcome =
        await ref.read(playStoreProvider).purchase(offer, expectedUid: uid);
    if (!mounted) return;
    switch (outcome.status) {
      case PlayPurchaseStatus.purchased:
        await _confirm(afterPurchase: true);
      case PlayPurchaseStatus.cancelled:
        setState(() => _phase = _PlayPhase.ready);
      case PlayPurchaseStatus.pending:
        unawaited(ErrorTelemetry.logEvent('play_purchase_pending',
            message: 'plan=${offer.planId}'));
        setState(() {
          _phase = _PlayPhase.pending;
          _say(PurchaseCopy.playPending);
        });
      case PlayPurchaseStatus.ownedByOtherAccount:
        unawaited(ErrorTelemetry.logEvent('play_purchase_owned_elsewhere',
            message: 'code=${outcome.errorCode}'));
        setState(() {
          _phase = _PlayPhase.ready;
          _showManage = true;
          _say(PurchaseCopy.playOwnedByOtherAccount);
        });
      case PlayPurchaseStatus.identityMismatch:
        unawaited(ErrorTelemetry.logEvent('play_purchase_identity_mismatch'));
        setState(() {
          _phase = _PlayPhase.ready;
          _say(PurchaseCopy.playAccountNotReady);
        });
      case PlayPurchaseStatus.failed:
        unawaited(ErrorTelemetry.logEvent('play_purchase_failed',
            message: 'code=${outcome.errorCode}'));
        setState(() {
          _phase = _PlayPhase.ready;
          _say(PurchaseCopy.playPurchaseFailed);
        });
    }
  }

  /// After a purchase (polls) or on RESTORE (one ask). A confirmed PRO
  /// rewrites the subscription state, so this body rebuilds into the
  /// "PRO until" view by itself.
  Future<void> _confirm({required bool afterPurchase}) async {
    final back = _phase == _PlayPhase.confirming ? _PlayPhase.ready : _phase;
    setState(() {
      _phase = _PlayPhase.confirming;
      _say(null);
    });
    bool pro;
    try {
      pro = await ref.read(playProConfirmerProvider)(
          afterPurchase: afterPurchase);
    } catch (e) {
      unawaited(ErrorTelemetry.logEvent('play_confirm_failed',
          message: 'type=${e.runtimeType}'));
      pro = false;
    }
    if (!mounted) return;
    ref.invalidate(subscriptionInfoProvider);
    setState(() {
      _phase = back == _PlayPhase.purchasing ? _PlayPhase.ready : back;
      if (pro) {
        _say(afterPurchase ? PurchaseCopy.playWelcome : PurchaseCopy.playRestored,
            ok: true);
      } else {
        _say(afterPurchase
            ? PurchaseCopy.playConfirmSlow
            : PurchaseCopy.playNothingToRestore);
      }
    });
  }

  Future<void> _manage() async {
    unawaited(ErrorTelemetry.logEvent('play_manage_tapped'));
    await ref.read(playManageOpenerProvider)();
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(subscriptionInfoProvider);
    final busy = _phase == _PlayPhase.purchasing ||
        _phase == _PlayPhase.confirming;
    return Container(
      key: const ValueKey('paywall-play-body'),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.card),
        ),
        border: Border(
          top: BorderSide(color: AppColors.line2, width: 1),
          left: BorderSide(color: AppColors.line2, width: 1),
          right: BorderSide(color: AppColors.line2, width: 1),
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.stackM,
            AppSpacing.gutter,
            AppSpacing.stackL,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.stackL),
                  decoration: BoxDecoration(
                    color: AppColors.line2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              WardLetterhead(
                eyebrow: info.hasActivePaidPlan ? PurchaseCopy.eyebrow : 'GO PRO',
                title: widget.title,
                divider: false,
                padding: EdgeInsets.zero,
              ),
              const SizedBox(height: AppSpacing.stackS),
              const WardRule(gold: true, margin: EdgeInsets.zero),
              const SizedBox(height: AppSpacing.stackM),
              Text(
                widget.subtitle,
                style: AppTypography.body.copyWith(
                  color: AppColors.textDim,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.stackL),
              _benefits(),
              const SizedBox(height: AppSpacing.stackL),
              if (info.hasActivePaidPlan)
                ..._alreadyPro(info)
              else
                ..._purchase(info, busy),
              if (_message != null) ...[
                const SizedBox(height: AppSpacing.stackS),
                Text(
                  _message!,
                  key: const ValueKey('paywall-play-status'),
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySm.copyWith(
                    color: _messageOk ? AppColors.ok : AppColors.textDim,
                  ),
                ),
              ],
              if (_showManage && !info.hasActivePaidPlan) ...[
                const SizedBox(height: AppSpacing.stackS),
                _manageButton(),
              ],
              const SizedBox(height: AppSpacing.stackS),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: widget.onClose,
                    child: Text(
                      'MAYBE LATER',
                      style: AppTypography.monoXs.copyWith(
                        color: AppColors.textMute,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  Text(
                    '·',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.textGhost,
                    ),
                  ),
                  TextButton(
                    onPressed:
                        busy ? null : () => _confirm(afterPurchase: false),
                    child: Text(
                      'RESTORE',
                      style: AppTypography.monoXs.copyWith(
                        color: AppColors.accent,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _benefits() {
    return WardCard(
      variant: WardCardVariant.inset,
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHAT YOU UNLOCK',
            style: AppTypography.mono.copyWith(
              color: AppColors.textMute,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: AppSpacing.stackS),
          ...widget.benefits.map(
            (b) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check, color: AppColors.accent, size: 15),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      b,
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _alreadyPro(SubscriptionInfoData info) {
    final shown = info.displayExpiresAt ?? info.expiresAt;
    return [
      Text(
        shown == null ? 'PRO' : PurchaseCopy.proUntil(istShortDate(shown)),
        key: const ValueKey('paywall-play-pro-until'),
        textAlign: TextAlign.center,
        style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
      ),
      if (info.isPlayStore) ...[
        const SizedBox(height: AppSpacing.stackM),
        _manageButton(),
      ],
    ];
  }

  Widget _manageButton() => WardButton(
        key: const ValueKey('paywall-play-manage'),
        label: PurchaseCopy.playManageButton,
        onPressed: _manage,
        variant: WardButtonVariant.outline,
        fullWidth: true,
      );

  List<Widget> _purchase(SubscriptionInfoData info, bool busy) {
    switch (_phase) {
      case _PlayPhase.loading:
        return [
          Container(
            key: const ValueKey('paywall-play-loading'),
            height: 120,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.input,
              borderRadius: BorderRadius.circular(AppRadius.sharp),
            ),
            child: Text(
              PurchaseCopy.playLoading,
              style: AppTypography.monoXs.copyWith(
                color: AppColors.textMute,
                letterSpacing: 2,
              ),
            ),
          ),
        ];
      case _PlayPhase.error:
        return [
          WardButton(
            key: const ValueKey('paywall-play-retry'),
            label: PurchaseCopy.playRetry,
            onPressed: _load,
            variant: WardButtonVariant.outline,
            fullWidth: true,
          ),
        ];
      case _PlayPhase.pending:
        return const [];
      case _PlayPhase.confirming:
        return [
          const LinearProgressIndicator(
            color: AppColors.accent,
            backgroundColor: AppColors.input,
          ),
          const SizedBox(height: AppSpacing.stackS),
          Text(
            PurchaseCopy.playConfirming,
            textAlign: TextAlign.center,
            style: AppTypography.bodySm.copyWith(color: AppColors.textDim),
          ),
        ];
      case _PlayPhase.ready:
      case _PlayPhase.purchasing:
        break;
    }
    PlayPlanOffer? of(PlayPlanPeriod p) {
      for (final o in _plans) {
        if (o.period == p) return o;
      }
      return null;
    }

    final monthly = of(PlayPlanPeriod.monthly);
    final yearly = of(PlayPlanPeriod.yearly);
    final saving = (monthly != null && yearly != null)
        ? yearlySavingPercent(monthly: monthly.price, yearly: yearly.price)
        : null;
    return [
      Row(
        children: [
          if (monthly != null)
            Expanded(
              child: GestureDetector(
                onTap: busy
                    ? null
                    : () => setState(() => _selected = PlayPlanPeriod.monthly),
                child: _PlayPlanCard(
                  label: PurchaseCopy.playMonthly,
                  price: monthly.priceString,
                  period: PurchaseCopy.playPerMonth,
                  isSelected: _selected == PlayPlanPeriod.monthly,
                ),
              ),
            ),
          if (monthly != null && yearly != null) const SizedBox(width: 10),
          if (yearly != null)
            Expanded(
              child: GestureDetector(
                onTap: busy
                    ? null
                    : () => setState(() => _selected = PlayPlanPeriod.yearly),
                child: _PlayPlanCard(
                  label: PurchaseCopy.playYearly,
                  price: yearly.priceString,
                  period: PurchaseCopy.playPerYear,
                  isSelected: _selected == PlayPlanPeriod.yearly,
                  savings: saving == null
                      ? null
                      : PurchaseCopy.playYearlySaving(saving),
                ),
              ),
            ),
        ],
      ),
      if (info.isReferralTrial) ...[
        const SizedBox(height: AppSpacing.stackS),
        Text(
          PurchaseCopy.playReferralStartsToday,
          key: const ValueKey('paywall-play-referral-today'),
          textAlign: TextAlign.center,
          style: AppTypography.bodySm.copyWith(color: AppColors.textDim),
        ),
      ],
      const SizedBox(height: AppSpacing.stackM),
      WardButton(
        key: const ValueKey('paywall-play-buy'),
        label: busy ? '...' : PurchaseCopy.playBuyButton,
        onPressed: busy || _selectedOffer == null ? null : _buy,
        variant: WardButtonVariant.primary,
        fullWidth: true,
      ),
      const SizedBox(height: AppSpacing.stackS),
      Text(
        PurchaseCopy.playRenewalTerms,
        textAlign: TextAlign.center,
        style: AppTypography.monoXs.copyWith(color: AppColors.textMute),
      ),
    ];
  }
}

class _PlayPlanCard extends StatelessWidget {
  final String label;
  final String price;
  final String period;
  final bool isSelected;
  final String? savings;

  const _PlayPlanCard({
    required this.label,
    required this.price,
    required this.period,
    required this.isSelected,
    this.savings,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.accentSoft : AppColors.input,
        borderRadius: BorderRadius.circular(AppRadius.sharp),
        border: Border.all(
          color: isSelected ? AppColors.accent : AppColors.line2,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          if (savings != null)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                savings!,
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.bgDeep,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          Text(
            label,
            style: AppTypography.mono.copyWith(
              color: AppColors.textMute,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              price,
              style: AppTypography.h1.copyWith(
                fontSize: 26,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            period,
            style: AppTypography.monoXs.copyWith(
              color: AppColors.textMute,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
