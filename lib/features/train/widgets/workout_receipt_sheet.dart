import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/utils/card_share_service.dart';
import 'edit_workout_log_sheet.dart';
import 'workout_receipt_card.dart';

/// Reusable bottom sheet that displays a WorkoutReceiptCard with share + close.
///
/// Used from: active_workout_screen (post-completion), home_screen (view card),
/// day_detail_sheet (view card for past completed days).
class WorkoutReceiptSheet extends StatefulWidget {
  final WorkoutReceiptData receiptData;

  const WorkoutReceiptSheet({super.key, required this.receiptData});

  /// Convenience: show this sheet as a modal bottom sheet.
  static void show(BuildContext context, WorkoutReceiptData data) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => WorkoutReceiptSheet(receiptData: data),
    );
  }

  @override
  State<WorkoutReceiptSheet> createState() => _WorkoutReceiptSheetState();
}

class _WorkoutReceiptSheetState extends State<WorkoutReceiptSheet> {
  final _cardKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The shareable card
            WorkoutReceiptCard(
              data: widget.receiptData,
              repaintKey: _cardKey,
            ),
            const SizedBox(height: 16),

            // Share action — sharp gold slab, black Mono caps.
            GestureDetector(
              onTap: () async {
                await CardShareService.captureAndShare(
                  _cardKey,
                  filename: 'icanbefitter_workout.png',
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(AppRadius.sharp),
                ),
                child: Center(
                  child: Text(
                    'DISPATCH TO INSTAGRAM / WHATSAPP',
                    style: AppTypography.mono.copyWith(
                      color: Colors.black,
                      letterSpacing: 2.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Edit — opens EditWorkoutLogSheet for the same date.
            GestureDetector(
              onTap: () {
                Navigator.of(context).pop();
                EditWorkoutLogSheet.show(context, widget.receiptData.date);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.sharp),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.55),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.edit_outlined,
                        size: 14, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Text(
                      'AMEND LOG',
                      style: AppTypography.monoXs.copyWith(
                        color: AppColors.accent,
                        letterSpacing: 2.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),

            // Close
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'DISMISS',
                  style: AppTypography.monoXs.copyWith(
                    color: AppColors.textMute,
                    letterSpacing: 2.4,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
