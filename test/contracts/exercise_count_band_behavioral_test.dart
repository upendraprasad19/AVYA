// OI-456 piece B (docs/plans/2026-11-04-oi456-b-count-band.md): the exercise count
// band. A day SEATS every exercise at 2 sets first (up to the level's maximum:
// beginner 5, intermediate 6, advanced 8), forces the count floor (4 from 25
// minutes, 5 from 45, 3 below; founder D-A) when only the clock says no, bounded by
// `maxForcedOverSeconds`, and only then grows sets towards 3.
//
// Part 1, crafted fixtures: the tables, the target, the force step (clock only,
// never past a cap or top, bounded, negative `secondsLeft`, copy days). Part 2, the
// REAL generator over level x minutes x days x goal x tier x every week: every day
// is within `[floor, max]` or named in `belowCount` / `selectorThin`, `countForced`
// only at short sessions, and the deload keeps each variant's count.
@Timeout(Duration(minutes: 15))
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
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_set_allocator.dart';

import '../helpers/session_budget_fixtures.dart';

AllocationStats statsA() => SessionSetAllocator.debugLastStats!['A']!;
AllocationStats statsB() => SessionSetAllocator.debugLastStats!['B']!;

/// The tables, restated literally: the engine's own tables are not the oracle.
const _floorByMinutes = {15: 3, 20: 3, 24: 3, 25: 4, 30: 4, 31: 4, 44: 4, 45: 5, 60: 5, 90: 5, 180: 5};
const _maxByLevel = {'beginner': 5, 'intermediate': 6, 'advanced': 8};

const _distinctGroups = [
  'Chest', 'Lats', 'Quads', 'Hamstrings', 'Glutes', 'Shoulders', 'Biceps', 'Triceps',
];

