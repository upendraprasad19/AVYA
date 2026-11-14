// lib/features/train/widgets/swap_picker_sheet.dart
//
// Shared "Swap <day> with…" picker (spec 2026-09-26-day-swapper-design §6.3):
// opened by the Train ⇅ button (Task 25) and the Home long-press (Task 26).
// Picking a day and pressing the button IS the confirmation on this path —
// there is no second sheet. Calls ONLY the Task 12 controller/providers; the
// engine re-checks everything at press time (spec §5.1), so a lock reason
// shown here can go stale between open and press and the press will refuse.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:icanbefitter/core/services/day_swap/day_swap_allowance.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_copy.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_result.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_rules.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

import '../providers/day_swap_provider.dart';

class SwapPickerSheet extends ConsumerStatefulWidget {
  const SwapPickerSheet(
      {super.key, required this.sourceDate, required this.origin});

  final String sourceDate;
  final DaySwapOrigin origin;

  static Future<DaySwapResult?> show(
    BuildContext context, {
    required String sourceDate,
    required DaySwapOrigin origin,
  }) {
    return showModalBottomSheet<DaySwapResult?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          SwapPickerSheet(sourceDate: sourceDate, origin: origin),
    );
  }

  @override
  ConsumerState<SwapPickerSheet> createState() => _SwapPickerSheetState();
}

class _SwapPickerSheetState extends ConsumerState<SwapPickerSheet> {
  String? _target;
  bool _swapping = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final weekStart = DaySwapRules.mondayOf(widget.sourceDate);
    final isPro = ref.watch(subscriptionInfoProvider).isPro;
    final week = ref.watch(daySwapWeekProvider(weekStart));
    final allowance = ref.watch(daySwapAllowanceProvider(weekStart));
    final todayStr = istTodayStr();
    final source = week.firstWhere((d) => d.date == widget.sourceDate,
        orElse: () => DaySwapDayState(
            date: widget.sourceDate,
            row: null,
            lock: DaySwapRefusal.noRow,
            isMoved: false,
            title: ''));

    if (!isPro && allowance.spent) return DaySwapSpentSheet.forContext(context);

