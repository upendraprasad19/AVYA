// Batch 12-A (W3.5 plateau escalation, PRO) — flat-window plateau DETECTOR +
// rung-2 (+sets) delta merge.
//
// A "plateau" = a COMPOUND lift whose estimated 1RM is FLAT (no meaningful
// progress) across ≥3 dated sessions spanning ≥4 weeks. When a plateaued group's
// user is NOT under persistent readiness fatigue (that fatigued case is the deload
// rung, ALREADY delivered by W2.4's readiness keep — a plateau-fatigue keep-term
// wired into `deload_evaluator.shouldLift` would be provably dead code, because it
// can only engage when `readiness.good` is already false), the group earns +1
// weekly set at the NEXT phase boundary. That +1 is merged into the W2.7 titration
// delta map so ONE clamped `applyToWeeks` pass applies both — a declining group's
// existing −1 always wins (`putIfAbsent` never overrides), so plateau can never
// add volume to a fatiguing/declining group (no double-bump).
//
// SAFE polarity + inert seams:
//   • `enable_plateau_escalation` DEFAULT OFF → mergePlateauSetDeltas returns the
//     input map unchanged (same ref) → applyToWeeks identity → byte-identical.
//   • ALSO gated on `enable_readiness` (mirrors DeloadEvaluator's guard) — the
//     fatigue gate needs readiness rows; without them +sets would fire blind.
//   • `phase >= 2` self-gate (PRO — free is phase 1; the two fresh-advance callers
//     are PRO-gated, inheriting the server-verified phases_2_to_12 gate).
//   • only ever ADDS +1 where titration left a group absent, clamped ≤MRV inside
//     `applyToWeeks`.

import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/core/utils/readiness.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';

import 'e1rm_history.dart';
import 'muscle_groups.dart';
import 'plan_engine_flags.dart';

class PlateauScan {
  PlateauScan._();

  /// e1RM history window — ≈2 phases, so a ≥28-day flat span fits with margin
  /// (wider than deload/titration's 35d: plateau is a longer-horizon signal).
  static const int _windowDays = 63;

  /// ≥3 distinct dated sessions of the compound.
  static const int _minSessions = 3;

  /// first→last session span must be ≥4 weeks.
  static const int _minSpanDays = 28;

  /// (max−min)/max ≤ this over the qualifying sessions ⇒ "flat" (no progress).
  static const double _flatRelRange = 0.05;

  /// Trailing IST-day readiness window for the fatigue gate (mirrors
  /// `deload_evaluator._readinessGood`).
  static const int _readinessWindow = 14;

  /// Minimum readiness check-ins before "persistent fatigue" is positive evidence.
  static const int _minReadiness = 3;

  /// Merge rung-2 (+sets) into the caller's titration [existing] delta map: for
  /// each plateaued-eligible major group titration left ABSENT, add +1. Never
  /// overrides an existing ±1 (`putIfAbsent`) → a declining group's −1 always
  /// wins (no double-bump). Returns [existing] UNCHANGED (same ref) when there is
  /// nothing to add → the caller's byte-identical inertness is preserved.
  static Map<String, int> mergePlateauSetDeltas(
    Map<String, int> existing, {
    required int phase,
  }) {
    final groups = plateauedGroups(phase: phase);
    if (groups.isEmpty) return existing;
    final out = Map<String, int>.from(existing);
    for (final g in groups) {
      out.putIfAbsent(g, () => 1);
    }
    return out;
  }

