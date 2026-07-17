part of 'screen.dart';

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

    // Weight: prefer last session's weight for weight-based exercises.
    // ⑦(b) + ⑥ 6-B: scale the LAST-LOGGED weight by the SINGLE effective load
    // factor — `effectiveLoadFactor(ex)` = larger-cut-wins(⑦b session-detraining
    // cut, readiness compound cut). One multiplication → no double-dip; readiness
    // and ⑦b never stack. 1.0 when both off / green / no gap. ONLY this branch —
    // the prescribed `exercise.weight` fallback below already carries ⑦a decay
    // (disjoint inputs). Idempotent (immutable lastWeight × session-constant).
    final String weightValue;
    if (['weight_reps', 'weighted_bodyweight'].contains(exercise.loggingType) &&
        lastPerf.lastWeight != null &&
        lastPerf.lastWeight! > 0) {
      // Show clean number: strip trailing .0
      final w = lastPerf.lastWeight! * widget.data.effectiveLoadFactor(exercise);
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
  ///
  /// APK Test #15.1 / Bug E — also enforces realistic per-set bounds
  /// (reps 1..60) matching the cloud CHECK constraint added in migration
  /// 060. Pre-fix the field accepted any int, so a typo like "135" (3
  /// keys vs 1) shipped to cloud and resurfaced as "LAST: 50KG · 135 REPS"
  /// for the founder. The cloud constraint is the canonical defender;
  /// this client-side check surfaces the error inline instead of after
  /// a sync attempt fails.
  /// closes-diagnose: 2026-05-12-rep-validation-e6a2d4
  static const int _repsMin = 1;
  static const int _repsMax = 60;

  String? _validateRepsBound(int reps) {
    if (reps < _repsMin) return 'Enter reps before marking complete';
    if (reps > _repsMax) {
      return 'Reps must be ≤ $_repsMax per set. Typo? Cloud rejects values above this.';
    }
    return null;
  }

  String? _validateSetInputs(int setIdx) {
    switch (widget.exercise.loggingType) {
      case 'weight_reps':
        final weight = double.tryParse(_weightControllers[setIdx].text) ?? 0;
        final reps = int.tryParse(_repsControllers[setIdx].text) ?? 0;
        if (weight <= 0) return 'Enter weight before marking complete';
        final repsErr = _validateRepsBound(reps);
        if (repsErr != null) return repsErr;
        return null;
      case 'bodyweight_reps':
        final reps = int.tryParse(_repsControllers[setIdx].text) ?? 0;
        return _validateRepsBound(reps);
      case 'weighted_bodyweight':
        final reps = int.tryParse(_repsControllers[setIdx].text) ?? 0;
        return _validateRepsBound(reps);
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
        return '${widget.exercise.sets} sets · ${widget.exercise.reps}s · ${widget.exercise.rest} rest';
      case 'cardio':
        return '${widget.exercise.reps} min · ${widget.exercise.rest} rest';
      case 'distance':
        return '${widget.exercise.reps} · ${widget.exercise.rest} rest';
      case 'bodyweight_reps':
        return '${widget.exercise.sets} sets · ${widget.exercise.reps} reps · ${widget.exercise.rest} rest';
      case 'weighted_bodyweight':
        return '${widget.exercise.sets} sets · ${widget.exercise.reps} reps · +${widget.exercise.weight} · ${widget.exercise.rest} rest';
      default: // weight_reps
        return '${widget.exercise.sets} sets · ${widget.exercise.reps} reps · ${widget.exercise.weight} · ${widget.exercise.rest} rest';
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
          SizedBox(width: 28, child: Center(child: Text('✓', style: AppTypography.monoXs.copyWith(color: AppColors.textDim)))),
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

                          // "Try: 52.5kg × 10" suggestion line — ⑦(b) + ⑥ 6-B:
                          // SUPPRESS when ANY session cut is active — the ⑦b
                          // detraining gap-cut OR the ⑥ readiness deload (the
                          // EFFECTIVE factor < 1.0). A "TRY: +2.5kg" directive
                          // would contradict the reduced prefill (the banner
                          // explains the lighter load) = "never shame". The
                          // factual "LAST:" line above is kept.
                          if (lastPerf.suggestedWeight != null &&
                              lastPerf.suggestedWeight! > 0 &&
                              widget.data.effectiveLoadFactor(widget.exercise) >=
                                  1.0) {
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
                                      loadFactor: widget.data.effectiveLoadFactor(widget.exercise),
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

                        // ── Per-exercise coaching content (W3.6) ─────
                        // Collapsed by default; renders nothing when the
                        // exercise has no library match (swap/custom).
                        CoachingContentPanel(
                          key: ValueKey(
                              'coaching_${widget.exercise.name}'),
                          exerciseName: widget.exercise.name,
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
