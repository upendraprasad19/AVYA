import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../core/services/error_telemetry.dart';
import '../../../../core/theme/colors.dart';
import '../../models/tool_intent.dart';
import '../../services/schedule_template_planner.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Diff preview for a `schedule_template` intent (Phase D.7).
///
/// Computes the per-date assignment in [initState] (calls
/// [ScheduleTemplatePlanner.plan]), then caches both the display rows AND
/// the resolved (date, templateId) pairs the dispatcher needs to perform
/// the writes — atomic via the planner's record-return contract.
///
/// Renders a gold header card with template name + group day count + how
/// many of N dates will be scheduled, followed by a per-date list. Each
/// row shows the weekday + day name + REPLACES / ASSIGN / SKIP (DONE)
/// badge and the existing workout name when one is being displaced.
class ScheduleTemplateDiff extends StatefulWidget {
  final ToolIntent intent;
  const ScheduleTemplateDiff({super.key, required this.intent});

  @override
  State<ScheduleTemplateDiff> createState() => _ScheduleTemplateDiffState();
}

class _ScheduleTemplateDiffState extends State<ScheduleTemplateDiff> {
  ScheduleTemplateResult? _plan;
  String? _error;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  Future<void> _compute() async {
    try {
      final p = widget.intent.payload;
      final templateId = p['template_id'] as String;
      final dates = (p['dates'] as List).cast<String>();

      final result = await ScheduleTemplatePlanner.instance.plan(
        templateId: templateId,
        dates: dates,
      );

      ScheduleTemplatePlanner.instance.cache(
        widget.intent.id,
        result.plan,
        result.assignments,
      );

      if (mounted) setState(() => _plan = result.plan);
    } catch (e) {
      final errStr = e.toString();
      final clipped = errStr.length > 500 ? errStr.substring(0, 500) : errStr;
      unawaited(ErrorTelemetry.logEvent(
          'diff_preview_schedule_template_load_failed',
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
          'Could not compute schedule: $_error',
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

    final p = _plan!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header summary card.
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
                p.groupName,
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                '${p.totalDaysInGroup}-day template \u2022 '
                '${p.willScheduleCount} of ${p.assignments.length} dates will be scheduled',
                style: AppTypography.body.copyWith(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.proGold),
              ),
              if (p.skipCompletedCount > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '${p.skipCompletedCount} completed day${p.skipCompletedCount == 1 ? '' : 's'} skipped',
                  style: AppTypography.body.copyWith(fontSize: 11, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
        ),
        // Per-date assignment rows.
        ...p.assignments.map(_buildAssignmentRow),
      ],
    );
  }

  Widget _buildAssignmentRow(ScheduleTemplateAssignment a) {
    Color color;
    String badge;
    if (a.willSkip) {
      color = AppColors.textSecondary;
      badge = 'SKIP (DONE)';
    } else if (a.willReplace) {
      color = AppColors.proGold;
      badge = 'REPLACES';
    } else {
      color = AppColors.green;
      badge = 'ASSIGN';
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              _dayLabel(a.date),
              style: AppTypography.body.copyWith(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.accent),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.dayName,
                  style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                if (a.currentWorkoutName != null && a.willReplace)
                  Text(
                    'was: ${a.currentWorkoutName}',
                    style: AppTypography.body.copyWith(fontSize: 10, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                  )
                else if (a.currentWorkoutName != null && a.willSkip)
                  Text(
                    'completed: ${a.currentWorkoutName}',
                    style: AppTypography.body.copyWith(fontSize: 10, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              badge,
              style: AppTypography.body.copyWith(fontSize: 10, fontWeight: FontWeight.w800, color: color),
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
