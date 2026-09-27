import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_allowance.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_result.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/swap_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';

import '../../helpers/hive_test_setup.dart';

// Week of Mon 21 – Sun 27 Sep 2026; "today" is Thu 24.
const mon = '2026-09-21';
const tue = '2026-09-22';
const wed = '2026-09-23';
const thu = '2026-09-24';
const fri = '2026-09-25';
const sat = '2026-09-26';
const sun = '2026-09-27';
const nextMon = '2026-09-28';

// ignore: deprecated_member_use
SwapService get engine => SwapService.instance;

Map<String, dynamic> workout(String date, String name,
        {String status = 'planned'}) =>
    {
      'date': date,
      'day_of_week': 0,
      'week': 2,
      'phase': 3,
      'week_character': 'working',
      'type': 'workout',
      'workout_name': name,
      'exercises': [
        {'exercise_name': '$name A', 'sets': 3}
      ],
      'status': status,
      'is_swapped': false,
      'original_date': null,
    };

Map<String, dynamic> rest(String date) => {
      'date': date,
      'day_of_week': 6,
      'week': 2,
      'phase': 3,
      'type': 'rest',
      'workout_name': 'Rest Day',
      'exercises': <Map<String, dynamic>>[],
      'status': 'rest',
    };

Future<void> put(String date, Map<String, dynamic> row) =>
    HiveService.instance.workoutBox.put('schedule_$date', row);

Map<String, dynamic>? get(String key) {
  final raw = HiveService.instance.workoutBox.get(key);
  return raw is Map ? Map<String, dynamic>.from(raw) : null;
}

