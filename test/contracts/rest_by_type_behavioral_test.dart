// OI-456 piece A (docs/plans/2026-11-04-oi456-a-rest-by-type.md): the rest between
// sets follows the EXERCISE (its archetype: H 150, M 120, I 75, B 60), never the
// day's intensity, and every day starts every exercise at 3 sets.
//
// Part 1, crafted fixtures: the stamp, the invariance across intensities, the
// deload rule, the week-2 pricing, and the custom row priced identically at the
// three sites that price it. Part 2, the REAL generator: every stored rest is the
// archetype's (expected rest derived HERE from the library row against the literal
// table, never from the engine), and the tester's plan is measured.
//
// `WRITE_REST_BY_TYPE_REPORT=1` also writes `rest_by_type_report.md` next to this
// file's report sibling (`test/plan_generator/`), the numbers the diagnose-doc cites.
@Timeout(Duration(minutes: 12))
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
import 'package:icanbefitter/shared/repositories/plan_engine/periodization_engine.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_set_allocator.dart';

import '../helpers/session_budget_fixtures.dart';

/// The literal table, restated: the engine's own table must not be the oracle.
const _expectedRest = {'H': 150, 'M': 120, 'I': 75, 'B': 60};

String _archetypeOfLibraryRow(Map<String, dynamic> row) {
  final lt = '${row['logging_type'] ?? 'weight_reps'}';
  if (lt == 'timed' || lt == 'cardio' || lt == 'distance') return 'B';
  final types = {
    for (final t in (row['exercise_type'] as List? ?? const ['compound'])) '$t'.trim().toLowerCase()
  };
  final m = RegExp(r'^\s*(\d+)\s*-\s*(\d+)\s*$').firstMatch('${row['rep_range']}');
  final lo = m == null ? null : int.parse(m.group(1)!);
  if (types.contains('compound')) return (lo != null && lo <= 6) ? 'H' : 'M';
  if (types.contains('isolation')) return 'I';
  if (types.contains('calisthenics')) return (lo != null && lo <= 10) ? 'M' : 'B';
  return 'B';
}

List<int> _setsOfDay(List<WeekPlan> weeks, int week, int day) =>
    [for (final e in weeks[week].workoutDays[day].exercises) e.sets];

