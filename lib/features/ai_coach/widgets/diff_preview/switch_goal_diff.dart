import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../core/services/error_telemetry.dart';
import '../../../../core/services/hive_service.dart';
import '../../../../core/theme/colors.dart';
import '../../models/tool_intent.dart';
import '../../services/regenerate_plan_planner.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Diff preview for a `switch_goal` intent (Phase D.5).
///
/// Two-part operation:
///   1. PERMANENT profile update — `userBox['profile']['primary_goal']` is
///      overwritten to the new goal (with audit fields).
///   2. Plan regeneration — reuses [RegeneratePlanPlanner] with `goal`
///      forced to the new value so the upcoming weeks line up with the
///      changed objective.
///
/// Renders a gold goal-change banner (old \u2192 new) followed by the
/// regenerated first-week details (workout names + exercise rows). Weeks
/// 2..N are summarised in a footer row to keep the bottom sheet readable.
class SwitchGoalDiff extends StatefulWidget {
  final ToolIntent intent;
  const SwitchGoalDiff({super.key, required this.intent});

  @override
  State<SwitchGoalDiff> createState() => _SwitchGoalDiffState();
}

class _SwitchGoalDiffState extends State<SwitchGoalDiff> {
  RegeneratePlanResult? _plan;
  String? _error;
  String? _currentGoal;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  Future<void> _compute() async {
    try {
      // Read current goal from profile (label only — actual write happens
      // in the dispatcher on Confirm).
      final rawProfile = HiveService.instance.userBox.get('profile');
      _currentGoal = rawProfile is Map
          ? rawProfile['primary_goal']?.toString()
          : null;

      final p = widget.intent.payload;
      final newGoal = p['new_goal'] as String;
      final weeks = (p['weeks'] as num?)?.toInt() ?? 4;
      final startDate = p['start_date'] as String?;

      // Reuse the regenerate planner with goal forced to newGoal so the
      // diff and the cached raw schedules already reflect the new goal.
      final result = await RegeneratePlanPlanner.instance.plan(
        weeks: weeks,
        goal: newGoal,
        startDate: startDate,
      );
      RegeneratePlanPlanner.instance.cache(
        widget.intent.id,
        result.plan,
        result.rawSchedules,
      );
      if (mounted) setState(() => _plan = result.plan);
    } catch (e) {
      final errStr = e.toString();
      final clipped = errStr.length > 500 ? errStr.substring(0, 500) : errStr;
      unawaited(ErrorTelemetry.logEvent('diff_preview_switch_goal_load_failed',
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
          'Could not compute switch: $_error',
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

    final newGoal = widget.intent.payload['new_goal'] as String;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Gold goal-change banner — signals the destructive profile edit.
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.proGold.withValues(alpha: 0.15),
                AppColors.accent.withValues(alpha: 0.10),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.proGold.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GOAL CHANGE',
                style: AppTypography.body.copyWith(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.proGold, letterSpacing: 0.5),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _humanGoal(_currentGoal ?? 'unknown'),
                      style: AppTypography.body.copyWith(fontWeight: FontWeight.w600, color: AppColors.textSecondary, decoration: TextDecoration.lineThrough),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.east, color: AppColors.proGold, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _humanGoal(newGoal),
                      style: AppTypography.body.copyWith(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Profile will be updated and the next ${_plan!.totalWeeks} '
                'week${_plan!.totalWeeks == 1 ? '' : 's'} regenerated.',
                style: AppTypography.body.copyWith(fontSize: 11, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),

        // First week eyebrow
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            'NEW WEEK 1',
            style: AppTypography.body.copyWith(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textSecondary, letterSpacing: 0.5),
          ),
        ),

        ..._plan!.firstWeek.map(_buildDayCard),

        if (_plan!.additionalDaysCount > 0) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '+ ${_plan!.additionalDaysCount} more workouts across '
              'weeks 2-${_plan!.totalWeeks}',
              style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary, fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDayCard(RegeneratePlanDay day) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: day.willSkip
            ? AppColors.input.withValues(alpha: 0.5)
            : AppColors.input,
        borderRadius: BorderRadius.circular(8),
        border: day.willSkip
            ? Border.all(color: AppColors.textSecondary.withValues(alpha: 0.3))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _dayLabel(day.date),
                style: AppTypography.body.copyWith(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.accent, letterSpacing: 0.5),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  day.workoutName,
                  style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (day.willSkip)
                _badge('SKIP (DONE)', AppColors.textSecondary)
              else if (day.replacing)
                _badge('REPLACES', AppColors.proGold),
            ],
          ),
          if (day.willSkip)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Already completed — keeping the original workout.',
                style: AppTypography.body.copyWith(fontSize: 11, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
              ),
            )
          else ...[
            const SizedBox(height: 4),
            ...day.exercises.map((ex) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '\u2022 ${ex.name}  ${ex.sets} \u00d7 '
                    '${ex.repsOrDuration}',
                    style: AppTypography.body.copyWith(fontSize: 11, color: AppColors.textSecondary),
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: AppTypography.body.copyWith(fontSize: 10, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.5),
      ),
    );
  }

  String _dayLabel(String date) {
    final d = DateTime.parse(date);
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${names[d.weekday - 1]} ${d.month}/${d.day}';
  }

  String _humanGoal(String raw) {
    switch (raw) {
      case 'build_muscle':
        return 'Build muscle';
      case 'lose_fat':
        return 'Lose fat';
      case 'general_fitness':
        return 'General fitness';
      case 'strength':
        return 'Strength';
      case 'unknown':
        return 'Not set';
      default:
        return raw;
    }
  }
}
