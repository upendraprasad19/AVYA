// Batch B1 Task 2 — the core-list selection fields on the shipped library
// (seed v13). Written by scripts/add_library_core_fields_v13.js from the
// committed table scripts/data/library_core_fields_v13.json; read by
// CoreListSelector (Task 3; behind `enable_core_list_pool` until Unit 1B-F).
//
// Every literal below was computed from the data (code-review lens 8): the
// discarded ids from the table, the overlay values from plan Rulings 3(a) and
// 4, the per-level counts over the 219 kept rows.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Batch C2a (OI-460): the `remove` ids of scripts/data/library_batch_c2_removals.json have left the library.
final Set<String> _c2Removed = {
  for (final e in ((jsonDecode(File('scripts/data/library_batch_c2_removals.json').readAsStringSync()) as Map<String, dynamic>)['entries'] as List))
    if ((e as Map)['decision'] == 'remove') e['id'] as String,
};

const _levels = {'beginner', 'intermediate', 'advanced'};
const _disciplines = {
  'strength', 'calisthenics_skill', 'olympic', 'plyometric', 'mobility',
  'cardio', 'prehab', 'yoga', 'conditioning',
};
const _gyms = {'home', 'standard_gym', 'well_equipped_gym', 'specialty'};

/// The 66 rows the tagging pass discarded: no variant_family, no core level.
const _discarded = {
  'E075', 'E081', 'E082', 'E084', 'E101', 'E111', 'E115', 'E116', 'E119',
  'E125', 'E126', 'E128', 'E130', 'E137', 'E138', 'E144', 'E146', 'E148',
  'E150', 'E153', 'E154', 'E156', 'E157', 'E158', 'E160', 'E162', 'E163',
  'E164', 'E169', 'E170', 'E178', 'E179', 'E183', 'E184', 'E192', 'E194',
  'E195', 'E196', 'E197', 'E199', 'E204', 'E208', 'E210', 'E211', 'E218',
  'E221', 'E223', 'E227', 'E228', 'E233', 'E234', 'E237', 'E243', 'E254',
  'E256', 'E261', 'E263', 'E265', 'E271', 'E279', 'E281', 'E285', 'E287',
  'E288', 'E293', 'E294',
};

/// Plan Ruling 3(a): ON-only movement pattern overlay.
const _slotPattern = <String, List<String>>{
  'E015': ['shoulder_isolation'],
  'E048': ['hip_dominant'],
  'E222': ['hip_dominant'],
  'E127': ['hip_dominant'],
  'E046': ['knee_dominant'],
  'E276': ['shoulder_isolation'],
  'E064': ['cardio'],
  'E292': ['knee_dominant'],
  // Library Batch S1b-2: the loaded version of E050 Sumo Deadlift takes its original's overlay. N19 Dumbbell Glute Bridge
  // does not (founder, 2026-11-09): it fills the Glutes isolation slot, where E048 is kept out by the overlay.
  'N20': ['hip_dominant'],
  'E050': ['hip_dominant'],
  'E274': ['shoulder_isolation'],
  'E277': ['shoulder_isolation'],
  'E198': ['knee_dominant'],
};

/// Plan Ruling 4: ON-only target-focus overlay.
const _slotFocus = <String, List<String>>{
  'E064': ['Full Body', 'Mid Back'],
  'E114': ['Shoulders', 'Front Delts', 'Upper Chest'],
  'E118': ['Mid Chest'],
  'E186': ['Front Delts', 'Shoulders', 'Mid Chest', 'Triceps'],
  'E198': ['Glutes', 'Quads', 'Core/Obliques'],
  'E264': ['Lats', 'Mid Back'],
  'E272': ['Shoulders', 'Rear Delts'],
  'E273': ['Lateral Delts', 'Shoulders'],
  'E274': ['Mid Back', 'Rear Delts'],
  'E275': ['Lats', 'Mid Back'],
  'E276': ['Rear Delts', 'Mid Back'],
  'E277': ['Mid Back', 'Rear Delts'],
  'E289': ['Lateral Delts', 'Shoulders'],
  'E290': ['Shoulders', 'Rear Delts'],
  'E090': ['Core', 'Core/Obliques', 'Forearms'],
  'E122': ['Biceps (Short Head)'],
  'E133': ['Core', 'Core/Obliques'],
  'E172': ['Core/Obliques'],
  'E175': ['Core/Obliques'],
};

