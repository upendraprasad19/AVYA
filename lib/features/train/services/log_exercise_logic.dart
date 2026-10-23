// One LOG per exercise (flag `enable_log_exercise_button`): the pure decision
// logic behind the LOG button, kept out of the private `part of` widgets so it
// is unit-testable. Plan: docs/plans/active-workout-log-exercise.md §5.
import 'package:icanbefitter/core/copy/set_log_copy.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import '../providers/train_provider.dart';

/// The input field a set's validation failed on.
enum SetField { weight, reps, duration, distance }

/// `empty`: nothing usable typed (label "Add …"). `outOfRange`: a value is
/// present but rejected, e.g. reps above 60 or more than 360 minutes
/// (label "Fix …").
enum SetFailureKind { empty, outOfRange }

class SetValidation {
  const SetValidation.ok()
      : field = null,
        kind = null,
        message = null;
  const SetValidation.failure(SetField this.field, SetFailureKind this.kind,
      String this.message);

  final SetField? field;
  final SetFailureKind? kind;
  final String? message;

  bool get isOk => field == null;
}

/// OI-389 (D2): cardio minutes as typed ("12.5", "12.", ".5") → whole
/// seconds, `(min × 60).round()`. Null when the text does not parse ("."
/// or "1.2.3"). The ONE parser: the validator, the workout card's capture
/// and the edit sheet all use it, so `SetInputValues.durationSeconds` holds
/// true seconds for every type.
int? cardioMinutesToSeconds(String text) {
  final minutes = double.tryParse(text.trim());
  if (minutes == null || minutes.isNaN || minutes.isInfinite) return null;
  return (minutes * 60).round();
}

/// The box text for [secs] of cardio: decimal minutes with at most 2
/// decimals, trailing zeros trimmed (750 → "12.5", 735 → "12.25",
/// 30 → "0.5", 1800 → "30"). Two decimals round-trip exactly through
/// [cardioMinutesToSeconds].
String secondsToMinutesInput(int secs) {
  var t = (secs / 60).toStringAsFixed(2);
  if (t.contains('.')) {
    t = t.replaceFirst(RegExp(r'0+$'), '');
    if (t.endsWith('.')) t = t.substring(0, t.length - 1);
  }
  return t;
}

/// The set a captured row of boxes stands for (OI-389 U5), for the one
/// logging type the slot shows: [fieldsClearedFor]'s table, a km <= 0 stored
/// as absent. [v]'s duration is already seconds (converted at capture).
ExerciseSet exerciseSetFromInput(
  SetInputValues v,
  String loggingType,
  int loggedAtMs,
) {
  final dur = v.durationSeconds;
  final km = ExerciseSet.canonicalKm(v.distanceKm);
  final cleared = fieldsClearedFor(
    loggingType,
    hasDuration: (dur ?? 0) > 0,
    hasKm: km != null,
  );
  return ExerciseSet(
    weightKg: cleared.weight ? 0 : (v.weight ?? 0),
    reps: cleared.reps ? 0 : (v.reps ?? 0),
    durationSec: cleared.duration ? null : dur,
    distanceKm: cleared.distance ? null : km,
    loggedAtMs: loggedAtMs,
  );
}

/// Same bounds as `exercise_card.dart` `_repsMin`/`_repsMax` (the cloud CHECK
/// added in migration 060; diagnose 2026-05-12-rep-validation-e6a2d4).
const int kLogRepsMin = 1;
const int kLogRepsMax = 60;

// Messages are VERBATIM copies of `_validateSetInputs` / `_validateRepsBound`
// in exercise_card.dart (pinned by a parity test). The OFF path keeps its own
// method untouched.
const String kEnterWeightMessage = 'Enter weight before marking complete';
const String kEnterRepsMessage = 'Enter reps before marking complete';
const String kRepsTooHighMessage =
    'Reps must be ≤ $kLogRepsMax per set. Typo? Cloud rejects values above this.';
