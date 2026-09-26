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
    // ⚠ The flag FLIPPED ON 2026-08-28 and the key inverted with it:
    // `enable_equipment_capability_floor` -> `disable_equipment_capability_floor`,
    // default ON. Deleting the old `enable_` key no longer disables anything, so
    // the OFF cases here must SET the kill-switch. Two tests in this file went
    // red on the flip for exactly that reason, which is the behaviour we want:
    // a key rename that silently left tests asserting the old world would be
    // worse than the failure.
    if (flagOn) {
      await cfg.delete('disable_equipment_capability_floor');
    } else {
      await cfg.put('disable_equipment_capability_floor', true);
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

    test('the KILL SWITCH returns null — every seam then skips its filter',
        () async {
      await seedProfile({'equipment_access': 'bodyweight'}, flagOn: false);
      expect(TrainingHistoryAnalyzer.resolveCapabilityFromProfile(), isNull,
          reason: 'null is a genuine SKIP; a wide set would NOT be inert '
              'because canPerform fails closed on unreadable requirements');
    });

    test('a GYM tier now ANSWERS — ⑧ OI-144 supersedes decision 1', () async {
      // This asserted `isNull` under OI-89: the hard floor was scoped to the
      // bodyweight tier and the other three kept queryV4's soft tier curation.
      // That scoping is exactly what made the Profile picker collect-but-ignore
      // — a home_dumbbells user could tick "pull-up bar" and nothing changed.
      await seedProfile({'equipment_access': 'full_gym'});
      final cap = TrainingHistoryAnalyzer.resolveCapabilityFromProfile();
      expect(cap, isNotNull);
      expect(cap, contains('barbell'),
          reason: 'full_gym grants it, so capability must too — the widening '
              'must never NARROW a tier that already had the item');
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

  group('effectiveEquipmentForSnapshot — the AI coach reader (decision 7)', () {
    // The coach used to receive the tier LABEL and had to guess what it held,
    // so it could recommend a barbell row to a bodyweight user and be entirely
    // self-consistent. It now receives the effective set itself.

    test('the KILL SWITCH returns null — the key is OMITTED, not emitted empty',
        () async {
      // An empty list would read to Gemini as "this user owns nothing at all",
      // which is a WORSE claim than the pre-batch silence.
      await seedProfile({'equipment_access': 'bodyweight'}, flagOn: false);
      expect(
          TrainingHistoryAnalyzer.effectiveEquipmentForSnapshot(
              {'equipment_access': 'bodyweight'}),
          isNull);
    });

    test('the two producers AGREE at every tier (⑧ OI-144)', () async {
      // Under OI-89 this test asserted the OPPOSITE and was right to: the two
      // producers deliberately disagreed, because the hard floor was scoped to
      // bodyweight while the coach needed truth everywhere. OI-144 removed that
      // scoping, so they now differ only in RETURN SHAPE (Set vs sorted List)
      // and any policy divergence between them is a bug rather than a design.
      // Pinning the agreement is strictly stronger than pinning the old split:
      // it catches drift in either direction.
      await seedProfile({
        'equipment_access': 'full_gym',
        'equipment_owned': ['suspension trainer'],
      });
      final viaProfile = TrainingHistoryAnalyzer.resolveCapabilityFromProfile();
      final viaSnapshot = TrainingHistoryAnalyzer.effectiveEquipmentForSnapshot({
        'equipment_access': 'full_gym',
        'equipment_owned': ['suspension trainer'],
      });
      expect(viaSnapshot, isNotNull);
      expect(viaSnapshot!.toSet(), equals(viaProfile),
          reason: 'same profile, same effective set');
    });

    test('both producers fail SAFE on an unrecognised tier', () async {
      // effectiveItems fails OPEN (every canonical token) for an unknown tier.
      // Both producers must override that, or a corrupt equipment_access hands
      // the user barbell work.
      await seedProfile({'equipment_access': 'mars_colony'});
      final viaProfile = TrainingHistoryAnalyzer.resolveCapabilityFromProfile();
      final viaSnapshot = TrainingHistoryAnalyzer.effectiveEquipmentForSnapshot(
          {'equipment_access': 'mars_colony'});
      expect(viaProfile, isNot(contains('barbell')));
      expect(viaSnapshot, isNot(contains('barbell')));
      expect(viaSnapshot!.toSet(), equals(viaProfile));
    });

    test('a home_dumbbells user is described honestly', () async {
      await seedProfile({'equipment_access': 'home_dumbbells'});
      final snap = TrainingHistoryAnalyzer.effectiveEquipmentForSnapshot(
          {'equipment_access': 'home_dumbbells'});
      expect(snap, contains('dumbbells'));
      expect(snap, isNot(contains('barbell')),
          reason: 'the whole point — the coach can no longer guess');
    });

    test('a MISSING equipment_access is described as bodyweight, not empty',
        () async {
      await seedProfile({});
      final snap = TrainingHistoryAnalyzer.effectiveEquipmentForSnapshot({});
      expect(snap, isNotNull);
      expect(snap, contains('bodyweight'));
      expect(snap, isNot(contains('barbell')));
    });

    test('owned widens and exclusions narrow the SAME snapshot', () async {
      await seedProfile({'equipment_access': 'bodyweight'});
      final snap = TrainingHistoryAnalyzer.effectiveEquipmentForSnapshot({
        'equipment_access': 'bodyweight',
        'equipment_owned': ['pull-up bar'],
        'equipment_exclusions': ['doorway'],
      });
      expect(snap, contains('pull-up bar'));
      expect(snap, isNot(contains('doorway')));
    });

    test('the output is SORTED — an unstable prompt defeats caching', () async {
      await seedProfile({'equipment_access': 'basic_gym'});
      final snap = TrainingHistoryAnalyzer.effectiveEquipmentForSnapshot(
          {'equipment_access': 'basic_gym'})!;
      expect(snap, equals([...snap]..sort()));
      expect(snap.toSet().length, snap.length, reason: 'no duplicates');
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
