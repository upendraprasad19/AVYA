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
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/volume_titration.dart';

import '../helpers/session_budget_fixtures.dart';

// ── pure builders ──
PlannedExercise _ex(String name, int sets, List<String> muscles,
        {int? workingSets, String? type}) =>
    PlannedExercise(
      exerciseId: name,
      exerciseName: name,
      loggingType: 'weight_reps',
      sets: sets,
      reps: '10',
      restSeconds: 90,
      primaryMuscles: muscles,
      workingSets: workingSets,
      exerciseType: type,
    );

List<List<int>> _sets(WeekPlan w) => [
      for (final d in w.workoutDays) [for (final e in d.exercises) e.sets]
    ];

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

  // Generator step 4 (OI-53, plan docs/plans/2026-11-16-generator-step4-titration-plateau.md): the ±1 keeps 2A's
  // lead-first rule. The day's lead is SequencingEngine.openerOf over its budgeted rows (a compound before an
  // isolation, whatever the slot), so these fixtures put an isolation row FIRST to tell the lead from slot 0.
  group('step 4: lead-first titration (T1-T3)', () {
    SessionBudgetContext b(Iterable<String> names, {Set<String> focus = const {}}) =>
        testBudget(names: names, focus: focus);

    // Fly (isolation, slot 0) at 4, Bench (compound, the lead) at 3.
    List<WeekPlan> flyFirst() => [
          _week('baseline', [
            [_ex('Fly', 4, ['Chest'], type: 'isolation'), _ex('Bench', 3, ['Chest'], type: 'compound')]
          ])
        ];

    test('T1: a +1 never takes a non-lead row past the lead + 1; it rolls to the lead', () {
      final out = VolumeTitration.applyToWeeks(flyFirst(), const {'Chest': 1}, budget: b(['Fly', 'Bench']));
      // Fly is first in slot order but 4 > the lead's 3: refused; Bench (the openerOf lead) takes it.
      expect(_sets(out.first), [[4, 4]]);
    });

    test('T1: leadFirst false switches the rule off (slot order, first that fits)', () {
      final out = VolumeTitration.applyToWeeks(flyFirst(), const {'Chest': 1},
          budget: b(['Fly', 'Bench']), leadFirst: false);
      expect(_sets(out.first), [[5, 3]]);
    });

    test('T1: a row crediting a focus group is exempt (R5, d27)', () {
      final out = VolumeTitration.applyToWeeks(flyFirst(), const {'Chest': 1},
          budget: b(['Fly', 'Bench'], focus: {'Chest'}));
      expect(_sets(out.first), [[5, 3]]);
    });

    test('T1: the lead is read at that moment (an earlier group\'s +1 on the lead lets a row follow)', () {
      // Groups run sorted: Chest first gives Bench (the lead) 2 -> 3; then Triceps: Pushdown at 3 is within the
      // lead's 3 + 1 only after that +1.
      final weeks = [
        _week('baseline', [
          [
            _ex('Pushdown', 3, ['Triceps'], type: 'isolation'),
            _ex('Bench', 2, ['Chest', 'Triceps'], type: 'compound'),
          ]
        ])
      ];
      final out = VolumeTitration.applyToWeeks(weeks, const {'Chest': 1, 'Triceps': 1},
          budget: b(['Pushdown', 'Bench']));
      expect(_sets(out.first), [[4, 3]]);
    });

    test('T2: a -1 takes the most sets first, ties to the latest day', () {
      final weeks = [
        _week('baseline', [
          [_ex('Bench', 4, ['Chest'], type: 'compound'), _ex('Fly', 3, ['Chest'], type: 'isolation')],
          [_ex('Press', 3, ['Chest'], type: 'compound'), _ex('Fly2', 4, ['Chest'], type: 'isolation')],
        ])
      ]; // 14, above the bottom (12)
      final out = VolumeTitration.applyToWeeks(weeks, const {'Chest': -1},
          budget: b(['Bench', 'Fly', 'Press', 'Fly2']));
      // Bench and Fly2 tie at 4: the latest day's row goes (d65's "latest rank", across days).
      expect(_sets(out.first), [[4, 3], [3, 3]]);
    });

    test('T2: a -1 never takes a row below 2 sets (d65)', () {
      final weeks = [
        _week('baseline', [
          [for (var i = 0; i < 4; i++) _ex('c$i', 2, ['Chest'], type: 'isolation')],
          [for (var i = 4; i < 7; i++) _ex('c$i', 2, ['Chest'], type: 'isolation')],
        ])
      ]; // 14 sets, above the bottom, but every row is at 2
      final out = VolumeTitration.applyToWeeks(weeks, const {'Chest': -1},
          budget: b([for (var i = 0; i < 7; i++) 'c$i']));
      expect(_sets(out.first), [[2, 2, 2, 2], [2, 2, 2]]);
    });

    // Day 0: Bench (lead) and a Biceps curl; days 1-2 more Chest. Chest 13, one above the bottom.
    List<WeekPlan> leadTrim(int curlSets) => [
          _week('baseline', [
            [_ex('Bench', 4, ['Chest'], type: 'compound'), _ex('Curl', curlSets, ['Biceps'], type: 'isolation')],
            [_ex('Press', 3, ['Chest'], type: 'compound'), _ex('Fly', 3, ['Chest'], type: 'isolation')],
            [_ex('Incline', 3, ['Chest'], type: 'compound')],
          ])
        ];
    const leadTrimNames = ['Bench', 'Curl', 'Press', 'Fly', 'Incline'];

    test('T2: the lead may take the -1 when R2 still holds after it (d65)', () {
      final out = VolumeTitration.applyToWeeks(leadTrim(3), const {'Chest': -1}, budget: b(leadTrimNames));
      expect(_sets(out.first), [[3, 3], [3, 3], [3]]);
    });

    test('T2: the lead keeps its sets when its -1 would leave a row past lead + 1; the next candidate goes', () {
      // Curl at 5 > (Bench 4 - 1) + 1: Bench is skipped; the 3s tie, the latest day's row (Incline, its own lead) goes.
      final out = VolumeTitration.applyToWeeks(leadTrim(5), const {'Chest': -1}, budget: b(leadTrimNames));
      expect(_sets(out.first), [[4, 5], [3, 3], [2]]);
    });

    test('T2: a focus row above the lead does not block the lead\'s -1 (the T1 / R5 predicate)', () {
      final out = VolumeTitration.applyToWeeks(leadTrim(5), const {'Chest': -1},
          budget: b(leadTrimNames, focus: {'Biceps'}));
      // Curl credits the focus group Biceps, so it is exempt: Bench (4, the most sets) takes the -1.
      expect(_sets(out.first), [[3, 5], [3, 3], [3]]);
    });

    test('T2: a row exactly at the lead\'s new sets + 1 does not block the lead\'s -1 (R2 holds at equality)', () {
      // Curl at 4 = (Bench 4 - 1) + 1: R2 still holds after the trim, so Bench (the most sets) takes it.
      final out = VolumeTitration.applyToWeeks(leadTrim(4), const {'Chest': -1}, budget: b(leadTrimNames));
      expect(_sets(out.first), [[3, 4], [3, 3], [3]]);
    });

    test('T2: an UNBUDGETED row past the lead\'s new sets + 1 blocks the lead\'s -1 too (R5 caps it in week 2)', () {
      // Plank is not budgeted (no archetype in this context) but R5 holds it to the lead + 1, so the guard counts it.
      final weeks = [
        _week('baseline', [
          [_ex('Bench', 4, ['Chest'], type: 'compound'), _ex('Plank', 5, ['Core'], type: 'isolation')],
          [_ex('Press', 3, ['Chest'], type: 'compound'), _ex('Fly', 3, ['Chest'], type: 'isolation')],
          [_ex('Incline', 3, ['Chest'], type: 'compound')],
        ])
      ];
      final out = VolumeTitration.applyToWeeks(weeks, const {'Chest': -1},
          budget: b(const ['Bench', 'Press', 'Fly', 'Incline']));
      expect(_sets(out.first), [[4, 5], [3, 3], [2]]);
    });

    test('the quad-first credit: with quadPrimaryCreditsGlutes false a squat earns no Glutes +1 (creditedOf, not of)', () {
      final ctx = SessionBudgetContext(
        minutes: 60,
        planGoal: 'build_muscle',
        level: 'intermediate',
        lighterPhase: false,
        focusGroups: const {},
        quadPrimaryCreditsGlutes: false,
        archetypeByName: const {'squat': 'B', 'thrust': 'B'},
      );
      final weeks = [
        _week('baseline', [
          [_ex('Squat', 3, ['Quads', 'Glutes'], type: 'compound')],
          [_ex('Thrust', 3, ['Glutes'], type: 'compound')],
        ])
      ];
      final out = VolumeTitration.applyToWeeks(weeks, const {'Glutes': 1}, budget: ctx);
      // The squat credits Quads only, so the Glutes +1 goes to the thrust (with the full credit it would go to the
      // squat, the first match).
      expect(_sets(out.first), [[3], [4]]);
    });

    test('T3: on the deload week a row with no stash is skipped, and a stash-less lead turns the lead check off', () {
      final weeks = [
        _week('deload', [
          [
            _ex('Bench', 2, ['Chest'], type: 'compound'), // the lead, no stash
            _ex('Fly', 2, ['Chest'], workingSets: 4, type: 'isolation'),
          ]
        ])
      ];
      final out = VolumeTitration.applyToWeeks(weeks, const {'Chest': 1}, budget: b(['Bench', 'Fly']));
      final exs = out.first.workoutDays.first.exercises;
      expect(exs[0].workingSets, isNull); // never written as 1
      expect(exs[1].workingSets, 5);
      expect([exs[0].sets, exs[1].sets], [2, 2]); // the shown deload sets never move
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

    test('kill switch disable_volume_titration set → {} (step 4)', () async {
      await cb.put('disable_volume_titration', true);
      await seedTrend(titName, olderW: 95, newerW: 90); // would be −1 if ON
      final d = VolumeTitration.resolveDeltas(phase: 2);
      expect(d, isEmpty);
    });

    test('no key → ON by default (step 4 flip); the retired enable_ key set false does not switch it off', () async {
      await cb.put('enable_volume_titration', false); // a stale tester-device value: ignored
      await seedTrend(titName, olderW: 95, newerW: 90);
      expect(PlanEngineFlags.volumeTitrationEnabled, isTrue);
      expect(VolumeTitration.resolveDeltas(phase: 2)[titGroup], -1);
    });

    test('phase < 2 → {} even with the flag ON', () async {
      // step 4: ON by default (setUp clears the config box; the `enable_volume_titration` key is retired).
      await seedTrend(titName, olderW: 95, newerW: 90);
      expect(VolumeTitration.resolveDeltas(phase: 1), isEmpty);
    });

    test('declining e1RM → group −1 (no readiness needed — safe direction)',
        () async {
      // step 4: ON by default (setUp clears the config box; the `enable_volume_titration` key is retired).
      await seedTrend(titName, olderW: 95, newerW: 90); // latest < prior
      final d = VolumeTitration.resolveDeltas(phase: 2);
      expect(d[titGroup], -1);
    });

    test('held/gained + recovered readiness (≥3 low-soreness) → group +1',
        () async {
      // step 4: ON by default (setUp clears the config box; the `enable_volume_titration` key is retired).
      await seedTrend(titName, olderW: 90, newerW: 95); // latest ≥ prior
      await seedReadiness(3, 0); // recovered
      final d = VolumeTitration.resolveDeltas(phase: 2);
      expect(d[titGroup], 1);
    });

    test('step 4 T4: readiness switched off (disable_readiness) → old green rows allow no +1', () async {
      await seedTrend(titName, olderW: 90, newerW: 95);
      await seedReadiness(3, 0); // would be "recovered"
      await cb.put('disable_readiness', true);
      final d = VolumeTitration.resolveDeltas(phase: 2);
      expect(d.containsKey(titGroup), isFalse);
      // The -1 direction needs no readiness and still applies.
      await seedTrend(titName, olderW: 95, newerW: 90);
      expect(VolumeTitration.resolveDeltas(phase: 2)[titGroup], -1);
    });

    test('a FLAT e1RM is held, not declining: +1 with recovery (B-pass seat B F2)', () async {
      await seedTrend(titName, olderW: 90, newerW: 90);
      await seedReadiness(3, 0);
      expect(VolumeTitration.resolveDeltas(phase: 2)[titGroup], 1);
    });

    test('the 40 % rule: 2 of 6 sore check-ins still recovered (+1), 3 of 6 not (hold) (B-pass seat B F3)', () async {
      Future<void> seedMixed(int sore) async {
        for (int i = 1; i <= 6; i++) {
          final d = fixedToday.subtract(Duration(days: i));
          await hb.put('readiness_${dk(d)}', {
            'date': dk(d),
            'sleep': 0,
            'soreness': i <= sore ? 2 : 0,
            'energy': 0,
            'level': i <= sore ? 'yellow' : 'green',
          });
        }
      }

      await seedTrend(titName, olderW: 90, newerW: 95);
      await seedMixed(2);
      expect(VolumeTitration.resolveDeltas(phase: 2)[titGroup], 1);
      await seedMixed(3);
      expect(VolumeTitration.resolveDeltas(phase: 2).containsKey(titGroup), isFalse);
    });

    test('held/gained + NO readiness → hold (no +1; the SAFE default)', () async {
      // step 4: ON by default (setUp clears the config box; the `enable_volume_titration` key is retired).
      await seedTrend(titName, olderW: 90, newerW: 95);
      // no readiness rows at all
      final d = VolumeTitration.resolveDeltas(phase: 2);
      expect(d.containsKey(titGroup), isFalse);
    });

    test('held/gained + systemic soreness (persistent beat-up) → hold', () async {
      // step 4: ON by default (setUp clears the config box; the `enable_volume_titration` key is retired).
      await seedTrend(titName, olderW: 90, newerW: 95);
      await seedReadiness(3, 2); // 3/3 beat-up → systemic fatigue
      final d = VolumeTitration.resolveDeltas(phase: 2);
      expect(d.containsKey(titGroup), isFalse);
    });

    test('sparse readiness (< 3 rows) → not "recovered" → no +1', () async {
      // step 4: ON by default (setUp clears the config box; the `enable_volume_titration` key is retired).
      await seedTrend(titName, olderW: 90, newerW: 95);
      await seedReadiness(2, 0); // only 2 → insufficient sample
      final d = VolumeTitration.resolveDeltas(phase: 2);
      expect(d.containsKey(titGroup), isFalse);
    });

    test('deterministic across repeated calls (sorted-group iteration)',
        () async {
      // step 4: ON by default (setUp clears the config box; the `enable_volume_titration` key is retired).
      await seedTrend(titName, olderW: 95, newerW: 90);
      final a = VolumeTitration.resolveDeltas(phase: 2);
      final b = VolumeTitration.resolveDeltas(phase: 2);
      expect(a.keys.toList(), b.keys.toList());
      expect(a[titGroup], b[titGroup]);
    });
  });
}
