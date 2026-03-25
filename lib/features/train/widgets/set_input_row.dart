import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';

/// Compact inline set row (~40px tall) for active workout.
///
/// Adapts fields based on [loggingType]:
///   weight_reps, bodyweight_reps, weighted_bodyweight, timed, cardio, distance
class SetInputRow extends StatelessWidget {
  final String loggingType;
  final TextEditingController weightController;
  final TextEditingController repsController;
  final TextEditingController durationController;
  final TextEditingController distanceController;
  final int setNumber;
  final String? previousPerformance;
  final bool isWarmUp;
  final bool isCompleted;
  final bool isChecked;
  final VoidCallback? onToggleWarmUp;
  final VoidCallback? onCheck;

  const SetInputRow({
    super.key,
    required this.loggingType,
    required this.weightController,
    required this.repsController,
    required this.durationController,
    required this.distanceController,
    required this.setNumber,
    this.previousPerformance,
    this.isWarmUp = false,
    this.isCompleted = false,
    this.isChecked = false,
    this.onToggleWarmUp,
    this.onCheck,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          // Set badge: 28x28 circle
          GestureDetector(
            onLongPress: isCompleted ? null : onToggleWarmUp,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isWarmUp
                    ? const Color(0xFFf97316).withValues(alpha: 0.12)
                    : AppColors.accentTint,
                shape: BoxShape.circle,
                border: isWarmUp
                    ? Border.all(
                        color: const Color(0xFFf97316).withValues(alpha: 0.3),
                      )
                    : null,
              ),
              child: Center(
                child: Text(
                  isWarmUp ? 'W' : '$setNumber',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: isWarmUp
                        ? const Color(0xFFf97316)
                        : AppColors.accent,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Input fields based on logging type
          ..._buildInputs(),

          const SizedBox(width: 6),

          // Checkbox: 28x28 circle
          GestureDetector(
            onTap: onCheck,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isChecked
                    ? AppColors.accent
                    : Colors.transparent,
                shape: BoxShape.circle,
                border: isChecked
                    ? null
                    : Border.all(
                        color: AppColors.border,
                        width: 1.5,
                      ),
              ),
              child: isChecked
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildInputs() {
    switch (loggingType) {
      case 'weight_reps':
        return [
          Expanded(child: _compactInput(weightController, 'kg')),
          const SizedBox(width: 6),
          Expanded(child: _compactInput(repsController, 'reps', isInt: true)),
        ];

      case 'bodyweight_reps':
        return [
          Expanded(child: _compactInput(repsController, 'reps', isInt: true)),
        ];

      case 'weighted_bodyweight':
        return [
          Expanded(child: _compactInput(weightController, 'kg')),
          const SizedBox(width: 6),
          Expanded(child: _compactInput(repsController, 'reps', isInt: true)),
        ];

      case 'timed':
        return [
          Expanded(child: _compactInput(durationController, 'sec', isInt: true)),
        ];

      case 'cardio':
        return [
          Expanded(child: _compactInput(durationController, 'min')),
          const SizedBox(width: 6),
          Expanded(child: _compactInput(distanceController, 'km')),
        ];

      case 'distance':
        return [
          Expanded(child: _compactInput(distanceController, 'km')),
          const SizedBox(width: 6),
          Expanded(child: _compactInput(weightController, 'kg')),
        ];

      default: // fallback to weight_reps
        return [
          Expanded(child: _compactInput(weightController, 'kg')),
          const SizedBox(width: 6),
          Expanded(child: _compactInput(repsController, 'reps', isInt: true)),
        ];
    }
  }

  Widget _compactInput(
    TextEditingController controller,
    String hint, {
    bool isInt = false,
  }) {
    return SizedBox(
      height: 36,
      child: TextField(
        controller: controller,
        keyboardType: isInt
            ? TextInputType.number
            : const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: isInt
            ? [FilteringTextInputFormatter.digitsOnly]
            : [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
        textAlign: TextAlign.center,
        style: GoogleFonts.getFont(
          'DM Sans',
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: AppColors.textSecondary,
          ),
          filled: true,
          fillColor: AppColors.input,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AppColors.accent, width: 1.5),
          ),
        ),
      ),
    );
  }
}
