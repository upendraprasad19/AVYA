// Unit 3C (OI-396, docs/plans/2026-11-16-generator-step3c-cardio-finisher.md §2.3): the stored cardio finisher through
// the REAL readers and writers, over real Hive boxes and the real exercise library.
//
// - Train (`workoutDayForDate`) shows the finisher with its own rows, its minutes and the day's minutes; Home's card
//   minutes equal Train's; an injury in the PROFILE hides a jumping finisher (the bike stays).
// - `FinisherShowContextReader.read()` fails closed (a read failure = injured, display only).
// - `shortenDay` (d79): the finisher goes first; then lifts; `target_too_low` writes nothing; a hidden finisher is not
//   counted and its key goes whenever the row is written.
// - The writers: `generateAndScheduleFromDate` (Edit Profile's reschedule) and the hotel planner write the finisher
//   like `generateAndSchedule` (round 1 writer drift, round 3 A-F4); a day swap carries it with the day's content.
// - The session (`startWorkout`) holds only the lifts: the finisher is never a set to save, a "Not saved" line or a PR.
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/swap_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_rules.dart';
import 'package:icanbefitter/features/ai_coach/services/hotel_workout_planner.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/services/log_exercise_logic.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/finisher_safety.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/finisher_show_context.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_estimate.dart';

const _user = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

Map<String, dynamic> _lift(String id, String name, {int sets = 3, int rest = 90, int tier = 1}) => {
      'exercise_id': id,
      'exercise_name': name,
      'logging_type': 'weight_reps',
      'exercise_type': ['compound'],
      'rep_range': '8-12',
      'sets': sets,
      'reps': '10',
      'rest_seconds': rest,
      'priority_tier': tier,
    };

Map<String, dynamic> _timed(String name, int secs) => {
      'exercise_id': name,
      'exercise_name': name,
      'logging_type': 'timed',
      'sets': 1,
      'reps': '${secs}s',
      'rest_seconds': 0,
      'duration_seconds': secs,
    };

/// The stored HIIT finisher (`CardioFinisher` with round rests): 3 x 120 s work + 3 x 60 s round rest = 540 s.
final _hiit = [
  {'exercise_name': 'Burpees', 'logging_type': 'timed', 'sets': 3, 'reps': '10', 'rest_seconds': 0, 'duration_seconds': 120},
  {'exercise_name': 'Mountain Climbers', 'logging_type': 'timed', 'sets': 3, 'reps': '30s', 'rest_seconds': 0, 'duration_seconds': 120},
  {'exercise_name': 'Jump Squats', 'logging_type': 'timed', 'sets': 3, 'reps': '10', 'rest_seconds': 60, 'duration_seconds': 120},
];

final _bike = [
  {
    'exercise_name': 'Stationary Bike Sprints',
    'logging_type': 'timed',
    'sets': 8,
    'reps': '30s fast / 30s slow',
    'rest_seconds': 0,
    'duration_seconds': 480,
  },
];

const _date = '2026-11-18';

Map<String, dynamic> _row({List<Map<String, dynamic>>? finisher}) => {
      'date': _date,
      'week': 1,
      'day_of_week': 2,
      'type': 'workout',
      'workout_name': 'Upper',
      'workout_focus': 'Push and pull',
      'status': 'planned',
      'exercises': [
        _lift('X1', 'Test Press A', tier: 1),
        _lift('X2', 'Test Row B', tier: 1),
        _lift('X3', 'Test Raise C', tier: 3),
        _lift('X4', 'Test Curl D', tier: 3),
      ],
      'warmup': [_timed('Light Jog', 180)],
      'cooldown': [_timed('Slow Walking', 180)],
      'finisher': ?finisher,
    };

Future<void> _putRow(Map<String, dynamic> row) => HiveService.instance.workoutBox.put('schedule_$_date', row);

Map<dynamic, dynamic> _storedRow() => HiveService.instance.workoutBox.get('schedule_$_date') as Map;

Future<void> _profile({Object? injuries = const ['none'], String goal = 'lose_fat'}) =>
    HiveService.instance.userBox.put('profile', {
      'primary_goal': goal,
      'fitness_experience': 'intermediate',
      'equipment_access': 'full_gym',
      'days_per_week': 4,
      'injuries': injuries,
    });

