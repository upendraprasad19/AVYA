import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/shared/utils/card_share_service.dart';
import '../providers/train_provider.dart';
import '../widgets/rest_timer_modal.dart';
import '../widgets/exercise_swap_sheet.dart';
import '../widgets/workout_receipt_card.dart';

class ActiveWorkoutScreen extends ConsumerStatefulWidget {
  const ActiveWorkoutScreen({super.key});

  @override
  ConsumerState<ActiveWorkoutScreen> createState() =>
      _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends ConsumerState<ActiveWorkoutScreen> {
  @override
  Widget build(BuildContext context) {
    final data = ref.watch(activeWorkoutProvider);
    final restTimer = ref.watch(restTimerProvider);

    // No workout started
    if (data.workoutDay == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.fitness_center,
                    color: AppColors.textDisabled, size: 48),
                const SizedBox(height: 12),
                Text(
                  'No workout in progress',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => context.go('/train'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      'Go to Training',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Workout complete
    if (data.isComplete) {
      return _buildCompleteScreen(data);
    }

    final pctInt = (data.progressPercent * 100).round();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Column(
            children: [
              // Header
              _buildHeader(data),

              // Progress bar
              _buildProgressBar(data.progressPercent, pctInt),

              // Exercise cards list
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(top: 6, bottom: 10),
                  children: [
                    ...data.exercises.asMap().entries.map((entry) {
                      final exIdx = entry.key;
                      final exercise = entry.value;
                      final isDone = data.isExerciseDone(exIdx);
                      // First non-done exercise is the active one
                      final isActive = !isDone &&
                          !data.exercises
                              .asMap()
                              .entries
                              .where((e) => e.key < exIdx)
                              .any((e) => !data.isExerciseDone(e.key));

                      return _ExerciseCard(
                        exerciseIndex: exIdx,
                        exercise: exercise,
                        isDone: isDone,
                        isActive: isActive || exIdx == 0,
                        data: data,
                        onToggleSet: (setIdx) {
                          final wasChecked =
                              data.isSetChecked(exIdx, setIdx);
                          ref
                              .read(activeWorkoutProvider.notifier)
                              .toggleSet(exIdx, setIdx);

                          // If checking (not unchecking), show rest timer
                          if (!wasChecked) {
                            final nextExName = exIdx + 1 < data.exercises.length
                                ? data.exercises[exIdx + 1].name
                                : 'Last exercise!';
                            final restSecs = _parseRestSeconds(exercise.rest);
                            ref
                                .read(restTimerProvider.notifier)
                                .start(restSecs, nextExName);
                          }
                        },
                        onSwap: () => _showSwapSheet(context, ref, exIdx),
                      );
                    }),

                    // Add Exercise button
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 5),
                      child: GestureDetector(
                        onTap: () {
                          // Add a placeholder exercise
                          ref
                              .read(activeWorkoutProvider.notifier)
                              .addExercise(const ExerciseData(
                                name: 'New Exercise',
                                sets: '3',
                                reps: '10',
                                weight: '0kg',
                                rest: '60s',
                              ));
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color:
                                AppColors.accent.withValues(alpha: 0.05),
                            border: Border.all(
                              color: AppColors.accent
                                  .withValues(alpha: 0.2),
                              style: BorderStyle.solid,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(
                              '+ Add Exercise',
                              style: GoogleFonts.getFont(
                                'DM Sans',
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Finish Workout button
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: GestureDetector(
                        onTap: () => _showFinishDialog(context, ref, data),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Center(
                            child: Text(
                              '\u2713 Finish Workout',
                              style: GoogleFonts.getFont(
                                'DM Sans',
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Cancel button
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: GestureDetector(
                        onTap: () => _showCancelDialog(context, ref),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(
                              color: AppColors.red.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '\u2715 Cancel',
                              style: GoogleFonts.getFont(
                                'DM Sans',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.red,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Rest Timer Modal overlay
          if (restTimer.isActive)
            RestTimerModal(
              restTimer: restTimer,
              onSkip: () => ref.read(restTimerProvider.notifier).skip(),
              onAddTime: () =>
                  ref.read(restTimerProvider.notifier).addTime(15),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(ActiveWorkoutData data) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: const BoxDecoration(
        color: AppColors.header,
        border: Border(
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // Back button
            GestureDetector(
              onTap: () => context.go('/train'),
              child: const Padding(
                padding: EdgeInsets.only(right: 10),
                child: Icon(Icons.arrow_back_ios_new,
                    color: AppColors.textPrimary, size: 18),
              ),
            ),
            // Title + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getDayType(data.workoutDay?.name ?? ''),
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'Phase 1 \u00b7 W1 \u00b7 ${data.completedSets}/${data.totalSets} sets',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 9,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // Timer badge
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.2),
                ),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Column(
                children: [
                  Text(
                    data.timerFormatted,
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: AppColors.accent,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'ELAPSED',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 7,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar(double progress, int pctInt) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 7, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF161d28),
                borderRadius: BorderRadius.circular(2),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progress.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$pctInt%',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompleteScreen(ActiveWorkoutData data) {
    final prs = data.detectedPRs;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.green.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle,
                      color: AppColors.green, size: 48),
                ),
                const SizedBox(height: 20),
                Text(
                  'Workout Complete!',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${data.completedSets} sets logged \u00b7 ${data.timerFormatted}',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),

                // PR callout
                if (prs.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.proGoldTint,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.proGold.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'NEW PERSONAL RECORDS!',
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: AppColors.proGold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ...prs.map((pr) => Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                pr,
                                style: GoogleFonts.getFont(
                                  'DM Sans',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            )),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Share Your Session button — opens Workout Receipt sheet
                GestureDetector(
                  onTap: () => _showWorkoutReceipt(context, data),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: AppColors.accent.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'Share Your Session',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => context.go('/home'),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Center(
                      child: Text(
                        'Back to Home',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getDayType(String name) {
    if (name.contains('CHEST') || name.contains('TRICEPS')) return 'PUSH DAY';
    if (name.contains('BACK') || name.contains('BICEPS')) return 'PULL DAY';
    if (name.contains('LEG')) return 'LEG DAY';
    if (name.contains('HIIT') || name.contains('CARDIO')) return 'CARDIO';
    return name;
  }

  int _parseRestSeconds(String rest) {
    if (rest.contains('min')) {
      final mins = int.tryParse(rest.replaceAll(RegExp(r'[^0-9]'), ''));
      return (mins ?? 2) * 60;
    }
    final secs = int.tryParse(rest.replaceAll(RegExp(r'[^0-9]'), ''));
    return secs ?? 90;
  }

  void _showSwapSheet(BuildContext context, WidgetRef ref, int exerciseIndex) {
    final currentExercise =
        ref.read(activeWorkoutProvider).exercises[exerciseIndex];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => ExerciseSwapSheet(
        currentExerciseName: currentExercise.name,
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
                ),
              );
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  void _showFinishDialog(
      BuildContext context, WidgetRef ref, ActiveWorkoutData data) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Complete Workout?',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'You have logged ${data.completedSets}/${data.totalSets} sets. Finish this workout?',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Continue',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(activeWorkoutProvider.notifier).completeWorkout();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            child: Text(
              'Complete',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showWorkoutReceipt(BuildContext context, ActiveWorkoutData data) {
    final receiptData = WorkoutReceiptData.fromActiveWorkout(data);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _WorkoutReceiptSheet(receiptData: receiptData),
    );
  }

  void _showCancelDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Cancel Workout?',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'All progress will be lost.',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Keep Going',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(activeWorkoutProvider.notifier).cancelWorkout();
              context.go('/train');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            child: Text(
              'Cancel',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Exercise Card ────────────────────────────────────────────────
// Supports all 6 logging types: weight_reps, bodyweight_reps,
// weighted_bodyweight, timed, cardio, distance

class _ExerciseCard extends StatelessWidget {
  final int exerciseIndex;
  final ExerciseData exercise;
  final bool isDone;
  final bool isActive;
  final ActiveWorkoutData data;
  final ValueChanged<int> onToggleSet;
  final VoidCallback onSwap;

  const _ExerciseCard({
    required this.exerciseIndex,
    required this.exercise,
    required this.isDone,
    required this.isActive,
    required this.data,
    required this.onToggleSet,
    required this.onSwap,
  });

  String _metaText() {
    switch (exercise.loggingType) {
      case 'timed':
        return '${exercise.sets} sets \u00b7 ${exercise.reps}s \u00b7 ${exercise.rest} rest';
      case 'cardio':
        return '${exercise.reps} min \u00b7 ${exercise.rest} rest';
      case 'distance':
        return '${exercise.reps} \u00b7 ${exercise.rest} rest';
      case 'bodyweight_reps':
        return '${exercise.sets} sets \u00b7 ${exercise.reps} reps \u00b7 ${exercise.rest} rest';
      case 'weighted_bodyweight':
        return '${exercise.sets} sets \u00b7 ${exercise.reps} reps \u00b7 +${exercise.weight} \u00b7 ${exercise.rest} rest';
      default: // weight_reps
        return '${exercise.sets} sets \u00b7 ${exercise.reps} reps \u00b7 ${exercise.weight} \u00b7 ${exercise.rest} rest';
    }
  }

  @override
  Widget build(BuildContext context) {
    final numSets = int.tryParse(exercise.sets) ?? 3;
    final weightStr = exercise.weight.replaceAll('kg', '').replaceAll('BW', '');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 5),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0e1219),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? AppColors.accent.withValues(alpha: 0.35)
                : const Color(0xFF1c2535),
          ),
        ),
        child: Column(
          children: [
            // Exercise header
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 0),
              child: Row(
                children: [
                  // Number badge
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.accent.withValues(alpha: 0.15)
                          : const Color(0xFF161d28),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Center(
                      child: Text(
                        '${exerciseIndex + 1}',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isActive
                              ? AppColors.accent
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),

                  // Name + meta
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          exercise.name,
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          _metaText(),
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 9,
                            fontWeight: FontWeight.w400,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Swap or Done badge
                  if (isDone)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.green.withValues(alpha: 0.1),
                        border: Border.all(
                          color: AppColors.green.withValues(alpha: 0.25),
                        ),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        '\u2713 Done',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.green,
                        ),
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: onSwap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161d28),
                          border:
                              Border.all(color: const Color(0xFF1c2535)),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          '\u21c4 Swap',
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Sets table — driven by logging_type
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                children: [
                  _SetsTableHeader(loggingType: exercise.loggingType),
                  ...List.generate(numSets, (setIdx) {
                    final isChecked =
                        data.isSetChecked(exerciseIndex, setIdx);
                    return _SetRow(
                      setIndex: setIdx,
                      loggingType: exercise.loggingType,
                      defaultWeight: weightStr,
                      defaultReps: exercise.reps,
                      isChecked: isChecked,
                      onToggle: () => onToggleSet(setIdx),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sets Table Header ────────────────────────────────────────────
// Adapts columns based on logging_type

class _SetsTableHeader extends StatelessWidget {
  final String loggingType;

  const _SetsTableHeader({required this.loggingType});

  @override
  Widget build(BuildContext context) {
    final columns = _columnsForType(loggingType);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF161d28))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Text('SET', style: _headerStyle()),
          ),
          for (int i = 0; i < columns.length; i++) ...[
            if (i > 0) const SizedBox(width: 14),
            Expanded(child: Center(child: Text(columns[i], style: _headerStyle()))),
          ],
          const SizedBox(width: 28),
        ],
      ),
    );
  }

  List<String> _columnsForType(String type) {
    switch (type) {
      case 'bodyweight_reps':
        return ['REPS'];
      case 'weighted_bodyweight':
        return ['+KG', 'REPS'];
      case 'timed':
        return ['SECS'];
      case 'cardio':
        return ['MIN', 'KM'];
      case 'distance':
        return ['KM', 'KG'];
      default: // weight_reps
        return ['KG', 'REPS'];
    }
  }

  TextStyle _headerStyle() {
    return GoogleFonts.getFont(
      'DM Sans',
      fontSize: 8,
      fontWeight: FontWeight.w700,
      color: AppColors.textSecondary,
      letterSpacing: 0.5,
    );
  }
}

// ── Set Row ──────────────────────────────────────────────────────
// Adapts inputs based on logging_type

class _SetRow extends StatelessWidget {
  final int setIndex;
  final String loggingType;
  final String defaultWeight;
  final String defaultReps;
  final bool isChecked;
  final VoidCallback onToggle;

  const _SetRow({
    required this.setIndex,
    required this.loggingType,
    required this.defaultWeight,
    required this.defaultReps,
    required this.isChecked,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF0d1117))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Text(
              'SET ${setIndex + 1}',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          ..._buildInputsForType(),
          const SizedBox(width: 6),
          // Check button
          GestureDetector(
            onTap: onToggle,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: isChecked
                    ? AppColors.green.withValues(alpha: 0.15)
                    : const Color(0xFF161d28),
                border: Border.all(
                  color: isChecked
                      ? AppColors.green.withValues(alpha: 0.4)
                      : const Color(0xFF1c2535),
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(
                Icons.check,
                size: 11,
                color: isChecked ? AppColors.green : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildInputsForType() {
    switch (loggingType) {
      case 'bodyweight_reps':
        return [
          Expanded(child: _SetInput(placeholder: defaultReps)),
        ];
      case 'weighted_bodyweight':
        return [
          Expanded(child: _SetInput(placeholder: defaultWeight)),
          _separator(),
          Expanded(child: _SetInput(placeholder: defaultReps)),
        ];
      case 'timed':
        return [
          Expanded(child: _SetInput(placeholder: defaultReps)),
        ];
      case 'cardio':
        return [
          Expanded(child: _SetInput(placeholder: defaultReps)),
          _separator(),
          Expanded(child: _SetInput(placeholder: '0')),
        ];
      case 'distance':
        return [
          Expanded(child: _SetInput(placeholder: defaultReps)),
          _separator(),
          Expanded(child: _SetInput(placeholder: defaultWeight)),
        ];
      default: // weight_reps
        return [
          Expanded(child: _SetInput(placeholder: defaultWeight)),
          _separator(),
          Expanded(child: _SetInput(placeholder: defaultReps)),
        ];
    }
  }

  Widget _separator() {
    return SizedBox(
      width: 14,
      child: Center(
        child: Text(
          '\u00d7',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 10,
            fontWeight: FontWeight.w400,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _SetInput extends StatelessWidget {
  final String placeholder;

  const _SetInput({required this.placeholder});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: const Color(0xFF161d28),
        border: Border.all(color: const Color(0xFF1c2535)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: TextField(
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
        ],
        textAlign: TextAlign.center,
        style: GoogleFonts.getFont(
          'DM Sans',
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: placeholder,
          hintStyle: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: AppColors.textDisabled,
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          isDense: true,
        ),
      ),
    );
  }
}

// ── Workout Receipt Bottom Sheet ─────────────────────────────────

class _WorkoutReceiptSheet extends StatefulWidget {
  final WorkoutReceiptData receiptData;

  const _WorkoutReceiptSheet({required this.receiptData});

  @override
  State<_WorkoutReceiptSheet> createState() => _WorkoutReceiptSheetState();
}

class _WorkoutReceiptSheetState extends State<_WorkoutReceiptSheet> {
  final _cardKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The shareable card
            WorkoutReceiptCard(
              data: widget.receiptData,
              repaintKey: _cardKey,
            ),
            const SizedBox(height: 16),

            // Share button
            GestureDetector(
              onTap: () async {
                await CardShareService.captureAndShare(
                  _cardKey,
                  filename: 'icanbefitter_workout.png',
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Center(
                  child: Text(
                    'Share to Instagram / WhatsApp',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Close
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Close',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
