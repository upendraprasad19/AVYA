import 'package:flutter/material.dart';
import 'package:icanbefitter/core/services/badge_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/profile/widgets/badges_grid.dart';
import 'package:icanbefitter/shared/models/achievement_badge.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Single-row achievements card for the profile screen.
/// Shows Fraunces count left, label, recent badge emojis, earned/total pill,
/// chevron. Tapping opens the full BadgesGrid in a bottom sheet.
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

    return WardCard(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      onTap: () => _openBadgesSheet(context),
      child: Row(
        children: [
          // Fraunces numeric count + "BADGES" label stack
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                earnedCount.toString().padLeft(2, '0'),
                style: AppTypography.h2.copyWith(
                  color: AppColors.accent,
                  height: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'BADGES',
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),

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
                  color: AppColors.bgRaise,
                  borderRadius: BorderRadius.circular(AppRadius.soft),
                  border: Border.all(
                    color: display[i].isUnlocked
                        ? AppColors.accent.withValues(alpha: 0.4)
                        : AppColors.line2,
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

          // Earned / total chip
          WardChip(
            label: '$earnedCount / $totalCount',
            tone: WardChipTone.gold,
          ),
          const SizedBox(width: 6),

          // Chevron
          const Icon(
            Icons.chevron_right,
            size: 18,
            color: AppColors.textMute,
          ),
        ],
      ),
    );
  }

  void _openBadgesSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
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
