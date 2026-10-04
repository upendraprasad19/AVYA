// ignore_for_file: avoid_print
//
// Batch 0 · D2 — Plan Quality Scorecard (7 dimensions, pure-Dart).
//
// Defines "good workout" measurably. Grades a GeneratedPlan 0-100 per
// dimension. Safety is a HARD gate (any contraindicated exercise → 0).
//
// SCOPE HONESTY (this is the baseline ruler, computed on the pure-Dart
// SELECTION path — no Hive/periodization):
//  - Volume uses each exercise's library `default_sets` as the per-session set
//    proxy (the periodized set count from PeriodizationEngine is NOT in this
//    path). Directional + consistent before/after → deltas are meaningful.
//  - Progression is a SUITE-level metric (phase N total sets ≤ phase N+1),
//    injected per-plan from its persona family.
//  - Personalization currently = injury-handling only (body-focus / cardio
//    features don't exist until Batches 4/1 — hooks are stubbed, scored N/A).
// Each dimension sharpens as the owning feature lands (NOT deferred silently).

import 'package:icanbefitter/shared/repositories/plan_engine/muscle_groups.dart';

import 'generator_matrix.dart';
import 'package:icanbefitter/core/utils/equipment_vocab.dart';

/// The major groups a well-rounded weekly plan is expected to train.
const _expectedGroups = <String>[
  'Chest', 'Back', 'Shoulders', 'Biceps', 'Triceps',
  'Quads', 'Hamstrings', 'Glutes', 'Core', 'Calves',
];

// Science landmarks (R5): direct sets/muscle/week effective band.
const _mev = 8;
const _mrv = 20;

// Delegates to the shared lib map (Batch 9 de-drift) — byte-identical content,
// same `.toLowerCase().trim()` normalization, so the frozen D3 baseline is unmoved.
String? _groupOf(String muscle) => muscleGroupOf(muscle);

List<String> _asStrings(dynamic v) {
  if (v is List) return v.map((e) => e.toString()).toList();
  if (v is String && v.isNotEmpty) return [v];
  return const [];
}

class Scorecard {
  final double coverage;
  final double balance;
  final double volume;
  final double progression;
  final double personalization;
  final double safety; // HARD: 100 or 0
  final double realism;
  final List<String> violations; // human-readable hard-invariant breaches

  const Scorecard({
    required this.coverage,
    required this.balance,
    required this.volume,
    required this.progression,
    required this.personalization,
    required this.safety,
    required this.realism,
    required this.violations,
  });

  /// Overall = mean of the 7 dimensions, but a safety breach hard-caps it at 0
  /// (an unsafe plan is never "good" no matter how balanced).
  double get overall {
    if (safety < 100) return 0;
    return (coverage +
            balance +
            volume +
            progression +
            personalization +
            realism) /
        6.0;
  }

  bool get isSafe => safety >= 100;

  Map<String, dynamic> toJson() => {
        'coverage': _r(coverage),
        'balance': _r(balance),
        'volume': _r(volume),
        'progression': _r(progression),
        'personalization': _r(personalization),
        'safety': _r(safety),
        'realism': _r(realism),
        'overall': _r(overall),
        'violations': violations,
      };

  static double _r(double v) => (v * 10).round() / 10;
}

/// Coverage: fraction of expected major groups trained (primary) this week.
double _coverage(GeneratedPlan plan) {
  final trained = <String>{};
  for (final ex in plan.allExercises) {
    final rec = ex.record;
    if (rec == null) continue;
    for (final m in _asStrings(rec['primary_muscles'])) {
      final g = _groupOf(m);
      if (g != null) trained.add(g);
    }
  }
  final hit = _expectedGroups.where(trained.contains).length;
  return 100.0 * hit / _expectedGroups.length;
}

/// Balance: mean of push:pull and knee:hip movement-pattern ratios.
double _balance(GeneratedPlan plan) {
  var hPush = 0, vPush = 0, hPull = 0, vPull = 0, knee = 0, hip = 0;
  for (final ex in plan.allExercises) {
    if (ex.isSafelyOmitted) continue; // no exercise occupies this slot (U2)
    final pats = ex.record != null
        ? _asStrings(ex.record!['movement_pattern'])
        : [ex.slot.movementPattern];
    for (final p in pats) {
      switch (p) {
        case 'horizontal_push': hPush++; break;
        case 'vertical_push': vPush++; break;
        case 'horizontal_pull': hPull++; break;
        case 'vertical_pull': vPull++; break;
        case 'knee_dominant': knee++; break;
        case 'hip_dominant': hip++; break;
      }
    }
  }
  final push = hPush + vPush, pull = hPull + vPull;
  final pushPull = _ratio(push, pull);
  final legs = _ratio(knee, hip);
  // If a plan has no leg work at all, don't penalize the leg ratio to 0 for an
  // upper-only split day set — but across a WEEK a balanced plan has both.
  final parts = <double>[pushPull];
  if (knee + hip > 0) parts.add(legs);
  return 100.0 * parts.reduce((a, b) => a + b) / parts.length;
}