void main() {
  group('crafted fixtures', () {
    test('(a) the tables: floor by minutes over the whole 15..180 range, maximum by level', () {
      _floorByMinutes.forEach((m, want) {
        expect(SessionBudget.countFloor(m), want, reason: '$m minutes');
      });
      _maxByLevel.forEach((l, want) {
        expect(SessionBudget.countMax(l), want, reason: l);
      });
      expect(SessionBudget.countMax('not-a-level'), 6, reason: 'unknown level reads intermediate');
      expect(SessionBudget.hardMax, 8);
      expect(SessionBudget.maxForcedOverSeconds, 300);
    });

    test('(b) the target: a day of 8 distinct-group slots holds 5 / 6 / 8 by level, all at 3 sets when time allows', () {
      for (final (level, want) in [('beginner', 5), ('intermediate', 6), ('advanced', 8)]) {
        final f = Fx();
        for (var i = 0; i < 8; i++) {
          f.row('iso$i', [_distinctGroups[i]], type: 'isolation', reps: '10-15');
        }
        final days = [f.day('hypertrophy', [for (var i = 0; i < 8; i++) f.ex('iso$i')])];
        final out = f.run(days, minutes: 90, level: level);
        expect(out[0].exercisesA.length, want, reason: level);
        // 90 minutes leaves room to grow every seated exercise to the base 3 (and on, to the
        // weekly band bottom: one exercise per group here).
        expect([for (final e in out[0].exercisesA) e.sets], everyElement(greaterThanOrEqualTo(3)), reason: level);
        // The slots left out are the lowest-ranked ones, labelled by the count.
        final left = [for (var i = want; i < 8; i++) 'iso$i'];
        expect([for (final e in out[0].exercisesA) e.exerciseName].any(left.contains), isFalse);
      }
    });

    test('(c) four heavy lifts at 30 minutes: the floor forces the 4th, the day overruns by less than the bound', () {
      final f = Fx();
      const groups = ['Chest', 'Lats', 'Quads', 'Hamstrings'];
      for (var i = 0; i < 4; i++) {
        f.row('h$i', [groups[i]], reps: '5-8'); // compound, lower bound 5 -> H
      }
      final days = [f.day('strength', [for (var i = 0; i < 4; i++) f.ex('h$i')])];
      final out = f.run(days, minutes: 30);
      // Unit 2A: h0, the day's lead (the sequencer's opener), is seated at the base 3 (R1); h1 and h2 fit at 2 and the
      // floor forces h3, now 284.4 s over (586.8 + 3 x 379.2 - 1440) instead of 76.8 s (4 x 379.2 - 1440), still
      // inside the 300 s bound (founder d26 / d28: the accepted overrun).
      expect(setsOf(out[0]), [('h0', 3), ('h1', 2), ('h2', 2), ('h3', 2)]);
      expect(statsA().countForced.keys, [0]);
      expect(statsA().countForced[0]!.map((e) => e.name), ['h3']);
      expect(statsA().belowCount, isEmpty);
      final spent = SessionBudget.exerciseSeconds(archetype: 'H', sets: 3, restSeconds: 150) +
          3 * SessionBudget.exerciseSeconds(archetype: 'H', sets: 2, restSeconds: 150);
      final over = spent - (30 - SessionBudget.warmCoolMinutes(30)) * 60;
      expect(over, closeTo(284.4, 1e-6), reason: 'fixture: the 4th lift really overruns');
      expect(over, lessThanOrEqualTo(SessionBudget.maxForcedOverSeconds));
    });

    test('(d) the force never passes a cap or a weekly top: a day of 6 Chest lifts at 90 min (beginner cap 6) stays short', () {
      final f = Fx();
      for (var i = 0; i < 6; i++) {
        f.row('c$i', ['Chest']);
      }
      final days = [f.day('strength', [for (var i = 0; i < 6; i++) f.ex('c$i')])];
      final out = f.run(days, minutes: 90, goal: 'general_fitness', level: 'beginner');
      expect(out[0].exercisesA.length, 3, reason: 'cap 6 = 3 x 2 sets');
      expect(statsA().belowCount, {0: 'cap_top'});
      expect(statsA().countForced, isEmpty);
      expect(statsA().weekly['Chest'], 6);
    });

    test('(e) the forcing bound: four heavy lifts at 15 minutes force ONE (not all), the rest stay out and the day says why', () {
      final f = Fx();
      const groups = ['Chest', 'Lats', 'Quads', 'Hamstrings'];
      for (var i = 0; i < 4; i++) {
        f.row('h$i', [groups[i]], reps: '5-8');
      }
      final days = [f.day('strength', [for (var i = 0; i < 4; i++) f.ex('h$i')])];
      // Unit 2B: the day floor off, so pass A2's own bound is what this reads.
      final out = f.run(days, minutes: 15, dayFloor: false);
      expect(out[0].exercisesA.length, 2);
      expect(statsA().countForced[0]!.length, 1);
      expect(statsA().belowCount, {0: 'clock'});
      final spent = 2 * SessionBudget.exerciseSeconds(archetype: 'H', sets: 2, restSeconds: 150);
      final over = spent - (15 - SessionBudget.warmCoolMinutes(15)) * 60;
      expect(over, greaterThan(0));
      expect(over, lessThanOrEqualTo(SessionBudget.maxForcedOverSeconds));
      // With the floor (d33): A2 still forces ONE (h1, inside its bound); the 3-exercise floor then seats h2 past the
      // clock (`overClock`, not in countForced). 3 rows = the count floor at 15 minutes, so no label.
      final floored = f.run(days, minutes: 15);
      expect([for (final e in floored[0].exercisesA) e.exerciseName], ['h0', 'h1', 'h2']);
      expect([for (final c in statsA().countForced[0]!) c.name], ['h1']);
      expect(statsA().floorSeats[0]!.single.name, 'h2');
      expect(statsA().floorSeats[0]!.single.overClock, isTrue);
      expect(statsA().belowCount, isEmpty);
    });

    test('(f) a day whose time is already negative still force-seats while the total overrun stays inside the bound', () {
      // A timed row (not budgeted, 8 sets at 104 s) spends 1293.6 of 1440 s, leaving 146.4 s.
      // Calisthenics rows are archetype B: 2 sets cost 204 s. Pass A seats none (204 > 146.4); the
      // empty-day guard puts the lead on (-57.6 s); the floor then force-seats ONE more (-261.6 s,
      // inside -300) and refuses the third (-465.6 s). `fits` would refuse the second one: it reads a
      // negative `secondsLeft` as "no room" even for 0 seconds.
      final f = Fx();
      f.row('wall', ['Core'], type: 'isolation', reps: '30-60', logging: 'timed');
      const groups = ['Chest', 'Lats', 'Quads'];
      for (var i = 0; i < 3; i++) {
        f.row('cal$i', [groups[i]], type: 'calisthenics', reps: '15-20');
      }
      final days = [
        f.day('hypertrophy', [
          f.ex('wall', sets: 8, logging: 'timed', rest: 104),
          for (var i = 0; i < 3; i++) f.ex('cal$i'),
        ]),
      ];
      final out = f.run(days, minutes: 30);
      final names = [for (final e in out[0].exercisesA) e.exerciseName];
      expect(names, ['wall', 'cal0', 'cal1']);
      expect(statsA().forcedDays, [0], reason: 'the guard seated the lead');
      expect(statsA().countForced[0]!.map((e) => e.name), ['cal1']);
      expect(statsA().belowCount, {0: 'clock'});
    });

    test('(g) a copied day inherits the forced slots (variant B copies A, forced seats included)', () {
      final f = Fx();
      const groups = ['Chest', 'Lats', 'Quads', 'Hamstrings'];
      for (var i = 0; i < 4; i++) {
        f.row('h$i', [groups[i]], reps: '5-8');
      }
      final list = [for (var i = 0; i < 4; i++) f.ex('h$i')];
      final days = [f.day('strength', list)];
      SessionSetAllocator.allocate(
        days: days,
        ctx: f.ctx(days, minutes: 30),
        rowsByName: f.rows,
        is6Day: false,
      );
      expect(statsA().countForced[0]!.map((e) => e.name), ['h3']);
      expect(statsB().countForced[0]!.map((e) => e.name), ['h3']);
    });

    test('(i) the force seats the CHEAPEST remaining slot, not the next in rank order', () {
      // A timed row spends 482.4 s; two heavy lifts seat (758 s); then 199.6 s are left, and neither the
      // M lift (336 s, rank 2) nor the isolation (257 s, rank 3) fits. rows = 3 < 4: the floor forces
      // the cheaper isolation (-57.4 s), not the earlier M lift (-136.4 s).
      final f = Fx();
      f.row('wall', ['Core'], type: 'isolation', reps: '30-60', logging: 'timed');
      f.row('h0', ['Chest'], reps: '5-8');
      f.row('h1', ['Lats'], reps: '5-8');
      f.row('m', ['Quads']);
      f.row('i', ['Biceps'], type: 'isolation', reps: '10-15');
      final days = [
        f.day('strength', [
          f.ex('wall', sets: 5, logging: 'timed', rest: 43),
          f.ex('h0'), f.ex('h1'), f.ex('m'), f.ex('i'),
        ]),
      ];
      final out = f.run(days, minutes: 30);
      expect([for (final e in out[0].exercisesA) e.exerciseName], ['wall', 'h0', 'h1', 'i']);
      expect(statsA().countForced[0]!.map((e) => e.name), ['i']);
    });

    test('(j) not-budgeted rows count against the maximum: 3 timed rows leave an intermediate day 3 budgeted slots', () {
      final f = Fx();
      for (var i = 0; i < 3; i++) {
        f.row('t$i', ['Core'], type: 'isolation', reps: '30-60', logging: 'timed');
      }
      for (var i = 0; i < 6; i++) {
        f.row('iso$i', [_distinctGroups[i]], type: 'isolation', reps: '10-15');
      }
      final days = [
        f.day('hypertrophy', [
          for (var i = 0; i < 3; i++) f.ex('t$i', sets: 2, logging: 'timed', rest: 30),
          for (var i = 0; i < 6; i++) f.ex('iso$i'),
        ]),
      ];
      final out = f.run(days, minutes: 90);
      expect(out[0].exercisesA.length, 6, reason: '3 timed + 3 budgeted = the intermediate maximum');
      expect([for (final e in out[0].exercisesA) e.exerciseName].where((n) => n.startsWith('iso')).length, 3);
    });

    test('(l) pass B grows every seated exercise to 3 before the weekly bottom concentrates sets on a lead lift', () {
      // Lighter phase (weekly top = band bottom = 12): two days of two Chest lifts. 4 x 2 = 8, 4 more sets to the
      // top. Pass B spreads them (3, 3 / 3, 3); without it the bottom pass would pile them on the first lift
      // (5, 2 / 3, 2).
      final f = Fx();
      for (var i = 0; i < 4; i++) {
        f.row('c$i', ['Chest']);
      }
      final days = [
        f.day('hypertrophy', [f.ex('c0'), f.ex('c1')]),
        f.day('hypertrophy', [f.ex('c2'), f.ex('c3')]),
      ];
      final out = f.run(days, minutes: 90, lighter: true);
      expect([for (final d in out) [for (final e in d.exercisesA) e.sets]], [[3, 3], [3, 3]]);
    });

    test('(m) the force never passes the WEEKLY top: a day left short by a spent top stays short', () {
      // general_fitness beginner: Chest top 10, session cap 6. Days 0 and 1 spend the week (6 + 4); day 2 keeps
      // its lead lift only and its 4 other Chest slots could be forced past the top (session cap 6 allows 2
      // more seats): they must not be.
      final f = Fx();
      final days = <PopulatedDay>[];
      for (var d = 0; d < 3; d++) {
        for (var i = 0; i < 5; i++) {
          f.row('c$d$i', ['Chest']);
        }
        days.add(f.day('strength', [for (var i = 0; i < 5; i++) f.ex('c$d$i')]));
      }
      f.run(days, minutes: 90, goal: 'general_fitness', level: 'beginner', dayFloor: false);
      expect(statsA().weekly['Chest'], 10);
      expect(statsA().countForced, isEmpty);
      expect(statsA().belowCount[2], 'cap_top');
      // Unit 2B (d30): pass A2 still never passes the top; the 3-exercise day floor does, by founder decision, and
      // names each such seat. Rows [2, 2, 1] -> [3, 3, 3]: 10 + 4 x 2 = 18. The count label is still A2's.
      final floored = f.run(days, minutes: 90, goal: 'general_fitness', level: 'beginner');
      expect([for (final d in floored) d.exercisesA.length], [3, 3, 3]);
      expect(statsA().weekly['Chest'], 18);
      expect(statsA().countForced, isEmpty);
      expect([for (final v in statsA().floorSeats.values) for (final x in v) x.overTop], [
        for (var i = 0; i < 4; i++) ['Chest'],
      ]);
      expect(statsA().belowCount[2], 'cap_top');
    });

    test('(n) a day whose selector supplied fewer slots than the floor is selectorThin, not belowCount', () {
      final f = Fx();
      for (var i = 0; i < 3; i++) {
        f.row('iso$i', [_distinctGroups[i]], type: 'isolation', reps: '10-15');
      }
      final days = [f.day('hypertrophy', [for (var i = 0; i < 3; i++) f.ex('iso$i')])];
      final out = f.run(days, minutes: 90);
      expect(out[0].exercisesA.length, 3);
      expect(statsA().selectorThin, [0]);
      expect(statsA().belowCount, isEmpty);
    });

    test('(o) not-budgeted rows past the maximum: 6 timed rows leave target 0 and the empty-day guard seats ONE lead (7 rows, named)', () {
      final f = Fx();
      for (var i = 0; i < 6; i++) {
        f.row('t$i', ['Core'], type: 'isolation', reps: '30-60', logging: 'timed');
      }
      f.row('cl', ['Chest']);
      final days = [
        f.day('hypertrophy', [
          for (var i = 0; i < 6; i++) f.ex('t$i', sets: 2, logging: 'timed', rest: 30),
          f.ex('cl'),
        ]),
      ];
      final out = f.run(days, minutes: 90);
      expect(out[0].exercisesA.length, 7, reason: 'countMax 6 plus the guard one lead lift');
      expect(statsA().forcedDays, [0]);
    });

    test('(p) the force prefers the lead lift when the bound allows it, over a cheaper accessory', () {
      // A timed row spends 1100.4 s, leaving 339.6 s. The heavy lead (379 s at 2 sets) does not fit, the first
      // isolation (257 s) does and seats (82.6 s left). rows = 2 < 4. The bound allows the lead (-296.4 s, inside
      // -300) but then nothing else: the lead is forced, not a second isolation.
      final f = Fx();
      f.row('wall', ['Core'], type: 'isolation', reps: '30-60', logging: 'timed');
      f.row('lead', ['Chest'], reps: '5-8');
      f.row('i0', ['Biceps'], type: 'isolation', reps: '10-15');
      f.row('i1', ['Triceps'], type: 'isolation', reps: '10-15');
      f.row('i2', ['Glutes'], type: 'isolation', reps: '10-15');
      final days = [
        f.day('strength', [
          f.ex('wall', sets: 8, logging: 'timed', rest: 81),
          f.ex('lead'), f.ex('i0'), f.ex('i1'), f.ex('i2'),
        ]),
      ];
      final out = f.run(days, minutes: 30);
      final names = [for (final e in out[0].exercisesA) e.exerciseName];
      expect(names, ['wall', 'lead', 'i0']);
      expect(statsA().countForced[0]!.map((e) => e.name), ['lead']);
      expect(statsA().belowCount, {0: 'clock'});
    });

    test('(k) a group whose only slots the count left out is labelled count_limited, not cap_limited', () {
      final f = Fx();
      for (var i = 0; i < 8; i++) {
        f.row('iso$i', [_distinctGroups[i]], type: 'isolation', reps: '10-15');
      }
      final days = [f.day('hypertrophy', [for (var i = 0; i < 8; i++) f.ex('iso$i')])];
      f.run(days, minutes: 90, level: 'beginner');
      // Beginner holds 5: slots 5..7 (Shoulders, Biceps, Triceps) were left out by the count alone.
      expect(statsA().belowFloor['Shoulders'], 'count_limited');
      expect(statsA().belowFloor['Triceps'], 'count_limited');
    });

    test('(h) the lead lift: boundBy is null when only time kept it below 3 (the reservation is not re-applied after pass B)', () {
      // One Chest lead lift beside a timed filler: 456 s are left after the filler, 2 sets of the
      // lift fit (336 s) and a 3rd does not (+186 s): time alone, so boundBy is null.
      final f = Fx();
      f.row('cl', ['Chest']);
      f.row('plank', ['Core'], type: 'isolation', reps: '30-60', logging: 'timed');
      final days = [
        f.day('strength', [f.ex('plank', sets: 6, logging: 'timed', rest: 110), f.ex('cl')]),
      ];
      f.run(days, minutes: 30, goal: 'general_fitness', level: 'beginner');
      final first = statsA().firstLifts.single;
      expect(first.sets, 2);
      expect(first.boundBy, isNull);
    });
  });

  group('the real generator', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('count_band');
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
      HiveService.instance.markInitializedForTests();
      await HiveUserSession.openForUser(testUser);
    });

    tearDownAll(() async {
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
      required int minutes,
      int phase = 1,
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

    test('every day of every week is inside [floor, max] or named by the allocator; the deload keeps the count', () {
      final bad = <String>[];
      var days = 0;
      var forcedSeen = 0;
      for (final tier in ['full_gym', 'bodyweight']) {
        for (final goal in ['build_muscle', 'general_fitness']) {
          for (final n in [3, 4, 5, 6]) {
            for (final level in ['beginner', 'intermediate', 'advanced']) {
              for (final minutes in [15, 20, 25, 30, 31, 35, 44, 45, 60, 90, 120, 180]) {
                final label = '$tier|$goal|${n}d|$level|${minutes}min';
                final plan = gen(goal: goal, tier: tier, days: n, level: level, minutes: minutes);
                final stats = SessionSetAllocator.debugLastStats!;
                for (var w = 0; w < plan.weekPlans.length; w++) {
                  final variant = (w == 1 || w == 3) && n != 6 ? 'B' : 'A';
                  final s = stats[variant]!;
                  final wk = plan.weekPlans[w].workoutDays;
                  for (var di = 0; di < wk.length; di++) {
                    days++;
                    final c = wk[di].exercises.length;
                    final max = _maxByLevel[level]!;
                    final floor = SessionBudget.countFloor(minutes);
                    if (c > max) bad.add('$label w${w + 1} d$di: $c > max $max');
                    final named = s.belowCount.containsKey(di) || s.selectorThin.contains(di);
                    if (c < floor && !named) bad.add('$label w${w + 1} d$di: $c < floor $floor, unnamed');
                    if (s.countForced.containsKey(di)) {
                      forcedSeen++;
                      if (minutes >= 45) bad.add('$label w${w + 1} d$di: countForced at $minutes min');
                    }
                  }
                }
                // Week 4 (deload) keeps week 2's count, week 3 keeps week 1's.
                for (var di = 0; di < plan.weekPlans[0].workoutDays.length; di++) {
                  final w1 = plan.weekPlans[0].workoutDays[di].exercises.length;
                  final w3 = plan.weekPlans[2].workoutDays[di].exercises.length;
                  final w2 = plan.weekPlans[1].workoutDays[di].exercises.length;
                  final w4 = plan.weekPlans[3].workoutDays[di].exercises.length;
                  if (w1 != w3) bad.add('$label d$di: week 3 holds $w3, week 1 held $w1');
                  if (w2 != w4) bad.add('$label d$di: week 4 holds $w4, week 2 held $w2');
                }
              }
            }
          }
        }
      }
      expect(days, greaterThan(5000));
      expect(forcedSeen, greaterThan(0), reason: 'non-vacuity: the sweep reaches a forced day');
      expect(bad.take(10).toList(), isEmpty, reason: '${bad.length} of $days days');
    });

    test('the tester plan (intermediate, basic_gym, 4 days, build_muscle) holds 6 on every day at 45 / 60 / 90 and 4 at 30', () {
      for (final (minutes, want) in [(30, 4), (45, 6), (60, 6), (90, 6)]) {
        final p = gen(goal: 'build_muscle', tier: 'basic_gym', days: 4, level: 'intermediate', minutes: minutes);
        expect([for (final d in p.weekPlans[0].workoutDays) d.exercises.length], everyElement(want),
            reason: '$minutes min');
      }
    });
  });
}
