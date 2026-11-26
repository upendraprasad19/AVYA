import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';

/// OI-348 Landing 3a (P1): the app now tells users "all phases, no end
/// point". This pins the promise: the local generator really builds Phase 13
/// and 14 (named "Deployment 1" / "Deployment 2" in the plan blob, a name no
/// screen shows) with four weeks of real workouts.
///
/// CHARACTERIZATION, not a regression test: the generator already did this
/// before the batch (`plan_generator.dart` `_getPhaseMeta`, 2026-05-31), so it
/// cannot fail "without the fix". Mutation proof (on a scratch copy, never
/// the tracked file, rule 14): change the `'Deployment ${phase - 12}'`
/// fallback, the name assertions redden.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeee1313';
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('phase_13_generation');
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
    final rows = jsonDecode(
      File('assets/data/exercise_library.json').readAsStringSync(),
    ) as List;
    for (final r in rows.whereType<Map>()) {
      await exBox.put((r['id'] ?? r['name']).toString(),
          Map<String, dynamic>.from(r));
    }
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
  });

  tearDownAll(() async {
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  for (final (phase, name) in [(13, 'Deployment 1'), (14, 'Deployment 2')]) {
    test('phase $phase is generated: "$name", 4 weeks of real workouts', () {
      final p = PlanGenerator.instance.generateV4(
        goal: 'build_muscle',
        equipment: 'full_gym',
        daysPerWeek: 4,
        phase: phase,
        experienceLevel: 'intermediate',
      );
      expect(p.phase, phase);
      expect(p.name, name);
      expect(p.weekPlans, hasLength(4));
      for (final wk in p.weekPlans) {
        expect(wk.workoutDays, isNotEmpty);
        for (final d in wk.workoutDays) {
          expect(d.exercises, isNotEmpty,
              reason: 'phase $phase must not produce an empty day');
        }
      }
    });
  }
}
