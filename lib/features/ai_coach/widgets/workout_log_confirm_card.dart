import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import '../copy/workout_draft_copy.dart';
import '../providers/ai_coach_provider.dart';
import '../services/conversational_log_handler.dart';

/// What the chat workout card shows (docs/plans/train-coach-log-refresh.md,
/// B'): the draft's [DraftCardStatus], with a running submit on top.
enum WorkoutCardState {
  pending,
  submitting,
  saved,
  savedDayNotMarked,
  partial,
  noneSaved,
}

/// Pure: the card state for [d].
WorkoutCardState cardStateFor(WorkoutDraft d) {
  if (d.isSubmitting) return WorkoutCardState.submitting;
  switch (d.status) {
    case DraftCardStatus.pending:
      return WorkoutCardState.pending;
    case DraftCardStatus.saved:
      return WorkoutCardState.saved;
    case DraftCardStatus.savedDayNotMarked:
      return WorkoutCardState.savedDayNotMarked;
    case DraftCardStatus.partial:
      return WorkoutCardState.partial;
    case DraftCardStatus.noneSaved:
      return WorkoutCardState.noneSaved;
  }
}

/// The header TalkBack reads when a held card appears.
const _readyHeader = 'Workout ready to log';

/// How long a card applied from hold ignores CONFIRM (F4).
const Duration kHeldCardTapGuard = Duration(milliseconds: 500);

/// Editable confirmation card for a multi-turn workout log.
///
/// Wardroom styling: sharp 2-px accent outline card with Fraunces h3
/// workout name, Mono-caps exercise summary rows, and sharp 2-px accent
/// CONFIRM / DISCARD slabs. Does NOT auto-confirm — workout data is too
/// important to auto-submit. Its saved / partial / held states live in
/// [workoutDraftProvider], so they survive the card's own rebuilds; the slot
/// keys it by draft id.
class WorkoutLogConfirmCard extends ConsumerStatefulWidget {
  const WorkoutLogConfirmCard({super.key});

  @override
  ConsumerState<WorkoutLogConfirmCard> createState() =>
      _WorkoutLogConfirmCardState();
}

