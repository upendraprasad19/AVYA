// lib/features/train/widgets/swap_confirm_sheet.dart
//
// The drag-path confirm sheet (spec §6.1, §6.4). Receives the two days'
// PRE-swap states from its caller (Task 25's drag-drop handler) rather than
// re-deriving them, so it stays a pure display + confirm surface.

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
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

import '../providers/day_swap_provider.dart';
import 'swap_picker_sheet.dart' show DaySwapSpentSheet, buildDaySwapToast;

class SwapConfirmSheet extends ConsumerStatefulWidget {
  const SwapConfirmSheet(
      {super.key, required this.dayA, required this.dayB, required this.origin});

  final DaySwapDayState dayA;
  final DaySwapDayState dayB;
  final DaySwapOrigin origin;

  static Future<DaySwapResult?> show(
    BuildContext context, {
    required DaySwapDayState dayA,
    required DaySwapDayState dayB,
    required DaySwapOrigin origin,
  }) {
    return showModalBottomSheet<DaySwapResult?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SwapConfirmSheet(dayA: dayA, dayB: dayB, origin: origin),
    );
  }

  @override
  ConsumerState<SwapConfirmSheet> createState() => _SwapConfirmSheetState();
}

class _SwapConfirmSheetState extends ConsumerState<SwapConfirmSheet> {
  bool _swapping = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final weekStart = DaySwapRules.mondayOf(widget.dayA.date);
    // Force a rebuild if a background server reply lands while this sheet
    // is open (spec §5.3 "the server count wins").
    final allowance = ref.watch(daySwapAllowanceProvider(weekStart));
    final isPro = ref.watch(subscriptionInfoProvider).isPro;
    // Same gate as SwapPickerSheet: a spent free user gets the upsell, not a
    // SWAP button that can only answer "spent" (B-pass R2-F1).
    if (!isPro && allowance.spent) return DaySwapSpentSheet.forContext(context);
    final preview = ref
        .read(daySwapControllerProvider)
        .preview(widget.dayA.date, widget.dayB.date);
    final earlyFirst = widget.dayA.date.compareTo(widget.dayB.date) <= 0;
    final early = earlyFirst ? widget.dayA : widget.dayB;
    final late = earlyFirst ? widget.dayB : widget.dayA;

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.line2, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 14),
              Text(DaySwapCopy.confirmEyebrow,
                  style: AppTypography.mono
                      .copyWith(color: AppColors.accent, letterSpacing: 3)),
              const SizedBox(height: 6),
              Text(DaySwapCopy.confirmTitle(widget.dayA.date, widget.dayB.date),
                  style: AppTypography.h3.copyWith(color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Text(DaySwapCopy.confirmBody,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySm.copyWith(color: AppColors.textDim)),
              const SizedBox(height: 14),
              _moveRow(DaySwapCopy.confirmMove(
                  from: early.date, title: early.title, to: late.date)),
              const SizedBox(height: 6),
              _moveRow(DaySwapCopy.confirmMove(
                  from: late.date, title: late.title, to: early.date)),
              const SizedBox(height: 12),
              Text(
                DaySwapCopy.confirmAllowance(preview.allowance,
                    currentWeekStart: weekStart),
                style: AppTypography.bodySm.copyWith(color: AppColors.textDim),
              ),
              if (preview.warning != null) ...[
                const SizedBox(height: 6),
                Text(
                  DaySwapCopy.restRunWarningLine(preview.warning!),
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySm.copyWith(color: AppColors.warn),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySm
                        .copyWith(color: AppColors.bad, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: WardButton(
                  label: DaySwapCopy.confirmSwap,
                  onPressed: _swapping ? null : _onSwap,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: WardButton(
                  label: DaySwapCopy.cancel,
                  variant: WardButtonVariant.ghost,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _moveRow(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.bgRaise,
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          border: Border.all(color: AppColors.line2),
        ),
        child: Text(text,
            style: AppTypography.monoXs
                .copyWith(color: AppColors.textPrimary, letterSpacing: 0.5)),
      );

  Future<void> _onSwap() async {
    setState(() {
      _swapping = true;
      _error = null;
    });
    final result = await ref.read(daySwapControllerProvider).swap(
        dateA: widget.dayA.date, dateB: widget.dayB.date, origin: widget.origin);
    if (!mounted) return;
    if (result is DaySwapDone) {
      final weekStart = DaySwapRules.mondayOf(widget.dayA.date);
      final subject = DaySwapCopy.toastSubject(widget.dayA, widget.dayB);
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(result);
      messenger.showSnackBar(buildDaySwapToast(
        title: DaySwapCopy.toastTitle(widget.dayA.date, widget.dayB.date),
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
