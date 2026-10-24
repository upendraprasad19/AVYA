import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/admin/models/admin_dashboard_data.dart';
import 'package:icanbefitter/shared/widgets/empty_state.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Maps an `alerts.severity` value to a chip tone. The live vocabulary is
/// `info` / `warn` / `critical` (migration 076 CHECK constraint) — NOT
/// `warning` / `high` / `medium` (that's the unrelated InsightSeverity enum,
/// B-pass Finding 2). `warn` is the value every alert cron actually writes, so
/// it MUST map to the warn tone or active warnings render as neutral. The
/// extra aliases are defensive against either vocabulary reaching this widget.
WardChipTone _severityTone(String severity) {
  switch (severity.toLowerCase()) {
    case 'critical':
    case 'high':
      return WardChipTone.bad;
    case 'warn':
    case 'warning':
    case 'medium':
      return WardChipTone.warn;
    default:
      return WardChipTone.neutral;
  }
}

class OpsHealthTab extends StatelessWidget {
  const OpsHealthTab({super.key, required this.data});

  final AdminDashboardData data;

  @override
  Widget build(BuildContext context) {
    final current = data.current;
    final chronological = data.trend.reversed.toList();
    final clientErrorsSeries =
        chronological.map((p) => p.clientErrorsToday.toDouble()).toList();
    final openAlertsSeries =
        chronological.map((p) => p.openAlertsCount.toDouble()).toList();
    final cronFailuresSeries =
        chronological.map((p) => p.cronFailures24h.toDouble()).toList();
    final dateFormat = DateFormat('d MMM, HH:mm');

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      children: [
        WardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const WardEyebrow('OPS HEALTH TODAY'),
              const SizedBox(height: AppSpacing.stackS),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppSpacing.gridGap,
                crossAxisSpacing: AppSpacing.gridGap,
                childAspectRatio: 1.4,
                children: [
                  // LIVE `current.*` (Hermes L1-F1) — not the stale snapshot.
                  // Open-alerts uses the uncapped live count, NOT the 20-capped
                  // list length below (Hermes L1-F3).
                  WardStatTile(
                    label: 'Errors today',
                    value: '${current.clientErrorsToday}',
                  ),
                  WardStatTile(
                    label: 'Errors 7d',
                    value: '${current.clientErrors7d}',
                  ),
                  WardStatTile(
                    label: 'Open alerts',
                    value: '${current.openAlertsCount}',
                    accent: current.openAlertsCount > 0,
                  ),
                  WardStatTile(
                    label: 'Cron failures',
                    value: '${current.cronFailures24h}',
                    unit: '24h',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sectionGap),
        WardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WardEyebrow(
                'OPEN ALERTS',
                // True (uncapped) count, matching the stat tile; the feed
                // below shows the most recent (up to 20).
                trailing: WardChip(
                  label: '${current.openAlertsCount}',
                  tone: current.openAlertsCount == 0
                      ? WardChipTone.ok
                      : WardChipTone.warn,
                ),
              ),
              const SizedBox(height: AppSpacing.stackS),
              if (current.openAlertsCount > data.openAlerts.length)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Showing latest ${data.openAlerts.length} of ${current.openAlertsCount}.',
                    style: AppTypography.bodySm.copyWith(color: AppColors.textMute),
                  ),
                ),
              if (data.openAlerts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: EmptyState(
                    icon: Icons.check_circle_outline,
                    title: 'No open alerts',
                    subtitle: 'All clear.',
                  ),
                )
              else
                ...data.openAlerts.map(
                  (alert) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            WardChip(
                              label: alert.severity,
                              tone: _severityTone(alert.severity),
                            ),
                            Text(
                              dateFormat.format(alert.detectedAt),
                              style: AppTypography.bodySm
                                  .copyWith(color: AppColors.textMute),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(alert.summary, style: AppTypography.bodyM),
                        Text(
                          alert.source,
                          style: AppTypography.bodySm
                              .copyWith(color: AppColors.textMute),
                        ),
                        if (alert.suggestedAction != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            alert.suggestedAction!,
                            style: AppTypography.bodySm
                                .copyWith(color: AppColors.accent),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sectionGap),
        _TrendCard(title: 'Client errors / day (30d)', data: clientErrorsSeries),
        const SizedBox(height: AppSpacing.sectionGap),
        _TrendCard(title: 'Open alerts (30d)', data: openAlertsSeries),
        const SizedBox(height: AppSpacing.sectionGap),
        _TrendCard(title: 'Cron failures, 24h window (30d)', data: cronFailuresSeries),
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
