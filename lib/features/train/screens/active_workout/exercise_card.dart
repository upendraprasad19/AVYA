part of 'screen.dart';

// ── Exercise Card ────────────────────────────────────────────────
// Supports all 6 logging types: weight_reps, bodyweight_reps,
// weighted_bodyweight, timed, cardio, distance

// Obs 4, internal-testing batch 2026-09-15. `lastWeight * effectiveLoadFactor`
// is a float multiplication that rarely lands on an exact value, so the old
// `w == w.roundToDouble() ? ... : w.toString()` fallback printed float noise
// like `27.900000000000002` into the weight input. Round to 2dp first (the
// precision every other weight display in this app uses), then still strip a
// clean trailing `.0`.
String formatWeightDisplayValue(double w) {
  final rounded = double.parse(w.toStringAsFixed(2));
  return rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : rounded.toString();
}

/// One LOG per exercise: the screen's handler for a LOG tap on this card.
typedef LogExerciseCallback = LogOutcomeKind Function(Set<int> setIndexes);

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
  /// One LOG per exercise (flag `enable_log_exercise_button`). Non-null puts
  /// the card in LOG mode: no per-set check taps, a sets stepper + LOG button
  /// row. Null (flag OFF) leaves the per-set path exactly as it was.
  final LogExerciseCallback? onLogExercise;
  /// LOG mode: the screen's RE-OPEN handler for this exercise (flip batch §1).
  /// Tapping LOGGED calls it; null in review mode and on the per-set path.
  final VoidCallback? onReopenExercise;

  // ⇄ swap / ⇅ move (docs/plans/active-workout-swap-move.md Task 5). In move
  // mode the card routes its own taps by [moveRole]: a target's whole header
  // places, the source's cancels, a done card ignores every tap.
  final bool moveModeActive;
  final MoveRole moveRole;
  /// Target arrow: ↑ when the target sits above the moving exercise.
  final bool moveTargetAbove;
  /// Show ⇅ (outside move mode): two or more exercises can still move.
  final bool canMove;
  /// ⇅ tap: enter move mode, or cancel it on the moving card.
  final VoidCallback onMove;
  /// A target tap: place the moving exercise here.
  final VoidCallback onMoveHere;
  /// First-use hint: a gold ring around ⇄ and ⇅.
  final bool showHintRing;
  /// Just placed by a move: a short gold border.
  final bool justMoved;

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
    this.onLogExercise,
    this.onReopenExercise,
    required this.onMove,
    required this.onMoveHere,
    this.moveModeActive = false,
    this.moveRole = MoveRole.none,
    this.moveTargetAbove = false,
    this.canMove = false,
    this.showHintRing = false,
    this.justMoved = false,
  });

  @override
  ConsumerState<_ExerciseCard> createState() => _ExerciseCardState();
}

/// The OS "remove animations" setting: pulses and rings hold still.
bool _motionReduced(BuildContext c) => MediaQuery.disableAnimationsOf(c);

