import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/spacing.dart';
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
      child: Material(
        color: AppColors.accentTint,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.pushNamed('editProfile'),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${data.percentage}%',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: AppColors.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Complete your profile',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Next: ${missing.label} — ${missing.benefit}',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 11,
                          color: AppColors.textSecondary,
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
        ),
      ),
    );
  }
}
