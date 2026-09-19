import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Full-width banner section with gradient background.
///
/// Shows "Add Cover Photo" when no banner image is set.
/// Tapping opens image picker (TODO(profile-ui): wire to image_picker —
/// tagged 2026-05-21 / C8. Currently a no-op tap; product-blocking only
/// when banner-upload feature graduates from PRO-staged-rollout to GA).
class ProfileBanner extends StatelessWidget {
  final VoidCallback onTapBanner;
  final VoidCallback onTapEdit;

  const ProfileBanner({
    super.key,
    required this.onTapBanner,
    required this.onTapEdit,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTapBanner,
      child: Container(
        height: 110,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.gradientNavyDeep,
              AppColors.gradientNavyShadow,
              AppColors.gradientGreenShadow,
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // "Add Cover Photo" overlay
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.image_outlined,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Add Cover Photo',
                    style: AppTypography.body.copyWith(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),

            // Edit pill button (bottom right)
            Positioned(
              bottom: 8,
              right: 8,
              child: GestureDetector(
                onTap: onTapEdit,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.edit,
                        size: 10,
                        color: AppColors.textPrimary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Edit',
                        style: AppTypography.body.copyWith(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
