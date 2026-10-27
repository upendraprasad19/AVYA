import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/core/theme/typography.dart';

import '../services/log_exercise_logic.dart' show SetField;

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

  /// One LOG per exercise (flag `enable_log_exercise_button`). All optional and
  /// unset on the per-set path, which renders exactly as before.
  /// `false` hides the check tile's tap target: a checked set shows a static
  /// tick, an unchecked one an empty slot of the same width.
  final bool interactiveCheck;
  final FocusNode? weightFocusNode;
  final FocusNode? repsFocusNode;
  final FocusNode? durationFocusNode;
  final FocusNode? distanceFocusNode;
  /// Fires on every keystroke, with the field that changed.
  final ValueChanged<SetField>? onChanged;

  /// Fields whose text the app put there and the user has not typed in
  /// (docs/plans/log-exercise-flip.md §2): rendered at 62% parchment, a tap
  /// selects the whole value, TalkBack hears "Prefilled value". Empty on the
  /// per-set path.
  final Set<SetField> fadedFields;

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
    this.interactiveCheck = true,
    this.weightFocusNode,
    this.repsFocusNode,
    this.durationFocusNode,
    this.distanceFocusNode,
    this.onChanged,
    this.fadedFields = const {},
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
          if (!interactiveCheck)
            _staticCheckSlot()
          else
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

  /// The check column without a tap target (LOG-per-exercise mode).
  Widget _staticCheckSlot() {
    if (!isChecked) return const SizedBox(width: 28, height: 28);
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Icon(Icons.check, size: 16, color: AppColors.bgDeep),
    );
  }

  List<Widget> _buildInputs() {
    switch (loggingType) {
      case 'weight_reps':
        return [
          Expanded(child: _compactInput(weightController, 'KG', SetField.weight, focusNode: weightFocusNode)),
          const SizedBox(width: 6),
          Expanded(child: _compactInput(repsController, 'REPS', SetField.reps, isInt: true, focusNode: repsFocusNode)),
        ];

      case 'bodyweight_reps':
        return [
          Expanded(child: _compactInput(repsController, 'REPS', SetField.reps, isInt: true, focusNode: repsFocusNode)),
        ];

      case 'weighted_bodyweight':
        return [
          Expanded(child: _compactInput(weightController, 'KG', SetField.weight, focusNode: weightFocusNode)),
          const SizedBox(width: 6),
          Expanded(child: _compactInput(repsController, 'REPS', SetField.reps, isInt: true, focusNode: repsFocusNode)),
        ];

      case 'timed':
        return [
          Expanded(child: _compactInput(durationController, 'SEC', SetField.duration, isInt: true, focusNode: durationFocusNode)),
        ];

      case 'cardio':
        return [
          Expanded(child: _compactInput(durationController, 'MIN', SetField.duration, focusNode: durationFocusNode)),
          const SizedBox(width: 6),
          Expanded(child: _compactInput(distanceController, 'KM', SetField.distance, focusNode: distanceFocusNode)),
        ];

      case 'distance':
        return [
          Expanded(child: _compactInput(distanceController, 'KM', SetField.distance, focusNode: distanceFocusNode)),
          const SizedBox(width: 6),
          Expanded(child: _compactInput(weightController, 'KG', SetField.weight, focusNode: weightFocusNode)),
        ];

      default:
        return [
          Expanded(child: _compactInput(weightController, 'KG', SetField.weight, focusNode: weightFocusNode)),
          const SizedBox(width: 6),
          Expanded(child: _compactInput(repsController, 'REPS', SetField.reps, isInt: true, focusNode: repsFocusNode)),
        ];
    }
  }

  Widget _compactInput(
    TextEditingController controller,
    String hint,
    SetField field, {
    bool isInt = false,
    FocusNode? focusNode,
  }) {
    final faded = fadedFields.contains(field);
    // Green border indicates this set's values have been locked in.
    final lockedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(2),
      borderSide: BorderSide(
        color: AppColors.ok.withValues(alpha: 0.6),
        width: 2,
      ),
    );

    // The Semantics wrapper is ALWAYS present, faded or not, LOG mode or not:
    // a wrapper that came and went would remount the TextField (focus and the
    // keyboard connection) on the first keystroke into a faded field. Only its
    // properties change. The unit label is null on a blank field, where the
    // hintText already speaks it.
    return Semantics(
      label: controller.text.isEmpty ? null : hint,
      hint: faded ? WardroomCopy.activePrefilledHint : null,
      child: SizedBox(
      height: 38,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged == null ? null : (_) => onChanged!(field),
        // A tap on an app-filled value selects all of it, so typing replaces
        // it. `selectAllOnFocus` does not fire on a tap (the tap focus change
        // is flagged internal); onTap runs after the tap's own selection.
        onTap: faded
            ? () => controller.selection = TextSelection(
                baseOffset: 0, extentOffset: controller.text.length)
            : null,
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
          color: faded
              ? AppColors.textPrimary.withValues(alpha: 0.62)
              : AppColors.textPrimary,
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
      ),
    );
  }
}
