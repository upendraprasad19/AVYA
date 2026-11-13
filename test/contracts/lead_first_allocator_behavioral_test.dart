// Unit 2A (OI-486, docs/plans/2026-11-12-generator-step2-allocator.md, founder d26-d29): the lead-first set allocator.
// A day's LEAD is the budgeted row the sequencer opens it with (`SequencingEngine.openerOf`). R1: the lead is seated at
// the base 3 in pass A when that fits; R2: no other budgeted row grows past the lead + 1 in pass C (pass D, the focus
// pass, is exempt); R3: per variant, the lead world, else the capped world, else main's, whichever is first not worse
// than main (`SessionSetAllocator.worldIsWorse`); R5: week 2 holds a non-lead, non-focus row (a hold included) to the
// lead's week-2 sets + 1. Kill switch `disable_lead_first` (`PlanEngineFlags.leadFirstEnabled`, default ON).
//
// Pure Dart over crafted fixtures (plus a Hive config box for the kill-switch group). Every expected list was worked
// by hand from the plan's rules and the budget's time model before the test was run: build_muscle intermediate unless
// stated (weekly band 12-16, session cap 8, count max 6); a compound ('M', 120 s rest) costs 336 s at 2 sets and 522 s
// at 3 (+186 a set), an isolation ('I', 75 s rest) 256.8 s at 2 and 403.2 s at 3 (+146.4 a set); budgets 1440 s at
// 30 minutes (count floor 4), 2220 s at 45 and 4560 s at 90 (floor 5).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/periodization_engine.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/sequencing_engine.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_set_allocator.dart';

import '../helpers/session_budget_fixtures.dart';

AllocationStats statsA() => SessionSetAllocator.debugLastStats!['A']!;
AllocationStats statsB() => SessionSetAllocator.debugLastStats!['B']!;

PlannedExercise _pe(String name, String type, {List<String> muscles = const [], int sets = 3, String logging = 'weight_reps'}) =>
    PlannedExercise(
      exerciseId: name.toLowerCase(),
      exerciseName: name,
      loggingType: logging,
      sets: sets,
      reps: '10',
      restSeconds: 75,
      exerciseType: type,
      primaryMuscles: muscles,
    );

/// The first row `SequencingEngine.sequence` puts in a one-day week built from [list] (`_reorderDay`'s first row).
String _sequencedFirst(List<PlannedExercise> list) => SequencingEngine.sequence([
      WeekPlan(
        weekNumber: 1,
        weekInPhase: 1,
        overloadNotes: '',
        workoutDays: [WorkoutDay(dayNumber: 1, name: 'D', focus: 'F', exercises: list)],
      ),
    ]).first.workoutDays.first.exercises.first.exerciseName;

/// A custom row (`customOrigin` set): not budgeted, so it only spends the day's time, at its archetype's rest.
PlannedExercise _sink(Fx f, String name, int sets) => f.ex(name, sets: sets, customOrigin: 'repeat_pin');

