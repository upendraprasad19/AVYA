// BEHAVIORAL CONTRACT TEST — custom_exercises_mutations, the name rule (OI-348 walk, A16).
//
// Founder 2026-11-25 (device walk, AAB +50): the app let a custom exercise be created with a name
// the exercise list already holds ("Barbell Bench Press"), kept it, and only refused later, when
// the name went into a workout. Founder: "why should there be duplicate names? This is incorrect."
// Decision: REFUSE ANY DUPLICATE NAME, at the one create path, for every door (the sheet, the AI
// coach). Reason: logs are keyed by the exercise name, so a second exercise with the same name
// would share the first one's history, and the pickers would show two rows that look the same.
//
// Writer:  lib/features/train/repositories/workout_repository.dart `createCustomExercise`
// Readers: the sheet (create_custom_exercise_sheet.dart shows e.message), the coach tool
//          (tool_dispatcher.dart `_executeCreateCustomExercise` passes e.message through).
//
// "The same name" = `exerciseDuplicateKey`: `exerciseNameKey` (trim + lower case) with runs of
// spaces read as one and curly apostrophes read as straight ones. Matched against (a) every
// exercise-list row's `name`, (b) every row's retired `name_aliases`, (c) every custom row,
// whatever id scheme it was stored with. Plus one row per v5 id.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';
import 'package:icanbefitter/features/ai_coach/services/tool_dispatcher.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart'
    show CreateCustomExerciseException, WorkoutRepository;
import 'package:uuid/uuid.dart';

import '../helpers/hive_test_setup.dart';

