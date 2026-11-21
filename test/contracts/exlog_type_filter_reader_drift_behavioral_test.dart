// Behavioral contract: readers of `exlog_*` rows must not filter on the `type`
// field. Only the cloud-restore writer stamps `type: 'exercise_log'`;
// `WorkoutWriteService.logExercise` (the device writer) never does. Three
// readers filtered on it (FINISH PR scan, BadgeService PR count, lifetime
// volume) and so never saw a device-logged row. Same drift class as
// graduationStatsProvider (diagnose 89d56c).
//
// Writers: WorkoutWriteService.logExercise (real Hive) + hand-built rows.
// Readers: WorkoutReadService.exlogRows, BadgeService.checkAll /
//          countBeatenPrs, ActiveWorkoutNotifier.completeWorkout (PR scan ->
//          state.detectedPRs), WorkoutRepository.getAllExerciseLogKeysForLifetimeSum.
//
// Run: TZ=Asia/Kolkata flutter test test/contracts/exlog_type_filter_reader_drift_behavioral_test.dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/badge_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_read_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/widgets/compass_form_sheet.dart'
    show utcDateFromIstDateStr;
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/shared/models/achievement_badge.dart';

import '../helpers/hive_test_setup.dart';

class _SeededNotifier extends ActiveWorkoutNotifier {
  _SeededNotifier(this.seed);
  final ActiveWorkoutData seed;
  @override
  ActiveWorkoutData build() => seed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    dir = await setUpHiveForTests();
    SyncService.pausedForSimulation = true;
  });

  tearDown(() async {
    SyncService.pausedForSimulation = false;
    resetTestClock();
    await tearDownHiveForTests(dir);
  });

  DateTime day(String ist) => utcDateFromIstDateStr(ist)!;

  Future<void> deviceLog(String name, String ist, List<ExerciseSet> sets,
      {String? hint}) async {
    final r = await WorkoutWriteService.instance.logExercise(
      date: day(ist),
      exerciseName: name,
      sets: sets,
      source: WriteSource.activeWorkout,
      loggingTypeHint: hint,
    );
    expect(r.success, isTrue, reason: r.errorMessage);
  }

  ExerciseSet set_(double kg, int reps) => ExerciseSet(
      weightKg: kg,
      reps: reps,
      loggedAtMs: DateTime.now().millisecondsSinceEpoch);

  Map<String, dynamic> row(String name, String date, double kg,
          {bool? isPr, List<Map<String, dynamic>>? sets}) =>
      {
        'exercise_name': name,
        'date': date,
        'weight_kg': kg,
        if (isPr != null) 'is_pr': isPr,
        if (sets != null) 'sets': sets,
      };

  group('WorkoutReadService.exlogRows (the one key predicate)', () {
    test('skips non-exlog keys and non-Map values; returns copies', () async {
      final box = HiveService.instance.workoutBox;
      await box.put('exlog_2026-03-01_aaaaaaaa', {'exercise_name': 'A'});
      await box.put('exlog_2026-03-01_bbbbbbbb', 'not a map');
      await box.put('other_2026-03-01', {
        'exercise_name': 'B',
        'type': 'exercise_log',
      });
      final rows = WorkoutReadService.exlogRows(box).toList();
      expect(rows.length, 1);
      expect(rows.single['exercise_name'], 'A');
      rows.single['exercise_name'] = 'mutated';
      expect((box.get('exlog_2026-03-01_aaaaaaaa') as Map)['exercise_name'],
          'A');
    });
  });

  group('BadgeService.countBeatenPrs (pure)', () {
    test('first-ever log gives 0; a later heavier log gives 1', () {
      expect(
          BadgeService.countBeatenPrs([row('Bench', '2026-03-01', 100)]), 0);
      expect(
          BadgeService.countBeatenPrs([
            row('Bench', '2026-03-01', 100),
            row('Bench', '2026-03-02', 110),
          ]),
          1);
    });

    test('restore-shaped row (type, no source) counts like a device row', () {
      final restored = row('Bench', '2026-03-02', 110)
        ..['type'] = 'exercise_log';
      expect(
          BadgeService.countBeatenPrs(
              [row('Bench', '2026-03-01', 100), restored]),
          1);
    });

    test('an earlier 0 kg row then a weighted row gives 0', () {
      expect(
          BadgeService.countBeatenPrs([
            row('Pushup', '2026-03-01', 0),
            row('Pushup', '2026-03-02', 20),
          ]),
          0);
    });

    test('two different names do not earn each other an earlier row', () {
      expect(
          BadgeService.countBeatenPrs([
            row('Bench', '2026-03-01', 100),
            row('Squat', '2026-03-02', 140),
          ]),
          0);
    });

    test('a same-date earlier row does not count', () {
      expect(
          BadgeService.countBeatenPrs([
            row('Bench', '2026-03-02', 100),
            row('Bench', '2026-03-02', 110),
          ]),
          0);
    });

    test('a later LIGHTER log gives 0', () {
      expect(
          BadgeService.countBeatenPrs([
            row('Bench', '2026-03-01', 100),
            row('Bench', '2026-03-02', 90),
          ]),
          0);
    });

    test('stale is_pr: flagged row with an earlier heavier row gives 0; '
        'unflagged row heavier than every earlier row gives 1', () {
      expect(
          BadgeService.countBeatenPrs([
            row('Bench', '2026-03-01', 120),
            row('Bench', '2026-03-02', 100, isPr: true),
          ]),
          0);
      expect(
          BadgeService.countBeatenPrs([
            row('Bench', '2026-03-01', 100),
            row('Bench', '2026-03-02', 110, isPr: false),
          ]),
          1);
    });

    test('the name key trims and lower-cases', () {
      expect(
          BadgeService.countBeatenPrs([
            row('bench press', '2026-03-01', 100),
            row('Bench Press ', '2026-03-02', 110),
          ]),
          1);
    });

    test('a row without a date is skipped', () {
      expect(
          BadgeService.countBeatenPrs([
            {'exercise_name': 'Bench', 'weight_kg': 200.0},
            row('Bench', '2026-03-02', 110),
          ]),
          0);
    });
  });

  group('BadgeService.checkAll (device-written rows, real Hive)', () {
    test('a heavier second device log unlocks firstPr', () async {
      await deviceLog('Bench Press', '2026-03-02', [set_(100, 8)]);
      await deviceLog('Bench Press', '2026-03-03', [set_(110, 8)]);
      final box = HiveService.instance.workoutBox;
      for (final k in box.keys.where((k) => '$k'.startsWith('exlog_'))) {
        expect((box.get(k) as Map).containsKey('type'), isFalse,
            reason: 'the device writer never stamps `type`');
      }
      expect(BadgeService.instance.checkAll(), contains(BadgeId.firstPr));
    });

    test('a single first-ever log does not unlock firstPr', () async {
      await deviceLog('Bench Press', '2026-03-02', [set_(100, 8)]);
      expect(BadgeService.instance.checkAll(),
          isNot(contains(BadgeId.firstPr)));
    });

    test('a non-exlog key carrying type + is_pr does not unlock it',
        () async {
      await HiveService.instance.workoutBox.put('streak_junk', {
        'type': 'exercise_log',
        'is_pr': true,
        'exercise_name': 'Bench Press',
        'date': '2026-03-03',
        'weight_kg': 200.0,
      });
      await deviceLog('Bench Press', '2026-03-02', [set_(100, 8)]);
      expect(BadgeService.instance.checkAll(),
          isNot(contains(BadgeId.firstPr)));
    });

    test('stale is_pr=true on a lighter later row does not unlock it',
        () async {
      await deviceLog('Bench Press', '2026-03-02', [set_(120, 8)]);
      await deviceLog('Bench Press', '2026-03-03', [set_(100, 8)]);
      // Force the stale flag the way a back-filled earlier row leaves it.
      final box = HiveService.instance.workoutBox;
      for (final k in box.keys.where((k) => '$k'.startsWith('exlog_'))) {
        final m = Map<String, dynamic>.from(box.get(k) as Map);
        m['is_pr'] = true;
        await box.put(k, m);
      }
      expect(BadgeService.instance.checkAll(),
          isNot(contains(BadgeId.firstPr)));
    });
  });

  group('FINISH PR scan (completeWorkout -> detectedPRs)', () {
    Future<List<String>> finish(String name, String loggingType, int reps,
        double weight) async {
      final c = ProviderContainer(overrides: [
        authUserIdTokenProvider.overrideWithValue('u'),
        activeWorkoutProvider.overrideWith(() => _SeededNotifier(
              ActiveWorkoutData(
                exercises: [ExerciseData(name: name, loggingType: loggingType)],
                checkedSets: const {'0-0': true},
                setInputValues: {
                  '0-0': SetInputValues(weight: weight, reps: reps)
                },
              ),
            )),
      ]);
      addTearDown(c.dispose);
      await c.read(activeWorkoutProvider.notifier).completeWorkout();
      return c.read(activeWorkoutProvider).detectedPRs;
    }

    String past() =>
        istDateStr(DateTime.now().subtract(const Duration(days: 3)));

    test('110 kg after a logged 100 kg yields the PR line; 100 does not',
        () async {
      await deviceLog('Bench Press', past(), [set_(100, 8)]);
      expect(await finish('Bench Press', 'weight_reps', 8, 110),
          ['Bench Press: 110.0kg (was 100.0kg)']);
    });

    test('a same-day coach row is not "earlier": today 100 kg, no history, '
        'session 105 kg -> no PR line', () async {
      await deviceLog('Bench Press', istTodayStr(), [set_(100, 8)]);
      expect(await finish('Bench Press', 'weight_reps', 8, 105), isEmpty);
    });

    test('earlier-day 100 kg plus a same-day 100 kg coach row, session 105 '
        'kg -> PR (was 100.0kg)', () async {
      await deviceLog('Bench Press', past(), [set_(100, 8)]);
      await deviceLog('Bench Press', istTodayStr(), [set_(100, 8)]);
      expect(await finish('Bench Press', 'weight_reps', 8, 105),
          ['Bench Press: 105.0kg (was 100.0kg)']);
    });

    test('mirror: earlier-day 100 kg plus a same-day 110 kg row, session 105 '
        'kg -> PR (was 100.0kg); the same-day row is ignored', () async {
      await deviceLog('Bench Press', past(), [set_(100, 8)]);
      await deviceLog('Bench Press', istTodayStr(), [set_(110, 8)]);
      expect(await finish('Bench Press', 'weight_reps', 8, 105),
          ['Bench Press: 105.0kg (was 100.0kg)']);
    });

    test('100 kg after a logged 100 kg yields none', () async {
      await deviceLog('Bench Press', past(), [set_(100, 8)]);
      expect(await finish('Bench Press', 'weight_reps', 8, 100), isEmpty);
    });

    test('trailing-space name matches the earlier row keyed lower-case',
        () async {
      await deviceLog('bench press', past(), [set_(100, 8)]);
      expect(await finish('Bench Press ', 'weight_reps', 8, 110),
          ['Bench Press : 110.0kg (was 100.0kg)']);
    });

    test('per-set weight: hand-built row whose row-level weight is lower '
        'than its per-set max', () async {
      // HAND-BUILT: writer rows have row weight == per-set max, so only a
      // hand-built row can tell the two definitions apart.
      await HiveService.instance.workoutBox
          .put('exlog_${past()}_deadbeef', {
        'exercise_name': 'Bench Press',
        'date': past(),
        'weight_kg': 50.0,
        'sets': [
          {'weight_kg': 100.0, 'reps': 8},
          {'weight_kg': 50.0, 'reps': 8},
        ],
      });
      expect(await finish('Bench Press', 'weight_reps', 8, 80), isEmpty);
    });

    test('bodyweight 12/10/8 earlier: 12 today is no PR, 13 is "(was 12 reps)"',
        () async {
      await deviceLog('Push Up', past(),
          [set_(0, 12), set_(0, 10), set_(0, 8)].asMap().entries.map((e) {
        return ExerciseSet(
            weightKg: 0,
            reps: e.value.reps,
            loggedAtMs: DateTime.now().millisecondsSinceEpoch + e.key * 1000);
      }).toList(), hint: 'bodyweight_reps');
      expect(await finish('Push Up', 'bodyweight_reps', 12, 0), isEmpty);
    });

    test('bodyweight 13 today after 12/10/8 gives the PR line', () async {
      await deviceLog('Push Up', past(),
          [12, 10, 8].asMap().entries.map((e) {
        return ExerciseSet(
            weightKg: 0,
            reps: e.value,
            loggedAtMs: DateTime.now().millisecondsSinceEpoch + e.key * 1000);
      }).toList(), hint: 'bodyweight_reps');
      expect(await finish('Push Up', 'bodyweight_reps', 13, 0),
          ['Push Up: 13 reps (was 12 reps)']);
    });

    test('a row with no per-set list still uses the stored-best / average '
        'fallbacks', () async {
      await HiveService.instance.workoutBox
          .put('exlog_${past()}_cafebabe', {
        'exercise_name': 'Dip',
        'date': past(),
        'set_number': 3,
        'reps_completed': 30,
      });
      // average 30 ~/ 3 = 10: 11 reps beats it.
      expect(await finish('Dip', 'bodyweight_reps', 11, 0),
          ['Dip: 11 reps (was 10 reps)']);
    });
  });

  group('lifetime volume', () {
    test('returns every volume_kg for device-shaped and restore-shaped rows',
        () async {
      final box = HiveService.instance.workoutBox;
      await box.put('exlog_2026-03-01_11111111', {
        'exercise_name': 'Bench Press',
        'date': '2026-03-01',
        'volume_kg': 800.0,
      });
      await box.put('exlog_2026-03-01_22222222', {
        'type': 'exercise_log',
        'exercise_name': 'Squat',
        'date': '2026-03-01',
        'volume_kg': 1200.0,
      });
      await box.put('wlog_2026-03-01', {'volume_kg': 99999.0});
      final out =
          WorkoutRepository.instance.getAllExerciseLogKeysForLifetimeSum();
      expect(out..sort(), [800.0, 1200.0]);
    });
  });
}
