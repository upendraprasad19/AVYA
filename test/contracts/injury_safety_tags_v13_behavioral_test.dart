// Batch B1 Task 1b — five safety-direction injury tags (founder decision
// 2026-10-22), diagnose docs/diagnoses/2026-10-22-library-injury-undertag-v13-c2d5e8.md.
//
// Each (row, added token) pair is proven on a real reader:
//  - E121 Renegade Row is the only one of the five that any golden persona's
//    OFF plan picks (19 of 998 personas), so it runs through the REAL
//    PlanGenerator.generateV4 with a positive control: the persona's plan holds
//    the row without the injury, and loses it with the injury.
//  - E061 / E070 / E127 / E173 are picked by no golden persona, so their pairs
//    are asserted on queryV4 itself, again with a positive control (the row is
//    in the unfiltered result), so a pattern typo cannot pass vacuously.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;
  late List<Map<String, dynamic>> library;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('injury_safety_tags_v13');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    final exBox = await Hive.openBox(HiveService.exerciseBoxName);
    library = (jsonDecode(
      File('assets/data/exercise_library.json').readAsStringSync(),
    ) as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    for (final r in library) {
      await exBox.put(r['id'] as String, r);
    }
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
  });

  tearDownAll(() async {
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('the five rows carry exactly their added tags, nothing removed', () {
    Set<String> tags(String id) => {
          for (final t in library.firstWhere((r) => r['id'] == id)
              ['injury_contraindications'] as List)
            t as String
        };
    expect(tags('E061'), {'ankle', 'knee'});
    expect(tags('E070'), {'elbow', 'shoulder', 'wrist'});
    expect(tags('E121'), {'lower_back', 'shoulder', 'wrist'});
    expect(tags('E127'), {'lower_back'});
    expect(tags('E173'), {'lower_back'});
  });

  group('E121 Renegade Row through the real generator', () {
    Set<String> planNames(List<String> injuries) {
      final Phase p = PlanGenerator.instance.generateV4(
        goal: 'build_muscle',
        equipment: 'home_dumbbells',
        daysPerWeek: 4,
        phase: 1,
        experienceLevel: 'intermediate',
        injuries: injuries,
        previousWeights: const {},
      );
      return {
        for (final w in p.weekPlans)
          for (final d in w.workoutDays)
            for (final e in d.exercises) e.exerciseName
      };
    }

    test('positive control: the uninjured plan holds it', () {
      expect(planNames(const []), contains('Renegade Row'));
    });
    for (final token in ['wrist', 'shoulder']) {
      test('+$token: an injured plan does not', () {
        expect(planNames([token]), isNot(contains('Renegade Row')));
      });
    }
  });

  group('rows no golden persona picks, on queryV4', () {
    const pairs = [
      ('E061', 'Running (Treadmill)', 'cardio', 'knee'),
      ('E070', 'Front Lever Hold', 'core', 'shoulder'),
      ('E070', 'Front Lever Hold', 'core', 'elbow'),
      ('E127', 'Reverse Hyper', 'hip_isolation', 'lower_back'),
      ('E173', 'Decline Sit Up', 'core', 'lower_back'),
    ];
    List<String> query(String pattern, List<String>? injuries) => [
          for (final r in ExerciseRepository.instance.queryV4(
            movementPattern: pattern,
            injuryExclusions: injuries,
            exclusions: const {},
            capability: null,
          ))
            r['name'] as String
        ];

    for (final (id, name, pattern, token) in pairs) {
      test('$id +$token: queryV4($pattern) drops $name', () {
        expect(query(pattern, null), contains(name),
            reason: 'positive control: unfiltered $pattern includes $name');
        expect(query(pattern, [token]), isNot(contains(name)));
      });
    }
  });
}
