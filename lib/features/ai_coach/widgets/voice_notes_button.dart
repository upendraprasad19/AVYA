import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';

/// Push-to-talk voice notes button (PRO only).
///
/// Free users see the button locked — tapping triggers [onLockedTap]
/// which should call subscription.gate('voice_notes').
/// PRO users see an active mic button — long press records.
class VoiceNotesButton extends StatelessWidget {
  final bool isPro;
  final bool isRecording;
  final VoidCallback onLockedTap;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;

  const VoiceNotesButton({
    super.key,
    required this.isPro,
    this.isRecording = false,
    required this.onLockedTap,
    required this.onStartRecording,
    required this.onStopRecording,
  });

  @override
  Widget build(BuildContext context) {
    if (!isPro) {
      return GestureDetector(
        onTap: onLockedTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.proGoldTint,
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.proGold.withValues(alpha: 0.3),
            ),
          ),
          child: Stack(
            children: [
              const Center(
                child: Icon(
                  Icons.mic,
                  color: AppColors.proGold,
                  size: 16,
                ),
              ),
              Positioned(
                bottom: 2,
                right: 2,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppColors.proGold,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.header, width: 1.5),
                  ),
                  child: const Icon(
                    Icons.lock,
                    size: 6,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onLongPressStart: (_) => onStartRecording(),
      onLongPressEnd: (_) => onStopRecording(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isRecording ? AppColors.red : AppColors.input,
          shape: BoxShape.circle,
          border: Border.all(
            color: isRecording
                ? AppColors.red
                : AppColors.accent.withValues(alpha: 0.3),
          ),
        ),
        child: Icon(
          isRecording ? Icons.stop : Icons.mic,
          color: isRecording ? Colors.white : AppColors.accent,
          size: 16,
        ),
      ),
    );
  }
}
