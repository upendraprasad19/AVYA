// Batch 9 (W2.7) — shared estimated-1RM helper.
//
// Extracted VERBATIM from `DeloadE1rmScan._sessionMaxE1rm` (+ its `_toDouble` /
// `_toInt` coercers) so the deload trigger (W2.4) and volume titration (W2.7)
// share ONE Epley loop instead of two hand-rolled copies (the #1 writer/reader-
// drift bug class). Behaviour is byte-identical — `DeloadE1rmScan` now calls this
// and its `deload_eval_behavioral_test` pins the equivalence.
//
// NOTE: a THIRD Epley in `ProgressionResolver` (`progression_resolver.dart`) takes
// a `_TopSet` record (not a `Map log`) — a different call shape — so it is
// intentionally NOT unified here.

/// A logged session's max estimated 1RM: MAX over the session's sets of Epley
/// `w*(1+reps/30)`. NOT the heaviest-weight set (a high-rep set can out-e1RM the
/// heaviest → heaviest-by-weight would mask a decline → an unsafe read). Falls
/// back to the top-level `weight_kg`/`reps_completed` for older rows without a
/// `sets` array. Returns null when there is no positive load (bodyweight / timed
/// → not a load lift).
double? sessionMaxE1rm(Map log) {
  double best = 0;
  final setsRaw = log['sets'];
  if (setsRaw is List) {
    for (final s in setsRaw) {
      if (s is! Map) continue;
      final w = _toDouble(s['weight_kg']);
      if (w == null || w <= 0) continue;
      final reps = _toInt(s['reps_completed'] ?? s['reps']) ?? 0;
      final e = reps > 0 ? w * (1 + reps / 30.0) : w;
      if (e > best) best = e;
    }
  }
  if (best <= 0) {
    final w = _toDouble(log['weight_kg']);
    if (w == null || w <= 0) return null;
    final reps = _toInt(log['reps_completed']) ?? 0;
    best = reps > 0 ? w * (1 + reps / 30.0) : w;
  }
  return best > 0 ? best : null;
}

double? _toDouble(Object? v) {
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int? _toInt(Object? v) {
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}
