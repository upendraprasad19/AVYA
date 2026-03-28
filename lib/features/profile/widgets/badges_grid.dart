import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/services/badge_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/shared/models/achievement_badge.dart';

/// Grid of all 15 achievement badges shown on the Profile screen.
/// Unlocked badges are full opacity with gold border.
/// Locked badges are dimmed with a lock overlay.
class BadgesGrid extends StatelessWidget {
  const BadgesGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final badges = BadgeService.instance.getAllWithStatus();
    final unlockedCount = badges.where((b) => b.isUnlocked).length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'ACHIEVEMENTS',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.proGold.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: AppColors.proGold.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '$unlockedCount / ${badges.length}',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.proGold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: badges.length,
            itemBuilder: (context, i) {
              final badge = badges[i];
              return GestureDetector(
                onTap: () => _showDetail(context, badge),
                child: AnimatedOpacity(
                  opacity: badge.isUnlocked ? 1.0 : 0.3,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.input,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: badge.isUnlocked
                            ? AppColors.proGold
                            : AppColors.border,
                        width: badge.isUnlocked ? 1.5 : 1.0,
                      ),
                    ),
                    child: Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Text(
                            badge.emoji,
                            style: const TextStyle(fontSize: 24),
                          ),
                          if (!badge.isUnlocked)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Icon(
                                Icons.lock,
                                size: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showDetail(BuildContext context, AchievementBadge badge) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0e1219),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF1c2535),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(badge.emoji, style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            Text(
              badge.name,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: const Color(0xFFeef2f7),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              badge.description,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 13,
                color: const Color(0xFF6b7a8d),
              ),
              textAlign: TextAlign.center,
            ),
            if (badge.isUnlocked) ...[
              const SizedBox(height: 12),
              Text(
                'Unlocked ${_fmt(badge.unlockedAt!)}',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 11,
                  color: const Color(0xFFF59E0B),
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              Text(
                'Keep going to unlock this!',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 11,
                  color: const Color(0xFF6b7a8d),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year}';
}
