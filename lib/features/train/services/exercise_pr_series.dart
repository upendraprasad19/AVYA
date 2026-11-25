// The ONE per-row value rule behind an exercise's personal record, and the
// per-day series the Home PR charts draw from it (plan
// docs/plans/pr-strength-charts.md).
//
// `WorkoutRepository.loadAllExercisePRs` ranks rows with [exercisePrValueOfRow];
// [buildExercisePrSeries] values the same rows with the same function, for the
// exercises and in the unit of the PR list it is given. The chart can therefore
// never peak above the PR, and peaks AT it whenever the PR's own row has a day.
//
// Pure: no Hive access, no Riverpod. Aggregate reads go through the
// `WorkoutReadService` statics; this file never reads a per-row distance,
// a row type stamp or a top-level reps total itself.

import 'package:icanbefitter/core/services/workout_read_service.dart';

import '../repositories/workout_repository.dart' show ExercisePR;

/// Lower-cased trimmed name: the PR reader's grouping key.
String exercisePrNameKey(String name) => name.trim().toLowerCase();

/// Name keys of the cardio exercises with ANY km logged (OI-389). Their PR is
/// in km; every other cardio exercise is ranked by its best set's seconds. One
/// unit per exercise, so a 5 km log and a later 1800 s log are never compared.
///
/// Reads the RAW `logging_type` (no default): a row with no type is never
/// cardio.
Set<String> cardioExercisesWithKm(Iterable<Map<String, dynamic>> rows) {
  final out = <String>{};
  for (final log in rows) {
    if ((log['logging_type'] as String?) != 'cardio') continue;
    final n = exercisePrNameKey(log['exercise_name'] as String? ?? '');
    if (n.isNotEmpty && WorkoutReadService.aggregateDistanceKm(log) > 0) {
      out.add(n);
    }
  }
  return out;
}

/// The PR-ranking value of one exlog row.
typedef ExercisePrRowValue = ({
  double value,
  String loggingType,

  /// The unit [value] is in: [statedUnit], else the type's default.
  String unit,

  /// The unit the reader states for this row (cardio and distance), null for
  /// the types whose unit follows from the logging type.
  String? statedUnit,
});

/// The PR-ranking value of [log], or null when the row has no positive value.
/// A missing `logging_type` is `weight_reps`. [cardioHasKm] is whether this
/// row's exercise is in [cardioExercisesWithKm].
ExercisePrRowValue? exercisePrValueOfRow(
  Map<String, dynamic> log, {
  required bool cardioHasKm,
}) {
  final loggingType = (log['logging_type'] as String? ?? 'weight_reps');

  // Per-set MAX semantic delegated to the canonical WorkoutReadService
  // (OI-02 / OI-08): never the cumulative top-level totals.
  double value;
  String? unit;
  switch (loggingType) {
    case 'weight_reps':
    case 'weighted_bodyweight':
      value = WorkoutReadService.bestPerSetWeight(log);
      break;
    case 'bodyweight_reps':
      value = WorkoutReadService.bestPerSetReps(log).toDouble();
      break;
    case 'timed':
      value = WorkoutReadService.bestPerSetDuration(log).toDouble();
      break;
    case 'cardio':
      // Cumulative distance IS the meaningful metric when the exercise has km
      // at all; otherwise the best set's duration. ONE unit per exercise.
      if (cardioHasKm) {
        value = WorkoutReadService.aggregateDistanceKm(log);
        unit = 'km';
      } else {
        value = WorkoutReadService.bestPerSetDuration(log).toDouble();
        unit = 'sec';
      }
      break;
    case 'distance':
      value = WorkoutReadService.aggregateDistanceKm(log);
      unit = 'km';
      break;
    default:
      value = (log['weight_kg'] as num?)?.toDouble() ?? 0;
  }

  if (value <= 0) return null;
  return (
    value: value,
    loggingType: loggingType,
    unit: unit ?? ExercisePR.defaultUnitFor(loggingType),
    statedUnit: unit,
  );
}

