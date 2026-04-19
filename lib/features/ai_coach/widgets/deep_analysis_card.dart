import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/ai_coach/services/pattern_detector.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Deep Analysis PRO card with real computed data.
///
/// PRO users see actual pattern analysis from PatternDetector inside a
/// hero [WardCard] with a gold [WardRule] under the Mono-caps eyebrow.
/// Free users see blurred content with a PRO overlay + sharp 2-px
/// accent upgrade slab.
///
/// The [onUpgradeTap] callback should call `subscription.gate('reasoning_tab')`
/// to properly route PRO vs free users.
class DeepAnalysisCard extends StatelessWidget {
  final bool isPro;
  final VoidCallback onUpgradeTap;

  const DeepAnalysisCard({
    super.key,
    required this.isPro,
    required this.onUpgradeTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: isPro ? _buildProContent() : _buildFreeOverlay(),
    );
  }

  /// Builds real analysis text from PatternDetector results.
  String _buildAnalysisText() {
    try {
      final insights = PatternDetector.instance.analyze();
      if (insights.isEmpty) {
        return 'No significant patterns detected yet. Keep logging your workouts and nutrition — I\'ll have insights for you soon.';
      }
      // Combine top 3 insights into natural prose
      final messages = insights
          .take(3)
          .map((i) => i.userMessage)
          .toList();
      return messages.join(' ');
    } catch (e) {
      debugPrint('[DeepAnalysisCard._buildAnalysisText] $e');
      return 'Keep logging consistently — your deep analysis will appear here once I have enough data to spot patterns.';
    }
  }

  /// Full deep analysis content shown to PRO users.
  Widget _buildProContent() {
    final analysisText = _buildAnalysisText();

    return WardCard(
      variant: WardCardVariant.hero,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'DEEP ANALYSIS',
                style: AppTypography.mono.copyWith(
                  color: AppColors.accent,
                  letterSpacing: 1.6,
                ),
              ),
              const Spacer(),
              const WardChip(label: 'PRO', tone: WardChipTone.gold),
            ],
          ),
          const SizedBox(height: 8),
          const WardRule(gold: true, margin: EdgeInsets.zero),
          const SizedBox(height: 10),
          Text(
            analysisText,
            style: AppTypography.body.copyWith(
              color: AppColors.textPrimary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  /// Blurred content with PRO overlay for free users.
  Widget _buildFreeOverlay() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Stack(
        children: [
          // Blurred background content
          WardCard(
            variant: WardCardVariant.hero,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DEEP ANALYSIS',
                  style: AppTypography.mono.copyWith(
                    color: AppColors.accent,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 8),
                const WardRule(gold: true, margin: EdgeInsets.zero),
                const SizedBox(height: 10),
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                  child: Text(
                    _buildAnalysisText(),
                    style: AppTypography.body.copyWith(
                      color: AppColors.textPrimary,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Dark overlay with PRO badge + upgrade button
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.bgDeep.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.33),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const WardChip(label: 'PRO FEATURE', tone: WardChipTone.gold),
                  const SizedBox(height: 10),

                  // Description
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Deep reasoning &\npersonalised pattern analysis',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.textDim,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Upgrade button — sharp 2-px accent slab
                  GestureDetector(
                    onTap: onUpgradeTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(AppRadius.sharp),
                      ),
                      child: Text(
                        'UPGRADE TO PRO',
                        style: AppTypography.mono.copyWith(
                          color: AppColors.bgDeep,
                          letterSpacing: 1.8,
                        ),
                      ),
                    ),
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
