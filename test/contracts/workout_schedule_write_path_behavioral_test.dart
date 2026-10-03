// BEHAVIORAL CONTRACT TEST — workout_schedule_write_path
//
// Concept:   workout_schedule_write_path
// Writer:    lib/core/services/workout_schedule_write_service.dart
//            (markCompleted, markSkipped)
// Reader:    Hive read-back via WorkoutScheduleReadService.getScheduleForDate
//
// Assert:
//   1. markCompleted(date) writes status='completed' and completed_at is non-null.
//   2. markSkipped(date) writes status='skipped'.
//   3. Neither method modifies Hive if no schedule entry exists for that date
//      (no-op / does not crash).
//
//   These asserts FAIL if:
//   - The schedule_<dateKey> key formula used by markCompleted/markSkipped
//     drifts from the key formula used by upsertScheduled (writer→writer drift).
//   - The 'status' field name changes.
//   - getScheduleForDate's key lookup drifts from the writer's key.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_write_service.dart';
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
  const fakeUserId = 'dddddddd-eeee-ffff-0000-000000000003';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('wswp_behavioral_');
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
    // Clean up schedule entries between tests.
    final box = HiveService.instance.workoutBox;
    final keysToRemove = box.keys
        .where((k) => k.toString().startsWith('schedule_'))
        .toList();
    for (final k in keysToRemove) {
      await box.delete(k);
    }
    await HiveUserSession.closeAll();
  });

  // Helper: write a 'planned' schedule entry for [date].
  Future<void> _seedPlannedEntry(DateTime date) async {
    await WorkoutWriteService.instance.upsertScheduled(
      date: date,
      entry: {
        'type': 'workout',
        'date': formatDateKey(date),
        'day_of_week': 'Monday',
        'status': 'planned',
        'exercises': <Map<String, dynamic>>[],
      },
      source: WriteSource.schedSwap,
    );
  }

  // ── Test 1: markCompleted writes status='completed' ─────────────────────
  test(
    'markCompleted writes status=completed and completed_at to Hive',
    () async {
      // Use a past date so completed_at (= DateTime.now()) is NOT earlier than
      // the entry date — getScheduleForDate resets status to 'planned' when
      // completedDateStr < requestedDateStr (stale-completion guard).
      final date = DateTime(2026, 6, 1); // Monday (past)
      await _seedPlannedEntry(date);

      // Call the canonical writer.
      await WorkoutScheduleWriteService.instance.markCompleted(date);

      // Read back via the canonical reader.
      final result =
          WorkoutScheduleReadService.instance.getScheduleForDate(date);

      expect(
        result,
        isNotNull,
        reason:
            'getScheduleForDate must find the entry after markCompleted. '
            'Key format drift between upsertScheduled and getScheduleForDate '
            'would cause null here.',
      );
      expect(
        result!['status'],
        equals('completed'),
        reason:
            'markCompleted must write status=completed. '
            'If this returns "planned", the field name or the upsertScheduled '
            'call inside markCompleted is not updating the Hive row.',
      );
      expect(
        result['completed_at'],
        isNotNull,
        reason:
            'markCompleted must stamp completed_at. '
            'Null here means the timestamp write was removed from the writer.',
      );
    },
  );

  // ── Test 2: markSkipped writes status='skipped' ──────────────────────────
  test(
    'markSkipped writes status=skipped to Hive',
    () async {
      // Past date — markSkipped does not stamp completed_at, but use a past
      // date for consistency with test 1.
      final date = DateTime(2026, 6, 2); // Tuesday (past)
      await _seedPlannedEntry(date);

      await WorkoutScheduleWriteService.instance.markSkipped(date);

      final result =
          WorkoutScheduleReadService.instance.getScheduleForDate(date);

      expect(
        result,
        isNotNull,
        reason: 'getScheduleForDate must find the entry after markSkipped.',
      );
      expect(
        result!['status'],
        equals('skipped'),
        reason:
            'markSkipped must write status=skipped. '
            'If this is still "planned", the status mutation inside markSkipped '
            'is not being persisted via upsertScheduled.',
      );
    },
  );

  // ── Test 3: markCompleted is a no-op when no entry exists ───────────────
  test(
    'markCompleted is a no-op and does not crash when no schedule entry exists',
    () async {
      final emptyDate = DateTime(2026, 8, 1);
      // No seed — intentionally absent.

      // Should not throw.
      await expectLater(
        WorkoutScheduleWriteService.instance.markCompleted(emptyDate),
        completes,
        reason:
            'markCompleted must be a no-op (not throw) when the schedule '
            'entry for the date does not exist.',
      );

      final result =
          WorkoutScheduleReadService.instance.getScheduleForDate(emptyDate);
      expect(
        result,
        isNull,
        reason:
            'After markCompleted on a non-existent date, Hive must remain empty. '
            'If this is non-null, markCompleted is creating phantom entries.',
      );
    },
  );

  // ── Test 4: markSkipped is a no-op when no entry exists ─────────────────
  test(
    'markSkipped is a no-op and does not crash when no schedule entry exists',
    () async {
      final emptyDate = DateTime(2026, 8, 2);

      await expectLater(
        WorkoutScheduleWriteService.instance.markSkipped(emptyDate),
        completes,
        reason:
            'markSkipped must be a no-op (not throw) when no schedule '
            'entry exists for the date.',
      );

      final result =
          WorkoutScheduleReadService.instance.getScheduleForDate(emptyDate);
      expect(
        result,
        isNull,
        reason: 'After markSkipped on a non-existent date, Hive must be empty.',
      );
    },
  );
}
