// BEHAVIORAL CONTRACT TEST — swap_counters (the weekly day-swap allowance)
//
// Concept:   swap_counters (Task 29 of the day-swapper plan re-points this
//            concept's writer at day_swap_allowance.dart)
// Writer:    SwapService.swapDays → DaySwapAllowance.recordSwap, ONLY after
//            WorkoutWriteService.swapScheduledDays succeeded
// Reader:    DaySwapAllowance.current (userBox key `day_swap_allowance`)
//
// These asserts FAIL if the engine counts a refused, cross-week or failed
// swap, counts before the write, or stops counting per IST week.
// The old counters (`swaps_this_week`, `swap_week_start`) are dead keys:
// the repair migrator deletes them (plan Task 23).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_allowance.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_result.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/swap_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';

import '../helpers/hive_test_setup.dart';

const week = '2026-09-21'; // Monday
const thu = '2026-09-24';
const fri = '2026-09-25';
const sat = '2026-09-26';
const sun = '2026-09-27';
const nextMon = '2026-09-28';

// ignore: deprecated_member_use
SwapService get engine => SwapService.instance;

Map<String, dynamic> row(String date, String name) => {
      'date': date,
      'type': 'workout',
      'workout_name': name,
      'status': 'planned',
      'exercises': <Map<String, dynamic>>[],
    };

void main() {
  late Directory dir;

  setUp(() async {
    dir = await setUpHiveForTests();
    setTestClockTo(DateTime.utc(2026, 9, 24, 4, 30)); // Thu 24, 10:00 IST
    ErrorTelemetry.debugOnLogEventForTests = (op, {message}) {};
    ErrorTelemetry.debugOnRecordNonFatalForTests =
        (e, st, {required reason, extra}) {};
    DaySwapAllowance.debugConsumeForTests = (_) async => null;
    SwapService.debugOnPlanPushForTests = () {};
    final box = HiveService.instance.workoutBox;
    for (final d in [thu, fri, sat, sun, nextMon]) {
      await box.put('schedule_$d', row(d, 'W $d'));
    }
  });

  tearDown(() async {
    ErrorTelemetry.debugOnLogEventForTests = null;
    ErrorTelemetry.debugOnRecordNonFatalForTests = null;
    DaySwapAllowance.debugConsumeForTests = null;
    SwapService.debugOnPlanPushForTests = null;
    SwapService.debugSwapWriteForTests = null;
    resetTestClock();
    await tearDownHiveForTests(dir);
  });

  int used() => DaySwapAllowance.instance.current(week, isPro: true).used;

  Future<DaySwapResult> swap(String a, String b) => engine.swapDays(
      dateA: a, dateB: b, origin: DaySwapOrigin.trainPicker, isPro: true);

  test('a successful swap counts 1 for its IST week', () async {
    expect(await swap(fri, sat), isA<DaySwapDone>());
    expect(used(), 1);
  });

  test('a second swap in the same week counts 2', () async {
    await swap(fri, sat);
    await swap(sat, sun);
    expect(used(), 2);
  });

  test("another week's count is independent", () async {
    await swap(fri, sat);
    expect(
        DaySwapAllowance.instance.current(nextMon, isPro: true).used, 0);
  });

  test('a cross-week swap is refused and counts nothing', () async {
    final r = await swap(sun, nextMon);
    expect((r as DaySwapRefused).reason, DaySwapRefusal.differentWeek);
    expect(used(), 0);
  });

  test('a refused swap (completed day) counts nothing', () async {
    await HiveService.instance.workoutBox
        .put('schedule_$fri', {...row(fri, 'Pull'), 'status': 'completed'});
    expect(await swap(fri, sat), isA<DaySwapRefused>());
    expect(used(), 0);
  });

  test('a failed write counts nothing', () async {
    SwapService.debugSwapWriteForTests =
        ({required dateA, required dateB, required build}) async =>
            WriteResult.fail('boom');
    expect(await swap(fri, sat), isA<DaySwapFailed>());
    expect(used(), 0);
  });
}
