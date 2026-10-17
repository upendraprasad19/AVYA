import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/profile/providers/profile_completeness_provider.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

class ProfileCompletenessCard extends ConsumerWidget {
  const ProfileCompletenessCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(profileCompletenessProvider);

    // Hide when profile is complete
    if (data.percentage >= 100) return const SizedBox.shrink();

    return WardCard(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mono eyebrow row: "PROFILE · X% COMPLETE"
          Row(
            children: [
              Expanded(
                child: Text(
                  'PROFILE · ${data.percentage}% COMPLETE',
                  style: AppTypography.mono.copyWith(
                    color: AppColors.textMute,
                    letterSpacing: 2,
                  ),
                ),
              ),
              Text(
                '${data.percentage}%',
                style: AppTypography.h3.copyWith(
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.stackS),
          WardBar(
            pct: data.percentage / 100,
            color: AppColors.accent,
            height: 4,
          ),
          if (data.allMissing.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.stackM),
            ...data.allMissing.map(
              (field) => GestureDetector(
                onTap: () => context.go('/profile/edit'),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              field.label.toUpperCase(),
                              style: AppTypography.mono.copyWith(
                                color: AppColors.textMute,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              field.benefit,
                              style: AppTypography.bodySm.copyWith(
                                color: AppColors.textDim,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const WardChip(label: 'ADD', tone: WardChipTone.warn),
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
