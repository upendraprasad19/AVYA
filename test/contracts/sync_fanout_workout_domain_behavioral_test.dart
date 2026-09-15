// Tech-debt audit 2026-05-20 finding T3.1 — BEHAVIORAL contract for the
// `sync_fanout_workout_domain` SoT registry concept.
//
// Concept: every WriteService write in the workout domain produces a
// matched pair of Hive entries (per-exercise `exlog_*` AND per-session
// `wlog_*` for the same IST date) so the downstream
// `SyncService.syncWorkoutData()` fan-out has both the exercise-level
// and session-level rows to push to cloud. Failure mode this test
// prevents: a regression in `WorkoutWriteService.logExercise` or
// `WorkoutWriteService.markCompleted` that silently writes only one of
// the two Hive entries (e.g. forgets the `wlog_*` upsert), leaving the
// cloud fan-out with nothing to push at the session tier → reinstall
// loses the workout entirely.
//
// Bug class prevented (cites
// `feedback_writer_reader_field_drift_recurring.md`): per-date
// writer/reader contract drift between exlog (per-exercise) and wlog
// (per-session) tiers. Source-grep alone cannot catch a regression
// where the writer's Hive `put` call is renamed but still touches the
// SAME Hive box — only a behavioral check that the right keys land
// catches it. Companion to source-grep
// `test/contracts/sync_fanout_contract_test.dart`.
//
// Run: flutter test test/contracts/sync_fanout_workout_domain_behavioral_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
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

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir =
        Directory.systemTemp.createTempSync('sync_fanout_workout_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Hive.init(tempDir.path);
    // Open shared boxes the WriteService transitively touches via
    // SyncService's no-op short-circuit path (currentUser == null →
    // returns without reading user-scoped boxes, but the call chain
    // still constructs HiveService references).
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
    await HiveUserSession.closeAll();
    const fakeUserId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    await HiveUserSession.openForUser(fakeUserId);
    await HiveService.instance.workoutBox.clear();
  });

  group('sync_fanout_workout_domain — behavioral contract', () {
    test(
        'logExercise produces an exlog_<date>_<hash> entry with the correct '
        'workout_log_id pointing at wlog_<date>', () async {
      final today = DateTime.utc(2026, 5, 20, 6, 0); // IST 11:30 → 2026-05-20
      final result =
          await WorkoutWriteService.instance.logExercise(
        date: today,
        exerciseName: 'Bench Press',
        sets: [
          const ExerciseSet(weightKg: 60, reps: 10),
          const ExerciseSet(weightKg: 60, reps: 8),
        ],
        source: WriteSource.activeWorkout,
      );

      expect(result.success, isTrue,
          reason: 'logExercise must succeed: ${result.errorMessage}');

      final box = HiveService.instance.workoutBox;
      final exlogKey = WorkoutWriteService.exlogKey(today, 'Bench Press');
      final wlogKey = WorkoutWriteService.wlogKey(today);

      // Per-exercise tier — MUST be written.
      final exlog = box.get(exlogKey);
      expect(exlog, isA<Map>(),
          reason: 'exlog_<date>_<hash> Hive entry must exist after '
              'logExercise; failure means writer forgot the per-exercise '
              'upsert and cloud fan-out has nothing to push.');
      final exMap = (exlog as Map);
      expect(exMap['exercise_name'], 'Bench Press');
      expect(exMap['set_number'], 2);
      expect(exMap['date'], WorkoutWriteService.istDateStr(today));
      // workout_log_id MUST point at the wlog key so receipt + cloud
      // can join the two tiers.
      expect(exMap['workout_log_id'], wlogKey,
          reason: 'exlog row must carry workout_log_id = wlog_<date> so '
              'receipt rendering + cloud join logic can pair per-exercise '
              'rows with their session.');
    });

    test(
        'markCompleted produces the wlog_<date> session tier paired with '
        'the schedule_<date> entry — completes the two-key fan-out',
        () async {
      final today = DateTime.utc(2026, 5, 20, 6, 0);

      // Log an exercise first (per-exercise tier).
      await WorkoutWriteService.instance.logExercise(
        date: today,
        exerciseName: 'Squat',
        sets: const [ExerciseSet(weightKg: 80, reps: 5)],
        source: WriteSource.activeWorkout,
      );

      // Now mark the session complete (session tier + schedule tier).
      final result = await WorkoutWriteService.instance.markCompleted(
        date: today,
        workoutName: 'Leg Day',
        durationSec: 1800,
      );
      expect(result.success, isTrue);

      final box = HiveService.instance.workoutBox;
      final wlogKey = WorkoutWriteService.wlogKey(today);
      final scheduleKey = WorkoutWriteService.scheduleKey(today);

      // Session tier — MUST be present.
      final wlog = box.get(wlogKey);
      expect(wlog, isA<Map>(),
          reason: 'markCompleted must write wlog_<date> so cloud fan-out '
              'has the session row to push (workout_logs table).');
      expect((wlog as Map)['workout_name'], 'Leg Day');
      expect(wlog['duration_seconds'], 1800);

      // Schedule tier — completion stamps the schedule entry.
      final sched = box.get(scheduleKey);
      expect(sched, isA<Map>(),
          reason: 'markCompleted must upsert schedule_<date> with '
              'status=completed; missing here means the workout_schedule_'
              'completions table will never receive this session.');
      expect((sched as Map)['status'], 'completed');
    });

    test(
        'exercise_log_index_<date> is appended on logExercise — required '
        'by the exlog reader fast-path', () async {
      final today = DateTime.utc(2026, 5, 20, 6, 0);
      final dateStr = WorkoutWriteService.istDateStr(today);

      await WorkoutWriteService.instance.logExercise(
        date: today,
        exerciseName: 'Deadlift',
        sets: const [ExerciseSet(weightKg: 100, reps: 5)],
        source: WriteSource.activeWorkout,
      );

      final box = HiveService.instance.workoutBox;
      final indexKey = 'exercise_log_index_$dateStr';
      final idx = box.get(indexKey);
      expect(idx, isA<List>(),
          reason: 'exercise_log_index_<date> MUST be a List<String> after '
              'logExercise — readers (workout_receipt_card et al.) use it as '
              'the fast-path before falling back to a full box scan.');
      expect((idx as List).cast<String>(),
          contains(WorkoutWriteService.exlogKey(today, 'Deadlift')));
    });

    test(
        'multiple exercises on the same date share the same wlog_<date> '
        'session anchor — fan-out groups per session, not per exercise',
        () async {
      final today = DateTime.utc(2026, 5, 20, 6, 0);
      final wlogKey = WorkoutWriteService.wlogKey(today);

      await WorkoutWriteService.instance.logExercise(
        date: today,
        exerciseName: 'Push Up',
        sets: const [ExerciseSet(weightKg: 0, reps: 15)],
        source: WriteSource.activeWorkout,
      );
      await WorkoutWriteService.instance.logExercise(
        date: today,
        exerciseName: 'Pull Up',
        sets: const [ExerciseSet(weightKg: 0, reps: 10)],
        source: WriteSource.activeWorkout,
      );

      final box = HiveService.instance.workoutBox;
      final pushUpKey = WorkoutWriteService.exlogKey(today, 'Push Up');
      final pullUpKey = WorkoutWriteService.exlogKey(today, 'Pull Up');

      expect((box.get(pushUpKey) as Map)['workout_log_id'], wlogKey);
      expect((box.get(pullUpKey) as Map)['workout_log_id'], wlogKey);
    });
  });
}
