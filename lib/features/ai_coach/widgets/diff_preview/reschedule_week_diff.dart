import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/colors.dart';
import '../../models/tool_intent.dart';
import '../../services/reschedule_week_planner.dart';

/// Diff preview for a `reschedule_week` intent.
///
/// Computes the move plan in [initState] (Hive read of all 7 days of the
/// target week) and caches it on [RescheduleWeekPlanner.instance] keyed by
/// `intent.id` so the dispatcher can pick it up on confirm without
/// recomputing.
class RescheduleWeekDiff extends StatefulWidget {
  final ToolIntent intent;
  const RescheduleWeekDiff({super.key, required this.intent});

  @override
  State<RescheduleWeekDiff> createState() => _RescheduleWeekDiffState();
}

class _RescheduleWeekDiffState extends State<RescheduleWeekDiff> {
  List<RescheduleMove>? _moves;
  String? _error;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  Future<void> _compute() async {
    try {
      final daysAvail = (widget.intent.payload['daysAvailable'] as List)
          .cast<num>()
          .map((n) => n.toInt())
          .toList();
      final weekStart = widget.intent.payload['weekStart'] as String?;
      final moves = await RescheduleWeekPlanner.instance.plan(
        daysAvailable: daysAvail,
        weekStart: weekStart,
      );
      RescheduleWeekPlanner.instance.cache(widget.intent.id, moves);
      if (mounted) setState(() => _moves = moves);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Could not compute reshuffle: $_error',
          style: GoogleFonts.getFont(
            'DM Sans',
            color: AppColors.red,
            fontSize: 13,
          ),
        ),
      );
    }
    if (_moves == null) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_moves!.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No scheduled workouts in this week — nothing to move.',
          style: GoogleFonts.getFont(
            'DM Sans',
            color: AppColors.textSecondary,
            fontSize: 13,
          ),
        ),
      );
    }

    final keepCount =
        _moves!.where((m) => m.action == RescheduleAction.keep).length;
    final moveCount =
        _moves!.where((m) => m.action == RescheduleAction.move).length;
    final dropCount =
        _moves!.where((m) => m.action == RescheduleAction.drop).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '$keepCount keep \u00b7 $moveCount move \u00b7 $dropCount drop',
            style: GoogleFonts.getFont(
              'DM Sans',
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ..._moves!.map(_buildMoveRow),
      ],
    );
  }

  Widget _buildMoveRow(RescheduleMove m) {
    Color color;
    String label;
    IconData icon;
    String detail;
    switch (m.action) {
      case RescheduleAction.keep:
        color = AppColors.green;
        label = 'KEEP';
        icon = Icons.check_circle_outline;
        detail =
            '${m.workoutName} on ${_dayLabel(m.fromDate)}${m.completedStatus != null ? ' (${m.completedStatus})' : ''}';
        break;
      case RescheduleAction.move:
        color = AppColors.accent;
        label = 'MOVE';
        icon = Icons.east;
        detail =
            '${m.workoutName}: ${_dayLabel(m.fromDate)} \u2192 ${_dayLabel(m.toDate!)}';
        break;
      case RescheduleAction.drop:
        color = AppColors.red;
        label = 'DROP';
        icon = Icons.delete_outline;
        detail = '${m.workoutName} on ${_dayLabel(m.fromDate)}';
        break;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Container(
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
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              detail,
              style: GoogleFonts.getFont(
                'DM Sans',
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
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
