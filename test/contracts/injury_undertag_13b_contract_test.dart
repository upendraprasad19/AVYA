// Batch 13-B — comprehensive injury tagging. Two-part regression guard:
//
//  (A) DATA CONTRACT — pins the EXACT injury_contraindications decision for every
//      row 13-B tagged (26 new + 2 deepened), as extended by the v14 injury
//      re-check where the founder's 2026-10-23 table adds to it, AND that the
//      33-row low-load / rehab safe pool (test/helpers/injury_safe_pool.dart)
//      stays untagged. A future edit that drops/adds a tag on any of these rows
//      fails here. (The 13-B "kept safe for variety" list was REJECTED by the
//      founder on 2026-10-23: only the v14 safe pool is untagged now.)
//  (B) BEHAVIORAL — drives the REAL generator (Hive + real library seeded) and proves
//      the new tags actually filter end-to-end: a hamstring / lower_back injured plan
//      contains ZERO of the newly-contraindicated exercises, with non-vacuity shown by
//      the same uninjured persona still getting them. Covers the hamstring token, which
//      injury_filter_behavioral_test.dart does not exercise.
//
// Why both: §4.4 rule 21 — the data contract pins the decision, the behavioral half
// proves the runtime path honors it (source-grep presence alone is false confidence).

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

import '../helpers/injury_safe_pool.dart';

