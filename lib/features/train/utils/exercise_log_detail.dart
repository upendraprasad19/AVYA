import 'package:icanbefitter/core/services/workout_read_service.dart';
import 'package:icanbefitter/core/utils/cardio_format.dart';

import 'set_count_label.dart';

/// The detail line under an exercise's name on the Train expanded view
/// (`ExpandedExerciseLogRow`), extracted pure so it is testable (OI-389 U7).
///
/// Every aggregate goes through [WorkoutReadService] (restored rows carry
/// top-level totals and no per-set list). NBSP between number and unit and
/// [kDetailSeparator] between parts, as the row always rendered.
String exerciseLogDetail(Map<String, dynamic> log) {
  // APK Test #12.4 / Unit 7 / OI-50 — the 4-source set-count MAX lives in ONE
  // place (WorkoutReadService.aggregateSetCount).
  final sets = WorkoutReadService.aggregateSetCount(log);
  final loggingType = log['logging_type'] as String? ?? 'weight_reps';

  // audit-2026-05-16 reader-side / Obs 3 — per-set MAX semantics for reps
  // and the timed "best"; OI-02 / OI-08 centralised in WorkoutReadService.
  final perSetMaxReps = WorkoutReadService.bestPerSetReps(log);
  final perSetMaxDur = WorkoutReadService.bestPerSetDuration(log);
  // For weight_reps the writer's top-level `weight_kg` is already MAX.
  final weight = (log['weight_kg'] as num?)?.toDouble() ?? 0;
  // Unit 7 / OI-50 — a TOTAL, so restored rows (no per-set array) still
  // render; `perSetMaxDur` stays the per-set MAX for the timed "best".
  final totalDuration = WorkoutReadService.aggregateDurationSeconds(log) ?? 0;

  if (loggingType == 'timed') {
    // Unit 7 / OI-50 round-2 — the label must follow the VALUE.
    final hasPerSetBest = perSetMaxDur > 0;
    final secs = hasPerSetBest ? perSetMaxDur : totalDuration;
    final mins = secs ~/ 60;
    final tail = secs % 60;
    final dur = '${mins > 0 ? '${mins}m ' : ''}${tail}s';
    return sets > 1
        ? '${setCountLabel(sets)}$kDetailSeparator${hasPerSetBest ? 'best' : 'total'} $dur'
        : dur;
  }
  if (loggingType == 'cardio' || loggingType == 'distance') {
    // OI-389 / OI-380: minutes (not seconds), km, and a distance branch; a
    // zero part is omitted, so a distance row never reads "0 reps".
    return cardioDistanceDetail(
      loggingType: loggingType,
      sets: sets,
      durationSec: totalDuration,
      km: WorkoutReadService.aggregateDistanceKm(log),
      reps: perSetMaxReps,
      weightKg: weight,
      space: kNbsp,
      separator: kDetailSeparator,
    );
  }
  if (weight > 0) {
    return '${setCountLabel(sets)}$kDetailSeparator'
        '${repCountLabel(perSetMaxReps)}$kDetailSeparator'
        '${weight.toStringAsFixed(1)}${kNbsp}kg';
  }
  return '${setCountLabel(sets)}$kDetailSeparator'
      '${repCountLabel(perSetMaxReps)}';
}
