// lib/features/train/widgets/day_swap_drag_wrapper.dart
//
// Long-press drag + drop-target chrome for a Train week-list row — the
// APPROVED mockup visuals (spec §6.1, Approach A), implemented exactly:
//   - long-press lifts the row; the lifted slot shows "moving…"
//   - every valid target gets a 10% gold wash + a dashed gold outline
//   - the hovered target's outline tightens to a near-solid dash and shows
//     "DROP TO SWAP"
//   - a locked row fades to 32% opacity with a lock glyph while a drag is
//     in progress
//   - a drop opens the Task 24 confirm sheet
//
// Self-contained — reads its own DaySwapDayState via daySwapWeekProvider —
// so week_rows.dart only wraps its already-built row `child` in this widget
// and never imports a day_swap/* type itself.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:icanbefitter/core/services/day_swap/day_swap_copy.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_result.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_rules.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

import '../providers/day_swap_provider.dart';
import 'day_swap_row_trailing.dart' show daySwapTrainUiEnabled;
import 'swap_confirm_sheet.dart';

/// The IST date currently lifted for a Train-tab drag, shared by every
/// [DaySwapDragWrapper] in the tree (every instance imports this same file,
/// so they all reference the same provider object without it needing to be
/// public). `Notifier`, not `.autoDispose`: the `StateProvider` this
/// replaces (repo's first, and only, `flutter_riverpod/legacy.dart` use —
/// task-25-review.md finding 4) was also never disposed, so this keeps the
/// exact same lifetime semantics as a pure API-migration — no behavior
/// change bundled into a refactor-only fix. `autoDispose` was considered (it
/// would additionally clear stale state if every `DaySwapDragWrapper` in the
/// tree unmounted mid-drag) but rejected: the Train tab's rows mount/unmount
/// as a set inside the app's persisted bottom-nav `IndexedStack`, so that
/// scenario is rare, and task-25-fix1's F5 standing test already proves the
/// state resets to null on every drag-termination path the widget wires up
/// — the actual coverage gap task-25-review.md finding 5 flagged.
class _LiftedDateNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// Lift [date] — called from `onDragStarted`.
  void lift(String date) => state = date;

  /// Clear the lifted date — called from every drag-termination path
  /// (`onDragEnd`, `onDraggableCanceled`, `onAcceptWithDetails`).
  void clear() => state = null;
}

final _liftedDateProvider =
    NotifierProvider<_LiftedDateNotifier, String?>(_LiftedDateNotifier.new);

class DaySwapDragWrapper extends ConsumerWidget {
  const DaySwapDragWrapper(
      {super.key, required this.date, required this.child});

  /// IST date `YYYY-MM-DD` of this row.
  final String date;

  /// The row's own already-built content (day label, title, EX count,
  /// status indicator, [DaySwapRowTrailing]) — this widget wraps it, never
  /// rebuilds it.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!daySwapTrainUiEnabled()) return child;

    final weekStart = DaySwapRules.mondayOf(date);
    final week = ref.watch(daySwapWeekProvider(weekStart));
    final statesByDate = {for (final d in week) d.date: d};
    final state = statesByDate[date];
    final movable = state?.movable ?? false;
    final lifted = ref.watch(_liftedDateProvider);
    final isDragging = lifted != null;
    final isLifted = lifted == date;
    final isValidTarget = movable && isDragging && lifted != date;

    Widget chrome(Widget inner, {required bool hovered}) {
      if (isValidTarget) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: hovered ? 0.16 : 0.10),
          ),
          child: CustomPaint(
            foregroundPainter: WardDashedBorderPainter(
              color: AppColors.accent,
              strokeWidth: hovered ? 2 : 1,
              dashLength: hovered ? 6 : 4,
              gapLength: hovered ? 1.5 : 3,
              radius: AppRadius.sharp,
            ),
            child: Stack(
              children: [
                inner,
                if (hovered)
                  const Positioned(
                    right: 14,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: WardChip(
                          label: DaySwapCopy.dropToSwap,
                          tone: WardChipTone.gold),
                    ),
                  ),
              ],
            ),
          ),
        );
      }
      if (isDragging && !movable && !isLifted) {
        // Locked rows fade to 32% with a lock glyph while a drag is active.
        return Opacity(
          opacity: 0.32,
          child: Stack(
            alignment: Alignment.centerRight,
            children: [
              inner,
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.lock, size: 12, color: AppColors.textMute),
              ),
            ],
          ),
        );
      }
      return inner;
    }

    final target = DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          isValidTarget && details.data != date,
      onAcceptWithDetails: (details) {
        ref.read(_liftedDateProvider.notifier).clear();
        final from = statesByDate[details.data];
        final to = statesByDate[date];
        if (from == null || to == null) return;
        SwapConfirmSheet.show(context,
            dayA: from, dayB: to, origin: DaySwapOrigin.trainDrag);
      },
      builder: (context, candidates, rejects) =>
          chrome(child, hovered: candidates.isNotEmpty),
    );

    if (!movable) return target;

    return LongPressDraggable<String>(
      data: date,
      onDragStarted: () => ref.read(_liftedDateProvider.notifier).lift(date),
      onDragEnd: (_) => ref.read(_liftedDateProvider.notifier).clear(),
      onDraggableCanceled: (_, __) =>
          ref.read(_liftedDateProvider.notifier).clear(),
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: MediaQuery.of(context).size.width -
              AppSpacing.screenPadding * 2,
          child: child,
        ),
      ),
      childWhenDragging: Container(
        height: 48,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Text(DaySwapCopy.movingLabel,
            style: AppTypography.monoXs
                .copyWith(color: AppColors.accent, letterSpacing: 1)),
      ),
      child: target,
    );
  }
}
