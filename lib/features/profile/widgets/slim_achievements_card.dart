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
///
/// Theme C · Test #8 — `compact` mode strips the WardCard wrapper so the
/// inner Row can be re-wrapped by `_buildFlushCard` in `profile_screen.dart`
/// (single-decoration flush stack, square inner corners).
class SlimAchievementsCard extends StatelessWidget {
  const SlimAchievementsCard({super.key, this.compact = false});

  /// When true, returns the inner Row inline (no WardCard wrapper, no
  /// padding, no tap target). The caller is responsible for decoration,
  /// padding, and the tap target.
  final bool compact;

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

    final body = Row(
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

          // Recent badge emojis.
          // diagnose c9e0a4 follow-up (D-profile): the count + fixed badge
          // tiles + chip + chevron overflowed this row (~right stripe) on
          // narrow widths. Expanded(Wrap) gives the badge group the remaining
          // space (keeping the chip right-aligned) and lets it wrap instead of
          // overflow when truly tight.
          Expanded(
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (int i = 0; i < display.length; i++)
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
            ),
          ),
          const SizedBox(width: 8),

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
      );

    if (compact) {
      // Caller (the flush stack in profile_screen.dart) provides decoration,
      // padding (14), and the tap surface. Wrap only in a GestureDetector so
      // the tap-to-open-badges-sheet still works inside the flush group.
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openBadgesSheet(context),
        child: body,
      );
    }

    return WardCard(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      onTap: () => _openBadgesSheet(context),
      child: body,
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
