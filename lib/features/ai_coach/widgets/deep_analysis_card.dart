import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/features/ai_coach/services/pattern_detector.dart';

/// Deep Analysis PRO card with real computed data.
///
/// PRO users see actual pattern analysis from PatternDetector.
/// Free users see blurred content with a PRO overlay + upgrade button.
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: isPro ? _buildProContent() : _buildFreeOverlay(),
      ),
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

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DEEP ANALYSIS',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            analysisText,
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 12,
              fontWeight: FontWeight.w400,
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
    return Stack(
      children: [
        // Blurred background content
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.cardM),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DEEP ANALYSIS',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 5),
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                child: Text(
                  _buildAnalysisText(),
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
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
              color: const Color(0xFF07090e).withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.12),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // PRO FEATURE gold badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.proGold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.badge),
                  ),
                  child: Text(
                    'PRO FEATURE',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.proGold,
                    ),
                  ),
                ),
                const SizedBox(height: 7),

                // Description
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Deep reasoning &\npersonalised pattern analysis',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Upgrade button
                GestureDetector(
                  onTap: onUpgradeTap,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      'Upgrade to PRO',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
