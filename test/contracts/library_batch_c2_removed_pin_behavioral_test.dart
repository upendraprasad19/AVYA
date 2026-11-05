// test/contracts/library_batch_c2_removed_pin_behavioral_test.dart
//
// Batch C2a (OI-460): a repeat (phase 2) plan pins the exercise names of the previous phase. After the library removals
// a stored pin can name a REMOVED row. The generator must drop that pin, refill the slot from the shipped library and never
// emit the removed name; a day must not shrink. Real library, the real PlanGenerator.generateV4.
//
// A plain test() with real generation; the file timeout covers a loaded machine (CLAUDE.md section 4.9).
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';

import '../helpers/generator_golden_personas.dart' show namesByDay;

/// Removed rows by name, from the removals file (the frozen decision, not a literal).
Set<String> _removedNames() => {
      for (final e in ((jsonDecode(File('scripts/data/library_batch_c2_removals.json').readAsStringSync())
              as Map<String, dynamic>)['entries'] as List)
          .cast<Map<String, dynamic>>())
        if (e['decision'] == 'remove') (e['name'] as String).toLowerCase(),
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('c2_removed_pin');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    final box = await Hive.openBox(HiveService.exerciseBoxName);
    for (final r in (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List).whereType<Map>()) {
      final m = Map<String, dynamic>.from(r);
      m['id'] = (m['id'] ?? m['name']).toString();
      await box.put(m['id'], m);
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

  Phase gen({Map<int, ({List<String> a, List<String> b})>? pins}) => PlanGenerator.instance.generateV4(
        goal: 'build_muscle',
        equipment: 'full_gym',
        daysPerWeek: 4,
        phase: 2,
        experienceLevel: 'intermediate',
        injuries: const [],
        equipmentExclusions: const [],
        previousWeights: const {},
        pinnedExercisesByDay: pins,
      );

  test('a pin naming a removed row is dropped and refilled: the removed name never appears and no day shrinks', () {
    final removed = _removedNames();
    final base = gen();
    final pins = namesByDay(base);
    final clean = gen(pins: pins);

    // Replace the first pinned name of day 0 (week A) with a removed row's name that is NOT in the plan already.
    final ghost = removed.firstWhere((n) => !pins[0]!.a.map((x) => x.toLowerCase()).contains(n)).split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');
    final poisoned = {
      for (final e in pins.entries)
        e.key: e.key == 0 ? (a: [ghost, ...e.value.a.skip(1)], b: e.value.b) : e.value,
    };
    final out = gen(pins: poisoned);

    final emitted = {
      for (final w in out.weekPlans) for (final d in w.workoutDays) for (final x in d.exercises) x.exerciseName.toLowerCase()
    };
    expect(emitted.intersection(removed), isEmpty, reason: 'a removed row must never be emitted');
    for (var i = 0; i < clean.weekPlans[0].workoutDays.length; i++) {
      expect(out.weekPlans[0].workoutDays[i].exercises.length, greaterThanOrEqualTo(clean.weekPlans[0].workoutDays[i].exercises.length - 1),
          reason: 'day $i shrank by more than the one dropped pin: the slot was not refilled');
    }
  });
}
