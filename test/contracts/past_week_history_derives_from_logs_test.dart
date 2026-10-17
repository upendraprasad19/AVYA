// test/contracts/past_week_history_derives_from_logs_test.dart
//
// Diagnose f4e1d9 (2026-06-01) — completed past-phase weeks rendered a
// generic "Workout" with no exercises in the Train week-selector's
// `_PastWeekSheet`. Root cause: cloud `scheduled_workouts` has no
// `workout_name`/exercises column, and the schedule-row restore only
// hydrates a name when `template_id` is set; plan-generator days
// (`template_id IS NULL`) come back name-less. The actual workout name
// survives on the restored `wlog_<date>` session row, and the exercises on
// the `exlog_*` rows.
//
// The fix derives the past-day view from those logs via
// `derivePastDayLog` (week_selector.dart). This test pins that behaviour:
// given a completed day whose schedule row LOST its workout_name (the
// post-restore drift state), the derived name comes from `wlog_<date>` and
// the exercise list from the canonical reader — NOT the generic "Workout".
//
// Pure Hive — no Supabase — so it runs in the pre-commit gate.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/train/widgets/week_selector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_past_week_history');
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
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    for (final name in [
      HiveService.workoutBoxName,
      HiveService.configBoxName,
      HiveService.migrationBoxName,
      'workoutBox_aaaaaaaa',
    ]) {
      if (Hive.isBoxOpen(name)) await Hive.box(name).close();
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
  });

  tearDown(() async {
    await HiveUserSession.closeAll();
  });

  group('past-week history derives from logs', () {
    test('completed day with a name-less schedule row shows the wlog name + '
        'logged exercises', () async {
      final day = DateTime.now().subtract(const Duration(days: 40));

      // 1. Log two exercises (creates exlog_* rows + index).
      for (final name in ['Bench Press', 'Overhead Press']) {
        final r = await WorkoutWriteService.instance.logExercise(
          date: day,
          exerciseName: name,
          sets: [
            ExerciseSet(
              weightKg: 60,
              reps: 8,
              loggedAtMs: DateTime.now().millisecondsSinceEpoch,
            ),
          ],
          source: WriteSource.aiCoach,
        );
        expect(r.success, isTrue);
      }

      // 2. Mark the day completed → writes wlog_<date> with workout_name.
      final mc = await WorkoutWriteService.instance.markCompleted(
        date: day,
        workoutName: 'Push Day',
        durationSec: 0,
      );
      expect(mc.success, isTrue);

      // 3. Simulate the post-restore drift: the schedule row comes back
      //    name-less (plan-gen day, no template_id → no hydration).
      final wb = HiveService.instance.workoutBox;
      final sKey = WorkoutWriteService.scheduleKey(day);
      await wb.put(sKey, {
        'date': istDateStr(day),
        'status': 'completed',
        'type': 'workout', // non-rest, but NO workout_name
      });

      // 4. Derive — name must come from wlog_<date>, not the empty schedule.
      final derived = derivePastDayLog(sKey, '');
      expect(derived.name, 'Push Day',
          reason: 'Name must derive from the wlog_<date> session row, not the '
              'name-less restored schedule row (would have been "Workout").');
      expect(derived.exercises.length, 2,
          reason: 'Exercises must come from the canonical exlog reader.');
      final names = derived.exercises
          .map((e) => e['exercise_name'] as String?)
          .toSet();
      expect(names, containsAll(<String>['Bench Press', 'Overhead Press']));
    });

    test('planned-but-not-logged day falls back gracefully (no logs)',
        () async {
      final day = DateTime.now().subtract(const Duration(days: 39));
      final wb = HiveService.instance.workoutBox;
      final sKey = WorkoutWriteService.scheduleKey(day);
      await wb.put(sKey, {
        'date': istDateStr(day),
        'status': 'planned',
        'type': 'workout',
      });

      final derived = derivePastDayLog(sKey, '');
      expect(derived.exercises, isEmpty);
      // No wlog, no schedule name, no fallback → generic label.
      expect(derived.name, 'Workout');
    });

    test('schedule name is used when no wlog session row exists', () async {
      final day = DateTime.now().subtract(const Duration(days: 38));
      final wb = HiveService.instance.workoutBox;
      final sKey = WorkoutWriteService.scheduleKey(day);
      await wb.put(sKey, {
        'date': istDateStr(day),
        'status': 'completed',
        'type': 'custom_template',
        'workout_name': 'Leg Day A',
      });

      // fallbackName mirrors what the widget passes (entry.workoutName).
      final derived = derivePastDayLog(sKey, 'Leg Day A');
      expect(derived.name, 'Leg Day A');
    });
  });
}
