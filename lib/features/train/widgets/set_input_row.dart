import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';

/// Weight + reps (or other fields) input row for active workout.
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

  const SetInputRow({
    super.key,
    required this.loggingType,
    required this.weightController,
    required this.repsController,
    required this.durationController,
    required this.distanceController,
    required this.setNumber,
    this.previousPerformance,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accentTint,
                  borderRadius: BorderRadius.circular(AppRadius.badge),
                ),
                child: Text(
                  'Set $setNumber',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accent,
                  ),
                ),
              ),
              if (previousPerformance != null) ...[
                const Spacer(),
                Text(
                  'Prev: $previousPerformance',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          _buildInputFields(),
        ],
      ),
    );
  }

  Widget _buildInputFields() {
    switch (loggingType) {
      case 'weight_reps':
        return Row(
          children: [
            Expanded(
              child: _inputField(
                controller: weightController,
                label: 'Weight (kg)',
                icon: Icons.fitness_center,
              ),
            ),
            const SizedBox(width: AppSpacing.gridGap),
            Expanded(
              child: _inputField(
                controller: repsController,
                label: 'Reps',
                icon: Icons.repeat,
                isInt: true,
              ),
            ),
          ],
        );

      case 'bodyweight_reps':
        return _inputField(
          controller: repsController,
          label: 'Reps',
          icon: Icons.repeat,
          isInt: true,
        );

      case 'weighted_bodyweight':
        return Row(
          children: [
            Expanded(
              child: _inputField(
                controller: weightController,
                label: 'Added Weight (kg)',
                icon: Icons.fitness_center,
              ),
            ),
            const SizedBox(width: AppSpacing.gridGap),
            Expanded(
              child: _inputField(
                controller: repsController,
                label: 'Reps',
                icon: Icons.repeat,
                isInt: true,
              ),
            ),
          ],
        );

      case 'timed':
        return _inputField(
          controller: durationController,
          label: 'Duration (seconds)',
          icon: Icons.timer,
          isInt: true,
        );

      case 'cardio':
        return Row(
          children: [
            Expanded(
              child: _inputField(
                controller: durationController,
                label: 'Duration (min)',
                icon: Icons.timer,
              ),
            ),
            const SizedBox(width: AppSpacing.gridGap),
            Expanded(
              child: _inputField(
                controller: distanceController,
                label: 'Distance (km)',
                icon: Icons.straighten,
              ),
            ),
          ],
        );

      case 'distance':
        return Row(
          children: [
            Expanded(
              child: _inputField(
                controller: distanceController,
                label: 'Distance (km)',
                icon: Icons.straighten,
              ),
            ),
            const SizedBox(width: AppSpacing.gridGap),
            Expanded(
              child: _inputField(
                controller: weightController,
                label: 'Load (kg)',
                icon: Icons.fitness_center,
              ),
            ),
          ],
        );

      default:
        return Row(
          children: [
            Expanded(
              child: _inputField(
                controller: weightController,
                label: 'Weight (kg)',
                icon: Icons.fitness_center,
              ),
            ),
            const SizedBox(width: AppSpacing.gridGap),
            Expanded(
              child: _inputField(
                controller: repsController,
                label: 'Reps',
                icon: Icons.repeat,
                isInt: true,
              ),
            ),
          ],
        );
    }
  }

  Widget _inputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isInt = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType:
          isInt ? TextInputType.number : const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: isInt
          ? [FilteringTextInputFormatter.digitsOnly]
          : [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
      style: GoogleFonts.getFont(
        'DM Sans',
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.getFont(
          'DM Sans',
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondary,
        ),
        prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 18),
        filled: true,
        fillColor: AppColors.input,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.row),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.row),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.row),
          borderSide: BorderSide(color: AppColors.accent, width: 1.5),
        ),
      ),
    );
  }
}
