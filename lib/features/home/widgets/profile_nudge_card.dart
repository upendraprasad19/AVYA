import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/features/profile/providers/profile_completeness_provider.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Slim dismissible card showing the highest-impact missing profile field.
/// Positioned between Quick Actions and AI Coach Insight on the home screen.
class ProfileNudgeCard extends ConsumerWidget {
  const ProfileNudgeCard({super.key});

  static const _dismissKey = 'profile_nudge_dismissed_at';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completeness = ref.watch(profileCompletenessProvider);

    // Don't show if complete
    if (completeness.isComplete) return const SizedBox.shrink();

    // Don't show if dismissed < 3 days ago
    final dismissedAt = MigratedKey.read<String>(_dismissKey);
    if (dismissedAt != null) {
      final dismissed = DateTime.tryParse(dismissedAt);
      if (dismissed != null && DateTime.now().difference(dismissed).inDays < 3) {
        return const SizedBox.shrink();
      }
    }

    final field = completeness.highestImpactMissing;
    if (field == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: WardCard(
        variant: WardCardVariant.inset,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        onTap: () => context.push('/profile/edit'),
        child: Row(
          children: [
            Icon(Icons.auto_awesome,
                size: 16, color: AppColors.accent.withValues(alpha: 0.7)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${field.benefit} \u2192',
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.textDim,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: () {
                MigratedKey.write(_dismissKey, DateTime.now().toIso8601String());
                ref.invalidate(profileCompletenessProvider);
              },
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 14, color: AppColors.textDim),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
