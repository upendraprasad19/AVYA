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
    await exb.put('jump_rope', {
      'name': 'Jump Rope',
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

  test('library-strict v2 — Jump Rope reps→duration migration', () async {
    // APK Test #12.4 — pins the regression fix. v1 (Test #12.2) flipped
    // Jump Rope from `timed` to `bodyweight_reps` because data had reps
    // but no duration (corrupt swap-state retention). v2 must trust the
    // library and MIGRATE the data: move reps→duration, keep type=timed.
    final wb = HiveService.instance.workoutBox;
    const dateStr = '2026-05-06';
    await wb.put('exlog_${dateStr}_jr', {
      'exercise_name': 'Jump Rope',
      'date': dateStr,
      'logging_type': 'timed', // already correctly typed
      'reps_completed': 1080, // bug — should be in duration
      'weight_kg': 0.0,
      'duration_seconds': null,
      'sets': [
        {'reps': 540, 'weight_kg': 0},
        {'reps': 540, 'weight_kg': 0},
      ],
    });

    final corrected = await LoggingTypeRepairMigrator.runIfNeeded();
    expect(corrected, 1);

    final updated = wb.get('exlog_${dateStr}_jr') as Map;
    expect(updated['logging_type'], 'timed',
        reason: 'library says timed; type stays timed');
    expect(updated['duration_seconds'], 1080,
        reason: 'top-level reps must move to duration_seconds');
    expect(updated['reps_completed'], 0,
        reason: 'reps cleared after move');

    // Per-set entries also migrated.
    final sets = updated['sets'] as List;
    expect((sets[0] as Map)['duration_sec'], 540);
    expect((sets[0] as Map)['reps'], 0);
    expect((sets[1] as Map)['duration_sec'], 540);
  });

  test('library-strict v3 — bodyweight_reps per-set duration_sec stripped',
      () async {
    // APK Test #12.5 / Class 5 — pin v3 fix. Founder install of APK
    // 12.4 surfaced: top-level `logging_type` was correctly flipped to
    // `bodyweight_reps` for Push Up + Hanging Leg Raise, but per-set
    // entries still carried `duration_sec` values from the original
    // corrupt write. WardSetChips continued rendering "18 secs"
    // because the chip pulls per-set `duration_sec` directly.
    //
    // v3 must walk per-set arrays (`sets[]` + `sets_detail[]`) and
    // migrate `duration_sec` → `reps` (when reps==0) or simply strip
    // it (when reps already present).
    final wb = HiveService.instance.workoutBox;
    const dateStr = '2026-05-06';
    await wb.put('exlog_${dateStr}_pu', {
      'exercise_name': 'Push Up',
      'date': dateStr,
      'logging_type': 'timed', // wrong type stamped at write time
      'reps_completed': 0, // already corrupted top-level
      'weight_kg': 0.0,
      'duration_seconds': 18,
      'sets': [
        // Per-set entries the v2 migrator would have left alone.
        {'duration_sec': 18, 'weight_kg': 0, 'reps': 0},
        {'duration_sec': 18, 'weight_kg': 0, 'reps': 0},
      ],
      'sets_detail': [
        {'duration_sec': 18, 'weight_kg': 0, 'reps': 0},
        {'duration_sec': 18, 'weight_kg': 0, 'reps': 0},
      ],
    });

    final corrected = await LoggingTypeRepairMigrator.runIfNeeded();
    expect(corrected, 1);

    final updated = wb.get('exlog_${dateStr}_pu') as Map;
    expect(updated['logging_type'], 'bodyweight_reps',
        reason: 'top-level type flipped to library value');
    expect(updated['reps_completed'], 18,
        reason: 'top-level duration → reps migration (v2 worked here)');

    // Per-set entries are the v3 contribution.
    final sets = updated['sets'] as List;
    expect(sets, hasLength(2));
    for (final s in sets) {
      final m = s as Map;
      expect(m.containsKey('duration_sec'), isFalse,
          reason: 'per-set duration_sec must be removed');
      expect(m.containsKey('duration_seconds'), isFalse);
      expect(m['reps'], 18,
          reason: 'per-set duration_sec → reps when reps was 0');
    }

    final setsDetail = updated['sets_detail'] as List;
    expect(setsDetail, hasLength(2));
    for (final s in setsDetail) {
      final m = s as Map;
      expect(m.containsKey('duration_sec'), isFalse);
      expect(m['reps'], 18);
    }
  });

  test('library-strict v2 — Handstand Hold weight=0 cleared', () async {
    // Founder's data had Handstand Hold tagged weight_reps with weight=1
    // (bogus). Library says timed. Migration must flip type AND clear
    // the bogus weight.
    final wb = HiveService.instance.workoutBox;
    const dateStr = '2026-05-06';
    await wb.put('exlog_${dateStr}_hh', {
      'exercise_name': 'Handstand Hold',
      'date': dateStr,
      'logging_type': 'weight_reps',
      'reps_completed': 3,
      'weight_kg': 1.0, // bogus
      'duration_seconds': null,
    });

    final corrected = await LoggingTypeRepairMigrator.runIfNeeded();
    expect(corrected, 1);

    final updated = wb.get('exlog_${dateStr}_hh') as Map;
    expect(updated['logging_type'], 'timed');
    expect(updated['weight_kg'], 0.0,
        reason: 'bogus weight must be cleared');
    // The 3 reps should have moved to duration since library says timed.
    expect(updated['duration_seconds'], 3);
    expect(updated['reps_completed'], 0);
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

  test('library-strict v4 — large per-set duration NOT moved to reps (wls guard)',
      () async {
    // d9a4f2 — a bodyweight_reps row carrying a LARGE duration (a mis-classified
    // timed hold) must NOT have that duration moved into reps: doing so produced
    // per-set reps > 1000 that violated wls_reps_realistic (23514) and were
    // silently dropped. The migrator strips the duration without fabricating a
    // huge rep count; small durations (<= _kMaxPlausibleReps) still migrate (v3).
    final wb = HiveService.instance.workoutBox;
    const dateStr = '2026-05-06';
    await wb.put('exlog_${dateStr}_big', {
      'exercise_name': 'Push Up',
      'date': dateStr,
      'logging_type': 'timed',
      'reps_completed': 0,
      'weight_kg': 0.0,
      'duration_seconds': 1200, // 1200s — implausible as reps
      'sets': [
        {'duration_sec': 1200, 'weight_kg': 0, 'reps': 0},
      ],
      'sets_detail': [
        {'duration_sec': 1200, 'weight_kg': 0, 'reps': 0},
      ],
    });

    final corrected = await LoggingTypeRepairMigrator.runIfNeeded();
    expect(corrected, 1);

    final updated = wb.get('exlog_${dateStr}_big') as Map;
    expect(updated['logging_type'], 'bodyweight_reps');
    // The large duration must NOT become a rep count.
    expect(updated['reps_completed'], 0,
        reason: '1200 is implausible as reps — must not be moved into reps');
    expect(updated.containsKey('duration_seconds'), isFalse,
        reason: 'duration stripped (no mixed signal on a bodyweight row)');

    for (final s in (updated['sets'] as List)) {
      final m = s as Map;
      expect(m['reps'], 0, reason: 'large per-set duration not moved to reps');
      expect(m.containsKey('duration_sec'), isFalse);
    }
    for (final s in (updated['sets_detail'] as List)) {
      final m = s as Map;
      expect(m['reps'], 0);
      expect(m.containsKey('duration_sec'), isFalse);
    }
  });
}
