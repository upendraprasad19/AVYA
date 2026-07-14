part of 'screen.dart';

// ── Exercise Add / Swap / Create Sheets ──────────────────────────

void _showExercisePickerSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _ExercisePickerSheet(
      onSelect: (exerciseData) {
        ref.read(activeWorkoutProvider.notifier).addExercise(
              ExerciseData(
                name: exerciseData['name'] as String? ?? 'Exercise',
                sets: '${exerciseData['default_sets'] ?? 3}',
                reps: '${exerciseData['default_reps'] ?? '10'}',
                weight: '0kg',
                rest: '${exerciseData['default_rest_secs'] ?? 60}s',
                loggingType:
                    exerciseData['logging_type'] as String? ?? 'weight_reps',
                exerciseType:
                    (exerciseData['exercise_type'] is List
                        ? ((exerciseData['exercise_type'] as List).isNotEmpty
                            ? (exerciseData['exercise_type'] as List).first.toString()
                            : null)
                        : exerciseData['exercise_type'] as String?) ?? 'isolation',
                category: exerciseData['category'] as String? ?? '',
                equipmentNeeded: ExerciseData.parseEquipmentNeeded(
                    exerciseData['equipment_needed']),
              ),
            );
        Navigator.of(ctx).pop();
      },
    ),
  );
}

void _showSwapSheet(BuildContext context, WidgetRef ref, int exerciseIndex) {
  final data = ref.read(activeWorkoutProvider);
  final currentExercise = data.exercises[exerciseIndex];
  final canDelete = data.exercises.length > 1;
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => ExerciseSwapSheet(
      currentExerciseName: currentExercise.name,
      category: currentExercise.category,
      equipment: currentExercise.equipmentNeeded,
      onSelect: (swapEx) {
        ref.read(activeWorkoutProvider.notifier).swapExercise(
              exerciseIndex,
              ExerciseData(
                name: swapEx.name,
                sets: currentExercise.sets,
                reps: currentExercise.reps,
                weight: currentExercise.weight,
                rest: currentExercise.rest,
                loggingType: currentExercise.loggingType,
                category: currentExercise.category,
                equipmentNeeded: currentExercise.equipmentNeeded,
              ),
            );
        // F11 · Ensure Home and Calendar immediately reflect the swap —
        // they read today's schedule/plan, which swapExercise has already
        // mutated in Hive, but Riverpod caches the last-read snapshot.
        ref.invalidate(todayWorkoutProvider);
        ref.invalidate(currentPlanProvider);
        ref.invalidate(calendarWeekProvider);
        Navigator.of(ctx).pop();
      },
      onDelete: canDelete
          ? () => ref.read(activeWorkoutProvider.notifier).removeExercise(exerciseIndex)
          : null,
      onAdd: (addEx) {
        // Sentinel '__ADD_MODE__' means user tapped "+ ADD EXERCISE"
        // inside the Swap sheet.
        //
        // Pre-2026-04-24 this opened a picker sheet to browse
        // existing exercises, forcing the user to then swap again
        // manually. Per APK test #1 feedback: "if the path was via
        // swap, it should have swapped as well." The new flow opens
        // CreateCustomExerciseSheet directly; on save the new
        // exercise is auto-swapped into the slot, with an UNDO
        // snackbar for recoverability.
        if (addEx.name == '__ADD_MODE__') {
          // Bug s1n4c0 (APK Test #16.2) — pop the outer swap sheet BEFORE
          // opening CreateCustomExerciseSheet. Pre-fix, the swap sheet
          // stayed mounted while the create sheet opened on top, so when
          // create.onCreated fired ScaffoldMessenger.showSnackBar at
          // _openCreateAndAutoSwap, the snackbar was hosted against a
          // context shadowed by the still-active swap modal route. The
          // 5s dismiss timer never fired on Android and the user had to
          // restart the app to clear the toast. Mirrors the picker-path
          // pop at the onSelect handler above.
          Navigator.of(ctx).pop();
          _openCreateAndAutoSwap(context, ref, exerciseIndex);
        }
      },
    ),
  );
}

/// Opens [CreateCustomExerciseSheet] and, on save, swaps the newly
/// created exercise into [exerciseIndex], preserving the slot's sets,
/// reps, weight, and rest. Shows an UNDO snackbar that restores the
/// original exercise if tapped within 5 s.
void _openCreateAndAutoSwap(
  BuildContext context,
  WidgetRef ref,
  int exerciseIndex,
) {
  final data = ref.read(activeWorkoutProvider);
  if (exerciseIndex < 0 || exerciseIndex >= data.exercises.length) return;
  final original = data.exercises[exerciseIndex];

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => CreateCustomExerciseSheet(
      onCreated: (newExercise) {
        final newName = (newExercise['name'] as String?) ?? 'Exercise';
        final loggingType =
            (newExercise['logging_type'] as String?) ?? 'weight_reps';
        final defaultSets = newExercise['default_sets'];
        final defaultReps = newExercise['default_reps'];
        final defaultRest = newExercise['default_rest_secs'];
        final equipRaw = newExercise['equipment_needed'];
        final equipment = equipRaw == null
            ? original.equipmentNeeded
            : ExerciseData.parseEquipmentNeeded(equipRaw);

        // Compose the swap target. Prefer the form's defaults (user
        // just typed them) and fall back to the original slot's
        // values so weight and cadence carry over naturally.
        final replacement = ExerciseData(
          name: newName,
          sets: defaultSets != null ? '$defaultSets' : original.sets,
          reps: defaultReps != null ? '$defaultReps' : original.reps,
          weight: original.weight,
          rest: defaultRest != null ? '${defaultRest}s' : original.rest,
          loggingType: loggingType,
          category: (newExercise['category'] as String?) ?? original.category,
          equipmentNeeded: equipment,
        );

        ref.read(activeWorkoutProvider.notifier).swapExercise(
              exerciseIndex,
              replacement,
            );
        ref.invalidate(todayWorkoutProvider);
        ref.invalidate(currentPlanProvider);
        ref.invalidate(calendarWeekProvider);

        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.card,
              duration: const Duration(seconds: 5),
              content: Text(
                'Swapped "${original.name}" → "$newName"',
                style: AppTypography.bodySm,
              ),
              action: SnackBarAction(
                label: 'UNDO',
                textColor: AppColors.accent,
                onPressed: () {
                  ref
                      .read(activeWorkoutProvider.notifier)
                      .swapExercise(exerciseIndex, original);
                  ref.invalidate(todayWorkoutProvider);
                  ref.invalidate(currentPlanProvider);
                  ref.invalidate(calendarWeekProvider);
                },
              ),
            ),
          );
      },
    ),
  );
}
