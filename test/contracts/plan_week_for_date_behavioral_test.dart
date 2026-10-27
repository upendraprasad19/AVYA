// Behavioral — OI-166 Unit 1: a row's plan week and wave character must derive
// from THAT ROW'S DATE, never from the clock.
//
// THE BUG. `hotel_workout_planner.dart` hardcoded `'week': 1` and
// `'week_character': 'baseline'` on every row it wrote, and stamped
// `'day_of_week': d.weekday` (1..7) where every reader expects 0..6
// (`tool_dispatcher.dart:695` states the canon explicitly;
// `train_provider.dart:619`/`:816` compute `(week-1)*7 + day_of_week + 1` and
// render it as the `D<n>` badge). So a hotel workout landing inside a `deload`
// week 4 announced itself as a baseline week-1 day, one day number too high.
//
// WHY A CLOCK-DERIVED WEEK WOULD NOT HAVE FIXED IT — the trap this file exists
// to pin. A hotel plan runs up to SEVEN consecutive days
// (`hotel_workout_planner.dart:79`, `n = days.clamp(1, 7)`) from a possibly
// FUTURE `start` (`:81-83`), so it can straddle a plan-week boundary. Stamping
// `getCurrentWeekNumber()` on all of them would put today's week on days that
// are not today — the same defect shape, moved. The first draft of the fix said
// exactly that and was caught in review.
//
// Pure arithmetic lives in `WorkoutScheduleReadService.rawWeekNumberFor`;
// `planWeekAndCharacterFor` pairs it with the blob's character. Neither has a
// `catch` above its guards, deliberately — see the file-level note on
// `currentDeloadReason`, where guards under a swallowing `catch` made three
// separate mutations redden ZERO of twelve assertions.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  final planStart = DateTime(2026, 6, 1); // a Monday
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_plan_week_for_date');
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
    // Cleanup is hygiene, never an assertion — a throwing teardown stacks a
    // second failure that HIDES the real one.
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    for (final name in [
      HiveService.configBoxName,
      HiveService.migrationBoxName,
      'userBox_aaaaaaaa',
      'workoutBox_aaaaaaaa',
      'nutritionBox_aaaaaaaa',
      'healthBox_aaaaaaaa',
      'coachBox_aaaaaaaa',
    ]) {
      if (Hive.isBoxOpen(name)) await Hive.box(name).close();
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
  });

  tearDown(() async {
    await HiveUserSession.closeAll();
  });

  Future<void> seedPlan({
    DateTime? start,
    List<String>? waveCharacters,
  }) async {
    final cb = HiveService.instance.configBox;
    await cb.put('plan_start_date', (start ?? planStart).toIso8601String());
    if (waveCharacters != null) {
      await HiveService.instance.workoutBox.put('current_plan', {
        'week_plans': [
          for (final c in waveCharacters) {'week_character': c},
        ],
      });
    }
  }

  final svc = WorkoutScheduleReadService.instance;

  group('rawWeekNumberFor — pure, UNCLAMPED', () {
    test('day 0 is week 1; day 6 is still week 1', () {
      expect(WorkoutScheduleReadService.rawWeekNumberFor(planStart, planStart),
          1);
      expect(
          WorkoutScheduleReadService.rawWeekNumberFor(
              planStart.add(const Duration(days: 6)), planStart),
          1);
    });

    test('each 7-day step advances exactly one week', () {
      for (var w = 0; w < 4; w++) {
        expect(
            WorkoutScheduleReadService.rawWeekNumberFor(
                planStart.add(Duration(days: w * 7)), planStart),
            w + 1);
      }
    });

    test('past the 4th week it does NOT clamp — >4 is a real state', () {
      // `redoWeek4` extends plan_end without moving plan_start, so day 28+ is
      // reachable in production. Clamping here would hide it from any caller
      // reasoning about layout.
      expect(
          WorkoutScheduleReadService.rawWeekNumberFor(
              planStart.add(const Duration(days: 28)), planStart),
          5);
      expect(
          WorkoutScheduleReadService.rawWeekNumberFor(
              planStart.add(const Duration(days: 41)), planStart),
          6);
    });

    test('a date BEFORE plan start yields <1 rather than throwing', () {
      expect(
          WorkoutScheduleReadService.rawWeekNumberFor(
              planStart.subtract(const Duration(days: 7)), planStart),
          0);
    });
  });

  group('getCurrentWeekNumber — behaviour preserved by the extraction', () {
    test('no plan start stored → 1', () async {
      expect(svc.getCurrentWeekNumber(), 1);
    });

    test('clamps a >4 raw week down to 4', () async {
      await seedPlan(start: DateTime.now().subtract(const Duration(days: 35)));
      expect(svc.rawWeekNumber(), greaterThan(4));
      expect(svc.getCurrentWeekNumber(), 4);
    });

    test('clamps a <1 raw week up to 1', () async {
      await seedPlan(start: DateTime.now().add(const Duration(days: 14)));
      expect(svc.rawWeekNumber(), lessThan(1));
      expect(svc.getCurrentWeekNumber(), 1);
    });
  });

  group('planWeekAndCharacterFor — the fix', () {
    test('a day in week 4 of a deload phase reports week 4 AND deload', () async {
      await seedPlan(
          waveCharacters: ['baseline', 'overreach', 'peak', 'deload']);

      final r = svc.planWeekAndCharacterFor(
          planStart.add(const Duration(days: 22))); // week 4
      expect(r.week, 4);
      // Pre-fix the hotel planner hardcoded 'baseline' here. That is the bug.
      expect(r.character, 'deload');
    });

    test('consecutive days STRADDLING a week boundary get different weeks',
        () async {
      // The heart of it: one hotel plan, two plan weeks. A clock-derived stamp
      // gives both days the same number.
      await seedPlan(
          waveCharacters: ['baseline', 'overreach', 'peak', 'deload']);

      final sunOfWeek1 = svc.planWeekAndCharacterFor(
          planStart.add(const Duration(days: 6)));
      final monOfWeek2 = svc.planWeekAndCharacterFor(
          planStart.add(const Duration(days: 7)));

      expect(sunOfWeek1.week, 1);
      expect(monOfWeek2.week, 2);
      expect(sunOfWeek1.character, 'baseline');
      expect(monOfWeek2.character, 'overreach');
    });

    test('a lifted week 4 reports `working`, not `deload`', () async {
      await seedPlan(
          waveCharacters: ['baseline', 'overreach', 'peak', 'working']);
      final r =
          svc.planWeekAndCharacterFor(planStart.add(const Duration(days: 24)));
      expect(r.week, 4);
      expect(r.character, 'working');
    });

    test('week clamps to 4 past the phase, and the character comes with it',
        () async {
      await seedPlan(
          waveCharacters: ['baseline', 'overreach', 'peak', 'deload']);
      final r =
          svc.planWeekAndCharacterFor(planStart.add(const Duration(days: 40)));
      expect(r.week, 4, reason: 'stamped weeks stay displayable (1..4)');
      expect(r.character, 'deload');
    });

    test('no plan start → week 1, null character', () async {
      final r = svc.planWeekAndCharacterFor(DateTime(2026, 6, 15));
      expect(r.week, 1);
      expect(r.character, isNull);
    });

    test('plan start present but NO blob → week computed, null character',
        () async {
      await seedPlan(); // no waveCharacters
      final r =
          svc.planWeekAndCharacterFor(planStart.add(const Duration(days: 8)));
      expect(r.week, 2);
      expect(r.character, isNull);
    });

    test('a SHORT blob does not throw — it returns a null character', () async {
      await seedPlan(waveCharacters: ['baseline', 'overreach']);
      final r =
          svc.planWeekAndCharacterFor(planStart.add(const Duration(days: 22)));
      expect(r.week, 4);
      expect(r.character, isNull,
          reason: 'week_plans[3] does not exist; must not RangeError');
    });

    test('an EMPTY character string reads as null, not as ""', () async {
      await seedPlan(waveCharacters: ['', 'overreach', 'peak', 'deload']);
      final r = svc.planWeekAndCharacterFor(planStart);
      expect(r.week, 1);
      expect(r.character, isNull);
    });

    test('an unparseable plan_start_date → week 1, null character', () async {
      await HiveService.instance.configBox
          .put('plan_start_date', 'not-a-date');
      final r = svc.planWeekAndCharacterFor(DateTime(2026, 6, 15));
      expect(r.week, 1);
      expect(r.character, isNull);
    });
  });

  group('hotel_workout_planner stamps (source pins — presence only)', () {
    // These pin the LITERALS, which a behavioral test of HotelWorkoutPlanner
    // cannot reach without a full PlanGenerator + profile + exercise-library
    // fixture. The DECISION they feed is behaviorally covered above.
    final src = File('lib/features/ai_coach/services/hotel_workout_planner.dart')
        .readAsStringSync();

    test('day_of_week is written 0..6, not raw weekday', () {
      expect(src, contains("'day_of_week': d.weekday - 1"));
      expect(src, isNot(contains("'day_of_week': d.weekday,")),
          reason: 'raw 1..7 weekday was the OI-166 Unit 1 defect');
    });

    test('week and week_character come from the per-date lookup', () {
      expect(src, contains('planWeekAndCharacterFor(d)'));
      expect(src, contains("'week': planWeek.week"));
      expect(src, contains("'week_character': planWeek.character ?? 'baseline'"));
    });

    test('the hardcoded week 1 / baseline stamps are gone', () {
      expect(src, isNot(contains("'week': 1,")));
      expect(src, isNot(contains("'week_character': 'baseline',")));
    });
  });
}
