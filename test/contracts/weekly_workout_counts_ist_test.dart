// Bug e7a2c4 — getWeeklyWorkoutCounts must bucket by WHOLE IST calendar days,
// anchored on the seam-aware IST "today", not raw device-local DateTime.now().
//
// Pre-fix it used `DateTime.now()` (device wall clock, with time-of-day) and
// `DateTime.tryParse(dateStr)` (local midnight), so the rolling 7x24h window
// drifted with the device timezone / time-of-day and ignored the dev/year-sim
// clock seam — the reports "This Week" tile + 4-week frequency chart could be
// off by a day. This test freezes the clock at a known instant and asserts the
// IST-calendar-day buckets deterministically.
//
// closes-diagnose: e7a2c4

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';

import '../workout_write_service/helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await wwsTestSetup();
    // 2026-06-11 18:30Z == 2026-06-12 00:00 IST → IST "today" = 2026-06-12.
    setTestClockTo(DateTime.utc(2026, 6, 11, 18, 30));
  });

  tearDown(() async {
    resetTestClock();
    await wwsTestTeardown();
  });

  Future<void> seed(String dateKey) async {
    await HiveService.instance.workoutBox.put('wlog_$dateKey', {
      'type': 'workout_log',
      'workout_name': 'W $dateKey',
      'date': dateKey,
      'duration_seconds': 1200,
    });
  }

  group('getWeeklyWorkoutCounts — IST whole-day buckets (e7a2c4)', () {
    test('buckets rows by IST days-ago from the seam-aware IST today', () async {
      await seed('2026-06-12'); // today          → week 0
      await seed('2026-06-06'); // 6 days ago     → week 0
      await seed('2026-06-05'); // 7 days ago     → week 1
      await seed('2026-05-16'); // 27 days ago    → week 3
      await seed('2026-05-15'); // 28 days ago    → none
      await seed('2026-06-13'); // future (+1)    → none

      final counts = WorkoutRepository.instance.getWeeklyWorkoutCounts();
      expect(counts, [2, 1, 0, 1],
          reason: 'week0={06-12,06-06}, week1={06-05}, week2={}, '
              'week3={05-16}; 05-15 (28d) + 06-13 (future) excluded.');
    });

    test('honors the clock seam — moving today shifts the buckets', () async {
      await seed('2026-06-05');
      // With today=06-12, 06-05 is 7 days ago → week 1.
      expect(WorkoutRepository.instance.getWeeklyWorkoutCounts()[1], 1);

      // Move "today" back to 06-05 IST → the same row is now day 0 → week 0.
      setTestClockTo(DateTime.utc(2026, 6, 4, 18, 30)); // 06-05 00:00 IST
      final counts = WorkoutRepository.instance.getWeeklyWorkoutCounts();
      expect(counts[0], 1, reason: 'row is "today" after the seam moves');
      expect(counts[1], 0);
    });
  });
}
