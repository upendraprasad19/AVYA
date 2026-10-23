// Batch A Task 3 — two rows labelled 'Lats' by a typo.
//
// E172 Dumbbell Side Bend is a core row whose only target_focus was 'Lats', so
// queryV4's target-muscle filter never offered it to a Core slot: the obliques
// exercise was invisible to the one slot it exists for. E163 Foam Roll IT Band
// (a flexibility row for the lateral thigh) carried the same typo.
//
// A general "Lats only on pull patterns" rule cannot replace these two pins:
// E070 Front Lever, E154 Lat Stretch, E159 Child's Pose and E213 Dead Hang
// carry 'Lats' correctly on non-pull patterns.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  final bundled = (jsonDecode(
    File('assets/data/exercise_library.json').readAsStringSync(),
  ) as List)
      .cast<Map<String, dynamic>>();

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('label_typo');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    final box = await Hive.openBox(HiveService.exerciseBoxName);
    await box.putAll({for (final r in bundled) r['id'] as String: r});
    HiveService.instance.markInitializedForTests();
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a Core slot at home_dumbbells is offered E172 Dumbbell Side Bend', () {
    final ids = ExerciseRepository.instance
        .queryV4(
          movementPattern: 'core',
          targetMuscle: 'Core',
          equipmentTier: 'home_dumbbells',
          exerciseType: 'isolation',
          exclusions: const {},
          capability: null,
        )
        .map((r) => r['id'])
        .toList();
    expect(ids, contains('E172'));
  });

  test('E172 and E163 carry no Lats label', () {
    for (final id in ['E172', 'E163']) {
      final row = bundled.singleWhere((r) => r['id'] == id);
      final focus = (row['target_focus'] as List).map((e) => e.toString());
      expect(focus, isNot(contains('Lats')), reason: '$id target_focus=$focus');
    }
  });
}
