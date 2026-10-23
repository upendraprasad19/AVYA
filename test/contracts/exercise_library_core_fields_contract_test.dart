// Batch B1 Task 2 — the core-list selection fields on the shipped library
// (seed v13). Written by scripts/add_library_core_fields_v13.js from the
// committed table scripts/data/library_core_fields_v13.json; read by
// CoreListSelector (Task 3) behind `enable_core_list_pool`.
//
// Every literal below was computed from the data (code-review lens 8): the
// discarded ids from the table, the overlay values from plan Rulings 3(a) and
// 4, the per-level counts over the 219 kept rows.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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

  test('variant_family is absent exactly on the 66 discarded rows', () {
    final absent = {for (final r in rows) if (!r.containsKey('variant_family')) id(r)};
    expect(absent, _discarded);
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

  test('per-level core counts over kept rows are 73 / 91 / 67', () {
    final counts = {for (final l in _levels) l: 0};
    for (final r in rows) {
      for (final l in (r['core_levels'] as List).cast<String>()) {
        counts[l] = counts[l]! + 1;
      }
    }
    expect(counts, {'beginner': 73, 'intermediate': 91, 'advanced': 67});
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
    expect(links, hasLength(9));
  });
}
