import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/shared/utils/card_share_service.dart';
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

            // Share button
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
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Center(
                  child: Text(
                    'Share to Instagram / WhatsApp',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Close
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Close',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
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
