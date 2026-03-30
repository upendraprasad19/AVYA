import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/features/ai_coach/services/pattern_detector.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';

/// Provider for the top coaching insight (highest severity pattern).
/// Refreshes once per build (cached by PatternDetector internally).
final topInsightProvider = Provider<CoachingInsight?>((ref) {
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
        accentColor = AppColors.red;
        icon = Icons.warning_amber_rounded;
        break;
      case InsightSeverity.medium:
        accentColor = AppColors.orange;
        icon = Icons.info_outline;
        break;
      case InsightSeverity.low:
        accentColor = AppColors.accent;
        icon = Icons.lightbulb_outline;
        break;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sectionGap),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.cardM),
          border: Border.all(color: accentColor.withValues(alpha: 0.2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left accent strip
            Container(
              width: 3,
              height: 40,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(2),
              ),
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
                    'Coach Notice',
                    style: GoogleFonts.getFont('DM Sans',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: accentColor),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    insight.userMessage,
                    style: GoogleFonts.getFont('DM Sans',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                        height: 1.4),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Arrow
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_ios,
                size: 12, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
