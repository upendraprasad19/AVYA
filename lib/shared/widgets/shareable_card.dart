import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/theme/colors.dart';

/// Base wrapper for all shareable cards.
///
/// Wraps [child] in a RepaintBoundary (for screenshot capture) with a
/// consistent dark-mode background and a branded bottom strip containing
/// the ICANBEFITTER wordmark and a QR code pointing to [AppConstants.appUrl].
class ShareableCard extends StatelessWidget {
  /// The card content above the branding strip.
  final Widget child;

  /// GlobalKey for the RepaintBoundary — pass to [CardShareService.captureAndShare].
  final GlobalKey repaintKey;

  const ShareableCard({
    super.key,
    required this.child,
    required this.repaintKey,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: repaintKey,
      child: Container(
        width: 360,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Card content
            child,

            // Branding strip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.border),
                ),
              ),
              child: Row(
                children: [
                  // Wordmark
                  Expanded(
                    child: Text(
                      AppConstants.appName,
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),

                  // QR code
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: QrImageView(
                      data: AppConstants.appUrl,
                      version: QrVersions.auto,
                      size: 44,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                      padding: const EdgeInsets.all(2),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