double _ratio(int a, int b) {
  if (a == 0 && b == 0) return 1.0; // neither present → not imbalanced
  final lo = a < b ? a : b, hi = a < b ? b : a;
  return hi == 0 ? 0.0 : lo / hi;
}

/// Volume: fraction of trained major groups whose weekly direct sets ∈ [MEV,MRV].
/// Direct = primary muscle × default_sets; indirect (secondary) × 0.5.
double _volume(GeneratedPlan plan) {
  final setsByGroup = <String, double>{};
  for (final ex in plan.allExercises) {
    final rec = ex.record;
    if (rec == null) continue;
    final sets = (rec['default_sets'] as num?)?.toDouble() ?? 3.0;
    for (final m in _asStrings(rec['primary_muscles'])) {
      final g = _groupOf(m);
      if (g != null) setsByGroup[g] = (setsByGroup[g] ?? 0) + sets;
    }
    for (final m in _asStrings(rec['secondary_muscles'])) {
      final g = _groupOf(m);
      if (g != null) setsByGroup[g] = (setsByGroup[g] ?? 0) + sets * 0.5;
    }
  }
  if (setsByGroup.isEmpty) return 0;
  var inBand = 0.0;
  for (final entry in setsByGroup.entries) {
    final s = entry.value;
    if (s >= _mev && s <= _mrv) {
      inBand += 1;
    } else if (s < _mev) {
      inBand += (s / _mev).clamp(0.0, 1.0); // partial credit toward MEV
    } else {
      // over MRV — linear penalty, floored at 0 by 2×MRV
      inBand += (1 - (s - _mrv) / _mrv).clamp(0.0, 1.0);
    }
  }
  return 100.0 * inBand / setsByGroup.length;
}

/// Personalization: of the personalization inputs this persona HAS, how many
/// are honored? Today only injuries exist as a consumed input (body-focus /
/// cardio land in Batches 4/1). No inputs → 100 (nothing to get wrong).
double _personalization(GeneratedPlan plan) {
  if (plan.persona.injuries.isEmpty) return 100.0; // nothing personalized yet
  // Honored = zero contraindicated picks (same signal as safety, but scored
  // as "did the personalization input take effect", which for injuries == safety).
  return _safetyViolations(plan).isEmpty ? 100.0 : 0.0;
}

/// Safety: HARD gate. Any main exercise contraindicated for the persona's
/// injuries → the plan is unsafe. Returns the list of violations.
List<String> _safetyViolations(GeneratedPlan plan) {
  final inj = plan.persona.injuries.map((e) => e.toLowerCase()).toSet();
  if (inj.isEmpty) return const [];
  final out = <String>[];
  for (final ex in plan.allExercises) {
    final rec = ex.record;
    if (rec == null) continue;
    final contra = _asStrings(rec['injury_contraindications'])
        .map((e) => e.toLowerCase())
        .toSet();
    final hit = contra.intersection(inj);
    if (hit.isNotEmpty) {
      out.add('${ex.name} contraindicated for ${hit.join(",")}');
    }
  }
  return out;
}

/// Realism: fraction of exercises that are on-target (non-fallback, present).
double _realism(GeneratedPlan plan) {
  // A safely-omitted slot (U2) is not a pick at all — exclude it from BOTH
  // numerator and denominator so it neither rewards nor penalizes realism.
  final all = plan.allExercises.where((e) => !e.isSafelyOmitted).toList();
  if (all.isEmpty) return 0;
  final good = all.where((e) => !e.isFallback && !e.isMissing).length;
  return 100.0 * good / all.length;
}

/// Score one plan. `familyProgression` is the suite-computed monotonicity score
/// for this plan's (goal,equip,days,exp) family (same for all 3 phase siblings).
Scorecard scorePlan(GeneratedPlan plan, {required double familyProgression}) {
  final safetyViol = _safetyViolations(plan);
  final equipViol = _equipmentViolations(plan);
  final violations = <String>[
    ...safetyViol,
    ...equipViol.map((v) => 'EQUIPMENT: $v'),
  ];
  return Scorecard(
    coverage: _coverage(plan),
    balance: _balance(plan),
    volume: _volume(plan),
    progression: familyProgression,
    personalization: _personalization(plan),
    safety: safetyViol.isEmpty ? 100.0 : 0.0,
    realism: _realism(plan),
    violations: violations,
  );
}

