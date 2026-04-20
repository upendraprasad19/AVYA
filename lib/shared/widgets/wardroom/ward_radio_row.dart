import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/theme/spacing.dart';

/// Onboarding Goal-screen radio selection card. 44 px mono key on the
/// left, title + subtitle, 12×12 radio circle on the right.
///
/// Selected state: `cardTop` bg, gold border, 3 px gold left border.
/// Unselected: `card` bg, `line2` border, no left-bar.
class WardRadioRow extends StatelessWidget {
  const WardRadioRow({
    super.key,
    required this.rowKey,
    required this.title,
    required this.subtitle,
    required this.selected,
    this.onTap,
  });

  final String rowKey;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.cardTop : AppColors.card,
          border: Border(
            top: BorderSide(
              color: selected ? AppColors.accent : AppColors.line2,
            ),
            right: BorderSide(
              color: selected ? AppColors.accent : AppColors.line2,
            ),
            bottom: BorderSide(
              color: selected ? AppColors.accent : AppColors.line2,
            ),
            left: BorderSide(
              color: selected ? AppColors.accent : AppColors.line2,
              width: selected ? 3 : 1,
            ),
          ),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 44,
              child: Text(
                rowKey,
                style: AppTypography.mono.copyWith(
                  color: selected ? AppColors.accent : AppColors.textMute,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppTypography.h3.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.textDim,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.accent : AppColors.textGhost,
                  width: 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: selected
                  ? Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accent,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
