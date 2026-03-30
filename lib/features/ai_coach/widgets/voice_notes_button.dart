import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';

/// Push-to-talk voice notes button — available to all users.
///
/// Tap toggles recording on/off. Long press also starts/stops recording.
class VoiceNotesButton extends StatelessWidget {
  final bool isPro;
  final bool isRecording;
  final VoidCallback onLockedTap;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;

  const VoiceNotesButton({
    super.key,
    this.isPro = true,
    this.isRecording = false,
    required this.onLockedTap,
    required this.onStartRecording,
    required this.onStopRecording,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isRecording ? onStopRecording : onStartRecording,
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