void main() {
  group('1. the lead: SequencingEngine.openerOf', () {
    test('a bilateral compound before a unilateral one, whatever the list order', () {
      final lunge = _pe('Dumbbell Lunge', 'compound');
      final row = _pe('Barbell Row', 'compound');
      for (final list in [
        [lunge, row],
        [row, lunge],
      ]) {
        expect(SequencingEngine.openerOf(list)!.exerciseName, 'Barbell Row');
        expect(_sequencedFirst(list), 'Barbell Row');
      }
    });

    test('within a tier, the higher CNS demand first', () {
      final list = [_pe('Dumbbell Row', 'compound'), _pe('Barbell Bench Press', 'compound')];
      expect(SequencingEngine.openerOf(list)!.exerciseName, 'Barbell Bench Press');
      expect(_sequencedFirst(list), 'Barbell Bench Press');
    });

    test('an isolation opens only a day with no compound', () {
      final withCompound = [_pe('Leg Curl', 'isolation'), _pe('Goblet Squat', 'compound')];
      expect(SequencingEngine.openerOf(withCompound)!.exerciseName, 'Goblet Squat');
      // Two isolations: the higher CNS demand ('leg press' in the name rates 3, a fly 1).
      final isolations = [_pe('Cable Fly', 'isolation'), _pe('Leg Press Calf Raise', 'isolation')];
      expect(SequencingEngine.openerOf(isolations)!.exerciseName, 'Leg Press Calf Raise');
      expect(_sequencedFirst(isolations), 'Leg Press Calf Raise');
      expect(SequencingEngine.openerOf(const []), isNull);
    });

    test('tied rows: the first in list order, as _reorderDay keeps it (List.sort is stable below 32 rows)', () {
      final a = _pe('Fly One', 'isolation');
      final b = _pe('Fly Two', 'isolation');
      expect(SequencingEngine.openerOf([a, b])!.exerciseName, 'Fly One');
      expect(SequencingEngine.openerOf([b, a])!.exerciseName, 'Fly Two');
      expect(_sequencedFirst([a, b]), 'Fly One');
      expect(_sequencedFirst([b, a]), 'Fly Two');
      final c = _pe('Press One', 'compound');
      final d = _pe('Press Two', 'compound');
      expect(SequencingEngine.openerOf([c, d, a])!.exerciseName, 'Press One');
      expect(SequencingEngine.openerOf([d, c, a])!.exerciseName, 'Press Two');
    });

    test('library sweep: for every pair of rows sharing a movement pattern, in both orders, openerOf names the '
        'row _reorderDay puts first', () {
      final rows = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List)
          .whereType<Map>()
          .toList();
      final byPattern = <String, List<PlannedExercise>>{};
      for (final r in rows) {
        final t = r['exercise_type'];
        final type = t is List ? (t.isEmpty ? null : '${t.first}') : t?.toString();
        byPattern.putIfAbsent('${r['movement_pattern']}', () => []).add(PlannedExercise(
              exerciseId: '${r['id'] ?? r['name']}',
              exerciseName: '${r['name']}',
              loggingType: '${r['logging_type'] ?? 'weight_reps'}',
              sets: 3,
              reps: '10',
              restSeconds: 75,
              exerciseType: type,
            ));
      }
      var pairs = 0;
      final bad = <String>[];
      for (final list in byPattern.values) {
        for (var i = 0; i < list.length; i++) {
          for (var j = 0; j < list.length; j++) {
            if (i == j) continue;
            final pair = [list[i], list[j]];
            pairs++;
            final want = _sequencedFirst(pair);
            if (SequencingEngine.openerOf(pair)!.exerciseName != want) bad.add('${list[i].exerciseName} / ${list[j].exerciseName}');
          }
        }
      }
      expect(pairs, greaterThan(10000), reason: 'the sweep must cover the library');
      expect(bad, isEmpty, reason: '${bad.length} pairs differ; first: ${bad.take(5)}');
    });

    test('a day whose opener is not admitted: the lead is openerOf over the ADMITTED slots, not the first by rank', () {
      // 30 minutes. A custom sink at 4 sets (708 s) leaves 732 s. iso1 (rank 0) and the Leg Press Calf Raise (rank 1,
      // CNS 3) seat at 2 (218.4 s left); the heavy compound (the opener, rank 2) fits neither at 3 (586.8) nor at 2
      // (379.2) and has no hold to evict; iso3 does not fit either, and the count floor (4) forces iso3 at 2 (38.4 s
      // over). The admitted slots' opener is the Leg Press Calf Raise (CNS 3), not iso1 (rank 0, CNS 1).
      final f = Fx();
      f.row('cust', ['Chest']);
      f.row('iso1', ['Biceps'], type: 'isolation');
      f.row('Leg Press Calf Raise', ['Calves'], type: 'isolation');
      f.row('heavy', ['Quads'], reps: '5-8');
      f.row('iso3', ['Triceps'], type: 'isolation');
      final out = f.run([
        f.day('hypertrophy', [_sink(f, 'cust', 4), f.ex('iso1'), f.ex('Leg Press Calf Raise'), f.ex('heavy'), f.ex('iso3')]),
      ], minutes: 30);
      expect(setsOf(out[0]), [('cust', 4), ('iso1', 2), ('Leg Press Calf Raise', 2), ('iso3', 2)]);
      expect(statsA().leadSeats.map((l) => l.name), ['Leg Press Calf Raise']);
      expect(statsA().leadWorld, 'lead');
    });
  });

  group('2. R1: the lead seated at the base sets in pass A', () {
    // 30 minutes, the lead a compound (Back), four isolations. ON: the lead at 3 (522), three isolations (1292.4,
    // 147.6 left), acc4 does not fit, pass B grows acc1 (+146.4). OFF: five rows at 2 (1363.2, 76.8 left, no growth).
    List<PopulatedDay> rankZero(Fx f) {
      f.row('lead', ['Lats']);
      f.row('acc1', ['Biceps'], type: 'isolation');
      f.row('acc2', ['Triceps'], type: 'isolation');
      f.row('acc3', ['Shoulders'], type: 'isolation');
      f.row('acc4', ['Triceps'], type: 'isolation');
      return [
        f.day('hypertrophy', [f.ex('lead'), f.ex('acc1'), f.ex('acc2'), f.ex('acc3'), f.ex('acc4')])
      ];
    }

    test('a lead at rank 0 is seated at 3 when it fits; no other slot is seated at 3 in pass A', () {
      final f = Fx();
      final days = rankZero(f);
      expect(setsOf(f.run(days, minutes: 30)[0]), [('lead', 3), ('acc1', 3), ('acc2', 2), ('acc3', 2)]);
      expect(statsA().leadWorld, 'lead');
      expect(statsA().leadSeats.single, (day: 0, rank: 0, name: 'lead', sets: 3, boundBy: null));
      expect(setsOf(f.run(days, minutes: 30, leadFirst: false)[0]),
          [('lead', 2), ('acc1', 2), ('acc2', 2), ('acc3', 2), ('acc4', 2)]);
      expect(statsA().leadWorld, isNull);
    });

    test('a lead at rank 2 (the opener, not rank 0) is seated at 3 at its own rank', () {
      // ON: iso1 256.8, iso2 513.6, lead at 3 1035.6, iso3 1292.4, iso4 refused (147.6 left); pass B: iso1 to 3.
      // R1 on rank 0 instead would seat iso1 at 3 and the lead at 2: [3, 3, 2, 2].
      final f = Fx();
      f.row('iso1', ['Biceps'], type: 'isolation');
      f.row('iso2', ['Triceps'], type: 'isolation');
      f.row('lead', ['Lats']);
      f.row('iso3', ['Shoulders'], type: 'isolation');
      f.row('iso4', ['Triceps'], type: 'isolation');
      final days = [
        f.day('hypertrophy', [f.ex('iso1'), f.ex('iso2'), f.ex('lead'), f.ex('iso3'), f.ex('iso4')])
      ];
      expect(setsOf(f.run(days, minutes: 30)[0]), [('iso1', 3), ('iso2', 2), ('lead', 3), ('iso3', 2)]);
      expect(statsA().leadSeats.single.rank, 2);
      expect(setsOf(f.run(days, minutes: 30, leadFirst: false)[0]),
          [('iso1', 2), ('iso2', 2), ('lead', 2), ('iso3', 2), ('iso4', 2)]);
    });

    test('a hold that would sort first is never the lead: R1 seats the budgeted opener', () {
      // 30 minutes. wallsit is a library timed row typed compound (archetype B, 3 sets at 60 s rest: 324 s), first in
      // the list, and ties the lead on every sort key, so over ALL rows the sequencer's opener would be the hold. The
      // lead is openerOf over the BUDGETED rows: lead at 3 (522), acc1 and acc2 at 2 (80.4 s left); acc3 does not fit
      // (the hold sits before it, so it is not evicted) and the day holds the floor (4). Fed every row, R1 would find no
      // slot and seat the lead at 2: [wallsit, lead 2, acc1 2, acc2 2, acc3 2].
      final f = Fx();
      f.row('wallsit', ['Quads'], reps: '30-60', logging: 'timed');
      f.row('lead', ['Lats']);
      f.row('acc1', ['Biceps'], type: 'isolation');
      f.row('acc2', ['Triceps'], type: 'isolation');
      f.row('acc3', ['Triceps'], type: 'isolation');
      final out = f.run([
        f.day('hypertrophy', [
          f.ex('wallsit', sets: 3, logging: 'timed', rest: 60), f.ex('lead'), f.ex('acc1'), f.ex('acc2'), f.ex('acc3'),
        ])
      ], minutes: 30);
      expect(setsOf(out[0]), [('wallsit', 3), ('lead', 3), ('acc1', 2), ('acc2', 2)]);
      expect(statsA().leadWorld, 'lead');
    });

    test('the clock refuses 3: the lead is seated at 2, exactly as on main', () {
      // A custom H sink at 5 sets (1002 s) leaves 438 s: the lead does not fit at 3 (522) but does at 2 (336, 102
      // left); acc (256.8) does not fit, and the count floor (3: the day's reach) forces it, 154.8 s over. A fits
      // check that priced the lead at 2 would seat it at 3.
      final f = Fx();
      f.row('cust', ['Core'], reps: '5-8');
      f.row('lead', ['Lats']);
      f.row('acc', ['Biceps'], type: 'isolation');
      final days = [f.day('hypertrophy', [_sink(f, 'cust', 5), f.ex('lead'), f.ex('acc')])];
      final on = setsOf(f.run(days, minutes: 30)[0]);
      expect(on, [('cust', 5), ('lead', 2), ('acc', 2)]);
      // The lead world itself holds this day (it equals main's): a lead seated at 3 on a 2-set price would overrun by
      // 84 s, acc could no longer be forced (340.8 s over), the lead world would be a row short and A would fall back
      // to the capped world, so the rows alone would not show it.
      expect(statsA().leadWorld, 'lead');
      expect(statsA().leadSeats.single.boundBy, 'clock');
      expect(on, setsOf(f.run(days, minutes: 30, leadFirst: false)[0]));
    });

    test('the lead\'s session cap refuses 3: the lead is seated at 2, and R2 then caps an accessory at 3', () {
      // build_muscle beginner (cap 6, Biceps band 10-12), 90 minutes. b1 and b2 (Back isolations) seat at 2 (Back 4);
      // the lead (Back compound, the opener) at 3 would be 7 > 6, so it is seated at 2 (Back 6); x (Biceps) at 2.
      // Pass B: Back is at its cap, x grows to 3. Pass C: Biceps is under its floor, but x is capped at the lead + 1
      // = 3 (main grows it to the per-exercise maximum, 5).
      final f = Fx();
      f.row('b1', ['Lats'], type: 'isolation');
      f.row('b2', ['Lats'], type: 'isolation');
      f.row('lead', ['Lats']);
      f.row('x', ['Biceps'], type: 'isolation');
      final days = [f.day('hypertrophy', [f.ex('b1'), f.ex('b2'), f.ex('lead'), f.ex('x')])];
      expect(setsOf(f.run(days, minutes: 90, level: 'beginner')[0]), [('b1', 2), ('b2', 2), ('lead', 2), ('x', 3)]);
      expect(statsA().leadSeats.single.boundBy, 'Back');
      expect(setsOf(f.run(days, minutes: 90, level: 'beginner', leadFirst: false)[0]),
          [('b1', 2), ('b2', 2), ('lead', 2), ('x', 5)]);
    });

    test('the rank-0 reservation refuses 3: every lead at 2, exactly as on main', () {
      // build_muscle beginner (Back top 12), six days each led by a Back compound. Day 0's lead at 3 would leave
      // 12 - 3 = 9 < 2 x 5 for the later five; at 2 it leaves 10. Every later lead likewise; the last fills the top.
      final f = Fx();
      f.row('row', ['Lats']);
      final days = [for (var i = 0; i < 6; i++) f.day('hypertrophy', [f.ex('row')])];
      final on = f.run(days, minutes: 90, level: 'beginner');
      expect([for (final d in on) d.exercisesA.single.sets], [2, 2, 2, 2, 2, 2]);
      expect(statsA().weekly['Back'], 12);
    });

    test('the reservation keeps room for the later days\' RANK-0 rows, not their leads: every rank-0 row is seated', () {
      // build_muscle beginner (Chest top 12), 90 minutes, 6-day. Day 0: P (Chest compound, rank 0, the lead). Days 1-5:
      // fly (Chest isolation, rank 0) then a compound of another group (the opener, rank 1). Day 0's lead at 3 would
      // leave 12 - 3 = 9 < 2 x 5 for the later rank-0 flies, so P is seated at 2 and every fly fits (Chest 12). Read
      // against the later days' leads (no Chest), P would take 3 and day 5's fly would no longer fit the top: the lead
      // world a row short there, and A would fall back to the capped world.
      final f = Fx();
      f.row('P', ['Chest']);
      f.row('fly', ['Chest'], type: 'isolation');
      final others = ['Lats', 'Quads', 'Hamstrings', 'Glutes', 'Shoulders'];
      for (final m in others) {
        f.row('X$m', [m]);
      }
      final out = f.run([
        f.day('hypertrophy', [f.ex('P')]),
        for (final m in others) f.day('hypertrophy', [f.ex('fly'), f.ex('X$m')]),
      ], minutes: 90, level: 'beginner');
      expect(statsA().leadWorld, 'lead');
      expect(out[0].exercisesA.single.sets, 2);
      for (var d = 1; d < 6; d++) {
        expect([for (final e in out[d].exercisesA) e.exerciseName], ['fly', 'X${others[d - 1]}'], reason: 'day $d');
      }
      expect(statsA().weekly['Chest'], 12);
    });

    test('the lead seated at 3 counts once against the day\'s target: a day at its target seats no extra row', () {
      // beginner (5 a day), 90 minutes: the lead at 3, then four isolations at 2; the sixth slot is left out by the count.
      final f = Fx();
      f.row('lead', ['Lats']);
      final groups = ['Biceps', 'Triceps', 'Shoulders', 'Calves', 'Core'];
      for (var i = 0; i < 5; i++) {
        f.row('i$i', [groups[i]], type: 'isolation');
      }
      final out = f.run([
        f.day('hypertrophy', [f.ex('lead'), for (var i = 0; i < 5; i++) f.ex('i$i')])
      ], minutes: 90, level: 'beginner');
      expect([for (final e in out[0].exercisesA) e.exerciseName], ['lead', 'i0', 'i1', 'i2', 'i3']);
      expect(out[0].exercisesA.first.sets, greaterThanOrEqualTo(3));
    });
  });

  group('3. R2: no accessory more than 1 set above its day\'s lead (pass C); pass D exempt', () {
    // 90 minutes, 6-day (B = A). Day 0: row (Back compound, the lead) and curl (Biceps). Days 1-2 bring Back to its
    // floor (12) by the end of pass B: row 3 + b1 3 + b2 3 + b3 3, so pass C never grows a Back row and the lead stays
    // at 3. Pass C then grows curl towards the Biceps floor: capped at 3 + 1 = 4 (main: 5).
    (Fx, List<PopulatedDay>) fixture() {
      final f = Fx();
      f.row('row', ['Lats']);
      f.row('curl', ['Biceps'], type: 'isolation');
      for (final b in ['b1', 'b2', 'b3']) {
        f.row(b, ['Lats']);
      }
      return (
        f,
        [
          f.day('hypertrophy', [f.ex('row'), f.ex('curl')]),
          f.day('hypertrophy', [f.ex('b1'), f.ex('b2')]),
          f.day('hypertrophy', [f.ex('b3')]),
        ]
      );
    }

    test('a lead at 3: an accessory under its weekly floor stops at 4 (not 3, not 5)', () {
      final (f, days) = fixture();
      expect(setsOf(f.run(days, minutes: 90)[0]), [('row', 3), ('curl', 4)]);
      expect(statsA().weekly['Back'], 12);
      expect(setsOf(f.run(days, minutes: 90, leadFirst: false)[0]), [('row', 3), ('curl', 5)]);
    });

    test('a focus-group accessory passes the cap in pass D (founder d27); in pass C it does not', () {
      final (f, days) = fixture();
      expect(setsOf(f.run(days, minutes: 90, focus: {'Biceps'})[0]), [('row', 3), ('curl', 5)]);
    });

    test('pass C caps a focus row too: on a tight clock the non-focus rows grow first, pass D takes what is left', () {
      // The fixture plus a custom sink (16 isolation sets, 2306.4 s) and two Triceps rows on day 0; Biceps focus. After
      // pass B day 0 has 522 s left (row 3, curl, t1, t2 at 3). Pass C, one set per group a round (Biceps before
      // Triceps): curl 4, t1 4; then curl is capped at the lead + 1 and t2 takes 4 (82.8 s left); pass D cannot add
      // curl's fifth set (146.4). Exempt in pass C as well, curl would take 5 in round 2 and t2 would stay at 3.
      final (f, days) = fixture();
      f.row('sink', ['Chest'], type: 'isolation');
      f.row('t1', ['Triceps'], type: 'isolation');
      f.row('t2', ['Triceps'], type: 'isolation');
      final day0 = f.day('hypertrophy', [_sink(f, 'sink', 16), f.ex('row'), f.ex('curl'), f.ex('t1'), f.ex('t2')]);
      final out = f.run([day0, ...days.skip(1)], minutes: 90, focus: {'Biceps'});
      expect(statsA().leadWorld, 'lead');
      expect(setsOf(out[0]), [('sink', 16), ('row', 3), ('curl', 4), ('t1', 4), ('t2', 4)]);
    });

    test('the cap reads the opener, not rank 0: a rank-0 accessory at 3 does not hold a rank-1 accessory at 4', () {
      // 90 minutes, 6-day. Day 0: a (Triceps isolation, rank 0), b (Biceps isolation), L (Back compound, the opener, rank
      // 2). Days 1-2 bring Triceps to its floor (t1 3 + t2 3 + t3 3 + a 3 = 12), so a stays at 3. Back has only L, so
      // pass C grows L to 4 and 5 and b with it (b <= L + 1): b ends at 5. Read against rank 0 (a, at 3), b would stop
      // at 4.
      final f = Fx();
      f.row('a', ['Triceps'], type: 'isolation');
      f.row('b', ['Biceps'], type: 'isolation');
      f.row('L', ['Lats']);
      for (final t in ['t1', 't2', 't3']) {
        f.row(t, ['Triceps'], type: 'isolation');
      }
      final out = f.run([
        f.day('hypertrophy', [f.ex('a'), f.ex('b'), f.ex('L')]),
        f.day('hypertrophy', [f.ex('t1'), f.ex('t2')]),
        f.day('hypertrophy', [f.ex('t3')]),
      ], minutes: 90);
      expect(setsOf(out[0]), [('a', 3), ('b', 5), ('L', 5)]);
      expect(statsA().weekly['Triceps'], 12);
    });
  });

  group('4. R3: the per-variant fallback', () {
    test('worldIsWorse: a day at exactly min(floor, main rows) is not worse, one row fewer is', () {
      expect(SessionSetAllocator.worldIsWorse([5, 4], const {}, [6, 4], const {}, 5), isFalse);
      expect(SessionSetAllocator.worldIsWorse([4, 4], const {}, [6, 4], const {}, 5), isTrue);
      expect(SessionSetAllocator.worldIsWorse([5, 3], const {}, [6, 4], const {}, 5), isTrue);
    });

    test('worldIsWorse: a thin day (main under the floor) compares against main\'s rows, not the floor', () {
      expect(SessionSetAllocator.worldIsWorse([3], const {}, [3], const {}, 5), isFalse);
      expect(SessionSetAllocator.worldIsWorse([2], const {}, [3], const {}, 5), isTrue);
    });

    test('worldIsWorse: a group main trains that the world has at 0 is worse; a group main does not train is not', () {
      expect(SessionSetAllocator.worldIsWorse([5], const {}, [5], const {'Calves': 4}, 5), isTrue);
      expect(SessionSetAllocator.worldIsWorse([5], const {'Calves': 2}, [5], const {'Calves': 4}, 5), isFalse);
      expect(SessionSetAllocator.worldIsWorse([5], const {'Calves': 2}, [5], const {}, 5), isFalse);
      expect(SessionSetAllocator.worldIsWorse([5], const {}, [5], const {}, 5), isFalse);
    });

    test('the lead world zeroing a group is not kept: the capped world is (and it is never worse than main in A)', () {
      // R1's rank-0 fixture with acc4 crediting Calves (the week's only Calves): the lead world drops it, so A keeps
      // the capped world: main's pass A, five rows at 2.
      final f = Fx();
      f.row('lead', ['Lats']);
      f.row('acc1', ['Biceps'], type: 'isolation');
      f.row('acc2', ['Triceps'], type: 'isolation');
      f.row('acc3', ['Shoulders'], type: 'isolation');
      f.row('acc4', ['Calves'], type: 'isolation');
      final out = f.run([
        f.day('hypertrophy', [f.ex('lead'), f.ex('acc1'), f.ex('acc2'), f.ex('acc3'), f.ex('acc4')])
      ], minutes: 30);
      expect(setsOf(out[0]), [('lead', 2), ('acc1', 2), ('acc2', 2), ('acc3', 2), ('acc4', 2)]);
      expect(statsA().leadWorld, 'capped');
      expect(statsA().weekly['Calves'], 2);
    });

    // 45 minutes. Day 1: a custom sink (5 isolation sets, 696 s), lead2 (Quads compound) and four isolations; k4 is
    // the week's only Hamstrings. The lead world seats lead2 at 3 and k1-k3 (1988.4 s), k4 does not fit (2245.2) and
    // the day already holds the floor (5): Hamstrings at 0, so the lead world is worse. Main seats all (2059.2 s).
    List<PlannedExercise> hamstringDay(Fx f) {
      f.row('sink1', ['Chest'], type: 'isolation');
      f.row('lead2', ['Quads']);
      f.row('k1', ['Calves'], type: 'isolation');
      f.row('k2', ['Core'], type: 'isolation');
      f.row('k3', ['Glutes'], type: 'isolation');
      f.row('k4', ['Hamstrings'], type: 'isolation');
      return [_sink(f, 'sink1', 5), f.ex('lead2'), f.ex('k1'), f.ex('k2'), f.ex('k3'), f.ex('k4')];
    }

    test('R2 runs in the capped world; its focus exemption too', () {
      // Day 2 (lots of time): r (Back compound, the opener), x1 and x2 (Back isolations), c (Biceps). Capped world:
      // r 2, x1 2, x2 2, c 2; pass B: r 3, x1 3 (Back 8, the cap), x2 stays 2, c 3. Pass C: Back cannot grow (the cap,
      // and day 0's lead2 is Quads), Biceps under its floor: c capped at r + 1 = 4. With a Biceps focus, pass D takes
      // c to 5.
      for (final (focus, want) in [(<String>{}, 4), ({'Biceps'}, 5)]) {
        final f = Fx();
        f.row('r', ['Lats']);
        f.row('x1', ['Lats'], type: 'isolation');
        f.row('x2', ['Lats'], type: 'isolation');
        f.row('c', ['Biceps'], type: 'isolation');
        final out = f.run([
          f.day('hypertrophy', hamstringDay(f)),
          f.day('hypertrophy', [f.ex('r'), f.ex('x1'), f.ex('x2'), f.ex('c')]),
        ], minutes: 45, focus: focus);
        expect(statsA().leadWorld, 'capped', reason: 'focus $focus');
        expect(setsOf(out[1]), [('r', 3), ('x1', 3), ('x2', 2), ('c', want)], reason: 'focus $focus');
        expect(statsA().weekly['Hamstrings'], 2);
      }
    });

    test('the capped world caps against the opener too, not rank 0', () {
      // Group 3's opener-not-rank-0 fixture at 45 minutes, with the Hamstrings day in front so A keeps the capped
      // world. Day 1: a (Triceps, rank 0), b (Biceps), L (Back compound, the opener, rank 2), all at 3 after pass B;
      // Triceps reaches its floor on days 2-3 (a 3 + t1 3 + t2 3 + t3 3). Pass C grows L to 5 and b with it (1993.2 s
      // of 2220). Read against rank 0 (a, at 3), b would stop at 4.
      final f = Fx();
      f.row('a', ['Triceps'], type: 'isolation');
      f.row('b', ['Biceps'], type: 'isolation');
      f.row('L', ['Lats']);
      for (final t in ['t1', 't2', 't3']) {
        f.row(t, ['Triceps'], type: 'isolation');
      }
      final out = f.run([
        f.day('hypertrophy', hamstringDay(f)),
        f.day('hypertrophy', [f.ex('a'), f.ex('b'), f.ex('L')]),
        f.day('hypertrophy', [f.ex('t1'), f.ex('t2')]),
        f.day('hypertrophy', [f.ex('t3')]),
      ], minutes: 45);
      expect(statsA().leadWorld, 'capped');
      expect(setsOf(out[1]), [('a', 3), ('b', 5), ('L', 5)]);
      expect(statsA().weekly['Triceps'], 12);
    });

    test('A keeps the capped world: B (every day copied) takes the CAPPED world\'s stats for its copied days', () {
      // Day 0: a custom sink (7 isolation sets, 988.8 s), the lead (Back compound) and three isolations. In the lead
      // world the lead at 3 leaves i3 to the count floor (forced, 61.2 s over: countForced); in the capped world the
      // day fits (2095.2 s), nothing forced. Day 1 makes the lead world worse (above), so A keeps the capped world, and
      // B, whose days are all copies, must report the capped world's countForced (none), not the lead world's.
      final f = Fx();
      f.row('sink0', ['Chest'], type: 'isolation');
      f.row('lead', ['Lats']);
      f.row('i1', ['Biceps'], type: 'isolation');
      f.row('i2', ['Triceps'], type: 'isolation');
      f.row('i3', ['Shoulders'], type: 'isolation');
      final out = f.run([
        f.day('hypertrophy', [_sink(f, 'sink0', 7), f.ex('lead'), f.ex('i1'), f.ex('i2'), f.ex('i3')]),
        f.day('hypertrophy', hamstringDay(f)),
      ], minutes: 45, is6Day: false);
      expect(statsA().leadWorld, 'capped');
      expect(statsA().countForced, isEmpty);
      expect(statsB().countForced, isEmpty);
      expect(setsOf(out[0]), [('sink0', 7), ('lead', 2), ('i1', 2), ('i2', 2), ('i3', 2)]);
      expect(setsOf(out[0], b: true), setsOf(out[0]));
    });

    // Not 6-day. Day 0 (the same list in A and B, so B copies A's allocation): the R1 rank-0 fixture with acc4 on
    // Calves; the lead world drops acc4. Day 1 differs between the variants: A holds a Calves isolation.
    (Fx, List<PopulatedDay>) copyFixture({required bool bHasCalves}) {
      final f = Fx();
      f.row('lead', ['Lats']);
      f.row('acc1', ['Biceps'], type: 'isolation');
      f.row('acc2', ['Triceps'], type: 'isolation');
      f.row('acc3', ['Shoulders'], type: 'isolation');
      f.row('acc4', ['Calves'], type: 'isolation');
      f.row('calf', ['Calves'], type: 'isolation');
      f.row('ham', ['Hamstrings']);
      f.row('calfB', ['Calves'], type: 'isolation');
      return (
        f,
        [
          f.day('hypertrophy', [f.ex('lead'), f.ex('acc1'), f.ex('acc2'), f.ex('acc3'), f.ex('acc4')]),
          f.day('hypertrophy', [f.ex('calf')], b: [f.ex('ham'), if (bHasCalves) f.ex('calfB')]),
        ]
      );
    }

    test('B keeps the lead world over the CHOSEN A: a copied day equals A\'s lead-world day', () {
      // A: the lead world drops acc4 on day 0 but day 1 keeps Calves, so A keeps it. B's day 1 also holds Calves, so
      // B keeps the lead world; its copied day 0 is A's lead-world day (4 rows), not main's (5).
      final (f, days) = copyFixture(bHasCalves: true);
      final out = f.run(days, minutes: 30, is6Day: false);
      expect(statsA().leadWorld, 'lead');
      expect(statsB().leadWorld, 'lead');
      expect(setsOf(out[0]), [('lead', 3), ('acc1', 3), ('acc2', 2), ('acc3', 2)]);
      expect(setsOf(out[0], b: true), setsOf(out[0]));
    });

    test('neither B world holds: the whole plan falls back to main (A = M, B = M_B; A\'s stats are main\'s)', () {
      // B's day 1 has no Calves: B's lead and capped worlds copy A's lead-world day 0 (no acc4), so B has Calves at 0
      // while main's B (copying main's day 0) has them: both worse. The whole plan becomes main's.
      final (f, days) = copyFixture(bHasCalves: false);
      final out = f.run(days, minutes: 30, is6Day: false);
      expect(statsA().leadWorld, 'main');
      expect(statsB().leadWorld, 'main');
      final main = [('lead', 2), ('acc1', 2), ('acc2', 2), ('acc3', 2), ('acc4', 2)];
      expect(setsOf(out[0]), main);
      expect(setsOf(out[0], b: true), main);
      expect(statsB().weekly['Calves'], 2);
    });

    test('the 6-day path allocates B as A (a different B list is ignored, and no B stats are written)', () {
      final (f, days) = copyFixture(bHasCalves: true);
      final out = f.run(days, minutes: 30);
      for (var d = 0; d < out.length; d++) {
        expect(setsOf(out[d], b: true), setsOf(out[d]), reason: 'day $d');
      }
      expect(SessionSetAllocator.debugLastStats!.keys, ['A']);
    });
  });

  group('5. R5: week 2 holds a non-lead row to the lead + 1', () {
    // Lighter phase (every weekly top is the band bottom, 12), 6-day. Day 1 holds Back at 9 (rowA 5, rowB 4), so with
    // day 0's lead at 3 Back is at its top and the lead cannot gain its week-2 set. Rows are budgeted through
    // testBudget's names (archetype B).
    List<PopulatedDay> days(List<PlannedExercise> day0) => [
          PopulatedDay(name: 'D0', focus: 'F', dayType: 'push', intensity: 'hypertrophy', exercisesA: day0, exercisesB: day0),
          PopulatedDay(
            name: 'D1',
            focus: 'F',
            dayType: 'pull',
            intensity: 'hypertrophy',
            exercisesA: [_pe('Row A', 'compound', muscles: ['Lats'], sets: 5), _pe('Row B', 'compound', muscles: ['Lats'], sets: 4)],
            exercisesB: [_pe('Row A', 'compound', muscles: ['Lats'], sets: 5), _pe('Row B', 'compound', muscles: ['Lats'], sets: 4)],
          ),
        ];
    const names = ['Lead Row', 'Acc Curl', 'Iso A', 'Iso B', 'Row A', 'Row B'];

    List<int> week2(List<PopulatedDay> populated, {bool lighter = true, Set<String> focus = const {}, bool? leadFirst, bool is6Day = true}) {
      final weeks = PeriodizationEngine.apply(
        populated: populated,
        phase: 1,
        is6Day: is6Day,
        budget: testBudget(names: names, lighter: lighter, focus: focus),
        leadFirst: leadFirst,
      );
      return [for (final e in weeks[1].workoutDays[0].exercises) e.sets];
    }

    final lead = _pe('Lead Row', 'compound', muscles: ['Lats'], sets: 3);
    final acc = _pe('Acc Curl', 'isolation', muscles: ['Biceps'], sets: 4);
    final hold = _pe('Plank Hold', 'isolation', sets: 4, logging: 'timed');

    test('a lead refused its week-2 set holds an accessory and a hold to the lead + 1', () {
      expect(week2(days([lead, acc, hold])), [3, 4, 4]);
      expect(week2(days([lead, acc, hold]), leadFirst: false), [3, 5, 5]);
    });

    test('a focus row is not held (founder d27)', () {
      expect(week2(days([lead, acc, hold]), focus: {'Biceps'}), [3, 5, 4]);
    });

    test('with the lead gaining, the accessory may gain too', () {
      // Not lighter: Back's top is 16, so the lead gains (3 to 4) before the accessory, which may then reach 5.
      expect(week2(days([lead, acc, hold]), lighter: false), [4, 5, 5]);
    });

    test('a day whose opener is at rank 2 caps a rank-1 accessory against the opener, not rank 0', () {
      // Iso A (rank 0, 3 sets) gains to 4; Iso B (rank 1, 4 sets) may not reach 5 (> lead 3 + 1). Read against rank 0
      // (Iso A, 4 after its gain), Iso B would gain.
      final isoA = _pe('Iso A', 'isolation', muscles: ['Biceps'], sets: 3);
      final isoB = _pe('Iso B', 'isolation', muscles: ['Triceps'], sets: 4);
      expect(week2(days([isoA, isoB, lead])), [4, 4, 3]);
    });

    test('week 2 reads the B list: the lead is the B list\'s opener', () {
      final isoB = _pe('Iso B', 'isolation', muscles: ['Triceps'], sets: 4);
      final x = _pe('Iso A', 'isolation', muscles: ['Biceps'], sets: 3);
      final rows = days([x]);
      final populated = [
        PopulatedDay(name: 'D0', focus: 'F', dayType: 'push', intensity: 'hypertrophy', exercisesA: [x], exercisesB: [isoB, lead]),
        rows[1],
      ];
      expect(week2(populated, is6Day: false), [4, 3]);
      expect(week2(populated, is6Day: false, leadFirst: false), [5, 3]);
    });
  });

  group('6. the kill switch disable_lead_first and the leadFirst argument', () {
    late Directory tempDir;
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      tempDir = await Directory.systemTemp.createTemp('lead_first_flag');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => tempDir.path,
      );
      Hive.init(tempDir.path);
      GuardedBox.testBypassOwnership = true;
      await Hive.openBox(HiveService.configBoxName);
      HiveService.instance.markInitializedForTests();
    });
    tearDownAll(() async {
      await HiveService.instance.configBox.delete('disable_lead_first');
      GuardedBox.testBypassOwnership = false;
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    // The R1 rank-0 fixture: ON [3, 3, 2, 2], OFF five rows at 2.
    List<(String, int)> allocated(bool? leadFirst) {
      final f = Fx();
      f.row('lead', ['Lats']);
      f.row('acc1', ['Biceps'], type: 'isolation');
      f.row('acc2', ['Triceps'], type: 'isolation');
      f.row('acc3', ['Shoulders'], type: 'isolation');
      f.row('acc4', ['Triceps'], type: 'isolation');
      return setsOf(f.run([
        f.day('hypertrophy', [f.ex('lead'), f.ex('acc1'), f.ex('acc2'), f.ex('acc3'), f.ex('acc4')])
      ], minutes: 30, leadFirst: leadFirst)[0]);
    }

    // The R5 fixture: ON [3, 4], OFF [3, 5].
    List<int> applied(bool? leadFirst) {
      final day0 = [_pe('Lead Row', 'compound', muscles: ['Lats'], sets: 3), _pe('Acc Curl', 'isolation', muscles: ['Biceps'], sets: 4)];
      final day1 = [_pe('Row A', 'compound', muscles: ['Lats'], sets: 5), _pe('Row B', 'compound', muscles: ['Lats'], sets: 4)];
      final weeks = PeriodizationEngine.apply(
        populated: [
          PopulatedDay(name: 'D0', focus: 'F', dayType: 'push', intensity: 'hypertrophy', exercisesA: day0, exercisesB: day0),
          PopulatedDay(name: 'D1', focus: 'F', dayType: 'pull', intensity: 'hypertrophy', exercisesA: day1, exercisesB: day1),
        ],
        phase: 1,
        is6Day: true,
        budget: testBudget(names: const ['Lead Row', 'Acc Curl', 'Row A', 'Row B'], lighter: true),
        leadFirst: leadFirst,
      );
      return [for (final e in weeks[1].workoutDays[0].exercises) e.sets];
    }

    const on = [('lead', 3), ('acc1', 3), ('acc2', 2), ('acc3', 2)];
    const off = [('lead', 2), ('acc1', 2), ('acc2', 2), ('acc3', 2), ('acc4', 2)];

    test('unset: the rule is ON (default), and leadFirst: false turns it off for the call', () async {
      await HiveService.instance.configBox.delete('disable_lead_first');
      expect(PlanEngineFlags.leadFirstEnabled, isTrue);
      expect(allocated(null), on);
      expect(allocated(false), off);
      expect(applied(null), [3, 4]);
      expect(applied(false), [3, 5]);
    });

    test('set: the rule is OFF, and leadFirst: true turns it on for the call', () async {
      await HiveService.instance.configBox.put('disable_lead_first', true);
      try {
        expect(PlanEngineFlags.leadFirstEnabled, isFalse);
        expect(allocated(null), off);
        expect(allocated(true), on);
        expect(applied(null), [3, 5]);
        expect(applied(true), [3, 4]);
      } finally {
        await HiveService.instance.configBox.delete('disable_lead_first');
      }
    });
  });
}
