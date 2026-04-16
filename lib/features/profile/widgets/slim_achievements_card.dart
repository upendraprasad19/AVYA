import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/services/badge_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/features/profile/widgets/badges_grid.dart';
import 'package:icanbefitter/shared/models/achievement_badge.dart';

/// Single-row achievements card for the profile screen.
/// Shows trophy icon + "Achievements" label + 3 recent badge emojis +
/// earned/total count pill + chevron. Tapping opens the full BadgesGrid
/// in a bottom sheet.
class SlimAchievementsCard extends StatelessWidget {
  const SlimAchievementsCard({super.key});

  @override
  Widget build(BuildContext context) {
    BadgeService.instance.checkAll();
    final allBadges = BadgeService.instance.getAllWithStatus();
    final earned = allBadges.where((b) => b.isUnlocked).toList()
      ..sort((a, b) =>
          (b.unlockedAt ?? DateTime(0)).compareTo(a.unlockedAt ?? DateTime(0)));
    final earnedCount = earned.length;
    final totalCount = allBadges.length;

    // Pick up to 3 most recent earned badges; pad with locked ones if fewer
    final locked = allBadges.where((b) => !b.isUnlocked).toList();
    final display = <AchievementBadge>[];
    display.addAll(earned.take(3));
    while (display.length < 3 && locked.isNotEmpty) {
      display.add(locked.removeAt(0));
    }

    return GestureDetector(
      onTap: () => _openBadgesSheet(context),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            // Trophy icon
            const Text('🏆', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),

            // Label
            Text(
              'Achievements',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 10),

            // Recent badge emojis
            for (int i = 0; i < display.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Opacity(
                opacity: display[i].isUnlocked ? 1.0 : 0.35,
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.input,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: display[i].isUnlocked
                          ? AppColors.proGold.withValues(alpha: 0.4)
                          : AppColors.border,
                    ),
                  ),
                  child: Text(
                    display[i].emoji,
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ),
            ],

            const Spacer(),

            // Earned / total pill
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.proGold.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                    color: AppColors.proGold.withValues(alpha: 0.3)),
              ),
              child: Text(
                '$earnedCount / $totalCount',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.proGold,
                ),
              ),
            ),
            const SizedBox(width: 6),

            // Chevron
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  void _openBadgesSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.only(top: 12, bottom: 12),
          child: SingleChildScrollView(child: BadgesGrid()),
        ),
      ),
    );
  }
}
