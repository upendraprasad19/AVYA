import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/theme/spacing.dart';
import 'ward_chip.dart';

/// Single phase row on the onboarding Plan screen. 40 px Roman-numeral
/// circle on the left (gold border + fill when active, dim
/// `textGhost` border when not), Fraunces 15 w600 title, mono 9 weeks
/// label, DM Sans 12 dim description, optional "START" chip on the
/// right for the active row.
class WardPhaseBlock extends StatelessWidget {
  const WardPhaseBlock({
    super.key,
    required this.roman,
    required this.title,
    required this.weeksLabel,
    required this.description,
    this.active = false,
    this.onTap,
  });

  final String roman;
  final String title;
  final String weeksLabel;
  final String description;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.stackM),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Roman-numeral circle.
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? AppColors.accentSoft : Colors.transparent,
                border: Border.all(
                  color: active ? AppColors.accent : AppColors.textGhost,
                  width: active ? 1.5 : 1,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                roman,
                style: AppTypography.h3.copyWith(
                  color: active ? AppColors.accent : AppColors.textDim,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: AppTypography.h3.copyWith(
                            fontSize: 15,
                            color: active
                                ? AppColors.textPrimary
                                : AppColors.textDim,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        weeksLabel.toUpperCase(),
                        style: AppTypography.monoXs.copyWith(
                          color: AppColors.textMute,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.textDim,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            if (active) ...[
              const SizedBox(width: 10),
              const WardChip(label: 'START', tone: WardChipTone.gold),
            ],
          ],
        ),
      ),
    );
  }
}