  /// The major muscle groups eligible for a +1 (rung-2). `{}` (no escalation) when
  /// the plateau/readiness flag is OFF, phase < 2, the user is under persistent
  /// readiness fatigue (→ the deload rung, W2.4), or there is no plateau evidence.
  /// Crash-safe: any read failure → `{}` (no escalation, the safe direction).
  static Set<String> plateauedGroups({required int phase}) {
    try {
      if (!PlanEngineFlags.plateauEscalationEnabled) return const <String>{};
      // The fatigue gate needs readiness data (mirrors DeloadEvaluator's guard).
      if (!PlanEngineFlags.readinessEnabled) return const <String>{};
      if (phase < 2) return const <String>{}; // PRO / free-is-phase-1 self-gate.
      // Persistent fatigue → the user should RECOVER (deload rung, W2.4), not add
      // volume. Checked BEFORE any e1RM read (short-circuit).
      if (_fatiguePresent()) return const <String>{};

      final box = HiveService.instance.workoutBox;
      final cutoff =
          istDateStr(nowWall().subtract(const Duration(days: _windowDays)));
      final byExercise = buildE1rmByDate(box, cutoff: cutoff);
      if (byExercise.isEmpty) return const <String>{};

      final repo = ExerciseRepository.instance;
      final groups = <String>{};
      byExercise.forEach((name, dated) {
        if (dated.length < _minSessions) return;
        if (!repo.isCompoundByExactName(name)) return; // main lifts only
        // ascending YYYY-MM-DD dates (lexical == chronological) → span + flatness
        // over ALL qualifying sessions.
        final dates = dated.keys.toList()..sort();
        final span = DateTime.parse(dates.last)
            .difference(DateTime.parse(dates.first))
            .inDays;
        if (span < _minSpanDays) return;
        final values = [for (final d in dates) dated[d]!];
        if (!isFlat(values)) return;
        groups.addAll(_groupsFor(name, repo));
      });
      return groups;
    } catch (_) {
      return const <String>{};
    }
  }

  /// (max−min)/max ≤ [_flatRelRange] ⇒ flat (no meaningful progress). Public +
  /// pure so the flatness threshold is unit-testable in isolation. Division-safe:
  /// `sessionMaxE1rm` filters non-positive loads (max > 0) and the ≥[_minSessions]
  /// gate guarantees [values] is non-empty. Empty/all-zero → false (not flat).
  static bool isFlat(List<double> values) {
    if (values.isEmpty) return false;
    var lo = values.first, hi = values.first;
    for (final v in values) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    if (hi <= 0) return false;
    return (hi - lo) / hi <= _flatRelRange;
  }

  /// The distinct major groups a library exercise's `primary_muscles` map to (via
  /// the shared `muscleGroupOf`) — the SAME aggregation VolumeTitration uses, so a
  /// plateau +1 keys on the exact groups the titration clamp/apply understands.
  static Set<String> _groupsFor(String name, ExerciseRepository repo) {
    final row = repo.getByExactName(name);
    if (row == null) return const <String>{};
    final pm = row['primary_muscles'];
    final tokens =
        pm is List ? pm : (pm is String && pm.isNotEmpty ? [pm] : const []);
    final out = <String>{};
    for (final t in tokens) {
      final g = muscleGroupOf(t.toString());
      if (g != null) out.add(g);
    }
    return out;
  }

  /// Persistent readiness fatigue = ≥[_minReadiness] check-ins in the trailing
  /// [_readinessWindow] IST days AND a STRICT MAJORITY flagged red/yellow (`level`
  /// != green). The strict complement of `deload_evaluator._readinessGood` on the
  /// ≥3-data branch — sparse (<3) / exact-half → NOT fatigued → +sets allowed
  /// (per F2). Reads `healthBox` directly (same rows/parser titration uses) so
  /// plan_engine gains no HealthReadService dependency. Any read failure bubbles
  /// to `plateauedGroups`'s outer catch → `{}` (no +sets, the safe direction).
  static bool _fatiguePresent() {
    final hbox = HiveService.instance.healthBox;
    final cutoff =
        istDateStr(nowWall().subtract(const Duration(days: _readinessWindow)));
    var n = 0, flagged = 0;
    for (final entry in hbox.toMap().entries) {
      if (!entry.key.toString().startsWith('readiness_')) continue;
      final raw = entry.value;
      if (raw is! Map) continue;
      final c = ReadinessCheckin.fromMap(raw);
      if (c.date.isEmpty || c.date.compareTo(cutoff) < 0) continue;
      n++;
      if (c.level != ReadinessLevel.green) flagged++;
    }
    return n >= _minReadiness && flagged * 2 > n;
  }
}
