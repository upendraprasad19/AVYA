import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';

/// Horizontal scrollable week tab bar.
///
/// Shows "W1 · Mar 24–30" format for each week. Scrollable so the user can
/// navigate to past/future weeks without limit. Auto-scrolls to the selected
/// week on first build.
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
  final ScrollController _scrollController = ScrollController();
  static const double _tabWidth = 88;
  static const double _tabSpacing = 6;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  @override
  void didUpdateWidget(covariant WeekSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedWeek != widget.selectedWeek) {
      _scrollToSelected();
    }
  }

  void _scrollToSelected() {
    if (!_scrollController.hasClients) return;
    final target = (widget.selectedWeek - 1) * (_tabWidth + _tabSpacing);
    final viewportWidth = _scrollController.position.viewportDimension;
    final offset = (target - viewportWidth / 2 + _tabWidth / 2)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(offset,
        duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final planStart = WorkoutScheduleService.instance.getPlanStartDate();

    return SizedBox(
      height: 42,
      child: ListView.separated(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: widget.totalWeeks,
        separatorBuilder: (_, __) => const SizedBox(width: _tabSpacing),
        itemBuilder: (context, index) {
          final week = index + 1;
          final isSelected = week == widget.selectedWeek;

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

          return GestureDetector(
            onTap: () => widget.onSelect(week),
            child: Container(
              width: _tabWidth,
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
          );
        },
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
