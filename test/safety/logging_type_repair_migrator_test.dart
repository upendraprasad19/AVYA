// APK Test #12.2 / Task #2b — pins the self-repair migration contract.
//
// Migrator walks every exlog_* row, re-infers logging_type from stored
// data + bundled exercise library, and corrects drift left by pre-Test-#12
// swap state retention.

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/logging_type_repair_migrator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_lt_repair');
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
      HiveService.exerciseBoxName,
      HiveService.configBoxName,
      HiveService.migrationBoxName,
      'workoutBox_aaaaaaaa',
      'exerciseBox_aaaaaaaa',
    ]) {
      if (Hive.isBoxOpen(name)) await Hive.box(name).close();
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    // exerciseBox is shared / bundled-library, not user-scoped — open
    // explicitly here so the migrator can read it.
    await Hive.openBox(HiveService.exerciseBoxName);
    HiveService.instance.markInitializedForTests();

    const fakeUserId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    await HiveUserSession.openForUser(fakeUserId);

    // Seed exercise library entries for the test rows.
    final exb = HiveService.instance.exerciseBox;
    await exb.put('push_up', {
      'name': 'Push Up',
      'logging_type': 'bodyweight_reps',
    });
    await exb.put('handstand_hold', {
      'name': 'Handstand Hold',
      'logging_type': 'timed',
    });
  });

  tearDown(() async {
    await HiveUserSession.closeAll();
  });

  test('corrects timed→bodyweight_reps when row has reps but no duration',
      () async {
    final wb = HiveService.instance.workoutBox;
    const dateStr = '2026-05-06';
    await wb.put('exlog_${dateStr}_-1', {
      'exercise_name': 'Push Up',
      'date': dateStr,
      'logging_type': 'timed', // ← drifted
      'reps_completed': 50,
      'weight_kg': 0.0,
      'duration_seconds': null,
      'sets': [
        {'reps': 25, 'weight_kg': 0},
        {'reps': 25, 'weight_kg': 0},
      ],
    });

    final corrected = await LoggingTypeRepairMigrator.runIfNeeded();
    expect(corrected, 1);

    final updated = wb.get('exlog_${dateStr}_-1') as Map;
    expect(updated['logging_type'], 'bodyweight_reps');
    expect(updated['logging_type_repaired_at_ms'], isNotNull);
  });

  test('corrects weight_reps→timed when row has duration but no weight/reps',
      () async {
    final wb = HiveService.instance.workoutBox;
    const dateStr = '2026-05-06';
    await wb.put('exlog_${dateStr}_-2', {
      'exercise_name': 'Handstand Hold',
      'date': dateStr,
      'logging_type': 'weight_reps', // ← drifted
      'reps_completed': 0,
      'weight_kg': 1.0, // bogus 1kg
      'duration_seconds': 30,
      'sets': [
        {'duration_sec': 15, 'weight_kg': 0, 'reps': 0},
        {'duration_sec': 15, 'weight_kg': 0, 'reps': 0},
      ],
    });

    final corrected = await LoggingTypeRepairMigrator.runIfNeeded();
    expect(corrected, 1);

    final updated = wb.get('exlog_${dateStr}_-2') as Map;
    expect(updated['logging_type'], 'timed');
    expect(updated['weight_kg'], 0.0,
        reason: 'bogus weight should be cleared on timed correction');
  });

  test('leaves correctly-typed rows untouched', () async {
    final wb = HiveService.instance.workoutBox;
    const dateStr = '2026-05-06';
    await wb.put('exlog_${dateStr}_-3', {
      'exercise_name': 'Push Up',
      'date': dateStr,
      'logging_type': 'bodyweight_reps', // ← correct
      'reps_completed': 50,
      'weight_kg': 0.0,
      'sets': [
        {'reps': 25, 'weight_kg': 0},
        {'reps': 25, 'weight_kg': 0},
      ],
    });

    final corrected = await LoggingTypeRepairMigrator.runIfNeeded();
    expect(corrected, 0);

    final updated = wb.get('exlog_${dateStr}_-3') as Map;
    expect(updated['logging_type'], 'bodyweight_reps');
    expect(updated.containsKey('logging_type_repaired_at_ms'), isFalse);
  });

  test('idempotent — second run is a no-op', () async {
    final wb = HiveService.instance.workoutBox;
    const dateStr = '2026-05-06';
    await wb.put('exlog_${dateStr}_-4', {
      'exercise_name': 'Push Up',
      'date': dateStr,
      'logging_type': 'timed',
      'reps_completed': 50,
      'weight_kg': 0.0,
      'sets': [
        {'reps': 25},
        {'reps': 25},
      ],
    });

    final firstRun = await LoggingTypeRepairMigrator.runIfNeeded();
    expect(firstRun, 1);
    expect(LoggingTypeRepairMigrator.hasRun(), isTrue);

    final secondRun = await LoggingTypeRepairMigrator.runIfNeeded();
    expect(secondRun, 0,
        reason: 'flag should short-circuit second invocation');
  });
}
