// APK Test #16.1 / Agent A — defence-in-depth fallback for the
// receipt builder.
//
// Founder reported on May 14 2026 (+24 APK) that the home weekly-
// calendar "View Card" button did nothing for today + yesterday.
// Root cause was the rogue `_restoreExerciseLogs` writer using a
// UTC-substring date to compose the index key
// (`exercise_log_index_<utc-date>`) while the receipt reader looks up
// `exercise_log_index_<ist-date>`. After 18:30 IST the two disagree,
// so the index lookup returned null → `fromExerciseLogs` returned
// null → `onViewCard: null` → button no-op.
//
// The forward fix is the rogue-writer rewrite (Agent A change-1) +
// migrator v8 bump. This test pins the BACKSTOP fallback in
// `WorkoutReceiptData.fromExerciseLogs`: when the IST-date index is
// empty/missing, it scans all `exlog_*` rows and synthesises the id
// list from any row whose stored `date` field matches dateKey.
//
// Without the fallback, View Card would silently no-op for the
// window between rogue-write and the next-launch migration.

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
    tempDir = await Directory.systemTemp.createTemp('test_receipt_fallback');
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

  test('fromExerciseLogs returns data when index is missing but exlog_* rows '
      'carry the matching date', () async {
    final wb = HiveService.instance.workoutBox;
    // Pick a date where formatDateKey returns a known IST string.
    // 2026-05-14 12:00 IST → istDateStr = '2026-05-14'.
    final date = DateTime.utc(2026, 5, 14, 6, 30);
    const dateKey = '2026-05-14';

    // Seed two exlog rows with arbitrary key shapes — the canonical
    // key formula is irrelevant to the fallback; what matters is the
    // stored `date` field matching the dateKey.
    await wb.put('exlog_arbitrary_one', {
      'exercise_name': 'Bench Press',
      'date': dateKey,
      'set_number': 3,
      'reps_completed': 24,
      'weight_kg': 80.0,
      'logging_type': 'weight_reps',
      'sets': [
        {'weight_kg': 80.0, 'reps': 8},
        {'weight_kg': 80.0, 'reps': 8},
        {'weight_kg': 80.0, 'reps': 8},
      ],
    });
    await wb.put('exlog_arbitrary_two', {
      'exercise_name': 'Squat',
      'date': dateKey,
      'set_number': 5,
      'reps_completed': 25,
      'weight_kg': 100.0,
      'logging_type': 'weight_reps',
      'sets': [
        {'weight_kg': 100.0, 'reps': 5},
        {'weight_kg': 100.0, 'reps': 5},
        {'weight_kg': 100.0, 'reps': 5},
        {'weight_kg': 100.0, 'reps': 5},
        {'weight_kg': 100.0, 'reps': 5},
      ],
    });

    // NO `exercise_log_index_2026-05-14` set — simulates rogue writer
    // having indexed under a different (UTC) date key.

    final receipt = WorkoutReceiptData.fromExerciseLogs(date);
    expect(receipt, isNotNull,
        reason: 'fallback must surface rows when index is missing');
    expect(receipt!.exercises.length, 2);
    expect(receipt.exercises.map((e) => e.name).toSet(),
        {'Bench Press', 'Squat'});
  });

  test('fromExerciseLogs prefers index when present (no scan)', () async {
    // The fallback only fires when the index is missing/empty. When
    // the index is present, the existing fast path runs unchanged.
    final wb = HiveService.instance.workoutBox;
    final date = DateTime.utc(2026, 5, 14, 6, 30);
    const dateKey = '2026-05-14';

    await wb.put('exlog_in_index', {
      'exercise_name': 'Bench Press',
      'date': dateKey,
      'set_number': 1,
      'reps_completed': 5,
      'weight_kg': 100.0,
      'logging_type': 'weight_reps',
    });
    await wb.put('exlog_orphan_no_index', {
      'exercise_name': 'Squat',
      'date': dateKey,
      'set_number': 1,
      'reps_completed': 5,
      'weight_kg': 100.0,
      'logging_type': 'weight_reps',
    });
    await wb.put('exercise_log_index_$dateKey', ['exlog_in_index']);

    final receipt = WorkoutReceiptData.fromExerciseLogs(date);
    expect(receipt, isNotNull);
    // Only the indexed row surfaces — the orphan is invisible per the
    // existing index-driven contract.
    expect(receipt!.exercises.length, 1);
    expect(receipt.exercises.single.name, 'Bench Press');
  });

  test('fromExerciseLogs returns null when neither index nor matching '
      'exlog_* rows exist', () async {
    final wb = HiveService.instance.workoutBox;
    final date = DateTime.utc(2026, 5, 14, 6, 30);
    // Seed a row for a DIFFERENT date.
    await wb.put('exlog_other_date', {
      'exercise_name': 'Bench Press',
      'date': '2026-05-13',
      'set_number': 1,
    });
    expect(WorkoutReceiptData.fromExerciseLogs(date), isNull);
  });
}
