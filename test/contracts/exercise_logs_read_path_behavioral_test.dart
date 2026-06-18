// BEHAVIORAL CONTRACT TEST — exercise_logs_read_path
//
// Concept:   exercise_logs_read_path
// Writer:    lib/core/services/workout_write_service.dart (logExercise)
// Reader:    lib/core/services/workout_read_service.dart (exerciseLogsForIstDate)
//
// Assert:
//   A log written at UTC 23:30 on 2026-05-19 (= IST 05:00 on 2026-05-20) MUST
//   appear under the IST date key '2026-05-20', NOT under the UTC key '2026-05-19'.
//
//   This is the canonical proof that the IST-keying contract holds end-to-end
//   through the real write→read path.  If istDateStr() were ever accidentally
//   replaced with a UTC formatter in the writer, this test fails.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/workout_read_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// ---------------------------------------------------------------------------
// Fake path provider
// ---------------------------------------------------------------------------

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;

  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;

  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

// ---------------------------------------------------------------------------

void main() {
  late Directory tempDir;
  const fakeUserId = 'aaaaaaaa-bbbb-cccc-dddd-000000000010';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir =
        Directory.systemTemp.createTempSync('exlog_ist_behavioral_');
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

  // -------------------------------------------------------------------------
  // Test — IST date key is used, NOT the UTC date key
  // -------------------------------------------------------------------------

  test(
    'exercise logged at UTC 23:30 (2026-05-19) appears under IST date 2026-05-20, not 2026-05-19',
    () async {
      // UTC 23:30 on 2026-05-19  →  IST 05:00 on 2026-05-20.
      // The writer must bucket this into the IST calendar day (2026-05-20).
      final utcTimestamp = DateTime.utc(2026, 5, 19, 23, 30);
      const exerciseName = 'Barbell Back Squat';

      // ACT — write via the canonical writer.
      await WorkoutWriteService.instance.logExercise(
        date: utcTimestamp,
        exerciseName: exerciseName,
        sets: const [
          ExerciseSet(weightKg: 80.0, reps: 5),
        ],
        source: WriteSource.activeWorkout,
      );

      // ASSERT — reader finds it on the IST day.
      final logsIst =
          WorkoutReadService.instance.exerciseLogsForIstDate('2026-05-20');
      expect(logsIst, isNotEmpty,
          reason:
              'exerciseLogsForIstDate("2026-05-20") must return the log written '
              'at UTC 23:30 on 2026-05-19 (= IST 05:00 on 2026-05-20)');

      final hasEntry = logsIst.any(
        (log) =>
            (log['exercise_name'] as String?)?.toLowerCase() ==
            exerciseName.toLowerCase(),
      );
      expect(hasEntry, isTrue,
          reason: 'The log must contain an entry for "$exerciseName"');

      // ASSERT — reader does NOT find it on the UTC day.
      final logsUtc =
          WorkoutReadService.instance.exerciseLogsForIstDate('2026-05-19');
      expect(logsUtc, isEmpty,
          reason:
              'exerciseLogsForIstDate("2026-05-19") must be empty — the log '
              'belongs to IST 2026-05-20, not the UTC calendar date 2026-05-19');
    },
  );
}
