import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// The founder's personal note — the first screen every new user reads.
///
/// Copy is the founder-locked Mission Brief (Unit 5, 2026-06-14). The
/// injury/comeback story + the "No one is coming to save you" closer are
/// verbatim as approved. The Instagram CTA was removed from this screen
/// (acquisition friction on the trust-building first screen — founder call
/// 2026-06-14).
class MissionBriefScreen extends StatelessWidget {
  const MissionBriefScreen({super.key, this.readOnly = false});

  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    // Gold-italic emphasis for the power phrases (matches the Wardroom voice).
    TextSpan accent(String text) => TextSpan(
          text: text,
          style: AppTypography.bodyL.copyWith(
            color: AppColors.accent,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w500,
            height: 1.6,
          ),
        );

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
                      cacheWidth: 192,
                      cacheHeight: 192,
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
                    const TextSpan(text: 'Welcome aboard, Recruit.\n\n'),
                    const TextSpan(
                      text:
                          'Early in my Navy training, I shattered my right leg '
                          'on a cross-country run — broken in several places. '
                          'While it healed with a rod inside, I started lifting. '
                          'Skinny. Humbled. No coach, no gym. I just never gave '
                          'up.\n\n',
                    ),
                    const TextSpan(
                      text:
                          'Fourteen years in uniform taught me the truth nobody '
                          'sells you — discipline ',
                    ),
                    accent("isn't motivation"),
                    const TextSpan(
                      text:
                          ". It's structure. A plan you follow on the days you "
                          "don't feel like it.\n\n",
                    ),
                    const TextSpan(
                      text:
                          "That's what AVYA is. The structure of military "
                          'training, the science of certified coaching — built '
                          'to carry you when willpower runs out.\n\n',
                    ),
                    const TextSpan(text: 'You do the work. '),
                    accent('AVYA holds the line'),
                    const TextSpan(text: '.\n\n'),
                    accent(
                        'Show up. Earn your promotions. Become the man who lasts'),
                    const TextSpan(text: '.\n\n'),
                    accent(
                        'No one is coming to save you, Recruit. The one who can → is you.'),
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
