// test/contracts/hive_field_name_nlog_writer_to_reader_test.dart
//
// Contract: hive_field_name_nlog
// Writer: NutritionWriteService (nlog_* rows)
// Readers: TodaysMealsCard, NutritionRepository, home_provider daily ring,
//          AiCoachRepository.buildAiContext, SyncService.syncNutritionData
//
// Pins every canonical field name so a rename in NutritionWriteService
// immediately breaks this test. See docs/architecture/sync.md "Hive field-name contract".

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import '_sync_service_source.dart';

void main() {
  late String writeServiceSource;
  late String syncSource;
  late String aiRepoSource;

  setUpAll(() {
    writeServiceSource = File(
            'lib/core/services/nutrition_write_service.dart')
        .readAsStringSync();
    syncSource =
        loadSyncServiceSource().readAsStringSync();
    // Tech-debt audit 2026-05-20 A10 — see exlog twin test for full note.
    // AI snapshot reader moved from ai_coach_repository.dart into
    // AiSnapshotBuilder; concat the shim + its 3 new homes.
    aiRepoSource = [
      'lib/features/ai_coach/repositories/ai_coach_repository.dart',
      'lib/features/ai_coach/services/ai_snapshot_builder.dart',
      'lib/features/ai_coach/services/coach_memory_service.dart',
      'lib/features/ai_coach/repositories/coach_interaction_repository.dart',
    ]
        .map((p) =>
            File(p).existsSync() ? File(p).readAsStringSync() : '')
        .join('\n\n');
  });

  group('hive_field_name_nlog contract — writer fields', () {
    for (final field in [
      'log_key',
      'date',
      'meal_type',
      'total_calories',
      'total_protein',
      'total_carbs',
      'total_fat',
      'total_fiber',
      'items',
      'source',
      'logged_at',
    ]) {
      test('writer writes field "$field"', () {
        expect(
          writeServiceSource,
          contains("'$field'"),
          reason:
              'NutritionWriteService must write "$field" field on nlog_* rows; '
              'renaming without updating all readers causes silent data loss.',
        );
      });
    }
  });

  group('hive_field_name_nlog contract — reader field agreement', () {
    test('sync reads total_calories from nlog rows', () {
      expect(
        syncSource,
        contains('total_calories'),
        reason:
            'SyncService._syncNutritionLogs must project total_calories from nlog rows.',
      );
    });

    test('sync reads total_protein from nlog rows', () {
      expect(
        syncSource,
        contains('total_protein'),
        reason:
            'SyncService._syncNutritionLogs must project total_protein from nlog rows.',
      );
    });

    test('AI repo reads meal_type from nlog rows', () {
      expect(
        aiRepoSource,
        contains('meal_type'),
        reason:
            'AiCoachRepository._getMealsToday must read meal_type to group meals. '
            'Must use nlog_ key prefix, not filter by missing "type" field.',
      );
    });

    test('sync iterates nlog_ key prefix (not box.values with type filter)', () {
      // Sync must use key prefix scan, not box.values filtered by a "type" field
      // that nlog rows don't have (that was the Test #8 regression class).
      expect(
        syncSource,
        contains("nlog_"),
        reason:
            'SyncService._syncNutritionLogs must iterate nlog_ prefix keys; '
            'filtering box.values by missing "type" field silently dropped all rows.',
      );
    });

    test('writer uses nlog_ key prefix', () {
      expect(
        writeServiceSource,
        contains("'nlog_"),
        reason: 'NutritionWriteService must write nlog_* Hive keys.',
      );
    });
  });
}
