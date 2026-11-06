import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/theme/spacing.dart';

/// Hero "Today's Insight" card. Gradient `cardTop → card` background,
/// soft gold border, a large gold quote-mark watermark at 8% alpha in
/// the top-right, Fraunces 18 italic body with gold-bold emphasis
/// segments, and optional CTA row.
///
/// Use for the Coach dispatch insight and the Nutrition AI Meal Coach
/// callout. The emphasis segments inside [body] are passed as a list of
/// [InsightSegment] — plain text alternates with `emphasised: true`
/// segments that render as gold, weight 700, non-italic.
class WardInsightQuote extends StatelessWidget {
  const WardInsightQuote({
    super.key,
    this.eyebrow,
    required this.segments,
    this.primaryCta,
    this.onPrimary,
    this.secondaryCta,
    this.onSecondary,
    this.padding = const EdgeInsets.all(18),
  });

  final String? eyebrow;
  final List<InsightSegment> segments;
  final String? primaryCta;
  final VoidCallback? onPrimary;
  final String? secondaryCta;
  final VoidCallback? onSecondary;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.cardTop, AppColors.card],
        ),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.27),
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Stack(
        children: [
          // Quote watermark.
          Positioned(
            top: -20,
            right: 10,
            child: Text(
              '\u201C',
              style: TextStyle(
                fontFamily: 'Fraunces',
                fontSize: 120,
                fontWeight: FontWeight.w700,
                color: AppColors.accent.withValues(alpha: 0.08),
                height: 1,
              ),
            ),
          ),
          Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (eyebrow != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      eyebrow!.toUpperCase(),
                      style: AppTypography.monoXs.copyWith(
                        color: AppColors.accent,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ),
                RichText(
                  text: TextSpan(
                    style: AppTypography.h2.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.1,
                      height: 1.35,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textPrimary,
                    ),
                    children: segments
                        .map((s) => TextSpan(
                              text: s.text,
                              style: s.emphasised
                                  ? TextStyle(
                                      fontStyle: FontStyle.normal,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.accent,
                                    )
                                  : null,
                            ))
                        .toList(),
                  ),
                ),
                if (primaryCta != null || secondaryCta != null) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (primaryCta != null)
                        _Cta(
                          label: primaryCta!,
                          onTap: onPrimary,
                          filled: true,
                        ),
                      if (primaryCta != null && secondaryCta != null)
                        const SizedBox(width: 10),
                      if (secondaryCta != null)
                        _Cta(
                          label: secondaryCta!,
                          onTap: onSecondary,
                          filled: false,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class InsightSegment {
  const InsightSegment(this.text, {this.emphasised = false});
  final String text;
  final bool emphasised;
}

class _Cta extends StatelessWidget {
  const _Cta({required this.label, required this.onTap, required this.filled});
  final String label;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: filled ? AppColors.accent : Colors.transparent,
          border: Border.all(
            color: filled ? AppColors.accent : AppColors.line2,
          ),
          borderRadius: BorderRadius.circular(AppRadius.sharp),
        ),
        child: Text(
          label.toUpperCase(),
          style: AppTypography.mono.copyWith(
            fontSize: 11,
            color: filled ? AppColors.bgDeep : AppColors.textDim,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.5,
          ),
        ),
      ),
    );
  }
}
