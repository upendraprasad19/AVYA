// Generator step 1A, R3 (a) data contract
// (docs/plans/2026-11-08-generator-step1-core-list.md): the like-for-like
// implement reduction depends on the library's data (exercise_type and the
// first-listed primary muscle), so this test pins, per (tier, level, isolation
// slot shape) of the real splits, which rows the reduced pool holds. A library
// edit that turns a cell off or drops a row fails here and must be re-recorded
// on purpose. The rows are also checked against the rule restated without the
// selector's helpers (isolation type; first muscle equals the slot muscle, or a
// listed calf head), and "Calves (Peroneus)" must not match.
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/core/utils/equipment_vocab.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/core_list_selector.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/split_resolver.dart';

const _implementPatterns = {
  'elbow_flexion', 'elbow_extension', 'shoulder_isolation', 'horizontal_pull', 'vertical_pull',
  'vertical_push',
};

/// Recorded 2026-11-08 on the 862-row library (generator step 1A). Key:
/// tier|level|muscle|pattern|subFocus; value: the reduced pool's ids in rank order.
/// Library Batch S1a (2026-11-08, plan docs/plans/2026-11-08-library-batch-s1-core-data.md) moved three cells:
/// G0339 Dumbbell Lying Hamstring Curl became core at intermediate and advanced, so it joins the full_gym Hamstrings
/// curl cells (last: priority 3); E257 Glute Kickback became core at advanced, so the home_dumbbells advanced Glutes
/// isolation core pool is [E257], all improvised, and no like-for-like reduction applies there any more.
const _expected = <String, List<String>>{
  'home_dumbbells|beginner|Calves|knee_dominant|': ['E258'],
  'home_dumbbells|beginner|Calves|knee_dominant|soleus': ['E258'],
  'home_dumbbells|intermediate|Calves|knee_dominant|': ['E258', 'G0409'],
  'home_dumbbells|intermediate|Calves|knee_dominant|soleus': ['E258', 'G0409'],
  'home_dumbbells|advanced|Calves|knee_dominant|': ['G0409'],
  'home_dumbbells|advanced|Calves|knee_dominant|soleus': ['G0409'],
  'basic_gym|beginner|Calves|knee_dominant|': ['E258'],
  'basic_gym|beginner|Calves|knee_dominant|soleus': ['E258'],
  'basic_gym|intermediate|Calves|knee_dominant|': ['E051', 'E258', 'G0409'],
  'basic_gym|intermediate|Glutes|hip_isolation|': ['E109'],
  'basic_gym|intermediate|Hamstrings|knee_dominant|': ['G0339'],
  'basic_gym|intermediate|Calves|knee_dominant|soleus': ['E051', 'E258', 'G0409'],
  'basic_gym|advanced|Calves|knee_dominant|': ['E051', 'G0409'],
  'basic_gym|advanced|Glutes|hip_isolation|': ['E109'],
  'basic_gym|advanced|Hamstrings|knee_dominant|': ['G0339'],
  'basic_gym|advanced|Calves|knee_dominant|soleus': ['E051', 'G0409'],
  'full_gym|beginner|Calves|knee_dominant|': ['E052', 'E258'],
  'full_gym|beginner|Quads|knee_dominant|isolation': ['E043'],
  'full_gym|beginner|Hamstrings|knee_dominant|': ['G0599'],
  'full_gym|beginner|Calves|knee_dominant|soleus': ['E052', 'E258'],
  'full_gym|intermediate|Calves|knee_dominant|': ['E051', 'E052', 'E258', 'G0409'],
  'full_gym|intermediate|Glutes|hip_isolation|': ['E109'],
  'full_gym|intermediate|Quads|knee_dominant|isolation': ['E043'],
  'full_gym|intermediate|Hamstrings|knee_dominant|': ['E049', 'G0599', 'G0339'],
  'full_gym|intermediate|Calves|knee_dominant|soleus': ['E052', 'E051', 'E258', 'G0409'],
  'full_gym|advanced|Calves|knee_dominant|': ['E051', 'E052', 'G0409'],
  'full_gym|advanced|Glutes|hip_isolation|': ['E109'],
  'full_gym|advanced|Quads|knee_dominant|isolation': ['E043'],
  'full_gym|advanced|Hamstrings|knee_dominant|': ['E049', 'G0599', 'G0339'],
  'full_gym|advanced|Calves|knee_dominant|soleus': ['E052', 'E051', 'G0409'],
};