const String kEnterDurationMessage = 'Enter duration before marking complete';
const String kEnterDistanceMessage = 'Enter distance before marking complete';

/// Structured twin of `_ExerciseCardState._validateSetInputs`: same field
/// order, same messages, plus WHICH field failed and HOW, so the LOG button
/// can label itself and focus that field.
///
/// The `kind` is new: a value that is present but unusable (an unparseable
/// duration, or one past a set's bound) is `outOfRange`, where the OFF
/// validator reports it as missing.
///
/// OI-389 (D2): cardio minutes take decimals ("12.5" = 750 s) through
/// [cardioMinutesToSeconds]; timed seconds stay whole. Bounds (OI-382): a set
/// holds at most 21600 s (360 min) and 300 km.
SetValidation validateSetInputs({
  required String loggingType,
  String weightText = '',
  String repsText = '',
  String durationText = '',
  String distanceText = '',
}) {
  SetValidation reps() {
    final r = int.tryParse(repsText.trim()) ?? 0;
    if (r < kLogRepsMin) {
      return const SetValidation.failure(
          SetField.reps, SetFailureKind.empty, kEnterRepsMessage);
    }
    if (r > kLogRepsMax) {
      return const SetValidation.failure(
          SetField.reps, SetFailureKind.outOfRange, kRepsTooHighMessage);
    }
    return const SetValidation.ok();
  }

  SetValidation duration() {
    final t = durationText.trim();
    if (loggingType == 'cardio') {
      if (t.isEmpty) {
        return const SetValidation.failure(
            SetField.duration, SetFailureKind.empty, kEnterDurationMessage);
      }
      final minutes = double.tryParse(t);
      final secs = cardioMinutesToSeconds(t);
      if (minutes == null || secs == null) {
        return const SetValidation.failure(
            SetField.duration, SetFailureKind.outOfRange, kEnterDurationMessage);
      }
      if (minutes <= 0) {
        return const SetValidation.failure(
            SetField.duration, SetFailureKind.empty, kEnterDurationMessage);
      }
      if (secs < 1) {
        return const SetValidation.failure(SetField.duration,
            SetFailureKind.outOfRange, kSetMinimumSecondMessage);
      }
      if (secs > kMaxSetDurationSec) {
        return const SetValidation.failure(
            SetField.duration, SetFailureKind.outOfRange, kSetMinutesMaxMessage);
      }
      return const SetValidation.ok();
    }
    final d = int.tryParse(t);
    if (d == null && t.isNotEmpty) {
      return const SetValidation.failure(
          SetField.duration, SetFailureKind.outOfRange, kEnterDurationMessage);
    }
    if ((d ?? 0) <= 0) {
      return const SetValidation.failure(
          SetField.duration, SetFailureKind.empty, kEnterDurationMessage);
    }
    if (d! > kMaxSetDurationSec) {
      return const SetValidation.failure(
          SetField.duration, SetFailureKind.outOfRange, kSetSecondsMaxMessage);
    }
    return const SetValidation.ok();
  }

  /// OI-382: a km above 300 is refused wherever a KM box exists.
  SetValidation? kmTooFar() {
    final km = double.tryParse(distanceText.trim()) ?? 0;
    return km > kMaxSetDistanceKm
        ? const SetValidation.failure(
            SetField.distance, SetFailureKind.outOfRange, kSetKmMaxMessage)
        : null;
  }

  switch (loggingType) {
    case 'weight_reps':
      final weight = double.tryParse(weightText.trim()) ?? 0;
      if (weight <= 0) {
        return const SetValidation.failure(
            SetField.weight, SetFailureKind.empty, kEnterWeightMessage);
      }
      return reps();
    case 'bodyweight_reps':
    case 'weighted_bodyweight':
      return reps();
    case 'timed':
      return duration();
    case 'cardio':
      final d = duration();
      if (!d.isOk) return d;
      return kmTooFar() ?? const SetValidation.ok();
    case 'distance':
      final distance = double.tryParse(distanceText.trim()) ?? 0;
      if (distance <= 0) {
        return const SetValidation.failure(
            SetField.distance, SetFailureKind.empty, kEnterDistanceMessage);
      }
      return kmTooFar() ?? const SetValidation.ok();
    default:
      return const SetValidation.ok();
  }
}