class _ExerciseCardState extends ConsumerState<_ExerciseCard>
    with SingleTickerProviderStateMixin {
  // Move-mode target glow and first-use hint ring (1.7 s). Created on first
  // need, runs only while one of them shows and motion is allowed.
  AnimationController? _pulse;
  // Per-set controllers: index by set number
  late List<TextEditingController> _weightControllers;
  late List<TextEditingController> _repsControllers;
  late List<TextEditingController> _durationControllers;
  late List<TextEditingController> _distanceControllers;

  // One LOG per exercise: per-set focus nodes (so a blocked LOG can focus the
  // failing field). Owned here, in step with the four controller lists:
  // created in _initControllers, appended / retired in didUpdateWidget,
  // disposed in dispose. A node leaving the list mid-frame is unfocused and
  // disposed post-frame, never while its TextField may still be mounted.
  List<FocusNode> _weightFocus = [];
  List<FocusNode> _repsFocus = [];
  List<FocusNode> _durationFocus = [];
  List<FocusNode> _distanceFocus = [];

  // LOG mode, batch 2 mirror: set 1's typed value copies into blank, untouched
  // fields of later sets. `_mirrored[field][set]` is the text the mirror last
  // wrote there: a set still holding it (or blank) is a FOLLOWER; a value the
  // user typed is never written again. Starts empty, so prefilled values never
  // follow. `_lastSourceText` tells which source field actually changed (one
  // onChanged per row).
  final Map<SetField, Map<int, String>> _mirrored = {};
  Map<SetField, String> _lastSourceText = {};
  int? _lastSourceIndex;

  int get _numSets => int.tryParse(widget.exercise.sets) ?? 3;

  bool get _logMode => widget.onLogExercise != null;

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
      weightValue = formatWeightDisplayValue(w);
    } else {
      final raw = exercise.weight.replaceAll('kg', '').replaceAll('BW', '').trim();
      weightValue = (raw != '0' && raw.isNotEmpty) ? raw : '';
    }

    _weightControllers = List.generate(n, (_) => TextEditingController(text: weightValue));
    _repsControllers = List.generate(n, (_) => TextEditingController(text: repsValue));
    // Bug e8f95e — this used to seed with `repsValue` (a copy-paste of the reps
    // line above). LastPerformanceData carries no duration field (only
    // lastWeight/lastReps), so there is no legitimate prefill source for
    // duration — leave it empty, exactly like `_distanceControllers` below,
    // which has the same "no prefill data" shape. `_captureSetValues` parses
    // BOTH this and the reps controller unconditionally regardless of which
    // one the active `set_input_row.dart` actually renders for this
    // exercise's `loggingType`, so a non-empty seed here silently leaks into
    // `SetInputValues.durationSeconds` even when the user never saw or
    // touched a duration field.
    _durationControllers = List.generate(n, (_) => TextEditingController());
    _distanceControllers = List.generate(n, (_) => TextEditingController());

    // Restore any values already captured in the provider (e.g. after widget rebuild).
    // This prevents controller text from resetting to defaults when Riverpod state changes.
    final savedValues = ref.read(activeWorkoutProvider).setInputValues;
    // Sets with nothing captured yet: this is their FIRST init, so their
    // prefill is app-filled (marked suggested after the frame, LOG mode).
    final firstInit = <int>{};
    for (int s = 0; s < n; s++) {
      final captured = savedValues['${widget.exerciseIndex}-$s'];
      if (captured == null) {
        firstInit.add(s);
        continue;
      }
      if (_logMode) {
        // LOG mode captures every keystroke, so a captured null is a field
        // the user CLEARED: restore it blank, never the prefill (flip §2).
        _weightControllers[s].text = captured.weight == null
            ? ''
            : formatWeightDisplayValue(captured.weight!);
        _repsControllers[s].text = captured.reps?.toString() ?? '';
        _durationControllers[s].text =
            captured.durationSeconds?.toString() ?? '';
        _distanceControllers[s].text = captured.distanceKm?.toString() ?? '';
        continue;
      }
      if (captured.weight != null) {
        _weightControllers[s].text = formatWeightDisplayValue(captured.weight!);
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

    // After the restore loop, so the first edit compares against what is shown.
    _mirrored.clear();
    _baselineMirrorSource(ref.read(activeWorkoutProvider));
    if (_logMode) _reseedMirrorFollowers(ref.read(activeWorkoutProvider));

    _resetFocusNodes(n);

    // Pre-seed provider state with controller values so that the receipt card
    // and exercise logger have correct data even if the user checks a set
    // without editing the pre-filled weight/reps fields.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final n = _weightControllers.length;
      if (_logMode) {
        // One write: the captures and the first-init suggested marks.
        ref.read(activeWorkoutProvider.notifier).recordCardEdit(
          widget.exerciseIndex,
          values: {for (var s = 0; s < n; s++) s: _valuesOf(s)},
          mark: {
            for (final s in firstInit)
              if (s < n) ..._nonEmptyMirrorKeys(s),
          },
        );
        return;
      }
      for (int s = 0; s < n; s++) {
        _captureSetValues(s);
      }
    });
  }

  /// The suggested keys of set [setIdx]'s non-empty rendered (mirror) fields.
  Set<String> _nonEmptyMirrorKeys(int setIdx) => {
        for (final f in mirrorFieldsFor(widget.exercise.loggingType))
          if (_controllersOf(f)[setIdx].text.trim().isNotEmpty)
            suggestedKey(widget.exerciseIndex, setIdx, f),
      };

  /// LOG mode, after a re-init (flip §2, R5B-04): `_mirrored` restarts empty,
  /// so followers the mirror made would stop following. While the source's
  /// own field is NOT suggested (the user typed it), a later set whose field
  /// is still suggested and holds the source's text came from the mirror:
  /// mark it a follower again. A history prefill (source still suggested)
  /// stays non-following, as before.
  void _reseedMirrorFollowers(ActiveWorkoutData data) {
    final source = _lastSourceIndex;
    if (source == null) return;
    final warm = _warmUpFlags(data);
    for (final f in mirrorFieldsFor(widget.exercise.loggingType)) {
      if (data.suggestedInputs
          .contains(suggestedKey(widget.exerciseIndex, source, f))) {
        continue;
      }
      final controllers = _controllersOf(f);
      final text = controllers[source].text;
      if (text.trim().isEmpty) continue;
      for (var t = source + 1; t < controllers.length; t++) {
        if (t < warm.length && warm[t]) continue;
        if (!data.suggestedInputs
            .contains(suggestedKey(widget.exerciseIndex, t, f))) {
          continue;
        }
        if (controllers[t].text != text) continue;
        _mirrored.putIfAbsent(f, () => {})[t] = text;
      }
    }
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse(); // the reduce-motion setting can change while mounted
  }

  /// Run the 1.7 s pulse only while a target glow or the hint ring shows and
  /// the OS allows motion; otherwise hold it still (fully lit).
  void _syncPulse() {
    final wants = (widget.moveRole == MoveRole.target || widget.showHintRing) &&
        !_motionReduced(context);
    if (wants) {
      final p = _pulse ??= AnimationController(
          vsync: this, duration: const Duration(milliseconds: 1700));
      if (!p.isAnimating) p.repeat(reverse: true);
    } else if (_pulse != null) {
      _pulse!
        ..stop()
        ..value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _ExerciseCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
    final oldCount = int.tryParse(oldWidget.exercise.sets) ?? 3;
    final newCount = int.tryParse(widget.exercise.sets) ?? 3;

    // Exercise swap: full rebuild needed (different pre-fills, weight, reps).
    if (oldWidget.exercise.name != widget.exercise.name) {
      _disposeControllers();
      _initControllers();
      return;
    }

    // Set count unchanged: only a warm-up toggle can have moved the source.
    if (newCount == oldCount) {
      _rebaselineIfSourceMoved();
      return;
    }

    if (newCount > oldCount) {
      // Append: preserve [0..oldCount-1] controllers, add new ones for the rest.
      for (var i = oldCount; i < newCount; i++) {
        _weightControllers.add(TextEditingController());
        _repsControllers.add(TextEditingController());
        _durationControllers.add(TextEditingController());
        _distanceControllers.add(TextEditingController());
      }
      if (_logMode) _seedAppendedSets(oldCount, newCount);
    } else {
      // Shrink: dispose trailing controllers from [newCount..oldCount-1].
      for (var i = oldCount - 1; i >= newCount; i--) {
        _weightControllers.removeAt(i).dispose();
        _repsControllers.removeAt(i).dispose();
        _durationControllers.removeAt(i).dispose();
        _distanceControllers.removeAt(i).dispose();
      }
      for (final marks in _mirrored.values) {
        marks.removeWhere((set, _) => set >= newCount);
      }
    }
    _resizeFocusNodes(newCount);
    _rebaselineIfSourceMoved();
  }

  /// LOG mode: a warm-up toggle (or `+`/`-`) can move the mirror source.
  /// Re-baseline on the rebuild that shows it, so the FIRST keystroke in the
  /// new source mirrors (a one-digit entry is the whole entry; B-pass finding 2).
  void _rebaselineIfSourceMoved() {
    if (!_logMode) return;
    final data = ref.read(activeWorkoutProvider);
    if (mirrorSourceIndex(_warmUpFlags(data)) != _lastSourceIndex) {
      _baselineMirrorSource(data);
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
    _pulse?.dispose();
    _disposeControllers();
    for (final n in [
      ..._weightFocus,
      ..._repsFocus,
      ..._durationFocus,
      ..._distanceFocus,
    ]) {
      n.dispose();
    }
    super.dispose();
  }

  List<FocusNode> _newFocusNodes(int n) =>
      List.generate(n, (_) => FocusNode(), growable: true);

  /// Unfocus now, dispose after the frame (the TextField holding the node is
  /// rebuilt without it during this frame).
  void _retireFocusNodes(List<FocusNode> nodes) {
    if (nodes.isEmpty) return;
    for (final n in nodes) {
      n.unfocus();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final n in nodes) {
        n.dispose();
      }
    });
  }

  void _resetFocusNodes(int n) {
    _retireFocusNodes([
      ..._weightFocus,
      ..._repsFocus,
      ..._durationFocus,
      ..._distanceFocus,
    ]);
    _weightFocus = _newFocusNodes(n);
    _repsFocus = _newFocusNodes(n);
    _durationFocus = _newFocusNodes(n);
    _distanceFocus = _newFocusNodes(n);
  }

  void _resizeFocusNodes(int n) {
    final retired = <FocusNode>[];
    for (final list in [_weightFocus, _repsFocus, _durationFocus, _distanceFocus]) {
      while (list.length < n) {
        list.add(FocusNode());
      }
      while (list.length > n) {
        retired.add(list.removeLast());
      }
    }
    _retireFocusNodes(retired);
  }

  SetTexts _textsOf(int setIdx) => SetTexts(
        weight: _weightControllers[setIdx].text,
        reps: _repsControllers[setIdx].text,
        duration: _durationControllers[setIdx].text,
        distance: _distanceControllers[setIdx].text,
      );

  SetValidation _validationOf(int setIdx) {
    final t = _textsOf(setIdx);
    return validateSetInputs(
      loggingType: widget.exercise.loggingType,
      weightText: t.weight,
      repsText: t.reps,
      durationText: t.duration,
      distanceText: t.distance,
    );
  }

  /// LOG mode, `+`: seed the appended sets FIELD-FOR-FIELD from the last
  /// non-warm-up set, then record them after the frame (a provider write must
  /// not happen inside didUpdateWidget, which runs during build), so the added
  /// set survives leaving and re-entering the screen (_initControllers
  /// restores only captured keys).
  void _seedAppendedSets(int oldCount, int newCount) {
    final existing = [for (var i = 0; i < oldCount; i++) _textsOf(i)];
    final warm = [
      for (var i = 0; i < oldCount; i++)
        widget.data.isSetWarmUp(widget.exerciseIndex, i),
    ];
    final seed = seedForAddedSet(existing, warm);
    for (var i = oldCount; i < newCount; i++) {
      _weightControllers[i].text = seed.weight;
      _repsControllers[i].text = seed.reps;
      _durationControllers[i].text = seed.duration;
      _distanceControllers[i].text = seed.distance;
    }
    // A copy of the mirror source, or of one of its followers, keeps following;
    // a copy of a prefilled or user-typed value is independent.
    final from = seedIndexForAddedSet(warm, oldCount);
    if (from != null) {
      for (final field in mirrorFieldsFor(widget.exercise.loggingType)) {
        final marks = _mirrored[field];
        final fromText = _controllersOf(field)[from].text;
        final follows = from == _lastSourceIndex ||
            (marks != null && marks[from] == fromText);
        if (!follows) continue;
        final m = _mirrored.putIfAbsent(field, () => {});
        for (var i = oldCount; i < newCount; i++) {
          m[i] = _controllersOf(field)[i].text;
        }
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final end = newCount < _weightControllers.length
          ? newCount
          : _weightControllers.length;
      // One write: the appended sets' values and their seeded fields as
      // suggested (app-filled until the user types).
      ref.read(activeWorkoutProvider.notifier).recordCardEdit(
        widget.exerciseIndex,
        values: {for (var i = oldCount; i < end; i++) i: _valuesOf(i)},
        mark: {for (var i = oldCount; i < end; i++) ..._nonEmptyMirrorKeys(i)},
      );
    });
  }

  /// LOG mode, every keystroke (flip §2): ONE `recordCardEdit` captures the
  /// edited set and every mirror target, clears the edited field's suggested
  /// key (the user typed it) and marks or clears each target's.
  ///
  /// An edit to an already-LOGGED set records only a VALID value: a cleared or
  /// out-of-range field keeps the last valid value, so a 0×0 or 61-rep set can
  /// never reach completeWorkout. An unlogged set records its raw text, so a
  /// card re-init restores what the user typed (completeWorkout reads only
  /// checked sets).
  void _onFieldChanged(int setIdx, SetField field) {
    if (!_logMode || setIdx >= _weightControllers.length) return;
    final data = ref.read(activeWorkoutProvider);
    // Review mode: completeWorkout will not save again, so a capture here would
    // only make the header volume disagree with the saved log.
    if (data.isSaved) return;
    final written = _mirrorFrom(setIdx, data);
    final ex = widget.exerciseIndex;
    final values = <int, SetInputValues>{};
    final mark = <String>{};
    final clear = <String>{suggestedKey(ex, setIdx, field)};
    if (!data.isSetChecked(ex, setIdx) || _validationOf(setIdx).isOk) {
      values[setIdx] = _valuesOf(setIdx);
    }
    written.forEach((f, targets) {
      for (final t in targets) {
        values[t] = _valuesOf(t);
        final key = suggestedKey(ex, t, f);
        if (_controllersOf(f)[t].text.trim().isEmpty) {
          clear.add(key);
        } else {
          mark.add(key);
        }
      }
    });
    ref
        .read(activeWorkoutProvider.notifier)
        .recordCardEdit(ex, values: values, mark: mark, clear: clear);
  }

  List<TextEditingController> _controllersOf(SetField field) =>
      switch (field) {
        SetField.weight => _weightControllers,
        SetField.reps => _repsControllers,
        SetField.duration => _durationControllers,
        SetField.distance => _distanceControllers,
      };

  /// Warm-up flags from the FRESH provider state, never the build-time
  /// `widget.data` (OI-355).
  List<bool> _warmUpFlags(ActiveWorkoutData data) => [
        for (var i = 0; i < _weightControllers.length; i++)
          data.isSetWarmUp(widget.exerciseIndex, i),
      ];

  void _baselineMirrorSource(ActiveWorkoutData data) {
    final source = mirrorSourceIndex(_warmUpFlags(data));
    _lastSourceIndex = source;
    _lastSourceText = source == null
        ? {}
        : {
            for (final field in SetField.values)
              field: _controllersOf(field)[source].text,
          };
  }

  /// Copies each source field the user just changed into its followers. The
  /// rebuild after a warm-up toggle normally re-baselines first
  /// (_rebaselineIfSourceMoved); if a keystroke still sees a moved source, it
  /// re-baselines and copies nothing. Writes controller text only and returns
  /// the sets it wrote, per field (the caller records them).
  Map<SetField, List<int>> _mirrorFrom(int setIdx, ActiveWorkoutData data) {
    final written = <SetField, List<int>>{};
    final warm = _warmUpFlags(data);
    final source = mirrorSourceIndex(warm);
    if (source == null) return written;
    if (source != _lastSourceIndex) {
      _baselineMirrorSource(data);
      return written;
    }
    if (setIdx != source) return written;
    final logged = [
      for (var i = 0; i < _weightControllers.length; i++)
        data.isSetChecked(widget.exerciseIndex, i),
    ];
    for (final field in mirrorFieldsFor(widget.exercise.loggingType)) {
      final controllers = _controllersOf(field);
      final text = controllers[source].text;
      if (text == _lastSourceText[field]) continue;
      _lastSourceText[field] = text;
      final marks = _mirrored.putIfAbsent(field, () => {});
      final targets = mirrorTargets(
        source: source,
        texts: [for (final c in controllers) c.text],
        lastMirrored: marks,
        isWarmUp: warm,
        isLogged: logged,
      );
      for (final t in targets) {
        controllers[t].text = text;
        marks[t] = text;
      }
      if (targets.isNotEmpty) written[field] = targets;
    }
    return written;
  }

  FocusNode? _focusNodeFor(int setIdx, SetField field) {
    final list = switch (field) {
      SetField.weight => _weightFocus,
      SetField.reps => _repsFocus,
      SetField.duration => _durationFocus,
      SetField.distance => _distanceFocus,
    };
    return setIdx < list.length ? list[setIdx] : null;
  }

  /// Blocked LOG: focus the failing field and open the keypad.
  void _focusFailingField(int setIdx, SetField field) {
    final node = _focusNodeFor(setIdx, field);
    if (node == null) return;
    FocusScope.of(context).requestFocus(node);
  }

  void _onLogPressed() {
    final data = ref.read(activeWorkoutProvider);
    if (data.isSaved) return;
    final numSets = _numSets;
    final toLog = setsToLog(
      exerciseIndex: widget.exerciseIndex,
      numSets: numSets,
      checkedSets: data.checkedSets,
    );
    if (toLog.isEmpty) return;
    for (final i in toLog) {
      final v = _validationOf(i);
      if (!v.isOk) {
        _focusFailingField(i, v.field!);
        return;
      }
    }
    // Record every set before logging: the unchecked ones being logged, and any
    // already-logged one whose current text is valid (an invalid edit keeps its
    // last valid value, as in _onFieldChanged).
    for (var i = 0; i < numSets && i < _weightControllers.length; i++) {
      if (toLog.contains(i) || _validationOf(i).isOk) _captureSetValues(i);
    }
    final outcome = widget.onLogExercise!(toLog);
    if (outcome == LogOutcomeKind.logged) _persistLoggedState(toLog.last);
  }

  /// LOG-mode twin of [_persistActiveState]: the completed count comes from
  /// the provider AFTER logSets (the shared helper reads the build-time
  /// `widget.data`, OI-355, and is left untouched for the per-set path).
  void _persistLoggedState(int setIdx) {
    final numSets = _numSets;
    final data = ref.read(activeWorkoutProvider);
    final completed = List.generate(
            numSets, (i) => data.isSetChecked(widget.exerciseIndex, i))
        .where((c) => c)
        .length;
    final t = setIdx < _weightControllers.length
        ? _textsOf(setIdx)
        : const SetTexts();
    ActiveWorkoutPersistence.writeState(
      exerciseName: widget.exercise.name,
      currentSet: completed.clamp(1, numSets),
      totalSets: numSets,
      weight: double.tryParse(t.weight),
      repsTarget: int.tryParse(widget.exercise.reps) ??
          _parseRepsMidpoint(widget.exercise.reps),
      repsCompleted: int.tryParse(t.reps) ?? int.tryParse(t.duration) ?? 0,
      rpeHistory: const [],
      restRemainingSecs: null,
    );
  }

  SetInputValues _valuesOf(int setIdx) => SetInputValues(
        weight: double.tryParse(_weightControllers[setIdx].text),
        reps: int.tryParse(_repsControllers[setIdx].text),
        durationSeconds: int.tryParse(_durationControllers[setIdx].text),
        distanceKm: double.tryParse(_distanceControllers[setIdx].text),
      );

  /// Capture current input values and record them into the provider.
  void _captureSetValues(int setIdx) {
    ref.read(activeWorkoutProvider.notifier).recordSetValues(
      widget.exerciseIndex,
      setIdx,
      _valuesOf(setIdx),
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

  /// LOG mode drops the weight segment (it prints the plan's placeholder
  /// weight, OI-352); the per-set path keeps [_metaText] unchanged.
  String _metaTextForLogMode() {
    switch (widget.exercise.loggingType) {
      case 'weighted_bodyweight':
      case 'weight_reps':
        return '${widget.exercise.sets} sets · ${widget.exercise.reps} reps · ${widget.exercise.rest} rest';
      default:
        return _metaText();
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

  /// LOG mode: the sets stepper and the LOG button on ONE row (founder
  /// 2026-10-17). Rebuilt on every keystroke through the merged controller
  /// listenable (built here, from the live lists, so it never goes stale), not
  /// only on the 1 Hz timer rebuild. The tap handler re-validates from the
  /// controllers and the provider, never from this label.
  Widget _buildLogRow(int numSets) {
    final reviewMode = widget.data.isSaved;
    return ListenableBuilder(
      listenable: Listenable.merge([
        ..._weightControllers,
        ..._repsControllers,
        ..._durationControllers,
        ..._distanceControllers,
      ]),
      builder: (context, _) {
        final data = widget.data;
        final toLog = setsToLog(
          exerciseIndex: widget.exerciseIndex,
          numSets: numSets,
          checkedSets: data.checkedSets,
        );
        final working = workingSetsToLog(
          exerciseIndex: widget.exerciseIndex,
          numSets: numSets,
          checkedSets: data.checkedSets,
          warmUpSets: data.warmUpSets,
        );

        // Scan EVERY set, logged ones too: a logged set whose text no longer
        // validates keeps its last valid stored value (_onFieldChanged), so
        // the row must say so instead of reading LOGGED with a blank field.
        SetValidation? failure;
        int? failingSet;
        for (var i = 0; i < numSets; i++) {
          if (i >= _weightControllers.length) continue;
          final v = _validationOf(i);
          if (!v.isOk) {
            failure = v;
            failingSet = i;
            break;
          }
        }

        final Widget button;
        if (failure != null) {
          final v = failure;
          final i = failingSet!;
          button = _LogExerciseButton(
            label: blockedLogLabel(v),
            style: _LogButtonStyle.blocked,
            onTap: reviewMode ? null : () => _focusFailingField(i, v.field!),
          );
        } else if (toLog.isEmpty) {
          button = _LogExerciseButton(
            label: WardroomCopy.activeLoggedLabel,
            style: _LogButtonStyle.logged,
            onTap: reviewMode ? null : widget.onReopenExercise,
          );
        } else {
          final workingIdx = [
            for (final i in toLog)
              if (i < _weightControllers.length &&
                  !data.isSetWarmUp(widget.exerciseIndex, i))
                i,
          ];
          final volume = loggedVolumeKg(
            loggingType: widget.exercise.loggingType,
            weightTexts: [for (final i in workingIdx) _weightControllers[i].text],
            repsTexts: [for (final i in workingIdx) _repsControllers[i].text],
          );
          // PREFILLED while the mirror source's weight is still app-filled
          // (flip §2, R4B-07): typing set 1 makes it the user's own number.
          final source = mirrorSourceIndex(_warmUpFlags(data));
          final sourcePrefilled = source != null &&
              isFaded(
                logMode: true,
                data: data,
                exerciseIndex: widget.exerciseIndex,
                setIndex: source,
                field: SetField.weight,
              );
          button = _LogExerciseButton(
            label: logButtonLabel(working),
            subline: sourcePrefilled
                ? prefilledSubline(volume)
                : liftedSubline(volume),
            style: _LogButtonStyle.ready,
            onTap: reviewMode ? null : _onLogPressed,
          );
        }

        final notifier = ref.read(activeWorkoutProvider.notifier);
        return Row(
          children: [
            _StepperButton(
              icon: Icons.remove,
              semanticLabel: 'Remove last set',
              onTap: (!reviewMode && numSets > 1)
                  ? () => notifier.removeLastSet(widget.exerciseIndex)
                  : null,
            ),
            SizedBox(
              width: 32,
              child: Center(
                child: Text(
                  '$numSets',
                  style: AppTypography.h2.copyWith(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            _StepperButton(
              icon: Icons.add,
              semanticLabel: 'Add a set',
              onTap: reviewMode
                  ? null
                  : () => notifier.addSet(widget.exerciseIndex),
            ),
            const SizedBox(width: 10),
            Expanded(child: button),
          ],
        );
      },
    );
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
    final reduced = _motionReduced(context);
    final isTarget = widget.moveModeActive && widget.moveRole == MoveRole.target;
    // Move mode: a card that is neither moving nor a target (a done one) dims.
    final dimmed = widget.moveModeActive && widget.moveRole == MoveRole.none;

    Widget card = GestureDetector(
        onTap: widget.isInSupersetGroupMode ? widget.onLongPressHeader : null,
        child: AnimatedContainer(
          duration: reduced ? Duration.zero : const Duration(milliseconds: 400),
          decoration: BoxDecoration(
            color: widget.isGroupModeSource
                ? AppColors.accent.withValues(alpha: 0.08)
                : widget.isInSupersetGroupMode
                    ? AppColors.accent.withValues(alpha: 0.03)
                    : AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: widget.justMoved
                  ? AppColors.accent
                  : widget.isGroupModeSource
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
                          onTap: _headerTap,
                          // Move mode owns the header: no superset pairing.
                          onLongPress: widget.moveModeActive
                              ? null
                              : widget.onLongPressHeader,
                          child: Row(
                            children: [
                              // The plate: what this movement LOOKS like. It
                              // replaces a number badge that carried almost
                              // nothing — position in a vertical list is
                              // already obvious — so the header row gains no
                              // element. 44 px is also the minimum touch
                              // target, up from 24.
                              ExercisePlateThumb(
                                exerciseName: widget.exercise.name,
                                size: 44,
                                // Move mode: the plate is part of the header
                                // tap (null lets it reach the header).
                                onTap: widget.moveModeActive
                                    ? null
                                    : () => ExercisePlateSheet.show(
                                        context, widget.exercise.name),
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
                                      _logMode
                                          ? _metaTextForLogMode()
                                          : _metaText(),
                                      style: AppTypography.monoXs.copyWith(
                                        color: AppColors.textDim,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    // Bug #6 — hint when reviewing a completed exercise.
                                    // LOG mode: the LOGGED button says what a tap
                                    // does (TAP TO RE-OPEN), so no second hint.
                                    if (widget.isDone &&
                                        widget.isExpanded &&
                                        !_logMode)
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

                              // ⇄ / ⇅, the move-mode tag, or Done.
                              _headerActions(),

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
                                  // Flexible + ellipsis: at 320 dp and a large
                                  // font this line overflowed (flip R4A-03).
                                  Flexible(
                                    child: Text(
                                      'LAST: ${lastPerf.lastWeight!.toStringAsFixed(1)}KG × ${lastPerf.lastReps ?? '?'} REPS',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTypography.monoXs.copyWith(
                                        color: AppColors.textDim,
                                        letterSpacing: 1.2,
                                      ),
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
                                    interactiveCheck: !_logMode,
                                    weightFocusNode: _logMode ? _focusNodeFor(setIdx, SetField.weight) : null,
                                    repsFocusNode: _logMode ? _focusNodeFor(setIdx, SetField.reps) : null,
                                    durationFocusNode: _logMode ? _focusNodeFor(setIdx, SetField.duration) : null,
                                    distanceFocusNode: _logMode ? _focusNodeFor(setIdx, SetField.distance) : null,
                                    onChanged: _logMode ? (f) => _onFieldChanged(setIdx, f) : null,
                                    fadedFields: {
                                      for (final f in mirrorFieldsFor(widget.exercise.loggingType))
                                        if (isFaded(
                                          logMode: _logMode,
                                          data: widget.data,
                                          exerciseIndex: widget.exerciseIndex,
                                          setIndex: setIdx,
                                          field: f,
                                        ))
                                          f,
                                    },
                                    onCheck: _logMode ? null : () {
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
                        if (_logMode)
                          _buildLogRow(numSets)
                        else
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
      );

    if (isTarget) {
      // A move target: dashed gold outline that breathes (static under
      // reduce motion, where the pulse is held at full).
      final pulse = _pulse ?? kAlwaysCompleteAnimation;
      card = AnimatedBuilder(
        animation: pulse,
        builder: (_, child) => WardDashedBorder(
          color: AppColors.accent.withValues(alpha: 0.45 + 0.45 * pulse.value),
          strokeWidth: 1.5,
          radius: AppRadius.card,
          child: child!,
        ),
        child: card,
      );
    }
    if (dimmed) card = Opacity(opacity: 0.5, child: card);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
      child: card,
    );
  }

  /// The header tap: focus outside move mode; in it, a target places, the
  /// moving card cancels, anything else (a done card) does nothing.
  VoidCallback? get _headerTap {
    if (!widget.moveModeActive) return widget.onFocus;
    return switch (widget.moveRole) {
      MoveRole.target => widget.onMoveHere,
      MoveRole.source => widget.onMove,
      MoveRole.none => null,
    };
  }

  /// Right side of the header, per role (plan Task 5 table).
  Widget _headerActions() {
    const done = WardChip(label: '✓ DONE', tone: WardChipTone.ok);
    if (widget.moveModeActive) {
      switch (widget.moveRole) {
        case MoveRole.target:
          return GestureDetector(
            onTap: widget.onMoveHere,
            child: WardChip(
              label: widget.moveTargetAbove
                  ? WardroomCopy.activeMoveHereUp
                  : WardroomCopy.activeMoveHereDown,
              tone: WardChipTone.gold,
            ),
          );
        case MoveRole.source:
          return Row(mainAxisSize: MainAxisSize.min, children: [
            _HeaderIconButton(
              icon: Icons.swap_horiz,
              label: WardroomCopy.activeSwapExerciseLabel,
              onTap: widget.onSwap,
            ),
            _HeaderIconButton(
              icon: Icons.swap_vert,
              label: WardroomCopy.activeMoveExerciseLabel,
              onTap: widget.onMove,
              filled: true,
            ),
            const WardChip(
                label: WardroomCopy.activeMovingTag, tone: WardChipTone.filled),
          ]);
        case MoveRole.none:
          return widget.isDone ? done : const SizedBox.shrink();
      }
    }
    if (widget.isDone) {
      return GestureDetector(onTap: widget.onFocus, child: done);
    }
    final icons = Row(mainAxisSize: MainAxisSize.min, children: [
      _HeaderIconButton(
        icon: Icons.swap_horiz,
        label: WardroomCopy.activeSwapExerciseLabel,
        onTap: widget.onSwap,
      ),
      if (widget.canMove)
        _HeaderIconButton(
          icon: Icons.swap_vert,
          label: WardroomCopy.activeMoveExerciseLabel,
          onTap: widget.onMove,
        ),
    ]);
    if (!widget.showHintRing) return icons;
    // First-use hint: a gold ring around the icons (static under reduce motion).
    final pulse = _pulse ?? kAlwaysCompleteAnimation;
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, child) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: AppColors.accent.withValues(alpha: 0.4 + 0.5 * pulse.value),
            width: 1.5,
          ),
        ),
        child: child,
      ),
      child: icons,
    );
  }
}

/// A 30 dp round header icon inside a 44 dp touch box (⇄ swap, ⇅ move). The
/// long-press tooltip names it; TalkBack reads [label] as a button.
class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled ? AppColors.accent : AppColors.input,
                  border: Border.all(
                    color: filled ? AppColors.accent : AppColors.border,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: filled ? AppColors.bgDeep : AppColors.accent,
                ),
              ),
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

enum _LogButtonStyle { ready, blocked, logged }

/// The LOG button: gold when ready, a neutral gold outline when a field is
/// missing (approved: never red), muted once every set is logged. A logged
/// button with [onTap] RE-OPENS the exercise (flip batch §1) and says so.
class _LogExerciseButton extends StatelessWidget {
  const _LogExerciseButton({
    required this.label,
    required this.style,
    this.subline,
    this.onTap,
  });

  final String label;
  final String? subline;
  final _LogButtonStyle style;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ready = style == _LogButtonStyle.ready;
    final logged = style == _LogButtonStyle.logged;
    final enabled = onTap != null;
    // The logged style shows TAP TO RE-OPEN only when a tap does something
    // (never in review mode).
    final shownSubline =
        logged ? (enabled ? WardroomCopy.activeReopenSubline : null) : subline;
    final Color fg = ready
        ? AppColors.bgDeep
        : logged
            ? AppColors.ok
            : AppColors.accent;
    // excludeSemantics drops the GestureDetector's own tap action, so the node
    // carries `onTap` itself (flip R4A-01: without it TalkBack cannot press
    // LOG). The logged label is "Logged" and the tap hint "Re-open"; TalkBack
    // adds "double tap to …" itself.
    return Semantics(
      button: true,
      enabled: enabled,
      onTap: onTap,
      onTapHint: logged && enabled ? WardroomCopy.activeReopenHint : null,
      label: logged
          ? WardroomCopy.activeLoggedSemantics
          : (subline == null ? label : '$label. $subline'),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Opacity(
          opacity: (onTap == null && !logged) ? 0.4 : 1,
          child: Container(
            // minHeight, not a fixed height: a two-line subline or a large
            // font grows the button instead of overflowing it.
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: ready
                  ? AppColors.accent
                  : logged
                      ? AppColors.ok.withValues(alpha: 0.08)
                      : AppColors.accentBg,
              borderRadius: BorderRadius.circular(AppRadius.sharp),
              border: ready
                  ? null
                  : Border.all(
                      color: logged
                          ? AppColors.ok.withValues(alpha: 0.3)
                          : AppColors.accent.withValues(alpha: 0.55),
                    ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: (ready || logged
                            ? AppTypography.mono
                            : AppTypography.bodySm)
                        .copyWith(
                      color: fg,
                      fontSize: ready || logged ? 12 : 13,
                      letterSpacing: ready || logged ? 1.6 : 0.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (shownSubline != null)
                  Text(
                    shownSubline,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: AppTypography.monoXs.copyWith(
                      color: fg.withValues(alpha: 0.75),
                      letterSpacing: 1.4,
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

/// 44 px sets-stepper button (LOG mode); the per-set path keeps its 28 px pair.
class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.semanticLabel,
    this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.input,
            borderRadius: BorderRadius.circular(AppRadius.sharp),
            border: Border.all(
              color: enabled
                  ? AppColors.border
                  : AppColors.border.withValues(alpha: 0.3),
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: enabled ? AppColors.textSecondary : AppColors.textDisabled,
          ),
        ),
      ),
    );
  }
}

/// Test seam (plan `docs/plans/active-workout-log-exercise.md` §6): the card is
/// a private `part of` widget, so tests reach it only through this host. It
/// watches the real [activeWorkoutProvider] and wires the card the way the
/// screen does, minus the screen-level focus/advance logic (that lives in
/// `LogExerciseController` and is tested there).
@visibleForTesting
Widget debugExerciseCardHostForTest({
  required int exerciseIndex,
  bool isExpanded = true,
  LogExerciseCallback? onLogExercise,
  VoidCallback? onReopenExercise,
  // ⇄ / ⇅ (docs/plans/active-workout-swap-move.md Task 5).
  VoidCallback? onFocus,
  VoidCallback? onSwap,
  VoidCallback? onLongPressHeader,
  VoidCallback? onMove,
  VoidCallback? onMoveHere,
  bool moveModeActive = false,
  MoveRole moveRole = MoveRole.none,
  bool moveTargetAbove = false,
  bool canMove = false,
  bool showHintRing = false,
  bool justMoved = false,
}) {
  return Consumer(builder: (context, ref, _) {
    final data = ref.watch(activeWorkoutProvider);
    return _ExerciseCard(
      exerciseIndex: exerciseIndex,
      exercise: data.exercises[exerciseIndex],
      isDone: data.isExerciseDone(exerciseIndex),
      isActive: true,
      data: data,
      isExpanded: isExpanded,
      moveModeActive: moveModeActive,
      moveRole: moveRole,
      moveTargetAbove: moveTargetAbove,
      canMove: canMove,
      showHintRing: showHintRing,
      justMoved: justMoved,
      onMove: onMove ?? () {},
      onMoveHere: onMoveHere ?? () {},
      onFocus: onFocus ?? () {},
      onToggleSet: (setIdx) => ref
          .read(activeWorkoutProvider.notifier)
          .toggleSet(exerciseIndex, setIdx),
      onToggleWarmUp: (setIdx) => ref
          .read(activeWorkoutProvider.notifier)
          .toggleWarmUp(exerciseIndex, setIdx),
      onSwap: onSwap ?? () {},
      onLongPressHeader: onLongPressHeader ?? () {},
      onLogExercise: onLogExercise,
      onReopenExercise: onReopenExercise,
    );
  });
}
