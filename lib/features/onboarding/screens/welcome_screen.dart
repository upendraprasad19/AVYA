import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// First-run welcome screen — matches the handoff
/// (`design_handoff_wardroom/src/screens/onboarding.jsx` WelcomeScreen,
/// lines 6–72).
///
/// Layout (top-to-bottom):
/// * Brand row: 18-px Anchor + "AVYA" mono caps + 1-px gold rule +
///   "EST · 2026" mono caption.
/// * Hero: "PROSPECTUS" mono eyebrow + Fraunces 44 three-line headline
///   with italic-gold emphasis on "serious" + DM Sans 14 dim body +
///   three numbered feature ticks (mono 11 gold number + DM Sans 13).
/// * CTA: full-width gold "BEGIN ENLISTMENT →" slab + "Already a
///   member? SIGN IN" mono caption.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: WardFrame(
        grain: true,
        padBottom: 0,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 40, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _brandRow(),
                Expanded(child: _hero()),
                _cta(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _brandRow() {
    return Row(
      children: [
        const AnchorGlyph(size: 18),
        const SizedBox(width: 10),
        Text(
          'AVYA',
          style: AppTypography.mono.copyWith(
            fontSize: 10,
            color: AppColors.accent,
            fontWeight: FontWeight.w700,
            letterSpacing: 4,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            color: AppColors.accent.withValues(alpha: 0.4),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'EST \u00B7 2026',
          style: AppTypography.monoXs.copyWith(
            color: AppColors.textMute,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }

  Widget _hero() {
    const features = [
      'Programmed plans that adapt week-to-week',
      'Nutrition logging tuned to your phase',
      'Coach that holds you to your own standards',
    ];

    return Center(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'PROSPECTUS',
            style: AppTypography.monoXs.copyWith(
              color: AppColors.textMute,
              letterSpacing: 3,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          RichText(
            text: TextSpan(
              style: AppTypography.display.copyWith(
                fontSize: 44,
                fontWeight: FontWeight.w400,
                color: AppColors.textPrimary,
                letterSpacing: -1.2,
                height: 1.02,
              ),
              children: const [
                TextSpan(text: 'Train like\nsomeone '),
                TextSpan(
                  text: 'serious',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500,
                    color: AppColors.accent,
                  ),
                ),
                TextSpan(text: '\nis watching.'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 320,
            child: Text(
              'Personalised coaching, disciplined programming, and an AI that '
              'remembers every lift. No streaks, no gimmicks \u2014 just the log.',
              style: AppTypography.body.copyWith(
                color: AppColors.textDim,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 32),
          for (var i = 0; i < features.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    (i + 1).toString().padLeft(2, '0'),
                    style: AppTypography.mono.copyWith(
                      fontSize: 11,
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    features[i],
                    style: AppTypography.body.copyWith(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            if (i < features.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _cta(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: () => context.go('/onboarding/goal'),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(AppRadius.sharp),
            ),
            alignment: Alignment.center,
            child: Text(
              'BEGIN ENLISTMENT \u2192',
              style: AppTypography.mono.copyWith(
                fontSize: 13,
                color: AppColors.bgDeep,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () => context.go('/auth/sign-in'),
          child: RichText(
            text: TextSpan(
              style: AppTypography.monoXs.copyWith(
                fontSize: 10,
                color: AppColors.textDim,
                letterSpacing: 1.5,
              ),
              children: [
                const TextSpan(text: 'Already a member? '),
                TextSpan(
                  text: 'SIGN IN',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
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
