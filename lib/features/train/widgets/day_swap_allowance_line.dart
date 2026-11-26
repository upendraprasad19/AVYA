// lib/features/train/widgets/day_swap_allowance_line.dart
//
// The Train week-list's allowance line + how-to hint (spec §6.1, §6.4).
// Renders nothing when the Train-UI kill switch is set — the hint text
// ("Hold a day and drag it onto another, or tap ⇅") would be misleading
// with both affordances hidden.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:icanbefitter/core/services/day_swap/day_swap_copy.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_rules.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

import '../providers/day_swap_provider.dart';
import 'day_swap_row_trailing.dart' show daySwapTrainUiEnabled;

class DaySwapAllowanceLine extends ConsumerWidget {
  const DaySwapAllowanceLine({super.key, required this.anyDateInWeek});

  /// Any IST date `YYYY-MM-DD` inside the week to show the allowance for.
  final String anyDateInWeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!daySwapTrainUiEnabled()) return const SizedBox.shrink();
    final weekStart = DaySwapRules.mondayOf(anyDateInWeek);
    final allowance = ref.watch(daySwapAllowanceProvider(weekStart));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          DaySwapCopy.allowanceLine(allowance, currentWeekStart: weekStart),
          style: AppTypography.bodySm.copyWith(color: AppColors.textDim),
        ),
        const SizedBox(height: 2),
        Text(
          DaySwapCopy.allowanceHint,
          style: AppTypography.monoXs
              .copyWith(color: AppColors.textMute, letterSpacing: 0.5),
        ),
      ],
    );
  }
}
