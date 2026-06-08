import 'dart:async';

import 'package:flutter/material.dart';
import 'package:icanbefitter/core/constants/fitness_goals.dart';
import '../../../../core/services/error_telemetry.dart';
import '../../../../core/theme/colors.dart';
import '../../models/tool_intent.dart';
import '../../services/regenerate_plan_planner.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Diff preview for a `regenerate_plan_block` intent (Phase D.3).
///
/// Computes the regenerated plan in [initState] (calls
/// [RegeneratePlanPlanner.plan] which invokes the existing
/// [PlanGenerator]), then caches both the display rows and the raw
/// schedule maps on [RegeneratePlanPlanner.instance] keyed by `intent.id`
/// so the dispatcher can write them on confirm without recomputing.
///
/// Renders the FIRST week in detail (workout name + exercise rows) and
/// shows a "+ N more workouts across weeks 2-N" footer for the rest. A
/// full N-week breakdown would overwhelm the bottom sheet.
class RegeneratePlanDiff extends StatefulWidget {
  final ToolIntent intent;
  const RegeneratePlanDiff({super.key, required this.intent});

  @override
  State<RegeneratePlanDiff> createState() => _RegeneratePlanDiffState();
}

class _RegeneratePlanDiffState extends State<RegeneratePlanDiff> {
  RegeneratePlanResult? _plan;
  String? _error;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  Future<void> _compute() async {
    try {
      final p = widget.intent.payload;
      final result = await RegeneratePlanPlanner.instance.plan(
        weeks: (p['weeks'] as num).toInt(),
        goal: p['goal'] as String?,
        daysPerWeek: (p['days_per_week'] as num?)?.toInt(),
        equipment: p['equipment'] as String?,
        startDate: p['start_date'] as String?,
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
      unawaited(ErrorTelemetry.logEvent(
          'diff_preview_regenerate_plan_load_failed',
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
          'Could not regenerate plan: $_error',
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

    final plan = _plan!;
    final replaceCount = plan.firstWeek.where((d) => d.replacing).length;
    final skipCount = plan.firstWeek.where((d) => d.willSkip).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header summary card — gold-tinted to signal a major change.
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
                '${plan.totalWeeks}-week plan',
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w800, color: AppColors.proGold),
              ),
              const SizedBox(height: 4),
              Text(
                '${_humanGoal(plan.resolvedGoal)} \u2022 '
                '${plan.resolvedDaysPerWeek} days/week \u2022 '
                '${_humanEquipment(plan.resolvedEquipment)}',
                style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),

        // First week eyebrow
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            'WEEK 1  \u00b7  $replaceCount replace \u00b7 $skipCount skip',
            style: AppTypography.body.copyWith(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textSecondary, letterSpacing: 0.5),
          ),
        ),

        ...plan.firstWeek.map(_buildDayCard),

        if (plan.additionalDaysCount > 0) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '+ ${plan.additionalDaysCount} more workouts across '
              'weeks 2-${plan.totalWeeks}',
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
      default:
        // 'recompose' + any future goal token resolves via FitnessGoals.
        return FitnessGoals.isKnown(raw) ? FitnessGoals.label(raw) : raw;
    }
  }

  String _humanEquipment(String raw) {
    switch (raw) {
      case 'bodyweight':
        return 'Bodyweight';
      case 'home_dumbbells':
        return 'Home dumbbells';
      case 'basic_gym':
        return 'Basic gym';
      case 'full_gym':
        return 'Full gym';
      default:
        return raw;
    }
  }
}
