// BEHAVIORAL CONTRACT TEST — workout_read_service
//
// Concept:   workout_read_service
// Writer:    lib/core/services/workout_write_service.dart (logExercise)
// Reader 1:  lib/core/services/workout_read_service.dart (bestPerSetReps)
// Reader 2:  lib/features/train/repositories/workout_repository.dart (loadAllExercisePRs)
//
// Assert:
//   Log 3 sets of the SAME bodyweight exercise (reps 8/10/7) on one date.
//   WorkoutReadService.bestPerSetReps MUST return MAX=10 (not sum=25, not avg≈8).
//   WorkoutRepository.loadAllExercisePRs MUST surface 10 for that exercise.
//   Both asserts FAIL if the reader uses top-level reps_completed (SUM=25) instead
//   of iterating the per-set sets[] array.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/workout_read_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart'
    show ExercisePR, WorkoutRepository;
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
  const fakeUserId = 'bbbbbbbb-cccc-dddd-eeee-000000000001';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('wrs_behavioral_');
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
    await HiveUserSession.closeAll();
  });

  test(
    'bestPerSetReps returns MAX reps across sets (not sum/avg), loadAllExercisePRs surfaces MAX',
    () async {
      const exerciseName = 'Pull Up Test Exercise';
      final logDate = DateTime(2026, 6, 10);

      // Log 3 sets with different reps: 8, 10, 7.
      // SUM = 25, MAX = 10.  The reader must return MAX=10.
      for (final reps in [8, 10, 7]) {
        await WorkoutWriteService.instance.logExercise(
          date: logDate,
          exerciseName: exerciseName,
          sets: [ExerciseSet(weightKg: 0.0, reps: reps)],
          source: WriteSource.activeWorkout,
        );
      }

      // Retrieve the stored exlog entry directly.
      final box = HiveService.instance.workoutBox;
      final key = WorkoutWriteService.exlogKey(logDate, exerciseName);
      final raw = box.get(key);
      expect(raw, isNotNull, reason: 'exlog entry must exist after logExercise');
      final log = Map<String, dynamic>.from(raw as Map);

      // Assert bestPerSetReps — MUST be 10 (MAX), not 25 (SUM).
      final best = WorkoutReadService.bestPerSetReps(log);
      expect(
        best,
        equals(10),
        reason:
            'bestPerSetReps must return MAX reps (10) across sets, not SUM (25) '
            'or average. If this returns 25 or ~8, the reader is using reps_completed '
            '(SUM field) instead of iterating sets[].',
      );

      // Assert sets[] was written and contains 3 entries.
      final sets = log['sets'] as List?;
      expect(sets, isNotNull, reason: 'sets[] must be populated by logExercise');
      expect(sets!.length, equals(3),
          reason: 'all 3 logged sets must be merged into sets[]');

      // Assert loadAllExercisePRs surfaces the correct (MAX) PR value.
      // loadAllExercisePRs() returns List<ExercisePR> — find our exercise.
      final List<ExercisePR> prs =
          WorkoutRepository.instance.loadAllExercisePRs();
      final ExercisePR? pr = prs.cast<ExercisePR?>().firstWhere(
            (p) =>
                p != null &&
                p.exerciseName.toLowerCase() == exerciseName.toLowerCase(),
            orElse: () => null,
          );
      expect(
        pr,
        isNotNull,
        reason: 'loadAllExercisePRs must find the logged exercise',
      );
      // ExercisePR.bestValue is a double; for bodyweight_reps it holds the reps MAX.
      expect(
        pr!.bestValue.toInt(),
        equals(10),
        reason:
            'loadAllExercisePRs must surface MAX reps=10 (not SUM=25). '
            'If this fails, WorkoutRepository.loadAllExercisePRs is not delegating '
            'to WorkoutReadService.bestPerSetReps correctly.',
      );
      expect(
        pr.loggingType,
        equals('bodyweight_reps'),
        reason:
            'loggingType must be bodyweight_reps so the MAX-reps path is exercised',
      );
    },
  );
}
