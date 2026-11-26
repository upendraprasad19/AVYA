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

  /// LOG mode only: the up / same / down arrow of a logged set, drawn INSIDE the
  /// KG box (9 dp from its right edge, vertically centred) because the check
  /// column that used to hold it is gone. Ignored on the per-set path and for a
  /// row with no weight box.
  final Widget? weightSuffix;

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
    this.weightSuffix,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          _setTile(),
          const SizedBox(width: 8),

          // Input fields based on logging type
          ..._buildInputs(),

          // Check tile (sharp 2-px): the per-set path only. LOG mode has no
          // check column, so the fields run to the card's edge and a logged set
          // is shown by its set tile (a tick) instead.
          if (interactiveCheck) ...[
            const SizedBox(width: 6),
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
        ],
      ),
    );
  }

  /// Set tile (sharp 2-px): "W" for warm-up, else the set number. In LOG mode a
  /// logged set shows a tick instead (accent for a working set, warn for a
  /// warm-up) with the "Set n, logged" label; the long-press that toggles
  /// warm-up stays disabled once the set is completed.
  Widget _setTile() {
    final tick = !interactiveCheck && isChecked;
    final tile = GestureDetector(
      onLongPress: isCompleted ? null : onToggleWarmUp,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: tick
              ? (isWarmUp ? AppColors.warn : AppColors.accent)
              : isWarmUp
                  ? AppColors.warn.withValues(alpha: 0.12)
                  : AppColors.accentSoft,
          borderRadius: BorderRadius.circular(2),
          border: isWarmUp && !tick
              ? Border.all(
                  color: AppColors.warn.withValues(alpha: 0.3),
                )
              : null,
        ),
        child: Center(
          child: tick
              ? Icon(Icons.check, size: 16, color: AppColors.bgDeep)
              : Text(
                  isWarmUp ? 'W' : '$setNumber',
                  style: AppTypography.mono.copyWith(
                    color: isWarmUp ? AppColors.warn : AppColors.accent,
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
        ),
      ),
    );
    if (!tick) return tile;
    return Semantics(
      container: true,
      label: (isWarmUp
              ? WardroomCopy.activeWarmUpSetLoggedLabelTemplate
              : WardroomCopy.activeSetLoggedLabelTemplate)
          .replaceAll('{n}', '$setNumber'),
      child: tile,
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
    final box = SizedBox(
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
    );

    // LOG mode's weight box carries the logged set's arrow as an overlay. The
    // Stack is built for EVERY LOG-mode weight box, logged or not, with the box
    // as its first child: only the overlay child comes and goes, so logging or
    // re-opening a set never remounts the TextField (the same reason as the
    // Semantics wrapper above). Positioned top and bottom with only a right
    // inset gives the Center an unbounded width, so the arrow shrink-wraps at
    // right: 9 and is centred on the 38 dp height; the Stack is sized by the box.
    final withSuffix = !interactiveCheck && field == SetField.weight
        ? Stack(
            children: [
              box,
              if (weightSuffix != null)
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 9,
                  child: IgnorePointer(
                    child: Center(child: ExcludeSemantics(child: weightSuffix)),
                  ),
                ),
            ],
          )
        : box;
    return Semantics(
      label: controller.text.isEmpty ? null : hint,
      hint: faded ? WardroomCopy.activePrefilledHint : null,
      child: withSuffix,
    );
  }
}
