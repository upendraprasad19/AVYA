import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import '../../providers/train_provider.dart';
import '../../services/active_workout_persistence.dart';
import '../../../home/providers/home_provider.dart';
import '../../widgets/create_custom_exercise_sheet.dart';
import '../../widgets/exercise_swap_sheet.dart';
import '../../widgets/set_input_row.dart';
import '../../widgets/workout_receipt_card.dart';
import '../../widgets/workout_receipt_sheet.dart';

part 'completion_sheet.dart';
part 'exercise_card.dart';
part 'exercise_picker_sheet.dart';
part 'finish_dialog.dart';
part 'header.dart';
part 'overload_indicator.dart';
part 'swap_sheets.dart';
part 'warmup_cooldown_section.dart';

/// Active Workout screen — live logging UI driven by `logging_type`.
///
/// C3 (tech-debt audit 2026-05-20): originally a 2430-line monolith. Split
/// into sibling part files under `active_workout/` to keep this screen
/// under 800 lines without breaking the existing private widget contracts
/// (`_ExerciseCard`, `_OverloadIndicator`, `_ExercisePickerSheet`,
/// `_WarmupCooldownSection`). Part files share the library's private scope
/// so the underscore-private widgets keep their names + visibility.
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
      return _buildCompleteScreen(context, ref, data);
    }

    final pctInt = (data.progressPercent * 100).round();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Column(
            children: [
              // Header
              _buildHeader(context, data),

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
                                      'Warm-up set — not counted in volume',
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
}