const _bench = 'Barbell Bench Press';
const _pike = 'Pike Push Up';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
    final lib = HiveService.instance.exerciseBox;
    await lib.clear();
    await lib.put('E1', {
      'id': 'E1',
      'name': _bench,
      'category': 'Push',
      'logging_type': 'weight_reps',
    });
    await lib.put('E2', {
      'id': 'E2',
      'name': _pike,
      'name_aliases': ['Pike Pushup', ' Elevated Pike '],
      'category': 'Push',
      'logging_type': 'bodyweight_reps',
    });
    // A real library name with a straight apostrophe.
    await lib.put('E3', {
      'id': 'E3',
      'name': "Child's Pose",
      'category': 'Core',
      'logging_type': 'timed',
    });
    await HiveService.instance.customBox.clear();
  });

  tearDown(() => tearDownHiveForTests(tempDir));

  Future<CreateCustomExerciseException> refused(String name) async {
    try {
      await WorkoutRepository.instance.createCustomExercise(
        name: name,
        category: 'Push',
        loggingType: 'weight_reps',
      );
    } on CreateCustomExerciseException catch (e) {
      return e;
    }
    fail('"$name" was created; it must be refused');
  }

  List<String> customNames() => HiveService.instance.customBox.values
      .whereType<Map>()
      .map((m) => m['name'] as String)
      .toList();

  group('REFUSED: a name the list already holds', () {
    test('the exact name of an exercise-list row', () async {
      final e = await refused(_bench);
      expect(e.code, 'duplicate_name');
      expect(customNames(), isEmpty, reason: 'nothing may be written');
    });

    test('case and spaces do not get around it', () async {
      expect((await refused('  BARBELL BENCH PRESS  ')).code, 'duplicate_name');
      expect((await refused('barbell  bench   press')).code, 'duplicate_name',
          reason: 'repeated spaces INSIDE the name');
      final nbsp = String.fromCharCode(0xA0);
      expect((await refused('Barbell${nbsp}Bench Press')).code, 'duplicate_name',
          reason: 'a non-breaking space');
      expect(customNames(), isEmpty);
    });

    test('a curly apostrophe does not make a new name', () async {
      expect((await refused('Child’s Pose')).code, 'duplicate_name');
      expect(customNames(), isEmpty);
    });

    test('a custom row with the same id blocks the create, whatever its name',
        () async {
      // The v5 id a create of "ZZ Id Twin" would get (signed-out namespace).
      final id = const Uuid().v5('5a1f0b0c-9dad-11d1-80b4-00c04fd430c8',
          'anon|exercise|zz id twin');
      await HiveService.instance.customBox.put('custom_exercise_2', {
        'id': id,
        'name': 'Renamed Elsewhere',
        'type': 'exercise',
        'category': 'Core',
      });
      expect((await refused('ZZ Id Twin')).code, 'duplicate_name');
      expect(customNames(), ['Renamed Elsewhere']);
    });

    test('a retired name (alias) of an exercise-list row', () async {
      expect((await refused('Pike Pushup')).code, 'duplicate_name');
      expect((await refused('elevated pike')).code, 'duplicate_name',
          reason: 'the alias is stored with stray spaces and capitals');
      expect(customNames(), isEmpty);
    });

    test('a custom row stored under an older id scheme still blocks its name',
        () async {
      // The v5 id of "old habit" differs from this row's id, so an id-only guard lets it through.
      await HiveService.instance.customBox.put('custom_exercise_1', {
        'id': 'cx_legacy_1',
        'name': 'Old Habit',
        'type': 'exercise',
        'category': 'Core',
      });
      expect((await refused('  OLD habit ')).code, 'duplicate_name',
          reason: 'a different case and stray spaces: the name key, not the raw text');
      expect(customNames(), ['Old Habit']);
    });

    test('a name the user created before is still refused (the earlier guard)',
        () async {
      await WorkoutRepository.instance.createCustomExercise(
        name: 'Zercher Hold Test',
        category: 'Core',
        loggingType: 'timed',
        defaultDurationSeconds: 30,
      );
      expect((await refused('zercher hold test')).code, 'duplicate_name');
      expect(customNames(), ['Zercher Hold Test']);
    });

    test('the message names the exercise and says it is already in the list',
        () async {
      final e = await refused(_bench);
      expect(e.message, contains(_bench));
      expect(e.message, contains('already in the exercise list'));
    });
  });

  group('MIRROR: a name that is only SIMILAR still creates', () {
    test('a new name creates and is stored', () async {
      final id = await WorkoutRepository.instance.createCustomExercise(
        name: 'Archer Push Up Test',
        category: 'Push',
        loggingType: 'bodyweight_reps',
        defaultReps: '8',
      );
      expect(id, isNotEmpty);
      expect(customNames(), ['Archer Push Up Test']);
    });

    test('a longer name that CONTAINS a list name creates (exact match, not substring)',
        () async {
      await WorkoutRepository.instance.createCustomExercise(
        name: '$_bench Wide Grip',
        category: 'Push',
        loggingType: 'weight_reps',
      );
      // A made-up prefix: "Incline Pike Push Up" is a real list row.
      await WorkoutRepository.instance.createCustomExercise(
        name: 'Sideways $_pike',
        category: 'Push',
        loggingType: 'bodyweight_reps',
      );
      expect(customNames(), ['$_bench Wide Grip', 'Sideways $_pike']);
    });

    test('a TEMPLATE in the same box with that name does not block it', () async {
      await HiveService.instance.customBox.put('tmpl_1', {
        'id': 'tmpl_1',
        'type': 'template',
        'name': 'Zercher Template Day',
        'exercises': <Map<String, dynamic>>[],
      });
      await WorkoutRepository.instance.createCustomExercise(
        name: 'Zercher Template Day',
        category: 'Push',
        loggingType: 'weight_reps',
      );
      expect(customNames(), containsAll(['Zercher Template Day']));
      expect(customNames().length, 2, reason: 'the template and the new exercise');
    });

    test('a name that is a PART of a list name creates', () async {
      await WorkoutRepository.instance.createCustomExercise(
        name: 'Bench Press',
        category: 'Push',
        loggingType: 'weight_reps',
      );
      expect(customNames(), ['Bench Press']);
    });
  });

  group('the AI coach door (create_custom_exercise intent)', () {
    ToolIntent intent(String name) => ToolIntent(
          id: 'i_$name',
          type: 'create_custom_exercise',
          payload: {
            'name': name,
            'category': 'push',
            'equipment': 'full_gym',
            'loggingType': 'weight_reps',
            'defaultSets': 3,
            'defaultReps': 8,
          },
          confirmationClass: ConfirmationClass.reviewable,
          previewSummary: 'Create custom exercise: $name',
          createdAt: DateTime.now(),
        );

    test('a name the list holds is refused: a failure, nothing written', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final refProvider = Provider<Ref>((ref) => ref);
      final result = await ToolDispatcher.instance
          .execute(container.read(refProvider), intent(_bench));
      expect(result.success, isFalse);
      expect(
          result.errorMessage,
          WardroomCopy.customExerciseNameTakenTemplate
              .replaceAll('{exercise}', _bench),
          reason: 'the coach says what is true: a list name, not "you already have"');
      expect(customNames(), isEmpty);
    });
  });
}
