// BEHAVIORAL CONTRACT TEST — workout_schedule_read_path
//
// Concept:   workout_schedule_read_path
// Writer:    lib/core/services/workout_schedule_read_service.dart
//            (via WorkoutScheduleWriteService / WorkoutWriteService.upsertScheduled)
// Reader:    lib/core/services/workout_schedule_read_service.dart
//            (getScheduleForDate, getCurrentWeekNumber)
//
// Assert:
//   1. After a schedule entry is written to Hive for a given date,
//      getScheduleForDate(date) returns a non-null map for that date.
//   2. When plan_start_date is written as today, getCurrentWeekNumber() == 1.
//   3. When plan_start_date is written as 7 days ago, getCurrentWeekNumber() == 2.
//
//   These asserts FAIL if:
//   - The key format for schedule entries changes (schedule_<date> keying drifts).
//   - MigratedKey.write/_planStartKey usage changes so getCurrentWeekNumber can't
//     read plan_start_date.
//   - The week formula drifts from (diff ~/ 7 + 1).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/date_utils.dart' show formatDateKey;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

void main() {
  late Directory tempDir;
  const fakeUserId = 'cccccccc-dddd-eeee-ffff-000000000002';
  // Key that WorkoutScheduleReadService._planStartKey resolves to.
  const planStartKey = 'plan_start_date';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('wsrp_behavioral_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.exerciseBoxName);
    await Hive.openBox(HiveService.foodBoxName);
    await Hive.openBox(HiveService.syncBoxName);
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await HiveUserSession.openForUser(fakeUserId);
  });

  tearDown(() async {
    // Clean up schedule and plan_start entries between tests.
    final box = HiveService.instance.workoutBox;
    final keysToRemove = box.keys
        .where((k) => k.toString().startsWith('schedule_'))
        .toList();
    for (final k in keysToRemove) {
      await box.delete(k);
    }
    // Remove plan_start_date from userBox (MigratedKey writes to userBox
    // when session is open).
    try {
      final userBox = HiveService.instance.userBox;
      await userBox.delete(planStartKey);
    } catch (_) {}
    await HiveUserSession.closeAll();
  });

  // ── Test 1: getScheduleForDate returns entry after upsertScheduled ──────
  test(
    'getScheduleForDate returns non-null after upsertScheduled writes the entry',
    () async {
      final testDate = DateTime(2026, 7, 1);

      // Write a schedule entry via the canonical writer path.
      await WorkoutWriteService.instance.upsertScheduled(
        date: testDate,
        entry: {
          'type': 'workout',
          'date': formatDateKey(testDate),
          'day_of_week': 'Tuesday',
          'status': 'planned',
          'exercises': <Map<String, dynamic>>[],
        },
        source: WriteSource.schedSwap,
      );

      // Read via the canonical reader.
      final result =
          WorkoutScheduleReadService.instance.getScheduleForDate(testDate);

      expect(
        result,
        isNotNull,
        reason:
            'getScheduleForDate must return the entry that was written via '
            'upsertScheduled. Null means the schedule_<dateKey> key format '
            'drifted between writer and reader.',
      );
      expect(
        result!['status'],
        equals('planned'),
        reason: 'status field must round-trip correctly',
      );
    },
  );

  // ── Test 2: getCurrentWeekNumber == 1 when plan started today ───────────
  test(
    'getCurrentWeekNumber returns 1 when plan_start_date is today',
    () async {
      // Write plan_start_date = today via MigratedKey (exactly what
      // generateAndScheduleFromDate does during plan creation).
      final today = DateTime.now();
      final todayStr = formatDateKey(today);
      await MigratedKey.write(planStartKey, todayStr);

      final weekNumber =
          WorkoutScheduleReadService.instance.getCurrentWeekNumber();

      expect(
        weekNumber,
        equals(1),
        reason:
            'getCurrentWeekNumber must be 1 on the plan start day. '
            'If this fails, MigratedKey.write does not match the key that '
            'getCurrentWeekNumber reads via MigratedKey.read, OR the '
            'week formula (diff ~/ 7 + 1) drifted.',
      );
    },
  );

  // ── Test 3: getCurrentWeekNumber == 2 after plan started 7 days ago ─────
  test(
    'getCurrentWeekNumber returns 2 when plan_start_date is 7 days ago',
    () async {
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
      final sevenDaysAgoStr = formatDateKey(sevenDaysAgo);
      await MigratedKey.write(planStartKey, sevenDaysAgoStr);

      final weekNumber =
          WorkoutScheduleReadService.instance.getCurrentWeekNumber();

      expect(
        weekNumber,
        equals(2),
        reason:
            'getCurrentWeekNumber must be 2 when plan started 7 days ago. '
            'The formula (diff ~/ 7 + 1) with diff=7 → 7~//7+1 = 2. '
            'If this returns 1, MigratedKey write/read key mismatch, or '
            'the formula drifted to (diff ~/ 7) (off by one).',
      );
    },
  );

  // ── Test 4: getCurrentWeekNumber returns 1 (not null/crash) with no plan ──
  test(
    'getCurrentWeekNumber returns 1 (default) when plan_start_date is not set',
    () async {
      // No MigratedKey.write call — simulates fresh install / no plan.
      final weekNumber =
          WorkoutScheduleReadService.instance.getCurrentWeekNumber();

      expect(
        weekNumber,
        equals(1),
        reason:
            'getCurrentWeekNumber must default to 1 when plan_start_date '
            'is absent (fresh install safety). If this throws or returns 0, '
            'the null-guard inside getCurrentWeekNumber was removed.',
      );
    },
  );
}
