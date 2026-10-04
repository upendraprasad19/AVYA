import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';

/// Push-to-talk voice notes button — available to all users.
///
/// Wardroom styling: sharp 2-px gold square tile (idle) /
/// destructive sharp 2-px tile (recording). Tap toggles recording;
/// long press also starts/stops recording.
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
          color: isRecording
              ? AppColors.bad.withValues(alpha: 0.14)
              : AppColors.accentSoft,
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          border: Border.all(
            color: isRecording ? AppColors.bad : AppColors.accent,
            width: 2,
          ),
        ),
        child: Icon(
          isRecording ? Icons.stop : Icons.mic,
          color: isRecording ? AppColors.bad : AppColors.accent,
          size: 16,
        ),
      ),
    );
  }
}
