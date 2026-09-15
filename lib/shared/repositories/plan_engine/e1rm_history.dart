// Batch 12-A (W3.5 plateau escalation) — shared exlog_* → e1RM-by-date history.
//
// Extracted VERBATIM from the two hand-rolled copies in `DeloadE1rmScan.scan`
// (W2.4) and `VolumeTitration.resolveDeltas` (W2.7) — and consumed by the new
// W3.5 `PlateauScan` — so ONE loop builds the per-exercise, per-day max-Epley
// e1RM map instead of three (the #1 writer/reader-drift bug class; the same
// rationale that extracted `e1rm.dart`'s `sessionMaxE1rm`). The ONLY per-caller
// difference was the recency `cutoff` (deload/titration 35d, plateau 63d) — now a
// required param. `e1rm.dart` stays a pure math util (no Hive); this
// Hive-Box-reading helper lives separately so that purity is preserved.

import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/utils/e1rm.dart';

/// Builds `exerciseName → (istDate → MAX Epley e1RM logged that day)` from the
/// user's `exlog_*` rows in [workoutBox], counting only rows whose IST `date` is
/// on/after [cutoff] (a `YYYY-MM-DD` string; lexical `>=`). A row with no positive
/// load (bodyweight / timed) contributes nothing (`sessionMaxE1rm` returns null).
/// Pure read — never mutates the box; crash-safe for a well-formed box.
Map<String, Map<String, double>> buildE1rmByDate(
  Box workoutBox, {
  required String cutoff,
}) {
  final byExercise = <String, Map<String, double>>{};
  for (final key in workoutBox.keys) {
    final k = key.toString();
    if (!k.startsWith('exlog_')) continue;
    final log = workoutBox.get(key);
    if (log is! Map) continue;
    final dateStr = log['date'] as String?;
    if (dateStr == null || dateStr.compareTo(cutoff) < 0) continue;
    final name = log['exercise_name'] as String?;
    if (name == null) continue;
    final e = sessionMaxE1rm(log);
    if (e == null) continue;
    final dated = byExercise[name] ??= <String, double>{};
    final prev = dated[dateStr];
    if (prev == null || e > prev) dated[dateStr] = e;
  }
  return byExercise;
}
