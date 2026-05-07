import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import '../providers/train_provider.dart';
import '../services/active_workout_persistence.dart';
import '../../home/providers/home_provider.dart';
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

  /// Bug #15b — Index of the user-focused (manually expanded) exercise card.
  /// `null` = no manual override → fall back to "first non-done" computed in
  /// [_effectiveFocusedIndex]. When the focused exercise becomes done, the
  /// fallback automatically advances to the next non-done exercise.
  int? _focusedExerciseIndex;

  @override
  void dispose() {
    _scrollController.dispose();
    // A7: clear mid-workout snapshot on any screen exit (back-button, system
    // nav, or auto-dismiss). Completion/cancellation paths also call this
    // explicitly so the AI coach sees null state immediately rather than
    // waiting for the next app lifecycle event.
    ActiveWorkoutPersistence.clearState();
    super.dispose();
  }

  /// Bug #15b — Resolves which exercise card should be expanded right now.
  /// Manual focus wins unconditionally (including Done exercises, so the user
  /// can tap back to review/edit logged values). When no manual override is
  /// set we fall back to the first non-done exercise from the start of the
  /// list (NOT from focused+1) so that any earlier skipped exercise gets
  /// surfaced again on completion.
  int _effectiveFocusedIndex(ActiveWorkoutData data) {
    final manual = _focusedExerciseIndex;
    if (manual != null &&
        manual >= 0 &&
        manual < data.exercises.length) {
      return manual;
    }
    for (int i = 0; i < data.exercises.length; i++) {
      if (!data.isExerciseDone(i)) return i;
    }
    // All exercises complete — keep the last card expanded so the screen
    // never has zero expanded cards.
    return data.exercises.isEmpty ? 0 : data.exercises.length - 1;
  }

  /// Bug #15b — Whether the card at [exIdx] should render its set inputs.
  /// Returns `true` for the focused exercise AND for any superset partner of
  /// the focused exercise (so paired members expand together).
  bool _isExerciseExpanded(int exIdx, ActiveWorkoutData data) {
    if (exIdx < 0 || exIdx >= data.exercises.length) return false;
    final focused = _effectiveFocusedIndex(data);
    if (exIdx == focused) return true;
    final myGroup = data.exercises[exIdx].supersetGroup;
    if (myGroup == null) return false;
    if (focused < 0 || focused >= data.exercises.length) return false;
    final focusedGroup = data.exercises[focused].supersetGroup;
    return focusedGroup != null && focusedGroup == myGroup;
  }

  /// Bug #15b — Handler for tap-to-focus on a card header. Sets the manual
  /// override and triggers a rebuild so the previously focused card collapses
  /// and the tapped one expands.
  void _focusExercise(int exIdx) {
    setState(() {
      _focusedExerciseIndex = exIdx;
    });
    // Smoothly bring the freshly focused card into view.
    Future.delayed(const Duration(milliseconds: 60), () {
      if (mounted) _scrollToExercise(exIdx);
    });
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
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.fitness_center,
                      color: AppColors.textGhost, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'No workout in progress',
                    style:
                        AppTypography.body.copyWith(color: AppColors.textDim),
                  ),
                  const SizedBox(height: 16),
                  WardButton(
                    label: 'GO TO TRAINING',
                    onPressed: () {
                      if (Navigator.canPop(context)) {
                        context.pop();
                      } else {
                        context.go('/train');
                      }
                    },
                    fullWidth: false,
                  ),
                ],
              ),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: AppColors.accentSoft,
                  child: Row(
                    children: [
                      const Icon(Icons.link,
                          size: 14, color: AppColors.accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'TAP ANOTHER EXERCISE TO CREATE SUPERSET',
                          style: AppTypography.monoXs.copyWith(
                            color: AppColors.accent,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => ref
                            .read(activeWorkoutProvider.notifier)
                            .cancelSupersetGrouping(),
                        child: const WardChip(
                          label: 'CANCEL',
                          tone: WardChipTone.bad,
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
                        color: AppColors.warn,
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

                      // Bug #15b — Only the focused exercise (and any of its
                      // superset partners) renders set inputs. All others
                      // collapse to header-only with a chevron.
                      final isExpanded = _isExerciseExpanded(exIdx, data);

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
                                style: AppTypography.monoXs.copyWith(
                                  fontSize: 8,
                                  color: groupColor.withValues(alpha: 0.8),
                                  letterSpacing: 1.8,
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
                            isExpanded: isExpanded,
                            onFocus: () => _focusExercise(exIdx),
                            onToggleSet: (setIdx) {
                              final wasChecked =
                                  data.isSetChecked(exIdx, setIdx);
                              ref
                                  .read(activeWorkoutProvider.notifier)
                                  .toggleSet(exIdx, setIdx);

                              // If checking (not unchecking) and the exercise
                              // just became Done, clear manual focus so
                              // auto-advance picks the next non-done exercise.
                              if (!wasChecked) {
                                final updatedData = ref.read(activeWorkoutProvider);
                                if (updatedData.isExerciseDone(exIdx)) {
                                  // Clear manual focus → auto-advance to next
                                  setState(() {
                                    _focusedExerciseIndex = null;
                                  });

                                  // Smart-scroll to superset partner if applicable
                                  if (isInSuperset) {
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
                                      borderRadius:
                                          BorderRadius.circular(AppRadius.sharp),
                                      side: BorderSide(
                                          color: AppColors.warn
                                              .withValues(alpha: 0.3)),
                                    ),
                                    content: Text(
                                      'Warm-up set \u2014 not counted in volume',
                                      style: AppTypography.bodySm.copyWith(
                                        color: AppColors.warn,
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
                        color: AppColors.info,
                        exercises: data.workoutDay!.cooldown,
                        initiallyExpanded: false,
                      ),

                    // Add Exercise button — disabled in review mode (already saved)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 5),
                      child: Opacity(
                        opacity: data.isSaved ? 0.3 : 1.0,
                        child: WardButton(
                          label: '+ ADD EXERCISE',
                          variant: WardButtonVariant.outline,
                          size: WardButtonSize.small,
                          onPressed: data.isSaved
                              ? null
                              : () =>
                                  _showExercisePickerSheet(context, ref),
                        ),
                      ),
                    ),

                    // Finish Workout button — disabled if already saved (review mode)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: WardButton(
                        label: data.isSaved
                            ? '✓ ALREADY SAVED'
                            : '✓ FINISH WORKOUT',
                        onPressed: data.isSaved
                            ? null
                            : () => _showFinishDialog(context, ref, data),
                      ),
                    ),

                    // Cancel button
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: WardButton(
                        label: '✕ CANCEL',
                        variant: WardButtonVariant.danger,
                        size: WardButtonSize.small,
                        onPressed: () => _showCancelDialog(context, ref),
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
        color: AppColors.bgDeep,
        border: Border(
          bottom: BorderSide(color: AppColors.line2),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // Back button
            GestureDetector(
              onTap: () {
                if (Navigator.canPop(context)) {
                  context.pop();
                } else {
                  context.go('/train');
                }
              },
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
                    _getDayType(data.workoutDay?.name ?? '').toUpperCase(),
                    style: AppTypography.mono.copyWith(
                      fontSize: 12,
                      color: AppColors.textPrimary,
                      letterSpacing: 2.5,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${data.completedSets} / ${data.totalSets} SETS${data.liveVolumeKg > 0 ? ' · ${data.liveVolumeKg.toStringAsFixed(0)}KG VOLUME' : ''}',
                    style: AppTypography.monoXs.copyWith(
                      color: AppColors.textDim,
                      letterSpacing: 1.2,
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
                color: AppColors.accentSoft,
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.27),
                ),
                borderRadius: BorderRadius.circular(AppRadius.sharp),
              ),
              child: Column(
                children: [
                  Text(
                    data.timerFormatted,
                    style: AppTypography.numeric.copyWith(
                      fontSize: 17,
                      color: AppColors.accent,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'ELAPSED',
                    style: AppTypography.monoXs.copyWith(
                      fontSize: 7,
                      color: AppColors.textDim,
                      letterSpacing: 1.5,
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
          Expanded(child: WardBar(pct: progress, height: 4)),
          const SizedBox(width: 8),
          Text(
            '$pctInt%',
            style: AppTypography.monoXs.copyWith(
              color: AppColors.accent,
              letterSpacing: 1.2,
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
                    color: AppColors.ok.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle,
                      color: AppColors.ok, size: 48),
                ),
                const SizedBox(height: 20),
                Text(
                  'Workout Complete!',
                  style: AppTypography.h1.copyWith(fontSize: 26),
                ),
                const SizedBox(height: 8),
                Text(
                  '${data.completedSets} SETS LOGGED · ${data.timerFormatted}',
                  style: AppTypography.mono.copyWith(
                    color: AppColors.textDim,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () =>
                      ref.read(activeWorkoutProvider.notifier).reopenWorkout(),
                  child: Text(
                    'REVIEW WORKOUT',
                    style: AppTypography.monoXs.copyWith(
                      color: AppColors.accent,
                      letterSpacing: 2,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.accent,
                    ),
                  ),
                ),

                // PR callout
                if (prs.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  WardCard(
                    variant: WardCardVariant.hero,
                    child: Column(
                      children: [
                        Text(
                          'NEW PERSONAL RECORDS!',
                          style: AppTypography.mono.copyWith(
                            color: AppColors.proGold,
                            letterSpacing: 2.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ...prs.map((pr) => Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                pr,
                                style:
                                    AppTypography.h3.copyWith(fontSize: 13),
                              ),
                            )),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Share Your Session button — opens Workout Receipt sheet
                WardButton(
                  label: 'SHARE YOUR SESSION',
                  variant: WardButtonVariant.outline,
                  onPressed: () => _showWorkoutReceipt(context, data),
                ),
                const SizedBox(height: AppSpacing.inlineGap),

                // Share as Video — hidden until Remotion/Lambda infra is live
                // _buildVideoShareRow(data),

                WardButton(
                  label: 'BACK TO WORKOUTS',
                  onPressed: () {
                    ref.read(activeWorkoutProvider.notifier).cancelWorkout();
                    context.go('/train');
                  },
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
                      (exerciseData['exercise_type'] is List
                          ? ((exerciseData['exercise_type'] as List).isNotEmpty
                              ? (exerciseData['exercise_type'] as List).first.toString()
                              : null)
                          : exerciseData['exercise_type'] as String?) ?? 'isolation',
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
          final equipment = (newExercise['equipment_needed'] as List?)
                  ?.cast<String>() ??
              original.equipmentNeeded;

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
                  'Swapped "${original.name}" \u2192 "$newName"',
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.line2),
        ),
        title: Text(
          'Complete Workout?',
          style: AppTypography.h2.copyWith(fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${data.completedSets}/${data.totalSets} sets logged',
              style: AppTypography.bodySm.copyWith(color: AppColors.textDim),
            ),
            const SizedBox(height: 14),
            Text(
              'DURATION',
              style: AppTypography.mono.copyWith(
                color: AppColors.textMute,
                letterSpacing: 2,
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
                    style: AppTypography.numeric.copyWith(
                      fontSize: 22,
                      color: AppColors.accent,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.bgRaise,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.sharp),
                        borderSide: const BorderSide(color: AppColors.line2),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.sharp),
                        borderSide: const BorderSide(color: AppColors.line2),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.sharp),
                        borderSide: const BorderSide(
                            color: AppColors.accent, width: 1.5),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    ':',
                    style: AppTypography.numeric.copyWith(
                      fontSize: 22,
                      color: AppColors.textDim,
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
                    style: AppTypography.numeric.copyWith(
                      fontSize: 22,
                      color: AppColors.accent,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.bgRaise,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.sharp),
                        borderSide: const BorderSide(color: AppColors.line2),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.sharp),
                        borderSide: const BorderSide(color: AppColors.line2),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.sharp),
                        borderSide: const BorderSide(
                            color: AppColors.accent, width: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'MIN : SEC',
                  style: AppTypography.monoXs.copyWith(
                    color: AppColors.textDim,
                    letterSpacing: 1.5,
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
              'CONTINUE',
              style: AppTypography.mono.copyWith(
                fontSize: 11,
                color: AppColors.textDim,
                letterSpacing: 2,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              // Apply user-edited duration before completing
              final editedMins =
                  (int.tryParse(minCtrl.text) ?? mins).clamp(0, 999);
              final editedSecs =
                  (int.tryParse(secCtrl.text) ?? secs).clamp(0, 59);
              final totalSeconds = editedMins * 60 + editedSecs;
              ref
                  .read(activeWorkoutProvider.notifier)
                  .setElapsedSeconds(totalSeconds);
              // A7: clear mid-workout state immediately on completion so
              // the AI coach snapshot reflects null (session over) right away.
              ActiveWorkoutPersistence.clearState();
              Navigator.of(ctx).pop();
              ref.read(activeWorkoutProvider.notifier).completeWorkout();
            },
            child: Text(
              'COMPLETE',
              style: AppTypography.mono.copyWith(
                fontSize: 11,
                color: AppColors.accent,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showWorkoutReceipt(BuildContext context, ActiveWorkoutData data) {
    // APK Test #12.6 — prefer the Hive-backed receipt builder when
    // [completeWorkout] has already persisted the logs. It populates
    // perSetBreakdown (giving WardSetChips real per-set chips) and
    // computes volume from the exact per-set sum the cloud projection
    // ships. Falls back to the in-memory builder when Hive somehow
    // lacks the logs (e.g. write-failure or no workoutDay date).
    final workoutDate = data.workoutDay?.date;
    WorkoutReceiptData? receiptData;
    if (workoutDate != null) {
      receiptData = WorkoutReceiptData.fromExerciseLogs(workoutDate);
    }
    receiptData ??= WorkoutReceiptData.fromActiveWorkout(data);
    WorkoutReceiptSheet.show(context, receiptData);
  }

  void _showCancelDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.line2),
        ),
        title: Text(
          'Cancel Workout?',
          style: AppTypography.h2.copyWith(fontSize: 18),
        ),
        content: Text(
          'All progress will be lost.',
          style: AppTypography.bodySm.copyWith(color: AppColors.textDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'KEEP GOING',
              style: AppTypography.mono.copyWith(
                fontSize: 11,
                color: AppColors.textDim,
                letterSpacing: 2,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              // A7: clear mid-workout state immediately on abandonment.
              ActiveWorkoutPersistence.clearState();
              Navigator.of(ctx).pop();
              ref.read(activeWorkoutProvider.notifier).cancelWorkout();
              context.go('/train');
            },
            child: Text(
              'CANCEL',
              style: AppTypography.mono.copyWith(
                fontSize: 11,
                color: AppColors.bad,
                letterSpacing: 2,
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
  /// Bug #15b — Whether this card's set inputs (and add/remove buttons) are
  /// rendered. Headers are always visible regardless.
  final bool isExpanded;
  /// Bug #15b — Tap-on-header callback to make this card the focused one.
  final VoidCallback onFocus;

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
    required this.isExpanded,
    required this.onFocus,
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
    final oldCount = int.tryParse(oldWidget.exercise.sets) ?? 3;
    final newCount = int.tryParse(widget.exercise.sets) ?? 3;

    // Exercise swap: full rebuild needed (different pre-fills, weight, reps).
    if (oldWidget.exercise.name != widget.exercise.name) {
      _disposeControllers();
      _initControllers();
      return;
    }

    // Set count unchanged: nothing to do.
    if (newCount == oldCount) return;

    if (newCount > oldCount) {
      // Append: preserve [0..oldCount-1] controllers, add new ones for the rest.
      for (var i = oldCount; i < newCount; i++) {
        _weightControllers.add(TextEditingController());
        _repsControllers.add(TextEditingController());
        _durationControllers.add(TextEditingController());
        _distanceControllers.add(TextEditingController());
      }
    } else {
      // Shrink: dispose trailing controllers from [newCount..oldCount-1].
      for (var i = oldCount - 1; i >= newCount; i--) {
        _weightControllers.removeAt(i).dispose();
        _repsControllers.removeAt(i).dispose();
        _durationControllers.removeAt(i).dispose();
        _distanceControllers.removeAt(i).dispose();
      }
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

  /// A7: Persist current mid-workout state to Hive so the AI coach snapshot
  /// reflects what the user is actively doing. Called after every set log.
  /// Uses the values from the set at [setIdx] as the most-recently-touched set.
  void _persistActiveState(int setIdx) {
    final numSets = _numSets;
    // Count completed sets (warm-up sets excluded by the provider's
    // completedSets getter, but here we capture the raw toggle state for
    // the snapshot — fine since the coach just needs approximate context).
    final completedSets = List.generate(numSets, (i) =>
        widget.data.isSetChecked(widget.exerciseIndex, i)).where((c) => c).length;

    // Weight: from the set being logged; fall back to first weight controller.
    final weightText = setIdx < _weightControllers.length
        ? _weightControllers[setIdx].text
        : _weightControllers.isNotEmpty ? _weightControllers.first.text : '';
    // Reps: prefer reps controller; fall back to duration (timed/cardio).
    final repsText = setIdx < _repsControllers.length
        ? _repsControllers[setIdx].text
        : '';
    final repsCompleted = int.tryParse(repsText) ??
        (setIdx < _durationControllers.length
            ? int.tryParse(_durationControllers[setIdx].text) ?? 0
            : 0);

    // current_set = number of sets completed so far (including the one just logged).
    // total_sets = configured set count for this exercise.
    ActiveWorkoutPersistence.writeState(
      exerciseName: widget.exercise.name,
      currentSet: completedSets.clamp(1, numSets),
      totalSets: numSets,
      weight: double.tryParse(weightText),
      repsTarget: int.tryParse(widget.exercise.reps) ??
          _parseRepsMidpoint(widget.exercise.reps),
      repsCompleted: repsCompleted,
      rpeHistory: const [], // RPE not surfaced per-set in current UI
      restRemainingSecs: null, // rest timer hidden per user feedback
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
          Expanded(child: Center(child: Text('REPS', style: AppTypography.monoXs.copyWith(color: AppColors.textDim, letterSpacing: 1.5)))),
          const SizedBox(width: 6),
          const SizedBox(width: 28), // checkbox
        ];
      case 'timed':
        return [
          const SizedBox(width: 28),
          const SizedBox(width: 8),
          Expanded(child: Center(child: Text('SEC', style: AppTypography.monoXs.copyWith(color: AppColors.textDim, letterSpacing: 1.5)))),
          const SizedBox(width: 6),
          const SizedBox(width: 28),
        ];
      case 'cardio':
        return [
          const SizedBox(width: 28),
          const SizedBox(width: 8),
          Expanded(child: Center(child: Text('MIN', style: AppTypography.monoXs.copyWith(color: AppColors.textDim, letterSpacing: 1.5)))),
          const SizedBox(width: 6),
          Expanded(child: Center(child: Text('KM', style: AppTypography.monoXs.copyWith(color: AppColors.textDim, letterSpacing: 1.5)))),
          const SizedBox(width: 6),
          const SizedBox(width: 28),
        ];
      case 'distance':
        return [
          const SizedBox(width: 28),
          const SizedBox(width: 8),
          Expanded(child: Center(child: Text('KM', style: AppTypography.monoXs.copyWith(color: AppColors.textDim, letterSpacing: 1.5)))),
          const SizedBox(width: 6),
          Expanded(child: Center(child: Text('KG', style: AppTypography.monoXs.copyWith(color: AppColors.textDim, letterSpacing: 1.5)))),
          const SizedBox(width: 6),
          const SizedBox(width: 28),
        ];
      default: // weight_reps, weighted_bodyweight
        return [
          const SizedBox(width: 28),
          const SizedBox(width: 8),
          Expanded(child: Center(child: Text('KG', style: AppTypography.monoXs.copyWith(color: AppColors.textDim, letterSpacing: 1.5)))),
          const SizedBox(width: 6),
          Expanded(child: Center(child: Text('REPS', style: AppTypography.monoXs.copyWith(color: AppColors.textDim, letterSpacing: 1.5)))),
          const SizedBox(width: 6),
          SizedBox(width: 28, child: Center(child: Text('\u2713', style: AppTypography.monoXs.copyWith(color: AppColors.textDim)))),
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
                    : AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: widget.isGroupModeSource
                  ? AppColors.accent.withValues(alpha: 0.5)
                  : widget.isInSupersetGroupMode
                      ? AppColors.accent.withValues(alpha: 0.2)
                      : widget.isActive
                          ? AppColors.accent.withValues(alpha: 0.35)
                          : AppColors.line2,
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
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(AppRadius.card),
                        bottomLeft: Radius.circular(AppRadius.card),
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
                        // Exercise header row — Bug #15b: tap to focus this
                        // card (collapses any other expanded card). Long-press
                        // still triggers superset grouping.
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.onFocus,
                          onLongPress: widget.onLongPressHeader,
                          child: Row(
                            children: [
                              // Number badge circle
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: widget.isActive
                                      ? AppColors.accentSoft
                                      : AppColors.bgRaise,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '${widget.exerciseIndex + 1}',
                                    style: AppTypography.monoXs.copyWith(
                                      color: widget.isActive
                                          ? AppColors.accent
                                          : AppColors.textDim,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),

                              // Name + subtitle
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.exercise.name,
                                      style: AppTypography.h3.copyWith(
                                        fontSize: 14,
                                        height: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      _metaText(),
                                      style: AppTypography.monoXs.copyWith(
                                        color: AppColors.textDim,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    // Bug #6 — hint when reviewing a completed exercise
                                    if (widget.isDone && widget.isExpanded)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(top: 2),
                                        child: Text(
                                          'Tap to edit values',
                                          style:
                                              AppTypography.bodySm.copyWith(
                                            color: AppColors.textDim,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),

                              // Swap or Done badge
                              if (widget.isDone)
                                GestureDetector(
                                  onTap: widget.onFocus,
                                  child: const WardChip(
                                    label: '✓ DONE',
                                    tone: WardChipTone.ok,
                                  ),
                                )
                              else
                                GestureDetector(
                                  onTap: widget.onSwap,
                                  child: const WardChip(
                                    label: '⇄ SWAP',
                                    tone: WardChipTone.neutral,
                                  ),
                                ),

                              // Bug #15b — Expand/collapse chevron. Rotates
                              // when this card becomes the focused one.
                              const SizedBox(width: 6),
                              AnimatedRotation(
                                turns: widget.isExpanded ? 0.5 : 0,
                                duration: const Duration(milliseconds: 180),
                                child: Icon(
                                  Icons.keyboard_arrow_down,
                                  size: 18,
                                  color: AppColors.textDim
                                      .withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Bug #15b — Everything below the header (last-perf
                        // hint, table, set rows, +/- buttons) is gated on
                        // isExpanded so collapsed cards stay header-only.
                        if (widget.isExpanded) ...[
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
                                  const Icon(Icons.history,
                                      size: 10,
                                      color: AppColors.textDim),
                                  const SizedBox(width: 3),
                                  Text(
                                    'LAST: ${lastPerf.lastWeight!.toStringAsFixed(1)}KG × ${lastPerf.lastReps ?? '?'} REPS',
                                    style: AppTypography.monoXs.copyWith(
                                      color: AppColors.textDim,
                                      letterSpacing: 1.2,
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
                                  const Icon(Icons.arrow_upward,
                                      size: 10, color: AppColors.accent),
                                  const SizedBox(width: 3),
                                  Text(
                                    'TRY: ${lastPerf.suggestedWeight!.toStringAsFixed(1)}KG × ${lastPerf.lastReps ?? widget.exercise.reps}',
                                    style: AppTypography.monoXs.copyWith(
                                      color: AppColors.accent,
                                      letterSpacing: 1.2,
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
                                        // A7: update snapshot on uncheck too —
                                        // reflects the revised completed-set count.
                                        _persistActiveState(setIdx);
                                        return;
                                      }

                                      // Validate required fields before marking complete
                                      final validationError = _validateSetInputs(setIdx);
                                      if (validationError != null) {
                                        ScaffoldMessenger.of(context).clearSnackBars();
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            backgroundColor: AppColors.card,
                                            behavior:
                                                SnackBarBehavior.floating,
                                            duration: const Duration(
                                                milliseconds: 1500),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      AppRadius.sharp),
                                              side: BorderSide(
                                                  color: AppColors.bad
                                                      .withValues(alpha: 0.3)),
                                            ),
                                            content: Text(
                                              validationError,
                                              style: AppTypography.bodySm
                                                  .copyWith(
                                                color: AppColors.bad,
                                              ),
                                            ),
                                          ),
                                        );
                                        return;
                                      }

                                      _captureSetValues(setIdx);
                                      widget.onToggleSet(setIdx);
                                      // A7: persist snapshot after every set check-off
                                      // so the Captain knows current mid-workout state.
                                      _persistActiveState(setIdx);
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
                        ], // close `if (widget.isExpanded) ...[` (Bug #15b)
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
      color = AppColors.ok;
      icon = '\u2191'; // up arrow
    } else if (currentWeight == lastWeight) {
      color = AppColors.warn;
      icon = '\u2192'; // right arrow
    } else {
      color = AppColors.bad;
      icon = '\u2193'; // down arrow
    }

    return Text(
      icon,
      style: AppTypography.h2.copyWith(fontSize: 14, color: color),
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
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.card),
        ),
        border: const Border(
          top: BorderSide(color: AppColors.line2),
          left: BorderSide(color: AppColors.line2),
          right: BorderSide(color: AppColors.line2),
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
                color: AppColors.line2,
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
                  style: AppTypography.mono.copyWith(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                    letterSpacing: 2.5,
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
                  child: const WardChip(
                    label: '+ CREATE CUSTOM',
                    tone: WardChipTone.gold,
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
              style: AppTypography.bodySm,
              decoration: InputDecoration(
                hintText: 'Search exercises...',
                hintStyle:
                    AppTypography.bodySm.copyWith(color: AppColors.textDim),
                prefixIcon: const Icon(Icons.search,
                    color: AppColors.textDim, size: 18),
                filled: true,
                fillColor: AppColors.bgRaise,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  borderSide: const BorderSide(color: AppColors.line2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  borderSide: const BorderSide(color: AppColors.line2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
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
                  child: WardChip(
                    label: cat,
                    tone: isSelected
                        ? WardChipTone.gold
                        : WardChipTone.neutral,
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
                        style: AppTypography.bodySm
                            .copyWith(color: AppColors.textDim),
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
                              bottom: BorderSide(
                                  color: AppColors.line2, width: 0.5),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: AppTypography.h3
                                          .copyWith(fontSize: 13),
                                    ),
                                    if (muscles.isNotEmpty)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(top: 2),
                                        child: Text(
                                          muscles,
                                          style: AppTypography.bodySm
                                              .copyWith(
                                                  color: AppColors.textDim),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Category badge
                              WardChip(
                                label: category,
                                tone: WardChipTone.gold,
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
                                color: AppColors.textGhost,
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

  /// Hive key used to persist the check list across widget rebuilds (scroll,
  /// keyboard, parent rebuild). F10 · without this, scrolling the workout
  /// screen clears every warmup check.
  String get _hiveKey {
    // APK Test #12.6 IST sweep — see feedback_use_ist_throughout.md
    final today = istDateStr(DateTime.now());
    final slug = widget.title.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    return 'warmup_checks_${today}_$slug';
  }

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _checked = _loadChecks();
  }

  List<bool> _loadChecks() {
    try {
      final raw = HiveService.instance.workoutBox.get(_hiveKey);
      if (raw is List) {
        final restored = raw
            .map((v) => v == true)
            .toList();
        // Adjust length if exercise count changed since last session.
        if (restored.length == widget.exercises.length) return restored;
      }
    } catch (_) {/* hive corrupt — fall through */}
    return List.filled(widget.exercises.length, false);
  }

  Future<void> _persistChecks() async {
    try {
      await HiveService.instance.workoutBox.put(_hiveKey, _checked);
    } catch (_) {/* non-fatal — UI still shows the tick */}
  }

  @override
  void didUpdateWidget(covariant _WarmupCooldownSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.exercises.length != _checked.length) {
      // Exercise count changed — reload from Hive (may still match),
      // else reset.
      _checked = _loadChecks();
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
          borderRadius: BorderRadius.circular(AppRadius.card),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(widget.icon, size: 16, color: widget.color),
                    const SizedBox(width: 8),
                    Text(
                      widget.title,
                      style: AppTypography.mono.copyWith(
                        color: widget.color,
                        letterSpacing: 2.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_checkedCount > 0)
                      Text(
                        '$_checkedCount/${widget.exercises.length}',
                        style: AppTypography.monoXs.copyWith(
                          color: widget.color.withValues(alpha: 0.6),
                          letterSpacing: 1.2,
                        ),
                      ),
                    const Spacer(),
                    if (_allDone)
                      Icon(Icons.check_circle, size: 16, color: widget.color)
                    else
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
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

                // Format duration/reps. ExerciseData.reps is now a clean
                // numeric string for timed exercises (Bug #16 fix). Defensive
                // fallback to 30s if parsing somehow fails.
                String detail;
                if (ex.loggingType == 'timed') {
                  final raw = ex.reps.replaceAll(RegExp(r'[^0-9]'), '');
                  final parsedSecs = int.tryParse(raw) ?? 0;
                  final secs = parsedSecs > 0 ? parsedSecs : 30;
                  if (secs >= 60) {
                    final mins = secs ~/ 60;
                    final remainder = secs % 60;
                    detail = remainder == 0 ? '${mins}m' : '${mins}m ${remainder}s';
                  } else {
                    detail = '${secs}s';
                  }
                } else {
                  detail = '${ex.sets} \u00d7 ${ex.reps}';
                }

                return GestureDetector(
                  onTap: () {
                    setState(() => _checked[idx] = !_checked[idx]);
                    _persistChecks(); // F10 · survive scroll rebuild
                  },
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
                            style: AppTypography.bodySm.copyWith(
                              color: done
                                  ? AppColors.textDim
                                  : AppColors.textPrimary,
                              decoration: done
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        Text(
                          detail,
                          style: AppTypography.monoXs.copyWith(
                            color: AppColors.textDim,
                            letterSpacing: 1.2,
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

