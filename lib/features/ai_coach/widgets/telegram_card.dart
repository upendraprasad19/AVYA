import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Telegram connection section.
///
/// Wardroom styling: centred stack with Mono-caps eyebrow, body copy,
/// and a sharp 2-px accent slab CTA. Connected state swaps the chip/CTA
/// tone to [WardChipTone.ok].
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
            isConnected ? 'COMMS CHANNEL · LINKED' : 'COMMS CHANNEL',
            style: AppTypography.monoXs.copyWith(
              color: AppColors.textMute,
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: isConnected ? null : onConnect,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isConnected
                    ? AppColors.ok.withValues(alpha: 0.14)
                    : AppColors.accentSoft,
                borderRadius: BorderRadius.circular(AppRadius.sharp),
                border: Border.all(
                  color: isConnected ? AppColors.ok : AppColors.accent,
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isConnected ? Icons.check_circle : Icons.send,
                    size: 14,
                    color: isConnected ? AppColors.ok : AppColors.accent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isConnected
                        ? 'TELEGRAM CONNECTED'
                        : 'CONNECT @AVYACOACHBOT',
                    style: AppTypography.mono.copyWith(
                      color: isConnected ? AppColors.ok : AppColors.accent,
                      letterSpacing: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
