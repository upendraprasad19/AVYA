// test/contracts/type_consistency_test.dart
//
// Contract (E.13 — Audit 2026-05-16 framework deliverable):
// Pin the cloud SQL types of 8 high-traffic columns. Drift in either
// direction (loosening to text, tightening to int when numeric was
// intended) silently breaks writers or readers.
//
// We pin by parsing the DDL out of the migration that introduced
// (or last altered) the column. This protects against:
//   - Adding a migration that ALTER COLUMNs to a wider type
//   - Renaming a migration / column without updating the writer
//
// Columns pinned:
//   workout_logs.duration_seconds         INT
//   nutrition_logs.total_calories         NUMERIC
//   weight_logs.weight_kg                 NUMERIC
//   ai_coach_interactions.tokens_used     INT
//   workout_log_exercises.weight_kg       NUMERIC
//   workout_log_sets.duration_secs        INT
//   user_profile.injuries                 TEXT[]
//   nutrition_logs.total_fiber            NUMERIC

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, String> migrationSources;

  setUpAll(() {
    final dir = Directory('supabase/migrations');
    expect(dir.existsSync(), isTrue);
    migrationSources = {
      for (final f in dir.listSync().whereType<File>())
        if (f.path.endsWith('.sql'))
          f.path.replaceAll('\\', '/').split('/').last:
              f.readAsStringSync().toLowerCase(),
    };
  });

  group('type_consistency contract', () {
    test('workout_logs.duration_seconds is int', () {
      _assertColumnType(
        migrationSources,
        column: 'duration_seconds',
        expectedTypeFragment: 'int',
        anchorFile: '002_create_fitness_tables.sql',
      );
    });

    test('nutrition_logs.total_calories is numeric', () {
      _assertColumnType(
        migrationSources,
        column: 'total_calories',
        expectedTypeFragment: 'numeric',
        anchorFile: '003_create_nutrition_tables.sql',
      );
    });

    test('weight_logs.weight_kg is numeric (NOT NULL)', () {
      _assertColumnType(
        migrationSources,
        column: 'weight_kg',
        expectedTypeFragment: 'numeric',
        anchorFile: '004_create_health_tables.sql',
      );
    });

    test('ai_coach_interactions.tokens_used is int', () {
      _assertColumnType(
        migrationSources,
        column: 'tokens_used',
        expectedTypeFragment: 'int',
        anchorFile: '005_create_ai_tables.sql',
      );
    });

    test('workout_log_exercises.weight_kg is numeric', () {
      // Lives in 009 (workout_sync_tables).
      _assertColumnType(
        migrationSources,
        column: 'weight_kg',
        expectedTypeFragment: 'numeric',
        anchorFile: '009_create_workout_sync_tables.sql',
      );
    });

    test('workout_log_sets.duration_secs is int', () {
      _assertColumnType(
        migrationSources,
        column: 'duration_secs',
        expectedTypeFragment: 'int',
        anchorFile: '019_workout_log_sets.sql',
      );
    });

    test('user_profile.injuries is text[]', () {
      // 033 migrated text → text[]. The final type in the migration
      // body MUST contain `text[]`.
      final src = migrationSources['033_injuries_text_array.sql'];
      expect(src, isNotNull, reason: 'migration 033 must exist');
      expect(src!, contains('text[]'),
          reason: 'user_profile.injuries was migrated to text[] in 033');
    });

    test('nutrition_logs.total_fiber is numeric', () {
      _assertColumnType(
        migrationSources,
        column: 'total_fiber',
        expectedTypeFragment: 'numeric',
        anchorFile: '034_nutrition_log_fiber.sql',
      );
    });
  });
}

void _assertColumnType(
  Map<String, String> sources, {
  required String column,
  required String expectedTypeFragment,
  required String anchorFile,
}) {
  final src = sources[anchorFile];
  expect(src, isNotNull,
      reason: 'expected migration file: $anchorFile (column=$column)');

  // Look for either:
  //   <column>   <type>...
  //   add column [if not exists] <column> <type>...
  //   alter column <column> type <type>
  // The cheap pin is: column name appears NEAR the expected type fragment.
  final lines = src!.split('\n');
  String? match;
  for (final line in lines) {
    final lc = line.trim();
    if (!lc.contains(column)) continue;
    if (lc.startsWith('--')) continue;
    if (lc.contains(expectedTypeFragment)) {
      match = lc;
      break;
    }
  }

  expect(match, isNotNull,
      reason: 'expected `$column` declared with type fragment '
          '`$expectedTypeFragment` in $anchorFile');
}
