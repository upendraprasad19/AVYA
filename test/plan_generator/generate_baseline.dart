// ignore_for_file: avoid_print
//
// Batch 0 · D3 — Freeze the current-engine baseline (golden files).
//
// Runs the full-matrix sweep (D1) through the scorecard (D2) against TODAY's
// engine and writes deterministic golden files:
//   test/plan_generator/baseline/baseline_scorecard.json  (machine — the "before")
//   test/plan_generator/baseline/baseline_plans.md        (human face-validity)
// Later batches re-run and diff their scorecard against baseline_scorecard.json:
// their targeted dimension must IMPROVE with NO regression elsewhere.
//
// Deterministic: no timestamps, stable persona ordering → re-running on an
// unchanged engine produces byte-identical files (a git-clean diff = no change).
//
// Run: `dart run test/plan_generator/generate_baseline.dart`

import 'dart:convert';
import 'dart:io';
import 'generator_matrix.dart';
import 'plan_scorecard.dart';

void main() {
  final plans = generateAll();
  final scores = scoreAll(plans);

  // ---- Aggregate ----
  final dims = ['coverage', 'balance', 'volume', 'progression', 'personalization', 'safety', 'realism', 'overall'];
  final sums = {for (final d in dims) d: 0.0};
  var unsafe = 0;
  var equipViolators = 0;
  var withFallback = 0;
  var totalFallback = 0;
  var totalExercises = 0;
  final fallbackByTier = <String, int>{};

  final perPersona = <Map<String, dynamic>>[];
  for (final plan in plans) {
    final sc = scores[plan.persona]!;
    final j = sc.toJson();
    for (final d in dims) {
      sums[d] = sums[d]! + (j[d] as num).toDouble();
    }
    if (!sc.isSafe) unsafe++;
    if (sc.violations.any((v) => v.startsWith('EQUIPMENT'))) equipViolators++;

    final fb = plan.allExercises.where((e) => e.isFallback).length;
    totalExercises += plan.allExercises.length;
    if (fb > 0) {
      withFallback++;
      totalFallback += fb;
      fallbackByTier[plan.persona.equipment] =
          (fallbackByTier[plan.persona.equipment] ?? 0) + fb;
    }

    perPersona.add({'id': plan.persona.id, ...j});
  }

  final n = plans.length;
  final aggregate = {
    'persona_count': n,
    'total_exercises': totalExercises,
    'mean_scores': {for (final d in dims) d: _r(sums[d]! / n)},
    'unsafe_plan_count': unsafe, // HARD invariant — expected 0
    'equipment_violation_plan_count': equipViolators, // HARD invariant — expected 0
    'plans_with_fallback_pick': withFallback,
    'total_fallback_picks': totalFallback,
    'fallback_by_tier': fallbackByTier, // baseline (bodyweight shallow-pool) — no-regression tracked
  };

  final baselineDir = Directory('test/plan_generator/baseline');
  baselineDir.createSync(recursive: true);

  // ---- JSON golden ----
  final jsonOut = const JsonEncoder.withIndent('  ').convert({
    'aggregate': aggregate,
    'personas': perPersona,
  });
  File('${baselineDir.path}/baseline_scorecard.json').writeAsStringSync('$jsonOut\n');

  // ---- Markdown golden (aggregate + curated face-validity subset) ----
  final md = StringBuffer();
  md.writeln('# Workout Generator — Baseline Scorecard (current engine)');
  md.writeln();
  md.writeln('> Frozen by Batch 0. Every later batch must IMPROVE its targeted');
  md.writeln('> dimension with NO regression here. Scores 0-100; safety is a hard gate.');
  md.writeln();
  md.writeln('## Aggregate (${aggregate['persona_count']} personas)');
  md.writeln('| Dimension | Mean |');
  md.writeln('|---|---|');
  final means = {for (final d in dims) d: _r(sums[d]! / n)};
  for (final d in dims) {
    md.writeln('| $d | ${means[d]} |');
  }
  md.writeln();
  md.writeln('- **Unsafe plans (contraindicated exercise present): ${aggregate['unsafe_plan_count']}** '
      '(HARD invariant — must be 0)');
  md.writeln('- **Equipment-violating plans: ${aggregate['equipment_violation_plan_count']}** '
      '(HARD invariant — must be 0)');
  md.writeln('- Plans with ≥1 fallback pick: ${aggregate['plans_with_fallback_pick']} '
      '/ total fallback picks: ${aggregate['total_fallback_picks']}');
  md.writeln('- Fallback picks by tier (baseline — shallow bodyweight pool; no-regression tracked): '
      '`$fallbackByTier`');
  md.writeln();

  md.writeln('## Curated plans (human face-validity)');
  for (final p in _curatedPersonas) {
    final plan = plans.firstWhere(
      (pl) => pl.persona.id == p,
      orElse: () => plans.first,
    );
    _renderPlan(md, plan, scores[plan.persona]!);
  }

  File('${baselineDir.path}/baseline_plans.md').writeAsStringSync(md.toString());

  // ---- Console summary ----
  print('Baseline written: ${plans.length} personas.');
  print('Mean overall: ${means['overall']}  |  unsafe: $unsafe  |  equip-violations: $equipViolators');
  print('Mean by dim: ${{for (final d in dims) d: means[d]}}');
  print('Fallback picks by tier: $fallbackByTier');
  if (unsafe > 0 || equipViolators > 0) {
    print('\n⚠ HARD-INVARIANT breaches in the CURRENT engine — recorded as baseline, NOT silently passed:');
    for (final plan in plans) {
      final sc = scores[plan.persona]!;
      if (!sc.isSafe || sc.violations.any((v) => v.startsWith('EQUIPMENT'))) {
        print('  ${plan.persona.id}: ${sc.violations.join("; ")}');
      }
    }
  }
}

