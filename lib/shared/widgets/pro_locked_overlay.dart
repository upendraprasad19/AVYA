import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Reusable PRO locked overlay that wraps any content widget.
///
/// Displays: blur(4) + dark overlay + gold lock badge + gold CTA.
/// Used by the Progress Photos screen's locked state (its only user today).
///
/// The text column is centred while it fits and scrolls when it does not (a short
/// window, a landscape phone, a large text scale), so the CTA is never clipped out
/// of reach. The CTA is a real button: keyboard-focusable (web), announced as a
/// button, at least 44 dp tall.
///
/// It needs a BOUNDED height (a Scaffold body, an Expanded, a SizedBox): its
/// layers are `Positioned.fill` children of a Stack, so inside a ListView or an
/// unconstrained Column the Stack has nothing to size itself against and asserts.
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
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
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
                                borderRadius:
                                    BorderRadius.circular(AppRadius.badge),
                              ),
                              child: Text(
                                'PRO FEATURE',
                                style: AppTypography.body.copyWith(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.proGold),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Feature label
                            Text(
                              featureLabel,
                              style: AppTypography.body.copyWith(fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                              textAlign: TextAlign.center,
                            ),

                            // Description
                            if (description != null) ...[
                              const SizedBox(height: 4),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                child: Text(
                                  description!,
                                  style: AppTypography.body.copyWith(fontSize: 11, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],

                            const SizedBox(height: 12),

                            // Gold CTA button (Wardroom "primary button": accent
                            // fill, black w900 text, pill). A Material + InkWell,
                            // not a bare GestureDetector, so a keyboard user on web
                            // can focus and activate it.
                            Semantics(
                              button: true,
                              child: Material(
                                color: AppColors.accent,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.pill),
                                child: InkWell(
                                  onTap: onUpgradeTap,
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.pill),
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(minHeight: 44),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 20, vertical: 9),
                                      child: Center(
                                        widthFactor: 1,
                                        child: Text(
                                          ctaText,
                                          style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w900, color: Colors.black),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
