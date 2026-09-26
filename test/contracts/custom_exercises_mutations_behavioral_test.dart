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
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart'
    show CreateCustomExerciseException, WorkoutRepository;
import 'package:icanbefitter/features/train/widgets/create_custom_exercise_sheet.dart';
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

  // ── Test 5: EDIT-mode save (custom-picker-fix, 2026-09-17) ───────────────
  //
  // The edit path = CreateCustomExerciseSheet.buildEditPayload (PURE) →
  // WorkoutWriteService.upsertCustomExercise (SoT writer, source
  // edit_sheet). Contract: writes to the SAME key, preserves
  // id/created_at/equipment_needed/approved_for_library, unions the
  // unmapped muscle tokens through (P1-2 — editing must never silently
  // drop tokens the UI cannot render), drops stale rep keys when the
  // logging type changed, and re-stamps source=edit_sheet.
  test(
    'edit-mode save writes the SAME key, preserves identity + cloud-state '
    'fields, unions unmapped muscle tokens',
    () async {
      const exerciseName = 'Edit Target Test';
      await WorkoutRepository.instance.createCustomExercise(
        name: exerciseName,
        category: 'Core',
        equipment: 'dumbbell',
        loggingType: 'weight_reps',
        primaryMuscles: const ['side deltoid'], // NOT in the 16-chip vocab
      );

      final box = HiveService.instance.customBox;
      String? foundKey;
      Map<String, dynamic>? row;
      for (final k in box.keys) {
        final v = box.get(k);
        if (v is Map &&
            (v['name'] as String?)?.toLowerCase() ==
                exerciseName.toLowerCase()) {
          foundKey = k.toString();
          row = Map<String, dynamic>.from(v);
          break;
        }
      }
      expect(foundKey, isNotNull,
          reason: 'seed row must exist before the edit simulation');

      // Simulate a row that was approved + already had created_at (AI or
      // approved community row) — the fields edit mode must NEVER wipe.
      row!['approved_for_library'] = true;
      final originalCreatedAt = row['created_at'] as String;
      final originalEquipment = List<String>.from(
          (row['equipment_needed'] as List).cast<String>());
      expect(originalEquipment, isNotEmpty,
          reason: 'fixture must carry a real equipment requirement — an '
              'empty one would make the preserve-assert vacuous '
              '(pre-migration rows both-empty is exactly the vacuous-'
              'fixture trap)');
      await box.put(foundKey, row);

      // The sheet's edit save, via the extracted PURE pieces. The REAL
      // workflow hands the sheet a map carrying `_key` (injected by
      // your_exercises_section._collectCustomExercises) while the STORED
      // row must not have it — reproduce exactly that shape, or the
      // strip-removal mutation below would be a zero-red no-op.
      final editInput = Map<String, dynamic>.from(row)..['_key'] = foundKey;
      final resolved = CreateCustomExerciseSheet.resolveMuscles(
        ['chest'], // selected chip
        ['side deltoid'], // pre-existing token outside the 16-chip vocab
      );
      final payload = CreateCustomExerciseSheet.buildEditPayload(
        editInput,
        category: 'Push',
        loggingType: 'timed', // reps-based → timed: stale default_reps dies
        defaultSets: 4,
        defaultDurationSeconds: 45,
        primaryMuscles: resolved,
        submittedToLibrary: false,
      );
      final res = await WorkoutWriteService.instance.upsertCustomExercise(
        key: foundKey!,
        exercise: payload,
        source: WriteSource.editSheet,
      );
      expect(res.success, isTrue, reason: 'edit write must succeed: ${res.errorMessage}');

      final after = Map<String, dynamic>.from(box.get(foundKey) as Map);
      expect(after.containsKey('_key'), isFalse,
          reason: 'the harness-injected _key must be stripped from the '
              'stored row — buildEditPayload removes it; if it reappears, '
              'the payload builder stopped sanitizing');
      expect(after['id'], equals(row['id']),
          reason: 'identity preserved — a changed id orphans the '
              'name-keyed log history and breaks the cloud onConflict key');
      expect(after['created_at'], equals(originalCreatedAt),
          reason: 'created_at is preserved, not reset by the edit');
      expect(after['approved_for_library'], isTrue,
          reason: 're-stamping false would demote an approved submission '
              'and stop fresh installs from pulling it');
      expect(
          List<String>.from((after['equipment_needed'] as List).cast<String>()),
          equals(originalEquipment),
          reason: 'equipment_needed is preserved — re-stamping [] would '
              'wipe an AI-authored row and re-open the L2 capability hole');
      expect(after['source'], equals('edit_sheet'),
          reason: 'the canonical writer re-stamps the source');
      expect(
          List<String>.from((after['primary_muscles'] as List).cast<String>()),
          containsAll(['chest', 'side deltoid']),
          reason: 'P1-2: unmapped tokens ride through the edit');
      expect(after.containsKey('default_reps'), isFalse,
          reason: 'timed logging type drops the stale reps key (create-shape parity)');
      expect(after['default_duration_seconds'], 45);
    },
  );

  test(
    'edit-mode resolveMuscles: selected and unmapped union, no duplicates',
    () {
      final out = CreateCustomExerciseSheet.resolveMuscles(
          ['chest', 'chest'], ['side deltoid']);
      expect(out.toSet().length, out.length,
          reason: 'no duplicate tokens even on repeated selection');
      expect(out, containsAll(['chest', 'side deltoid']));
    },
  );
}