/// Representative personas rendered in full for human review.
const _curatedPersonas = <String>[
  'build_muscle | full_gym | 4d | intermediate | p1 | inj:none',
  'lose_fat | basic_gym | 4d | beginner | p1 | inj:none',
  'strength | full_gym | 4d | advanced | p2 | inj:none',
  'general_fitness | home_dumbbells | 3d | beginner | p1 | inj:none',
  'build_muscle | bodyweight | 4d | intermediate | p1 | inj:none',
  'build_muscle | full_gym | 4d | intermediate | p1 | inj:shoulder',
  'build_muscle | full_gym | 4d | advanced | p1 | inj:shoulder+knee',
];

void _renderPlan(StringBuffer md, GeneratedPlan plan, Scorecard sc) {
  md.writeln('---');
  md.writeln('### ${plan.persona.id}');
  final j = sc.toJson();
  md.writeln('`coverage ${j['coverage']} · balance ${j['balance']} · volume ${j['volume']} · '
      'progression ${j['progression']} · personalization ${j['personalization']} · '
      'safety ${j['safety']} · realism ${j['realism']} · **overall ${j['overall']}**`');
  if (sc.violations.isNotEmpty) {
    md.writeln();
    md.writeln('**⚠ violations:** ${sc.violations.join("; ")}');
  }
  md.writeln();
  for (final day in plan.days) {
    md.writeln('**${day.name}** (${day.focus})');
    md.writeln('| Slot | Exercise | Source | Muscles | Equip |');
    md.writeln('|---|---|---|---|---|');
    for (final ex in day.exercises) {
      final rec = ex.record;
      final muscles = rec != null ? _joinField(rec['primary_muscles']) : '';
      final equip = rec != null ? _joinField(rec['equipment_needed']) : '';
      final flag = ex.isFallback ? ' ⚠' : '';
      md.writeln('| ${ex.slot.targetMuscle}/${ex.slot.movementPattern} | ${ex.name} | '
          '${ex.source}$flag | $muscles | $equip |');
    }
    md.writeln();
  }
}

String _r(double v) => ((v * 10).round() / 10).toString();

/// Coerce a library field that may be a List OR a bare String (rows E252-E260
/// store equipment_needed as a String) into a comma-joined display string.
String _joinField(dynamic v) {
  if (v is List) return v.join(', ');
  if (v is String) return v;
  return '';
}