class _WorkoutLogConfirmCardState
    extends ConsumerState<WorkoutLogConfirmCard> {
  /// DISCARD was tapped after a save: the confirm row is showing.
  bool _confirmingDiscard = false;

  /// A card applied from hold (after "Discard the rest") takes its place
  /// under the user's finger: CONFIRM ignores taps for [kHeldCardTapGuard],
  /// so the second tap of a double tap cannot log a workout the user never
  /// saw (B-pass fb5048e68fae F4). Real time, not frames.
  final Stopwatch _sinceMount = Stopwatch()..start();
  late final bool _appliedFromHold =
      ref.read(workoutDraftProvider)?.appliedFromHold ?? false;

  @override
  void initState() {
    super.initState();
    _appliedFromHold; // read before the post-frame callback consumes it
    // A held card that has just been applied is announced once, by its own
    // card (the notifier has no context).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final d = ref.read(workoutDraftProvider);
      if (d == null || !d.appliedFromHold) return;
      SemanticsService.sendAnnouncement(
          View.of(context), _readyHeader, TextDirection.ltr);
      ref.read(workoutDraftProvider.notifier).consumeHoldAnnouncement(d.id);
    });
  }

  Future<void> _submit() async {
    if (_appliedFromHold && _sinceMount.elapsed < kHeldCardTapGuard) return;
    final draft = ref.read(workoutDraftProvider);
    if (draft == null) return;
    await submitWorkoutDraft(draft, ref);
  }

  void _onDiscard(WorkoutDraft draft) {
    if (draft.savedNames.isNotEmpty) {
      setState(() => _confirmingDiscard = true);
      return;
    }
    ref.read(workoutDraftProvider.notifier).discard();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(workoutDraftProvider, (prev, next) {
      if (next != null &&
          isSavedDraftStatus(next.status) &&
          (prev == null || !isSavedDraftStatus(prev.status))) {
        HapticFeedback.lightImpact();
      }
    });
    final draft = ref.watch(workoutDraftProvider);
    if (draft == null) return const SizedBox.shrink();
    final view = cardStateFor(draft);
    final saved = view == WorkoutCardState.saved ||
        view == WorkoutCardState.savedDayNotMarked;
    final submitting = view == WorkoutCardState.submitting;
    // OI-361: nothing to write, nothing to confirm (the submit's own guard).
    final canLog = draftHasLoggableSet(draft);
    final exercises = saved
        ? [
            for (final e in draft.exercises)
              if (draftExerciseSets(e).isNotEmpty) e,
          ]
        : draft.exercises;
    final stacked = MediaQuery.textScalerOf(context).scale(10) >= 15;

    // The lines TalkBack must hear, in the live region (re-created per
    // failed attempt so a same-text failure is announced again).
    final lines = <(String, Color)>[
      if (draft.hasHeldDraft && !submitting && !saved)
        (WardroomCopy.coachWorkoutHeldNotice, AppColors.warn),
      if (view == WorkoutCardState.savedDayNotMarked ||
          (!saved && draft.dayNotMarked))
        (WardroomCopy.coachWorkoutDayNotMarked, AppColors.warn),
      if (!saved && draft.note != null) (draft.note!, AppColors.warn),
      if (!saved && draft.skippedNames.isNotEmpty)
        (formatSkipped(draft.skippedNames), AppColors.textDim),
    ];
    // On a saved card the Skipped line sits under the saved row.
    final below = <(String, Color)>[
      if (saved && draft.skippedNames.isNotEmpty)
        (formatSkipped(draft.skippedNames), AppColors.textDim),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.accent, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.fitness_center,
                  color: AppColors.accent, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  saved ? WardroomCopy.coachWorkoutLoggedHeader : _readyHeader,
                  style: AppTypography.h3,
                ),
              ),
              WardChip(
                label: '${exercises.length} EX',
                tone: WardChipTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: 10),
          const WardRule(gold: true, margin: EdgeInsets.zero),
          const SizedBox(height: 12),

          // Exercise list
          ...exercises.asMap().entries.map((entry) {
            return _ExerciseRow(
              exercise: entry.value,
              exerciseIndex: entry.key,
              pencilVisible: !saved && !submitting,
            );
          }),

          if (!canLog && !saved) ...[
            const SizedBox(height: 10),
            Text(
              WardroomCopy.coachDraftNoSets,
              style: AppTypography.bodySm.copyWith(color: AppColors.warn),
            ),
          ],

          if (lines.isNotEmpty || saved)
            _LiveLines(
              key: ValueKey('live_${draft.failedAttempt}'),
              lines: lines,
              savedRow: saved,
              below: below,
            ),

          if (!saved) ...[
            const SizedBox(height: 14),
            if (_confirmingDiscard)
              _discardConfirmRow(draft, stacked)
            else
              _actionRow(draft, stacked,
                  submitting: submitting, canLog: canLog),
          ],
        ],
      ),
    );
  }

  Widget _actionRow(WorkoutDraft draft, bool stacked,
      {required bool submitting, required bool canLog}) {
    final confirmEnabled = !submitting && canLog;
    final confirm = Semantics(
      button: true,
      enabled: confirmEnabled,
      label: submitting
          ? WardroomCopy.coachWorkoutSavingSemantics
          : WardroomCopy.coachWorkoutConfirmSemantics,
      onTap: confirmEnabled ? _submit : null,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: confirmEnabled ? _submit : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: confirmEnabled
                ? AppColors.accent
                : AppColors.accent.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppRadius.sharp),
          ),
          child: Center(
            child: submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.bgDeep,
                    ),
                  )
                : Text(
                    'CONFIRM · LOG WORKOUT',
                    textAlign: TextAlign.center,
                    style: AppTypography.mono.copyWith(
                      color: AppColors.bgDeep,
                      letterSpacing: 1.8,
                    ),
                  ),
          ),
        ),
      ),
    );
    final discardTap = submitting ? null : () => _onDiscard(draft);
    final discard = _textButton(
      label: 'DISCARD',
      semanticsLabel: WardroomCopy.coachWorkoutDiscardSemantics,
      onTap: discardTap,
      color: AppColors.textDim,
    );
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [confirm, const SizedBox(height: 8), discard],
      );
    }
    return Row(
      children: [
        Expanded(child: confirm),
        const SizedBox(width: 12),
        discard,
      ],
    );
  }

  /// DISCARD after a save asks first. DISCARD takes the left (or top) slot in
  /// the danger look and KEEP the right (or bottom) one. The question line
  /// above pushes this row down, so the second tap of a quick double tap on
  /// the old DISCARD lands on that inert line, never on "Discard the rest"
  /// (measured at 1.0 / 1.5 / 2.0, B-pass fb5048e68fae F3).
  Widget _discardConfirmRow(WorkoutDraft draft, bool stacked) {
    final notifier = ref.read(workoutDraftProvider.notifier);
    final line = formatDiscardRest(draft.savedNames);
    final discard = Semantics(
      button: true,
      enabled: true,
      label: WardroomCopy.coachWorkoutDiscardRestSemantics,
      onTap: notifier.discard,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: notifier.discard,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.bad),
            borderRadius: BorderRadius.circular(AppRadius.sharp),
          ),
          child: Text(
            'DISCARD',
            style: AppTypography.mono.copyWith(
              color: AppColors.bad,
              letterSpacing: 1.6,
            ),
          ),
        ),
      ),
    );
    final keep = _textButton(
      label: WardroomCopy.coachWorkoutKeepLabel,
      semanticsLabel: WardroomCopy.coachWorkoutKeepSemantics,
      onTap: () => setState(() => _confirmingDiscard = false),
      color: AppColors.textDim,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          container: true,
          label: line,
          excludeSemantics: true,
          child: Text(
            line,
            style: AppTypography.bodySm.copyWith(color: AppColors.warn),
          ),
        ),
        const SizedBox(height: 10),
        if (stacked) ...[
          discard,
          const SizedBox(height: 8),
          keep,
        ] else
          Row(
            children: [
              Expanded(child: discard),
              const SizedBox(width: 12),
              keep,
            ],
          ),
      ],
    );
  }

  Widget _textButton({
    required String label,
    required String semanticsLabel,
    required VoidCallback? onTap,
    required Color color,
  }) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticsLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: AppTypography.mono.copyWith(
                  color: color,
                  letterSpacing: 1.6,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The card's live region: the held notice, the day line, the note and the
/// Skipped line, plus the saved row in the saved states. It fades in, inside
/// its own semantics node, so TalkBack hears it even mid-fade.
class _LiveLines extends StatelessWidget {
  final List<(String, Color)> lines;
  final bool savedRow;
  final List<(String, Color)> below;

  const _LiveLines({
    super.key,
    required this.lines,
    required this.savedRow,
    this.below = const [],
  });

  static List<Widget> _texts(List<(String, Color)> lines) => [
        for (final (text, color) in lines) ...[
          const SizedBox(height: 10),
          Text(text, style: AppTypography.bodySm.copyWith(color: color)),
        ],
      ];

  @override
  Widget build(BuildContext context) {
    final label = [
      ...lines.map((l) => l.$1),
      if (savedRow) WardroomCopy.coachWorkoutLogged,
      ...below.map((l) => l.$1),
    ].join('\n');
    return Semantics(
      liveRegion: true,
      container: true,
      label: label,
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 200),
        builder: (context, opacity, child) => Opacity(
          opacity: opacity,
          alwaysIncludeSemantics: true,
          child: child,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ..._texts(lines),
            if (savedRow) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    WardroomCopy.coachWorkoutLogged,
                    style: AppTypography.mono.copyWith(
                      color: AppColors.ok,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.check_circle,
                      size: 18, color: AppColors.ok),
                ],
              ),
            ],
            ..._texts(below),
          ],
        ),
      ),
    );
  }
}

