import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/shared/models/achievement_badge.dart';

/// Bug #21 — Inline compact achievements row for the Profile identity band.
/// Shows the 3 most recently unlocked badges (by `unlockedAt` desc) followed
/// by a chevron that opens the full BadgesGrid in a bottom sheet.
///
/// If fewer than 3 badges are unlocked, the row is padded with locked badges
/// rendered at 40% opacity — the layout always reserves exactly 3 slots so
/// the right-hand chevron + PRO pill don't jitter as badges unlock.
class CompactAchievementsRow extends StatelessWidget {
  final List<AchievementBadge> badges;
  final VoidCallback onOpenAll;

  const CompactAchievementsRow({
    super.key,
    required this.badges,
    required this.onOpenAll,
  });

  List<AchievementBadge> _pickDisplay() {
    final unlocked = badges.where((b) => b.isUnlocked).toList()
      ..sort((a, b) => (b.unlockedAt ?? DateTime(0))
          .compareTo(a.unlockedAt ?? DateTime(0)));
    final locked = badges.where((b) => !b.isUnlocked).toList();

    final display = <AchievementBadge>[];
    display.addAll(unlocked.take(3));
    while (display.length < 3 && locked.isNotEmpty) {
      display.add(locked.removeAt(0));
    }
    return display;
  }

  @override
  Widget build(BuildContext context) {
    final display = _pickDisplay();

    return GestureDetector(
      onTap: onOpenAll,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < display.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            _BadgeIcon(badge: display[i]),
          ],
          const SizedBox(width: 4),
          const Icon(
            Icons.keyboard_arrow_down,
            size: 18,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

class _BadgeIcon extends StatelessWidget {
  final AchievementBadge badge;

  const _BadgeIcon({required this.badge});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: badge.isUnlocked ? 1.0 : 0.4,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.input,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: badge.isUnlocked
                ? AppColors.proGold.withValues(alpha: 0.4)
                : AppColors.border,
          ),
        ),
        child: Text(badge.emoji, style: const TextStyle(fontSize: 18)),
      ),
    );
  }
}