/// Equipment invariant (HARD, baseline): every picked exercise's `equipment_tier`
/// list INCLUDES the persona's tier — exactly what the live V4 `queryV4` filters
/// on (exercise_repository.dart:248: no tier on the exercise → passes; else must
/// contain the user's tier). NOTE: this is the CURRENT-engine guarantee. The
/// item-level `equipment_needed ⊆ user's items` check is a FUTURE (Batch 5)
/// invariant — and this baseline empirically confirmed WHY it isn't ready:
/// `equipment_needed` is free-text ("barbell on rack or trx", "cable machine")
/// + 9 rows store it as a bare String, so it can't be filtered on until Batch 5's
/// data-quality pass. Attempts 1-4 are tier-guaranteed; only universal-pool
/// fallback picks (which bypass queryV4) can breach this.
List<String> _equipmentViolations(GeneratedPlan plan) {
  // ⑧ OI-144: keyed on what the user can PERFORM, not on `equipment_tier`.
  //
  // The old form asked "does this row's equipment_tier list contain the persona's
  // tier?" — which is the very field the generator stopped treating as
  // authoritative. It would report a legitimately-unlocked exercise as a
  // violation: a home_dumbbells user who OWNS a pull-up bar is correctly given
  // Chin Up, whose equipment_tier is [basic_gym, full_gym]. OI-89 promoted this
  // check to a hard `== 0`, so a tier-keyed oracle would fail the gate on correct
  // behaviour.
  //
  // The oracle reads `equipment_needed` against the persona's EFFECTIVE set. That
  // is the same field the production predicate reads — one step apart, not
  // independent — and the independent evidence remains check_equipment_audit,
  // which reads the exercise NAME and coaching prose instead.
  final effective = EquipmentVocab.effectiveItems(
    plan.persona.equipment,
    plan.persona.equipmentOwned,
    plan.persona.equipmentExclusions,
  );
  final out = <String>[];
  for (final ex in plan.allExercises) {
    final rec = ex.record;
    if (rec == null) continue; // placeholder — realism already penalizes it
    final needed = EquipmentVocab.fromProfile(rec['equipment_needed']);
    if (needed.isEmpty) continue; // unreadable requirement — not a tier claim
    final off = needed.where((t) => !effective.contains(t)).toList();
    if (off.isNotEmpty) {
      out.add('${ex.name} needs $off, outside ${plan.persona.equipment}'
          '${plan.persona.equipmentOwned.isEmpty ? '' : ' +owned'}');
    }
  }
  return out;
}

/// Suite-level progression: for each (goal,equip,days,exp) family, is total
/// weekly direct-set volume non-decreasing across phases 1→2→6? Returns a map
/// familyKey → 0-100 (100 = monotonic non-decreasing, 0 = decreased).
Map<String, double> computeProgression(List<GeneratedPlan> plans) {
  String familyKey(Persona p) =>
      '${p.goal}|${p.equipment}|${p.days}|${p.experience}|${p.injuryLabel}';
  double totalSets(GeneratedPlan plan) {
    var s = 0.0;
    for (final ex in plan.allExercises) {
      s += (ex.record?['default_sets'] as num?)?.toDouble() ?? 3.0;
    }
    return s;
  }

  final byFamily = <String, Map<int, double>>{};
  for (final plan in plans) {
    final k = familyKey(plan.persona);
    (byFamily[k] ??= {})[plan.persona.phase] = totalSets(plan);
  }

  final result = <String, double>{};
  for (final entry in byFamily.entries) {
    final phasesSorted = entry.value.keys.toList()..sort();
    if (phasesSorted.length < 2) {
      result[entry.key] = 100.0; // only one phase sampled → nothing to violate
      continue;
    }
    var monotonic = true;
    for (var i = 1; i < phasesSorted.length; i++) {
      if (entry.value[phasesSorted[i]]! < entry.value[phasesSorted[i - 1]]! - 0.001) {
        monotonic = false;
        break;
      }
    }
    result[entry.key] = monotonic ? 100.0 : 0.0;
  }
  return result;
}

/// Convenience: score every plan, wiring in suite progression.
Map<Persona, Scorecard> scoreAll(List<GeneratedPlan> plans) {
  final prog = computeProgression(plans);
  String familyKey(Persona p) =>
      '${p.goal}|${p.equipment}|${p.days}|${p.experience}|${p.injuryLabel}';
  final out = <Persona, Scorecard>{};
  for (final plan in plans) {
    out[plan.persona] =
        scorePlan(plan, familyProgression: prog[familyKey(plan.persona)] ?? 100.0);
  }
  return out;
}
