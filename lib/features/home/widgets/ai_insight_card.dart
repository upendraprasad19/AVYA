import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// AI Coach insight card — matches the Wardroom handoff
/// (`design_handoff_wardroom/src/screens/daily.jsx` lines 177–192).
///
/// `cardHi` variant (the outer `WardCard.hi`) hosts the insight body in
/// Fraunces 14 w500, plus a nested `bgRaise` inset rail with a 2-px
/// gold left border containing "QUICK WINS" (gold mono 10.5) followed
/// by the macro bullets in dim mono 10.5. Eyebrow is rendered by the
/// caller (home_screen) with a leading ok-green dot.
class AiInsightCard extends StatelessWidget {
  final String? insight;
  final String userName;
  final double proteinCurrent;
  final double proteinTarget;

  const AiInsightCard({
    super.key,
    this.insight,
    this.userName = 'there',
    this.proteinCurrent = 0,
    this.proteinTarget = 184,
  });

  @override
  Widget build(BuildContext context) {
    final deficit =
        (proteinTarget - proteinCurrent).clamp(0, proteinTarget).toInt();
    final bodyText = insight ??
        (deficit > 0
            ? '$userName — ${deficit}g of protein left to hit your target.'
            : '$userName — on track for the day.');

    return WardCard(
      variant: WardCardVariant.hero,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            bodyText,
            style: AppTypography.h3.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
              height: 1.45,
              letterSpacing: -0.1,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.stackM),
          // Nested inset — gold left border + QUICK WINS label.
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.bgRaise,
              border: const Border(
                left: BorderSide(color: AppColors.accent, width: 2),
              ),
            ),
            child: RichText(
              text: TextSpan(
                style: AppTypography.monoXs.copyWith(
                  fontSize: 10.5,
                  color: AppColors.textDim,
                  letterSpacing: 0.3,
                  height: 1.6,
                ),
                children: const [
                  TextSpan(
                    text: 'QUICK WINS',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(
                    text:
                        ' \u00B7 3 eggs = 18g \u00B7 100g chicken = 31g \u00B7 1 scoop whey = 25g \u00B7 200g paneer = 36g',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
