import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/shared/utils/card_share_service.dart';
import '../providers/train_provider.dart';
import '../widgets/rest_timer_modal.dart';
import '../widgets/exercise_swap_sheet.dart';
import '../widgets/set_input_row.dart';
import '../widgets/workout_receipt_card.dart';

class ActiveWorkoutScreen extends ConsumerStatefulWidget {
  const ActiveWorkoutScreen({super.key});

  @override
  ConsumerState<ActiveWorkoutScreen> createState() =>
      _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends ConsumerState<ActiveWorkoutScreen> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _exerciseKeys = {};
  bool _hasShownWarmUpHint = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Scroll to the exercise at [exerciseIndex] with animation.
  void _scrollToExercise(int exerciseIndex) {
    final key = _exerciseKeys[exerciseIndex];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        alignment: 0.1,
      );
    }
  }

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

              // Superset group mode floating chip
              if (data.isSupersetGroupMode)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: AppColors.accent.withValues(alpha: 0.1),
                  child: Row(
                    children: [
                      Icon(Icons.link, size: 14, color: AppColors.accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Tap another exercise to create superset',
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => ref.read(activeWorkoutProvider.notifier).cancelSupersetGrouping(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.getFont(
                              'DM Sans',
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.red,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Exercise cards list
              Expanded(
                child: ListView(
                  controller: _scrollController,
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

                      // Ensure a GlobalKey exists for this exercise
                      _exerciseKeys.putIfAbsent(exIdx, () => GlobalKey());

                      // Superset grouping visual logic
                      final supersetGroup = exercise.supersetGroup;
                      final isInSuperset = supersetGroup != null;
                      final isFirstInGroup = isInSuperset &&
                          (exIdx == 0 || data.exercises[exIdx - 1].supersetGroup != supersetGroup);
                      final isLastInGroup = isInSuperset &&
                          (exIdx == data.exercises.length - 1 ||
                              data.exercises[exIdx + 1].supersetGroup != supersetGroup);

                      // Build superset label between paired exercises
                      Widget? supersetLabel;
                      if (isInSuperset && !isFirstInGroup) {
                        final groupColor = ActiveWorkoutData.supersetColor(supersetGroup);
                        supersetLabel = Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
                          child: Row(
                            children: [
                              const SizedBox(width: 4),
                              Container(
                                width: 3,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: groupColor,
                                  borderRadius: BorderRadius.circular(1.5),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'SUPERSET',
                                style: GoogleFonts.getFont(
                                  'DM Sans',
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                  color: groupColor.withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return Column(
                        key: _exerciseKeys[exIdx],
                        children: [
                          if (supersetLabel != null) supersetLabel,
                          _ExerciseCard(
                            exerciseIndex: exIdx,
                            exercise: exercise,
                            isDone: isDone,
                            isActive: isActive || exIdx == 0,
                            data: data,
                            supersetGroup: supersetGroup,
                            isFirstInSupersetGroup: isFirstInGroup,
                            isLastInSupersetGroup: isLastInGroup,
                            isInSupersetGroupMode: data.isSupersetGroupMode,
                            isGroupModeSource: data.supersetGroupingSourceIndex == exIdx,
                            onToggleSet: (setIdx) {
                              final wasChecked =
                                  data.isSetChecked(exIdx, setIdx);
                              ref
                                  .read(activeWorkoutProvider.notifier)
                                  .toggleSet(exIdx, setIdx);

                              // If checking (not unchecking)
                              if (!wasChecked) {
                                // Smart scroll: if superset partner exists and current exercise is now done
                                final updatedData = ref.read(activeWorkoutProvider);
                                if (updatedData.isExerciseDone(exIdx) && isInSuperset) {
                                  final partners = updatedData.getSupersetPartners(exIdx);
                                  for (final partnerIdx in partners) {
                                    if (!updatedData.isExerciseDone(partnerIdx)) {
                                      // Delay scroll slightly for state to settle
                                      Future.delayed(const Duration(milliseconds: 200), () {
                                        _scrollToExercise(partnerIdx);
                                      });
                                      // Only start rest timer after ALL superset exercises are done
                                      return;
                                    }
                                  }
                                }

                                // Normal rest timer behavior
                                final nextExName = exIdx + 1 < data.exercises.length
                                    ? data.exercises[exIdx + 1].name
                                    : 'Last exercise!';
                                final restSecs = _parseRestSeconds(exercise.rest);
                                ref
                                    .read(restTimerProvider.notifier)
                                    .start(restSecs, nextExName);
                              }
                            },
                            onToggleWarmUp: (setIdx) {
                              ref.read(activeWorkoutProvider.notifier).toggleWarmUp(exIdx, setIdx);
                              if (!_hasShownWarmUpHint) {
                                _hasShownWarmUpHint = true;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: AppColors.card,
                                    behavior: SnackBarBehavior.floating,
                                    duration: const Duration(seconds: 3),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: BorderSide(color: const Color(0xFFf97316).withValues(alpha: 0.3)),
                                    ),
                                    content: Text(
                                      'Warm-up set \u2014 not counted in volume',
                                      style: GoogleFonts.getFont(
                                        'DM Sans',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFFf97316),
                                      ),
                                    ),
                                  ),
                                );
                              }
                            },
                            onSwap: () => _showSwapSheet(context, ref, exIdx),
                            onLongPressHeader: () {
                              if (data.isSupersetGroupMode) {
                                ref.read(activeWorkoutProvider.notifier).pairSuperset(exIdx);
                              } else {
                                ref.read(activeWorkoutProvider.notifier).startSupersetGrouping(exIdx);
                              }
                            },
                          ),
                        ],
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

class _ExerciseCard extends ConsumerStatefulWidget {
  final int exerciseIndex;
  final ExerciseData exercise;
  final bool isDone;
  final bool isActive;
  final ActiveWorkoutData data;
  final int? supersetGroup;
  final bool isFirstInSupersetGroup;
  final bool isLastInSupersetGroup;
  final bool isInSupersetGroupMode;
  final bool isGroupModeSource;
  final ValueChanged<int> onToggleSet;
  final ValueChanged<int> onToggleWarmUp;
  final VoidCallback onSwap;
  final VoidCallback onLongPressHeader;

  const _ExerciseCard({
    required this.exerciseIndex,
    required this.exercise,
    required this.isDone,
    required this.isActive,
    required this.data,
    this.supersetGroup,
    this.isFirstInSupersetGroup = false,
    this.isLastInSupersetGroup = false,
    this.isInSupersetGroupMode = false,
    this.isGroupModeSource = false,
    required this.onToggleSet,
    required this.onToggleWarmUp,
    required this.onSwap,
    required this.onLongPressHeader,
  });

  @override
  ConsumerState<_ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends ConsumerState<_ExerciseCard> {
  // Per-set controllers: index by set number
  late List<TextEditingController> _weightControllers;
  late List<TextEditingController> _repsControllers;
  late List<TextEditingController> _durationControllers;
  late List<TextEditingController> _distanceControllers;

  int get _numSets => int.tryParse(widget.exercise.sets) ?? 3;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    final n = _numSets;
    final weightDefault =
        widget.exercise.weight.replaceAll('kg', '').replaceAll('BW', '');
    final repsDefault = widget.exercise.reps;

    _weightControllers = List.generate(n, (_) => TextEditingController(text: weightDefault != '0' ? weightDefault : ''));
    _repsControllers = List.generate(n, (_) => TextEditingController(text: repsDefault));
    _durationControllers = List.generate(n, (_) => TextEditingController(text: repsDefault));
    _distanceControllers = List.generate(n, (_) => TextEditingController());
  }

  @override
  void didUpdateWidget(covariant _ExerciseCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newNumSets = int.tryParse(widget.exercise.sets) ?? 3;
    if (newNumSets != _weightControllers.length ||
        oldWidget.exercise.name != widget.exercise.name) {
      _disposeControllers();
      _initControllers();
    }
  }

  void _disposeControllers() {
    for (final c in _weightControllers) { c.dispose(); }
    for (final c in _repsControllers) { c.dispose(); }
    for (final c in _durationControllers) { c.dispose(); }
    for (final c in _distanceControllers) { c.dispose(); }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  /// Capture current input values and record them into the provider.
  void _captureSetValues(int setIdx) {
    ref.read(activeWorkoutProvider.notifier).recordSetValues(
      widget.exerciseIndex,
      setIdx,
      SetInputValues(
        weight: double.tryParse(_weightControllers[setIdx].text),
        reps: int.tryParse(_repsControllers[setIdx].text),
        durationSeconds: int.tryParse(_durationControllers[setIdx].text),
        distanceKm: double.tryParse(_distanceControllers[setIdx].text),
      ),
    );
  }

  String _metaText() {
    switch (widget.exercise.loggingType) {
      case 'timed':
        return '${widget.exercise.sets} sets \u00b7 ${widget.exercise.reps}s \u00b7 ${widget.exercise.rest} rest';
      case 'cardio':
        return '${widget.exercise.reps} min \u00b7 ${widget.exercise.rest} rest';
      case 'distance':
        return '${widget.exercise.reps} \u00b7 ${widget.exercise.rest} rest';
      case 'bodyweight_reps':
        return '${widget.exercise.sets} sets \u00b7 ${widget.exercise.reps} reps \u00b7 ${widget.exercise.rest} rest';
      case 'weighted_bodyweight':
        return '${widget.exercise.sets} sets \u00b7 ${widget.exercise.reps} reps \u00b7 +${widget.exercise.weight} \u00b7 ${widget.exercise.rest} rest';
      default: // weight_reps
        return '${widget.exercise.sets} sets \u00b7 ${widget.exercise.reps} reps \u00b7 ${widget.exercise.weight} \u00b7 ${widget.exercise.rest} rest';
    }
  }

  @override
  Widget build(BuildContext context) {
    final numSets = _numSets;
    final isInSuperset = widget.supersetGroup != null;
    final supersetColor = isInSuperset
        ? ActiveWorkoutData.supersetColor(widget.supersetGroup!)
        : null;
    // Reduce spacing between superset partners
    final bottomPadding = isInSuperset && !widget.isLastInSupersetGroup ? 2.0 : 5.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
      child: GestureDetector(
        onTap: widget.isInSupersetGroupMode ? widget.onLongPressHeader : null,
        child: Container(
          decoration: BoxDecoration(
            color: widget.isGroupModeSource
                ? AppColors.accent.withValues(alpha: 0.08)
                : widget.isInSupersetGroupMode
                    ? AppColors.accent.withValues(alpha: 0.03)
                    : const Color(0xFF0e1219),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isGroupModeSource
                  ? AppColors.accent.withValues(alpha: 0.5)
                  : widget.isInSupersetGroupMode
                      ? AppColors.accent.withValues(alpha: 0.2)
                      : widget.isActive
                          ? AppColors.accent.withValues(alpha: 0.35)
                          : const Color(0xFF1c2535),
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Superset colored left bar
                if (isInSuperset)
                  Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: supersetColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        bottomLeft: Radius.circular(12),
                      ),
                    ),
                  ),
                // Main card content
                Expanded(
                  child: Column(
                  children: [
                    // Exercise header
                    GestureDetector(
                      onLongPress: widget.onLongPressHeader,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 9, 12, 0),
                        child: Row(
                          children: [
                            // Number badge
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: widget.isActive
                                    ? AppColors.accent.withValues(alpha: 0.15)
                                    : const Color(0xFF161d28),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Center(
                                child: Text(
                                  '${widget.exerciseIndex + 1}',
                                  style: GoogleFonts.getFont(
                                    'DM Sans',
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: widget.isActive
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
                                    widget.exercise.name,
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
                            if (widget.isDone)
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
                                onTap: widget.onSwap,
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
                    ),

            // Suggested weight line (above sets)
            Builder(builder: (_) {
              final lastPerf = ref.watch(lastPerformanceProvider(widget.exercise.name));
              if (lastPerf.suggestedWeight != null && lastPerf.suggestedWeight! > 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                  child: Row(
                    children: [
                      Icon(Icons.arrow_upward, size: 10, color: AppColors.accent),
                      const SizedBox(width: 3),
                      Text(
                        'Suggested: ${lastPerf.suggestedWeight!.toStringAsFixed(1)}kg \u00d7 ${lastPerf.lastReps ?? widget.exercise.reps}',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            }),

                    // Sets with SetInputRow + checkbox — driven by logging_type
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                      child: Column(
                        children: List.generate(numSets, (setIdx) {
                          final isChecked =
                              widget.data.isSetChecked(widget.exerciseIndex, setIdx);
                          final isWarmUp =
                              widget.data.isSetWarmUp(widget.exerciseIndex, setIdx);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // SetInputRow from set_input_row.dart
                                Expanded(
                                  child: SetInputRow(
                                    loggingType: widget.exercise.loggingType,
                                    weightController: _weightControllers[setIdx],
                                    repsController: _repsControllers[setIdx],
                                    durationController: _durationControllers[setIdx],
                                    distanceController: _distanceControllers[setIdx],
                                    setNumber: setIdx + 1,
                                    isWarmUp: isWarmUp,
                                    isCompleted: isChecked,
                                    onToggleWarmUp: () => widget.onToggleWarmUp(setIdx),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                // Overload indicator (only shows when set is checked)
                                if (isChecked)
                                  _OverloadIndicator(
                                    exerciseName: widget.exercise.name,
                                    currentWeight: double.tryParse(_weightControllers[setIdx].text) ?? 0,
                                  ),
                                const SizedBox(width: 4),
                                // Checkbox to mark set done
                                Padding(
                                  padding: const EdgeInsets.only(top: 14),
                                  child: GestureDetector(
                                    onTap: () {
                                      _captureSetValues(setIdx);
                                      widget.onToggleSet(setIdx);
                                    },
                                    child: Container(
                                      width: 32,
                                      height: 32,
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
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        Icons.check,
                                        size: 16,
                                        color: isChecked
                                            ? AppColors.green
                                            : AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}

// Old _SetsTableHeader, _SetRow, and _SetInput removed.
// Set inputs are now handled by SetInputRow from set_input_row.dart
// with TextEditingControllers managed by _ExerciseCardState.

// ── Overload Indicator ───────────────────────────────────────────
/// Shows a small indicator comparing current weight to last performance.
/// Green "PR!" if higher, orange arrow if same, red "Recovery" if lower.
class _OverloadIndicator extends ConsumerWidget {
  final String exerciseName;
  final double currentWeight;

  const _OverloadIndicator({
    required this.exerciseName,
    required this.currentWeight,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastPerf = ref.watch(lastPerformanceProvider(exerciseName));
    final lastWeight = lastPerf.lastWeight;

    // No history or no weight entered — don't show indicator
    if (lastWeight == null || lastWeight <= 0 || currentWeight <= 0) {
      return const SizedBox.shrink();
    }

    final Color color;
    final String icon;
    final String? label;

    if (currentWeight > lastWeight) {
      color = AppColors.green;
      icon = '\u2191'; // up arrow
      label = 'PR!';
    } else if (currentWeight == lastWeight) {
      color = AppColors.orange;
      icon = '\u2192'; // right arrow
      label = null;
    } else {
      color = AppColors.red;
      icon = '\u2193'; // down arrow
      label = 'Recovery';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            icon,
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          if (label != null) ...[
            const SizedBox(width: 2),
            Text(
              label,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ],
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
