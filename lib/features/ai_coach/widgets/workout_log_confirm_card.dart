import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import '../providers/ai_coach_provider.dart';
import '../services/conversational_log_handler.dart';

/// Editable confirmation card for a multi-turn workout log.
///
/// Shown when the AI parses exercise details from a conversation.
/// Unlike [LogConfirmCard], this does NOT auto-confirm — workout data
/// is too important to auto-submit. User must tap "Log Workout" explicitly.
class WorkoutLogConfirmCard extends ConsumerStatefulWidget {
  const WorkoutLogConfirmCard({super.key});

  @override
  ConsumerState<WorkoutLogConfirmCard> createState() =>
      _WorkoutLogConfirmCardState();
}

class _WorkoutLogConfirmCardState
    extends ConsumerState<WorkoutLogConfirmCard> {
  bool _isSubmitting = false;

  Future<void> _submit() async {
    final draft = ref.read(workoutDraftProvider);
    if (draft == null || _isSubmitting) return;

    setState(() => _isSubmitting = true);
    await submitWorkoutDraft(draft, ref);
    if (mounted) setState(() => _isSubmitting = false);
  }

  void _discard() {
    ref.read(workoutDraftProvider.notifier).clearDraft();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(workoutDraftProvider);
    if (draft == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.fitness_center, color: AppColors.accent, size: 16),
              const SizedBox(width: 8),
              Text(
                'Workout ready to log',
                style: GoogleFonts.getFont('DM Sans',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent),
              ),
              const Spacer(),
              Text(
                '${draft.exercises.length} exercises',
                style: GoogleFonts.getFont('DM Sans',
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Exercise list
          ...draft.exercises.asMap().entries.map((entry) {
            final i = entry.key;
            final exercise = entry.value;
            return _ExerciseRow(
              exercise: exercise,
              exerciseIndex: i,
            );
          }),

          const SizedBox(height: 14),

          // Action buttons
          Row(
            children: [
              // Log Workout CTA
              Expanded(
                child: GestureDetector(
                  onTap: _isSubmitting ? null : _submit,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _isSubmitting
                          ? AppColors.accent.withValues(alpha: 0.5)
                          : AppColors.accent,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Center(
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : Text(
                              'Log Workout',
                              style: GoogleFonts.getFont('DM Sans',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.black),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Discard button
              GestureDetector(
                onTap: _discard,
                child: Text(
                  'Discard',
                  style: GoogleFonts.getFont('DM Sans',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Exercise Row ────────────────────────────────────────────────

class _ExerciseRow extends ConsumerWidget {
  final DraftExercise exercise;
  final int exerciseIndex;

  const _ExerciseRow({
    required this.exercise,
    required this.exerciseIndex,
  });

  String get _summary {
    if (exercise.loggingType == 'cardio') {
      final parts = <String>[];
      if (exercise.durationMins != null) {
        parts.add('${exercise.durationMins}min');
      }
      if (exercise.distanceKm != null) {
        parts.add('${exercise.distanceKm}km');
      }
      return parts.isEmpty ? 'Cardio' : parts.join(' · ');
    }

    if (exercise.sets.isEmpty) return 'No sets';

    final setCount = exercise.sets.length;
    final firstSet = exercise.sets.first;

    if (exercise.loggingType == 'timed') {
      final secs = firstSet.durationSecs ?? 0;
      return '$setCount × ${secs}s';
    }

    final reps = firstSet.reps ?? 0;
    final weight = firstSet.weightKg;
    if (weight != null && weight > 0) {
      return '$setCount × $reps @ ${weight.toStringAsFixed(1)}kg';
    }
    return '$setCount × $reps reps';
  }

  IconData get _icon {
    switch (exercise.loggingType) {
      case 'weight_reps':
      case 'weighted_bodyweight':
        return Icons.fitness_center;
      case 'bodyweight_reps':
        return Icons.accessibility_new;
      case 'timed':
        return Icons.timer_outlined;
      case 'cardio':
        return Icons.directions_run;
      default:
        return Icons.fitness_center;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: BorderRadius.circular(AppRadius.row),
      ),
      child: Row(
        children: [
          Icon(_icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exercise.name,
                  style: GoogleFonts.getFont('DM Sans',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _summary,
                  style: GoogleFonts.getFont('DM Sans',
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          // Tap to edit (opens inline editor in future iteration)
          GestureDetector(
            onTap: () => _showEditSheet(context, ref),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.edit_outlined,
                  size: 14, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditSheet(BuildContext context, WidgetRef ref) {
    final draft = ref.read(workoutDraftProvider);
    if (draft == null || exerciseIndex >= draft.exercises.length) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.cardL)),
      ),
      builder: (ctx) {
        return _ExerciseEditSheet(
          exercise: exercise,
          exerciseIndex: exerciseIndex,
          parentRef: ref,
        );
      },
    );
  }
}

// ── Exercise Edit Bottom Sheet ──────────────────────────────────

class _ExerciseEditSheet extends StatefulWidget {
  final DraftExercise exercise;
  final int exerciseIndex;
  final WidgetRef parentRef;

  const _ExerciseEditSheet({
    required this.exercise,
    required this.exerciseIndex,
    required this.parentRef,
  });

  @override
  State<_ExerciseEditSheet> createState() => _ExerciseEditSheetState();
}

class _ExerciseEditSheetState extends State<_ExerciseEditSheet> {
  late List<TextEditingController> _weightControllers;
  late List<TextEditingController> _repsControllers;

  @override
  void initState() {
    super.initState();
    _weightControllers = widget.exercise.sets
        .map((s) => TextEditingController(
            text: s.weightKg?.toStringAsFixed(1) ?? ''))
        .toList();
    _repsControllers = widget.exercise.sets
        .map((s) => TextEditingController(text: s.reps?.toString() ?? ''))
        .toList();
  }

  @override
  void dispose() {
    for (final c in _weightControllers) {
      c.dispose();
    }
    for (final c in _repsControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final notifier =
        widget.parentRef.read(workoutDraftProvider.notifier);

    for (int i = 0; i < widget.exercise.sets.length; i++) {
      final weight = double.tryParse(_weightControllers[i].text);
      final reps = int.tryParse(_repsControllers[i].text);
      notifier.updateSet(
        widget.exerciseIndex,
        i,
        DraftSet(
          weightKg: weight,
          reps: reps,
          durationSecs: widget.exercise.sets[i].durationSecs,
          distanceKm: widget.exercise.sets[i].distanceKm,
        ),
      );
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Edit ${widget.exercise.name}',
            style: GoogleFonts.getFont('DM Sans',
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 16),

          // Set rows
          ...widget.exercise.sets.asMap().entries.map((entry) {
            final i = entry.key;
            final isWeighted = widget.exercise.loggingType == 'weight_reps' ||
                widget.exercise.loggingType == 'weighted_bodyweight';

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Text(
                    'Set ${i + 1}',
                    style: GoogleFonts.getFont('DM Sans',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: 12),
                  if (isWeighted) ...[
                    Expanded(
                      child: TextField(
                        controller: _weightControllers[i],
                        keyboardType: TextInputType.number,
                        style: GoogleFonts.getFont('DM Sans',
                            fontSize: 14, color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'kg',
                          hintStyle: GoogleFonts.getFont('DM Sans',
                              color: AppColors.textDisabled),
                          filled: true,
                          fillColor: AppColors.input,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: TextField(
                      controller: _repsControllers[i],
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.getFont('DM Sans',
                          fontSize: 14, color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'reps',
                        hintStyle: GoogleFonts.getFont('DM Sans',
                            color: AppColors.textDisabled),
                        filled: true,
                        fillColor: AppColors.input,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 16),

          // Save button
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: _save,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Center(
                  child: Text(
                    'Save Changes',
                    style: GoogleFonts.getFont('DM Sans',
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Colors.black),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
