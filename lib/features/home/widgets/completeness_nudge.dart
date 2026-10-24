import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../../../shared/widgets/wardroom/wardroom.dart';
import '../../profile/providers/profile_completeness_provider.dart';

/// F15 · Home-screen nudge for users whose profile isn't fully filled.
///
/// Non-dismissible banner; tap deep-links to Edit Profile. Hides at
/// ≥80% completeness (covers "mostly done" users without annoying them).
/// Complements F3's fix to never falsely flag profiles as incomplete.
class CompletenessNudge extends ConsumerWidget {
  const CompletenessNudge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(profileCompletenessProvider);
    if (data.percentage >= 80 || data.highestImpactMissing == null) {
      return const SizedBox.shrink();
    }
    final missing = data.highestImpactMissing!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding, 8, AppSpacing.screenPadding, 4),
      child: WardCard(
        variant: WardCardVariant.inset,
        padding: const EdgeInsets.all(12),
        onTap: () => context.pushNamed('editProfile'),
        child: Row(
          children: [
            WardChip(
              label: '${data.percentage}%',
              tone: WardChipTone.gold,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'COMPLETE YOUR PROFILE',
                    style: AppTypography.mono.copyWith(
                      color: AppColors.accent,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Next: ${missing.label} — ${missing.benefit}',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.textDim,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppColors.accent, size: 20),
          ],
        ),
      ),
    );
  }
}