/// The day's minutes without any finisher: the shared estimate, as the readers price it.
int _baseMinutes() => budgetedDayMinutes(_row(), finisher: const [])!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('finisher_display');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    final exBox = await Hive.openBox(HiveService.exerciseBoxName);
    final rows = jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List;
    for (final r in rows.whereType<Map>()) {
      await exBox.put((r['id'] ?? r['name']).toString(), Map<String, dynamic>.from(r));
    }
    HiveService.instance.markInitializedForTests();
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await HiveUserSession.openForUser(_user);
    await HiveService.instance.workoutBox.clear();
    await HiveService.instance.userBox.clear();
    SyncService.pausedForSimulation = true;
    SwapService.debugOnPlanPushForTests = () {};
  });

  tearDown(() async {
    SyncService.pausedForSimulation = false;
    SwapService.debugOnPlanPushForTests = null;
    await HiveUserSession.closeAll();
  });

  group('Train and Home show the finisher the rule allows', () {
    test('uninjured: Train lists the HIIT with its own rows, 9 MIN, and the day grows by it; Home agrees', () async {
      await _profile();
      await _putRow(_row(finisher: _hiit));
      final day = workoutDayForDate(DateTime.parse(_date))!;
      expect(day.finisher.map((e) => e.name), ['Burpees', 'Mountain Climbers', 'Jump Squats']);
      expect(day.finisher.map((e) => e.detailText), ['3 rounds · 10', '3 rounds · 30s', '3 rounds · 10']);
      expect(day.finisher.every((e) => e.muscleLabel == null), isTrue);
      expect(day.finisherSeconds, 540);
      expect(FinisherSafety.minutesLabel(day.finisherSeconds), '9 MIN');
      expect(day.budgetMinutes, budgetedDayMinutes(_row(), finisher: _hiit));
      expect(day.budgetMinutes! - _baseMinutes(), inInclusiveRange(8, 10));
      final home = homeCardMinutes(_storedRow(),
          finisher: FinisherSafety.shownOfRow(_storedRow(), FinisherShowContextReader.read()));
      expect(home, day.budgetMinutes, reason: 'Train == Home');
    });

    test('an injury in the profile hides the jumping finisher and its minutes; the bike stays', () async {
      await _profile(injuries: const ['knee']);
      await _putRow(_row(finisher: _hiit));
      var day = workoutDayForDate(DateTime.parse(_date))!;
      expect(day.finisher, isEmpty);
      expect(day.finisherSeconds, 0);
      expect(day.budgetMinutes, _baseMinutes());
      expect(
          homeCardMinutes(_storedRow(),
              finisher: FinisherSafety.shownOfRow(_storedRow(), FinisherShowContextReader.read())),
          _baseMinutes());

      await _putRow(_row(finisher: _bike));
      day = workoutDayForDate(DateTime.parse(_date))!;
      expect(day.finisher.map((e) => e.name), ['Stationary Bike Sprints']);
      expect(day.finisher.single.detailText, '8 rounds · 30s fast / 30s slow');
      expect(day.finisherSeconds, 480);
    });

    test('profile none keeps the finisher (round 3 A-F1)', () async {
      await _profile(injuries: 'none');
      await _putRow(_row(finisher: _hiit));
      expect(workoutDayForDate(DateTime.parse(_date))!.finisher, hasLength(3));
    });

    test('the context reader fails closed: no user session = injured', () async {
      await HiveUserSession.closeAll();
      final ctx = FinisherShowContextReader.read();
      expect(ctx.injured, isTrue);
      expect(FinisherSafety.shownFinisherMaps(_hiit, injured: ctx.injured), isEmpty);
      await HiveUserSession.openForUser(_user);
    });

    test('no profile yet (before a restore lands) is read as injured: a stored HIIT stays hidden (seat A F1)', () async {
      await _putRow(_row(finisher: _hiit));
      expect(HiveService.instance.userBox.get('profile'), isNull, reason: 'precondition: no profile');
      final ctx = FinisherShowContextReader.read();
      expect(ctx.injured, isTrue);
      expect(workoutDayForDate(DateTime.parse(_date))!.finisher, isEmpty);
      // Mirror: a profile with no injuries key is a profile, so its HIIT shows.
      await _profile(injuries: null);
      expect(FinisherShowContextReader.read().injured, isFalse);
      expect(workoutDayForDate(DateTime.parse(_date))!.finisher, hasLength(3));
    });
  });

  group('shortenDay drops the finisher first (d79)', () {
    Future<ShortenDayResult> shorten(int minutes) =>
        WorkoutScheduleService.instance.shortenDay(date: _date, targetMinutes: minutes);

    test('the finisher alone fits the target: it goes, every lift stays', () async {
      await _profile();
      await _putRow(_row(finisher: _hiit));
      final res = await shorten(_baseMinutes() + 1);
      expect(res.finisherDropped, isTrue);
      expect(res.droppedExerciseNames, isEmpty);
      final row = _storedRow();
      expect(row.containsKey('finisher'), isFalse);
      expect((row['exercises'] as List).length, 4);
    });

    test('still over without it: the finisher and then the lowest-priority lifts go', () async {
      await _profile();
      await _putRow(_row(finisher: _hiit));
      final res = await shorten(_baseMinutes() - 8);
      expect(res.finisherDropped, isTrue);
      expect(res.droppedExerciseNames, isNotEmpty);
      expect(_storedRow().containsKey('finisher'), isFalse);
    });

    test('below the floor of 2 lifts: target_too_low, nothing written, the finisher kept', () async {
      await _profile();
      await _putRow(_row(finisher: _hiit));
      final before = jsonEncode(_storedRow());
      await expectLater(shorten(5), throwsA(isA<ShortenDayException>().having((e) => e.code, 'code', 'target_too_low')));
      expect(jsonEncode(_storedRow()), before);
    });

    test('a target the day already meets writes nothing', () async {
      await _profile();
      await _putRow(_row(finisher: _hiit));
      final before = jsonEncode(_storedRow());
      final res = await shorten(_baseMinutes() + 30);
      expect(res.finisherDropped, isFalse);
      expect(jsonEncode(_storedRow()), before);
    });

    test('a hidden finisher is not counted, and its key goes when the row is written', () async {
      await _profile(injuries: const ['knee']);
      await _putRow(_row(finisher: _hiit));
      // Uncounted: the day without the finisher fits, so nothing is written.
      final fits = await shorten(_baseMinutes());
      expect(fits.finisherDropped, isFalse);
      expect(_storedRow().containsKey('finisher'), isTrue);
      // A real shorten writes the row without the hidden finisher.
      final res = await shorten(_baseMinutes() - 8);
      expect(res.finisherDropped, isFalse);
      expect(res.droppedExerciseNames, isNotEmpty);
      expect(_storedRow().containsKey('finisher'), isFalse);
    });
  });

  group('the writers keep the finisher (writer drift)', () {
    Map<String, bool> finisherByDate() {
      final out = <String, bool>{};
      final box = HiveService.instance.workoutBox;
      for (final k in box.keys.whereType<String>().where((k) => k.startsWith('schedule_'))) {
        final r = box.get(k);
        if (r is Map && r['type'] == 'workout') out[k] = r['finisher'] is List && (r['finisher'] as List).isNotEmpty;
      }
      return out;
    }

    test('Edit Profile\'s reschedule writes it on the same days as the first schedule', () async {
      await _profile();
      final monday = DateTime(2026, 11, 16);
      final svc = WorkoutScheduleReadService.instance;
      await svc.generateAndSchedule(
          goal: 'lose_fat', equipment: 'full_gym', daysPerWeek: 4, startDate: monday, experienceLevel: 'intermediate');
      final first = finisherByDate();
      expect(first.values.where((v) => v), isNotEmpty);
      for (final k in first.keys) {
        final r = Map<String, dynamic>.from(HiveService.instance.workoutBox.get(k) as Map)..remove('finisher');
        await HiveService.instance.workoutBox.put(k, r);
      }
      await svc.generateAndScheduleFromDate(
          goal: 'lose_fat', equipment: 'full_gym', daysPerWeek: 4, fromDate: monday, experienceLevel: 'intermediate');
      expect(finisherByDate(), first);
    });

    test('the hotel planner keeps the finisher it was generated with', () async {
      await _profile();
      final plan = await HotelWorkoutPlanner.instance.plan(days: 3, startDate: _date);
      final withFinisher = plan.rawSchedules.where((r) => r['finisher'] is List && (r['finisher'] as List).isNotEmpty);
      expect(withFinisher, isNotEmpty);
      expect(plan.rawSchedules.first['finisher'], isNotNull, reason: 'day index 0 is always a finisher day');
    });
  });
  group('a swapped day carries its finisher (§3)', () {
    test('buildSwap moves the finisher with the content, both ways', () {
      final a = {..._row(finisher: _hiit), 'date': '2026-11-18'};
      final b = {..._row(), 'date': '2026-11-20', 'workout_name': 'Lower'};
      final w = DaySwapRules.buildSwap(
          dateA: '2026-11-18', dateB: '2026-11-20', rowA: a, rowB: b, displacedA: null, displacedB: null, nowMs: 1);
      expect(w.rowB['finisher'], _hiit, reason: 'the finisher went with its workout');
      expect(w.rowA.containsKey('finisher'), isFalse, reason: 'and did not stay on the old date');
    });
  });

  group('the session never logs the finisher (§2.3)', () {
    test('startWorkout holds the lifts only: no saveable set, no "Not saved" line for a finisher row', () async {
      await _profile();
      await _putRow(_row(finisher: _hiit));
      final day = workoutDayForDate(DateTime.parse(_date))!;
      expect(day.finisher, isNotEmpty, reason: 'precondition: the day carries the finisher');
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(activeWorkoutProvider.notifier).startWorkout(day);
      final s = c.read(activeWorkoutProvider);
      expect(s.exercises.map((e) => e.name), ['Test Press A', 'Test Row B', 'Test Raise C', 'Test Curl D']);
      expect(s.hasSaveableSet, isFalse);
      final g = finishGuard(s);
      for (final name in ['Burpees', 'Mountain Climbers', 'Jump Squats']) {
        expect([...g.skipped, ...g.typedUnsaved, ...g.reopenedUnsaved, ...g.partial.map((p) => p.name)], isNot(contains(name)));
      }
      expect(s.workoutDay!.finisher.map((e) => e.name), ['Burpees', 'Mountain Climbers', 'Jump Squats'],
          reason: 'the screen still reads it from the day');
      c.read(activeWorkoutProvider.notifier).cancelWorkout();
    });
  });
}