/// The blocked LOG button's label: the single field-to-label table.
String blockedLogLabel(SetValidation v) {
  final fix = v.kind == SetFailureKind.outOfRange;
  switch (v.field) {
    case SetField.weight:
      return fix
          ? WardroomCopy.activeBlockedFixWeight
          : WardroomCopy.activeBlockedAddWeight;
    case SetField.reps:
      return fix
          ? WardroomCopy.activeBlockedFixReps
          : WardroomCopy.activeBlockedAddReps;
    case SetField.duration:
      return fix
          ? WardroomCopy.activeBlockedFixTime
          : WardroomCopy.activeBlockedAddTime;
    case SetField.distance:
      return fix
          ? WardroomCopy.activeBlockedFixDistance
          : WardroomCopy.activeBlockedAddDistance;
    case null:
      return '';
  }
}

/// Every UNCHECKED set of the exercise, warm-ups included: LOG checks them
/// all, otherwise `isExerciseDone` (which requires every set) never flips.
Set<int> setsToLog({
  required int exerciseIndex,
  required int numSets,
  required Map<String, bool> checkedSets,
}) {
  return {
    for (var i = 0; i < numSets; i++)
      if (!checkedSets.containsKey('$exerciseIndex-$i')) i,
  };
}

/// The `{n}` on the LOG button: unchecked WORKING sets (warm-ups excluded, as
/// in `completedSets`).
int workingSetsToLog({
  required int exerciseIndex,
  required int numSets,
  required Map<String, bool> checkedSets,
  required Map<String, bool> warmUpSets,
}) {
  var n = 0;
  for (var i = 0; i < numSets; i++) {
    final key = '$exerciseIndex-$i';
    if (!checkedSets.containsKey(key) && !warmUpSets.containsKey(key)) n++;
  }
  return n;
}

/// `LOG {n} SETS ✓`, `LOG 1 SET ✓`, or `LOG ✓` when only warm-ups remain.
String logButtonLabel(int workingSets) {
  if (workingSets <= 0) return WardroomCopy.activeLogCta;
  if (workingSets == 1) return WardroomCopy.activeLogOneSetCta;
  return WardroomCopy.activeLogSetsCtaTemplate
      .replaceAll('{n}', '$workingSets');
}

/// Projected volume of the sets about to be logged: `sum(weight × reps)`, the
/// `liveVolumeKg` formula. 0 for a logging type that carries no load.
double loggedVolumeKg({
  required String loggingType,
  required List<String> weightTexts,
  required List<String> repsTexts,
}) {
  if (loggingType != 'weight_reps' && loggingType != 'weighted_bodyweight') {
    return 0;
  }
  var vol = 0.0;
  for (var i = 0; i < weightTexts.length && i < repsTexts.length; i++) {
    final w = double.tryParse(weightTexts[i].trim()) ?? 0;
    final r = int.tryParse(repsTexts[i].trim()) ?? 0;
    if (w > 0 && r > 0) vol += w * r;
  }
  return vol;
}

/// `{kg} KG LIFTED`, or null (subline hidden) when there is no volume.
String? liftedSubline(double volumeKg) {
  if (volumeKg <= 0) return null;
  return WardroomCopy.activeLiftedSublineTemplate
      .replaceAll('{kg}', formatKg(volumeKg));
}

/// `{kg} KG · PREFILLED`: the subline while the mirror source's weight is still
/// app-filled (docs/plans/log-exercise-flip.md §2). Null without volume.
String? prefilledSubline(double volumeKg) {
  if (volumeKg <= 0) return null;
  return WardroomCopy.activePrefilledSublineTemplate
      .replaceAll('{kg}', formatKg(volumeKg));
}

