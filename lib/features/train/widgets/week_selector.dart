import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';

/// Horizontal scrollable week tab bar — matches the handoff
/// (`design_handoff_wardroom/src/screens/train.jsx` lines 50–62).
///
/// Short "W1 / W2 / W3 / W4" format (not "WK 01"). Selected: `accent`
/// bg + `bgDeep` text. Unselected: transparent + `line2` border +
/// `textDim` text. Sharp 2-px corners. Auto-centres on the selected
/// week. A date range caption below the letter label appears only on
/// selected weeks to conserve vertical space.
class WeekSelector extends StatefulWidget {
  final int totalWeeks;
  final int selectedWeek; // 1-indexed
  final ValueChanged<int> onSelect;

  const WeekSelector({
    super.key,
    required this.totalWeeks,
    required this.selectedWeek,
    required this.onSelect,
  });

  @override
  State<WeekSelector> createState() => _WeekSelectorState();
}

class _WeekSelectorState extends State<WeekSelector> {
  static const double _tabSpacing = 4;

  @override
  Widget build(BuildContext context) {
    final planStart = WorkoutScheduleService.instance.getPlanStartDate();

    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
        child: Row(
          children: List.generate(widget.totalWeeks, (index) {
            final week = index + 1;
            final isSelected = week == widget.selectedWeek;

            final label = 'W$week';
            String? sub;
            if (planStart != null && isSelected) {
              final weekStart = planStart.add(Duration(days: index * 7));
              final weekEnd = weekStart.add(const Duration(days: 6));
              sub = (weekStart.month == weekEnd.month)
                  ? '${_formatShort(weekStart)}–${weekEnd.day}'
                  : '${_formatShort(weekStart)}–${_formatShort(weekEnd)}';
            }

            final fg = isSelected ? AppColors.bgDeep : AppColors.textDim;
            final bg = isSelected ? AppColors.accent : AppColors.card;
            final border = isSelected ? AppColors.accent : AppColors.line2;

            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                    left: index == 0 ? 0 : _tabSpacing / 2,
                    right: index == widget.totalWeeks - 1 ? 0 : _tabSpacing / 2),
                child: GestureDetector(
                  onTap: () => widget.onSelect(week),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(AppRadius.sharp),
                      border: Border.all(color: border),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: AppTypography.monoXs.copyWith(
                              fontSize: 10,
                              color: fg,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                              height: 1.1,
                            ),
                          ),
                          if (sub != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              sub.toUpperCase(),
                              style: AppTypography.monoXs.copyWith(
                                color: fg.withValues(alpha: 0.85),
                                fontSize: 7,
                                letterSpacing: 1,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatShort(DateTime d) {
    return '${_months[d.month - 1]} ${d.day}';
  }
}
