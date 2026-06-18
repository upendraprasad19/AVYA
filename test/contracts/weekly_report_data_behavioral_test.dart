// BEHAVIORAL contract for weekly_report_data:
//
// Writer: WorkoutWriteService.markCompleted writes wlog_<istDateStr> keys
//         to workoutBox (logExercise writes exlog_* keys but NOT wlog_*).
// Reader: WeeklyReportDataNotifier.build() reads wlog_* keys and counts
//         unique workout dates.
//
// Contracts verified:
//  1. After marking 3 workouts complete on distinct dates within the current
//     7-day IST window, weeklyReportDataProvider.workouts has exactly 3
//     non-zero entries (one per distinct date).
//  2. Two completions on the SAME date count as 1 (dedup by date — the
//     second markCompleted overwrites the same wlog_ key, same date field).
//  3. A workout completed BEFORE the 7-day window (day -7) is NOT counted.
//
// All dates must be ≤ TODAY (2026-06-18) — future dates trip guard logic.
//
// Run: flutter test test/contracts/weekly_report_data_behavioral_test.dart

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/profile/providers/weekly_report_data_provider.dart';
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

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('weekly_report_data_');
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

  const testUser = 'test-weekly-report-0005-aabbccdd';

  setUp(() async {
    await HiveUserSession.openForUser(testUser);
    await HiveService.instance.workoutBox.clear();
    await HiveService.instance.healthBox.clear();
    await HiveService.instance.nutritionBox.clear();
  });

  group('weekly_report_data — wlog_ writes reflected in workouts series', () {
    test('3 workouts on 3 distinct IST dates within window → 3 non-zero entries',
        () async {
      final today = DateTime.now();

      // Use dates within the 7-day window (days 0, -1, -2 from today).
      final dates = [
        today,
        today.subtract(const Duration(days: 1)),
        today.subtract(const Duration(days: 2)),
      ];

      // markCompleted is the writer for wlog_* keys (logExercise writes
      // exlog_* keys, which are NOT scanned by weeklyReportDataProvider).
      for (final date in dates) {
        final result = await WorkoutWriteService.instance.markCompleted(
          date: date,
          workoutName: 'Test Workout',
          durationSec: 1800,
        );
        expect(result.success, isTrue,
            reason:
                'markCompleted must succeed for date ${istDateStr(date)}');
      }

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final series = container.read(weeklyReportDataProvider);

      // workouts is a 7-element list. Count the non-zero entries.
      final nonZeroCount = series.workouts.where((v) => v > 0).length;
      expect(nonZeroCount, 3,
          reason:
              '3 workouts marked complete on 3 distinct days must yield 3 '
              'non-zero entries in the workouts series');

      // The series must NOT be isEmpty (non-zero workout data).
      expect(series.isEmpty, isFalse,
          reason: 'series must not be empty when workouts were completed');
    });

    test('two completions on the same date count as 1 (dedup by date)', () async {
      final today = DateTime.now();
      final todayStr = istDateStr(today);

      // Call markCompleted twice for the SAME date — second call overwrites
      // the wlog_ key, both map to todayStr, dedup produces 1 bar.
      final r1 = await WorkoutWriteService.instance.markCompleted(
        date: today,
        workoutName: 'Morning Workout',
        durationSec: 1800,
      );
      expect(r1.success, isTrue);

      final r2 = await WorkoutWriteService.instance.markCompleted(
        date: today,
        workoutName: 'Evening Workout',
        durationSec: 900,
      );
      expect(r2.success, isTrue);

      // The wlog_ key for today must be present.
      final wlogKey = 'wlog_$todayStr';
      final stored = HiveService.instance.workoutBox.get(wlogKey);
      expect(stored, isNotNull,
          reason: 'wlog_$todayStr must exist after markCompleted for today');

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final series = container.read(weeklyReportDataProvider);

      // Only ONE day should be non-zero (both completions are on the same
      // date — the wlog_ key is overwritten, same date field → 1 entry in set).
      final nonZeroCount = series.workouts.where((v) => v > 0).length;
      expect(nonZeroCount, 1,
          reason:
              'two markCompleted calls on the same date must produce exactly '
              '1 non-zero entry (dedup by date — same wlog_ key)');

      // That entry must be 1.0.
      final todayIndex = series.workouts.length - 1; // dates[6] = today
      expect(series.workouts[todayIndex], 1.0,
          reason:
              "today's workout count must be 1.0 even after 2 completions "
              '(dedup prevents double-count drift)');
    });

    test(
        'workout completed on day -7 (outside the window) is NOT counted',
        () async {
      final today = DateTime.now();

      // day -7 from today is OUTSIDE the window (window is days -6 to 0).
      final outsideWindow = today.subtract(const Duration(days: 7));

      final r = await WorkoutWriteService.instance.markCompleted(
        date: outsideWindow,
        workoutName: 'Old Workout',
        durationSec: 1200,
      );
      expect(r.success, isTrue);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final series = container.read(weeklyReportDataProvider);

      // The 7-day window is dates[0] = today-6 through dates[6] = today.
      // Day -7 is NOT in the window → workouts must all be 0.
      expect(series.workouts.every((v) => v == 0), isTrue,
          reason:
              'workout on day -7 (outside the 7-day window) must NOT appear '
              'in the workouts series');
    });
  });
}