// ── Exercise Row ────────────────────────────────────────────────

class _ExerciseRow extends ConsumerWidget {
  final DraftExercise exercise;
  final int exerciseIndex;
  final bool pencilVisible;

  const _ExerciseRow({
    required this.exercise,
    required this.exerciseIndex,
    required this.pencilVisible,
  });

  /// The first set the submit would drop or that carries a negative value,
  /// so the user can see what to fix.
  String? get _badSet {
    for (var i = 0; i < exercise.sets.length; i++) {
      final s = exercise.sets[i];
      final negative = (s.weightKg ?? 0) < 0 ||
          (s.reps ?? 0) < 0 ||
          (s.durationSecs ?? 0) < 0;
      final blank = (s.weightKg ?? 0) <= 0 &&
          (s.reps ?? 0) <= 0 &&
          (s.durationSecs ?? 0) <= 0;
      if (!negative && !blank) continue;
      if (exercise.loggingType == 'timed') {
        return 'set ${i + 1}: ${s.durationSecs ?? 0}s';
      }
      final reps = s.reps ?? 0;
      final weight = s.weightKg;
      if (weight != null && weight != 0) {
        return 'set ${i + 1}: $reps @ ${weight.toStringAsFixed(1)}kg';
      }
      return 'set ${i + 1}: $reps reps';
    }
    return null;
  }

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
    final bad = _badSet;
    if (bad != null) return bad;

    final setCount = exercise.sets.length;
    final firstSet = exercise.sets.first;

    if (exercise.loggingType == 'timed') {
      final secs = firstSet.durationSecs ?? 0;
      return '$setCount × ${secs}s';
    }

