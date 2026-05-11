import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/services/error_telemetry.dart';
import '../../../../core/theme/colors.dart';
import '../../models/tool_intent.dart';
import '../../services/hotel_workout_planner.dart';

/// Diff preview for a `generate_hotel_workout` intent.
///
/// Computes the bodyweight plan in [initState] (calls
/// [HotelWorkoutPlanner.plan] which invokes the existing
/// [PlanGenerator]), then caches both the display rows and the raw
/// schedule maps on [HotelWorkoutPlanner.instance] keyed by `intent.id`
/// so the dispatcher can write them on confirm without recomputing.
class HotelWorkoutDiff extends StatefulWidget {
  final ToolIntent intent;
  const HotelWorkoutDiff({super.key, required this.intent});

  @override
  State<HotelWorkoutDiff> createState() => _HotelWorkoutDiffState();
}

class _HotelWorkoutDiffState extends State<HotelWorkoutDiff> {
  List<HotelWorkoutDay>? _plan;
  String? _error;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  Future<void> _compute() async {
    try {
      final days = (widget.intent.payload['days'] as num).toInt();
      final startDate = widget.intent.payload['startDate'] as String?;

      final result = await HotelWorkoutPlanner.instance.plan(
        days: days,
        startDate: startDate,
      );

      HotelWorkoutPlanner.instance.cache(
        widget.intent.id,
        result.days,
        result.rawSchedules,
      );

      if (mounted) setState(() => _plan = result.days);
    } catch (e) {
      final errStr = e.toString();
      final clipped = errStr.length > 500 ? errStr.substring(0, 500) : errStr;
      unawaited(ErrorTelemetry.logEvent(
          'diff_preview_hotel_workout_load_failed',
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
          'Could not generate plan: $_error',
          style: GoogleFonts.getFont(
            'DM Sans',
            color: AppColors.red,
            fontSize: 13,
          ),
        ),
      );
    }
    if (_plan == null) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_plan!.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No days to plan.',
          style: GoogleFonts.getFont(
            'DM Sans',
            color: AppColors.textSecondary,
            fontSize: 13,
          ),
        ),
      );
    }

    final replaceCount = _plan!.where((d) => d.replacing).length;
    final skipCount = _plan!.where((d) => d.willSkip).length;
    final newCount = _plan!.length - replaceCount - skipCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '$newCount new \u00b7 $replaceCount replace \u00b7 $skipCount skip',
            style: GoogleFonts.getFont(
              'DM Sans',
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ..._plan!.map(_buildDayCard),
      ],
    );
  }

  Widget _buildDayCard(HotelWorkoutDay day) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: day.willSkip
            ? AppColors.input.withValues(alpha: 0.5)
            : AppColors.input,
        borderRadius: BorderRadius.circular(10),
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
                style: GoogleFonts.getFont(
                  'DM Sans',
                  color: AppColors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  day.workoutName,
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
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
          const SizedBox(height: 6),
          if (day.willSkip)
            Text(
              'Already completed — keeping the original workout.',
              style: GoogleFonts.getFont(
                'DM Sans',
                color: AppColors.textSecondary,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            ...day.exercises.map((ex) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '\u2022 ${ex.name}  ${ex.sets} \u00d7 ${ex.repsOrDuration}',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                )),
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
        style: GoogleFonts.getFont(
          'DM Sans',
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  String _dayLabel(String date) {
    final d = DateTime.parse(date);
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${names[d.weekday - 1]} ${d.month}/${d.day}';
  }
}