void main() {
  late Directory dir;
  final events = <String>[];
  final nonFatals = <String>[];
  var planPushes = 0;

  setUp(() async {
    dir = await setUpHiveForTests();
    setTestClockTo(DateTime.utc(2026, 9, 24, 4, 30)); // Thu 24, 10:00 IST
    events.clear();
    nonFatals.clear();
    planPushes = 0;
    ErrorTelemetry.debugOnLogEventForTests =
        (op, {message}) => events.add('$op $message');
    ErrorTelemetry.debugOnRecordNonFatalForTests =
        (e, st, {required reason, extra}) => nonFatals.add(reason);
    DaySwapAllowance.debugConsumeForTests = (_) async => null;
    SwapService.debugOnPlanPushForTests = () => planPushes++;
    SwapService.debugSwapWriteForTests = null;
    SwapService.debugRecordSwapForTests = null;
    await put(mon, workout(mon, 'Push', status: 'completed'));
    await put(tue, rest(tue));
    await put(wed, workout(wed, 'Legs'));
    await put(thu, workout(thu, 'Calisthenics'));
    await put(fri, workout(fri, 'Pull + Core'));
    await put(sat, workout(sat, 'Legs + Core'));
    await put(sun, rest(sun));
  });

  tearDown(() async {
    ErrorTelemetry.debugOnLogEventForTests = null;
    ErrorTelemetry.debugOnRecordNonFatalForTests = null;
    DaySwapAllowance.debugConsumeForTests = null;
    SwapService.debugOnPlanPushForTests = null;
    SwapService.debugSwapWriteForTests = null;
    SwapService.debugRecordSwapForTests = null;
    resetTestClock();
    await tearDownHiveForTests(dir);
  });

  Future<DaySwapResult> swap(String a, String b,
          {bool isPro = true, String? inProgress}) =>
      engine.swapDays(
          dateA: a,
          dateB: b,
          origin: DaySwapOrigin.trainDrag,
          isPro: isPro,
          inProgressDate: inProgress);

  test('workout<->workout: both rows swap, stamped, counted once, plan pushed',
      () async {
    final r = await swap(fri, sat);
    expect(r, isA<DaySwapDone>());
    expect((r as DaySwapDone).allowanceAfter,
        const DayAllowance(weekStart: mon, used: 1, limit: 3));
    final f = get('schedule_$fri')!;
    final s = get('schedule_$sat')!;
    expect(f['workout_name'], 'Legs + Core');
    expect(s['workout_name'], 'Pull + Core');
    expect(f['source'], 'day_swap');
    expect(f['original_date'], sat);
    expect(f['arranged_at_ms'], s['arranged_at_ms']);
    expect(planPushes, 1);
    expect(events.where((e) => e.startsWith('day_swap_done ')), hasLength(1));
  });

  test('a completed day is refused; nothing written, counted or pushed',
      () async {
    await put(fri, workout(fri, 'Pull + Core', status: 'completed'));
    final satBefore = get('schedule_$sat');
    final r = await swap(fri, sat);
    expect((r as DaySwapRefused).reason, DaySwapRefusal.completed);
    expect(r.date, fri);
    expect(get('schedule_$sat'), satBefore);
    expect(DaySwapAllowance.instance.current(mon, isPro: true).used, 0);
    expect(planPushes, 0);
    expect(events, ['day_swap_refused origin=trainDrag reason=completed']);
  });

  test('checks run at confirm time: completed after the preview is refused',
      () async {
    expect(engine.preview(dateA: fri, dateB: sat, isPro: true).refusal, isNull);
    await put(sat, workout(sat, 'Legs + Core', status: 'completed'));
    final r = await swap(fri, sat);
    expect((r as DaySwapRefused).reason, DaySwapRefusal.completed);
    expect(r.date, sat);
  });

  test("today with a workout log (wlog) is STARTED", () async {
    await HiveService.instance.workoutBox.put('wlog_$thu', {'date': thu});
    final r = await swap(thu, fri);
    expect((r as DaySwapRefused).reason, DaySwapRefusal.started);
  });

  test('today with a logged exercise (exlog index) is STARTED', () async {
    final box = HiveService.instance.workoutBox;
    await box.put('exlog_test_1', {'date': thu, 'exercise_name': 'Row'});
    await box.put('exercise_log_index_$thu', ['exlog_test_1']);
    final r = await swap(thu, fri);
    expect((r as DaySwapRefused).reason, DaySwapRefusal.started);
  });

  test('the in-progress date is STARTED', () async {
    final r = await swap(fri, sat, inProgress: fri);
    expect((r as DaySwapRefused).reason, DaySwapRefusal.started);
  });

  test('a past day is PAST', () async {
    final r = await swap(wed, fri);
    expect((r as DaySwapRefused).reason, DaySwapRefusal.past);
    expect(r.date, wed);
  });

  test('a cross-week pair is refused before any write', () async {
    final r = await swap(sun, nextMon);
    expect((r as DaySwapRefused).reason, DaySwapRefusal.differentWeek);
    expect(planPushes, 0);
  });

  test('free: the second swap of the week is refused and writes nothing',
      () async {
    expect(await swap(fri, sat, isPro: false), isA<DaySwapDone>());
    final sunBefore = get('schedule_$sun');
    final r = await swap(sat, sun, isPro: false);
    expect((r as DaySwapRefused).reason, DaySwapRefusal.allowanceSpent);
    expect(get('schedule_$sun'), sunBefore);
    expect(DaySwapAllowance.instance.current(mon, isPro: false).used, 1);
  });

  test('a failed write is not counted and pushes no plan', () async {
    SwapService.debugSwapWriteForTests =
        ({required dateA, required dateB, required build}) async =>
            WriteResult.fail('boom');
    final r = await swap(fri, sat);
    expect(r, isA<DaySwapFailed>());
    expect(DaySwapAllowance.instance.current(mon, isPro: true).used, 0);
    expect(planPushes, 0);
    expect(events.single, startsWith('day_swap_failed '));
  });

  test('a write that THROWS is Failed; nothing counted, nothing pushed, '
      'telemetry recorded (H-42)', () async {
    SwapService.debugSwapWriteForTests =
        ({required dateA, required dateB, required build}) async =>
            throw Exception('boom');
    final r = await swap(fri, sat);
    expect(r, isA<DaySwapFailed>());
    expect(DaySwapAllowance.instance.current(mon, isPro: true).used, 0);
    expect(planPushes, 0);
    expect(nonFatals, ['day_swap_write_threw']);
    expect(events, isEmpty,
        reason: 'a throw is a non-fatal, not a day_swap_failed logEvent');
  });

  test('recordSwap THROWING after a successful write still reports Done — '
      'the write is never disowned; telemetry recorded (H-42)', () async {
    SwapService.debugRecordSwapForTests =
        (String weekStart, {required bool isPro}) async =>
            throw Exception('boom');
    final r = await swap(fri, sat);
    expect(r, isA<DaySwapDone>());
    // Under-counted, never double-charged: recordSwap never persisted its
    // increment, so .current() still reads the pre-swap value.
    expect((r as DaySwapDone).allowanceAfter.used, 0);
    // The write DID happen — never claim a done swap failed.
    expect(get('schedule_$fri')!['workout_name'], 'Legs + Core');
    expect(get('schedule_$sat')!['workout_name'], 'Pull + Core');
    expect(planPushes, 1);
    expect(nonFatals, ['day_swap_record_threw']);
    expect(events.where((e) => e.startsWith('day_swap_done ')), hasLength(1));
  });

  test('creating three rest days in a row warns but still swaps', () async {
    await put(thu, rest(thu));
    await put(sat, rest(sat));
    final r = await swap(thu, fri);
    expect(r, isA<DaySwapDone>());
    expect((r as DaySwapDone).warning,
        const RestRunWarning(runDates: [fri, sat, sun]));
    expect(get('schedule_$fri')!['type'], 'rest');
  });

  test("a template's displaced_ backup travels with it", () async {
    await put(fri, {
      ...workout(fri, 'My Split'),
      'type': 'custom_template',
      'template_id': 't1',
    });
    await HiveService.instance.workoutBox
        .put('displaced_$fri', workout(fri, 'Pull + Core'));
    expect(await swap(fri, sat), isA<DaySwapDone>());
    expect(HiveService.instance.workoutBox.containsKey('displaced_$fri'),
        isFalse);
    final moved = get('displaced_$sat')!;
    expect(moved['workout_name'], 'Pull + Core');
    expect(moved['date'], sat);
    expect(get('schedule_$sat')!['template_id'], 't1');
  });

  test('swap-back clears MOVED and keeps a newer arranged_at_ms', () async {
    await swap(fri, sat);
    final later = DateTime.utc(2026, 9, 24, 5, 30);
    setTestClockTo(later);
    await swap(fri, sat);
    final f = get('schedule_$fri')!;
    expect(f['workout_name'], 'Pull + Core');
    expect(f.containsKey('is_swapped'), isFalse);
    expect(f['arranged_at_ms'], later.millisecondsSinceEpoch);
    expect(DaySwapAllowance.instance.current(mon, isPro: true).used, 2);
  });

  test('weekStates: locks and titles for the whole week', () {
    final s = engine.weekStates(thu);
    expect(s.map((d) => d.date), [mon, tue, wed, thu, fri, sat, sun]);
    expect(s[0].lock, DaySwapRefusal.completed);
    expect(s[1].lock, DaySwapRefusal.past);
    expect(s[3].lock, isNull);
    expect(s[4].title, 'Pull + Core');
    expect(s[6].title, 'Rest day');
    expect(s[4].movable, isTrue);
  });

  test('preview reports allowance and warning, writes and logs nothing',
      () {
    final p = engine.preview(dateA: thu, dateB: fri, isPro: false);
    expect(p.allowance, const DayAllowance(weekStart: mon, used: 0, limit: 1));
    expect(p.refusal, isNull);
    expect(events, isEmpty);
    expect(get('schedule_$thu')!['workout_name'], 'Calisthenics');
  });
}
