// BEHAVIORAL CONTRACT TEST — Unit 0: session dating + Home START
//
// Covers two all-users bugs found while live-testing the free-tier Phase-1 wall.
//
// FIX 1 — back-dated workout logs (data corruption)
//   Writer:  lib/features/train/providers/train_provider.dart
//            completeWorkout → resolveSessionDate (pure, extracted for this test)
//   Before:  `state.workoutDay?.date ?? now` — and CurrentPlanData.todayWorkout's
//            fallback can hand back a PAST day, so a user completing a missed
//            workout wrote exlog_<pastDate>/wlog_<pastDate> and marked the PAST
//            schedule row completed, while today's row stayed `planned` forever.
//   Assert:  a session is NEVER dated to a non-today date.
//
//   These asserts FAIL if the clamp is reverted to `scheduledDate ?? now`:
//   case "stale scheduled day" would return the past date instead of today.
//
// FIX 2 — Home's START dead-ended
//   Writer:  lib/features/home/screens/home_screen.dart (onStart)
//   Before:  bare `context.go('/train/active-workout')` with no startWorkout(),
//            so ActiveWorkoutScreen mounted with a null workoutDay and rendered
//            "No workout in progress".
//   Assert:  workoutDayForDate() yields a startable day from the SAME schedule
//            row Home renders (getScheduleForDate), and correctly declines for
//            rest / empty / absent rows. Plus the wiring is pinned by grep.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/date_utils.dart' show formatDateKey;
import 'package:icanbefitter/features/train/providers/train_provider.dart';
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
  const fakeUserId = 'aaaaaaaa-bbbb-cccc-dddd-000000000042';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('unit0_behavioral_');
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

  setUp(() async {
    await HiveUserSession.openForUser(fakeUserId);
  });

  tearDown(() async {
    final box = HiveService.instance.workoutBox;
    for (final k in box.keys.toList()) {
      if (k is String && k.startsWith('schedule_')) await box.delete(k);
    }
  });

  // ── FIX 1 ───────────────────────────────────────────────────────────
  group('resolveSessionDate — a session is dated when it was PERFORMED', () {
    final now = DateTime(2026, 7, 20, 19, 30);

    test('STALE scheduled day (the bug) → today, never the past date', () {
      // CurrentPlanData.todayWorkout's fallback returns "first non-rest,
      // non-done workout in the current week" — a PAST day when today has no
      // match. Before the fix this date flowed straight into logExercise(),
      // markCompleted() and the streak key.
      final stale = DateTime(2026, 7, 14, 8, 0); // 6 days earlier
      final resolved = resolveSessionDate(scheduledDate: stale, now: now);

      expect(formatDateKey(resolved), formatDateKey(now));
      expect(formatDateKey(resolved), isNot(formatDateKey(stale)),
          reason: 'a completed session must never be written to a past date');
    });

    test('scheduled day IS today → unchanged (healthy path byte-identical)',
        () {
      final todayScheduled = DateTime(2026, 7, 20, 6, 0);
      final resolved =
          resolveSessionDate(scheduledDate: todayScheduled, now: now);

      expect(resolved, same(todayScheduled),
          reason: 'the normal path must be untouched by the clamp');
    });

    test('null scheduled day → today', () {
      expect(formatDateKey(resolveSessionDate(scheduledDate: null, now: now)),
          formatDateKey(now));
    });

    test('FUTURE scheduled day → today', () {
      final future = DateTime(2026, 8, 3, 8, 0);
      expect(
          formatDateKey(resolveSessionDate(scheduledDate: future, now: now)),
          formatDateKey(now));
    });
  });

  // ── FIX 2 ───────────────────────────────────────────────────────────
  group('workoutDayForDate — Home can start what Home displayed', () {
    Future<void> seed(DateTime date, Map<String, dynamic> entry) =>
        WorkoutWriteService.instance.upsertScheduled(
          date: date,
          entry: entry,
          source: WriteSource.schedSwap,
        );

    test('workout row → a startable day built from THAT date\'s row', () async {
      final today = DateTime(2026, 7, 20);
      await seed(today, {
        'date': formatDateKey(today),
        'type': 'workout',
        'status': 'planned',
        'workout_name': 'Push',
        'workout_focus': 'Chest, shoulders, triceps',
        'week': 2,
        'day_of_week': 0,
        'exercises': [
          {'name': 'Barbell Bench Press', 'sets': '4', 'reps': '8', 'rest': 120},
          {'name': 'Lateral Raise', 'sets': '3', 'reps': '12', 'rest': 60},
        ],
      });

      final day = workoutDayForDate(today);

      expect(day, isNotNull,
          reason: 'Home rendered a workout, so START must have a day to begin');
      expect(day!.name, 'PUSH');
      expect(day.exercises.length, 2);
      expect(day.isRest, isFalse);
      // The date must be the requested one — this is what stops Home starting a
      // different (fallback) day than the card showed.
      expect(formatDateKey(day.date!), formatDateKey(today));
    });

    test('rest row → null (no START offered)', () async {
      final today = DateTime(2026, 7, 21);
      await seed(today, {
        'date': formatDateKey(today),
        'type': 'rest',
        'status': 'rest',
        'workout_name': 'Rest Day',
        'exercises': <dynamic>[],
      });

      expect(workoutDayForDate(today), isNull);
    });

    test('workout row with no exercises → null', () async {
      final today = DateTime(2026, 7, 22);
      await seed(today, {
        'date': formatDateKey(today),
        'type': 'workout',
        'status': 'planned',
        'workout_name': 'Empty',
        'exercises': <dynamic>[],
      });

      expect(workoutDayForDate(today), isNull);
    });

    test('no row at all → null', () {
      expect(workoutDayForDate(DateTime(2026, 7, 23)), isNull);
    });
  });

  // ── FIX 2 wiring (presence — the behavioral half is above) ──────────
  test('Home START routes through the canonical start path, not bare nav', () {
    final src = File('lib/features/home/screens/home_screen.dart')
        .readAsStringSync()
        // strip comments so the prose above onStart cannot satisfy the grep
        // (feedback_source_grep_strip_comments_first)
        .replaceAll(RegExp(r'//.*'), '')
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');

    expect(src.contains('beginWorkoutWithReadiness'), isTrue,
        reason: 'Home START must start the workout, not only navigate');
    expect(src.contains('workoutDayForDate'), isTrue,
        reason: 'the started day must come from the rendered schedule row');
    expect(
        src.contains("onStart: () => context.go('/train/active-workout')"),
        isFalse,
        reason: 'the bare-navigation dead end must not return');
  });
}