void main() {
  final rows = (jsonDecode(
    File('assets/data/exercise_library.json').readAsStringSync(),
  ) as List)
      .cast<Map<String, dynamic>>();
  String id(Map<String, dynamic> r) => r['id'] as String;

  test('every row carries the five required core-list keys with legal values',
      () {
    final bad = <String>[];
    for (final r in rows) {
      final levels = r['core_levels'];
      if (levels is! List || levels.any((l) => !_levels.contains(l)) ||
          levels.toSet().length != levels.length) {
        bad.add('${id(r)}.core_levels=$levels');
      }
      if (!_disciplines.contains(r['discipline'])) {
        bad.add('${id(r)}.discipline=${r['discipline']}');
      }
      if (!_gyms.contains(r['gym_availability'])) {
        bad.add('${id(r)}.gym_availability=${r['gym_availability']}');
      }
      for (final k in ['requires_coaching', 'high_impact']) {
        if (r[k] is! bool) bad.add('${id(r)}.$k=${r[k]}');
      }
    }
    expect(bad, isEmpty);
  });

  test('variant_family is absent exactly on the discarded rows that are still in the library (66 minus the C2a removals)', () {
    final absent = {for (final r in rows) if (!r.containsKey('variant_family')) id(r)};
    expect(absent, _discarded.difference(_c2Removed));
    final blank = [
      for (final r in rows)
        if (r.containsKey('variant_family') &&
            (r['variant_family'] is! String ||
                (r['variant_family'] as String).trim().isEmpty))
          id(r)
    ];
    expect(blank, isEmpty);
  });

  test('every discarded row has core_levels: []', () {
    expect([
      for (final r in rows)
        if (_discarded.contains(id(r)) && (r['core_levels'] as List).isNotEmpty)
          id(r)
    ], isEmpty);
  });

  test('slot_pattern and slot_focus sit on exactly the ruled ids and values',
      () {
    expect({
      for (final r in rows)
        if (r.containsKey('slot_pattern')) id(r): r['slot_pattern']
    }, _slotPattern);
    expect({
      for (final r in rows)
        if (r.containsKey('slot_focus')) id(r): r['slot_focus']
    }, _slotFocus);
  });

  // Library Batch S1a (docs/plans/2026-11-08-library-batch-s1-core-data.md, Table A) moved these from 129 / 138 / 98
  // (73 / 91 / 67 original + 56 / 47 / 31 Batch C1): 21 kept rows through scripts/data/library_s1_core_levels.json and 13
  // source rows in scripts/data/library_batch_c_source.json. Counted by node from the library, not typed from the plan.
  test('per-level core counts are 135 / 165 / 137 (74 / 101 / 83 kept-row + 61 / 64 / 54 Batch C1 source; Library Batch S1b-1: E038 off advanced, E107 and G0168 at every level, E109 at beginner; Library Batch S1b-2: N14 to N22 add 4 / 9 / 9)', () {
    final counts = {for (final l in _levels) l: 0};
    for (final r in rows) {
      for (final l in (r['core_levels'] as List).cast<String>()) {
        counts[l] = counts[l]! + 1;
      }
    }
    expect(counts, {'beginner': 135, 'intermediate': 165, 'advanced': 137});
  });

  test('the seed version is at least 13, so existing installs re-seed', () {
    final src = File('lib/core/services/seed_service.dart').readAsStringSync();
    final m = RegExp(r'_exerciseLibraryVersion\s*=\s*(\d+)').firstMatch(src);
    expect(m, isNotNull, reason: 'version constant not found');
    expect(int.parse(m!.group(1)!), greaterThanOrEqualTo(13),
        reason: 'without the bump a v12 Hive box never receives these keys');
  });

  test('every regression_to / progression_to resolves to exactly one row', () {
    final byName = <String, int>{};
    for (final r in rows) {
      byName[r['name'] as String] = (byName[r['name'] as String] ?? 0) + 1;
    }
    final links = <String>[], bad = <String>[];
    for (final r in rows) {
      for (final k in ['regression_to', 'progression_to']) {
        if (!r.containsKey(k)) continue;
        links.add('${id(r)}.$k');
        if (byName[r[k]] != 1) bad.add('${id(r)}.$k=${r[k]}');
      }
    }
    expect(bad, isEmpty);
    expect(links, hasLength(34), reason: '9 original links (E256 left in Batch C2a) + 26 on the shipped Batch C1 rows');
  });
}
