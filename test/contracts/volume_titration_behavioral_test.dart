// Batch 9 (W2.7) — volume titration behavioral test (platform behavioral_test_path,
// §4.4 rule 21). Two halves:
//   • PURE `applyToWeeks` (budgeted, flip 2026-11-02) — inertness (identical ref on
//     empty), per-group ±1 within the budget's band, multi-group dedup,
//     deload-week `workingSets` symmetry.
//   • Hive-seeded `resolveDeltas` — SAFE polarity (−1 on e1RM decline alone; +1
//     ONLY with positive readiness recovery evidence) + the flag/phase gates.
//
// The Hive harness mirrors `deload_eval_behavioral_test.dart` (clock seam, guarded
// per-user boxes, seeded exercise library). Per Round-2 R2-2 the resolveDeltas
// cases seed a BARE-token library lift (primary maps cleanly to a major group),
// never a qualifier-tagged / empty-primary one.

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
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/volume_titration.dart';

import '../helpers/session_budget_fixtures.dart';

// ── pure builders ──
PlannedExercise _ex(String name, int sets, List<String> muscles,
        {int? workingSets}) =>
    PlannedExercise(
      exerciseId: name,
      exerciseName: name,
      loggingType: 'weight_reps',
      sets: sets,
      reps: '10',
      restSeconds: 90,
      primaryMuscles: muscles,
      workingSets: workingSets,
    );

