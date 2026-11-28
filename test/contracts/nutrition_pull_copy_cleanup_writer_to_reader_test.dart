// Writer -> reader contract for the SoT concept `nutrition_pull_copy_cleanup`
// (OI-348 Landing 1a-i, diagnose b1d2a8).
//
// WRITER: `SyncService._pullNutritionLogs` (sync_service.dart) puts every cloud
//   `nutrition_logs` row under the row's own `id` (a UUID) as `{...row,
//   'source': row['source'] ?? 'telegram'}`; the row has exactly the columns of
//   the live table (backups/live_schema_columns.json), so no `items`.
// READER: `isNutritionPullCopy` (sync_nutrition.dart), which decides what
//   `_cleanupNutritionPullCopies` deletes.
//
// The contract: a row built from the LIVE column list, exactly as the writer
// builds it, is a copy; every other nutritionBox writer's shape is not. If the
// table gains an `items` or `source` column, or the writer changes its key or
// its source label, this test reddens before the cleanup silently stops
// matching (or starts matching real meals).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

const _uuid = '0b6f0a52-1c2d-4e3f-8a9b-0c1d2e3f4a5b';

List<String> _liveNutritionColumns() {
  final json = jsonDecode(
    File('backups/live_schema_columns.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  // The snapshot nests tables under one top-level key; find the table list.
  List<String>? found;
  void walk(Object? n) {
    if (found != null) return;
    if (n is Map) {
      final v = n['nutrition_logs'];
      if (v is List) {
        found = v.cast<String>();
        return;
      }
      for (final child in n.values) {
        walk(child);
      }
    }
  }

  walk(json);
  expect(found, isNotNull, reason: 'nutrition_logs missing from the snapshot');
  return found!;
}

/// A cloud row with every live column filled, as PostgREST returns it.
Map<String, dynamic> _cloudRow(List<String> columns) => {
      for (final c in columns)
        c: switch (c) {
          'id' => _uuid,
          'user_id' => 'user-1',
          'date' => '2026-11-22',
          'meal_type' => 'lunch',
          'created_at' => '2026-11-22T07:00:00Z',
          _ => 95,
        },
    };

/// The writer's put, byte for byte in shape: key = row id, value = row plus
/// the source label (`sync_service.dart` `_pullNutritionLogs`).
MapEntry<String, Map<String, dynamic>> _writerPut(Map<String, dynamic> row) =>
    MapEntry(row['id'] as String, {...row, 'source': row['source'] ?? 'telegram'});

void main() {
  group('nutrition_pull_copy_cleanup writer -> reader', () {
    test('the live table has no items and no source column (the rule relies on it)', () {
      final columns = _liveNutritionColumns();
      expect(columns, containsAll(['id', 'user_id', 'date', 'meal_type']));
      expect(columns, isNot(contains('items')));
      expect(columns, isNot(contains('source')));
    });

    test('the writer source still keys by the row id and labels the source', () {
      final src = File('lib/core/services/sync_service.dart').readAsStringSync();
      final start = src.indexOf('Future<void> _pullNutritionLogs(');
      expect(start, greaterThan(0));
      final body = src.substring(start, src.indexOf('Future<void> _pullMeasurements(', start));
      expect(body, contains("final id = map['id'] as String? ?? '';"));
      expect(body, contains('await nutritionBox.put(id, {'));
      expect(body, contains('...map,'));
      expect(body, contains("'source': map['source'] ?? 'telegram',"));
    });

    test('what the writer puts, from the live columns, is a pull copy', () {
      final put = _writerPut(_cloudRow(_liveNutritionColumns()));
      expect(isNutritionPullCopy(put.key, put.value), isTrue);
    });

    test("the device's own meal (nlog_ key, items) is not a pull copy", () {
      final own = {
        ..._cloudRow(_liveNutritionColumns()),
        'id': 'nlog_2026-11-22_lunch_0a1b2c3d',
        'items': [
          {'name': 'Apple', 'calories': 95.0},
        ],
      };
      expect(isNutritionPullCopy('nlog_2026-11-22_lunch_0a1b2c3d', own), isFalse);
      // Same value under a UUID key still has items: kept.
      expect(isNutritionPullCopy(_uuid, own), isFalse);
    });

    test('a full-restore row (source cloud_restore) and a saved meal are not pull copies', () {
      final row = _cloudRow(_liveNutritionColumns());
      expect(isNutritionPullCopy(_uuid, {...row, 'source': 'cloud_restore'}), isFalse);
      expect(isNutritionPullCopy(_uuid, {...row, 'is_saved_meal': true}), isFalse);
    });
  });
}
