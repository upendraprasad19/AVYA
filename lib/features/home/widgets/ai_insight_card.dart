import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Compact AI Coach insight card — Mono eyebrow ("COACH · LIVE"),
/// body copy, quick-win footer.
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
    return WardCard(
      variant: WardCardVariant.standard,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Eyebrow row: live dot + label
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.ok,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'COACH \u00B7 LIVE',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Insight text
          if (insight != null)
            Text(
              insight!,
              style: AppTypography.body.copyWith(
                color: AppColors.textPrimary,
                height: 1.5,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            )
          else
            Text(
              'Start a conversation with your AI coach for personalised tips!',
              style: AppTypography.body.copyWith(
                color: AppColors.textDim,
                height: 1.5,
              ),
            ),
          const SizedBox(height: 6),
          Text(
            '\u{1F4A1} Quick wins: 3 eggs = 18g \u00B7 100g chicken = 31g \u00B7 1 scoop whey = 25g \u00B7 200g paneer = 36g',
            style: AppTypography.bodySm.copyWith(
              color: AppColors.textDim,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
