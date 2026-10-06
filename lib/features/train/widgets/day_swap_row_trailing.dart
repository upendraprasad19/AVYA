// lib/features/train/widgets/day_swap_row_trailing.dart
//
// The Train week-list row's day-swap trailing controls (spec §6.1): the
// "⇄ MOVED" tag and the ⇅ affordance that opens the shared picker
// (Task 24). Self-contained — reads its own DaySwapDayState via
// daySwapWeekProvider — so week_rows.dart (a `part of screen.dart` file
// with no imports of its own) only needs `screen.dart` to import THIS
// widget, not every day_swap/* type individually.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:icanbefitter/core/services/day_swap/day_swap_copy.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_result.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_rules.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

import '../providers/day_swap_provider.dart';
import 'swap_picker_sheet.dart';

/// True unless the Train-UI kill switch (spec §11
/// `disable_day_swap_train_ui`) is set. Shared by all three day-swap Train
/// widgets in this directory.
bool daySwapTrainUiEnabled() =>
    HiveService.instance.configBox.get('disable_day_swap_train_ui') != true;

class DaySwapRowTrailing extends ConsumerWidget {
  const DaySwapRowTrailing({super.key, required this.date});

  /// IST date `YYYY-MM-DD` of this row.
  final String date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekStart = DaySwapRules.mondayOf(date);
    final week = ref.watch(daySwapWeekProvider(weekStart));
    final state = week.firstWhere((d) => d.date == date,
        orElse: () => DaySwapDayState(
            date: date,
            row: null,
            lock: DaySwapRefusal.noRow,
            isMoved: false,
            title: ''));
    final enabled = daySwapTrainUiEnabled();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.isMoved) ...[
          WardChip(label: DaySwapCopy.movedTag, tone: WardChipTone.gold),
          const SizedBox(width: 8),
        ],
        if (enabled && state.movable)
          Semantics(
            label: DaySwapCopy.swapSemanticsLabel(date),
            button: true,
            child: IconButton(
              icon: const Icon(Icons.swap_vert,
                  size: 18, color: AppColors.accent),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => SwapPickerSheet.show(context,
                  sourceDate: date, origin: DaySwapOrigin.trainPicker),
            ),
          ),
      ],
    );
  }
}