/// The workout day of [log] as `yyyy-MM-dd`, or null when it has none. A day
/// is resolved exactly when the PR reader's own parse of
/// `WorkoutReadService.istDateForExlogRow` succeeds.
String? exercisePrDayOfRow(Map<String, dynamic> log) {
  final raw = WorkoutReadService.istDateForExlogRow(log);
  if (raw == null) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;
  String p(int n) => n.toString().padLeft(2, '0');
  return '${parsed.year}-${p(parsed.month)}-${p(parsed.day)}';
}

/// Whether a row valued [value] on [day] replaces the current best
/// ([bestValue] on [bestDay]; a null day is an unresolved one).
///
/// Strictly greater always wins. On an EQUAL value the earlier resolved day
/// wins, and a resolved day beats an unresolved one, so a PR's date is the
/// first day the best was achieved whatever order the rows are walked in.
bool exercisePrRowReplaces({
  required double value,
  required String? day,
  required double bestValue,
  required String? bestDay,
}) {
  if (value > bestValue) return true;
  if (value < bestValue) return false;
  if (day == null) return false;
  if (bestDay == null) return true;
  return day.compareTo(bestDay) < 0;
}

/// One day of an exercise's history.
class PrSeriesPoint {
  /// IST day, `yyyy-MM-dd`.
  final String date;

  /// The day's best value, in the PR's unit.
  final double value;

  /// For a weighted lift logged with per-set detail: the most reps done at
  /// the day's heaviest weight. Null otherwise.
  final int? reps;

  const PrSeriesPoint({required this.date, required this.value, this.reps});
}

/// An exercise's best value per workout day, oldest first.
class ExercisePrSeries {
  final List<PrSeriesPoint> points;
  const ExercisePrSeries(this.points);

  static const empty = ExercisePrSeries(<PrSeriesPoint>[]);
}

/// The most reps among the sets at [weight] in [log], or null when the row
/// has no per-set detail (the top-level reps figure is a SUM, never used).
int? _repsAtWeight(Map<String, dynamic> log, double weight) {
  final sets = log['sets'];
  if (sets is! List) return null;
  int? best;
  for (final s in sets) {
    if (s is! Map) continue;
    final w = (s['weight_kg'] as num?)?.toDouble() ?? 0.0;
    if (w != weight) continue;
    final r = (s['reps'] as num?)?.toInt() ?? 0;
    if (r > 0 && (best == null || r > best)) best = r;
  }
  return best;
}

/// name key -> series, for the exercises in [prs].
///
/// A row joins the series of the PR with its name key only when its value is
/// in THAT PR's unit, so one chart has one unit and the PR's own row is always
/// eligible. Rows with no resolved day are skipped (a chart cannot place
/// them). Per day the greatest value; on an equal value the first row walked.
Map<String, ExercisePrSeries> buildExercisePrSeries(
  Iterable<Map<String, dynamic>> rows,
  List<ExercisePR> prs,
) {
  if (prs.isEmpty) return const {};
  final all = rows is List<Map<String, dynamic>> ? rows : rows.toList();
  final unitOf = <String, String>{
    for (final pr in prs) exercisePrNameKey(pr.exerciseName): pr.unit,
  };
  final cardioWithKm = cardioExercisesWithKm(all);
  final byName = <String, Map<String, PrSeriesPoint>>{};

  for (final log in all) {
    final nameKey = exercisePrNameKey(log['exercise_name'] as String? ?? '');
    final wantUnit = unitOf[nameKey];
    if (wantUnit == null) continue;
    final v = exercisePrValueOfRow(log,
        cardioHasKm: cardioWithKm.contains(nameKey));
    if (v == null || v.unit != wantUnit) continue;
    final day = exercisePrDayOfRow(log);
    if (day == null) continue;

    final days = byName[nameKey] ??= <String, PrSeriesPoint>{};
    final existing = days[day];
    if (existing != null && v.value <= existing.value) continue;
    final weighted = v.loggingType == 'weight_reps' ||
        v.loggingType == 'weighted_bodyweight';
    days[day] = PrSeriesPoint(
      date: day,
      value: v.value,
      reps: weighted ? _repsAtWeight(log, v.value) : null,
    );
  }

  return {
    for (final e in byName.entries)
      e.key: ExercisePrSeries(
        e.value.values.toList()..sort((a, b) => a.date.compareTo(b.date)),
      ),
  };
}
