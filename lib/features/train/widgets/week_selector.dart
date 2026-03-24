import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';

/// Horizontal row of week tab buttons showing "WEEK 1 · Mar 24–30" format.
/// Active tab: cyan bg, black text. Inactive: dark bg, gray border.
class WeekSelector extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final planStart = WorkoutScheduleService.instance.getPlanStartDate();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: List.generate(totalWeeks, (index) {
          final week = index + 1;
          final isSelected = week == selectedWeek;

          String label;
          if (planStart != null) {
            final weekStart = planStart.add(Duration(days: index * 7));
            final weekEnd = weekStart.add(const Duration(days: 6));
            final startStr = _formatShort(weekStart);
            final endStr = _formatShort(weekEnd);
            label = 'W$week\n$startStr–$endStr';
          } else {
            label = 'WEEK $week';
          }

          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(week),
              child: Container(
                margin: EdgeInsets.only(
                  left: index == 0 ? 0 : 3,
                  right: index == totalWeeks - 1 ? 0 : 3,
                ),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.accent
                      : const Color(0xFF0e1219),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.accent
                        : const Color(0xFF1c2535),
                  ),
                ),
                child: Center(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color:
                          isSelected ? Colors.black : AppColors.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
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
