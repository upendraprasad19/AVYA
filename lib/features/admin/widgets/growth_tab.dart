import 'package:flutter/material.dart';

import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/features/admin/models/admin_dashboard_data.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

class GrowthTab extends StatelessWidget {
  const GrowthTab({super.key, required this.data});

  final AdminDashboardData data;

  @override
  Widget build(BuildContext context) {
    final current = data.current;
    // trend arrives newest-first (Edge Function orders snapshot_date desc);
    // reverse to chronological (oldest -> newest) for the sparkline.
    final chronological = data.trend.reversed.toList();
    final totalUsersSeries =
        chronological.map((p) => p.totalUsers.toDouble()).toList();
    final signupsSeries =
        chronological.map((p) => p.signupsTodayIst.toDouble()).toList();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      children: [
        WardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const WardEyebrow('ACQUISITION'),
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
                    label: 'Total users',
                    value: '${current.totalUsers}',
                    accent: true,
                  ),
                  WardStatTile(
                    label: 'Signups today',
                    value: '${current.signupsTodayIst}',
                  ),
                  WardStatTile(
                    label: 'Signups 7d',
                    value: '${current.signups7d}',
                  ),
                  WardStatTile(
                    label: 'Signups 30d',
                    value: '${current.signups30d}',
                  ),
                  WardStatTile(
                    label: 'PRO active',
                    value: '${current.proActive}',
                  ),
                  WardStatTile(
                    label: 'Free users',
                    value: '${current.freeUsers}',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sectionGap),
        _TrendCard(
          title: 'Total users (30d)',
          data: totalUsersSeries,
        ),
        const SizedBox(height: AppSpacing.sectionGap),
        _TrendCard(
          title: 'Signups per day (30d)',
          data: signupsSeries,
        ),
      ],
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.title, required this.data});

  final String title;
  final List<double> data;

  @override
  Widget build(BuildContext context) {
    return WardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WardEyebrow(title),
          const SizedBox(height: AppSpacing.stackM),
          if (data.length < 2)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Not enough history yet — one point accumulates per day.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: WardSpark(data: data, width: 260, height: 48),
            ),
        ],
      ),
    );
  }
}
