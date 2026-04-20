import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';

/// Horizontal row of small achievement circles for the Profile identity
/// header. Earned circles use gold-soft bg + gold border + the passed
/// icon in gold; locked circles are transparent with a ghost border and
/// a ghost-tinted icon.
///
/// Default diameter 36 px, 8 px gap, scrollable when [entries] exceeds
/// the available width.
class WardAchievementStrip extends StatelessWidget {
  const WardAchievementStrip({
    super.key,
    required this.entries,
    this.diameter = 36,
    this.gap = 8,
  });

  final List<WardAchievement> entries;
  final double diameter;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: diameter,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: entries.length,
        separatorBuilder: (_, _) => SizedBox(width: gap),
        itemBuilder: (_, i) {
          final entry = entries[i];
          final earned = entry.earned;
          return Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              color: earned ? AppColors.accentSoft : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                color: earned ? AppColors.accent : AppColors.textGhost,
                width: earned ? 1.2 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: IconTheme(
              data: IconThemeData(
                size: diameter * 0.5,
                color: earned
                    ? AppColors.accent
                    : AppColors.textGhost.withValues(alpha: 0.7),
              ),
              child: entry.icon,
            ),
          );
        },
      ),
    );
  }
}

class WardAchievement {
  const WardAchievement({required this.icon, required this.earned});
  final Widget icon;
  final bool earned;
}
