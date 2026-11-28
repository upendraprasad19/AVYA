// Shared pieces of the Nutrition History screen (plan
// docs/plans/nutrition-history.md 6.2): labels, status colours, the section
// card and the legend dot. Colour never stands alone: every status colour is
// shown with a legend entry.

import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

import '../../services/nutrition_history.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// `12 Nov` from a day key; the raw text when it does not parse.
String historyDayLabel(String dayKey) {
  final d = parseDayKey(dayKey);
  return d == null ? dayKey : '${d.day} ${_months[d.month - 1]}';
}

/// `Wed 12 Nov 2026`.
String historyLongDayLabel(String dayKey) {
  final d = parseDayKey(dayKey);
  if (d == null) return dayKey;
  return '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]} ${d.year}';
}

String metricLabel(NutritionMetric m) {
  switch (m) {
    case NutritionMetric.calories:
      return 'Calories';
    case NutritionMetric.protein:
      return 'Protein';
    case NutritionMetric.carbs:
      return 'Carbs';
    case NutritionMetric.fat:
      return 'Fat';
    case NutritionMetric.fiber:
      return 'Fibre';
    case NutritionMetric.water:
      return 'Water';
  }
}

String metricUnit(NutritionMetric m) {
  switch (m) {
    case NutritionMetric.calories:
      return 'kcal';
    case NutritionMetric.water:
      return 'ml';
    case NutritionMetric.protein:
    case NutritionMetric.carbs:
    case NutritionMetric.fat:
    case NutritionMetric.fiber:
      return 'g';
  }
}

/// `1,850 kcal`, `120 g`, `2,500 ml`.
String metricText(double value, NutritionMetric m) =>
    '${groupedInt(value.round())} ${metricUnit(m)}';

String groupedInt(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

Color metricColor(NutritionMetric m) {
  switch (m) {
    case NutritionMetric.calories:
      return AppColors.accent;
    case NutritionMetric.protein:
      return AppColors.warn;
    case NutritionMetric.carbs:
      return AppColors.ok;
    case NutritionMetric.fat:
      return AppColors.bad;
    case NutritionMetric.fiber:
      return AppColors.textDim;
    case NutritionMetric.water:
      return AppColors.info;
  }
}

Color statusColor(DayStatus s) {
  switch (s) {
    case DayStatus.onTarget:
      return AppColors.ok;
    case DayStatus.lowProtein:
      return AppColors.bad; // red (founder 2026-11-26); over stays amber
    case DayStatus.under:
      return AppColors.info;
    case DayStatus.over:
      return AppColors.warn;
    case DayStatus.logged:
      return AppColors.textDim;
    case DayStatus.partial:
    case DayStatus.inProgress:
      return AppColors.textMute;
    case DayStatus.notLogged:
      return AppColors.input;
  }
}

String statusLabel(DayStatus s) {
  switch (s) {
    case DayStatus.onTarget:
      return 'On target';
    case DayStatus.lowProtein:
      return 'Low protein';
    case DayStatus.under:
      return 'Under';
    case DayStatus.over:
      return 'Over';
    case DayStatus.logged:
      return 'Logged';
    case DayStatus.partial:
      return 'Partial';
    case DayStatus.inProgress:
      return 'In progress';
    case DayStatus.notLogged:
      return 'Not logged';
  }
}

/// A titled card. [note] is a small line under the title.
class HistorySection extends StatelessWidget {
  const HistorySection({
    super.key,
    required this.title,
    required this.child,
    this.note,
  });

  final String title;
  final String? note;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return WardCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.mono
                .copyWith(color: AppColors.textMute, letterSpacing: 2),
          ),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(note!,
                style: AppTypography.bodySm.copyWith(color: AppColors.textMute)),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class HistoryLegend extends StatelessWidget {
  const HistoryLegend(this.entries, {super.key});

  /// (colour, label) pairs.
  final List<(Color, String)> entries;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        for (final e in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: e.$1,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(e.$2,
                    style: AppTypography.bodySm
                        .copyWith(color: AppColors.textDim)),
              ),
            ],
          ),
      ],
    );
  }
}

/// A selectable pill (range and metric chips).
class HistoryChip extends StatelessWidget {
  const HistoryChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentSoft : AppColors.input,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: selected ? AppColors.accent : AppColors.border),
          ),
          child: Text(
            label,
            style: AppTypography.bodySm.copyWith(
              color: selected ? AppColors.accent : AppColors.textDim,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
