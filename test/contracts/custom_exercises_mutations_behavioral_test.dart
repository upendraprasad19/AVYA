// BEHAVIORAL CONTRACT TEST — custom_exercises_mutations
//
// Concept:   custom_exercises_mutations
// Writer:    lib/features/train/repositories/workout_repository.dart
//            (createCustomExercise → WorkoutWriteService.upsertCustomExercise)
// Reader:    lib/shared/repositories/exercise_repository.dart
//            (getCustomExercises)
//
// Assert:
//   1. After createCustomExercise(...), getCustomExercises() returns the new entry.
//   2. The returned entry has type=='exercise' OR key starts with custom_exercise_.
//   3. The exercise name round-trips exactly (no trim drift).
//   4. Calling createCustomExercise twice with the same name throws
//      CreateCustomExerciseException (duplicate_name) — no silent overwrite.
//
//   These asserts FAIL if:
//   - upsertCustomExercise stops writing to customBox (or changes the box).
//   - getCustomExercises changes its filter logic (type field or key prefix).
//   - The key format 'custom_exercise_<millis>' changes and the prefix filter
//     no longer matches (writer/reader drift).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart'
    show CreateCustomExerciseException, WorkoutRepository;
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
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
  const fakeUserId = 'eeeeeeee-ffff-0000-1111-000000000004';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('cem_behavioral_');
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
    // Clean up custom exercises between tests.
    final box = HiveService.instance.customBox;
    final keysToRemove = box.keys
        .where((k) => k.toString().startsWith('custom_exercise_'))
        .toList();
    for (final k in keysToRemove) {
      await box.delete(k);
    }
    await HiveUserSession.closeAll();
  });

  // ── Test 1: createCustomExercise → getCustomExercises round-trip ─────────
  test(
    'createCustomExercise is visible to getCustomExercises after write',
    () async {
      const exerciseName = 'Archer Push Up Test';
      await WorkoutRepository.instance.createCustomExercise(
        name: exerciseName,
        category: 'Push',
        equipment: 'none',
        loggingType: 'bodyweight_reps',
        defaultSets: 3,
        defaultReps: 8,
      );

      final customs = ExerciseRepository.instance.getCustomExercises();

      final match = customs.where((e) =>
          (e['name'] as String?)?.toLowerCase() ==
          exerciseName.toLowerCase()).toList();

      expect(
        match,
        isNotEmpty,
        reason:
            'getCustomExercises must return the exercise created by '
            'createCustomExercise. Empty result means: (1) upsertCustomExercise '
            'wrote to the wrong Hive box, or (2) getCustomExercises filter '
            'changed and no longer accepts custom_exercise_* keys / type==exercise.',
      );
    },
  );

  // ── Test 2: returned entry has correct type or key prefix ────────────────
  test(
    "custom exercise entry has type=='exercise' OR key starts with custom_exercise_",
    () async {
      const exerciseName = 'Dragon Flag Test';
      await WorkoutRepository.instance.createCustomExercise(
        name: exerciseName,
        category: 'Core',
        equipment: 'bar',
        loggingType: 'bodyweight_reps',
      );

      final box = HiveService.instance.customBox;
      // Find the raw entry directly from Hive.
      Map<String, dynamic>? foundEntry;
      String? foundKey;
      for (final k in box.keys) {
        final v = box.get(k);
        if (v is Map) {
          final ex = Map<String, dynamic>.from(v);
          if ((ex['name'] as String?)?.toLowerCase() ==
              exerciseName.toLowerCase()) {
            foundEntry = ex;
            foundKey = k.toString();
            break;
          }
        }
      }

      expect(
        foundEntry,
        isNotNull,
        reason: 'Raw Hive entry must exist for the created custom exercise.',
      );
      final hasCorrectType = foundEntry!['type'] == 'exercise';
      final hasCorrectKeyPrefix = foundKey!.startsWith('custom_exercise_');
      expect(
        hasCorrectType || hasCorrectKeyPrefix,
        isTrue,
        reason:
            "Custom exercise must satisfy: type=='exercise' OR key.startsWith "
            "'custom_exercise_'. Currently: type=${foundEntry['type']}, "
            "key=$foundKey. If getCustomExercises stops accepting one of these "
            "forms, entries created by createCustomExercise become invisible.",
      );
    },
  );

  // ── Test 3: exercise name round-trips correctly ──────────────────────────
  test(
    'exercise name round-trips through Hive without mutation',
    () async {
      const exerciseName = 'Bulgarian Split Squat Test';
      await WorkoutRepository.instance.createCustomExercise(
        name: exerciseName,
        category: 'Legs',
        equipment: 'dumbbell',
        loggingType: 'weight_reps',
      );

      final customs = ExerciseRepository.instance.getCustomExercises();
      final match = customs.firstWhere(
        (e) => (e['name'] as String?)?.toLowerCase() ==
            exerciseName.toLowerCase(),
        orElse: () => <String, dynamic>{},
      );

      expect(
        match['name'],
        equals(exerciseName),
        reason:
            'The exercise name must round-trip exactly. '
            'If this fails the writer is mutating (uppercasing/trimming) '
            'the name in a way the reader does not expect.',
      );
      expect(
        match['is_custom'],
        isTrue,
        reason:
            "Custom exercises must carry is_custom=true so readers can "
            "distinguish library vs user-created exercises.",
      );
    },
  );

  // ── Test 4: duplicate name throws ───────────────────────────────────────
  test(
    'createCustomExercise throws CreateCustomExerciseException on duplicate name',
    () async {
      const exerciseName = 'Typewriter Pull Up Test';
      // First creation must succeed.
      await WorkoutRepository.instance.createCustomExercise(
        name: exerciseName,
        category: 'Pull',
        equipment: 'bar',
        loggingType: 'bodyweight_reps',
      );

      // Second creation with same name must throw.
      await expectLater(
        WorkoutRepository.instance.createCustomExercise(
          name: exerciseName,
          category: 'Pull',
          equipment: 'bar',
          loggingType: 'bodyweight_reps',
        ),
        throwsA(isA<CreateCustomExerciseException>()),
        reason:
            'Creating a duplicate custom exercise must throw '
            'CreateCustomExerciseException(duplicate_name). If this succeeds '
            'silently, the duplicate-ID guard was removed from createCustomExercise.',
      );
    },
  );
}
