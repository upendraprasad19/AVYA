// test/contracts/hive_field_name_exlog_writer_to_reader_test.dart
//
// Contract: hive_field_name_exlog
// Writer: WorkoutWriteService (exlog_* rows)
// Readers: WorkoutReceiptData.fromExerciseLogs, WorkoutRepository.getExerciseLogsForDate,
//          AiCoachRepository.buildAiContext, SyncService.syncWorkoutData,
//          EditWorkoutLogSheet.save (rescans is_pr)
//
// Pins every canonical field name so a rename in WorkoutWriteService
// immediately breaks this test. See CLAUDE.md §15 "Hive field-name contract".

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String writeServiceSource;
  late String receiptSource;
  late String syncSource;
  late String aiRepoSource;

  setUpAll(() {
    writeServiceSource =
        File('lib/core/services/workout_write_service.dart').readAsStringSync();
    receiptSource =
        File('lib/features/train/widgets/workout_receipt_card.dart')
            .readAsStringSync();
    syncSource =
        File('lib/core/services/sync_service.dart').readAsStringSync();
    aiRepoSource =
        File('lib/features/ai_coach/repositories/ai_coach_repository.dart')
            .readAsStringSync();
  });

  group('hive_field_name_exlog contract — writer fields', () {
    for (final field in [
      'exercise_name',
      'date',
      'set_number',
      'reps_completed',
      'weight_kg',
      'volume_kg',
      'logging_type',
      'is_pr',
      'source',
      'updated_at_ms',
    ]) {
      test('writer writes field "$field"', () {
        expect(
          writeServiceSource,
          contains("'$field'"),
          reason:
              'WorkoutWriteService must write "$field" field on exlog_* rows; '
              'renaming without updating all readers causes silent data loss.',
        );
      });
    }
  });

  group('hive_field_name_exlog contract — reader field agreement', () {
    test('receipt reader uses set_number as primary (legacy sets_completed fallback only)', () {
      // set_number is canonical since Test #8 WriteService rewrite.
      // sets_completed MAY appear as a backwards-compat fallback read, but
      // set_number must be the primary key checked first.
      expect(
        receiptSource,
        contains('set_number'),
        reason:
            'WorkoutReceiptData must read set_number (canonical); '
            'sets_completed was the pre-Test-#8 name that caused "0 sets" bug.',
      );
      // Verify that set_number appears BEFORE sets_completed in the source
      // (primary key checked first in the fallback chain).
      final setNumberIdx = receiptSource.indexOf('set_number');
      final setsCompletedIdx = receiptSource.indexOf('sets_completed');
      if (setsCompletedIdx != -1) {
        expect(
          setNumberIdx < setsCompletedIdx,
          isTrue,
          reason:
              'set_number must appear before sets_completed in receipt_card.dart '
              '— set_number is the primary key; sets_completed is legacy fallback.',
        );
      }
    });

    test('sync reads exercise_name as exercise_id for cloud upload', () {
      expect(
        syncSource,
        contains('exercise_name'),
        reason:
            'SyncService._syncExerciseLogs must project exercise_name from exlog rows.',
      );
    });

    test('AI repo reads exercise_name from exlog rows', () {
      expect(
        aiRepoSource,
        contains('exercise_name'),
        reason:
            'AiCoachRepository._getPersonalRecords / _getThisWeekWorkouts must '
            'read exercise_name from exlog_* rows (not filter by missing "type" field).',
      );
    });
  });
}
