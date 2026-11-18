// lib/features/profile/services/weigh_in_target_refresh.dart
//
// goal-change-targets B2 (founder decision, 2026-11-18): a weigh-in recomputes the calorie /
// protein targets only when the 7-day MEAN of the weigh-ins has drifted more than 2 kg from the
// weight the targets were last built from. Inside the band nothing moves, so one heavy morning
// cannot shift the day's calories.
//
// Pure: no Hive, no Riverpod, no clock of its own. `WeightLogNotifier.logWeight` reads the box
// entries and hands them in, and applies the patch inside ONE `ProfileWriteService.patchProfileWith`.
import 'package:icanbefitter/features/profile/services/profile_target_recompute.dart';

/// The drift band in integer tenths of a kg: more than 2.0 kg recomputes.
const int kWeighInDriftBandTenths = 20;

/// The window, in days, the mean covers (today and the six days before it).
const int kWeighInWindowDays = 7;

/// What `WeightLogNotifier.logWeight` reports back to its callers.
class WeightLogResult {
  const WeightLogResult({
    required this.wrote,
    this.targetsMoved = false,
    this.caloriesFrom,
    this.caloriesTo,
    this.proteinFrom,
    this.proteinTo,
  });

  /// The profile write landed (false: the account changed under it, nothing written).
  final bool wrote;

  /// A calorie or protein number changed because of this weigh-in.
  final bool targetsMoved;

  final num? caloriesFrom;
  final num? caloriesTo;
  final num? proteinFrom;
  final num? proteinTo;
}

/// The refresh decision for one weigh-in.
class WeighInRefresh {
  const WeighInRefresh({
    this.patch,
    this.targetsMoved = false,
    this.caloriesFrom,
    this.caloriesTo,
    this.proteinFrom,
    this.proteinTo,
  });

  /// Keys to merge into the profile besides the raw `current_weight_kg`; null = nothing.
  final Map<String, dynamic>? patch;
  final bool targetsMoved;
  final num? caloriesFrom;
  final num? caloriesTo;
  final num? proteinFrom;
  final num? proteinTo;
}

/// The weigh-in values inside the window, strictly read. An entry counts when its key is
/// `weight_<YYYY-MM-DD>` AND its value is a map with `type == 'weight_log'` (what
/// `HealthWriteService.logWeight`, the cloud restore and Health Connect all write) AND
/// `weight_kg` is a finite number in (0, 500]; its date lies in `[today - 6, today]`
/// (a future-dated row is excluded). One value per date: the key is the date.
List<double> recentWeighInKgs(
  Iterable<MapEntry<dynamic, dynamic>> entries,
  String todayIst,
) {
  final today = _parseDay(todayIst);
  if (today == null) return const <double>[];
  final out = <double>[];
  for (final e in entries) {
    final key = e.key;
    if (key is! String || !key.startsWith('weight_')) continue;
    final day = _parseDay(key.substring('weight_'.length));
    if (day == null) continue;
    final age = today.difference(day).inDays;
    if (age < 0 || age >= kWeighInWindowDays) continue;
    final v = e.value;
    if (v is! Map || v['type'] != 'weight_log') continue;
    final kg = v['weight_kg'];
    if (kg is! num) continue;
    final d = kg.toDouble();
    if (!d.isFinite || d <= 0 || d > 500) continue;
    out.add(d);
  }
  return out;
}

DateTime? _parseDay(String s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (m == null) return null;
  return DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

/// The mean of [kgs], or [fallbackKg] when there is none.
double smoothedWeightKg(List<double> kgs, double fallbackKg) {
  if (kgs.isEmpty) return fallbackKg;
  var sum = 0.0;
  for (final k in kgs) {
    sum += k;
  }
  return sum / kgs.length;
}

/// True when [smoothedKg] is more than the band away from [basisKg], compared in integer
/// tenths (`64.4 - 62.4` is `2.000000000000007` as doubles).
bool weighInDriftExceedsBand(double smoothedKg, double basisKg) {
  final drift = (smoothedKg * 10).round() - (basisKg * 10).round();
  return drift.abs() > kWeighInDriftBandTenths;
}

/// Decides what a weigh-in does to the targets. [profile] is the profile BEFORE this weigh-in
/// (the builder of `patchProfileWith` sees it that way).
///
/// - basis = `targets_basis_weight_kg`, else the stored `current_weight_kg`; none -> nothing.
/// - over the band -> recompute from [smoothedKg]; the overlay (which carries the new basis)
///   is the patch; an incomplete profile (null overlay) -> nothing.
/// - inside the band with no stored basis -> seed ONLY `targets_basis_weight_kg`; with one -> nothing.
WeighInRefresh weighInTargetRefresh(
  Map<String, dynamic> profile, {
  required double smoothedKg,
  required DateTime now,
  required bool bodyFatCalcDisabled,
}) {
  final storedBasis = profile[kTargetsBasisWeightKey];
  final basisNum = storedBasis is num
      ? storedBasis
      : profile['current_weight_kg'] is num
          ? profile['current_weight_kg'] as num
          : null;
  if (basisNum == null || !basisNum.isFinite || basisNum <= 0) {
    return const WeighInRefresh();
  }
  final basis = basisNum.toDouble();
  if (!weighInDriftExceedsBand(smoothedKg, basis)) {
    if (storedBasis is num) return const WeighInRefresh();
    return WeighInRefresh(patch: <String, dynamic>{kTargetsBasisWeightKey: basis});
  }
  final overlay = recomputeDerivedTargets(
    <String, dynamic>{...profile, 'current_weight_kg': smoothedKg},
    now: now,
    bodyFatCalcDisabled: bodyFatCalcDisabled,
  );
  if (overlay == null) return const WeighInRefresh();
  num? n(Object? v) => v is num ? v : null;
  final cFrom = n(profile['daily_calories']);
  final pFrom = n(profile['protein_grams']);
  final cTo = n(overlay['daily_calories']);
  final pTo = n(overlay['protein_grams']);
  return WeighInRefresh(
    patch: overlay,
    targetsMoved: cFrom != cTo || pFrom != pTo,
    caloriesFrom: cFrom,
    caloriesTo: cTo,
    proteinFrom: pFrom,
    proteinTo: pTo,
  );
}