    return _Sheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _DragHandle(),
          const SizedBox(height: 14),
          Text(DaySwapCopy.pickerTitle(widget.sourceDate),
              style: AppTypography.h3.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(
            DaySwapCopy.pickerSubtitle(
                title: source.title, a: allowance, currentWeekStart: weekStart),
            style: AppTypography.bodySm.copyWith(color: AppColors.textDim),
          ),
          const SizedBox(height: 14),
          for (final d in week)
            if (d.date != widget.sourceDate && d.lock != DaySwapRefusal.noRow)
              _dayRow(d, todayStr: todayStr, weekStart: weekStart),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(_error!,
                textAlign: TextAlign.center,
                style: AppTypography.bodySm
                    .copyWith(color: AppColors.bad, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 8),
          if (_target != null)
            SizedBox(
              width: double.infinity,
              child: WardButton(
                label: DaySwapCopy.pickerButton(widget.sourceDate, _target!),
                onPressed: _swapping ? null : _onSwap,
              ),
            ),
          const SizedBox(height: 10),
          Text(
            DaySwapCopy.pickerFooter,
            textAlign: TextAlign.center,
            style: AppTypography.monoXs
                .copyWith(color: AppColors.textMute, letterSpacing: 1.2),
          ),
        ],
      ),
    );
  }

  Widget _dayRow(DaySwapDayState d,
      {required String todayStr, required String weekStart}) {
    final locked = d.lock != null;
    final selected = _target == d.date;
    final label = '${DaySwapCopy.dayShort(d.date)}'
        '${d.date == todayStr ? ' · ${DaySwapCopy.pickerTodayTag}' : ''}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Opacity(
        opacity: locked ? 0.5 : 1.0,
        child: GestureDetector(
          onTap: locked
              ? null
              : () => setState(() {
                    _target = d.date;
                    _error = null;
                  }),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AppColors.accentSoft : AppColors.bgRaise,
              borderRadius: BorderRadius.circular(AppRadius.sharp),
              border: Border.all(
                color: selected ? AppColors.accent : AppColors.line2,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: AppTypography.body.copyWith(
                              color: selected
                                  ? AppColors.accent
                                  : AppColors.textPrimary,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(d.title,
                          style: AppTypography.monoXs.copyWith(
                              color: AppColors.textMute, letterSpacing: 1.2)),
                    ],
                  ),
                ),
                if (locked && d.lock!.label != null)
                  WardChip(label: d.lock!.label!, tone: WardChipTone.neutral)
                else if (selected)
                  const Icon(Icons.swap_horiz_rounded,
                      color: AppColors.accent, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onSwap() async {
    final target = _target;
    if (target == null) return;
    final weekStart = DaySwapRules.mondayOf(widget.sourceDate);
    final week = ref.read(daySwapWeekProvider(weekStart));
    final before = <String, DaySwapDayState>{for (final d in week) d.date: d};
    setState(() {
      _swapping = true;
      _error = null;
    });
    final result = await ref.read(daySwapControllerProvider).swap(
        dateA: widget.sourceDate, dateB: target, origin: widget.origin);
    if (!mounted) return;
    if (result is DaySwapDone) {
      final subject = DaySwapCopy.toastSubject(
          before[widget.sourceDate] ?? before.values.first,
          before[target] ?? before.values.first);
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(result);
      messenger.showSnackBar(_toast(
        title: DaySwapCopy.toastTitle(widget.sourceDate, target),
        body: DaySwapCopy.toastBody(
            subject: subject,
            today: istTodayStr(),
            after: result.allowanceAfter,
            currentWeekStart: weekStart),
      ));
      return;
    }
    final isPro = ref.read(subscriptionInfoProvider).isPro;
    setState(() {
      _swapping = false;
      _error = DaySwapCopy.errorFor(result,
          isPro: isPro,
          limit: isPro ? DaySwapAllowance.proLimit : DaySwapAllowance.freeLimit);
    });
  }
}

/// The "no swaps left" full-screen state for a free user (spec §6.3/§6.4).
/// Shared by EVERY entry point: this picker (Train ⇅ + Home long-press) and
/// [SwapConfirmSheet] (Train drag) — the drag path showed a plain confirm
/// sheet to a spent free user until B-pass R2-F1.
class DaySwapSpentSheet extends StatelessWidget {
  const DaySwapSpentSheet({super.key, required this.onSeePro});

  /// "See PRO" closes the sheet and opens the one paywall (rule 7).
  factory DaySwapSpentSheet.forContext(BuildContext context) =>
      DaySwapSpentSheet(onSeePro: () {
        Navigator.of(context).pop();
        showPaywallSheet(context, feature: 'Day Swaps');
      });

  final VoidCallback onSeePro;

  @override
  Widget build(BuildContext context) {
    return _Sheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _DragHandle(),
          const SizedBox(height: 16),
          Text(DaySwapCopy.spentTitleFree,
              style: AppTypography.h3.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text(DaySwapCopy.spentBodyFree,
              textAlign: TextAlign.center,
              style: AppTypography.bodySm.copyWith(color: AppColors.textDim)),
          const SizedBox(height: 16),
          SizedBox(
              width: double.infinity,
              child: WardButton(label: DaySwapCopy.seePro, onPressed: onSeePro)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: WardButton(
              label: DaySwapCopy.close,
              variant: WardButtonVariant.ghost,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared bottom-sheet chrome for the picker and its spent state.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter, 12, AppSpacing.gutter, AppSpacing.gutter),
          child: child,
        ),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();
  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.line2,
          borderRadius: BorderRadius.circular(2),
        ),
      );
}

/// The post-swap toast, shared with [SwapConfirmSheet] (they carry identical
/// copy per spec §6.4 "After a swap").
SnackBar buildDaySwapToast({required String title, required String body}) =>
    SnackBar(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: AppTypography.body
                  .copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
          Text(body,
              style: AppTypography.bodySm.copyWith(color: AppColors.textDim)),
        ],
      ),
      backgroundColor: AppColors.card,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sharp)),
      duration: const Duration(seconds: 3),
    );

SnackBar _toast({required String title, required String body}) =>
    buildDaySwapToast(title: title, body: body);
