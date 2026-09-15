import 'package:flutter/material.dart';
import 'package:icanbefitter/core/services/subscription_service.dart'
    show ExpiryBannerSeverity;
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Home PRO-expiry banner (diagnose 2026-06-06) — sticky, dismiss-per-day.
///
/// Mirrors [StreakWarningBanner]'s Wardroom shell (soft bg + 3px accent left
/// border + glyph + Fraunces title + mono meta + CTA). Amber (`warn`) while PRO
/// is expiring within 7 days; red (`bad`) once it has lapsed. The trailing ✕
/// dismisses for the day; the RENEW CTA opens the canonical PaywallSheet.
class SubscriptionExpiryBanner extends StatelessWidget {
  final ExpiryBannerSeverity severity;
  final int daysLeft;
  final VoidCallback onRenew;
  final VoidCallback onDismiss;

  const SubscriptionExpiryBanner({
    super.key,
    required this.severity,
    required this.daysLeft,
    required this.onRenew,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final lapsed = severity == ExpiryBannerSeverity.lapsed;
    final accent = lapsed ? AppColors.bad : AppColors.warn;
    final title = lapsed
        ? 'Your PRO has expired'
        : 'PRO expires in $daysLeft ${daysLeft == 1 ? 'day' : 'days'}';
    final meta = lapsed
        ? 'RENEW TO KEEP YOUR COACH, REPORTS & FULL PLAN'
        : 'RENEW TO STAY PRO';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter, 0, AppSpacing.gutter, 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          border: Border(
            top: BorderSide(color: accent.withValues(alpha: 0.33)),
            right: BorderSide(color: accent.withValues(alpha: 0.33)),
            bottom: BorderSide(color: accent.withValues(alpha: 0.33)),
            left: BorderSide(color: accent, width: 3),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(lapsed ? '⚠' : '⏳',
                style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppTypography.h3.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: accent,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    style: AppTypography.monoXs.copyWith(
                      fontSize: 10,
                      color: AppColors.textDim,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Semantics(
              button: true,
              label: 'Renew PRO',
              child: GestureDetector(
                onTap: onRenew,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(AppRadius.sharp),
                  ),
                  child: Text(
                    'RENEW',
                    style: AppTypography.mono.copyWith(
                      fontSize: 11,
                      color: AppColors.bgDeep,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Semantics(
              button: true,
              label: 'Dismiss',
              child: GestureDetector(
                onTap: onDismiss,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.close, size: 16, color: AppColors.textDim),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
