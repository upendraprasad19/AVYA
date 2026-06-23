part of 'screen.dart';

extension _SubscriptionSection on _ProfileScreenState {

  // ── #7 Subscription Section ─────────────────────────────────────

  Widget _buildSubscriptionSection(SubscriptionInfoData subInfo, bool isPro, UsageCounterService usage) {
    if (isPro) {
      // PRO dossier — matches the Wardroom handoff spec
      // (`design_handoff_wardroom/src/screens/profile.jsx` block 13,
      // lines 360–391): gradient accentSoft→bgDeep card with a Seal
      // badge in the top-right corner, PRO chip + plan tag on top,
      // "Everything unlocked" Fraunces hero line, renewal mono line,
      // and a dashed-divider + MANAGE SUBSCRIPTION → CTA below.
      final expiryStr = subInfo.expiresAt != null
          ? '${subInfo.expiresAt!.day} ${_ProfileScreenState._monthName(subInfo.expiresAt!.month)} ${subInfo.expiresAt!.year}'
          : '\u2014';
      final planLabel = (subInfo.plan ?? 'monthly').toUpperCase();
      // "EST" seal carries the member-since date — the Wardroom brand
      // motif mirrors the welcome screen's "EST · 2026" + the founder
      // seal. Compute from expiresAt minus plan duration (best-effort;
      // no dedicated startedAt field exists on SubscriptionInfoData).
      final sealDate = _ProfileScreenState._estSealDate(subInfo);
      return Container(
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.accentSoft,
              AppColors.bgDeep,
            ],
          ),
          border: Border.all(
            color: AppColors.accent.withValues(alpha: 0.40),
          ),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Reserve space on the right so content doesn't
                    // slide under the corner seal.
                    Padding(
                      padding: const EdgeInsets.only(right: 56),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const WardChip(
                                label: 'PRO',
                                tone: WardChipTone.gold,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                planLabel,
                                style: AppTypography.monoXs.copyWith(
                                  fontSize: 9,
                                  color: AppColors.accent,
                                  letterSpacing: 1.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (subInfo.isVerifying) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.sync,
                                  size: 11,
                                  color: AppColors.accent.withValues(alpha: 0.75),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'CONFIRMING',
                                  style: AppTypography.monoXs.copyWith(
                                    fontSize: 9,
                                    color: AppColors.accent.withValues(alpha: 0.75),
                                    letterSpacing: 1.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Everything unlocked',
                            style: AppTypography.h3.copyWith(
                              fontSize: 18,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subInfo.isVerifying
                                ? 'AWAITING WEBHOOK CONFIRMATION'
                                : '${(subInfo.plan ?? '').contains('trial') ? 'EXPIRES' : 'RENEWS'} $expiryStr'.toUpperCase(),
                            style: AppTypography.mono.copyWith(
                              fontSize: 10,
                              color: AppColors.textDim,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Dashed divider + MANAGE CTA (full width — past the
                    // reserved padding so it stretches across).
                    const SizedBox(height: 12),
                    WardDashedBorder(
                      color: AppColors.line2,
                      strokeWidth: 1,
                      dashLength: 3,
                      gapLength: 3,
                      radius: 0,
                      child: const SizedBox(
                        width: double.infinity,
                        height: 0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: _onManageSubscription,
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        children: [
                          Text(
                            'MANAGE SUBSCRIPTION \u2192',
                            style: AppTypography.mono.copyWith(
                              fontSize: 9,
                              color: AppColors.accent,
                              letterSpacing: 2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Corner seal — JSX spec uses size 48; the Wardroom
              // WardSealBadge.subscription variant defaults to 54 for
              // consistency with the report + phase placements.
              Positioned(
                top: 10,
                right: 10,
                child: WardSealBadge(
                  label: 'EST',
                  subline: sealDate,
                  variant: WardSealVariant.subscription,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Free user — rate-limit meters with trial pill.
    final aiTextUsed = usage.used(AppConstants.featureAiTextLogPro, false);
    final aiTextLimit = AppConstants.freeAiTextLogsPerDay;
    final scanUsed = usage.used(AppConstants.featureScanMealPro, false);
    final scanLimit = AppConstants.freeScanMealPerDay;
    final cartUsed = usage.used(AppConstants.featureCartAuditorPro, false);
    final cartLimit = AppConstants.freeCartAuditorPerDay;

    return WardCard(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('FREE PLAN',
                  style: AppTypography.mono.copyWith(
                    color: AppColors.textMute,
                    letterSpacing: 2.0,
                  )),
              const Spacer(),
              GestureDetector(
                onTap: () => showPaywallSheet(context, feature: 'PRO'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(AppRadius.sharp),
                  ),
                  child: Text('UPGRADE',
                      style: AppTypography.monoXs.copyWith(
                        color: Colors.black,
                        letterSpacing: 2.0,
                        fontWeight: FontWeight.w700,
                      )),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _usageRow('AI Text Logs', aiTextUsed, aiTextLimit, '/day'),
          const SizedBox(height: 8),
          _usageRow('Meal Scans', scanUsed, scanLimit, '/day'),
          const SizedBox(height: 8),
          _usageRow('Cart Auditor', cartUsed, cartLimit, '/day'),
        ],
      ),
    );
  }

  Widget _usageRow(String label, int used, int limit, String period) {
    final pct = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;
    final isExhausted = used >= limit;
    final meterColor = isExhausted ? AppColors.bad : AppColors.accent;
    final readoutColor = isExhausted ? AppColors.bad : AppColors.textDim;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 92,
          child: Text(label.toUpperCase(),
              style: AppTypography.monoXs.copyWith(
                color: AppColors.textMute,
                letterSpacing: 1.6,
              )),
        ),
        Expanded(child: WardBar(pct: pct, color: meterColor, height: 4)),
        const SizedBox(width: 10),
        Text('$used/$limit$period',
            style: AppTypography.monoXs.copyWith(color: readoutColor)),
      ],
    );
  }

  // ── #8 Nutrition Targets (Bug #24: + projection subtitle) ──────

  /// Theme C · Test #8 — paired with `_buildNutritionTargetsInner`. The
  /// inner builder doesn't expose `onTap`, so this helper computes whether
  /// a projection sheet exists and returns the matching tap callback (or
  /// null) for `_buildFlushCard` to wrap. Keeps the inner method pure.
  VoidCallback? _nutritionTargetsOnTap({
    double? currentKg,
    double? targetKg,
    required String goal,
    required String pacePreference,
  }) {
    if ((goal != 'lose_fat' && goal != 'build_muscle') ||
        currentKg == null ||
        targetKg == null ||
        (currentKg - targetKg).abs() <= 0.1) {
      return null;
    }
    return () => _showPaceDetailSheet(
          currentKg: currentKg,
          targetKg: targetKg,
          pacePreference: pacePreference,
          goal: goal,
        );
  }
}