// ── Faded prefill (flip batch, docs/plans/log-exercise-flip.md §2) ─────────

/// The `ActiveWorkoutData.suggestedInputs` key of one field. The provider
/// stores plain strings (`SetField.name`): this file imports the provider.
String suggestedKey(int exerciseIndex, int setIndex, SetField field) =>
    '$exerciseIndex-$setIndex-${field.name}';

/// A field renders faded (app-filled, not yet touched) only in LOG mode, never
/// in review mode, never on a logged set.
bool isFaded({
  required bool logMode,
  required ActiveWorkoutData data,
  required int exerciseIndex,
  required int setIndex,
  required SetField field,
}) {
  if (!logMode || data.isSaved) return false;
  if (data.isSetChecked(exerciseIndex, setIndex)) return false;
  return data.suggestedInputs
      .contains(suggestedKey(exerciseIndex, setIndex, field));
}

/// A volume rounded to one decimal, with a whole number shown without `.0`
/// (`1200`, `142.5`). Shared by the LOG subline and the UNDO toast.
String formatKg(double volumeKg) {
  final rounded = double.parse(volumeKg.toStringAsFixed(1));
  return rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : rounded.toString();
}

/// The four input texts of one set.
class SetTexts {
  const SetTexts({
    this.weight = '',
    this.reps = '',
    this.duration = '',
    this.distance = '',
  });
  final String weight;
  final String reps;
  final String duration;
  final String distance;
}

/// Prefill for a set added with `+`: copied FIELD-FOR-FIELD from the last
/// non-warm-up set (never one field from another — bug e8f95e), else from the
/// last set, else blank.
SetTexts seedForAddedSet(List<SetTexts> existing, List<bool> isWarmUp) {
  final i = seedIndexForAddedSet(isWarmUp, existing.length);
  if (i != null) return existing[i];
  return existing.isEmpty ? const SetTexts() : existing.last;
}

/// The set a `+` copies: the last non-warm-up of the first [count] sets, or
/// null when there is none (then [seedForAddedSet] falls back to the last set).
int? seedIndexForAddedSet(List<bool> isWarmUp, int count) {
  for (var i = count - 1; i >= 0; i--) {
    final warm = i < isWarmUp.length && isWarmUp[i];
    if (!warm) return i;
  }
  return null;
}

// ── Mirror (batch 2, docs/plans/log-exercise-batch2.md §5.2) ─────────────
// Set 1's typed value copies into blank, untouched fields of the same
// exercise. Card-local: these helpers decide, the card writes controller text.

/// The fields that mirror for a logging type: what `SetInputRow` renders,
/// minus reps (always prefilled).
Set<SetField> mirrorFieldsFor(String loggingType) {
  switch (loggingType) {
    case 'bodyweight_reps':
      return const {};
    case 'timed':
      return const {SetField.duration};
    case 'cardio':
      return const {SetField.duration, SetField.distance};
    case 'distance':
      return const {SetField.distance, SetField.weight};
    default: // weight_reps, weighted_bodyweight
      return const {SetField.weight};
  }
}

/// The set that mirrors: the first non-warm-up set, or null when every set is
/// a warm-up.
int? mirrorSourceIndex(List<bool> isWarmUp) {
  for (var i = 0; i < isWarmUp.length; i++) {
    if (!isWarmUp[i]) return i;
  }
  return null;
}

/// The sets one field of the source copies into: after the source, not a
/// warm-up, not logged, and still a FOLLOWER (blank, or holding exactly the
/// value the mirror last wrote there). A field the user changed is never
/// written again.
List<int> mirrorTargets({
  required int source,
  required List<String> texts,
  required Map<int, String> lastMirrored,
  required List<bool> isWarmUp,
  required List<bool> isLogged,
}) {
  return [
    for (var t = source + 1; t < texts.length; t++)
      if (!(t < isWarmUp.length && isWarmUp[t]) &&
          !(t < isLogged.length && isLogged[t]) &&
          (texts[t].trim().isEmpty || texts[t] == lastMirrored[t]))
        t,
  ];
}

