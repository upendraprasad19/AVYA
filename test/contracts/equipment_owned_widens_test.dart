// ⑧ OI-144 — owning equipment must WIDEN the pool at every tier.
//
// The defect: Profile offered a home_dumbbells user 13 chips (pull-up bar,
// kettlebell, bench, …), wrote the answer, synced it, and raised the
// "Reschedule Workouts?" prompt — and the regenerated plan was byte-identical.
// TWO independent reasons, and a test that covered only one would have passed
// against a fix that does nothing:
//
//   1. resolveCapability returned null above the bodyweight tier, so the
//      capability filter never ran for gym-tier users.
//   2. queryV4's tier block independently dropped any row whose equipment_tier
//      lacked the tier string. Chin Up is [basic_gym, full_gym], so a
//      home_dumbbells user never saw it HOWEVER capability was computed.
//
// So the assertions below drive BOTH: the producer (does it answer at a gym
// tier?) and the consumer (does the tier block yield to it?).
//
// THE ORACLE READS `equipment_needed`, NEVER `equipment_tier` — the latter is the
// field under test, and an oracle sharing it with the predicate proves threading
// rather than truth.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/utils/equipment_vocab.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/training_history_analyzer.dart';

Map<String, dynamic> _ex(String id, String name, List<String> needed,
        List<String> tiers, String pattern) =>
    <String, dynamic>{
      'id': id,
      'name': name,
      'movement_pattern': [pattern],
      'equipment_needed': needed,
      'equipment_tier': tiers,
      'exercise_type': ['compound'],
      'target_focus': ['Back'],
      'primary_muscles': ['Lats'],
      'suitable_for': ['Beginner', 'Intermediate', 'Advanced'],
      'is_foundational': true,
      'priority_tier': 1,
      'is_active': true,
      'default_sets': 3,
      'default_reps': '10',
      'default_rest_secs': 60,
      'rep_range': '8-12',
      'logging_type': 'reps',
      'injury_contraindications': <String>[],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_owned_widens');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await HiveService.instance.init();
    await HiveUserSession.openForUser(
      'owned-widens-12345678-aaaa-bbbb-cccc-dddddddddddd',
    );
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    // Cleanup is hygiene, not an assertion — a throw here stacks a second
    // failure that hides the real one.
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    final box = HiveService.instance.exerciseBox;
    await box.clear();
    // A pull-up-bar row tagged for the GYM tiers only — the exact shape of the
    // bug. And a dumbbell row a home_dumbbells user can always do.
    await box.put('BAR', _ex('BAR', 'Test Chin Up', ['pull-up bar'],
        ['basic_gym', 'full_gym'], 'vertical_pull'));
    await box.put('DB', _ex('DB', 'Test Dumbbell Row', ['dumbbells'],
        ['home_dumbbells', 'basic_gym', 'full_gym'], 'vertical_pull'));
    HiveService.instance.markInitializedForTests();
  });

  Future<void> seedProfile(Map<String, dynamic> profile,
      {bool killed = false}) async {
    final cfg = HiveService.instance.configBox;
    if (killed) {
      await cfg.put('disable_equipment_capability_floor', true);
    } else {
      await cfg.delete('disable_equipment_capability_floor');
    }
    await HiveService.instance.userBox.put('profile', profile);
  }

  List<String> namesFor(Set<String>? capability) => ExerciseRepository.instance
      .queryV4(
        movementPattern: 'vertical_pull',
        equipmentTier: 'home_dumbbells',
        exclusions: const {},
        capability: capability,
      )
      .map((e) => e['name'] as String)
      .toList();

  group('the CONSUMER — queryV4 lets capability override the tier block', () {
    test('owning a pull-up bar unlocks a gym-tagged row at home_dumbbells', () {
      final owned = EquipmentVocab.effectiveItems(
          'home_dumbbells', ['pull-up bar'], const []);
      expect(namesFor(owned), contains('Test Chin Up'),
          reason: 'equipment_tier is [basic_gym, full_gym]; the user OWNS the '
              'bar, so capability must override the tier string');
    });

    test('the SAME user owning nothing does NOT get it', () {
      // The other half. Without this, a fix that simply deleted the tier filter
      // would pass the assertion above and be catastrophically wrong.
      final nothing =
          EquipmentVocab.effectiveItems('home_dumbbells', const [], const []);
      final names = namesFor(nothing);
      expect(names, isNot(contains('Test Chin Up')));
      expect(names, contains('Test Dumbbell Row'),
          reason: 'the tier baseline must still be reachable');
    });

    test('capability null falls back to the LEGACY tier filter, unchanged', () {
      final names = namesFor(null);
      expect(names, isNot(contains('Test Chin Up')),
          reason: 'with no capability the tier block must still bind');
      expect(names, contains('Test Dumbbell Row'));
    });
  });

  group('the PRODUCER — resolveCapabilityFromProfile answers at every tier', () {
    test('a gym tier is no longer null (this is the OI-144 change)', () async {
      await seedProfile({'equipment_access': 'home_dumbbells'});
      final cap = TrainingHistoryAnalyzer.resolveCapabilityFromProfile();
      expect(cap, isNotNull,
          reason: 'OI-89 scoped the floor to bodyweight and returned null here; '
              'OI-144 removes that gate');
      expect(cap, contains('dumbbells'));
      expect(cap, isNot(contains('pull-up bar')));
    });

    test('owned widens it at a gym tier', () async {
      await seedProfile({
        'equipment_access': 'home_dumbbells',
        'equipment_owned': ['pull-up bar'],
      });
      expect(TrainingHistoryAnalyzer.resolveCapabilityFromProfile(),
          contains('pull-up bar'));
    });

    test('an UNRECOGNISED tier resolves to the bodyweight floor, not to '
        'everything (R1-B)', () async {
      // effectiveItems fails OPEN on an unknown tier, returning every canonical
      // token. That branch was unreachable while resolveCapability gated on
      // `tier == bodyweight`; removing the gate is what makes it reachable, so a
      // corrupt equipment_access would otherwise hand out barbell work.
      await seedProfile({'equipment_access': 'mars_colony'});
      final cap = TrainingHistoryAnalyzer.resolveCapabilityFromProfile();
      expect(cap, isNotNull);
      expect(cap, isNot(contains('barbell')),
          reason: 'a corrupt tier must fail SAFE, not open');
      expect(cap, contains('bodyweight'));
    });

    test('the kill switch still yields null at a gym tier', () async {
      await seedProfile({'equipment_access': 'full_gym'}, killed: true);
      expect(TrainingHistoryAnalyzer.resolveCapabilityFromProfile(), isNull,
          reason: 'null means DO NOT ENFORCE and must survive the widening');
    });
  });

  group('unchanged for everyone else', () {
    test('a full_gym user owning nothing sees the same set either way', () {
      // The spec argues the two filters are extensionally equal on the
      // no-owned case. This is the evidence rather than the argument.
      final viaCapability = ExerciseRepository.instance
          .queryV4(
            movementPattern: 'vertical_pull',
            equipmentTier: 'full_gym',
            exclusions: const {},
            capability:
                EquipmentVocab.effectiveItems('full_gym', const [], const []),
          )
          .map((e) => e['name'] as String)
          .toSet();
      final viaLegacyTier = ExerciseRepository.instance
          .queryV4(
            movementPattern: 'vertical_pull',
            equipmentTier: 'full_gym',
            exclusions: const {},
            capability: null,
          )
          .map((e) => e['name'] as String)
          .toSet();
      expect(viaCapability, equals(viaLegacyTier));
      expect(viaCapability, containsAll(['Test Chin Up', 'Test Dumbbell Row']));
    });
  });
}
