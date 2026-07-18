// ⑥ Batch 7-B-2 (W2.4 triggered deload): per-exercise e1RM fatigue scan.
//
// Reads `exlog_*` rows and computes, per COMPOUND lift, whether its estimated
// 1RM is DECLINING across its two most-recent DISTINCT dated sessions. This is
// the OBJECTIVE "no fatigue" evidence half of the deload trigger (readiness is
// the subjective half). It is a genuine re-implementation of the progression
// scan loop because the reusable primitives are date-discarding
// (`ProgressionResolver._topSet` returns `DateTime(0)`) and pick the heaviest
// set by WEIGHT — which can MASK an e1RM decline (a high-rep set can out-e1RM
// the heaviest-weight set). Here the per-session representative is the MAX Epley
// e1RM over the session's sets.
//
// SAFE polarity: `noFatigue` requires POSITIVE evidence — ≥1 compound with ≥2
// dated sessions AND none declining. Zero evaluable compounds → `hasCompound
// Evidence=false` → `noFatigue=false` → the caller KEEPS the deload.

import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/e1rm.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';

/// Outcome of a [DeloadE1rmScan.scan]: whether there is positive compound
/// evidence, and whether any compound is declining.
class DeloadE1rmResult {
  /// ≥1 compound lift has ≥2 distinct dated sessions of load history.
  final bool hasCompoundEvidence;

  /// ≥1 compound lift's latest-session max e1RM is below its prior session's.
  final bool anyCompoundDeclining;

  const DeloadE1rmResult({
    required this.hasCompoundEvidence,
    required this.anyCompoundDeclining,
  });

  /// Positively-confirmed no fatigue: real evidence AND nothing declining.
  bool get noFatigue => hasCompoundEvidence && !anyCompoundDeclining;
}

/// Scans logged history for compound-lift e1RM fatigue. Pure read; crash-safe.
class DeloadE1rmScan {
  DeloadE1rmScan._();

  /// Never throws for the caller — any read failure returns a no-evidence
  /// result (→ keep the deload, the safe direction).
  static DeloadE1rmResult scan() {
    try {
      final box = HiveService.instance.workoutBox;
      // Recency bound — only sessions in the trailing 35 IST days count as CURRENT
      // evidence (a phase is 28 days; wk4 evaluates at day 21-27). Stale progression
      // from a prior phase must not read as "no fatigue now" → drops to fewer recent
      // sessions → the ≥2-session gate keeps the deload (the safe direction).
      final cutoff = istDateStr(nowWall().subtract(const Duration(days: 35)));
      // exerciseName -> (istDate -> max Epley e1RM that day)
      final byExercise = <String, Map<String, double>>{};

      for (final key in box.keys) {
        final k = key.toString();
        if (!k.startsWith('exlog_')) continue;
        final log = box.get(key);
        if (log is! Map) continue;
        final dateStr = log['date'] as String?;
        if (dateStr == null) continue;
        if (dateStr.compareTo(cutoff) < 0) continue; // stale → not current evidence
        final name = log['exercise_name'] as String?;
        if (name == null) continue;
        final e1rm = sessionMaxE1rm(log);
        if (e1rm == null) continue;
        final dated = byExercise[name] ??= <String, double>{};
        final prev = dated[dateStr];
        if (prev == null || e1rm > prev) dated[dateStr] = e1rm;
      }

      final repo = ExerciseRepository.instance;
      var hasEvidence = false;
      var anyDeclining = false;

      byExercise.forEach((name, dated) {
        if (dated.length < 2) return; // need ≥2 dated sessions
        if (!_isCompound(name, repo)) return; // main lifts only
        hasEvidence = true;
        // top-2 most-recent DISTINCT dates (YYYY-MM-DD lexical desc).
        final dates = dated.keys.toList()..sort((a, b) => b.compareTo(a));
        final latest = dated[dates[0]]!;
        final prior = dated[dates[1]]!;
        if (latest < prior) anyDeclining = true;
      });

      return DeloadE1rmResult(
        hasCompoundEvidence: hasEvidence,
        anyCompoundDeclining: anyDeclining,
      );
    } catch (_) {
      return const DeloadE1rmResult(
        hasCompoundEvidence: false,
        anyCompoundDeclining: false,
      );
    }
  }

  /// True iff [name] resolves to a library exercise whose `exercise_type` is
  /// EXACTLY 'compound' (mirrors `ExerciseRepository._fieldContains` — the same
  /// exact-match predicate the generator's compounds-first sort uses). Custom /
  /// swapped names absent from the library → false (not a main lift).
  static bool _isCompound(String name, ExerciseRepository repo) {
    final row = repo.getByExactName(name);
    if (row == null) return false;
    final t = row['exercise_type'];
    const target = 'compound';
    if (t is List) {
      return t.any((e) => e.toString().toLowerCase() == target);
    }
    return (t as String?)?.toLowerCase() == target;
  }
}
