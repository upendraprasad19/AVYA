// Contract — the equipment vocabulary MUST cover the exercise library (⑥ slice A).
//
// GATE (SUBSET, not equality): every distinct `equipment_needed` token in
// assets/data/exercise_library.json must be a member of
// EquipmentVocab.canonicalTokens. It is a SUBSET (⊆) rather than an equality
// assert because `smith machine` is a canonical token with ZERO library rows
// (kept for tier alignment) — an equality test would fail. This FAILS the moment
// the library gains a raw non-canonical token (e.g. a new "Treadmill" row →
// "treadmill" ∉ canonicalTokens), forcing the normalizer/vocab to be updated in
// the same commit so the field can never silently drift back to free text.
//
// BEHAVIORAL (account-tier behavioral_test_path): the owned custom-exercise
// write (workout_repository.dart:1375, the AI createCustomExercise tool's sink)
// normalizes caller free-text equipment → canonical (write → Hive read-back).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/utils/equipment_vocab.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('library equipment_needed ⊆ EquipmentVocab.canonicalTokens (SUBSET)', () {
    final lib = jsonDecode(
      File('assets/data/exercise_library.json').readAsStringSync(),
    ) as List;

    final tokens = <String>{};
    for (final e in lib) {
      final eq = (e as Map)['equipment_needed'];
      if (eq is List) {
        for (final t in eq) {
          tokens.add(t.toString().toLowerCase().trim());
        }
      } else if (eq is String && eq.trim().isNotEmpty) {
        tokens.add(eq.toLowerCase().trim());
      }
    }

    final nonCanonical = tokens.difference(EquipmentVocab.canonicalTokens);
    expect(
      nonCanonical,
      isEmpty,
      reason: 'exercise_library.json has equipment_needed token(s) outside the '
          'canonical vocab: ${nonCanonical.toList()..sort()}. Re-run '
          '`dart run scripts/normalize_equipment_library.dart`; if a genuinely '
          'new equipment type was added, extend EquipmentVocab._aliases + '
          'canonicalTokens in the same commit.',
    );
    // SUBSET, not equality: `smith machine` is canonical with 0 library rows.
    expect(
      EquipmentVocab.canonicalTokens.containsAll(tokens),
      isTrue,
    );
  });

  group('normalizeToken', () {
    test('multi-word token maps as ONE (no whitespace split, R1 vocab P1-1)', () {
      expect(EquipmentVocab.normalizeToken('Cable Machine'), 'cables');
      expect(EquipmentVocab.normalizeToken('Leg Curl Machine'), 'machines');
      expect(EquipmentVocab.normalizeToken('Incline Bench'), 'bench');
    });
    test('OR-compound collapses to the most-accessible alternative', () {
      expect(EquipmentVocab.normalizeToken('Barbell or Dumbbells'), 'dumbbells');
      expect(EquipmentVocab.normalizeToken('Bodyweight or Barbell'), 'bodyweight');
      expect(EquipmentVocab.normalizeToken('Machine or Barbell'), 'barbell');
      expect(EquipmentVocab.normalizeToken('Pull-Up Bar or Rack'), 'pull-up bar');
      expect(EquipmentVocab.normalizeToken('Reverse Hyper Machine or Bench'), 'bench');
      expect(EquipmentVocab.normalizeToken('Box or Bench'), 'bodyweight');
      expect(EquipmentVocab.normalizeToken('Barbell on Rack or TRX'), 'bodyweight');
    });
    test('canonical tokens pass through unchanged', () {
      expect(EquipmentVocab.normalizeToken('Barbell'), 'barbell');
      expect(EquipmentVocab.normalizeToken('pull-up bar'), 'pull-up bar');
      expect(EquipmentVocab.normalizeToken('CARDIO MACHINE'), 'cardio machine');
    });
    test('cardio + niche tokens bucket correctly', () {
      expect(EquipmentVocab.normalizeToken('Treadmill'), 'cardio machine');
      expect(EquipmentVocab.normalizeToken('Battle Ropes'), 'cardio machine');
      expect(EquipmentVocab.normalizeToken('Box (30-45cm)'), 'bodyweight');
      expect(EquipmentVocab.normalizeToken('Medicine Ball'), 'bodyweight');
      expect(EquipmentVocab.normalizeToken('Weight Plate'), 'dumbbells');
      expect(EquipmentVocab.normalizeToken('Landmine'), 'barbell');
      expect(EquipmentVocab.normalizeToken('Rope'), 'cables');
    });
    test('unmappable / empty → null', () {
      expect(EquipmentVocab.normalizeToken('Spaceship'), isNull);
      expect(EquipmentVocab.normalizeToken(''), isNull);
      expect(EquipmentVocab.normalizeToken('   '), isNull);
    });
  });

  group('normalize (list)', () {
    test('does NOT flip OR→AND ("X or Y" collapses, does not become [X, Y])', () {
      expect(EquipmentVocab.normalize(['Cable Machine']), ['cables']);
      expect(EquipmentVocab.normalize(['Bodyweight or Dumbbells']), ['bodyweight']);
    });
    test('the 3 OR-mixed-AND rows keep their AND sibling', () {
      expect(EquipmentVocab.normalize(['Dumbbells or Barbell', 'Bench']),
          ['dumbbells', 'bench']); // E041
      expect(EquipmentVocab.normalize(['Dumbbell', 'Box or Bench']),
          ['dumbbells', 'bodyweight']); // E044 (Box→bodyweight outranks bench)
      expect(EquipmentVocab.normalize(['Bodyweight', 'Partner or Nordic Attachment']),
          ['bodyweight']); // E148 (dedup)
    });
    test('de-duplicates preserving first-seen order', () {
      expect(EquipmentVocab.normalize(['Cable Machine', 'Rope']), ['cables']); // E014
      expect(EquipmentVocab.normalize(['Barbell', 'Bench', 'Barbell']),
          ['barbell', 'bench']);
    });
    test('all-unmappable / null → [] (most-permissive)', () {
      expect(EquipmentVocab.normalize(['Spaceship', 'Wormhole']), isEmpty);
      expect(EquipmentVocab.normalize(null), isEmpty);
      expect(EquipmentVocab.normalize(<String>[]), isEmpty);
    });
    test('idempotent (canonical in → same out)', () {
      expect(EquipmentVocab.normalize(['cables', 'bench']), ['cables', 'bench']);
      expect(EquipmentVocab.normalize(['barbell', 'bodyweight']),
          ['barbell', 'bodyweight']);
    });
  });

  group('fromProfile (crash-safe extract + normalize)', () {
    test('List → normalized', () {
      expect(EquipmentVocab.fromProfile(['Cable Machine', 'Rope']), ['cables']);
    });
    test('bare String never throws (the ⑥ crash class e9d1c7)', () {
      expect(EquipmentVocab.fromProfile('Dumbbells'), ['dumbbells']);
    });
    test('null / empty / wrong-type → []', () {
      expect(EquipmentVocab.fromProfile(null), isEmpty);
      expect(EquipmentVocab.fromProfile(''), isEmpty);
      expect(EquipmentVocab.fromProfile(42), isEmpty);
    });
  });

  group('floorSanitizedExclusions (⑥ B1 seam — normalize + strip the floor)', () {
    test('normalizes to canonical + returns a Set', () {
      expect(EquipmentVocab.floorSanitizedExclusions(['Cable Machine', 'Dumbbells']),
          {'cables', 'dumbbells'});
    });
    test('STRIPS none/bodyweight — the floor is never excludable', () {
      // A user can never exclude the bodyweight floor, so a pure-bodyweight
      // exercise is never droppable + the att5 pool floor always survives.
      expect(EquipmentVocab.floorSanitizedExclusions(['bodyweight', 'cables']),
          {'cables'});
      expect(EquipmentVocab.floorSanitizedExclusions(['none', 'bodyweight']),
          isEmpty);
      expect(EquipmentVocab.floorSanitizedExclusions(['Bodyweight']), isEmpty);
    });
    test('null / empty / all-unmappable → empty Set (the no-op input)', () {
      expect(EquipmentVocab.floorSanitizedExclusions(null), isEmpty);
      expect(EquipmentVocab.floorSanitizedExclusions(const []), isEmpty);
      expect(EquipmentVocab.floorSanitizedExclusions(['Spaceship']), isEmpty);
    });
    test('de-dupes via the Set (Cable Machine + Rope → one cables)', () {
      expect(EquipmentVocab.floorSanitizedExclusions(['Cable Machine', 'Rope']),
          {'cables'});
    });
  });

  group('Behavioral: owned custom-exercise write normalizes equipment_needed', () {
    Directory? tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('eqvocab_test_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tempDir!.path,
      );
      Hive.init(tempDir!.path);
      GuardedBox.testBypassOwnership = true;
      await HiveService.instance.init();
      await HiveUserSession.openForUser(
        'eqvocab-test-12345678-aaaa-bbbb-cccc-dddddddddddd',
      );
    });

    tearDownAll(() async {
      GuardedBox.testBypassOwnership = false;
      await HiveUserSession.closeAll();
      await Hive.deleteFromDisk();
      await Hive.close();
      if (tempDir != null && await tempDir!.exists()) {
        await tempDir!.delete(recursive: true);
      }
    });

    test('createCustomExercise("Cable Machine") stores ["cables"] (write→read)',
        () async {
      final customBox = HiveService.instance.customBox;
      await customBox.clear();

      await WorkoutRepository.instance.createCustomExercise(
        name: 'Test Cable Row',
        category: 'Pull',
        equipment: 'Cable Machine',
        loggingType: 'weight_reps',
      );

      final row = customBox.values
          .whereType<Map>()
          .firstWhere((v) => v['name'] == 'Test Cable Row');
      expect(
        row['equipment_needed'],
        ['cables'],
        reason: 'the owned custom-write seam (workout_repository.dart:1375) must '
            'normalize the caller free-text equipment ("Cable Machine") to the '
            'canonical vocab ("cables") — writer/reader-drift class.',
      );
    });
  });
}
