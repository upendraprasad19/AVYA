// ⑦ OI-89 seams 6–9 — the seams the COMPILER cannot reach.
//
// The generator seams take `capability` as a REQUIRED parameter, so a missed one
// fails to build. These four call none of those functions, so nothing structural
// protects them:
//
//   6  exercise_swap_sheet        declared an `equipment` field and read it NOWHERE
//   7  template_builder_screen    getAll().take(30) + search + customs, unfiltered
//   8  exercise_picker_sheet      getAll() + customs, filtered on category/name only
//   9  SwapService                no equipment check at all — and the AI coach's
//                                 swap_exercise tool drives it WITHOUT opening any
//                                 sheet, so filtering the UI does not cover it
//
// All four read the same helper, so that helper is what these tests pin. The
// widget lists themselves are exercised by the filter it returns.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/utils/equipment_vocab.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/equipment_capability.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/training_history_analyzer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_ui_seam_cap');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    // userBox is USER-SCOPED (GuardedBox): opening the raw box by name is not
    // enough — HiveService.init + a user session are what make
    // `HiveService.instance.userBox` resolve. Learned by reading the
    // neighbouring equipment_vocab_library_contract_test rather than guessing.
    await HiveService.instance.init();
    await HiveUserSession.openForUser(
      'uiseam-test-12345678-aaaa-bbbb-cccc-dddddddddddd',
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

  Future<void> seedProfile(Map<String, dynamic> profile,
      {bool flagOn = true}) async {
    final cfg = HiveService.instance.configBox;
    if (flagOn) {
      await cfg.put('enable_equipment_capability_floor', true);
    } else {
      await cfg.delete('enable_equipment_capability_floor');
    }
    await HiveService.instance.userBox.put('profile', profile);
  }

  group('resolveCapabilityFromProfile — the shared UI seam helper', () {
    test('a bodyweight profile yields the baseline capability set', () async {
      await seedProfile({'equipment_access': 'bodyweight'});
      final cap = TrainingHistoryAnalyzer.resolveCapabilityFromProfile();
      expect(cap, isNotNull);
      expect(cap, contains('bodyweight'));
      expect(cap, contains('wall'));
      expect(cap, isNot(contains('barbell')));
      expect(cap, isNot(contains('pull-up bar')));
    });

    test('a barbell exercise is rejected for that profile', () async {
      await seedProfile({'equipment_access': 'bodyweight'});
      final cap = TrainingHistoryAnalyzer.resolveCapabilityFromProfile();
      expect(EquipmentCapability.canPerform(['barbell'], cap!), isFalse,
          reason: 'this is what every one of the four seams now filters on');
      expect(EquipmentCapability.canPerform(['bodyweight'], cap), isTrue);
    });

    test('equipment_owned widens it — the pull-up-bar case (decision 4)',
        () async {
      await seedProfile({
        'equipment_access': 'bodyweight',
        'equipment_owned': ['pull-up bar'],
      });
      final cap = TrainingHistoryAnalyzer.resolveCapabilityFromProfile();
      expect(EquipmentCapability.canPerform(['pull-up bar'], cap!), isTrue);
    });

    test('equipment_exclusions narrows it', () async {
      await seedProfile({
        'equipment_access': 'bodyweight',
        'equipment_exclusions': ['doorway'],
      });
      final cap = TrainingHistoryAnalyzer.resolveCapabilityFromProfile();
      expect(EquipmentCapability.canPerform(['doorway'], cap!), isFalse);
    });

    test('the flag OFF returns null — every seam then skips its filter',
        () async {
      await seedProfile({'equipment_access': 'bodyweight'}, flagOn: false);
      expect(TrainingHistoryAnalyzer.resolveCapabilityFromProfile(), isNull,
          reason: 'null is a genuine SKIP; a wide set would NOT be inert '
              'because canPerform fails closed on unreadable requirements');
    });

    test('a GYM tier returns null — decision 1 scopes the hard floor',
        () async {
      await seedProfile({'equipment_access': 'full_gym'});
      expect(TrainingHistoryAnalyzer.resolveCapabilityFromProfile(), isNull,
          reason: 'the other three tiers keep queryV4 soft tier curation');
    });

    test('a MISSING equipment_access defaults to bodyweight, not a gym tier',
        () async {
      // The fail-safe direction: a bodyweight plan is performable by a gym
      // user; a gym plan is not performable by a bodyweight user.
      await seedProfile({});
      final cap = TrainingHistoryAnalyzer.resolveCapabilityFromProfile();
      expect(cap, isNotNull);
      expect(EquipmentCapability.canPerform(['barbell'], cap!), isFalse);
    });

    test('an unmappable owned token does not widen anything', () async {
      await seedProfile({
        'equipment_access': 'bodyweight',
        'equipment_owned': ['moon rocks'],
      });
      final cap = TrainingHistoryAnalyzer.resolveCapabilityFromProfile();
      expect(cap, isNotNull);
      expect(EquipmentCapability.canPerform(['barbell'], cap!), isFalse);
    });
  });

  group('the capability set is consistent with effectiveItems', () {
    test('profile-read and parameter-passed derivations agree', () async {
      // The UI seams read the profile; the plan engine gets tier + exclusions
      // passed down from generateV4. Both must land on the same set, or a swap
      // sheet could offer what the generator would refuse.
      await seedProfile({
        'equipment_access': 'bodyweight',
        'equipment_owned': ['pull-up bar'],
      });
      final fromProfile =
          TrainingHistoryAnalyzer.resolveCapabilityFromProfile();
      final direct = EquipmentVocab.effectiveItems(
          'bodyweight', ['pull-up bar'], const []);
      expect(fromProfile, equals(direct));
    });
  });
}
