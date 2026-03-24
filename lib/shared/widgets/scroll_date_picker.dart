import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';

/// A compact scroll-wheel date picker with three side-by-side columns:
/// [Day] [Month] [Year] — all in one row.
///
/// Returns the selected [DateTime] via [onDateChanged].
class ScrollDatePicker extends StatefulWidget {
  final DateTime? initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onDateChanged;

  const ScrollDatePicker({
    super.key,
    this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.onDateChanged,
  });

  @override
  State<ScrollDatePicker> createState() => _ScrollDatePickerState();
}

class _ScrollDatePickerState extends State<ScrollDatePicker> {
  late FixedExtentScrollController _dayController;
  late FixedExtentScrollController _monthController;
  late FixedExtentScrollController _yearController;

  late int _selectedDay;
  late int _selectedMonth; // 1-12
  late int _selectedYear;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  void initState() {
    super.initState();
    final init = widget.initialDate ?? DateTime(1998, 1, 1);
    _selectedDay = init.day;
    _selectedMonth = init.month;
    _selectedYear = init.year;

    _dayController = FixedExtentScrollController(initialItem: _selectedDay - 1);
    _monthController = FixedExtentScrollController(initialItem: _selectedMonth - 1);
    _yearController = FixedExtentScrollController(initialItem: _selectedYear - widget.firstDate.year);
  }

  @override
  void dispose() {
    _dayController.dispose();
    _monthController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  int _daysInMonth(int month, int year) {
    return DateTime(year, month + 1, 0).day;
  }

  void _onChanged() {
    final maxDay = _daysInMonth(_selectedMonth, _selectedYear);
    if (_selectedDay > maxDay) {
      _selectedDay = maxDay;
      _dayController.jumpToItem(_selectedDay - 1);
    }
    final date = DateTime(_selectedYear, _selectedMonth, _selectedDay);
    widget.onDateChanged(date);
  }

  @override
  Widget build(BuildContext context) {
    final firstYear = widget.firstDate.year;
    final lastYear = widget.lastDate.year;
    final yearCount = lastYear - firstYear + 1;
    final maxDay = _daysInMonth(_selectedMonth, _selectedYear);

    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Stack(
        children: [
          // Selection highlight band
          Center(
            child: Container(
              height: 38,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.25),
                ),
              ),
            ),
          ),
          // Wheels
          Row(
            children: [
              // Day wheel
              Expanded(
                flex: 2,
                child: ListWheelScrollView.useDelegate(
                  controller: _dayController,
                  itemExtent: 38,
                  physics: const FixedExtentScrollPhysics(),
                  diameterRatio: 1.5,
                  perspective: 0.003,
                  onSelectedItemChanged: (index) {
                    setState(() => _selectedDay = index + 1);
                    _onChanged();
                  },
                  childDelegate: ListWheelChildBuilderDelegate(
                    childCount: maxDay,
                    builder: (context, index) {
                      final day = index + 1;
                      final isSelected = day == _selectedDay;
                      return Center(
                        child: Text(
                          day.toString().padLeft(2, '0'),
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: isSelected ? 18 : 14,
                            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w500,
                            color: isSelected
                                ? AppColors.accent
                                : AppColors.textSecondary,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              // Month wheel
              Expanded(
                flex: 3,
                child: ListWheelScrollView.useDelegate(
                  controller: _monthController,
                  itemExtent: 38,
                  physics: const FixedExtentScrollPhysics(),
                  diameterRatio: 1.5,
                  perspective: 0.003,
                  onSelectedItemChanged: (index) {
                    setState(() => _selectedMonth = index + 1);
                    _onChanged();
                  },
                  childDelegate: ListWheelChildBuilderDelegate(
                    childCount: 12,
                    builder: (context, index) {
                      final isSelected = (index + 1) == _selectedMonth;
                      return Center(
                        child: Text(
                          _months[index],
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: isSelected ? 18 : 14,
                            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w500,
                            color: isSelected
                                ? AppColors.accent
                                : AppColors.textSecondary,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              // Year wheel
              Expanded(
                flex: 3,
                child: ListWheelScrollView.useDelegate(
                  controller: _yearController,
                  itemExtent: 38,
                  physics: const FixedExtentScrollPhysics(),
                  diameterRatio: 1.5,
                  perspective: 0.003,
                  onSelectedItemChanged: (index) {
                    setState(() => _selectedYear = firstYear + index);
                    _onChanged();
                  },
                  childDelegate: ListWheelChildBuilderDelegate(
                    childCount: yearCount,
                    builder: (context, index) {
                      final year = firstYear + index;
                      final isSelected = year == _selectedYear;
                      return Center(
                        child: Text(
                          year.toString(),
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: isSelected ? 18 : 14,
                            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w500,
                            color: isSelected
                                ? AppColors.accent
                                : AppColors.textSecondary,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          // Top/bottom fade overlays
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 40,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.input,
                      AppColors.input.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 40,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      AppColors.input,
                      AppColors.input.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
