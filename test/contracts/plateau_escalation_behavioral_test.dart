// Batch 12-A (W3.5 plateau escalation) — behavioral test (platform
// behavioral_test_path, §4.4 rule 21). Proves the write→read chain: seed Hive
// `exlog_*` (compound e1RM history) + `readiness_*`, flip the flags, and assert
// the detected groups / merged deltas / applied sets.
//
// Three groups:
//   • plateauedGroups — the detector gates (flag / readiness-flag / phase / fatigue
//     / ≥3-session / ≥28d-span / flatness / compound-only).
//   • mergePlateauSetDeltas — the rung-2 merge (adds +1 where absent; NEVER
//     overrides a titration ±1 → no double-bump / a declining group's −1 wins;
//     flag OFF → same ref → byte-identical).
//   • end-to-end merge → applyToWeeks — the group's real weekly sets move (+1 flat,
//     net −1 on the declining∧flat safety case, clamped at MRV).
//
// Harness mirrors `volume_titration_behavioral_test.dart` (clock seam, guarded
// per-user boxes, seeded exercise library) — but discovers a COMPOUND
// group-mappable lift (plateau is main-lift-only).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/muscle_groups.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plateau_scan.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/volume_titration.dart';

PlannedExercise _ex(String name, int sets, List<String> muscles) =>
    PlannedExercise(
      exerciseId: name,
      exerciseName: name,
      loggingType: 'weight_reps',
      sets: sets,
      reps: '5',
      restSeconds: 120,
      primaryMuscles: muscles,
    );

WeekPlan _week(List<List<PlannedExercise>> days) => WeekPlan(
      weekNumber: 1,
      weekInPhase: 1,
      overloadNotes: '',
      weekCharacter: 'baseline',
      workoutDays: [
        for (var i = 0; i < days.length; i++)
          WorkoutDay(
              dayNumber: i + 1, name: 'D$i', focus: '', exercises: days[i]),
      ],
    );

