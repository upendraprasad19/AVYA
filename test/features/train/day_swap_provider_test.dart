import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_allowance.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_result.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/swap_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/train/providers/day_swap_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';

import '../../helpers/hive_test_setup.dart';

const mon = '2026-09-21';
const thu = '2026-09-24';
const fri = '2026-09-25';
const sat = '2026-09-26';

class _Sub extends SubscriptionInfoNotifier {
  _Sub(this.pro);
  final bool pro;
  @override
  SubscriptionInfoData build() => SubscriptionInfoData(isPro: pro);
}

class _Active extends ActiveWorkoutNotifier {
  _Active(this.data);
  final ActiveWorkoutData data;
  @override
  ActiveWorkoutData build() => data;
}

class _Plan extends CurrentPlanNotifier {
  static int builds = 0;
  @override
  CurrentPlanData build() {
    builds++;
    return const CurrentPlanData();
  }
}

Map<String, dynamic> workout(String date, String name,
        {String status = 'planned'}) =>
    {
      'date': date,
      'type': 'workout',
      'workout_name': name,
      'status': status,
      'exercises': <Map<String, dynamic>>[],
    };

ActiveWorkoutData sessionOn(DateTime? date) => ActiveWorkoutData(
    workoutDay: WorkoutDayData(dayNumber: 1, name: 'Pull', date: date));

void main() {
  late Directory dir;

  setUp(() async {
    dir = await setUpHiveForTests();
    setTestClockTo(DateTime.utc(2026, 9, 24, 4, 30)); // Thu 24, 10:00 IST
    _Plan.builds = 0;
    ErrorTelemetry.debugOnLogEventForTests = (op, {message}) {};
    ErrorTelemetry.debugOnRecordNonFatalForTests =
        (e, st, {required reason, extra}) {};
    DaySwapAllowance.debugConsumeForTests = (_) async => null;
    SwapService.debugOnPlanPushForTests = () {};
    final box = HiveService.instance.workoutBox;
    await box.put('schedule_$thu', workout(thu, 'Calisthenics'));
    await box.put('schedule_$fri', workout(fri, 'Pull + Core'));
    await box.put('schedule_$sat', workout(sat, 'Legs + Core'));
  });

  tearDown(() async {
    ErrorTelemetry.debugOnLogEventForTests = null;
    ErrorTelemetry.debugOnRecordNonFatalForTests = null;
    DaySwapAllowance.debugConsumeForTests = null;
    SwapService.debugOnPlanPushForTests = null;
    resetTestClock();
    await tearDownHiveForTests(dir);
  });

  ProviderContainer container(
      {bool pro = true, ActiveWorkoutData active = const ActiveWorkoutData()}) {
    final c = ProviderContainer(overrides: [
      subscriptionInfoProvider.overrideWith(() => _Sub(pro)),
      activeWorkoutProvider.overrideWith(() => _Active(active)),
      currentPlanProvider.overrideWith(_Plan.new),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  Future<DaySwapResult> swap(ProviderContainer c, String a, String b) => c
      .read(daySwapControllerProvider)
      .swap(dateA: a, dateB: b, origin: DaySwapOrigin.trainPicker);

  test('inProgressDateOf: none, dated session, undated session', () {
    expect(inProgressDateOf(const ActiveWorkoutData()), isNull);
    expect(inProgressDateOf(sessionOn(DateTime.utc(2026, 9, 25))), fri);
    expect(inProgressDateOf(sessionOn(null)), thu);
  });

  test('the PRO tier reaches the engine', () async {
    final pro = await swap(container(pro: true), fri, sat);
    expect((pro as DaySwapDone).allowanceAfter.limit, 3);
  });

  test('the free tier reaches the engine', () async {
    final free = await swap(container(pro: false), fri, sat);
    expect((free as DaySwapDone).allowanceAfter.limit, 1);
  });

  test('the in-progress date reaches the engine', () async {
    final c = container(active: sessionOn(DateTime.utc(2026, 9, 25)));
    final r = await swap(c, fri, sat);
    expect((r as DaySwapRefused).reason, DaySwapRefusal.started);
  });

  test('a done swap refreshes the week states and the plan', () async {
    final c = container();
    expect(c.read(daySwapWeekProvider(mon))[4].title, 'Pull + Core');
    final buildsBefore = _Plan.builds;
    expect(await swap(c, fri, sat), isA<DaySwapDone>());
    expect(c.read(daySwapWeekProvider(mon))[4].title, 'Legs + Core');
    expect(_Plan.builds, greaterThan(buildsBefore));
  });

  test('a refused swap still refreshes the week (the screen was stale)',
      () async {
    final c = container();
    expect(c.read(daySwapWeekProvider(mon))[4].movable, isTrue);
    await HiveService.instance.workoutBox.put(
        'schedule_$fri', workout(fri, 'Pull + Core', status: 'completed'));
    expect(await swap(c, fri, sat), isA<DaySwapRefused>());
    expect(c.read(daySwapWeekProvider(mon))[4].lock, DaySwapRefusal.completed);
  });

  test('the allowance provider follows a server reply that lands later',
      () async {
    final gate = Completer<Map<String, dynamic>?>();
    DaySwapAllowance.debugConsumeForTests = (_) => gate.future;
    final c = container();
    await swap(c, fri, sat);
    expect(c.read(daySwapAllowanceProvider(mon)).used, 1);
    gate.complete({'allowed': true, 'used': 3, 'limit': 3});
    await DaySwapAllowance.instance.lastConsumeForTests;
    expect(c.read(daySwapAllowanceProvider(mon)).used, 3);
  });

  test(
      'preview: PRO vs free allowance, an in-progress date locks, no side '
      'effects', () {
    final pro = container(pro: true);
    final proPreview = pro.read(daySwapControllerProvider).preview(fri, sat);
    expect(proPreview.allowance.limit, 3);
    expect(proPreview.refusal, isNull);

    final free = container(pro: false);
    final freePreview =
        free.read(daySwapControllerProvider).preview(fri, sat);
    expect(freePreview.allowance.limit, 1);
    expect(freePreview.refusal, isNull);

    final active =
        container(active: sessionOn(DateTime.utc(2026, 9, 25))); // fri
    final activePreview =
        active.read(daySwapControllerProvider).preview(fri, sat);
    expect(activePreview.refusal, DaySwapRefusal.started);

    // No side effects: nothing written, nothing consumed, nothing logged.
    expect(pro.read(daySwapAllowanceProvider(mon)).used, 0);
    expect(free.read(daySwapAllowanceProvider(mon)).used, 0);
    final friRow = HiveService.instance.workoutBox.get('schedule_$fri') as Map?;
    final satRow = HiveService.instance.workoutBox.get('schedule_$sat') as Map?;
    expect(friRow?['workout_name'], 'Pull + Core');
    expect(satRow?['workout_name'], 'Legs + Core');
  });
}
