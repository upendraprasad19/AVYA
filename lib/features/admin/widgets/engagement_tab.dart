import 'package:flutter/material.dart';

import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/features/admin/models/admin_dashboard_data.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

class EngagementTab extends StatelessWidget {
  const EngagementTab({super.key, required this.data});

  final AdminDashboardData data;

  @override
  Widget build(BuildContext context) {
    final current = data.current;
    final chronological = data.trend.reversed.toList();
    final workoutsSeries =
        chronological.map((p) => p.workoutsLoggedToday.toDouble()).toList();
    final foodSeries =
        chronological.map((p) => p.foodLogsToday.toDouble()).toList();
    final aiSeries =
        chronological.map((p) => p.aiMessagesToday.toDouble()).toList();
    final streakSeries = chronological
        .map((p) => p.streakMaintainedCurrentWeek.toDouble())
        .toList();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      children: [
        WardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const WardEyebrow('ENGAGEMENT TODAY'),
              const SizedBox(height: AppSpacing.stackS),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppSpacing.gridGap,
                crossAxisSpacing: AppSpacing.gridGap,
                childAspectRatio: 1.4,
                children: [
                  // All LIVE `current.*` values (Hermes L1-F1) — not the
                  // up-to-24h-stale trend snapshot. activeLast7d is the
                  // 7-day-active-USERS (WAU) count, its own labeled tile.
                  WardStatTile(
                    label: 'Workouts today',
                    value: '${current.workoutsLoggedToday}',
                  ),
                  WardStatTile(
                    label: 'AI messages',
                    value: '${current.aiMessagesToday}',
                    accent: true,
                  ),
                  WardStatTile(
                    label: 'On-streak',
                    value: '${current.streakMaintainedCurrentWeek}',
                    unit: 'this wk',
                  ),
                  WardStatTile(
                    label: 'Active',
                    value: '${current.activeLast7d}',
                    unit: '7d users',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sectionGap),
        _TrendCard(title: 'Workouts logged / day (30d)', data: workoutsSeries),
        const SizedBox(height: AppSpacing.sectionGap),
        _TrendCard(title: 'Food logs / day (30d)', data: foodSeries),
        const SizedBox(height: AppSpacing.sectionGap),
        _TrendCard(title: 'AI coach messages / day (30d)', data: aiSeries),
        const SizedBox(height: AppSpacing.sectionGap),
        _TrendCard(title: 'Users on-streak this week (30d)', data: streakSeries),
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
