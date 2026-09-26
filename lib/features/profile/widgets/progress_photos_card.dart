import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Progress Photos card — PRO only.
///
/// PRO users see a grid of their photos with timeline.
/// Free users see a blurred preview with upgrade overlay.
class ProgressPhotosCard extends StatelessWidget {
  final bool isPro;
  final int photoCount;
  final VoidCallback onTap;
  final VoidCallback onUpgradeTap;

  const ProgressPhotosCard({
    super.key,
    required this.isPro,
    this.photoCount = 0,
    required this.onTap,
    required this.onUpgradeTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
      child: isPro ? _buildProContent() : _buildLockedContent(),
    );
  }

  Widget _buildProContent() {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.photo_camera,
                    size: 16,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Progress Photos',
                        style: AppTypography.bodyM.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                      Text(
                        photoCount > 0
                            ? '$photoCount photos \u00B7 Tap to view timeline'
                            : 'Take your first progress photo',
                        style: AppTypography.body.copyWith(fontSize: 10, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_a_photo, size: 13, color: Colors.black),
                      const SizedBox(width: 5),
                      Text(
                        'Capture',
                        style: AppTypography.body.copyWith(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.black),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Placeholder photo grid
            if (photoCount > 0) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 80,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: photoCount > 6 ? 6 : photoCount,
                  itemBuilder: (context, index) {
                    return Container(
                      width: 60,
                      height: 80,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: AppColors.input,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Icon(
                        Icons.image,
                        color: AppColors.textDisabled,
                        size: 20,
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLockedContent() {
    return Stack(
      children: [
        // Blurred background
        Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.input,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 60,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.input,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 60,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.input,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Overlay
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.bg.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(AppRadius.cardM),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.proGold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.badge),
                  ),
                  child: Text(
                    'PRO FEATURE',
                    style: AppTypography.body.copyWith(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.proGold),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Progress Photos',
                  style: AppTypography.body.copyWith(fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  'Track your body transformation',
                  style: AppTypography.body.copyWith(fontSize: 11, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: onUpgradeTap,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      'Upgrade to PRO',
                      style: AppTypography.body.copyWith(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.black),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
