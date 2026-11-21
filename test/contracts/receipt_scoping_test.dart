// APK Test #12 / Task A-2 + A-3 — pins the receipt scoping contract.
//
// Pre-Test-#12 `WorkoutReceiptData.fromExerciseLogs(date)` aggregated
// every exlog logged on that IST date — even when the user had multiple
// workout sessions on the day. Founder feedback 2026-05-06: "May 4
// receipt shows back exercises but I only did leg day."
//
// Test #12:
//   - WorkoutWriteService.logExercise stamps a `workout_log_id` field
//     on every exlog row (default `wlogKey(date)`).
//   - WorkoutReceiptData.fromExerciseLogs accepts an optional
//     `workoutLogId` arg; rows with a different id are skipped, while
//     legacy rows without the field always pass through.

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/train/widgets/workout_receipt_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_receipt_scope');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    for (final name in [
      HiveService.workoutBoxName,
      HiveService.configBoxName,
      HiveService.migrationBoxName,
      'workoutBox_aaaaaaaa',
    ]) {
      if (Hive.isBoxOpen(name)) await Hive.box(name).close();
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.instance.markInitializedForTests();

    const fakeUserId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    await HiveUserSession.openForUser(fakeUserId);
  });

  tearDown(() async {
    await HiveUserSession.closeAll();
  });

  test('receipt with workoutLogId filters out other sessions', () async {
    final wb = HiveService.instance.workoutBox;
    const dateStr = '2026-05-04';

    // Session 1 (leg day) — exercises stamped with one workout_log_id.
    await wb.put('exlog_${dateStr}_1', {
      'exercise_name': 'Squat',
      'date': dateStr,
      'workout_log_id': 'wlog_2026-05-04_session1',
      'sets': [
        {'weight_kg': 100, 'reps': 5},
      ],
      'set_number': 1,
      'reps_completed': 5,
      'weight_kg': 100,
      'volume_kg': 500,
      'logging_type': 'weight_reps',
    });
    // Session 2 (back day) — different id.
    await wb.put('exlog_${dateStr}_2', {
      'exercise_name': 'Lat Pulldown',
      'date': dateStr,
      'workout_log_id': 'wlog_2026-05-04_session2',
      'sets': [
        {'weight_kg': 60, 'reps': 10},
      ],
      'set_number': 1,
      'reps_completed': 10,
      'weight_kg': 60,
      'volume_kg': 600,
      'logging_type': 'weight_reps',
    });
    await wb.put('exercise_log_index_$dateStr', [
      'exlog_${dateStr}_1',
      'exlog_${dateStr}_2',
    ]);

    // Receipt scoped to session 1 — should ONLY see Squat.
    final scoped = WorkoutReceiptData.fromExerciseLogs(
      DateTime(2026, 5, 4),
      workoutLogId: 'wlog_2026-05-04_session1',
    );
    expect(scoped, isNotNull);
    expect(scoped!.exercises.length, 1);
    expect(scoped.exercises.first.name, 'Squat');

    // Unscoped — sees both (legacy behavior preserved).
    final unscoped =
        WorkoutReceiptData.fromExerciseLogs(DateTime(2026, 5, 4));
    expect(unscoped, isNotNull);
    expect(unscoped!.exercises.length, 2);
  });

  test('legacy exlogs without workout_log_id always pass through', () async {
    final wb = HiveService.instance.workoutBox;
    const dateStr = '2026-05-04';

    // Legacy row — NO workout_log_id field.
    await wb.put('exlog_${dateStr}_legacy', {
      'exercise_name': 'Bench Press',
      'date': dateStr,
      'sets': [
        {'weight_kg': 80, 'reps': 8},
      ],
      'set_number': 1,
      'reps_completed': 8,
      'weight_kg': 80,
      'volume_kg': 640,
      'logging_type': 'weight_reps',
    });
    await wb.put('exercise_log_index_$dateStr', [
      'exlog_${dateStr}_legacy',
    ]);

    // Even with a scope filter, legacy rows must pass — otherwise the
    // upgrade from APK 11.x to APK 12.x would suddenly hide a user's
    // historical receipts.
    final scoped = WorkoutReceiptData.fromExerciseLogs(
      DateTime(2026, 5, 4),
      workoutLogId: 'wlog_2026-05-04_anything',
    );
    expect(scoped, isNotNull);
    expect(scoped!.exercises.length, 1);
    expect(scoped.exercises.first.name, 'Bench Press');
  });

  test('sessionLabel populates only when multi-session day', () async {
    final wb = HiveService.instance.workoutBox;
    const dateStr = '2026-05-04';

    // 2 distinct sessions.
    await wb.put('exlog_${dateStr}_a', {
      'exercise_name': 'Squat',
      'date': dateStr,
      'workout_log_id': 'wlog_a',
      'updated_at_ms': 1000,
      'sets': [
        {'weight_kg': 100, 'reps': 5},
      ],
      'set_number': 1,
      'reps_completed': 5,
      'weight_kg': 100,
      'volume_kg': 500,
      'logging_type': 'weight_reps',
    });
    await wb.put('exlog_${dateStr}_b', {
      'exercise_name': 'Bench',
      'date': dateStr,
      'workout_log_id': 'wlog_b',
      'updated_at_ms': 2000, // chronologically second
      'sets': [
        {'weight_kg': 80, 'reps': 8},
      ],
      'set_number': 1,
      'reps_completed': 8,
      'weight_kg': 80,
      'volume_kg': 640,
      'logging_type': 'weight_reps',
    });
    await wb.put('exercise_log_index_$dateStr', [
      'exlog_${dateStr}_a',
      'exlog_${dateStr}_b',
    ]);

    final session1 = WorkoutReceiptData.fromExerciseLogs(
      DateTime(2026, 5, 4),
      workoutLogId: 'wlog_a',
    );
    expect(session1!.sessionLabel, 'SESSION 1');

    final session2 = WorkoutReceiptData.fromExerciseLogs(
      DateTime(2026, 5, 4),
      workoutLogId: 'wlog_b',
    );
    expect(session2!.sessionLabel, 'SESSION 2');

    // No scoping → no session label (header stays clean).
    final unscoped =
        WorkoutReceiptData.fromExerciseLogs(DateTime(2026, 5, 4));
    expect(unscoped!.sessionLabel, isNull);
  });
}