/// The 13-B decisions, keyed by exercise id → EXACT expected (sorted) token set.
/// Five rows carry a v14 extension (founder table 2026-10-23): E057 +hip,
/// E074 +shoulder, E135 +shoulder, E101 +elbow, E022 +elbow.
const Map<String, List<String>> k13bExpected = {
  // cardio
  'E064': ['lower_back'], // Rowing Machine
  // core — advanced / loaded / support / hang (13-B kept the bodyweight crunch+sit-up
  // family safe; v14 tagged most of it, pinned in injury_recheck_v14_contract_test.dart)
  'E057': ['hip', 'lower_back', 'shoulder'], // Hanging Leg Raise (v14 +hip)
  'E071': ['shoulder', 'wrist'], // L-Sit Hold
  'E074': ['lower_back', 'shoulder'], // Dragon Flag (v14 +shoulder)
  'E134': ['hip'], // Copenhagen Plank (correction: NOT wrist)
  'E141': ['shoulder'], // Kettlebell Turkish Get Up
  'E172': ['lower_back'], // Dumbbell Side Bend
  'E199': ['shoulder'], // Half Turkish Get Up
  'E133': ['lower_back'], // Landmine Rotation
  'E135': ['shoulder', 'wrist'], // Bear Crawl (v14 +shoulder)
  'E136': ['shoulder', 'wrist'], // Crab Walk
  'E179': ['lower_back', 'shoulder'], // Toes to Bar
  'E180': ['lower_back', 'shoulder'], // Windshield Wiper
  // hip_dominant — hinges
  'E045': ['hamstring', 'lower_back'], // Romanian Deadlift
  'E046': ['hamstring', 'knee'], // Nordic Curl (correction: knee+hamstring, not lower_back)
  'E087': ['lower_back'], // Trap Bar Deadlift
  'E091': ['hamstring', 'lower_back'], // Single Leg Romanian Deadlift
  'E142': ['lower_back', 'shoulder'], // Medicine Ball Slam
  'E148': ['knee'], // Reverse Nordic Curl (correction: QUAD/knee, not hamstring/lower_back)
  // horizontal_pull — free bent-over
  'E116': ['lower_back'], // Meadows Row
  'E121': ['lower_back', 'shoulder', 'wrist'], // Renegade Row (B1 Task 1b, founder 2026-10-22: +shoulder +wrist)
  'E187': ['lower_back'], // Kettlebell Row
  // knee_dominant
  'E049': ['hamstring'], // Leg Curl (Lying)
  // vertical_pull — overhead dead-hang
  'E101': ['elbow', 'shoulder'], // Chest to Bar Pull Up (v14 +elbow)
  'E022': ['elbow', 'shoulder'], // Pull Up (v14 +elbow)
  // vertical_push — front raise (Goblet Press E186 is shoulder-tagged by v14, not here)
  'E015': ['shoulder'], // Front Raise
  // deepened existing rows (retag / union)
  'E178': ['hip', 'lower_back'], // GHD Sit Up — was [hip]
  'E092': ['hamstring', 'lower_back'], // Good Morning — was [lower_back]
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------- (A) DATA CONTRACT ----------
  group('13-B injury tags — data contract', () {
    late Map<String, Set<String>> byId;
    late Map<String, Set<String>> byName;

    setUpAll(() {
      final lib = jsonDecode(
        File('assets/data/exercise_library.json').readAsStringSync(),
      ) as List;
      byId = {};
      byName = {};
      for (final e in lib) {
        final m = Map<String, dynamic>.from(e as Map);
        final ic = m['injury_contraindications'];
        final toks = ic is List
            ? ic.map((t) => t.toString().toLowerCase()).toSet()
            : <String>{};
        byId[m['id'] as String] = toks;
        byName[(m['name'] as String).toLowerCase()] = toks;
      }
    });

    test('every 13-B row carries EXACTLY its expected injury tokens', () {
      k13bExpected.forEach((id, expected) {
        expect(byId[id], expected.toSet(),
            reason: '$id injury_contraindications drifted from the 13-B decision');
      });
    });

    test('corrections are exact (the dry-run heuristic mistakes stay fixed)', () {
      expect(byName['reverse nordic curl'], {'knee'},
          reason: 'Reverse Nordic is a QUAD/knee-extension move — never hamstring/lower_back');
      expect(byName['copenhagen plank'], {'hip'},
          reason: 'Copenhagen Plank is a forearm-supported adductor hold — never wrist');
      expect(byName['nordic curl'], {'hamstring', 'knee'},
          reason: 'Nordic Curl is kneeling knee-flexion — not a hip-hinge (no lower_back)');
      expect(byName['hollow body hold'], {'lower_back'},
          reason: 'Hollow Body is lower_back-tagged by the founder (2026-10-23): if the '
              'lower back lifts off the floor the hold strains it (never wrist)');
    });

    test('the injury-safe pool stays untagged (33 low-load / rehab rows, v14)', () {
      for (final n in kV14SafePool) {
        expect(byName[n.toLowerCase()], isNotNull,
            reason: 'safe-pool row "$n" missing from library');
        expect(byName[n.toLowerCase()], isEmpty,
            reason: '"$n" must stay untagged (low-load / rehab, founder table 2026-10-23)');
      }
      // Founder 2026-10-23, "wrist and shoulders": Push Up loads the shoulder too.
      expect(byName['push up'], {'shoulder', 'wrist'},
          reason: 'Push Up is wrist AND shoulder (founder 2026-10-23)');
    });

    test('vocabulary stays closed to the 9 canonical tokens', () {
      const canon = {
        'ankle', 'elbow', 'hamstring', 'hip', 'knee', 'lower_back', 'neck',
        'shoulder', 'wrist'
      };
      for (final toks in byId.values) {
        expect(canon.containsAll(toks), isTrue,
            reason: 'a non-canonical injury token leaked in: $toks');
      }
    });
  });

  // ---------- (B) BEHAVIORAL (real generator) ----------
  group('13-B injury tags — behavioral (real generator)', () {
    late Directory tempDir;
    late Map<String, Set<String>> contraByName;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('test_injury_13b');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => tempDir.path,
      );
      Hive.init(tempDir.path);
      GuardedBox.testBypassOwnership = true;
    });

    tearDownAll(() async {
      GuardedBox.testBypassOwnership = false;
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    setUp(() async {
      for (final name in [
        HiveService.workoutBoxName,
        HiveService.coachBoxName,
        HiveService.configBoxName,
        HiveService.migrationBoxName,
        HiveService.exerciseBoxName,
        'workoutBox_aaaaaaaa',
        'coachBox_aaaaaaaa',
        'userBox_aaaaaaaa',
      ]) {
        if (Hive.isBoxOpen(name)) await Hive.box(name).close();
        try {
          await Hive.deleteBoxFromDisk(name);
        } catch (_) {}
      }
      await Hive.openBox(HiveService.configBoxName);
      await Hive.openBox(HiveService.migrationBoxName);
      final exBox = await Hive.openBox(HiveService.exerciseBoxName);
      final lib = jsonDecode(
        File('assets/data/exercise_library.json').readAsStringSync(),
      ) as List;
      contraByName = {};
      for (final e in lib) {
        final m = Map<String, dynamic>.from(e as Map);
        await exBox.put(m['id'], m);
        final ic = m['injury_contraindications'];
        contraByName[(m['name'] as String).toLowerCase()] = ic is List
            ? ic.map((t) => t.toString().toLowerCase()).toSet()
            : <String>{};
      }
      HiveService.instance.markInitializedForTests();
      await HiveUserSession.openForUser('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
    });

    tearDown(() async {
      await HiveUserSession.closeAll();
    });

    Set<String> injuryHits(Phase phase, Set<String> injuries) {
      final hits = <String>{};
      for (final wp in phase.weekPlans) {
        for (final day in wp.workoutDays) {
          for (final ex in day.exercises) {
            final contra = contraByName[ex.exerciseName.toLowerCase()] ?? const {};
            hits.addAll(contra.intersection(injuries));
          }
        }
      }
      return hits;
    }

    Phase gen(List<String> injuries, {String equipment = 'full_gym'}) =>
        PlanGenerator.instance.generate(
          goal: 'build_muscle',
          equipment: equipment,
          daysPerWeek: 4,
          phase: 1,
          experienceLevel: 'advanced',
          injuries: injuries,
        );

    test('hamstring injury → NO hamstring-contra exercise (13-B enables this token)',
        () {
      final phase = gen(['hamstring']);
      expect(phase.weekPlans, isNotEmpty);
      expect(injuryHits(phase, {'hamstring'}), isEmpty,
          reason: 'RDL/Nordic/Leg-Curl etc. are now hamstring-tagged (13-B) → excluded');
    });

    test('non-vacuity: uninjured persona DOES get hamstring-loaded exercises', () {
      expect(injuryHits(gen(const []), {'hamstring'}), isNotEmpty,
          reason: 'an uninjured full_gym plan must contain ≥1 hamstring-loaded lift, '
              'else the hamstring test above would pass vacuously');
    });

    test('lower_back injury → NO lower_back-contra exercise at a hinge-heavy tier', () {
      final phase = gen(['lower_back'], equipment: 'home_dumbbells');
      expect(phase.weekPlans, isNotEmpty);
      expect(injuryHits(phase, {'lower_back'}), isEmpty,
          reason: 'RDL / bent rows / loaded-flexion core are now lower_back-tagged (13-B)');
    });
  });
}
