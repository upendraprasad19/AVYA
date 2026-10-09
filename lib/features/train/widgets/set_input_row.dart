import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Compact inline set row (~40 px tall) for active workout.
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
          // Set tile (sharp 2-px) — "W" for warm-up, else set number
          GestureDetector(
            onLongPress: isCompleted ? null : onToggleWarmUp,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isWarmUp
                    ? AppColors.warn.withValues(alpha: 0.12)
                    : AppColors.accentSoft,
                borderRadius: BorderRadius.circular(2),
                border: isWarmUp
                    ? Border.all(
                        color: AppColors.warn.withValues(alpha: 0.3),
                      )
                    : null,
              ),
              child: Center(
                child: Text(
                  isWarmUp ? 'W' : '$setNumber',
                  style: AppTypography.mono.copyWith(
                    color: isWarmUp ? AppColors.warn : AppColors.accent,
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Input fields based on logging type
          ..._buildInputs(),

          const SizedBox(width: 6),

          // Check tile (sharp 2-px)
          GestureDetector(
            onTap: onCheck,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isChecked ? AppColors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
                border: isChecked
                    ? null
                    : Border.all(color: AppColors.line2, width: 1.5),
              ),
              child: isChecked
                  ? Icon(Icons.check, size: 16, color: AppColors.bgDeep)
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
          Expanded(child: _compactInput(weightController, 'KG')),
          const SizedBox(width: 6),
          Expanded(child: _compactInput(repsController, 'REPS', isInt: true)),
        ];

      case 'bodyweight_reps':
        return [
          Expanded(child: _compactInput(repsController, 'REPS', isInt: true)),
        ];

      case 'weighted_bodyweight':
        return [
          Expanded(child: _compactInput(weightController, 'KG')),
          const SizedBox(width: 6),
          Expanded(child: _compactInput(repsController, 'REPS', isInt: true)),
        ];

      case 'timed':
        return [
          Expanded(child: _compactInput(durationController, 'SEC', isInt: true)),
        ];

      case 'cardio':
        return [
          Expanded(child: _compactInput(durationController, 'MIN')),
          const SizedBox(width: 6),
          Expanded(child: _compactInput(distanceController, 'KM')),
        ];

      case 'distance':
        return [
          Expanded(child: _compactInput(distanceController, 'KM')),
          const SizedBox(width: 6),
          Expanded(child: _compactInput(weightController, 'KG')),
        ];

      default:
        return [
          Expanded(child: _compactInput(weightController, 'KG')),
          const SizedBox(width: 6),
          Expanded(child: _compactInput(repsController, 'REPS', isInt: true)),
        ];
    }
  }

  Widget _compactInput(
    TextEditingController controller,
    String hint, {
    bool isInt = false,
  }) {
    // Green border indicates this set's values have been locked in.
    final lockedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(2),
      borderSide: BorderSide(
        color: AppColors.ok.withValues(alpha: 0.6),
        width: 2,
      ),
    );

    return SizedBox(
      height: 38,
      child: TextField(
        controller: controller,
        keyboardType: isInt
            ? TextInputType.number
            : const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: isInt
            ? [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ]
            : [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                LengthLimitingTextInputFormatter(6),
              ],
        textAlign: TextAlign.center,
        style: AppTypography.h2.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.2,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTypography.monoXs.copyWith(
            color: AppColors.textMute,
            letterSpacing: 1.4,
          ),
          filled: true,
          fillColor: isChecked
              ? AppColors.ok.withValues(alpha: 0.06)
              : AppColors.bgRaise,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(2),
            borderSide: const BorderSide(color: AppColors.line2, width: 2),
          ),
          enabledBorder: isChecked
              ? lockedBorder
              : OutlineInputBorder(
                  borderRadius: BorderRadius.circular(2),
                  borderSide:
                      const BorderSide(color: AppColors.line2, width: 2),
                ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(2),
            borderSide: const BorderSide(color: AppColors.accent, width: 2),
          ),
        ),
      ),
    );
  }
}
