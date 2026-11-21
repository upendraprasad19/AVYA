import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/admin/models/admin_dashboard_data.dart';
import 'package:icanbefitter/shared/widgets/empty_state.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

class RevenueTab extends StatelessWidget {
  const RevenueTab({super.key, required this.data});

  final AdminDashboardData data;

  @override
  Widget build(BuildContext context) {
    final current = data.current;
    final revenue = data.revenue;
    final mrrFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      children: [
        WardCard(
          variant: WardCardVariant.hero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const WardEyebrow('DERIVED MRR'),
              const SizedBox(height: AppSpacing.stackXS),
              Text(
                mrrFormat.format(revenue.derivedMrrInr),
                style: AppTypography.h1.copyWith(color: AppColors.accent),
              ),
              const SizedBox(height: AppSpacing.stackXS),
              Text(
                'Derived from active-plan counts × current list price — '
                'not a stored figure. Assumes no active promo discounts.',
                style: AppTypography.bodySm.copyWith(color: AppColors.textMute),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sectionGap),
        WardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const WardEyebrow('SUBSCRIPTIONS'),
              const SizedBox(height: AppSpacing.stackS),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppSpacing.gridGap,
                crossAxisSpacing: AppSpacing.gridGap,
                childAspectRatio: 1.4,
                children: [
                  WardStatTile(
                    label: 'Active subs',
                    value: '${current.activeSubscriptions}',
                    accent: true,
                  ),
                  WardStatTile(
                    label: 'Monthly',
                    value: '${revenue.monthlyActive}',
                    unit: '₹${revenue.currentMonthlyPriceInr}/mo',
                  ),
                  WardStatTile(
                    label: 'Yearly',
                    value: '${revenue.yearlyActive}',
                    unit: '₹${revenue.currentYearlyPriceInr}/yr',
                  ),
                  WardStatTile(
                    label: 'Trial',
                    value: '${revenue.trialActive}',
                    unit: 'referral',
                  ),
                  if (revenue.otherActive > 0)
                    WardStatTile(
                      label: 'Other plan',
                      value: '${revenue.otherActive}',
                    ),
                  WardStatTile(label: 'Free users', value: '${current.freeUsers}'),
                  WardStatTile(label: 'PRO expired', value: '${current.proExpired}'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sectionGap),
        _ExpiryBucketCard(
          title: 'Already expired',
          tone: WardChipTone.bad,
          rows: data.subscriptionsExpiring.expired,
          dateFormat: DateFormat('d MMM yyyy'),
        ),
        const SizedBox(height: AppSpacing.stackL),
        _ExpiryBucketCard(
          title: 'Expiring within 7 days',
          tone: WardChipTone.warn,
          rows: data.subscriptionsExpiring.expiring7d,
          dateFormat: DateFormat('d MMM yyyy'),
        ),
        const SizedBox(height: AppSpacing.stackL),
        _ExpiryBucketCard(
          title: 'Expiring within 30 days',
          tone: WardChipTone.neutral,
          rows: data.subscriptionsExpiring.expiring30d,
          dateFormat: DateFormat('d MMM yyyy'),
        ),
      ],
    );
  }
}

class _ExpiryBucketCard extends StatelessWidget {
  const _ExpiryBucketCard({
    required this.title,
    required this.tone,
    required this.rows,
    required this.dateFormat,
  });

  final String title;
  final WardChipTone tone;
  final List<AdminExpiringSubscription> rows;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    return WardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WardEyebrow(
            title,
            trailing: WardChip(label: '${rows.length}', tone: tone),
          ),
          const SizedBox(height: AppSpacing.stackS),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: EmptyState(icon: Icons.check_circle_outline, title: 'None'),
            )
          else
            ...rows.map(
              (r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        r.email ?? r.userId,
                        style: AppTypography.bodyM,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      dateFormat.format(r.subscriptionExpiresAt),
                      style: AppTypography.bodySm
                          .copyWith(color: AppColors.textMute),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
