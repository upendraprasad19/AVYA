import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/ai_coach/services/pattern_detector.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Provider for the top coaching insight (highest severity pattern).
/// Refreshes once per build (cached by PatternDetector internally).
final topInsightProvider = Provider<CoachingInsight?>((ref) {
  ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
  return AiCoachRepository.instance.getTopInsight();
});

/// Dashboard card that shows the AI coach's top insight.
///
/// Sits between "Today's Workout" and "Nutrition Snapshot" on Home screen.
/// Tapping navigates to the AI Coach tab with the insight as context.
class InsightCard extends ConsumerWidget {
  final VoidCallback? onTap;

  const InsightCard({super.key, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insight = ref.watch(topInsightProvider);
    if (insight == null) return const SizedBox.shrink();

    final Color accentColor;
    final IconData icon;
    switch (insight.severity) {
      case InsightSeverity.high:
        accentColor = AppColors.bad;
        icon = Icons.warning_amber_rounded;
        break;
      case InsightSeverity.medium:
        accentColor = AppColors.warn;
        icon = Icons.info_outline;
        break;
      case InsightSeverity.low:
        accentColor = AppColors.accent;
        icon = Icons.lightbulb_outline;
        break;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sectionGap),
      child: WardCard(
        variant: WardCardVariant.standard,
        padding: const EdgeInsets.all(14),
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left accent strip — sharp 2-px slab
            Container(
              width: 3,
              height: 40,
              color: accentColor,
            ),
            const SizedBox(width: 12),

            // Icon
            Icon(icon, size: 18, color: accentColor),
            const SizedBox(width: 10),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'COACH NOTICE',
                    style: AppTypography.mono.copyWith(
                      color: accentColor,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    insight.userMessage,
                    style: AppTypography.body.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Arrow
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_ios,
                size: 12, color: AppColors.textDim),
          ],
        ),
      ),
    );
  }
}