int _groupWeeklySets(WeekPlan w, String group) {
  var s = 0;
  for (final d in w.workoutDays) {
    for (final e in d.exercises) {
      if ((e.primaryMuscles ?? const []).any((m) => muscleGroupOf(m) == group)) {
        s += e.sets;
      }
    }
  }
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box wb, hb, cb;
  late String compName; // a real library COMPOUND lift
  late String compGroup; // its major group
  late String compToken; // a primary_muscles token mapping to compGroup
  final fixedToday = DateTime(2026, 6, 1, 12);
  String dk(DateTime d) => istDateStr(d);

  // Seed `values.length` compound sessions on distinct IST days [offsets] ago.
  // e1RM ∝ weight (reps fixed at 5), so the value list IS the e1RM shape.
  Future<void> seedSessions(
      String name, List<num> values, List<int> offsets) async {
    for (var i = 0; i < values.length; i++) {
      final d = fixedToday.subtract(Duration(days: offsets[i]));
      await wb.put('exlog_${dk(d)}_$i', {
        'exercise_name': name,
        'date': dk(d),
        'logging_type': 'weight_reps',
        'sets': [
          {'weight_kg': values[i], 'reps_completed': 5}
        ],
      });
    }
  }

  // [flagged] rows are yellow (soreness=2 → 1 flag → level != green); else green.
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

  // A ≥3-session, ≥28d-span, flat (identical) compound history — the canonical
  // plateau. Offsets -35/-20/-5 → 30d span, inside the 63d window.
  Future<void> seedFlatPlateau() =>
      seedSessions(compName, const [100, 100, 100], const [35, 20, 5]);

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('plateau_scan');
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
    // Discover a real COMPOUND lift whose first primary_muscles token maps to a
    // major group (plateau escalates main lifts only, aggregated by group).
    compName = '';
    compGroup = '';
    compToken = '';
    for (final v in exBox.values) {
      if (v is! Map) continue;
      final t = v['exercise_type'];
      final isCompound = t is List
          ? t.any((e) => e.toString().toLowerCase() == 'compound')
          : (t as String?)?.toLowerCase() == 'compound';
      if (isCompound != true) continue;
      final pm = v['primary_muscles'];
      if (pm is! List || pm.isEmpty) continue;
      final g = muscleGroupOf(pm.first.toString());
      if (g != null) {
        compName = (v['name'] as String?) ?? '';
        compGroup = g;
        compToken = pm.first.toString();
        if (compName.isNotEmpty) break;
      }
    }
    expect(compName, isNotEmpty,
        reason: 'library must have a group-mappable COMPOUND lift');
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
    // Default: BOTH gate flags ON so a case only has to seed data. Individual
    // tests override to pin the flag gates.
    await cb.put('enable_plateau_escalation', true);
    await cb.put('enable_readiness', true);
  });

  group('plateauedGroups (Hive-seeded detector)', () {
    test('flat compound + sparse readiness (net-new: no readiness rows) → detects',
        () async {
      await seedFlatPlateau(); // no readiness rows → not fatigued (n<3)
      final g = PlateauScan.plateauedGroups(phase: 2);
      expect(g, contains(compGroup));
    });

    test('flat compound + 3 GREEN readiness (not fatigued) → detects', () async {
      await seedFlatPlateau();
      await seedReadiness(3, flagged: false);
      expect(PlateauScan.plateauedGroups(phase: 2), contains(compGroup));
    });

    test('persistent fatigue (3 flagged) → {} (deload rung, not +sets)', () async {
      await seedFlatPlateau();
      await seedReadiness(3, flagged: true); // majority non-green → fatigued
      expect(PlateauScan.plateauedGroups(phase: 2), isEmpty);
    });

    test('plateau flag OFF → {}', () async {
      await cb.put('enable_plateau_escalation', false);
      await seedFlatPlateau();
      expect(PlateauScan.plateauedGroups(phase: 2), isEmpty);
    });

    test('readiness flag OFF (flag-ordering) → {} even with plateau ON', () async {
      await cb.put('enable_readiness', false);
      await seedFlatPlateau();
      expect(PlateauScan.plateauedGroups(phase: 2), isEmpty);
    });

    test('phase < 2 (self-gate) → {}', () async {
      await seedFlatPlateau();
      expect(PlateauScan.plateauedGroups(phase: 1), isEmpty);
    });

    test('< 3 sessions → {} (min-session gate)', () async {
      await seedSessions(compName, const [100, 100], const [30, 5]); // only 2
      expect(PlateauScan.plateauedGroups(phase: 2), isEmpty);
    });

    test('span < 28 days → {} (min-span gate)', () async {
      // 3 sessions but only a 9-day span.
      await seedSessions(compName, const [100, 100, 100], const [10, 5, 1]);
      expect(PlateauScan.plateauedGroups(phase: 2), isEmpty);
    });

    test('progressing (> 5% range) → {} (not a plateau)', () async {
      await seedSessions(compName, const [100, 106, 112], const [35, 20, 5]);
      expect(PlateauScan.plateauedGroups(phase: 2), isEmpty);
    });

    test('isolation (non-compound) lift, flat → {} (compound-only)', () async {
      // Discover an ISOLATION lift; if the library has none, the gate is vacuous.
      final exBox = Hive.box(HiveService.exerciseBoxName);
      String iso = '';
      for (final v in exBox.values) {
        if (v is! Map) continue;
        final t = v['exercise_type'];
        final isCompound = t is List
            ? t.any((e) => e.toString().toLowerCase() == 'compound')
            : (t as String?)?.toLowerCase() == 'compound';
        if (isCompound == true) continue;
        final pm = v['primary_muscles'];
        if (pm is! List || pm.isEmpty) continue;
        if (muscleGroupOf(pm.first.toString()) == null) continue;
        iso = (v['name'] as String?) ?? '';
        if (iso.isNotEmpty) break;
      }
      if (iso.isEmpty) return; // no isolation lift to test — gate vacuously holds
      await seedSessions(iso, const [100, 100, 100], const [35, 20, 5]);
      expect(PlateauScan.plateauedGroups(phase: 2), isEmpty);
    });
  });

  group('mergePlateauSetDeltas (rung-2 merge)', () {
    test('plateau detected + empty existing → {group: +1}', () async {
      await seedFlatPlateau();
      final merged = PlateauScan.mergePlateauSetDeltas(const {}, phase: 2);
      expect(merged[compGroup], 1);
    });

    test('no double-bump: existing +1 (titration) stays +1', () async {
      await seedFlatPlateau();
      final merged =
          PlateauScan.mergePlateauSetDeltas({compGroup: 1}, phase: 2);
      expect(merged[compGroup], 1); // putIfAbsent no-op, NOT +2
    });

    test('respect decline: existing −1 stays −1 (never +sets a declining group)',
        () async {
      await seedFlatPlateau();
      final merged =
          PlateauScan.mergePlateauSetDeltas({compGroup: -1}, phase: 2);
      expect(merged[compGroup], -1);
    });

    test('flag OFF → returns existing UNCHANGED (same ref → byte-identical)',
        () async {
      await cb.put('enable_plateau_escalation', false);
      await seedFlatPlateau();
      const existing = <String, int>{'Chest': 1};
      final merged = PlateauScan.mergePlateauSetDeltas(existing, phase: 2);
      expect(identical(existing, merged), isTrue);
    });
  });

  group('end-to-end: merge → applyToWeeks', () {
    test('flat plateau → the group gains +1 weekly set (below MRV)', () async {
      await seedFlatPlateau();
      final deltas = PlateauScan.mergePlateauSetDeltas(const {}, phase: 2);
      final weeks = [
        _week([
          [_ex(compName, 3, [compToken])]
        ])
      ];
      final out = VolumeTitration.applyToWeeks(weeks, deltas);
      expect(_groupWeeklySets(out.first, compGroup), 4); // 3 → 4
    });

    test('SAFETY: declining∧flat (titration −1 + plateau flat) → net −1, never +1',
        () async {
      await cb.put('enable_volume_titration', true);
      // [100,100,100,98] over 31d: titration sees latest 98 < prior 100 → −1;
      // plateau sees 2% range → flat. Merge must keep −1 (putIfAbsent no-op).
      await seedSessions(
          compName, const [100, 100, 100, 98], const [33, 20, 10, 2]);
      await seedReadiness(3, flagged: false); // recovered → titration would +1 IF held
      final base = VolumeTitration.resolveDeltas(phase: 2);
      expect(base[compGroup], -1, reason: 'titration trims a declining group');
      final merged = PlateauScan.mergePlateauSetDeltas(base, phase: 2);
      expect(merged[compGroup], -1, reason: 'plateau must NOT override the −1');
      final weeks = [
        _week([
          [_ex(compName, 5, [compToken]), _ex('${compName}_b', 5, [compToken])]
        ])
      ];
      final out = VolumeTitration.applyToWeeks(weeks, merged);
      expect(_groupWeeklySets(out.first, compGroup), 9); // 10 → 9 (trim, not +1)
    });

    test('+1 clamped at MRV (group already ≥20 → no bump)', () async {
      await seedFlatPlateau();
      final deltas = PlateauScan.mergePlateauSetDeltas(const {}, phase: 2);
      final weeks = [
        _week([
          [_ex(compName, 10, [compToken]), _ex('${compName}_b', 10, [compToken])]
        ])
      ];
      final out = VolumeTitration.applyToWeeks(weeks, deltas);
      expect(_groupWeeklySets(out.first, compGroup), 20); // unchanged
    });
  });

  group('end-to-end: generateV4 entry-point (Stage 4.5 glue)', () {
    // Seed one flat plateau per distinct major group so whatever the persona
    // trains, some trained group has plateaued (unique keys per exercise).
    Future<void> seedManyCompoundPlateaus() async {
      final exBox = Hive.box(HiveService.exerciseBoxName);
      final seededGroups = <String>{};
      var ex = 0;
      for (final v in exBox.values) {
        if (v is! Map) continue;
        final t = v['exercise_type'];
        final isCompound = t is List
            ? t.any((e) => e.toString().toLowerCase() == 'compound')
            : (t as String?)?.toLowerCase() == 'compound';
        if (isCompound != true) continue;
        final pm = v['primary_muscles'];
        if (pm is! List || pm.isEmpty) continue;
        final g = muscleGroupOf(pm.first.toString());
        if (g == null || seededGroups.contains(g)) continue;
        final name = (v['name'] as String?) ?? '';
        if (name.isEmpty) continue;
        seededGroups.add(g);
        const offsets = [35, 20, 5];
        for (var s = 0; s < 3; s++) {
          final d = fixedToday.subtract(Duration(days: offsets[s]));
          await wb.put('exlog_${dk(d)}_ex${ex}_$s', {
            'exercise_name': name,
            'date': dk(d),
            'logging_type': 'weight_reps',
            'sets': [
              {'weight_kg': 100, 'reps_completed': 5}
            ],
          });
        }
        ex++;
      }
    }

    int totalSets(Phase p) {
      var s = 0;
      for (final w in p.weekPlans) {
        for (final d in w.workoutDays) {
          for (final e in d.exercises) {
            s += e.sets;
          }
        }
      }
      return s;
    }

    Phase gen(bool on) => PlanGenerator.instance.generateV4(
          goal: 'build_muscle',
          equipment: 'full_gym',
          daysPerWeek: 4,
          phase: 2,
          experienceLevel: 'intermediate',
          applyPlateauEscalation: on,
        );

    test('applyPlateauEscalation:true adds volume vs :false (real entry point)',
        () async {
      await seedManyCompoundPlateaus();
      await seedReadiness(3, flagged: false); // not fatigued
      final off = totalSets(gen(false));
      final onT = totalSets(gen(true));
      expect(onT, greaterThan(off),
          reason: 'plateau +sets must flow through generateV4 Stage 4.5');
    });

    test('kill-switch OFF → the applyPlateauEscalation param is inert end-to-end',
        () async {
      await cb.put('enable_plateau_escalation', false);
      await seedManyCompoundPlateaus();
      await seedReadiness(3, flagged: false);
      expect(totalSets(gen(true)), totalSets(gen(false)));
    });
  });
}
