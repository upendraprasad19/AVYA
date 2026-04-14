import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/features/profile/providers/profile_completeness_provider.dart';

class ProfileCompletenessCard extends ConsumerWidget {
  const ProfileCompletenessCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(profileCompletenessProvider);

    // Hide when profile is complete
    if (data.percentage >= 100) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: title + percentage
          Row(
            children: [
              Text(
                'Profile Completeness',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '${data.percentage}%',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: data.percentage / 100,
              minHeight: 6,
              backgroundColor: AppColors.input,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
            ),
          ),
          if (data.allMissing.isNotEmpty) ...[
            const SizedBox(height: 12),
            // Missing fields list — each row navigates to edit profile
            ...data.allMissing.map(
              (field) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: GestureDetector(
                  onTap: () => context.go('/profile/edit'),
                  child: Row(
                    children: [
                      Icon(
                        Icons.add_circle_outline,
                        size: 14,
                        color: AppColors.accent.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${field.label} — ${field.benefit}',
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 14,
                        color: AppColors.textSecondary.withValues(alpha: 0.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
