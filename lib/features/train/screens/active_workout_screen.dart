import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import '../providers/train_provider.dart';
import '../widgets/create_custom_exercise_sheet.dart';
import '../widgets/exercise_swap_sheet.dart';
import '../widgets/set_input_row.dart';
import '../widgets/workout_receipt_card.dart';
import '../widgets/workout_receipt_sheet.dart';

class ActiveWorkoutScreen extends ConsumerStatefulWidget {
  const ActiveWorkoutScreen({super.key});

  @override
  ConsumerState<ActiveWorkoutScreen> createState() =>
      _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends ConsumerState<ActiveWorkoutScreen> {
  final ScrollController _scrollController = ScrollController();
  /// Keyed by exercise NAME so the GlobalKey follows the exercise across
  /// index changes (e.g. after another exercise is removed).
  final Map<String, GlobalKey> _exerciseKeys = {};
  bool _hasShownWarmUpHint = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Scroll to the exercise at [exerciseIndex] with animation.
  void _scrollToExercise(int exerciseIndex) {
    final exercises = ref.read(activeWorkoutProvider).exercises;
    if (exerciseIndex < 0 || exerciseIndex >= exercises.length) return;
    final key = _exerciseKeys[exercises[exerciseIndex].name];
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
    ref.watch(restTimerProvider);

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
                    // Warm-up section (collapsible)
                    if (data.workoutDay?.warmup.isNotEmpty == true)
                      _WarmupCooldownSection(
                        title: 'WARM-UP',
                        icon: Icons.local_fire_department_rounded,
                        color: AppColors.orange,
                        exercises: data.workoutDay!.warmup,
                        initiallyExpanded: !data.isComplete,
                      ),

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

                      // Ensure a GlobalKey exists for this exercise (keyed by name)
                      _exerciseKeys.putIfAbsent(exercise.name, () => GlobalKey());

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
                        key: _exerciseKeys[exercise.name],
                        children: [
                          ?supersetLabel,
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

                              // If checking (not unchecking), smart-scroll to superset partner
                              if (!wasChecked) {
                                final updatedData = ref.read(activeWorkoutProvider);
                                if (updatedData.isExerciseDone(exIdx) && isInSuperset) {
                                  final partners = updatedData.getSupersetPartners(exIdx);
                                  for (final partnerIdx in partners) {
                                    if (!updatedData.isExerciseDone(partnerIdx)) {
                                      Future.delayed(const Duration(milliseconds: 200), () {
                                        _scrollToExercise(partnerIdx);
                                      });
                                      return;
                                    }
                                  }
                                }
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
                                      side: BorderSide(color: AppColors.orange.withValues(alpha: 0.3)),
                                    ),
                                    content: Text(
                                      'Warm-up set \u2014 not counted in volume',
                                      style: GoogleFonts.getFont(
                                        'DM Sans',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.orange,
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

                    // Cool-down section (collapsible)
                    if (data.workoutDay?.cooldown.isNotEmpty == true)
                      _WarmupCooldownSection(
                        title: 'COOL-DOWN',
                        icon: Icons.air_rounded,
                        color: AppColors.blue,
                        exercises: data.workoutDay!.cooldown,
                        initiallyExpanded: false,
                      ),

                    // Add Exercise button — disabled in review mode (already saved)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 5),
                      child: GestureDetector(
                        onTap: data.isSaved
                            ? null
                            : () => _showExercisePickerSheet(context, ref),
                        child: Opacity(
                          opacity: data.isSaved ? 0.3 : 1.0,
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
                    ),

                    // Finish Workout button — disabled if already saved (review mode)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: GestureDetector(
                        onTap: data.isSaved
                            ? null
                            : () => _showFinishDialog(context, ref, data),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          decoration: BoxDecoration(
                            color: data.isSaved
                                ? AppColors.accent.withValues(alpha: 0.4)
                                : AppColors.accent,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Center(
                            child: Text(
                              data.isSaved ? '\u2713 Already Saved' : '\u2713 Finish Workout',
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

          // Rest timer removed — users found the auto-popup disruptive.
          // Timer infrastructure kept in provider for future opt-in use.
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
                    '${data.completedSets}/${data.totalSets} sets${data.liveVolumeKg > 0 ? ' \u00b7 ${data.liveVolumeKg.toStringAsFixed(0)}kg volume' : ''}',
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
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => ref.read(activeWorkoutProvider.notifier).reopenWorkout(),
                  child: Text(
                    'Review Workout',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.accent,
                    ),
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
                const SizedBox(height: AppSpacing.inlineGap),

                // Share as Video — hidden until Remotion/Lambda infra is live
                // _buildVideoShareRow(data),

                GestureDetector(
                  onTap: () {
                    ref.read(activeWorkoutProvider.notifier).cancelWorkout();
                    context.go('/train');
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Center(
                      child: Text(
                        'Back to Workouts',
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

  // Video share feature deferred — see CLAUDE.md §10.

  String _getDayType(String name) {
    if (name.contains('CHEST') || name.contains('TRICEPS')) return 'PUSH DAY';
    if (name.contains('BACK') || name.contains('BICEPS')) return 'PULL DAY';
    if (name.contains('LEG')) return 'LEG DAY';
    if (name.contains('HIIT') || name.contains('CARDIO')) return 'CARDIO';
    return name;
  }

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
                      exerciseData['exercise_type'] as String? ?? 'isolation',
                  category: exerciseData['category'] as String? ?? '',
                  equipmentNeeded: (exerciseData['equipment_needed'] as List?)
                          ?.cast<String>() ??
                      [],
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
          Navigator.of(ctx).pop();
        },
        onDelete: canDelete
            ? () => ref.read(activeWorkoutProvider.notifier).removeExercise(exerciseIndex)
            : null,
      ),
    );
  }

  void _showFinishDialog(
      BuildContext context, WidgetRef ref, ActiveWorkoutData data) {
    // Pre-fill with current elapsed seconds — user can edit before confirming.
    final mins = data.elapsedSeconds ~/ 60;
    final secs = data.elapsedSeconds % 60;
    final minCtrl = TextEditingController(text: mins.toString());
    final secCtrl = TextEditingController(text: secs.toString().padLeft(2, '0'));

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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${data.completedSets}/${data.totalSets} sets logged',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'DURATION',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                // Minutes field
                SizedBox(
                  width: 56,
                  child: TextField(
                    controller: minCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppColors.accent,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.input,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            BorderSide(color: AppColors.accent, width: 1.5),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    ':',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                // Seconds field
                SizedBox(
                  width: 56,
                  child: TextField(
                    controller: secCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppColors.accent,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.input,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            BorderSide(color: AppColors.accent, width: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'min : sec',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
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
              // Apply user-edited duration before completing
              final editedMins = int.tryParse(minCtrl.text) ?? mins;
              final editedSecs =
                  (int.tryParse(secCtrl.text) ?? secs).clamp(0, 59);
              final totalSeconds = editedMins * 60 + editedSecs;
              ref
                  .read(activeWorkoutProvider.notifier)
                  .setElapsedSeconds(totalSeconds);
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
    WorkoutReceiptSheet.show(context, receiptData);
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
    final exercise = widget.exercise;
    final lastPerf = ref.read(lastPerformanceProvider(exercise.name));

    // Reps: prefer last session's reps, then parse range to midpoint, then default 8
    final String repsValue;
    if (lastPerf.lastReps != null && lastPerf.lastReps! > 0) {
      repsValue = lastPerf.lastReps.toString();
    } else {
      repsValue = _parseRepsMidpoint(exercise.reps).toString();
    }

    // Weight: prefer last session's weight for weight-based exercises
    final String weightValue;
    if (['weight_reps', 'weighted_bodyweight'].contains(exercise.loggingType) &&
        lastPerf.lastWeight != null &&
        lastPerf.lastWeight! > 0) {
      // Show clean number: strip trailing .0
      final w = lastPerf.lastWeight!;
      weightValue = w == w.roundToDouble() ? w.toInt().toString() : w.toString();
    } else {
      final raw = exercise.weight.replaceAll('kg', '').replaceAll('BW', '').trim();
      weightValue = (raw != '0' && raw.isNotEmpty) ? raw : '';
    }

    _weightControllers = List.generate(n, (_) => TextEditingController(text: weightValue));
    _repsControllers = List.generate(n, (_) => TextEditingController(text: repsValue));
    _durationControllers = List.generate(n, (_) => TextEditingController(text: repsValue));
    _distanceControllers = List.generate(n, (_) => TextEditingController());

    // Restore any values already captured in the provider (e.g. after widget rebuild).
    // This prevents controller text from resetting to defaults when Riverpod state changes.
    final savedValues = ref.read(activeWorkoutProvider).setInputValues;
    for (int s = 0; s < n; s++) {
      final captured = savedValues['${widget.exerciseIndex}-$s'];
      if (captured == null) continue;
      if (captured.weight != null) {
        final w = captured.weight!;
        _weightControllers[s].text =
            w == w.roundToDouble() ? w.toInt().toString() : w.toString();
      }
      if (captured.reps != null) {
        _repsControllers[s].text = captured.reps.toString();
      }
      if (captured.durationSeconds != null) {
        _durationControllers[s].text = captured.durationSeconds.toString();
      }
      if (captured.distanceKm != null) {
        _distanceControllers[s].text = captured.distanceKm.toString();
      }
    }

    // Pre-seed provider state with controller values so that the receipt card
    // and exercise logger have correct data even if the user checks a set
    // without editing the pre-filled weight/reps fields.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final n = _weightControllers.length;
      for (int s = 0; s < n; s++) {
        _captureSetValues(s);
      }
    });
  }

  /// Parse a reps string like "6-10" to its midpoint (8), or "10" to 10.
  static int _parseRepsMidpoint(String repsStr) {
    if (repsStr.contains('-')) {
      final parts = repsStr.split('-');
      final low = int.tryParse(parts[0].trim()) ?? 8;
      final high = int.tryParse(parts[1].trim()) ?? 12;
      return ((low + high) / 2).round();
    }
    return int.tryParse(repsStr) ?? 8;
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

  /// Returns an error message if required fields are empty, or null if valid.
  String? _validateSetInputs(int setIdx) {
    switch (widget.exercise.loggingType) {
      case 'weight_reps':
        final weight = double.tryParse(_weightControllers[setIdx].text) ?? 0;
        final reps = int.tryParse(_repsControllers[setIdx].text) ?? 0;
        if (weight <= 0 || reps <= 0) {
          return 'Enter weight and reps before marking complete';
        }
        return null;
      case 'bodyweight_reps':
        final reps = int.tryParse(_repsControllers[setIdx].text) ?? 0;
        if (reps <= 0) return 'Enter reps before marking complete';
        return null;
      case 'weighted_bodyweight':
        final reps = int.tryParse(_repsControllers[setIdx].text) ?? 0;
        if (reps <= 0) return 'Enter reps before marking complete';
        return null;
      case 'timed':
        final duration = int.tryParse(_durationControllers[setIdx].text) ?? 0;
        if (duration <= 0) return 'Enter duration before marking complete';
        return null;
      case 'cardio':
        final duration = int.tryParse(_durationControllers[setIdx].text) ?? 0;
        if (duration <= 0) return 'Enter duration before marking complete';
        return null;
      case 'distance':
        final distance = double.tryParse(_distanceControllers[setIdx].text) ?? 0;
        if (distance <= 0) return 'Enter distance before marking complete';
        return null;
      default:
        return null;
    }
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

  /// Build the table header labels based on logging type.
  List<Widget> _tableHeaderLabels() {
    switch (widget.exercise.loggingType) {
      case 'bodyweight_reps':
        return [
          const SizedBox(width: 28), // set badge
          const SizedBox(width: 8),
          Expanded(child: Center(child: Text('REPS', style: GoogleFonts.getFont('DM Sans', fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 1)))),
          const SizedBox(width: 6),
          const SizedBox(width: 28), // checkbox
        ];
      case 'timed':
        return [
          const SizedBox(width: 28),
          const SizedBox(width: 8),
          Expanded(child: Center(child: Text('SEC', style: GoogleFonts.getFont('DM Sans', fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 1)))),
          const SizedBox(width: 6),
          const SizedBox(width: 28),
        ];
      case 'cardio':
        return [
          const SizedBox(width: 28),
          const SizedBox(width: 8),
          Expanded(child: Center(child: Text('MIN', style: GoogleFonts.getFont('DM Sans', fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 1)))),
          const SizedBox(width: 6),
          Expanded(child: Center(child: Text('KM', style: GoogleFonts.getFont('DM Sans', fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 1)))),
          const SizedBox(width: 6),
          const SizedBox(width: 28),
        ];
      case 'distance':
        return [
          const SizedBox(width: 28),
          const SizedBox(width: 8),
          Expanded(child: Center(child: Text('KM', style: GoogleFonts.getFont('DM Sans', fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 1)))),
          const SizedBox(width: 6),
          Expanded(child: Center(child: Text('KG', style: GoogleFonts.getFont('DM Sans', fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 1)))),
          const SizedBox(width: 6),
          const SizedBox(width: 28),
        ];
      default: // weight_reps, weighted_bodyweight
        return [
          const SizedBox(width: 28),
          const SizedBox(width: 8),
          Expanded(child: Center(child: Text('KG', style: GoogleFonts.getFont('DM Sans', fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 1)))),
          const SizedBox(width: 6),
          Expanded(child: Center(child: Text('REPS', style: GoogleFonts.getFont('DM Sans', fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 1)))),
          const SizedBox(width: 6),
          SizedBox(width: 28, child: Center(child: Text('\u2713', style: GoogleFonts.getFont('DM Sans', fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textSecondary)))),
        ];
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
    final bottomPadding = isInSuperset && !widget.isLastInSupersetGroup ? 2.0 : 4.0;

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
            borderRadius: BorderRadius.circular(14),
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
                        topLeft: Radius.circular(14),
                        bottomLeft: Radius.circular(14),
                      ),
                    ),
                  ),
                // Main card content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Exercise header row
                        GestureDetector(
                          onLongPress: widget.onLongPressHeader,
                          child: Row(
                            children: [
                              // Number badge circle
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: widget.isActive
                                      ? AppColors.accent.withValues(alpha: 0.15)
                                      : const Color(0xFF161d28),
                                  shape: BoxShape.circle,
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
                              const SizedBox(width: 10),

                              // Name + subtitle
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.exercise.name,
                                      style: GoogleFonts.getFont(
                                        'DM Sans',
                                        fontSize: 14,
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
                                        fontSize: 11,
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

                        // Last performance + suggested weight
                        Builder(builder: (_) {
                          final lastPerf = ref.watch(lastPerformanceProvider(widget.exercise.name));
                          if (!lastPerf.hasData) return const SizedBox.shrink();

                          final children = <Widget>[];

                          // "Last: 50.0kg × 10 reps" line
                          if (lastPerf.lastWeight != null && lastPerf.lastWeight! > 0) {
                            children.add(Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                children: [
                                  Icon(Icons.history, size: 10, color: AppColors.textSecondary),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Last: ${lastPerf.lastWeight!.toStringAsFixed(1)}kg \u00d7 ${lastPerf.lastReps ?? '?'} reps',
                                    style: GoogleFonts.getFont(
                                      'DM Sans',
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ));
                          }

                          // "Try: 52.5kg × 10" suggestion line
                          if (lastPerf.suggestedWeight != null && lastPerf.suggestedWeight! > 0) {
                            children.add(Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Row(
                                children: [
                                  Icon(Icons.arrow_upward, size: 10, color: AppColors.accent),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Try: ${lastPerf.suggestedWeight!.toStringAsFixed(1)}kg \u00d7 ${lastPerf.lastReps ?? widget.exercise.reps}',
                                    style: GoogleFonts.getFont(
                                      'DM Sans',
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.accent,
                                    ),
                                  ),
                                ],
                              ),
                            ));
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: children,
                          );
                        }),

                        const SizedBox(height: 8),

                        // Table header row
                        Row(children: _tableHeaderLabels()),

                        const SizedBox(height: 4),

                        // Compact set rows
                        ...List.generate(numSets, (setIdx) {
                          final isChecked =
                              widget.data.isSetChecked(widget.exerciseIndex, setIdx);
                          final isWarmUp =
                              widget.data.isSetWarmUp(widget.exerciseIndex, setIdx);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
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
                                    isChecked: isChecked,
                                    onToggleWarmUp: () => widget.onToggleWarmUp(setIdx),
                                    onCheck: () {
                                      // If unchecking, allow without validation
                                      final alreadyChecked = widget.data.isSetChecked(
                                          widget.exerciseIndex, setIdx);
                                      if (alreadyChecked) {
                                        _captureSetValues(setIdx);
                                        widget.onToggleSet(setIdx);
                                        return;
                                      }

                                      // Validate required fields before marking complete
                                      final validationError = _validateSetInputs(setIdx);
                                      if (validationError != null) {
                                        ScaffoldMessenger.of(context).clearSnackBars();
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            backgroundColor: AppColors.card,
                                            behavior: SnackBarBehavior.floating,
                                            duration: const Duration(milliseconds: 1500),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10),
                                              side: BorderSide(
                                                  color: AppColors.red.withValues(alpha: 0.3)),
                                            ),
                                            content: Text(
                                              validationError,
                                              style: GoogleFonts.getFont(
                                                'DM Sans',
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.red,
                                              ),
                                            ),
                                          ),
                                        );
                                        return;
                                      }

                                      _captureSetValues(setIdx);
                                      widget.onToggleSet(setIdx);
                                    },
                                  ),
                                ),
                                // Inline overload indicator after checkbox
                                if (isChecked)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: _OverloadIndicator(
                                      exerciseName: widget.exercise.name,
                                      currentWeight: double.tryParse(_weightControllers[setIdx].text) ?? 0,
                                    ),
                                  ),
                                if (!isChecked)
                                  const SizedBox(width: 18), // placeholder for alignment
                              ],
                            ),
                          );
                        }),

                        // ── Add / Remove set buttons ─────────────────
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // Remove last set (−)
                            GestureDetector(
                              onTap: numSets > 1
                                  ? () => ref
                                      .read(activeWorkoutProvider.notifier)
                                      .removeLastSet(widget.exerciseIndex)
                                  : null,
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: AppColors.input,
                                  borderRadius: BorderRadius.circular(7),
                                  border: Border.all(
                                    color: numSets > 1
                                        ? AppColors.border
                                        : AppColors.border.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.remove,
                                    size: 14,
                                    color: numSets > 1
                                        ? AppColors.textSecondary
                                        : AppColors.textDisabled,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Add set (+)
                            GestureDetector(
                              onTap: () => ref
                                  .read(activeWorkoutProvider.notifier)
                                  .addSet(widget.exerciseIndex),
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: AppColors.accent.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(7),
                                  border: Border.all(
                                    color: AppColors.accent.withValues(alpha: 0.25),
                                  ),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.add,
                                    size: 14,
                                    color: AppColors.accent,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
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

    if (currentWeight > lastWeight) {
      color = AppColors.green;
      icon = '\u2191'; // up arrow
    } else if (currentWeight == lastWeight) {
      color = AppColors.orange;
      icon = '\u2192'; // right arrow
    } else {
      color = AppColors.red;
      icon = '\u2193'; // down arrow
    }

    return Text(
      icon,
      style: GoogleFonts.getFont(
        'DM Sans',
        fontSize: 14,
        fontWeight: FontWeight.w900,
        color: color,
      ),
    );
  }
}

// ── Exercise Picker Bottom Sheet ─────────────────────────────────

class _ExercisePickerSheet extends StatefulWidget {
  final void Function(Map<String, dynamic> exerciseData) onSelect;

  const _ExercisePickerSheet({required this.onSelect});

  @override
  State<_ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<_ExercisePickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'All';
  List<Map<String, dynamic>> _allExercises = [];
  List<Map<String, dynamic>> _filtered = [];

  static const _categoryFilters = [
    'All', 'Push', 'Pull', 'Legs', 'Core', 'Cardio', 'Flexibility',
  ];

  @override
  void initState() {
    super.initState();
    _loadAllExercises();
    _searchController.addListener(_applyFilter);
  }

  void _loadAllExercises() {
    final library = ExerciseRepository.instance.getAll();
    final custom = ExerciseRepository.instance.getCustomExercises();
    _allExercises = [...library, ...custom];
    _filtered = _allExercises;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilter() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filtered = _allExercises.where((e) {
        // Category filter
        if (_selectedCategory != 'All') {
          final cat = (e['category'] as String?)?.toLowerCase() ?? '';
          if (cat != _selectedCategory.toLowerCase()) return false;
        }
        // Search filter
        if (query.isNotEmpty) {
          final name = (e['name'] as String?)?.toLowerCase() ?? '';
          if (!name.contains(query)) {
            final aliases = e['name_aliases'];
            if (aliases is List) {
              final aliasMatch = aliases.any(
                  (a) => a.toString().toLowerCase().contains(query));
              if (!aliasMatch) return false;
            } else {
              return false;
            }
          }
        }
        return true;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(
          top: BorderSide(color: AppColors.border),
          left: BorderSide(color: AppColors.border),
          right: BorderSide(color: AppColors.border),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textDisabled,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title + Create Custom button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Text(
                  'ADD EXERCISE',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () async {
                    await showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder: (_) => Padding(
                        padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).viewInsets.bottom),
                        child: CreateCustomExerciseSheet(
                          onCreated: (ex) {
                            widget.onSelect(ex);
                          },
                        ),
                      ),
                    );
                    // Refresh list in case user created and then dismissed
                    if (mounted) {
                      setState(() => _loadAllExercises());
                      _applyFilter();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add,
                            size: 12, color: AppColors.accent),
                        const SizedBox(width: 4),
                        Text(
                          'Create Custom',
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _searchController,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Search exercises...',
                hintStyle: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                ),
                prefixIcon: const Icon(Icons.search,
                    color: AppColors.textSecondary, size: 18),
                filled: true,
                fillColor: AppColors.input,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                      color: AppColors.accent.withValues(alpha: 0.5)),
                ),
              ),
            ),
          ),

          // Category filter chips
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              itemCount: _categoryFilters.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final cat = _categoryFilters[i];
                final isSelected = cat == _selectedCategory;
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedCategory = cat);
                    _applyFilter();
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.accent.withValues(alpha: 0.15)
                          : AppColors.input,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.accent.withValues(alpha: 0.4)
                            : AppColors.border,
                      ),
                    ),
                    child: Text(
                      cat,
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? AppColors.accent
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 4),

          // Exercise list
          Flexible(
            child: _filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'No exercises found',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 20),
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) {
                      final ex = _filtered[i];
                      final name = ex['name'] as String? ?? 'Unknown';
                      final category = ex['category'] as String? ?? '';
                      final muscles =
                          (ex['primary_muscles'] as List?)?.join(', ') ?? '';
                      final loggingType =
                          ex['logging_type'] as String? ?? 'weight_reps';

                      return InkWell(
                        onTap: () => widget.onSelect(ex),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom:
                                  BorderSide(color: AppColors.border, width: 0.5),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: GoogleFonts.getFont(
                                        'DM Sans',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    if (muscles.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          muscles,
                                          style: GoogleFonts.getFont(
                                            'DM Sans',
                                            fontSize: 11,
                                            fontWeight: FontWeight.w400,
                                            color: AppColors.textSecondary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Category badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.accent.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(100),
                                  border: Border.all(
                                    color:
                                        AppColors.accent.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Text(
                                  category,
                                  style: GoogleFonts.getFont(
                                    'DM Sans',
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.accent,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Logging type icon
                              Icon(
                                loggingType == 'timed'
                                    ? Icons.timer_outlined
                                    : loggingType == 'cardio'
                                        ? Icons.directions_run
                                        : Icons.fitness_center,
                                size: 14,
                                color: AppColors.textDisabled,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Warm-up / Cool-down collapsible checklist
// ══════════════════════════════════════════════════════════════════

class _WarmupCooldownSection extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<ExerciseData> exercises;
  final bool initiallyExpanded;

  const _WarmupCooldownSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.exercises,
    this.initiallyExpanded = true,
  });

  @override
  State<_WarmupCooldownSection> createState() => _WarmupCooldownSectionState();
}

class _WarmupCooldownSectionState extends State<_WarmupCooldownSection> {
  late bool _expanded;
  late List<bool> _checked;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _checked = List.filled(widget.exercises.length, false);
  }

  @override
  void didUpdateWidget(covariant _WarmupCooldownSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.exercises.length != _checked.length) {
      _checked = List.filled(widget.exercises.length, false);
    }
  }

  int get _checkedCount => _checked.where((c) => c).length;
  bool get _allDone => _checkedCount == widget.exercises.length;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: widget.color.withValues(alpha: _allDone ? 0.3 : 0.12),
          ),
        ),
        child: Column(
          children: [
            // Header row (tappable to expand/collapse)
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(widget.icon, size: 16, color: widget.color),
                    const SizedBox(width: 8),
                    Text(
                      widget.title,
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: widget.color,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_checkedCount > 0)
                      Text(
                        '$_checkedCount/${widget.exercises.length}',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: widget.color.withValues(alpha: 0.6),
                        ),
                      ),
                    const Spacer(),
                    if (_allDone)
                      Icon(Icons.check_circle, size: 16, color: widget.color)
                    else
                      Icon(
                        _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 18,
                        color: widget.color.withValues(alpha: 0.5),
                      ),
                  ],
                ),
              ),
            ),

            // Exercise rows (collapsible)
            if (_expanded)
              ...widget.exercises.asMap().entries.map((entry) {
                final idx = entry.key;
                final ex = entry.value;
                final done = _checked[idx];

                // Format duration/reps
                String detail;
                if (ex.loggingType == 'timed') {
                  final raw = ex.reps.replaceAll('s', '');
                  final secs = int.tryParse(raw) ?? 0;
                  detail = secs >= 60 ? '${secs ~/ 60} min' : '${secs}s';
                } else {
                  detail = '${ex.sets} \u00d7 ${ex.reps}';
                }

                return GestureDetector(
                  onTap: () => setState(() => _checked[idx] = !_checked[idx]),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                    child: Row(
                      children: [
                        Icon(
                          done ? Icons.check_circle : Icons.circle_outlined,
                          size: 18,
                          color: done
                              ? widget.color
                              : widget.color.withValues(alpha: 0.3),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            ex.name,
                            style: GoogleFonts.getFont(
                              'DM Sans',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: done
                                  ? AppColors.textSecondary
                                  : AppColors.textPrimary,
                              decoration: done ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                        Text(
                          detail,
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            if (_expanded) const SizedBox(height: 2),
          ],
        ),
      ),
    );
  }
}

