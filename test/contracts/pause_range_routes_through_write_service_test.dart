// Behavioral contract test: pause_range_routes_through_write_service
//
// Writer:  WorkoutScheduleWriteService.pauseRange
//          → routes through WorkoutWriteService.upsertScheduled (audit-fixwave / F3)
// Reader:  workoutBox.get('schedule_<istDate>') — raw Hive key
//
// Asserts pauseRange(startDate, days: 1):
//   - sets status='paused' + preserves paused_via / paused_at / pause_reason.
//   - ROUTES through the canonical WriteService: the stored row carries `source`
//     and `updated_at_ms`, which ONLY WorkoutWriteService.upsertScheduled stamps
//     (workout_write_service.dart:523-529). The pre-fix bypass did a bare
//     `box.put(key, map)` which sets status='paused' but does NOT stamp
//     source/updated_at_ms — so this test FAILS against the pre-fix code
//     (schedule-bypass P1) and PASSES with the routing fix.
//
// A completed day must never be paused (pauseRange skips it → throws when the
// range yields nothing to pause).
//
// closes-diagnose: f3b2e8

// ignore_for_file: deprecated_member_use

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_write_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import '../workout_write_service/helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await wwsTestSetup();
  });

  tearDown(() async {
    await wwsTestTeardown();
  });

  group('pause_range_routes_through_write_service — pauseRange contract', () {
    // Fixed FUTURE date: clears pauseRange's "not older than yesterday" guard
    // AND keeps istDateStr/formatDateKey deterministic (CI runs in IST).
    final date = DateTime(2030, 6, 15);

    test('pauseRange sets status=paused AND routes through upsertScheduled', () async {
      // Seed a planned schedule entry so pauseRange has a row to pause.
      await WorkoutWriteService.instance.upsertScheduled(
        date: date,
        entry: {
          'date': '2030-06-15',
          'type': 'workout',
          'workout_name': 'Push Day',
          'status': 'planned',
          'exercises': <dynamic>[],
        },
        source: WriteSource.planGenerator,
      );

      final paused = await WorkoutScheduleWriteService.instance.pauseRange(
        startDate: date,
        days: 1,
        reason: 'travel',
      );
      expect(paused, isNotEmpty,
          reason: 'pauseRange must return the paused date(s)');

      final box = HiveService.instance.workoutBox;
      final key = 'schedule_${WorkoutWriteService.istDateStr(date)}';
      final raw = box.get(key) as Map?;

      expect(raw, isNotNull, reason: 'schedule row must exist after pauseRange');
      expect(raw!['status'], 'paused', reason: 'status must be "paused"');
      expect(raw['paused_via'], 'ai_coach',
          reason: 'paused_via annotation must be preserved through the writer');
      expect(raw['pause_reason'], 'travel',
          reason: 'pause_reason must be preserved through the writer');

      // ROUTING PROOF — the seed was written with source=planGenerator.
      // upsertScheduled OVERWRITES `source` with the caller's value
      // (workout_write_service.dart:526, `'source': source.code`), so after a
      // routed pause the row's source is schedSwap. The pre-fix bare
      // `box.put(map)` re-persists the map verbatim → source stays planGenerator.
      // This is the assertion that distinguishes the fix from the bypass.
      expect(raw['source'], WriteSource.schedSwap.code,
          reason: 'pauseRange must route through upsertScheduled with '
              'WriteSource.schedSwap — a bare box.put would leave the seed '
              'source (planGenerator) unchanged (pre-fix schedule-bypass)');
    });

    test('pauseRange refuses to pause an already-completed day', () async {
      // Seed a COMPLETED day via schedSwap (planGenerator is refused on completed
      // days by upsertScheduled; schedSwap is allowed).
      await WorkoutWriteService.instance.upsertScheduled(
        date: date,
        entry: {
          'date': '2030-06-15',
          'type': 'workout',
          'status': 'completed',
          'exercises': <dynamic>[],
        },
        source: WriteSource.schedSwap,
      );

      // The only day in range is completed → pauseRange skips it → range yields
      // nothing → throws no_schedules_in_range.
      await expectLater(
        WorkoutScheduleWriteService.instance.pauseRange(startDate: date, days: 1),
        throwsA(isA<PausePlanException>()),
        reason: 'a completed day must not be paused',
      );

      // And the day must remain completed (not flipped to paused).
      final box = HiveService.instance.workoutBox;
      final raw =
          box.get('schedule_${WorkoutWriteService.istDateStr(date)}') as Map;
      expect(raw['status'], 'completed',
          reason: 'completed status must be untouched by a no-op pauseRange');
    });
  });
}
