import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_plate_sheet.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_plate_thumb.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import '../../providers/train_provider.dart';
import '../../services/active_workout_persistence.dart';
import '../../services/log_exercise_flags.dart';
import '../../services/log_exercise_logic.dart';
import '../../../home/providers/home_provider.dart';
import '../../widgets/create_custom_exercise_sheet.dart';
import '../../widgets/log_undo_toast.dart';
import '../../widgets/exercise_swap_sheet.dart';
import '../../widgets/set_input_row.dart';
import '../../widgets/workout_receipt_card.dart';
import '../../widgets/workout_receipt_sheet.dart';

// ⑦ OI-89 seams 6 + 8: the swap sheet and the exercise picker are `part of`
// this library, so their capability imports must live here.
import 'package:icanbefitter/shared/repositories/plan_engine/training_history_analyzer.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/equipment_capability.dart';

part 'coaching_content_panel.dart';
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

  /// Obs 1 (2026-09-21, diagnose swap-undo-snackbar-completion-dismiss) — the
  /// swap-undo SnackBar is shown via `ScaffoldMessenger.of(context)` from
  /// `_openCreateAndAutoSwap` (swap_sheets.dart), a top-level function that
  /// does not otherwise outlive the sheet it's called from. Captured here so
  /// BOTH exit paths below can dismiss the SAME messenger instance: the
  /// immediate completion listener (screen stays mounted, only its build
  /// output changes) and dispose() (the backstop for every path that DOES
  /// unmount the screen — cancel dialog's context.go, system back-gesture —
  /// without needing to enumerate each one).
  ScaffoldMessengerState? _swapUndoMessenger;

  /// One LOG per exercise (flag `enable_log_exercise_button`): the LOG
  /// decision + input guard live HERE, not on a card — the guard must protect
  /// the NEXT card's button, which belongs to a different State. Monotonic
  /// clock: `nowWall()` is frozen under the dev clock override.
  final Stopwatch _logClock = Stopwatch()..start();
  late final LogExerciseController _logController =
      LogExerciseController(clock: () => _logClock.elapsed);

  /// Batch 2 UNDO toast (docs/plans/log-exercise-batch2.md §5.1): an in-tree
  /// overlay, never a SnackBar, so it cannot outlive this screen. The latest
  /// LOG wins; the Timer clears only its own generation.
  LogUndoRecord? _logUndo;
  int _logUndoGeneration = 0;
  Timer? _logUndoTimer;

  /// Applies the controller's outcome: clear the manual focus so the next
  /// non-done exercise expands, and reveal a superset partner.
  LogOutcomeKind _onLogExercise(int exIdx, Set<int> setIdxs) {
    final before = ref.read(activeWorkoutProvider);
    final outcome = _logController.log(
      exerciseIndex: exIdx,
      setIndexes: setIdxs,
      logSets: ref.read(activeWorkoutProvider.notifier).logSets,
      readState: () => ref.read(activeWorkoutProvider),
    );
    if (outcome.clearFocus) {
      setState(() {
        _focusedExerciseIndex = null;
      });
    }
    final partner = outcome.revealPartner;
    if (partner != null) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _scrollToExercise(partner);
      });
    }
    if (outcome.kind == LogOutcomeKind.logged) _showLogUndo(exIdx, before);
    return outcome.kind;
  }

  void _showLogUndo(int exIdx, ActiveWorkoutData before) {
    final record = undoRecordFor(
      before: before,
      after: ref.read(activeWorkoutProvider),
      exerciseIndex: exIdx,
      shownAt: _logClock.elapsed,
      generation: ++_logUndoGeneration,
      // No toast while a save is running: its UNDO would do nothing.
      completing: ref.read(activeWorkoutProvider.notifier).isCompleting,
    );
    if (record == null) return;
    _logUndoTimer?.cancel();
    setState(() => _logUndo = record);
    _logUndoTimer = Timer(kLogUndoWindow, () {
      if (!mounted || _logUndo?.generation != record.generation) return;
      setState(() => _logUndo = null);
    });
  }

  void _clearLogUndo() {
    _logUndoTimer?.cancel();
    _logUndoTimer = null;
    if (_logUndo != null) setState(() => _logUndo = null);
  }

  void _onLogUndo() {
    final record = _logUndo;
    if (record == null) return;
    if (shouldIgnoreUndo(now: _logClock.elapsed, shownAt: record.shownAt)) {
      return;
    }
    _clearLogUndo();
    // The coach snapshot (ActiveWorkoutPersistence) is left as the LOG wrote
    // it: clearing it would tell the coach the session is over.
    final undone = ref.read(activeWorkoutProvider.notifier).unlogSets(
        record.exerciseIndex, record.setIndexes,
        exerciseName: record.exerciseName);
    if (undone) _focusExercise(record.exerciseIndex);
  }

  /// RE-OPEN (flip batch §1, founder "amend log"): a tap on LOGGED unchecks the
  /// exercise through the controller (its guard ignores the "did it register?"
  /// second tap). Clears a toast for THIS exercise only, focuses the card and
  /// tells TalkBack. The coach snapshot is left as LOG wrote it (as UNDO).
  void _onReopenExercise(int exIdx) {
    final outcome = _logController.reopen(
      exerciseIndex: exIdx,
      readState: () => ref.read(activeWorkoutProvider),
      unlogSets: ref.read(activeWorkoutProvider.notifier).unlogSets,
    );
    if (outcome.kind != LogOutcomeKind.reopened) return;
    if (_logUndo?.exerciseIndex == exIdx) _clearLogUndo();
    _focusExercise(exIdx);
    final name = ref.read(activeWorkoutProvider).exercises[exIdx].name;
    unawaited(SemanticsService.sendAnnouncement(
      View.of(context),
      WardroomCopy.activeReopenedAnnouncementTemplate
          .replaceAll('{exercise}', name),
      TextDirection.ltr,
    ));
  }

  /// The exercise list with the UNDO toast over its top edge (LOG mode only).
  Widget _withLogUndoToast(bool logMode, ActiveWorkoutData data, Widget list) {
    final undo =
        logMode ? visibleUndoRecord(_logUndo, _logClock.elapsed, data) : null;
    return LogUndoToastHost(
      enabled: logMode,
      list: list,
      toast: undo == null
          ? null
          : LogUndoToast(text: logToastText(undo, data), onUndo: _onLogUndo),
    );
  }

  void _dismissSwapUndoSnackBar() {
    _swapUndoMessenger?.hideCurrentSnackBar();
    _swapUndoMessenger = null;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    // Backstop for the swap-undo snackbar: covers every exit path that
    // unmounts this screen (cancel dialog's context.go, back-gesture pop)
    // without needing to name each one individually.
    _dismissSwapUndoSnackBar();
    _logUndoTimer?.cancel();
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

    // Obs 1 — completion doesn't unmount this screen (build() just switches
    // to _buildCompleteScreen below), so dispose() never fires here. Dismiss
    // the swap-undo snackbar immediately on the false->true transition
    // instead of leaving it to linger until its own 5s timer elapses.
    ref.listen<ActiveWorkoutData>(activeWorkoutProvider, (previous, next) {
      if (next.isComplete && previous?.isComplete != true) {
        _dismissSwapUndoSnackBar();
        _logUndoTimer?.cancel();
        _logUndo = null;
      }
    });

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

    // Read ONCE per build and passed down, so it cannot change between a
    // card's didUpdateWidget and its build within one frame.
    final logMode = LogExerciseFlags.logExerciseButtonEnabled;
    final allLogged = logMode && allExercisesLogged(data);
    // LOG mode counts what the save writes, warm-ups out of the total too
    // (flip §3); the per-set path keeps its own getters.
    final counts = logMode ? workingSetCounts(data) : null;
    final progress =
        counts != null ? workingProgress(counts) : data.progressPercent;
    final pctInt = (progress * 100).round();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Column(
            children: [
              // Header
              _buildHeader(context, data, counts: counts),

              // Progress bar
              _buildProgressBar(progress, pctInt),

              // ⑦(b) session detraining resume banner — shown when a gap cut is
              // active (sessionDetrainingFactor < 1.0). Non-shaming re-entry copy:
              // explains the lighter prefill without quantifying the break.
              if (data.sessionDetrainingFactor < 1.0)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: AppColors.accentSoft,
                  child: Row(
                    children: [
                      const Icon(Icons.restart_alt,
                          size: 14, color: AppColors.accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'WELCOME BACK — TODAY\'S WEIGHTS EASED SO YOU RAMP BACK UP SAFELY',
                          style: AppTypography.monoXs.copyWith(
                            color: AppColors.accent,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

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
                child: _withLogUndoToast(
                  logMode,
                  data,
                  ListView(
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
                            onLogExercise: logMode
                                ? (setIdxs) => _onLogExercise(exIdx, setIdxs)
                                : null,
                            onReopenExercise: logMode && !data.isSaved
                                ? () => _onReopenExercise(exIdx)
                                : null,
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
                            onSwap: () => _showSwapSheet(context, ref, exIdx, this),
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

                    // Batch 2 last-exercise emphasis (LOG mode): FINISH is an
                    // outline until every exercise is logged, then gold with
                    // this line above it. OFF and review mode: as before.
                    if (allLogged)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                        child: Text(
                          WardroomCopy.activeAllExercisesLogged,
                          textAlign: TextAlign.center,
                          style: AppTypography.bodySm
                              .copyWith(color: AppColors.accent),
                        ),
                      ),

                    // Finish Workout button — disabled if already saved (review mode)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: WardButton(
                        label: data.isSaved
                            ? '✓ ALREADY SAVED'
                            : '✓ FINISH WORKOUT',
                        variant: logMode && !data.isSaved && !allLogged
                            ? WardButtonVariant.outline
                            : WardButtonVariant.primary,
                        onPressed: data.isSaved
                            ? null
                            : () => _showFinishDialog(context, ref, data,
                                logMode: logMode, onComplete: _clearLogUndo),
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