/// After LOG advances the screen to the next exercise, that exercise's LOG
/// button lands under the same thumb. Taps on LOG inside this window are
/// ignored.
const Duration kLogInputGuard = Duration(milliseconds: 400);

/// The window after an advance that SCROLLS: a superset reveal (200 ms delay +
/// 400 ms `ensureVisible`, screen.dart) or a RE-OPEN's focus scroll (60 + 400
/// ms). A LOG tap inside it would land on moving content.
const Duration kRevealGuard = Duration(milliseconds: 700);

/// A RE-OPEN tap this soon after an advancing LOG is ignored: the "did it
/// register?" second tap on the button that just turned into LOGGED.
const Duration kReopenGuard = Duration(milliseconds: 1200);

/// [now] and [lastAdvanceAt] come from a MONOTONIC clock (never `nowWall()`,
/// which is frozen under the dev clock override and would swallow every LOG).
bool shouldIgnoreLog({
  required Duration now,
  required Duration? lastAdvanceAt,
  Duration window = kLogInputGuard,
}) {
  if (lastAdvanceAt == null) return false;
  return now - lastAdvanceAt < window;
}

/// The first not-yet-done superset partner of [exerciseIndex], to scroll to.
int? supersetPartnerToReveal(ActiveWorkoutData data, int exerciseIndex) {
  if (exerciseIndex < 0 || exerciseIndex >= data.exercises.length) return null;
  for (final p in data.getSupersetPartners(exerciseIndex)) {
    if (!data.isExerciseDone(p)) return p;
  }
  return null;
}

enum LogOutcomeKind { ignored, logged, reopened, noop }

class LogOutcome {
  const LogOutcome(this.kind, {this.clearFocus = false, this.revealPartner});
  final LogOutcomeKind kind;

  /// The exercise is now done: clear the manual focus so the screen's
  /// first-non-done fallback expands the next exercise.
  final bool clearFocus;

  /// A superset partner to scroll to, if any.
  final int? revealPartner;
}

/// The screen's LOG decision: input guard, `logSets`, and the advance. Owned by
/// `_ActiveWorkoutScreenState` (cards are separate States, so a card-level
/// guard could not protect the NEXT card's button).
class LogExerciseController {
  LogExerciseController({required Duration Function() clock}) : _clock = clock;

  final Duration Function() _clock;
  Duration? _lastAdvanceAt;

  /// The LOG guard window after the last advance: [kRevealGuard] when that
  /// advance scrolled (a superset reveal, a RE-OPEN), else [kLogInputGuard].
  Duration _lastAdvanceWindow = kLogInputGuard;

  LogOutcome log({
    required int exerciseIndex,
    required Set<int> setIndexes,
    required void Function(int exerciseIndex, Set<int> setIndexes) logSets,
    required ActiveWorkoutData Function() readState,
  }) {
    if (shouldIgnoreLog(
        now: _clock(),
        lastAdvanceAt: _lastAdvanceAt,
        window: _lastAdvanceWindow)) {
      return const LogOutcome(LogOutcomeKind.ignored);
    }
    final before = readState();
    if (setIndexes.isEmpty ||
        before.isSaved ||
        exerciseIndex < 0 ||
        exerciseIndex >= before.exercises.length) {
      return const LogOutcome(LogOutcomeKind.noop);
    }
    logSets(exerciseIndex, setIndexes);
    final after = readState();
    // `logSets` leaves state untouched when it adds nothing.
    if (identical(after, before)) return const LogOutcome(LogOutcomeKind.noop);
    if (!after.isExerciseDone(exerciseIndex)) {
      return const LogOutcome(LogOutcomeKind.logged);
    }
    _lastAdvanceAt = _clock();
    final partner = supersetPartnerToReveal(after, exerciseIndex);
    _lastAdvanceWindow = partner != null ? kRevealGuard : kLogInputGuard;
    return LogOutcome(
      LogOutcomeKind.logged,
      clearFocus: true,
      revealPartner: partner,
    );
  }

