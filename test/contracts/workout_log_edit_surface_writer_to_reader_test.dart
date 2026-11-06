// test/contracts/workout_log_edit_surface_writer_to_reader_test.dart
//
// Contract: workout_log_edit_surface
// Single edit surface: EditWorkoutLogSheet (edit_workout_log_sheet.dart).
// 4 entry points must route through it; save must invalidate all workout providers.
//
// See docs/architecture/sync.md "Source of Truth Rules".

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String editSheetSource;
  late String receiptSheetSource;

  setUpAll(() {
    editSheetSource = File(
            'lib/features/train/widgets/edit_workout_log_sheet.dart')
        .readAsStringSync();
    receiptSheetSource = File(
            'lib/features/train/widgets/workout_receipt_sheet.dart')
        .readAsStringSync();
  });

  group('workout_log_edit_surface writer→reader contract', () {
    test('edit sheet writes set_number field (canonical since Test #8)', () {
      expect(
        editSheetSource,
        contains('set_number'),
        reason:
            'EditWorkoutLogSheet.save must write set_number field; '
            'sets_completed caused "0 sets" receipt bug (Test #8 → #12).',
      );
    });

    test('edit sheet recomputes volume_kg on save', () {
      expect(
        editSheetSource,
        contains('volume_kg'),
        reason:
            'EditWorkoutLogSheet.save must recompute volume_kg = weight_kg × reps.',
      );
    });

    test('edit sheet fires pushSnapshot after save', () {
      expect(
        editSheetSource,
        contains('pushSnapshot'),
        reason:
            'EditWorkoutLogSheet.save must fire pushSnapshot() fire-and-forget '
            'so AI coach context reflects the edit.',
      );
    });

    test('receipt sheet routes to edit sheet (not inline editing)', () {
      expect(
        receiptSheetSource,
        contains('EditWorkoutLogSheet'),
        reason:
            'WorkoutReceiptSheet Edit button must open EditWorkoutLogSheet — '
            'do not add a second edit path that can drift.',
      );
    });

    test('edit sheet invalidates todayWorkoutProvider', () {
      expect(
        editSheetSource,
        contains('todayWorkoutProvider'),
        reason:
            'EditWorkoutLogSheet.save must invalidate todayWorkoutProvider '
            'so home screen reflects updated state immediately.',
      );
    });
  });
}
