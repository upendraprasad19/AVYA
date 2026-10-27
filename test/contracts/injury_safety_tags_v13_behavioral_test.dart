// Batch B1 Task 1b — five safety-direction injury tags (founder decision
// 2026-10-22), diagnose docs/diagnoses/2026-10-22-library-injury-undertag-v13-c2d5e8.md.
//
// Each (row, added token) pair is proven on a real reader:
//  - E121 Renegade Row was, on the 285-row library, the only one of the five that any
//    golden persona's OFF plan picked (19 of 998 personas), so it ran through the REAL
//    PlanGenerator.generateV4. Batch C1 (629 new rows) displaced it: a reach search over
//    3 goals x 4 tiers x 3 levels x 4 day counts found NO plan that holds it, so its pairs
//    moved to queryV4 with the other four.
//  - E061 / E070 / E121 / E127 / E173 are asserted on queryV4 itself, with a positive
//    control (the row is in the unfiltered result), so a pattern typo cannot pass vacuously.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';

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
    // E061 also carries the v14 +hip (founder table 2026-10-23, aligned with the
    // warm-up list's Running (Treadmill) = {knee, ankle, hip}); +knee is v13's.
    expect(tags('E061'), {'ankle', 'hip', 'knee'});
    expect(tags('E070'), {'elbow', 'shoulder', 'wrist'});
    expect(tags('E121'), {'lower_back', 'shoulder', 'wrist'});
    expect(tags('E127'), {'lower_back'});
    expect(tags('E173'), {'lower_back'});
  });

  group('rows no persona picks, on queryV4', () {
    const pairs = [
      ('E061', 'Running (Treadmill)', 'cardio', 'knee'),
      ('E070', 'Front Lever Hold', 'core', 'shoulder'),
      ('E070', 'Front Lever Hold', 'core', 'elbow'),
      ('E121', 'Renegade Row', 'horizontal_pull', 'wrist'),
      ('E121', 'Renegade Row', 'horizontal_pull', 'shoulder'),
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
