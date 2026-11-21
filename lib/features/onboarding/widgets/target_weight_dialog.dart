// lib/features/onboarding/widgets/target_weight_dialog.dart
//
// The ONE popup that explains why a target weight was refused. Used by the
// onboarding Stats screen and (OI-191) by Edit Profile's Save, so both doors
// show the same words in the same box. It touches no focus: the caller decides
// where focus goes after the await (Stats puts it back on the TARGET field).
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Dismissable popup (the ADJUST button or a tap outside closes it).
Future<void> showTargetWeightDialog(
  BuildContext context,
  String message,
) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      key: const ValueKey('target_weight_dialog'),
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: AppColors.accent.withValues(alpha: 0.53)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'CHECK YOUR TARGET',
              style: AppTypography.mono.copyWith(
                color: AppColors.accent,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: AppTypography.bodyL.copyWith(
                color: AppColors.textPrimary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            GestureDetector(
              key: const ValueKey('target_weight_dialog_close'),
              onTap: () => Navigator.of(ctx).pop(),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(AppRadius.sharp),
                ),
                alignment: Alignment.center,
                child: Text(
                  'ADJUST TARGET',
                  style: AppTypography.mono.copyWith(
                    fontSize: 12,
                    color: AppColors.bgDeep,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
