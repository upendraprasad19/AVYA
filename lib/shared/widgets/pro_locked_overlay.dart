import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';

/// Reusable PRO locked overlay that wraps any content widget.
///
/// Displays: blur(4) + dark overlay + gold lock badge + cyan CTA.
/// Used consistently across all PRO-gated sections.
///
/// ```dart
/// ProLockedOverlay(
///   featureLabel: 'Progress Photos',
///   description: 'Track your body transformation',
///   onUpgradeTap: () => showPaywallSheet(context, feature: 'Progress Photos'),
///   child: _buildPhotosContent(),  // The content to show blurred
/// )
/// ```
class ProLockedOverlay extends StatelessWidget {
  /// The content to show blurred behind the overlay.
  final Widget child;

  /// Short label for the locked feature (e.g., "Progress Photos").
  final String featureLabel;

  /// Optional description text below the label.
  final String? description;

  /// Called when the user taps the upgrade CTA.
  final VoidCallback onUpgradeTap;

  /// Optional CTA button text. Defaults to "Upgrade to PRO".
  final String ctaText;

  /// Minimum height for the overlay area. Defaults to 120.
  final double minHeight;

  const ProLockedOverlay({
    super.key,
    required this.child,
    required this.featureLabel,
    this.description,
    required this.onUpgradeTap,
    this.ctaText = 'Upgrade to PRO',
    this.minHeight = 120,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.cardM),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Stack(
          children: [
            // Blurred content
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                child: child,
              ),
            ),

            // Dark overlay + lock + CTA
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.bg.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(AppRadius.cardM),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Gold lock icon
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.proGoldTint,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock_rounded,
                        color: AppColors.proGold,
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // PRO badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.proGold.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.badge),
                      ),
                      child: Text(
                        'PRO FEATURE',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.proGold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Feature label
                    Text(
                      featureLabel,
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    // Description
                    if (description != null) ...[
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          description!,
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            color: AppColors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),

                    // Cyan CTA button
                    GestureDetector(
                      onTap: onUpgradeTap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 9),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          ctaText,
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
