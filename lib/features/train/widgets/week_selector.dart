import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';

/// Horizontal scrollable week tab bar.
///
/// Shows "WK 01 · MAR 24" format per week in Wardroom voice. Gold chip when
/// selected, neutral otherwise. Scrolls without limit — auto-centres the
/// selected week on first build.
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
  static const double _tabWidth = 92;
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
      height: 44,
      child: ListView.separated(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
        itemCount: widget.totalWeeks,
        separatorBuilder: (_, index) => const SizedBox(width: _tabSpacing),
        itemBuilder: (context, index) {
          final week = index + 1;
          final isSelected = week == widget.selectedWeek;

          String label;
          String? sub;
          if (planStart != null) {
            final weekStart = planStart.add(Duration(days: index * 7));
            final weekEnd = weekStart.add(const Duration(days: 6));
            label = 'WK ${week.toString().padLeft(2, '0')}';
            sub = '${_formatShort(weekStart)}–${_formatShort(weekEnd)}';
          } else {
            label = 'WK ${week.toString().padLeft(2, '0')}';
          }

          final fg = isSelected ? AppColors.bgDeep : AppColors.textDim;
          final bg = isSelected ? AppColors.accent : Colors.transparent;
          final border = isSelected ? AppColors.accent : AppColors.line2;

          return GestureDetector(
            onTap: () => widget.onSelect(week),
            child: Container(
              width: _tabWidth,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: border),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: AppTypography.monoXs.copyWith(
                        color: fg,
                        letterSpacing: 1.6,
                        height: 1.1,
                      ),
                    ),
                    if (sub != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        sub.toUpperCase(),
                        style: AppTypography.monoXs.copyWith(
                          color: fg.withValues(
                              alpha: isSelected ? 0.85 : 0.75),
                          fontSize: 8,
                          letterSpacing: 1.2,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ],
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
