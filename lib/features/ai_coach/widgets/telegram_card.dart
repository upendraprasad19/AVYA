import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';

/// Telegram connection section matching the mockup design.
///
/// Centered layout with "Chat on Telegram instead" text and a connect button.
class TelegramCard extends StatelessWidget {
  final bool isConnected;
  final VoidCallback onConnect;

  const TelegramCard({
    super.key,
    required this.isConnected,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        children: [
          Text(
            isConnected
                ? 'Connected to Telegram'
                : 'Chat on Telegram instead',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 10,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: isConnected ? null : onConnect,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: isConnected
                      ? AppColors.green.withValues(alpha: 0.3)
                      : AppColors.accent.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isConnected) ...[
                    const Icon(
                      Icons.check_circle,
                      color: AppColors.green,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Telegram Connected',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.green,
                      ),
                    ),
                  ] else ...[
                    Text(
                      '\u{1F4F1}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Connect @ICanbeFitterBot',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
