// APK Test #12.2 / Task #1 — pins the 3rd fallback for sets count.
//
// Pre-Test-#12.2 the train screen + receipt readers took
// MAX(set_number, sets_completed). Cloud audit revealed local rows
// where BOTH are 0/null but `sets[]` (or legacy `sets_detail[]`)
// arrays carry the count. Cloud projection prefers array length, so
// cloud has set_number=4 while local readers showed "0 sets · 26 reps".
//
// New rule: take MAX of FOUR sources — the two top-level fields AND
// the two array lengths. Whichever is highest wins.

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
    tempDir = await Directory.systemTemp.createTemp('test_sets_3rd_fb');
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

  test('Receipt reads sets_detail.length when both top-level counts are 0',
      () async {
    final wb = HiveService.instance.workoutBox;
    const dateStr = '2026-05-06';

    // Pre-Test-#6 row shape: sets_detail array but NO set_number,
    // NO sets_completed top-level. Cloud projection still gets it
    // right via resolvedSets.length, but pre-Test-#12.2 readers
    // returned 0.
    await wb.put('exlog_${dateStr}_-1234', {
      'exercise_name': 'Barbell Bench Press',
      'date': dateStr,
      'sets_detail': [
        {'set_number': 1, 'weight_kg': 80, 'reps': 8},
        {'set_number': 2, 'weight_kg': 80, 'reps': 8},
        {'set_number': 3, 'weight_kg': 85, 'reps': 6},
        {'set_number': 4, 'weight_kg': 85, 'reps': 4},
      ],
      'reps_completed': 26,
      'weight_kg': 85.0,
      'logging_type': 'weight_reps',
      // NB: NO set_number, NO sets_completed
    });
    await wb.put('exercise_log_index_$dateStr', ['exlog_${dateStr}_-1234']);

    final receipt = WorkoutReceiptData.fromExerciseLogs(DateTime(2026, 5, 6));
    expect(receipt, isNotNull);
    expect(receipt!.exercises.length, 1);
    expect(receipt.exercises.first.sets, 4,
        reason: '3rd fallback to sets_detail.length must yield 4, not 0');
  });

  test('Receipt reads sets[] length when sets_detail is absent', () async {
    final wb = HiveService.instance.workoutBox;
    const dateStr = '2026-05-06';

    // WriteService-shape row but with set_number missing/zero (edge
    // case after editLog merge that didn't recompute aggregates).
    await wb.put('exlog_${dateStr}_-9999', {
      'exercise_name': 'Lat Pulldown',
      'date': dateStr,
      'sets': [
        {'weight_kg': 100, 'reps': 8},
        {'weight_kg': 110, 'reps': 8},
        {'weight_kg': 110, 'reps': 8},
      ],
      'set_number': 0, // explicit zero
      'reps_completed': 24,
      'weight_kg': 110.0,
      'logging_type': 'weight_reps',
    });
    await wb.put('exercise_log_index_$dateStr', ['exlog_${dateStr}_-9999']);

    final receipt = WorkoutReceiptData.fromExerciseLogs(DateTime(2026, 5, 6));
    expect(receipt, isNotNull);
    expect(receipt!.exercises.first.sets, 3,
        reason: 'When set_number=0 but sets[] has 3 entries, 3rd fallback wins');
  });

  test('Receipt prefers highest non-zero count among all sources',
      () async {
    final wb = HiveService.instance.workoutBox;
    const dateStr = '2026-05-06';

    // Edge case: set_number=2, sets_completed=4, sets[].length=3.
    // The MAX is 4. (Some legacy rows had drift like this from
    // partial edit_workout_log_sheet writes.)
    await wb.put('exlog_${dateStr}_-5555', {
      'exercise_name': 'Squat',
      'date': dateStr,
      'set_number': 2,
      'sets_completed': 4,
      'sets': [
        {'weight_kg': 100, 'reps': 5},
        {'weight_kg': 100, 'reps': 5},
        {'weight_kg': 100, 'reps': 5},
      ],
      'reps_completed': 20,
      'weight_kg': 100.0,
      'logging_type': 'weight_reps',
    });
    await wb.put('exercise_log_index_$dateStr', ['exlog_${dateStr}_-5555']);

    final receipt = WorkoutReceiptData.fromExerciseLogs(DateTime(2026, 5, 6));
    expect(receipt, isNotNull);
    expect(receipt!.exercises.first.sets, 4,
        reason: 'MAX(2, 4, 3, 0) = 4');
  });
}
