// SoT concept: coach_day_completion_rule (docs/sot_registry.yaml).
//
// Gate 9 (scripts/check_writeservice_contracts.dart) requires every
// hive-key-prefixed SoT concept to ship a same-named writer→reader contract
// test. This is that test for `coach_day_completion_rule` (coach workout
// parity 1b, OI-490, diagnose 24e630): a Hive write through the production
// writers, then a read through the production readers.
//
//   WRITERS = CoachDayCompletion.completeOnTap (door trainTap) — through
//             WorkoutWriteService.markCompleted, flips schedule_<date> to
//             status 'completed' + completed_via 'train_tap' + the plan
//             day's name; CompletionPromptStore.write / resolve — the
//             coachBox completion_prompt_<date> row.
//   READERS = WorkoutScheduleReadService.rawScheduleRow → decideCoachDay
//             (the rule reads the completed row as alreadyDone),
//             CoachDayCompletion.canCompleteOnTap (Train's button gate),
//             WorkoutReadService.datesWithExerciseLogs (Train's LOGGED rows),
//             and the prompt row's fields as the completion tile reads them.
//
// The full door-by-door behaviour (card, typed backstop, tile, Train; rest,
// moved, past and future days) is coach_day_completion_behavioral_test.dart.
//
// Pure Hive (path_provider-mocked), no Supabase. Setup mirrors
// coach_derived_completion_writer_to_reader_test.dart.
//
// Run: TZ=Asia/Kolkata flutter test test/contracts/coach_day_completion_rule_writer_to_reader_test.dart

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/completion_prompt_store.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_read_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/train/services/coach_day_completion.dart';
import 'package:icanbefitter/features/train/services/workout_completion_bookkeeping.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp
        .createTemp('test_coach_day_completion_rule');
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
      HiveService.coachBoxName,
      HiveService.configBoxName,
      HiveService.migrationBoxName,
      'workoutBox_aaaaaaaa',
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
    await HiveUserSession.openForUser('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
    await HiveService.instance.userBox
        .put('progress', {'total_workouts_done': 0});
    SyncService.pausedForSimulation = true;
  });

  tearDown(() async {
    SyncService.pausedForSimulation = false;
    await HiveUserSession.closeAll();
  });

  final today = utcDateFromIstDateStr(istTodayStr())!;
  final todayStr = istTodayStr();

  Future<void> seedDay(List<String> exercises, {String type = 'workout'}) =>
      HiveService.instance.workoutBox
          .put(WorkoutWriteService.scheduleKey(today), {
        'date': todayStr,
        'workout_name': 'Push Day',
        'status': 'planned',
        'type': type,
        'exercises': [
          for (final e in exercises) {'exercise_name': e}
        ],
      });

  Future<void> coachLog(String name) async {
    final r = await WorkoutWriteService.instance.logExercise(
      date: today,
      exerciseName: name,
      sets: [
        ExerciseSet(
            weightKg: 60,
            reps: 8,
            loggedAtMs: DateTime.now().millisecondsSinceEpoch),
      ],
      source: WriteSource.aiCoach,
    );
    expect(r.success, isTrue, reason: r.errorMessage);
  }

  CoachDayDecision decide() {
    final row = WorkoutScheduleReadService.instance.rawScheduleRow(today);
    return decideCoachDay(
      rawRow: row,
      loggedCount: row == null ? 0 : loggedPlannedExerciseCount(today, row),
      hasWlog: HiveService.instance.workoutBox
          .get(WorkoutWriteService.wlogKey(today)) is Map,
      dateStr: todayStr,
      istToday: todayStr,
    );
  }

  group('coach_day_completion_rule — writer→reader contract', () {
    test(
        'a partial day: the coach log is read by Train, the rule asks, and '
        "Train's tap writes a completed row the rule then reads as done",
        () async {
      await seedDay(['Bench Press', 'Overhead Press']);
      await coachLog('Bench Press');

      // Readers before the tap.
      expect(WorkoutReadService.instance.datesWithExerciseLogs(),
          contains(todayStr));
      expect(decide(), CoachDayDecision.askToComplete);
      expect(CoachDayCompletion.instance.canCompleteOnTap(todayStr), isTrue);

      // Writer.
      final r = await CoachDayCompletion.instance
          .completeOnTap(date: todayStr, door: CompletionDoor.trainTap);
      expect(r, CoachTapResult.completed);

      // Readers after the tap: the stored row and the rule agree.
      final row = WorkoutScheduleReadService.instance.rawScheduleRow(today)!;
      expect(row['status'], 'completed');
      expect(row['completed_via'], 'train_tap');
      expect(row['workout_name'], 'Push Day');
      expect(decide(), CoachDayDecision.alreadyDone);
      expect(CoachDayCompletion.instance.canCompleteOnTap(todayStr), isFalse);
    });

    test('a rest day with a coach log: the tap writes nothing', () async {
      await seedDay(const [], type: 'rest');
      await coachLog('Bench Press');

      expect(decide(), CoachDayDecision.rest);
      expect(CoachDayCompletion.instance.canCompleteOnTap(todayStr), isFalse);
      final r = await CoachDayCompletion.instance
          .completeOnTap(date: todayStr, door: CompletionDoor.trainTap);
      expect(r, CoachTapResult.refusedNotCountable);
      final row = WorkoutScheduleReadService.instance.rawScheduleRow(today)!;
      expect(row['status'], 'planned');
      expect(row.containsKey('completed_via'), isFalse);
    });

    test(
        'the prompt row: write is read back with its counts; a later write '
        'resolves the older row; resolve stamps resolved_at', () async {
      final store = CompletionPromptStore.instance;
      final box = HiveService.instance.coachBox;
      const older = '2026-01-01';

      await store.write(dateStr: older, plannedCount: 4, loggedCount: 1);
      final first = box.get(CompletionPromptStore.keyFor(older)) as Map;
      expect(first['kind'], 'completion_prompt');
      expect(first['date'], older);
      expect(first['planned_count'], 4);
      expect(first['logged_count'], 1);
      expect(first['resolved_at'], isNull);

      await store.write(dateStr: todayStr, plannedCount: 5, loggedCount: 2);
      expect(
          (box.get(CompletionPromptStore.keyFor(older)) as Map)['resolved_at'],
          isNotNull);
      final current = box.get(CompletionPromptStore.keyFor(todayStr)) as Map;
      expect(current['planned_count'], 5);
      expect(current['logged_count'], 2);
      expect(current['resolved_at'], isNull);

      await store.resolve(todayStr);
      expect(
          (box.get(CompletionPromptStore.keyFor(todayStr)) as Map)[
              'resolved_at'],
          isNotNull);
    });
  });
}
