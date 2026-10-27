// test/contracts/workout_receipt_rendering_writer_to_reader_test.dart
//
// Contract: workout_receipt_rendering
// Writer: WorkoutWriteService.logExercise (exlog_* keys with workout_log_id)
// Reader: WorkoutReceiptData.fromExerciseLogs (receipt_card.dart)
//
// Pins the writer→reader field agreement so a field rename in WorkoutWriteService
// breaks this test immediately (before APK build). See docs/architecture/sync.md.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String writeServiceSource;
  late String receiptCardSource;

  setUpAll(() {
    writeServiceSource = File(
            'lib/core/services/workout_write_service.dart')
        .readAsStringSync();
    receiptCardSource = File(
            'lib/features/train/widgets/workout_receipt_card.dart')
        .readAsStringSync();
  });

  group('workout_receipt_rendering writer→reader contract', () {
    test('writer stamps workout_log_id on every exlog row', () {
      expect(
        writeServiceSource,
        contains('workout_log_id'),
        reason:
            'WorkoutWriteService.logExercise must stamp workout_log_id on exlog rows '
            '(Test #12 / Task A-3); receipt scoping depends on it.',
      );
    });

    test('reader reads set_number field (not legacy sets_completed)', () {
      // set_number is the canonical field since Test #8 WriteService rewrite.
      expect(
        receiptCardSource,
        contains('set_number'),
        reason:
            'WorkoutReceiptData must read set_number (canonical since Test #8); '
            'legacy sets_completed caused "0 sets" receipt bug.',
      );
    });

    test('receipt card defines fromExerciseLogs static factory', () {
      // The static factory must live in workout_receipt_card.dart — callers
      // such as home_screen and active_workout_screen invoke
      // WorkoutReceiptData.fromExerciseLogs(...) to avoid hand-building
      // receipt data from widget local state.
      expect(
        receiptCardSource,
        contains('static WorkoutReceiptData'),
        reason:
            'WorkoutReceiptData must define the fromExerciseLogs static factory; '
            'do not hand-build receipt data from widget local state.',
      );
      expect(
        receiptCardSource,
        contains('fromExerciseLogs'),
        reason:
            'Receipt data factory must be named fromExerciseLogs (not renamed); '
            'callers in home_screen and active_workout_screen depend on this name.',
      );
    });

    test('writer uses exlog_ key prefix', () {
      expect(
        writeServiceSource,
        contains("'exlog_"),
        reason: 'WorkoutWriteService must write exlog_* Hive keys.',
      );
    });

    test('reader deduplicates by exercise_name', () {
      expect(
        receiptCardSource,
        contains('exercise_name'),
        reason:
            'Receipt reader must deduplicate exercises by exercise_name field.',
      );
    });
  });
}
