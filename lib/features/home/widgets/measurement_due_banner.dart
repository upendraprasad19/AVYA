import 'package:flutter/material.dart';

import 'package:icanbefitter/core/copy/measurement_copy.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Home banner inviting a body-measurements entry (L2b Landing B, E1 / E5).
///
/// One line of copy that differs between the `due` and `baseline` variants, a
/// tap on the card that opens the sheet, and ONE dismiss X (a second "Not now"
/// control with an invisibly different effect would be a trap). Optional,
/// never shaming, never PRO-gated. The X is a >= 44 dp target with a
/// `Semantics` label.
class MeasurementDueBanner extends StatelessWidget {
  const MeasurementDueBanner({
    super.key,
    required this.baseline,
    required this.onOpen,
    required this.onDismiss,
  });

  /// True for the never-measured (baseline) variant, false for `due`.
  final bool baseline;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding, 0, AppSpacing.screenPadding, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(AppRadius.cardM),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                child: Row(
                  children: [
                    const Icon(Icons.straighten,
                        size: 20, color: AppColors.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        baseline
                            ? MeasurementCopy.bannerBaseline
                            : MeasurementCopy.bannerDue,
                        style: AppTypography.body.copyWith(
                            fontSize: 13,
                            color: AppColors.textDim,
                            height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Semantics(
            label: MeasurementCopy.bannerDismissLabel,
            button: true,
            child: InkWell(
              onTap: onDismiss,
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.close,
                    size: 18, color: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