void main() {
  group('crafted fixtures', () {
    test('(a) the stamp: each rep-based exercise carries its OWN archetype rest, in every week', () {
      final f = Fx();
      f.row('heavy', ['Chest'], reps: '5-8'); // compound, lower bound 5  -> H
      f.row('mid', ['Lats'], reps: '8-12'); // compound, lower bound 8   -> M
      f.row('iso', ['Biceps'], type: 'isolation', reps: '10-15'); // isolation -> I
      f.row('cali', ['Core'], type: 'calisthenics', reps: '20-30'); // calisthenics, lower 20 -> B
      final days = [
        f.day('endurance', [f.ex('heavy'), f.ex('mid'), f.ex('iso'), f.ex('cali')]),
      ];
      final weeks = PeriodizationEngine.apply(
        populated: days,
        phase: 1,
        is6Day: false,
        budget: f.ctx(days, minutes: 90),
      );
      for (var w = 0; w < 4; w++) {
        expect(
          [for (final e in weeks[w].workoutDays[0].exercises) e.restSeconds],
          [150, 120, 75, 60],
          reason: 'week ${w + 1}: an endurance day no longer rests 38 s',
        );
      }
    });

    test('(b) invariance: the same list on a strength, hypertrophy, strength and endurance day is the same day', () {
      // Strength / intermediate: band (10, 14). One single-group exercise per group, on
      // every day, at 3 sets = 12 a week per group: inside the band and under the top, so
      // `grow` adds nothing and the only thing left to differ is the day's intensity.
      final f = Fx();
      final names = {
        'bench': ('Chest', 'compound', '5-8'),
        'row': ('Lats', 'compound', '8-12'),
        'sq': ('Quads', 'compound', '5-8'),
        'curl': ('Biceps', 'isolation', '10-15'),
        'pushdown': ('Triceps', 'isolation', '10-15'),
        'legcurl': ('Hamstrings', 'isolation', '10-15'),
      };
      names.forEach((n, v) => f.row(n, [v.$1], type: v.$2, reps: v.$3));
      final days = [
        for (final i in ['strength', 'hypertrophy', 'strength', 'endurance'])
          f.day(i, [for (final n in names.keys) f.ex(n)]),
      ];
      final allocated = SessionSetAllocator.allocate(
        days: days,
        ctx: f.ctx(days, minutes: 90, goal: 'strength'),
        rowsByName: f.rows,
        is6Day: true,
      );
      for (final d in allocated) {
        expect([for (final e in d.exercisesA) e.sets], everyElement(SessionBudget.baseSets),
            reason: 'non-vacuity: every slot holds exactly the base sets, nothing was grown');
      }
      final reference = [for (final e in allocated[0].exercisesA) (e.exerciseName, e.sets)];
      expect(reference.length, 6);
      for (final d in allocated.skip(1)) {
        expect([for (final e in d.exercisesA) (e.exerciseName, e.sets)], reference);
      }
      // Through `apply`, weeks 1 and 3 only: week 2's extra sets are day-order dependent
      // (`_weekTwoGains` grants rank-major up to each group's weekly top).
      final weeks = PeriodizationEngine.apply(
        populated: allocated,
        phase: 1,
        is6Day: true,
        budget: f.ctx(allocated, minutes: 90, goal: 'strength'),
      );
      for (final w in [0, 2]) {
        final ref = [
          for (final e in weeks[w].workoutDays[0].exercises) (e.exerciseName, e.sets, e.restSeconds)
        ];
        for (var d = 1; d < 4; d++) {
          expect([
            for (final e in weeks[w].workoutDays[d].exercises) (e.exerciseName, e.sets, e.restSeconds)
          ], ref, reason: 'week ${w + 1}, day ${d + 1}');
        }
      }
    });

    test('(c) deload: min(sets, max(2, floor(0.6 x sets))) for 1..5 sets, and the day keeps its count', () {
      final f = Fx();
      final names = ['a', 'b', 'c', 'd', 'e'];
      for (final n in names) {
        f.row(n, ['Chest']);
      }
      final days = [
        f.day('hypertrophy', [for (var i = 0; i < 5; i++) f.ex(names[i], sets: i + 1)]),
      ];
      final weeks = PeriodizationEngine.apply(
        populated: days,
        phase: 1,
        is6Day: true,
        budget: f.ctx(days, minutes: 90),
      );
      expect(_setsOfDay(weeks, 0, 0), [1, 2, 3, 4, 5]);
      expect(_setsOfDay(weeks, 3, 0), [1, 2, 2, 2, 3]);
      expect(weeks[3].workoutDays[0].exercises.length, 5);
    });

    test('(d) week-2 gains are priced at the archetype rest, not the selector default', () {
      // One isolation row (archetype I, rest 75) whose selector default is a stale 30 s,
      // beside a timed filler that leaves exactly 120 s of the 30-minute day (1440 s):
      //   filler 5 sets at 164 s rest = 1.2 x (30 + 5 x 40 + 4 x 164) = 1063.2 s
      //   iso 2 sets at 75 s          = 1.2 x (45 + 2 x 47 + 75)       =  256.8 s
      //   left = 1440 - 1063.2 - 256.8 = 120 s
      // A 3rd iso set costs 1.2 x (47 + 75) = 146.4 s at the archetype rest (does NOT fit)
      // but 1.2 x (47 + 30) = 92.4 s at the stale one (would fit).
      Fx build() {
        final f = Fx();
        f.row('iso', ['Biceps'], type: 'isolation', reps: '10-15');
        f.row('plank', ['Core'], type: 'isolation', reps: '30-60', logging: 'timed');
        return f;
      }

      List<PopulatedDay> days(Fx f) => [
            f.day('hypertrophy', [
              f.ex('plank', sets: 5, logging: 'timed', rest: 164),
              f.ex('iso', sets: 2, rest: 30),
            ]),
          ];
      int isoSetsWeek2(Fx f, int minutes) {
        final d = days(f);
        final weeks = PeriodizationEngine.apply(
          populated: d,
          phase: 1,
          is6Day: true,
          budget: f.ctx(d, minutes: minutes),
        );
        return weeks[1].workoutDays[0].exercises.firstWhere((e) => e.exerciseName == 'iso').sets;
      }

      final f = build();
      expect(isoSetsWeek2(f, 30), 2, reason: '146.4 s does not fit the 120 s left');
      expect(isoSetsWeek2(f, 45), 3, reason: 'non-vacuity: with room it gains its set');
    });

    test('(e) a rep-based custom is priced at its archetype rest by the allocator and stamped by apply', () {
      // A custom H lift (5-8 reps, selector default 75 s) beside two chest/back compounds
      // on a 30-minute day (1440 s). At its archetype's 150 s the custom (3 sets) costs
      // 586.8 s and leaves 853.2 s: c1 takes 3 sets (522 s), 331.2 s are left and c2's 2 sets
      // (336 s) do not fit. Priced at the stale 75 s (406.8 s) c2 would fit.
      final f = Fx();
      f.row('cust', ['Core'], reps: '5-8');
      f.row('c1', ['Chest']);
      f.row('c2', ['Lats']);
      final days = [
        f.day('hypertrophy', [
          f.ex('cust', customOrigin: 'repeat_pin'),
          f.ex('c1'),
          f.ex('c2'),
        ]),
      ];
      final out = SessionSetAllocator.allocate(
        days: days,
        ctx: f.ctx(days, minutes: 30),
        rowsByName: f.rows,
        is6Day: true,
      );
      expect([for (final e in out[0].exercisesA) e.exerciseName], ['cust', 'c1']);
      final weeks = PeriodizationEngine.apply(
        populated: out,
        phase: 1,
        is6Day: true,
        budget: f.ctx(out, minutes: 30),
      );
      final stamped = {
        for (final e in weeks[0].workoutDays[0].exercises) e.exerciseName: e.restSeconds
      };
      expect(stamped['cust'], 150, reason: 'a custom H row is stamped at the H rest');
      expect(stamped['c1'], 120);
    });
    test('(h) the allocator prices isolations at 75 s: at 30 minutes six distinct-group isolations seat 3', () {
      // Day budget 1440 s. A 3-set isolation at 75 s costs 1.2 x (45 + 3 x 47 + 2 x 75) = 403.2 s, so 3 fit
      // (1209.6 s) and a 4th does not even at 2 sets (+256.8 s). Priced at the old 38 s rest it costs 314.4 s,
      // and a 4th would be admitted (a mutant that prices at the day's rest turns this red).
      final f = Fx();
      const groups = ['Chest', 'Lats', 'Quads', 'Biceps', 'Triceps', 'Hamstrings'];
      for (var i = 0; i < groups.length; i++) {
        f.row('iso$i', [groups[i]], type: 'isolation', reps: '10-15');
      }
      final days = [f.day('hypertrophy', [for (var i = 0; i < groups.length; i++) f.ex('iso$i')])];
      final out = SessionSetAllocator.allocate(
        days: days,
        ctx: f.ctx(days, minutes: 30),
        rowsByName: f.rows,
        is6Day: true,
      );
      final kept = out[0].exercisesA;
      expect(kept.length, 3);
      // (the weekly-band growth passes may add a set to the lead lift; the count and the true cost are the pin)
      final spent = kept.fold<double>(
          0, (t, e) => t + SessionBudget.exerciseSeconds(archetype: 'I', sets: e.sets, restSeconds: SessionBudget.restForArchetype('I')));
      expect(spent, lessThanOrEqualTo(1440));
    });

    test('(e2) week 2: a rep-based custom\'s extra set is priced at its archetype rest, not the selector default', () {
      // `_weekTwoGains` runs before the stamp, so a custom\'s `restSeconds` is still the
      // selector default (30 s here). A custom H lift (5-8 reps), 3 sets, beside a timed
      // filler on a 30-minute day (1440 s):
      //   filler 6 sets at 100 s rest = 1.2 x (30 + 6 x 40 + 5 x 100) = 924 s
      //   custom 3 sets at 150 s      = 1.2 x (120 + 3 x 23 + 2 x 150) = 586.8 s
      // A 4th custom set costs 1.2 x (23 + 150) = 207.6 s at the archetype rest, but only
      // 1.2 x (23 + 30) = 63.6 s at the stale one; the day has 1440 - 924 - 586.8 < 0 left
      // at the true price (no gain) and 1440 - 924 - 298.8 = 217.2 s at the stale price
      // (a gain), so a mutant that prices at `ex.restSeconds` gains a set and this fails.
      Fx build() {
        final f = Fx();
        f.row('cust', ['Chest'], reps: '5-8');
        f.row('plank', ['Core'], type: 'isolation', reps: '30-60', logging: 'timed');
        return f;
      }

      int custSetsWeek2(int minutes) {
        final f = build();
        final d = [
          f.day('hypertrophy', [
            // The custom comes FIRST: not-budgeted rows are offered their extra set in list
            // order, and the filler would otherwise take the spare time before it is asked.
            f.ex('cust', sets: 3, rest: 30, customOrigin: 'repeat_pin'),
            f.ex('plank', sets: 6, logging: 'timed', rest: 100),
          ]),
        ];
        final weeks = PeriodizationEngine.apply(
          populated: d,
          phase: 1,
          is6Day: true,
          budget: f.ctx(d, minutes: minutes),
        );
        return weeks[1].workoutDays[0].exercises.firstWhere((e) => e.exerciseName == 'cust').sets;
      }

      expect(custSetsWeek2(30), 3, reason: 'no room at the true 150 s rest');
      expect(custSetsWeek2(45), 4, reason: 'non-vacuity: with room the custom gains its set');
    });
  });

  group('the real generator', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    late Directory tempDir;
    late Map<String, Map<String, dynamic>> byName;
    final report = StringBuffer();
    // The cells (f) measured, keyed 'tier|days|level|minutes'; the report is written only when all of them ran.
    final measured = <String, List<int>>{};

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('rest_by_type');
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
      final rows = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync())
              as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      for (final r in rows) {
        await exBox.put((r['id'] ?? r['name']).toString(), r);
      }
      byName = {for (final r in rows) (r['name'] as String).toLowerCase(): r};
      HiveService.instance.markInitializedForTests();
      await HiveUserSession.openForUser(testUser);
    });

    tearDownAll(() async {
      if (Platform.environment['WRITE_REST_BY_TYPE_REPORT'] == '1' && measured.length == 9) {
        File('test/plan_generator/rest_by_type_report.md').writeAsStringSync(report.toString());
      }
      await HiveUserSession.closeAll();
      GuardedBox.testBypassOwnership = false;
      await Hive.close();
      try {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    Phase gen({
      required String goal,
      required String tier,
      required int days,
      required String level,
      int phase = 1,
      int? minutes,
    }) =>
        PlanGenerator.instance.generateV4(
          goal: goal,
          equipment: tier,
          daysPerWeek: days,
          phase: phase,
          experienceLevel: level,
          injuries: const [],
          bodyFocus: const [],
          sessionDuration: minutes,
          previousWeights: const {},
        );

    bool budgeted(PlannedExercise e) =>
        e.customOrigin == null &&
        !const {'timed', 'cardio', 'distance'}.contains(e.loggingType) &&
        byName.containsKey(e.exerciseName.toLowerCase());

    test('every budgeted rep-based exercise of every week is stored at its archetype rest', () {
      final bad = <String>[];
      var checked = 0;
      for (final goal in ['build_muscle', 'strength', 'lose_fat', 'general_fitness']) {
        for (final days in [3, 4, 5, 6]) {
          for (final level in ['beginner', 'intermediate', 'advanced']) {
            for (final minutes in [30, 60, 90]) {
              for (final phase in [1, 4]) {
                final plan = gen(
                    goal: goal, tier: 'full_gym', days: days, level: level, phase: phase, minutes: minutes);
                for (final wk in plan.weekPlans) {
                  for (final d in wk.workoutDays) {
                    for (final e in d.exercises.where(budgeted)) {
                      if (!SessionBudget.isRepBased(e.loggingType)) continue;
                      final want = _expectedRest[_archetypeOfLibraryRow(byName[e.exerciseName.toLowerCase()]!)];
                      checked++;
                      if (e.restSeconds != want) {
                        bad.add('$goal|${days}d|$level|p$phase|${minutes}min w${wk.weekInPhase} '
                            '${e.exerciseName}: ${e.restSeconds} != $want');
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
      expect(checked, greaterThan(1000));
      expect(bad.take(5).toList(), isEmpty, reason: '${bad.length} of $checked exercises');
    });

    test('(f) the tester plan (intermediate, basic_gym, 4 days, build_muscle, default 60 min) is measured', () {
      report.writeln('# OI-456 piece A: measured exercise counts per day (week 1)\n');
      report.writeln('Generated by `rest_by_type_behavioral_test.dart` (`WRITE_REST_BY_TYPE_REPORT=1`).\n');
      report.writeln('| goal | tier | days | level | minutes | counts per day (week 1) | spread |');
      report.writeln('|---|---|---|---|---|---|---|');
      List<int> counts(Phase p) => [for (final d in p.weekPlans[0].workoutDays) d.exercises.length];
      for (final (tier, days, level, minutes) in [
        ('basic_gym', 4, 'intermediate', null),
        ('basic_gym', 4, 'intermediate', 30),
        ('basic_gym', 4, 'intermediate', 45),
        ('basic_gym', 4, 'intermediate', 90),
        ('basic_gym', 4, 'beginner', null),
        ('basic_gym', 4, 'advanced', null),
        ('full_gym', 3, 'intermediate', null),
        ('full_gym', 5, 'intermediate', null),
        ('full_gym', 6, 'intermediate', null),
      ]) {
        final c = counts(gen(
            goal: 'build_muscle', tier: tier, days: days, level: level, minutes: minutes));
        final spread = c.reduce((a, b) => a > b ? a : b) - c.reduce((a, b) => a < b ? a : b);
        measured['$tier|$days|$level|${minutes ?? 60}'] = c;
        report.writeln('| build_muscle | $tier | $days | $level | ${minutes ?? '60 (default)'} | $c | $spread |');
      }
      final tester = counts(gen(
          goal: 'build_muscle', tier: 'basic_gym', days: 4, level: 'intermediate'));
      final spread = tester.reduce((a, b) => a > b ? a : b) - tester.reduce((a, b) => a < b ? a : b);
      // The cells the diagnose-doc and the nested CLAUDE.md quote: a change that moves one must move the prose.
      expect(measured['basic_gym|4|intermediate|60'], [6, 6, 7, 6]);
      expect(measured['basic_gym|4|intermediate|30'], [3, 3, 3, 3]);
      expect(measured['basic_gym|4|intermediate|45'], [4, 5, 5, 5]);
      expect(measured['basic_gym|4|intermediate|90'], [7, 6, 8, 9]);
      expect(measured['basic_gym|4|beginner|60'], [5, 5, 5, 4]);
      expect(measured['basic_gym|4|advanced|60'], [6, 6, 7, 6]);
      expect(measured['full_gym|3|intermediate|60'], [6, 7, 7]);
      expect(measured['full_gym|5|intermediate|60'], [6, 5, 7, 7, 6]);
      expect(measured['full_gym|6|intermediate|60'], [6, 6, 7, 6, 6, 7]);
      // Before OI-456 the same persona measured 4 / 6 / 4 / 9 (a spread of 5).
      expect(spread, lessThanOrEqualTo(2), reason: 'tester counts: $tester');
    });
  });
}