  /// RE-OPEN of a LOGGED exercise (flip batch §1): unchecks every checked set
  /// of [exerciseIndex] through `unlogSets(reopened: true)`. Ignored within
  /// [kReopenGuard] of an advancing LOG; `noop` unless the exercise is done
  /// and `unlogSets` accepts. A successful re-open stamps the guard with the
  /// [kRevealGuard] window (the screen scrolls to the card).
  LogOutcome reopen({
    required int exerciseIndex,
    required ActiveWorkoutData Function() readState,
    required bool Function(int exerciseIndex, Set<int> setIndexes,
            {required String exerciseName, bool reopened})
        unlogSets,
  }) {
    if (shouldIgnoreLog(
        now: _clock(), lastAdvanceAt: _lastAdvanceAt, window: kReopenGuard)) {
      return const LogOutcome(LogOutcomeKind.ignored);
    }
    final data = readState();
    if (data.isSaved ||
        exerciseIndex < 0 ||
        exerciseIndex >= data.exercises.length ||
        !data.isExerciseDone(exerciseIndex)) {
      return const LogOutcome(LogOutcomeKind.noop);
    }
    final numSets = int.tryParse(data.exercises[exerciseIndex].sets) ?? 3;
    final checked = {
      for (var i = 0; i < numSets; i++)
        if (data.isSetChecked(exerciseIndex, i)) i,
    };
    final ok = unlogSets(exerciseIndex, checked,
        exerciseName: data.exercises[exerciseIndex].name, reopened: true);
    if (!ok) return const LogOutcome(LogOutcomeKind.noop);
    _lastAdvanceAt = _clock();
    _lastAdvanceWindow = kRevealGuard;
    return const LogOutcome(LogOutcomeKind.reopened);
  }
}

// ── UNDO toast (batch 2, docs/plans/log-exercise-batch2.md §5.1) ─────────
// An in-tree toast, not a SnackBar: SnackBars queue and a queued one cannot be
// closed, and a toast that outlives its context is the b4e7f1 / s1n4c0 class.

/// How long the toast after a LOG stays.
const Duration kLogUndoWindow = Duration(seconds: 5);

/// One LOG that can still be undone. Session-only screen state, never stored
/// (and never an `undo_<logKey>` Hive key).
class LogUndoRecord {
  const LogUndoRecord({
    required this.exerciseIndex,
    required this.exerciseName,
    required this.setIndexes,
    required this.shownAt,
    required this.generation,
  });
  final int exerciseIndex;
  final String exerciseName;

  /// Exactly the sets this LOG checked.
  final Set<int> setIndexes;

  /// On the screen's monotonic clock (the LOG guard's Stopwatch).
  final Duration shownAt;

  /// Bumped on every LOG, so a late Timer cannot clear a newer record.
  final int generation;
}

/// The record for a LOG: the sets of [exerciseIndex] checked in [after] and not
/// in [before]. Null when nothing was added, or while a save is running
/// ([completing]): its UNDO would do nothing.
LogUndoRecord? undoRecordFor({
  required ActiveWorkoutData before,
  required ActiveWorkoutData after,
  required int exerciseIndex,
  required Duration shownAt,
  required int generation,
  required bool completing,
}) {
  if (completing) return null;
  if (exerciseIndex < 0 || exerciseIndex >= after.exercises.length) return null;
  final numSets = int.tryParse(after.exercises[exerciseIndex].sets) ?? 3;
  final added = {
    for (var i = 0; i < numSets; i++)
      if (after.isSetChecked(exerciseIndex, i) &&
          !before.isSetChecked(exerciseIndex, i))
        i,
  };
  if (added.isEmpty) return null;
  return LogUndoRecord(
    exerciseIndex: exerciseIndex,
    exerciseName: after.exercises[exerciseIndex].name,
    setIndexes: added,
    shownAt: shownAt,
    generation: generation,
  );
}

