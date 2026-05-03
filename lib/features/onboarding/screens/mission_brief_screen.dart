import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

class MissionBriefScreen extends ConsumerWidget {
  const MissionBriefScreen({super.key, this.readOnly = false});

  final bool readOnly;

  Future<void> _openInstagram() async {
    final native = Uri.parse('instagram://user?username=icanbefitter');
    if (await canLaunchUrl(native)) {
      await launchUrl(native);
    } else {
      await launchUrl(Uri.parse('https://instagram.com/icanbefitter'));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: readOnly
          ? AppBar(
              backgroundColor: AppColors.bg,
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new,
                    color: AppColors.textPrimary, size: 20),
                onPressed: () => context.pop(),
              ),
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '⊙  AVYA  ·  MISSION BRIEF',
                style: AppTypography.mono.copyWith(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 8),
              Container(width: 80, height: 1, color: AppColors.accent),
              const SizedBox(height: 24),
              Text(
                'A note from your coach.',
                style: AppTypography.titleL.copyWith(fontSize: 28),
              ),
              const SizedBox(height: 32),
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.accent, width: 1.5),
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/founder/upendra.jpg',
                      key: const ValueKey('founder-photo'),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: AppColors.card,
                        child: const Icon(Icons.person,
                            color: AppColors.textMute, size: 40),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'UPENDRA PRASAD',
                  style: AppTypography.titleL.copyWith(fontSize: 22),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'EX-INDIAN NAVY  ·  14 YEARS',
                  style: AppTypography.mono.copyWith(
                    fontSize: 10,
                    letterSpacing: 1.2,
                    color: AppColors.accent,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  'CERTIFIED FITNESS + NUTRITION COACH',
                  style: AppTypography.mono.copyWith(
                    fontSize: 10,
                    letterSpacing: 1.2,
                    color: AppColors.accent,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  width: 24,
                  height: 1,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 24),
              RichText(
                text: TextSpan(
                  style: AppTypography.bodyL.copyWith(
                    color: AppColors.textPrimary,
                    height: 1.6,
                  ),
                  children: [
                    const TextSpan(text: 'Welcome aboard.\n\nYou\'re not joining an app. You\'re reporting in.\n\n'),
                    const TextSpan(
                      text: 'For 14 years I trained men in the Indian Navy. Discipline ',
                    ),
                    TextSpan(
                      text: 'isn\'t motivation',
                      style: AppTypography.bodyL.copyWith(
                        color: AppColors.accent,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w500,
                        height: 1.6,
                      ),
                    ),
                    const TextSpan(
                      text: ' — it\'s structure. A plan you can follow when you don\'t feel like it.\n\nThat\'s what AVYA is. The discipline of military training. The science of certified coaching. Built for the long haul.\n\nYou do the work. ',
                    ),
                    TextSpan(
                      text: 'AVYA holds the discipline',
                      style: AppTypography.bodyL.copyWith(
                        color: AppColors.accent,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w500,
                        height: 1.6,
                      ),
                    ),
                    const TextSpan(
                      text: '.\n\n',
                    ),
                    TextSpan(
                      text: 'Show up. Earn promotions. Become the man who lasts',
                      style: AppTypography.bodyL.copyWith(
                        color: AppColors.accent,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w500,
                        height: 1.6,
                      ),
                    ),
                    const TextSpan(
                      text: '.\n\nThe AI runs the drills. ',
                    ),
                    TextSpan(
                      text: 'The playbook is mine',
                      style: AppTypography.bodyL.copyWith(
                        color: AppColors.accent,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w500,
                        height: 1.6,
                      ),
                    ),
                    const TextSpan(
                      text: '.\n\n',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  'Jai Hind.',
                  style: AppTypography.titleS.copyWith(
                    color: AppColors.accent,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '— Upendra',
                  style: AppTypography.mono.copyWith(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Center(
                child: GestureDetector(
                  onTap: _openInstagram,
                  child: RichText(
                    text: TextSpan(
                      style: AppTypography.mono.copyWith(
                        fontSize: 11,
                        color: AppColors.textMute,
                      ),
                      children: [
                        const TextSpan(text: 'Daily wins on Instagram → '),
                        TextSpan(
                          text: '@icanbefitter',
                          style: TextStyle(
                            color: AppColors.accent,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              if (!readOnly)
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () => context.go('/onboarding/identity'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.bg,
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      'CONTINUE  →',
                      style: AppTypography.mono.copyWith(
                        fontSize: 14,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