WeekPlan _week(String character, List<List<PlannedExercise>> days) => WeekPlan(
      weekNumber: 1,
      weekInPhase: 1,
      overloadNotes: '',
      weekCharacter: character,
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

  // The flip (2026-11-02) deleted the unbudgeted clamp [MEV=8, MRV=20]; titration
  // is the budget's own: bottom 12 / top 16 for intermediate build_muscle, a +1
  // must fit the ledger (session cap 8, every co-group's top, the day's time), a
  // -1 may not take a credited group below the bottom, only budgeted rows move.
  group('applyToWeeks (pure, budgeted)', () {
    SessionBudgetContext b(Iterable<String> names) => testBudget(names: names);

    test('empty deltas → IDENTICAL reference (byte-identical inertness)', () {
      final weeks = [
        _week('baseline', [
          [_ex('Bench', 3, ['Chest'])]
        ])
      ];
      expect(
          identical(weeks,
              VolumeTitration.applyToWeeks(weeks, const {}, budget: b(['Bench']))),
          isTrue);
    });

    test('+1 bumps exactly one matching exercise; below the top', () {
      final weeks = [
        _week('baseline', [
          [_ex('Bench', 3, ['Chest']), _ex('Fly', 3, ['Chest'])]
        ])
      ];
      final out = VolumeTitration.applyToWeeks(weeks, const {'Chest': 1},
          budget: b(['Bench', 'Fly']));
      expect(_groupWeeklySets(out.first, 'Chest'), 7); // 6 → 7, one exercise
      final exs = out.first.workoutDays.first.exercises;
      expect(exs.where((e) => e.sets == 4).length, 1);
      expect(exs.where((e) => e.sets == 3).length, 1);
    });

    test('+1 refused at the weekly top (16 for intermediate build_muscle)', () {
      final weeks = [
        _week('baseline', [
          [_ex('a', 4, ['Chest']), _ex('b', 4, ['Chest'])],
          [_ex('c', 4, ['Chest']), _ex('d', 4, ['Chest'])],
        ])
      ];
      final out = VolumeTitration.applyToWeeks(weeks, const {'Chest': 1},
          budget: b(['a', 'b', 'c', 'd']));
      expect(_groupWeeklySets(out.first, 'Chest'), 16); // unchanged
    });

    test('+1 refused at the per-session cap (8 for intermediate)', () {
      final weeks = [
        _week('baseline', [
          [_ex('a', 4, ['Chest']), _ex('b', 4, ['Chest'])],
        ])
      ];
      final out = VolumeTitration.applyToWeeks(weeks, const {'Chest': 1},
          budget: b(['a', 'b']));
      expect(_groupWeeklySets(out.first, 'Chest'), 8); // unchanged, 8 in one day
    });

    test('−1 trims one exercise (above the bottom, 12)', () {
      final weeks = [
        _week('baseline', [
          [_ex('a', 4, ['Chest']), _ex('b', 4, ['Chest'])],
          [_ex('c', 5, ['Chest'])],
        ])
      ];
      final out = VolumeTitration.applyToWeeks(weeks, const {'Chest': -1},
          budget: b(['a', 'b', 'c']));
      expect(_groupWeeklySets(out.first, 'Chest'), 12); // 13 → 12, one exercise
    });

    test('−1 no-op at the bottom (never trims a group below 12)', () {
      final weeks = [
        _week('baseline', [
          [_ex('a', 3, ['Chest']), _ex('b', 3, ['Chest'])],
          [_ex('c', 3, ['Chest']), _ex('d', 3, ['Chest'])],
        ])
      ];
      final out = VolumeTitration.applyToWeeks(weeks, const {'Chest': -1},
          budget: b(['a', 'b', 'c', 'd']));
      expect(_groupWeeklySets(out.first, 'Chest'), 12); // == bottom → unchanged
    });

    test('−1 respects the per-exercise sets≥1 floor', () {
      // 13 chest exercises x 1 set → weekly 13 (> bottom) but every match is
      // already at 1 → the −1 applies nowhere.
      final weeks = [
        _week('baseline', [
          [for (var i = 0; i < 7; i++) _ex('c$i', 1, ['Chest'])],
          [for (var i = 7; i < 13; i++) _ex('c$i', 1, ['Chest'])],
        ])
      ];
      final out = VolumeTitration.applyToWeeks(weeks, const {'Chest': -1},
          budget: b([for (var i = 0; i < 13; i++) 'c$i']));
      expect(_groupWeeklySets(out.first, 'Chest'), 13); // unchanged (floored)
      expect(
          out.first.workoutDays
              .every((d) => d.exercises.every((e) => e.sets == 1)),
          isTrue);
    });

    test('multi-group exercise bumped AT MOST once per week (dedup)', () {
      final weeks = [
        _week('baseline', [
          [_ex('Bench', 3, ['Chest', 'Triceps'])]
        ])
      ];
      final out = VolumeTitration.applyToWeeks(
          weeks, const {'Chest': 1, 'Triceps': 1},
          budget: b(['Bench']));
      // Bench matches BOTH deltas but is adjusted once → 4, not 5.
      expect(out.first.workoutDays.first.exercises.first.sets, 4);
    });

    test('deload week: visible sets untouched, workingSets bumped symmetrically',
        () {
      final weeks = [
        _week('deload', [
          [_ex('Bench', 2, ['Chest'], workingSets: 4)]
        ])
      ];
      final out = VolumeTitration.applyToWeeks(weeks, const {'Chest': 1},
          budget: b(['Bench']));
      final e = out.first.workoutDays.first.exercises.first;
      expect(e.sets, 2); // recovery week visible sets preserved
      expect(e.workingSets, 5); // stashed peak titrated 4 → 5 (under the 5-set limit)
    });

    test('deload week with NO stash (workingSets null) → nothing changes', () {
      final weeks = [
        _week('deload', [
          [_ex('Bench', 2, ['Chest'])]
        ])
      ];
      final out = VolumeTitration.applyToWeeks(weeks, const {'Chest': 1},
          budget: b(['Bench']));
      final e = out.first.workoutDays.first.exercises.first;
      expect(e.sets, 2);
      expect(e.workingSets, isNull);
    });

    test('a group with no matching exercise this week is a safe no-op', () {
      final weeks = [
        _week('baseline', [
          [_ex('Squat', 3, ['Quads'])]
        ])
      ];
      final out = VolumeTitration.applyToWeeks(weeks, const {'Chest': 1},
          budget: b(['Squat']));
      expect(out.first.workoutDays.first.exercises.first.sets, 3);
    });

    test('a NOT-budgeted row (no library row) is never titrated', () {
      final weeks = [
        _week('baseline', [
          [_ex('Bench', 3, ['Chest'])]
        ])
      ];
      final out = VolumeTitration.applyToWeeks(weeks, const {'Chest': 1},
          budget: b(const [])); // Bench absent from archetypeByName
      expect(out.first.workoutDays.first.exercises.first.sets, 3);
    });
  });

  group('resolveDeltas (Hive-seeded)', () {
    late Directory tempDir;
    late Box wb, hb, cb;
    late String titName;
    late String titGroup;
    final fixedToday = DateTime(2026, 6, 1, 12);
    String dk(DateTime d) => istDateStr(d);

    Future<void> seedTrend(String name,
        {required int olderW, required int newerW}) async {
      final d1 = fixedToday.subtract(const Duration(days: 6)); // older
      final d2 = fixedToday.subtract(const Duration(days: 2)); // newer
      await wb.put('exlog_${dk(d1)}_x', {
        'exercise_name': name,
        'date': dk(d1),
        'logging_type': 'weight_reps',
        'sets': [
          {'weight_kg': olderW, 'reps_completed': 5}
        ],
      });
      await wb.put('exlog_${dk(d2)}_x', {
        'exercise_name': name,
        'date': dk(d2),
        'logging_type': 'weight_reps',
        'sets': [
          {'weight_kg': newerW, 'reps_completed': 5}
        ],
      });
    }

    Future<void> seedReadiness(int n, int soreness) async {
      for (int i = 1; i <= n; i++) {
        final d = fixedToday.subtract(Duration(days: i));
        await hb.put('readiness_${dk(d)}', {
          'date': dk(d),
          'sleep': 0,
          'soreness': soreness,
          'energy': 0,
          'level': soreness >= 2 ? 'red' : 'green',
        });
      }
    }

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('vol_titration');
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
      // Discover a real library lift whose FIRST primary_muscles token maps to a
      // major group (a BARE token — never a qualifier-tagged / empty-primary row).
      titName = '';
      titGroup = '';
      for (final v in exBox.values) {
        if (v is! Map) continue;
        final pm = v['primary_muscles'];
        if (pm is! List || pm.isEmpty) continue;
        final g = muscleGroupOf(pm.first.toString());
        if (g != null) {
          titName = (v['name'] as String?) ?? '';
          titGroup = g;
          if (titName.isNotEmpty) break;
        }
      }
      expect(titName, isNotEmpty,
          reason: 'library must have a group-mappable lift');
      HiveService.instance.markInitializedForTests();
      await HiveUserSession.openForUser(
          'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
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
    });

    test('flag OFF → {}', () async {
      await seedTrend(titName, olderW: 95, newerW: 90); // would be −1 if ON
      final d = VolumeTitration.resolveDeltas(phase: 2);
      expect(d, isEmpty);
    });

    test('phase < 2 → {} even with the flag ON', () async {
      await cb.put('enable_volume_titration', true);
      await seedTrend(titName, olderW: 95, newerW: 90);
      expect(VolumeTitration.resolveDeltas(phase: 1), isEmpty);
    });

    test('declining e1RM → group −1 (no readiness needed — safe direction)',
        () async {
      await cb.put('enable_volume_titration', true);
      await seedTrend(titName, olderW: 95, newerW: 90); // latest < prior
      final d = VolumeTitration.resolveDeltas(phase: 2);
      expect(d[titGroup], -1);
    });

    test('held/gained + recovered readiness (≥3 low-soreness) → group +1',
        () async {
      await cb.put('enable_volume_titration', true);
      await seedTrend(titName, olderW: 90, newerW: 95); // latest ≥ prior
      await seedReadiness(3, 0); // recovered
      final d = VolumeTitration.resolveDeltas(phase: 2);
      expect(d[titGroup], 1);
    });

    test('held/gained + NO readiness → hold (no +1; the SAFE default)', () async {
      await cb.put('enable_volume_titration', true);
      await seedTrend(titName, olderW: 90, newerW: 95);
      // no readiness rows at all
      final d = VolumeTitration.resolveDeltas(phase: 2);
      expect(d.containsKey(titGroup), isFalse);
    });

    test('held/gained + systemic soreness (persistent beat-up) → hold', () async {
      await cb.put('enable_volume_titration', true);
      await seedTrend(titName, olderW: 90, newerW: 95);
      await seedReadiness(3, 2); // 3/3 beat-up → systemic fatigue
      final d = VolumeTitration.resolveDeltas(phase: 2);
      expect(d.containsKey(titGroup), isFalse);
    });

    test('sparse readiness (< 3 rows) → not "recovered" → no +1', () async {
      await cb.put('enable_volume_titration', true);
      await seedTrend(titName, olderW: 90, newerW: 95);
      await seedReadiness(2, 0); // only 2 → insufficient sample
      final d = VolumeTitration.resolveDeltas(phase: 2);
      expect(d.containsKey(titGroup), isFalse);
    });

    test('deterministic across repeated calls (sorted-group iteration)',
        () async {
      await cb.put('enable_volume_titration', true);
      await seedTrend(titName, olderW: 95, newerW: 90);
      final a = VolumeTitration.resolveDeltas(phase: 2);
      final b = VolumeTitration.resolveDeltas(phase: 2);
      expect(a.keys.toList(), b.keys.toList());
      expect(a[titGroup], b[titGroup]);
    });
  });
}
