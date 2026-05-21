import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../core/services/error_telemetry.dart';
import '../../../../core/theme/colors.dart';
import '../../models/tool_intent.dart';
import '../../services/pause_plan_planner.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Diff preview for a `pause_plan` intent (Phase D.4).
///
/// Computes the per-day pause categorization in [initState] (calls
/// [PausePlanPlanner.plan]) and caches the result on
/// [PausePlanPlanner.instance] keyed by `intent.id`. The cache is
/// informational — the dispatcher reads the original payload and calls
/// [WorkoutScheduleService.pauseRange] directly (no schedule rebuild).
///
/// Renders a gold summary header + per-day rows showing:
///   - PAUSE badge for non-completed scheduled workouts
///   - SKIP (DONE) badge for completed workouts (history preserved)
///   - NO PLAN badge for unscheduled / rest days (no-op)
class PausePlanDiff extends StatefulWidget {
  final ToolIntent intent;
  const PausePlanDiff({super.key, required this.intent});

  @override
  State<PausePlanDiff> createState() => _PausePlanDiffState();
}

class _PausePlanDiffState extends State<PausePlanDiff> {
  PausePlanResult? _plan;
  String? _error;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  Future<void> _compute() async {
    try {
      final p = widget.intent.payload;
      final startDate = DateTime.parse(p['start_date'] as String);
      final days = (p['days'] as num).toInt();
      final result = await PausePlanPlanner.instance.plan(
        startDate: startDate,
        days: days,
      );
      PausePlanPlanner.instance.cache(widget.intent.id, result);
      if (mounted) setState(() => _plan = result);
    } catch (e) {
      final errStr = e.toString();
      final clipped = errStr.length > 500 ? errStr.substring(0, 500) : errStr;
      unawaited(ErrorTelemetry.logEvent('diff_preview_pause_plan_load_failed',
          message: clipped));
      if (mounted) setState(() => _error = errStr);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Could not compute pause: $_error',
          style: AppTypography.bodyM.copyWith(color: AppColors.red),
        ),
      );
    }
    if (_plan == null) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final reason = widget.intent.payload['reason'] as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary header — gold-tinted to signal a destructive change.
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.proGold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.proGold.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_plan!.willPauseCount} workout'
                '${_plan!.willPauseCount == 1 ? "" : "s"} will be paused',
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w800, color: AppColors.proGold),
              ),
              if (reason != null && reason.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Reason: $reason',
                  style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                ),
              ],
              if (_plan!.skipCompletedCount > 0 ||
                  _plan!.skipNoScheduleCount > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '${_plan!.skipCompletedCount} completed + '
                  '${_plan!.skipNoScheduleCount} unscheduled days '
                  'will be skipped',
                  style: AppTypography.body.copyWith(fontSize: 11, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
        ),
        // Day-by-day list
        ..._plan!.days.map(_buildDayRow),
      ],
    );
  }

  Widget _buildDayRow(PausePlanDay day) {
    Color color;
    String badge;
    Color badgeColor;
    if (day.willPause) {
      color = AppColors.proGold;
      badge = 'PAUSE';
      badgeColor = AppColors.proGold;
    } else if (day.skipReason == 'completed') {
      color = AppColors.green;
      badge = 'SKIP (DONE)';
      badgeColor = AppColors.green;
    } else {
      color = AppColors.textSecondary;
      badge = 'NO PLAN';
      badgeColor = AppColors.textSecondary;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Text(
            _dayLabel(day.date),
            style: AppTypography.body.copyWith(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.accent),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              day.workoutName ?? '\u2014 No workout scheduled',
              style: AppTypography.bodySm.copyWith(color: AppColors.textPrimary),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              badge,
              style: AppTypography.body.copyWith(fontSize: 10, fontWeight: FontWeight.w800, color: badgeColor),
            ),
          ),
        ],
      ),
    );
  }

  String _dayLabel(String date) {
    final d = DateTime.parse(date);
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${names[d.weekday - 1]} ${d.day}';
  }
}
