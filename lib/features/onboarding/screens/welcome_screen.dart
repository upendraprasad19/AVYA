import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/auth/providers/referral_code_stash_provider.dart';
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
///   member? SIGN IN" mono caption + optional referral code field +
///   privacy footer.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _referralController = TextEditingController();

  @override
  void dispose() {
    _referralController.dispose();
    super.dispose();
  }

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
          onTap: () => context.go('/onboarding/mission-brief'),
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
          onTap: () => context.go('/sign-in'),
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
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        // \u2500\u2500 Optional referral code field \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0),
          child: Column(
            children: [
              TextField(
                controller: _referralController,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9\-]')),
                  LengthLimitingTextInputFormatter(13),
                ],
                decoration: InputDecoration(
                  hintText: 'Got a code? AVYA-XXXXXXXX',
                  hintStyle: AppTypography.mono.copyWith(
                    color: AppColors.textGhost,
                    fontSize: 12,
                  ),
                  filled: true,
                  fillColor: AppColors.input,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.accent,
                      width: 1.5,
                    ),
                  ),
                ),
                style: AppTypography.mono.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                ),
                onChanged: (v) {
                  ref
                      .read(referralCodeStashProvider.notifier)
                      .setCode(v.trim().toUpperCase());
                },
              ),
              const SizedBox(height: 4),
              Text(
                'Apply within 7 days of signup',
                style: AppTypography.bodyS.copyWith(
                  color: AppColors.textMute,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _PrivacyFooter(),
      ],
    );
  }
}

/// Inline "By continuing, you agree to our Privacy Policy and Terms."
/// footer shown at the bottom of the welcome screen CTA section.
class _PrivacyFooter extends StatefulWidget {
  @override
  State<_PrivacyFooter> createState() => _PrivacyFooterState();
}

class _PrivacyFooterState extends State<_PrivacyFooter> {
  final _privacyRecognizer = TapGestureRecognizer();
  final _termsRecognizer = TapGestureRecognizer();

  @override
  void initState() {
    super.initState();
    _privacyRecognizer.onTap = () => launchUrl(
          Uri.parse('https://icanbefitter.com/privacy'),
          mode: LaunchMode.externalApplication,
        );
    _termsRecognizer.onTap = () => launchUrl(
          Uri.parse('https://icanbefitter.com/terms'),
          mode: LaunchMode.externalApplication,
        );
  }

  @override
  void dispose() {
    _privacyRecognizer.dispose();
    _termsRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: AppTypography.bodyS.copyWith(
            color: AppColors.textMute,
            height: 1.4,
          ),
          children: [
            const TextSpan(text: 'By continuing, you agree to our '),
            TextSpan(
              text: 'Privacy Policy',
              style: const TextStyle(
                color: AppColors.accent,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.accent,
              ),
              recognizer: _privacyRecognizer,
            ),
            const TextSpan(text: ' and '),
            TextSpan(
              text: 'Terms',
              style: const TextStyle(
                color: AppColors.accent,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.accent,
              ),
              recognizer: _termsRecognizer,
            ),
            const TextSpan(text: '.'),
          ],
        ),
      ),
    );
  }
}