/// The record to show now, or null: past the window, saved, the index out of
/// range (an exercise was removed), another exercise at that index (swap or
/// removal), or any of its sets no longer checked (`-`, a swap back, a
/// remove-and-re-add). Never throws in `build`.
LogUndoRecord? visibleUndoRecord(
    LogUndoRecord? record, Duration now, ActiveWorkoutData data) {
  if (record == null) return null;
  if (now - record.shownAt >= kLogUndoWindow) return null;
  if (data.isSaved) return null;
  final i = record.exerciseIndex;
  if (i < 0 || i >= data.exercises.length) return null;
  if (data.exercises[i].name != record.exerciseName) return null;
  for (final s in record.setIndexes) {
    if (!data.isSetChecked(i, s)) return null;
  }
  return record;
}

/// UNDO sits where the next exercise's controls can be: a tap inside the LOG
/// guard window after the toast appears is ignored.
bool shouldIgnoreUndo({required Duration now, required Duration shownAt}) =>
    now - shownAt < kLogInputGuard;

/// `{Exercise} logged · {n} sets · {kg} KG`, computed at render from the
/// current state. `n` counts working sets (warm-ups excluded, as in
/// `completedSets`); `kg` only for loaded types, from the stored values.
/// Empty when the record's index is out of range.
String logToastText(LogUndoRecord record, ActiveWorkoutData data) {
  final i = record.exerciseIndex;
  if (i < 0 || i >= data.exercises.length) return '';
  final exercise = data.exercises[i];
  final parts = <String>[
    WardroomCopy.activeLogToastLoggedTemplate
        .replaceAll('{exercise}', exercise.name),
  ];
  final working = [
    for (final s in record.setIndexes)
      if (!data.isSetWarmUp(i, s)) s,
  ];
  if (working.length == 1) {
    parts.add(WardroomCopy.activeLogToastOneSet);
  } else if (working.length > 1) {
    parts.add(WardroomCopy.activeLogToastSetsTemplate
        .replaceAll('{n}', '${working.length}'));
  }
  final loaded = exercise.loggingType == 'weight_reps' ||
      exercise.loggingType == 'weighted_bodyweight';
  if (loaded) {
    var kg = 0.0;
    for (final s in working) {
      final v = data.setInputValues['$i-$s'];
      if (v == null) continue;
      kg += (v.weight ?? 0) * (v.reps ?? 0);
    }
    if (kg > 0) {
      parts.add(WardroomCopy.activeLogToastKgTemplate
          .replaceAll('{kg}', formatKg(kg)));
    }
  }
  return parts.join(WardroomCopy.activeLogToastSeparator);
}

/// Every exercise logged and the session not saved: FINISH turns gold with
/// `All exercises logged.` above it (LOG mode only, decided by the caller).
bool allExercisesLogged(ActiveWorkoutData data) {
  if (data.isSaved || data.exercises.isEmpty) return false;
  for (var i = 0; i < data.exercises.length; i++) {
    if (!data.isExerciseDone(i)) return false;
  }
  return true;
}

// ── FINISH guard + working counts (flip batch §3, OI-361 §3b) ─────────────

/// `(saved, total)` working sets: `saved` is exactly what `completeWorkout`
/// writes (`saveableSetIndexes`), `total` the template sets minus warm-ups.
({int saved, int total}) workingSetCounts(ActiveWorkoutData data) {
  var saved = 0;
  var total = 0;
  for (var i = 0; i < data.exercises.length; i++) {
    saved += data.saveableSetIndexes(i).length;
    final numSets = int.tryParse(data.exercises[i].sets) ?? 3;
    for (var s = 0; s < numSets; s++) {
      if (!data.isSetWarmUp(i, s)) total++;
    }
  }
  return (saved: saved, total: total);
}

