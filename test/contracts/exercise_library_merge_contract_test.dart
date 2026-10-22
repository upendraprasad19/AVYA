// Batch A Task 2 (docs/plans/2026-10-22-library-data-repair.md) — seven
// duplicate rows are retired into their twins.
//
// A retired row leaves the bundled JSON; its name moves to the kept row's
// `name_aliases` (read by search and the exact-name lookups) and its id to the
// kept row's `merged_ids` (read by the seed prune, which deletes it from every
// install's exerciseBox). Where the twins share a movement_pattern the kept row
// also carries the retired twin's selection fields, so the slot it used to fill
// keeps the same movement. Injury tags are NEVER merged: the founder's 13-B
// carve-out keeps 'v-up' and 'hip abduction machine' untagged
// (injury_undertag_13b_contract_test.dart, k13bKeptSafe).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// retired id -> (retired name, kept id)
const _merges = <String, (String, String)>{
  'E241': ('Close-Grip Bench Press', 'E016'),
  'E240': ('Overhead Cable Extension', 'E097'),
  'E225': ('Hip Abductor Machine', 'E107'),
  'E249': ('V-Ups', 'E176'),
  'E165': ('Quad Stretch', 'E216'),
  'E167': ('Cross Body Shoulder Stretch', 'E219'),
  'E168': ('Doorway Chest Stretch', 'E220'),
};

void main() {
  final rows = (jsonDecode(
    File('assets/data/exercise_library.json').readAsStringSync(),
  ) as List)
      .cast<Map<String, dynamic>>();
  final byId = {for (final r in rows) r['id'] as String: r};
  List<String> strings(Object? v) =>
      v is List ? v.map((e) => e.toString()).toList() : const <String>[];

  group('exercise_library duplicate merges (Batch A Task 2)', () {
    test('285 rows, and none of the 7 retired ids is a row', () {
      expect(rows.length, 285);
      expect(_merges.keys.where(byId.containsKey), isEmpty);
    });

    test('each retired id sits in exactly one merged_ids, on its kept twin', () {
      for (final MapEntry(key: retired, value: (_, kept)) in _merges.entries) {
        final holders = rows
            .where((r) => strings(r['merged_ids']).contains(retired))
            .map((r) => r['id'])
            .toList();
        expect(holders, [kept], reason: retired);
      }
    });

    test('no row id appears in any merged_ids', () {
      final ids = byId.keys.toSet();
      final clash = rows
          .expand((r) => strings(r['merged_ids']))
          .where(ids.contains)
          .toList();
      expect(clash, isEmpty);
    });

    test('each retired name is an alias of its kept twin and of no other row', () {
      for (final MapEntry(value: (name, kept)) in _merges.entries) {
        final holders = rows
            .where((r) => strings(r['name_aliases'])
                .any((a) => a.toLowerCase() == name.toLowerCase()))
            .map((r) => r['id'])
            .toList();
        expect(holders, [kept], reason: name);
      }
    });

    test('no alias equals another row\'s name', () {
      final names = {for (final r in rows) (r['name'] as String).toLowerCase()};
      final clash = rows
          .expand((r) => strings(r['name_aliases']))
          .where((a) => names.contains(a.toLowerCase()))
          .toList();
      expect(clash, isEmpty);
    });

    test('same-pattern twins carry the retired selection fields', () {
      final e107 = byId['E107']!;
      expect(e107['is_foundational'], isTrue);
      expect(e107['priority_tier'], 2);
      expect(strings(e107['target_focus']), contains('Glutes'));
      expect(strings(e107['primary_muscles']), contains('Glutes'));
      expect(byId['E097']!['priority_tier'], 2);
      expect(byId['E176']!['priority_tier'], 2);
    });

    test('different-pattern twins carry nothing but aliases', () {
      expect(byId['E016']!['movement_pattern'], ['horizontal_push']);
      expect(byId['E216']!['movement_pattern'], ['cooldown']);
      // Selection fields stay exactly as they were before the merge (values
      // read from the pre-merge file, fcbe6840). A wrong samePattern() would
      // hand E219 "Mid Back (Thickness)" and E220 "Biceps" from their twins.
      const before = <String, Map<String, Object>>{
        'E016': {'tf': ['Triceps'], 'pm': ['Triceps'], 'pt': 1, 'f': true},
        'E216': {'tf': ['Quads', 'Legs'], 'pm': ['Quads'], 'pt': 3, 'f': false},
        'E219': {'tf': ['Rear Delts', 'Shoulders'], 'pm': ['Rear Deltoid'], 'pt': 3, 'f': false},
        'E220': {'tf': ['Mid Chest', 'chest'], 'pm': ['Chest'], 'pt': 3, 'f': false},
      };
      for (final entry in before.entries) {
        final row = byId[entry.key]!;
        expect(strings(row['target_focus']), entry.value['tf'], reason: '${entry.key} target_focus');
        expect(strings(row['primary_muscles']), entry.value['pm'], reason: '${entry.key} primary_muscles');
        expect(row['priority_tier'], entry.value['pt'], reason: '${entry.key} priority_tier');
        expect(row['is_foundational'], entry.value['f'], reason: '${entry.key} is_foundational');
      }
    });

    test('injury tags are never merged (founder 13-B carve-out)', () {
      expect(byId['E107']!['injury_contraindications'], isEmpty);
      expect(byId['E176']!['injury_contraindications'], isEmpty);
      expect(byId['E016']!['injury_contraindications'], ['elbow', 'shoulder']);
      expect(byId['E097']!['injury_contraindications'], ['elbow']);
    });
  });
}
