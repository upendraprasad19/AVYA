// One LOG per exercise (flag `enable_log_exercise_button`): the pure decision
// logic behind the LOG button, kept out of the private `part of` widgets so it
// is unit-testable. Plan: docs/plans/active-workout-log-exercise.md §5.
import 'package:icanbefitter/core/copy/wardroom_copy.dart';

import '../providers/train_provider.dart';

/// The input field a set's validation failed on.
enum SetField { weight, reps, duration, distance }

/// `empty`: nothing usable typed (label "Add …"). `outOfRange`: a value is
/// present but rejected, e.g. reps above 60 or "12.5" minutes (label "Fix …").
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
/// The `kind` is new: a duration that is present but not a whole number (the
/// cardio field takes decimals, the validator `int.tryParse`s) is
/// `outOfRange`, where the OFF validator reports it as missing.
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
    final d = int.tryParse(t);
    if (d == null && t.isNotEmpty) {
      return const SetValidation.failure(
          SetField.duration, SetFailureKind.outOfRange, kEnterDurationMessage);
    }
    if ((d ?? 0) <= 0) {
      return const SetValidation.failure(
          SetField.duration, SetFailureKind.empty, kEnterDurationMessage);
    }
    return const SetValidation.ok();
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
    case 'cardio':
      return duration();
    case 'distance':
      final distance = double.tryParse(distanceText.trim()) ?? 0;
      if (distance <= 0) {
        return const SetValidation.failure(
            SetField.distance, SetFailureKind.empty, kEnterDistanceMessage);
      }
      return const SetValidation.ok();
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
  final rounded = double.parse(volumeKg.toStringAsFixed(1));
  final kg = rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : rounded.toString();
  return WardroomCopy.activeLiftedSublineTemplate.replaceAll('{kg}', kg);
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
  for (var i = existing.length - 1; i >= 0; i--) {
    final warm = i < isWarmUp.length && isWarmUp[i];
    if (!warm) return existing[i];
  }
  return existing.isEmpty ? const SetTexts() : existing.last;
}

/// After LOG advances the screen to the next exercise, that exercise's LOG
/// button lands under the same thumb. Taps on LOG inside this window are
/// ignored.
const Duration kLogInputGuard = Duration(milliseconds: 400);

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

enum LogOutcomeKind { ignored, logged, noop }

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

  LogOutcome log({
    required int exerciseIndex,
    required Set<int> setIndexes,
    required void Function(int exerciseIndex, Set<int> setIndexes) logSets,
    required ActiveWorkoutData Function() readState,
  }) {
    if (shouldIgnoreLog(now: _clock(), lastAdvanceAt: _lastAdvanceAt)) {
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
    return LogOutcome(
      LogOutcomeKind.logged,
      clearFocus: true,
      revealPartner: supersetPartnerToReveal(after, exerciseIndex),
    );
  }
}