/// The progress fraction for the header bar: 0 with no working sets (every
/// set a warm-up; `NaN.round()` throws), clamped to 1 (a checked set beyond
/// the template count).
double workingProgress(({int saved, int total}) counts) {
  if (counts.total == 0) return 0.0;
  return (counts.saved / counts.total).clamp(0.0, 1.0);
}

/// What the FINISH dialog names (LOG mode), over the exercises present now.
class FinishGuard {
  const FinishGuard({
    this.reopenedUnsaved = const [],
    this.typedUnsaved = const [],
    this.skipped = const [],
    this.partial = const [],
  });

  /// Logged, re-opened, never logged again: nothing will be saved.
  final List<String> reopenedUnsaved;

  /// The user typed a value on an unlogged set and never logged it.
  final List<String> typedUnsaved;

  /// Nothing to save, any other reason (skipped, untouched, all warm-ups).
  final List<String> skipped;

  /// Some working sets will be saved, not all (`+` after LOG).
  final List<({String name, int saved, int working})> partial;
}

FinishGuard finishGuard(ActiveWorkoutData data) {
  final reopened = <String>[];
  final typed = <String>[];
  final skipped = <String>[];
  final partial = <({String name, int saved, int working})>[];
  for (var i = 0; i < data.exercises.length; i++) {
    final exercise = data.exercises[i];
    final saved = data.saveableSetIndexes(i).length;
    final numSets = int.tryParse(exercise.sets) ?? 3;
    if (saved == 0) {
      if (data.reopenedExercises.contains(exercise.name)) {
        reopened.add(exercise.name);
      } else if (_hasTypedUnloggedValue(data, i, exercise.loggingType)) {
        typed.add(exercise.name);
      } else {
        skipped.add(exercise.name);
      }
      continue;
    }
    var working = 0;
    for (var s = 0; s < numSets; s++) {
      if (!data.isSetWarmUp(i, s)) working++;
    }
    if (saved < working) {
      partial.add((name: exercise.name, saved: saved, working: working));
    }
  }
  return FinishGuard(
    reopenedUnsaved: reopened,
    typedUnsaved: typed,
    skipped: skipped,
    partial: partial,
  );
}

/// An UNCHECKED set with a rendered (`mirrorFieldsFor`) value the user typed:
/// captured non-null and not app-filled (no suggested key). Reps are never
/// marked, so they cannot tell typed from prefilled and are not read.
bool _hasTypedUnloggedValue(
    ActiveWorkoutData data, int exerciseIndex, String loggingType) {
  final fields = mirrorFieldsFor(loggingType);
  final numSets = int.tryParse(data.exercises[exerciseIndex].sets) ?? 3;
  for (var s = 0; s < numSets; s++) {
    if (data.isSetChecked(exerciseIndex, s)) continue;
    final v = data.setInputValues['$exerciseIndex-$s'];
    if (v == null) continue;
    for (final f in fields) {
      final present = switch (f) {
        SetField.weight => v.weight != null,
        SetField.duration => v.durationSeconds != null,
        SetField.distance => v.distanceKm != null,
        SetField.reps => false,
      };
      if (present &&
          !data.suggestedInputs.contains(suggestedKey(exerciseIndex, s, f))) {
        return true;
      }
    }
  }
  return false;
}

/// At most [max] names joined with `, `, then ` +N more`.
String capNames(List<String> names, {int max = 5}) {
  if (names.length <= max) return names.join(', ');
  return '${names.take(max).join(', ')}'
      '${WardroomCopy.activeFinishMoreTemplate.replaceAll('{n}', '${names.length - max}')}';
}
