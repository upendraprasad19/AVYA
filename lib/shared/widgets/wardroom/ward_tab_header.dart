// lib/shared/widgets/wardroom/ward_tab_header.dart
//
// Unified header used by all 5 tab screens (Daily/Workout/Nutrition/Coach/Profile).
// Provides identical structure + Y-position for the rank chip across tabs so
// the user perceives stability when navigating tabs.
//
// Structure (56dp tall):
//   [avatar 32dp] [TAB EYEBROW (mono caps gold)]  [Spacer]  [streak chip] [freeze chip]
//
// Source: APK Test #4 hotfix spec §3 U7.

import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

class WardTabHeader extends StatelessWidget {
  /// Tab-specific eyebrow text. Captain voice, mono caps.
  /// e.g., "DAILY BRIEF", "TRAIN", "FUEL", "DISPATCH", "DOSSIER".
  final String eyebrow;

  /// First letter of user's name for the avatar circle. Defaults to "A".
  final String avatarInitial;

  /// Current streak in days. 0 hides the streak chip.
  final int streakDays;

  /// Available freezes. -1 hides the chip; 0+ shows.
  final int freezesAvailable;

  /// Optional avatar tap handler (e.g., to navigate to Profile).
  final VoidCallback? onAvatarTap;

  const WardTabHeader({
    super.key,
    required this.eyebrow,
    this.avatarInitial = 'A',
    this.streakDays = 0,
    this.freezesAvailable = -1,
    this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Avatar
            GestureDetector(
              onTap: onAvatarTap,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.accent, width: 1.2),
                ),
                alignment: Alignment.center,
                child: Text(
                  avatarInitial.isEmpty ? 'A' : avatarInitial[0].toUpperCase(),
                  style: AppTypography.mono.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Eyebrow text
            Expanded(
              child: Text(
                eyebrow,
                style: AppTypography.mono.copyWith(
                  fontSize: 11,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ),
            // Streak chip
            if (streakDays > 0) _StreakChip(days: streakDays),
            if (streakDays > 0 && freezesAvailable >= 0) const SizedBox(width: 6),
            // Freeze chip
            if (freezesAvailable >= 0) _FreezeChip(count: freezesAvailable),
          ],
        ),
      ),
    );
  }
}

class _StreakChip extends StatelessWidget {
  final int days;
  const _StreakChip({required this.days});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.bgRaise,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🔥', style: TextStyle(fontSize: 11)),
          const SizedBox(width: 4),
          Text(
            '$days D',
            style: AppTypography.mono.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _FreezeChip extends StatelessWidget {
  final int count;
  const _FreezeChip({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.bgRaise,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('❄', style: TextStyle(fontSize: 11)),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: AppTypography.mono.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