List<String> _strs(Object? v) =>
    v is List ? [for (final e in v) e.toString()] : const <String>[];

bool _restatedLikeForLike(Map<String, dynamic> r, String muscle) {
  if (!_strs(r['exercise_type']).map((t) => t.toLowerCase()).contains('isolation')) {
    return false;
  }
  final prim = _strs(r['primary_muscles']);
  if (prim.isEmpty) return false;
  final m = prim.first.trim().toLowerCase();
  final t = muscle.toLowerCase();
  return m == t ||
      (t == 'calves' && (m == 'calves (gastrocnemius)' || m == 'calves (soleus)'));
}

void main() {
  final rows = (jsonDecode(
    File('assets/data/exercise_library.json').readAsStringSync(),
  ) as List)
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList();

  // Every isolation slot shape the reduction can apply to, from the real splits.
  final shapes = <String, MuscleSlot>{};
  for (final goal in const ['build_muscle', 'lose_fat', 'general_fitness', 'strength']) {
    for (final days in const [3, 4, 5, 6]) {
      for (final level in const ['beginner', 'intermediate', 'advanced']) {
        for (final d in SplitResolver.selectV4(goal, days, experienceLevel: level)) {
          for (final s in [...d.slotsA, ...?d.slotsB]) {
            if (s.exerciseType.toLowerCase() != 'isolation' ||
                s.movementPattern == 'core' ||
                _implementPatterns.contains(s.movementPattern)) {
              continue;
            }
            shapes['${s.targetMuscle}|${s.movementPattern}|${s.subFocus ?? ''}'] = s;
          }
        }
      }
    }
  }

  Map<String, List<String>> measure() {
    final out = <String, List<String>>{};
    for (final tier in const ['home_dumbbells', 'basic_gym', 'full_gym']) {
      final cap = EquipmentVocab.effectiveItems(tier, null, null);
      for (final level in const ['beginner', 'intermediate', 'advanced']) {
        for (final e in shapes.entries) {
          final r = CoreListSelector.rankedPool(
            rows: rows,
            slot: e.value,
            level: level,
            phase: 1,
            equipmentTier: tier,
            capability: cap,
            exclusions: const {},
            isContraindicated: (_) => false,
            pickedNames: const {},
            demotedNames: const {},
          );
          if (r.likeForLikeImplement) {
            out['$tier|$level|${e.key}'] = [for (final x in r.ordered) x['id'] as String];
          }
        }
      }
    }
    return out;
  }

  test('the splits hold isolation slots the reduction can apply to', () {
    expect(shapes.keys,
        containsAll(['Calves|knee_dominant|', 'Calves|knee_dominant|soleus', 'Quads|knee_dominant|isolation']));
  });

  test('the reduced pools per (tier, level, slot) are the recorded ones', () {
    final got = measure();
    expect(got, _expected,
        reason: 'library data changed a like-for-like cell; re-record on purpose:\n'
            '${got.entries.map((e) => "  '${e.key}': ${jsonEncode(e.value).replaceAll('"', "'")},").join('\n')}');
  });

  test('every recorded row meets the restated rule', () {
    final byId = {for (final r in rows) r['id'] as String: r};
    for (final e in _expected.entries) {
      final muscle = e.key.split('|')[2];
      for (final id in e.value) {
        expect(_restatedLikeForLike(byId[id]!, muscle), isTrue, reason: '${e.key} $id');
      }
    }
  });

  test('the calf heads: E051 and E052 qualify for Calves, Peroneus never does', () {
    final byId = {for (final r in rows) r['id'] as String: r};
    expect(_restatedLikeForLike(byId['E051']!, 'Calves'), isTrue);
    expect(_restatedLikeForLike(byId['E052']!, 'Calves'), isTrue);
    expect(CoreListSelector.namesMuscle('Calves (Peroneus)', 'Calves'), isFalse);
    expect(
        _expected.entries
            .where((e) => e.key.startsWith('full_gym|intermediate|Calves|'))
            .expand((e) => e.value),
        containsAll(['E051', 'E052']));
  });
}
