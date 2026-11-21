// Behavioral regression — Batch 5 crash fix (equipment_needed bare-String):
// `ExerciseData.parseEquipmentNeeded` never crashes on the library's bare-String
// `equipment_needed`, and the library JSON stores it as a List on all 258 rows.
// Before: 9 rows (E252–E260) stored a bare String, and the swap / add-exercise
// picker cast it `as List?` (swap_sheets.dart:28,130) → `_CastError` → crash on
// selecting any of those 9 (Incline Dumbbell Press, Split Squat, Wall Sit, …).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';

void main() {
  group('ExerciseData.parseEquipmentNeeded — shape-tolerant reader (crash fix)', () {
    test('bare String → single-element list (was the _CastError crash)', () {
      // The exact shape the 9 rows stored (E252 "Bodyweight", E260 "Dumbbells").
      expect(ExerciseData.parseEquipmentNeeded('Bodyweight'), ['Bodyweight']);
      expect(ExerciseData.parseEquipmentNeeded('Dumbbells'), ['Dumbbells']);
    });
    test('List → stringified list (the canonical 249/258 shape)', () {
      expect(ExerciseData.parseEquipmentNeeded(['Dumbbells', 'Bench']),
          ['Dumbbells', 'Bench']);
      expect(ExerciseData.parseEquipmentNeeded(<dynamic>['none']), ['none']);
    });
    test('null / empty / non-string / bad type → const [] (never throws)', () {
      expect(ExerciseData.parseEquipmentNeeded(null), isEmpty);
      expect(ExerciseData.parseEquipmentNeeded(''), isEmpty);
      expect(ExerciseData.parseEquipmentNeeded('   '), isEmpty);
      expect(ExerciseData.parseEquipmentNeeded(42), isEmpty);
    });
  });

  group('exercise_library.json — equipment_needed data-quality (source fix)', () {
    test('every row stores equipment_needed as a List (0 bare Strings)', () {
      final file = File('assets/data/exercise_library.json');
      expect(file.existsSync(), isTrue,
          reason: 'run from repo root so the asset path resolves');
      final decoded = jsonDecode(file.readAsStringSync());
      expect(decoded, isA<List>(),
          reason: 'exercise_library.json is a top-level JSON array');
      final rows = decoded as List;
      expect(rows, isNotEmpty);
      final bareString = rows
          .whereType<Map>()
          .where((e) => e['equipment_needed'] is String)
          .map((e) => e['id'] ?? e['name'])
          .toList();
      expect(bareString, isEmpty,
          reason: 'equipment_needed must be a List on every row — a bare String '
              'crashes the swap picker (E252–E260 fixed in seed v6). Offenders: '
              '$bareString');
    });
  });
}
