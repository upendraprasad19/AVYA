// Library Batch S1b-2 (plan docs/plans/2026-11-09-library-batch-s1b2-loaded-versions.md, Decisions 1 and 3): the nine
// loaded versions (OI-148, founder 2026-11-08) and the E010 / E045 suitable_for widening (founder 2026-11-09, board d12),
// read from the shipped library. The same-day rule that reads `same_movement_as` is pinned by
// test/plan_generator/same_movement_day_gate_test.dart and same_movement_behavioral_test.dart.
//
// The expected pairs and core levels are restated here from the plan, never read from the source file, so a source
// edit that moves one is red.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

typedef Json = Map<String, dynamic>;

const _all = ['beginner', 'intermediate', 'advanced'];
const _ia = ['intermediate', 'advanced'];

/// id -> (original id, name, equipment_needed, core_levels).
const _rows = <String, (String, String, List<String>, List<String>)>{
  'N14': ('E147', 'Dumbbell Sumo Squat', ['dumbbells'], _all),
  'N15': ('E259', 'Dumbbell Split Squat', ['dumbbells'], _all),
  'N16': ('E042', 'Dumbbell Walking Lunge', ['dumbbells'], _ia),
  'N17': ('E145', 'Dumbbell Lateral Lunge', ['dumbbells'], _ia),
  'N18': ('E047', 'Dumbbell Hip Thrust', ['dumbbells', 'elevated surface'], _ia),
  'N19': ('E048', 'Dumbbell Glute Bridge', ['dumbbells'], _all),
  'N20': ('E050', 'Dumbbell Sumo Deadlift', ['dumbbells'], _ia),
  'N21': ('E045', 'Kettlebell Romanian Deadlift', ['kettlebell'], _all),
  'N22': ('E059', 'Weighted Russian Twist', ['dumbbells'], _ia),
};

/// Keys a loaded version copies from its original unchanged (Decision 1).
const _copied = [
  'category', 'movement_pattern', 'primary_muscles', 'secondary_muscles', 'target_focus', 'difficulty_level',
  'priority_tier', 'tempo', 'is_bilateral', 'default_sets', 'variant_family', 'slot_pattern', 'injury_contraindications',
];

List<String> _strs(Object? v) => v is List ? v.map((e) => '$e').toList() : const [];

void main() {
  final lib = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List).cast<Json>();
  final byId = {for (final r in lib) r['id'] as String: r};

  test('the nine rows exist with their name, original, equipment and core levels', () {
    for (final e in _rows.entries) {
      final r = byId[e.key];
      expect(r, isNotNull, reason: e.key);
      final (orig, name, eq, core) = e.value;
      expect(r!['name'], name);
      expect(r['same_movement_as'], orig, reason: e.key);
      expect(r['equipment_needed'], eq, reason: e.key);
      expect(r['core_levels'], core, reason: e.key);
      expect(r['logging_type'], 'weight_reps', reason: e.key);
      expect(r['is_foundational'], isFalse, reason: '${e.key}: a new row stays out of the Phase 1 foundational pool');
      expect(r['discipline'], 'strength');
      expect(r['high_impact'], isFalse);
      expect(r['requires_coaching'], isFalse);
    }
  });

  test('each copies its original where the load changes nothing (injury tags included), and the exceptions are the planned ones', () {
    for (final e in _rows.entries) {
      final r = byId[e.key]!;
      final o = byId[e.value.$1]!;
      for (final k in _copied) {
        if (e.key == 'N19' && (k == 'slot_pattern' || k == 'priority_tier')) continue;
        expect(jsonEncode(r[k]), jsonEncode(o[k]), reason: '${e.key}.$k vs ${o['id']}');
      }
      if (e.key == 'N19') {
        // Founder, 2026-11-09 (after the Task 3 audit): N19 drops E048's ON overlay so the Glutes isolation slot offers it.
        expect(r.containsKey('slot_pattern'), isFalse, reason: 'N19 carries no slot_pattern');
        expect(o['slot_pattern'], ['hip_dominant'], reason: 'E048 keeps its overlay');
        // Founder, 2026-11-09: priority 3 (E048 has 2), level with E109 Glute Kickback (Cable), so a gym user keeps the cable row.
        expect([r['priority_tier'], o['priority_tier']], [3, 2]);
      }
      expect(r['suitable_for'], o['suitable_for'], reason: '${e.key}: N21 copies E045 AFTER the widening');
      expect(r['exercise_type'], e.key == 'N15' ? ['compound'] : o['exercise_type'], reason: e.key);
      if (e.key == 'N20') {
        expect([r['default_reps'], r['rep_range'], r['default_rest_secs'], r['cns_demand']], ['8-12', '8-12', 120, 3],
            reason: 'N20 is set for a dumbbell, not the barbell numbers');
      } else {
        for (final k in ['default_reps', 'rep_range', 'default_rest_secs', 'cns_demand']) {
          expect(r[k], o[k], reason: '${e.key}.$k');
        }
      }
    }
  });

  test('every same_movement_as names an existing row that carries no link itself, and only the nine carry one', () {
    final linked = [for (final r in lib) if (r.containsKey('same_movement_as')) r['id']];
    expect(linked.toSet(), _rows.keys.toSet());
    for (final id in _rows.keys) {
      final target = byId[byId[id]!['same_movement_as']];
      expect(target, isNotNull, reason: '$id links a missing row');
      expect(target!.containsKey('same_movement_as'), isFalse, reason: '$id links a linked row');
    }
  });

  test('core_levels lie inside suitable_for for the nine rows', () {
    for (final id in _rows.keys) {
      final sf = _strs(byId[id]!['suitable_for']).map((s) => s.toLowerCase()).toSet();
      expect(_strs(byId[id]!['core_levels']).where((l) => !sf.contains(l)), isEmpty, reason: id);
    }
  });

  test('E010 Pike Push Up and E045 Romanian Deadlift are suitable for every level (founder 2026-11-09)', () {
    expect(byId['E010']!['suitable_for'], ['Beginner', 'Intermediate', 'Advanced']);
    expect(byId['E045']!['suitable_for'], ['Beginner', 'Intermediate', 'Advanced']);
  });

  test('N21 reaches only full gym (kettlebell); the dumbbell rows reach home dumbbells and both gyms', () {
    expect(byId['N21']!['equipment_tier'], ['full_gym']);
    for (final id in _rows.keys.where((i) => i != 'N21')) {
      expect(byId[id]!['equipment_tier'], ['home_dumbbells', 'basic_gym', 'full_gym'], reason: id);
    }
  });
}