    final reps = firstSet.reps ?? 0;
    final weight = firstSet.weightKg;
    if (weight != null && weight != 0) {
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
    final editLabel = WardroomCopy.coachWorkoutEditSemanticsTemplate
        .replaceAll('{name}', exercise.name);
    final pencil = Semantics(
      button: true,
      label: editLabel,
      onTap: () => _showEditSheet(context, ref),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showEditSheet(context, ref),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(AppRadius.sharp),
              ),
              child: const Icon(Icons.edit_outlined,
                  size: 14, color: AppColors.textDim),
            ),
          ),
        ),
      ),
    );
    return WardCard(
      variant: WardCardVariant.inset,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(_icon, size: 16, color: AppColors.textDim),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exercise.name,
                  style: AppTypography.h3.copyWith(fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  _summary,
                  style: AppTypography.monoXs.copyWith(
                    color: AppColors.textDim,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          // Tap to edit. The slot is kept while hidden, so wrapped rows do
          // not reflow during a submit.
          Visibility(
            visible: pencilVisible,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: pencilVisible ? pencil : ExcludeSemantics(child: pencil),
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
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
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

// ── Set input ────────────────────────────────────────────────────

/// The edit sheet's number filter. A keystroke or paste that would make the
/// text invalid is REJECTED (the old text stays), never trimmed; a deletion
/// is always accepted, so a seeded `-5.0` can be backspaced away; a text-equal
/// value (a composing commit) passes unchanged.
class DraftSetInputFormatter extends TextInputFormatter {
  /// Weight (one `.`, `,` read as `.`) when true; reps (digits) when false.
  final bool decimal;

  DraftSetInputFormatter({required this.decimal});

  static final _weight = RegExp(r'^\d*\.?\d*$');
  static final _reps = RegExp(r'^\d*$');

  static bool isDeletion(String oldText, String newText) {
    if (newText.length >= oldText.length) return false;
    var p = 0;
    while (p < newText.length && newText[p] == oldText[p]) {
      p++;
    }
    return oldText.substring(p + oldText.length - newText.length) ==
        newText.substring(p);
  }

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text == oldValue.text) return newValue;
    final value = decimal && newValue.text.contains(',')
        ? newValue.copyWith(text: newValue.text.replaceAll(',', '.'))
        : newValue;
    if (isDeletion(oldValue.text, value.text)) return value;
    if ((decimal ? _weight : _reps).hasMatch(value.text)) return value;
    return oldValue;
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

  // Captured at open: the row's ref is unusable once a new draft has
  // replaced the card (b7f3e2), and the notifier instance outlives it.
  late final String? _draftId;
  late final WorkoutDraftNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _draftId = widget.parentRef.read(workoutDraftProvider)?.id;
    _notifier = widget.parentRef.read(workoutDraftProvider.notifier);
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
    final draftId = _draftId;
    if (draftId != null) {
      for (int i = 0; i < widget.exercise.sets.length; i++) {
        final weight = double.tryParse(_weightControllers[i].text);
        final reps = int.tryParse(_repsControllers[i].text);
        _notifier.updateSet(
          draftId,
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
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // The weight field also shows when a set carries a weight, so a bad
    // weight on a non-weighted row can be fixed.
    final isWeighted = widget.exercise.loggingType == 'weight_reps' ||
        widget.exercise.loggingType == 'weighted_bodyweight' ||
        widget.exercise.sets.any((s) => (s.weightKg ?? 0) != 0);
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
            style: AppTypography.h2,
          ),
          const SizedBox(height: 12),
          const WardRule(gold: true, margin: EdgeInsets.zero),
          const SizedBox(height: 16),

          // Set rows
          ...widget.exercise.sets.asMap().entries.map((entry) {
            final i = entry.key;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(
                      'SET ${i + 1}',
                      style: AppTypography.monoXs.copyWith(
                        color: AppColors.textMute,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (isWeighted) ...[
                    Expanded(
                      child: TextField(
                        key: ValueKey('draft_weight_$i'),
                        controller: _weightControllers[i],
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          DraftSetInputFormatter(decimal: true),
                        ],
                        style: AppTypography.body.copyWith(
                          color: AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: 'kg',
                          hintStyle: AppTypography.body.copyWith(
                            color: AppColors.textDisabled,
                          ),
                          filled: true,
                          fillColor: AppColors.bgRaise,
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.sharp),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: TextField(
                      key: ValueKey('draft_reps_$i'),
                      controller: _repsControllers[i],
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        DraftSetInputFormatter(decimal: false),
                      ],
                      style: AppTypography.body.copyWith(
                        color: AppColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'reps',
                        hintStyle: AppTypography.body.copyWith(
                          color: AppColors.textDisabled,
                        ),
                        filled: true,
                        fillColor: AppColors.bgRaise,
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadius.sharp),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 12),

          // Save button — sharp 2-px accent slab
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: _save,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(AppRadius.sharp),
                ),
                child: Center(
                  child: Text(
                    'SAVE CHANGES',
                    style: AppTypography.mono.copyWith(
                      color: AppColors.bgDeep,
                      letterSpacing: 1.8,
                    ),
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
