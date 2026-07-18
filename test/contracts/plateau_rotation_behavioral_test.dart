// Batch 12-B (W3.5 plateau escalation) — rung-3 exercise rotation behavioral test
// (platform behavioral_test_path, §4.4 rule 21). Proves the write→read chain: seed
// Hive `exlog_*` flat plateaus for the compounds a persona actually trains, flip the
// flags, and assert the stuck lifts are ROTATED to same-pattern siblings via the
// cascade `avoidNames`/`_preferNovel` seam.
//
// NON-VACUOUS target derivation (Round-1 P1-2): the plateaued names are taken from a
// BASELINE (flag-OFF) plan — not a library scan — so "rotated out" is meaningful, and
// a broken rotation (avoidNames ignored) yields ON==OFF → RED. Seeds NO swap/custom
// history so the L6 post-pass (`_applyHistoryAdjustments`, gated on demoted/customs)
// is SKIPPED → deterministic. Deep-pool `full_gym`/`advanced` persona so siblings
// exist to rotate to.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plateau_scan.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box wb, hb, cb;
  final fixedToday = DateTime(2026, 6, 1, 12);
  String dk(DateTime d) => istDateStr(d);

  // Deep-pool persona → same-pattern siblings exist to rotate to.
  Phase gen(bool on, {List<String> injuries = const []}) =>
      PlanGenerator.instance.generateV4(
        goal: 'build_muscle',
        equipment: 'full_gym',
        daysPerWeek: 4,
        phase: 2,
        experienceLevel: 'advanced',
        injuries: injuries,
        applyPlateauEscalation: on,
      );

  Set<String> allNames(Phase p) {
    final out = <String>{};
    for (final w in p.weekPlans) {
      for (final d in w.workoutDays) {
        for (final e in d.exercises) {
          out.add(e.exerciseName.toLowerCase());
        }
      }
    }
    return out;
  }

  int totalExerciseCount(Phase p) {
    var n = 0;
    for (final w in p.weekPlans) {
      for (final d in w.workoutDays) {
        n += d.exercises.length;
      }
    }
    return n;
  }

  // The lowercased names in [p] that resolve to a library COMPOUND (rotation targets).
  Set<String> compoundNames(Phase p) {
    final repo = ExerciseRepository.instance;
    return allNames(p)
        .where((n) => repo.isCompoundByExactName(n))
        .toSet();
  }

  // Seed a flat (identical-weight) 3-session history spanning ≥28d for each name, so
  // PlateauScan flags every one. Unique keys per name/session.
  Future<void> seedPlateausFor(Iterable<String> names) async {
    const offsets = [35, 20, 5]; // 30d span, inside the 63d window
    var idx = 0;
    for (final name in names) {
      for (var s = 0; s < offsets.length; s++) {
        final d = fixedToday.subtract(Duration(days: offsets[s]));
        await wb.put('exlog_${dk(d)}_r${idx}_$s', {
          'exercise_name': name,
          'date': dk(d),
          'logging_type': 'weight_reps',
          'sets': [
            {'weight_kg': 100, 'reps_completed': 5}
          ],
        });
      }
      idx++;
    }
  }

  Future<void> seedReadiness(int n, {required bool flagged}) async {
    for (var i = 1; i <= n; i++) {
      final d = fixedToday.subtract(Duration(days: i));
      await hb.put('readiness_${dk(d)}', {
        'date': dk(d),
        'sleep': 0,
        'soreness': flagged ? 2 : 0,
        'energy': 0,
        'level': flagged ? 'yellow' : 'green',
      });
    }
  }

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('plateau_rotation');
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
      final id = (r['id'] ?? r['name']).toString();
      await exBox.put(id, Map<String, dynamic>.from(r));
    }
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
    wb = HiveService.instance.workoutBox;
    hb = HiveService.instance.healthBox;
    cb = HiveService.instance.configBox;
    setTestClockTo(fixedToday);
  });

  tearDownAll(() async {
    resetTestClock();
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await wb.clear();
    await hb.clear();
    await cb.clear();
    // Both gate flags ON by default (variety stays OFF unless a test enables it).
    await cb.put('enable_plateau_escalation', true);
    await cb.put('enable_readiness', true);
  });

  group('rung-3 rotation (Hive-seeded, baseline-derived targets)', () {
    test('plateaued compounds from the baseline plan are ROTATED OUT when ON',
        () async {
      final off = gen(false);
      final targets = compoundNames(off);
      expect(targets, isNotEmpty,
          reason: 'advanced/full_gym persona must train compounds');
      await seedPlateausFor(targets);
      await seedReadiness(3, flagged: false); // not fatigued
      final on = gen(true);
      final onNames = allNames(on);
      final stillPresent = targets.where(onNames.contains).toSet();
      // Rotation must remove at least one plateaued compound (deep pool → siblings).
      expect(stillPresent.length, lessThan(targets.length),
          reason: 'avoidNames must rotate ≥1 stuck compound to a same-pattern sibling');
    });

    test('independence: variety OFF + plateau ON → still rotates (12-B requirement)',
        () async {
      await cb.put('enable_cross_phase_variety', false); // explicit
      final off = gen(false);
      final targets = compoundNames(off);
      await seedPlateausFor(targets);
      await seedReadiness(3, flagged: false);
      final onNames = allNames(gen(true));
      expect(targets.where(onNames.contains).length, lessThan(targets.length),
          reason: 'rotation must fire under enable_plateau_escalation alone');
    });

    test('ship-dark: flag OFF → identical exercise set (byte-identical)', () async {
      await cb.put('enable_plateau_escalation', false);
      final off = gen(false);
      await seedPlateausFor(compoundNames(off));
      await seedReadiness(3, flagged: false);
      expect(allNames(gen(true)), allNames(gen(false)));
    });

    test('slot-count-invariance: rotation is a SWAP, not an add (count unchanged)',
        () async {
      final off = gen(false);
      await seedPlateausFor(compoundNames(off));
      await seedReadiness(3, flagged: false);
      // Total exercise COUNT identical ON vs OFF (only identities differ). Sets may
      // differ ±1 via default_sets — that is NOT asserted here.
      expect(totalExerciseCount(gen(true)), totalExerciseCount(off));
    });

    test('bounded: heavy rotation seeding never empties a slot / crashes', () async {
      final off = gen(false);
      await seedPlateausFor(compoundNames(off));
      await seedReadiness(3, flagged: false);
      final on = gen(true);
      // every day non-empty; every exercise a real (non-empty) name.
      for (final w in on.weekPlans) {
        for (final d in w.workoutDays) {
          expect(d.exercises, isNotEmpty);
          for (final e in d.exercises) {
            expect(e.exerciseName.trim(), isNotEmpty);
          }
        }
      }
    });

    test('injury-safe: rotation + shoulder injury → no contraindicated exercise',
        () async {
      final off = gen(false, injuries: ['shoulder']);
      await seedPlateausFor(compoundNames(off));
      await seedReadiness(3, flagged: false);
      final on = gen(true, injuries: ['shoulder']);
      final repo = ExerciseRepository.instance;
      for (final n in allNames(on)) {
        final row = repo.getByExactName(n);
        final ci = row?['injury_contraindications'];
        final tokens = ci is List ? ci.map((e) => e.toString().toLowerCase()) : const <String>[];
        expect(tokens.contains('shoulder'), isFalse,
            reason: '$n is shoulder-contraindicated but present in the plan');
      }
    });

    test('fatigued plateau → NO rotation (routes to deload rung)', () async {
      final off = gen(false);
      final targets = compoundNames(off);
      await seedPlateausFor(targets);
      await seedReadiness(3, flagged: true); // persistent red/yellow → fatigued
      // _fatiguePresent → plateauedExerciseNames {} → no avoid → identical set.
      expect(allNames(gen(true)), allNames(off));
    });

    test('both-coherence: titration + rotation ON → generates, still rotates',
        () async {
      await cb.put('enable_volume_titration', true);
      final off = gen(false);
      final targets = compoundNames(off);
      await seedPlateausFor(targets);
      await seedReadiness(3, flagged: false);
      final on = gen(true);
      expect(targets.where(allNames(on).contains).length, lessThan(targets.length));
      // Group sets stay MRV-bounded (no exercise's sets explode).
      for (final w in on.weekPlans) {
        for (final d in w.workoutDays) {
          for (final e in d.exercises) {
            expect(e.sets, lessThanOrEqualTo(20));
          }
        }
      }
    });
  });

  group('plateauedExerciseNames gates (Hive-seeded)', () {
    Future<Set<String>> seedOneFlatCompoundThenScan(int phase) async {
      // Discover a real compound + seed a flat plateau for it.
      final exBox = Hive.box(HiveService.exerciseBoxName);
      String comp = '';
      for (final v in exBox.values) {
        if (v is! Map) continue;
        final t = v['exercise_type'];
        final isComp = t is List
            ? t.any((e) => e.toString().toLowerCase() == 'compound')
            : (t as String?)?.toLowerCase() == 'compound';
        if (isComp != true) continue;
        comp = (v['name'] as String?) ?? '';
        if (comp.isNotEmpty) break;
      }
      await seedPlateausFor([comp]);
      return PlateauScan.plateauedExerciseNames(phase: phase);
    }

    test('seeded flat compound → its lowercased name present', () async {
      await seedReadiness(3, flagged: false);
      final names = await seedOneFlatCompoundThenScan(2);
      expect(names, isNotEmpty);
      expect(names.every((n) => n == n.toLowerCase()), isTrue);
    });

    test('flag OFF → {}', () async {
      await cb.put('enable_plateau_escalation', false);
      await seedReadiness(3, flagged: false);
      expect(await seedOneFlatCompoundThenScan(2), isEmpty);
    });

    test('readiness flag OFF → {}', () async {
      await cb.put('enable_readiness', false);
      await seedReadiness(3, flagged: false);
      expect(await seedOneFlatCompoundThenScan(2), isEmpty);
    });

    test('phase < 2 → {}', () async {
      await seedReadiness(3, flagged: false);
      expect(await seedOneFlatCompoundThenScan(1), isEmpty);
    });

    test('fatigued → {}', () async {
      await seedReadiness(3, flagged: true);
      expect(await seedOneFlatCompoundThenScan(2), isEmpty);
    });
  });
}
