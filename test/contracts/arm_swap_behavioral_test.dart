// Unit 2E (OI-496, founder d51; plan docs/plans/2026-11-15-generator-step2e-arm-swap.md S1-S7): under 60 minutes, a
// variant whose week holds 0 Biceps or 0 Triceps while the other variant trains them swaps the day's last
// over-served row for the arm row, at 2 sets. The row count is unchanged, and the day is no longer than before. The
// seat is a `minimumSeats` entry. The swap's victim may be:
// - a budgeted admitted row or a kept library hold;
// - never rank 0, the day's opener, a minimum seat or a focus row;
// - only a row each of whose groups another row of the day also credits.
// S6: an arm group that B gains late in the 2C-b fixpoint becomes a target of A too.
//
// Pure Dart over crafted fixtures (`session_budget_fixtures.dart`), found by a probe sweep. Two 30-minute days:
// - day 0's A list is a row (Back, rank 0), a 3-set custom (it spends the day's time), two library holds and a curl;
// - B trains Biceps (curlB).
// R (the floor re-run) admits the row and both holds and the clock refuses the curl. The allowance re-run keeps R's 4
// rows (d44), so the minimum pass refuses the curl, and only the swap seats it. The real-engine reach (21 of the 2,304
// audit plans; the 1,152 at 30 / 45 minutes hold all of them) is pinned by the 2E block of
// test/plan_generator/weekly_minimum_gate_test.dart.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/sequencing_engine.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_set_allocator.dart';

import '../helpers/session_budget_fixtures.dart';

Fx lib({List<String> hold0 = const ['Back'], List<String> hold1 = const ['Back'], List<String> arm = const ['Biceps']}) {
  final f = Fx();
  f.row('row', ['Back']);
  f.row('bench', ['Chest']);
  f.row('hold0', hold0, type: 'isolation', logging: 'timed');
  f.row('hold1', hold1, type: 'isolation', logging: 'timed');
  f.row('curlA', arm, type: 'isolation');
  f.row('curlB', arm, type: 'isolation');
  return f;
}

List<PopulatedDay> week(Fx f, {int custom = 3, int hold0Sets = 3, int hold1Sets = 3}) {
  final dA = [
    f.ex('row'),
    if (custom > 0) f.ex('mine', sets: custom, rest: 100, customOrigin: 'user'),
    f.ex('hold0', logging: 'timed', sets: hold0Sets, rest: 30),
    f.ex('hold1', logging: 'timed', sets: hold1Sets, rest: 30),
    f.ex('curlA'),
  ];
  final dB = [f.ex('bench'), f.ex('curlB'), f.ex('row')];
  return [
    f.day('hypertrophy', dA, b: dB),
    f.day('hypertrophy', [f.ex('bench'), f.ex('row')], b: [f.ex('bench'), f.ex('row')]),
  ];
}

// The opener fixtures (found by a 4,158-case probe sweep, round 1): day 0's A list in [order]; heavy is a heavy
// compound (Back, Hamstrings, 3-5 reps), so the 2A opener over the whole list, refused by the clock at 30 minutes.
(Fx, List<PopulatedDay>) openerDays(List<String> order, String arm, int custom) {
  final f = Fx();
  f.row('row', ['Back']);
  f.row('heavy', ['Back', 'Hamstrings'], reps: '3-5');
  f.row('bench', ['Chest']);
  f.row('fly', ['Back'], type: 'isolation');
  f.row('pullover', ['Back'], type: 'isolation');
  f.row('curl', ['Biceps'], type: 'isolation');
  f.row('chin', ['Biceps', 'Back'], reps: '3-6');
  f.row('curlB', ['Biceps'], type: 'isolation');
  final dA = [
    for (final n in order)
      if (n == 'mine') ...[if (custom > 0) f.ex('mine', sets: custom, rest: 100, customOrigin: 'user')]
      else f.ex(n == 'ARM' ? arm : n),
  ];
  return (
    f,
    [
      f.day('hypertrophy', dA, b: [f.ex('bench'), f.ex('curlB'), f.ex('row')]),
      f.day('hypertrophy', [f.ex('bench'), f.ex('row')], b: [f.ex('bench'), f.ex('row')]),
    ]
  );
}

List<String> names(List<PlannedExercise> xs) => [for (final e in xs) e.exerciseName];

/// The whole plan's shape: names and sets of both variants, every day.
List<Object> shape(List<PopulatedDay> out) => [
      for (final d in out) ...[setsOf(d), setsOf(d, b: true)],
    ];

List<PopulatedDay> runArm(Fx f, List<PopulatedDay> days,
    {required bool on, int minutes = 30, String level = 'beginner', Set<String> focus = const {}, bool? balancedWeek}) {
  SessionSetAllocator.debugArmSwap = on;
  try {
    return f.run(days,
        minutes: minutes, level: level, is6Day: false, focus: focus, balancedWeek: balancedWeek);
  } finally {
    SessionSetAllocator.debugArmSwap = true;
  }
}

void main() {
  tearDown(() => SessionSetAllocator.debugArmSwap = true);

  group('the swap', () {
    test('a hold victim: the last over-served hold gives way to the curl (seated at 2, grown to 3); the row count is unchanged', () {
      for (final level in ['beginner', 'intermediate']) {
        final f = lib();
        final off = runArm(f, week(f), on: false, level: level);
        final on = runArm(f, week(f), on: true, level: level);
        expect(names(off[0].exercisesA), ['row', 'mine', 'hold0', 'hold1'], reason: '$level: R refuses the curl');
        expect(names(on[0].exercisesA), ['row', 'mine', 'hold0', 'curlA'], reason: level);
        // Seated at 2 sets by the swap, then grown to the base 3 by pass B like every seat.
        expect(on[0].exercisesA.last.sets, 3);
        expect(on[0].exercisesA.length, off[0].exercisesA.length);
        expect(SessionSetAllocator.debugLastStats!['A']!.minimumSeats[0], [(name: 'curlA', group: 'Biceps')]);
        expect(SessionSetAllocator.debugLastStats!['A']!.credited['Biceps'], 3);
        expect(on[0].allowance, isTrue, reason: 'the allowance world ran, no fallback to R');
        // Week 2 (B) and day 1 are untouched.
        expect([setsOf(on[0], b: true), setsOf(on[1]), setsOf(on[1], b: true)],
            [setsOf(off[0], b: true), setsOf(off[1]), setsOf(off[1], b: true)]);
      }
    });

    test('a hold whose group no other row of the day credits is not a victim: the walk passes it', () {
      // hold1 (last) is the day's only Core row, so the swap walks on to hold0 (Back, which the row also credits).
      final f = lib(hold1: const ['Core']);
      final on = runArm(f, week(f), on: true);
      expect(names(on[0].exercisesA), ['row', 'mine', 'hold1', 'curlA']);
    });

    test('no over-served row at all: no swap', () {
      // Both holds are the day's only row of their group (Core, Glutes); the row is rank 0 and the opener.
      final f = lib(hold0: const ['Glutes'], hold1: const ['Core']);
      final off = runArm(f, week(f), on: false);
      final on = runArm(f, week(f), on: true);
      expect(shape(on), shape(off));
      expect(names(on[0].exercisesA), isNot(contains('curlA')));
    });

    test('a focus-group row is never a victim (d38)', () {
      final f = lib();
      final off = runArm(f, week(f), on: false, focus: const {'Back'});
      final on = runArm(f, week(f), on: true, focus: const {'Back'});
      expect(names(on[0].exercisesA).where((n) => n.startsWith('hold')), names(off[0].exercisesA).where((n) => n.startsWith('hold')));
    });
  });

  // A budgeted victim (probe-found): day 0's A list opens with an isolation (fly, rank 0), then a second Back row
  // (pullover), then the day's opener (row, a compound, so the walk puts the curl behind it), a custom of [custom] sets
  // and the curl. At 30 minutes R admits fly, pullover and row; the curl has no room.
  Fx libB({List<String> fly = const ['Chest'], List<String> pullover = const ['Back'], List<String> arm = const ['Biceps']}) {
    final f = Fx();
    f.row('row', ['Back']);
    f.row('bench', ['Chest']);
    f.row('fly', fly, type: 'isolation');
    f.row('pullover', pullover, type: 'isolation');
    f.row('curlA', arm, type: 'isolation');
    f.row('curlB', const ['Biceps'], type: 'isolation');
    for (var i = 0; i < 6; i++) {
      f.row('press$i', ['Chest']);
    }
    return f;
  }

  List<PopulatedDay> weekB(Fx f, {int custom = 2, int chestDay1 = 0}) => [
        f.day('hypertrophy', [
          f.ex('fly'),
          f.ex('pullover'),
          f.ex('row'),
          if (custom > 0) f.ex('mine', sets: custom, rest: 100, customOrigin: 'user'),
          f.ex('curlA'),
        ], b: [
          f.ex('bench'),
          f.ex('curlB'),
          f.ex('row')
        ]),
        f.day('hypertrophy', [f.ex('bench'), f.ex('row'), for (var i = 0; i < chestDay1; i++) f.ex('press$i')],
            b: [f.ex('bench'), f.ex('row'), for (var i = 0; i < chestDay1; i++) f.ex('press$i')]),
      ];

  group('budgeted victims', () {
    test('a budgeted row whose group no other row of ITS DAY credits is not a victim, though the week trains it', () {
      // pullover is day 0's only Glutes row; day 1 trains Glutes (bridge), so the week would keep Glutes and only the
      // day-level rule refuses.
      final f = libB(pullover: const ['Glutes']);
      f.row('bridge', const ['Glutes']);
      final days = weekB(f);
      final withBridge = [
        days[0],
        f.day('hypertrophy', [f.ex('bench'), f.ex('row'), f.ex('bridge')], b: [f.ex('bench'), f.ex('row'), f.ex('bridge')]),
      ];
      final on = runArm(f, withBridge, on: true);
      expect(names(on[0].exercisesA), contains('pullover'));
    });

    test('the last over-served budgeted row (pullover, a second Back row) gives way to the curl', () {
      for (final level in ['beginner', 'intermediate']) {
        final f = libB();
        final off = runArm(f, weekB(f), on: false, level: level);
        final on = runArm(f, weekB(f), on: true, level: level);
        expect(names(off[0].exercisesA), ['fly', 'pullover', 'row', 'mine'], reason: level);
        expect(names(on[0].exercisesA), ['fly', 'row', 'mine', 'curlA'], reason: level);
        expect(SessionSetAllocator.debugLastStats!['A']!.minimumSeats[0], [(name: 'curlA', group: 'Biceps')]);
      }
    });

    test('never rank 0 (fly) or the opener (row), and never a row whose group no other row credits (pullover)', () {
      // fly and row both credit Back, so each is over-served; pullover is the day's only Glutes row.
      final f = libB(fly: const ['Back'], pullover: const ['Glutes']);
      final off = runArm(f, weekB(f), on: false);
      final on = runArm(f, weekB(f), on: true);
      expect(shape(on), shape(off));
      expect(names(on[0].exercisesA), isNot(contains('curlA')));
    });

    test('a focus-group budgeted row is never a victim (d38)', () {
      final f = libB();
      final on = runArm(f, weekB(f), on: true, focus: const {'Back'});
      expect(names(on[0].exercisesA), contains('pullover'));
      expect(names(on[0].exercisesA), isNot(contains('curlA')));
    });
  });

  group('armPairsOf / lostAny (the re-run keep rule, pure)', () {
    test('armPairsOf counts an arm group at 0 in exactly one variant, either way round', () {
      expect(SessionSetAllocator.armPairsOf({'Biceps': 3}, {}), 1);
      expect(SessionSetAllocator.armPairsOf({}, {'Biceps': 3}), 1, reason: 'symmetric');
      expect(SessionSetAllocator.armPairsOf({'Biceps': 3, 'Triceps': 2}, {}), 2);
      expect(SessionSetAllocator.armPairsOf({'Biceps': 2}, {'Triceps': 2}), 2);
      expect(SessionSetAllocator.armPairsOf({}, {}), 0, reason: 'at 0 in both: not a pair');
      expect(SessionSetAllocator.armPairsOf({'Biceps': 0}, {'Biceps': 2}), 1, reason: 'an explicit 0 is 0');
      expect(SessionSetAllocator.armPairsOf({'Biceps': 2}, {'Biceps': 1}), 0);
      expect(SessionSetAllocator.armPairsOf({'Calves': 2, 'Core': 3}, {}), 0, reason: 'arm groups only');
    });

    test('lostAny: a group the first run credited is at 0 in the re-run, Calves included', () {
      expect(SessionSetAllocator.lostAny({'Calves': 2}, {}), isTrue);
      expect(SessionSetAllocator.lostAny({'Calves': 2}, {'Calves': 0}), isTrue);
      expect(SessionSetAllocator.lostAny({'Calves': 2, 'Back': 3}, {'Calves': 1, 'Back': 3}), isFalse);
      expect(SessionSetAllocator.lostAny({'Calves': 0}, {}), isFalse, reason: 'credited at 0 is not credited');
      expect(SessionSetAllocator.lostAny({}, {'Biceps': 2}), isFalse, reason: 'a gain is not a loss');
    });
  });

  // Two days, each with an arm slot the clock refuses in R. [victims0] / [victims1] are the muscle lists of each day's
  // two holds: ['Back'] holds are over-served (the row credits Back); ['Glutes'] / ['Core'] holds are not.
  (Fx, List<PopulatedDay>) twoDays({
    List<List<String>> holds0 = const [['Glutes'], ['Core']],
    List<List<String>> holds1 = const [['Back'], ['Back']],
    bool compoundArm0 = false,
  }) {
    final f = Fx();
    f.row('row', ['Back']);
    f.row('bench', ['Chest']);
    for (var d = 0; d < 2; d++) {
      final hs = d == 0 ? holds0 : holds1;
      f.row('h${d}a', hs[0], type: 'isolation', logging: 'timed');
      f.row('h${d}b', hs[1], type: 'isolation', logging: 'timed');
    }
    f.row('curl0', ['Biceps'], type: compoundArm0 ? 'compound' : 'isolation');
    f.row('curl1', ['Biceps'], type: 'isolation');
    f.row('curlB', ['Biceps'], type: 'isolation');
    List<PlannedExercise> dayA(int d) => [
          f.ex('row'),
          f.ex('mine', sets: 3, rest: 100, customOrigin: 'user'),
          f.ex('h${d}a', logging: 'timed', sets: 3, rest: 30),
          f.ex('h${d}b', logging: 'timed', sets: 3, rest: 30),
          f.ex('curl$d'),
        ];
    return (
      f,
      [
        f.day('hypertrophy', dayA(0), b: [f.ex('bench'), f.ex('curlB'), f.ex('row')]),
        f.day('hypertrophy', dayA(1), b: [f.ex('bench'), f.ex('row')]),
      ]
    );
  }

  group('which arm slot', () {
    test('the cheapest candidate whose day has no victim is passed for the next one (fall-through)', () {
      final (f, days) = twoDays();
      final on = runArm(f, days, on: true);
      expect(names(on[0].exercisesA), isNot(contains('curl0')), reason: 'day 0 has no over-served row');
      expect(names(on[1].exercisesA), contains('curl1'));
      expect(SessionSetAllocator.debugLastStats!['A']!.minimumSeats[1], [(name: 'curl1', group: 'Biceps')]);
    });

    test('equal cost: the earlier day takes the swap', () {
      final (f, days) = twoDays(holds0: const [['Back'], ['Back']]);
      final on = runArm(f, days, on: true);
      expect(names(on[0].exercisesA), contains('curl0'));
      expect(names(on[1].exercisesA), isNot(contains('curl1')));
    });

    test('the cheaper arm slot goes first, whatever its day', () {
      // Day 0's arm row is a compound (120 s rest against 75), so day 1's curl is cheaper.
      final (f, days) = twoDays(holds0: const [['Back'], ['Back']], compoundArm0: true);
      final on = runArm(f, days, on: true);
      expect(names(on[1].exercisesA), contains('curl1'));
      expect(names(on[0].exercisesA), isNot(contains('curl0')));
    });
  });

  group('the re-run (S8)', () {
    test('a re-run that is not kept leaves the plan, the stamp and the stats of the first run', () {
      // Found by the round-1 probe (an always-keep mutant changes it): at 45 minutes with a 9-set custom the first
      // run falls back to R; the re-run leaves R (allowance world) and keeps the pair (B's chin-up is never seated).
      final (f, base) = openerDays(const ['fly', 'pullover', 'row', 'mine', 'ARM'], 'curl', 9);
      final days = [
        f.day('hypertrophy', base[0].exercisesA,
            b: [f.ex('bench'), f.ex('pullover'), f.ex('mine', sets: 9, rest: 100, customOrigin: 'user'), f.ex('chin')]),
        base[1],
      ];
      final off = runArm(f, days, on: false, minutes: 45, level: 'beginner');
      final offSeats = SessionSetAllocator.debugLastStats!['A']!.minimumSeats;
      expect(SessionSetAllocator.debugLastAllowance, isFalse, reason: 'the first run is R');
      final on = runArm(f, days, on: true, minutes: 45, level: 'beginner');
      expect(shape(on), shape(off));
      expect([for (final d in on) d.allowance], [false, false]);
      expect(SessionSetAllocator.debugLastAllowance, isFalse, reason: 'restored from the first run');
      expect(SessionSetAllocator.debugLastStats!['A']!.minimumSeats, offSeats, reason: 'restored from the first run');
    });
  });

  group('the opener (d48)', () {
    test('a 2A opener that pass A refused protects nothing: the lead is the opener of the admitted rows', () {
      // heavy is the precomputed opener and is not admitted; the day's lead is fly (rank 0), so pullover is a victim.
      final (f, days) = openerDays(const ['fly', 'heavy', 'row', 'pullover', 'mine', 'ARM'], 'curl', 7);
      final off = runArm(f, days, on: false);
      final on = runArm(f, days, on: true);
      expect(setsOf(off[0]), [('fly', 2), ('pullover', 2), ('mine', 7)]);
      expect(setsOf(on[0]), [('fly', 2), ('mine', 7), ('curl', 2)]);
    });

    test('an arm row that would open the day (a compound chin-up over an isolation lead) is not swapped in', () {
      for (final k in [5, 6]) {
        final (f, days) = openerDays(const ['fly', 'pullover', 'heavy', 'row', 'mine', 'ARM'], 'chin', k);
        final off = runArm(f, days, on: false);
        final on = runArm(f, days, on: true);
        expect(shape(on), shape(off), reason: 'custom $k');
        expect(names(on[0].exercisesA), isNot(contains('chin')), reason: 'custom $k');
      }
    });

    test('the shipped library: the swap seats an arm row that IS the day\'s refused 2A opener (seeded sweep plan 122)', () {
      // session_allowance_behavioral_test.dart's seeded sweep, plan 122 (30 minutes, strength, beginner). Kettlebell Two
      // Arm Military Press (Triceps) is day 0's 2A opener over the whole list and pass A refused it; the swap seats it
      // for Handstand Push Up, and the day opens with it. Round 1's first opener rule refused this (CI, ddc06521).
      final rows = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List)
          .cast<Map<String, dynamic>>();
      final byName = {for (final r in rows) (r['name'] as String).toLowerCase(): r};
      PlannedExercise ex(String n) => PlannedExercise(
          exerciseId: n.toLowerCase(),
          exerciseName: n,
          loggingType: byName[n.toLowerCase()]!['logging_type'] as String,
          sets: 3,
          reps: '10',
          restSeconds: 75,
          primaryMuscles: [for (final m in (byName[n.toLowerCase()]!['primary_muscles'] as List)) '$m']);
      PopulatedDay day(String i, List<String> a, List<String> b) => PopulatedDay(
          name: 'D', focus: 'F', dayType: 'push', intensity: i,
          exercisesA: [for (final n in a) ex(n)], exercisesB: [for (final n in b) ex(n)]);
      const d1 = ['Barbell Standing Wide Grip Curl', 'Dumbbell Alternate Preacher Curl', 'Barbell Curl', 'Lever Squat',
          'Oblique Crunches Floor', 'Band Concentration Curl', 'Smith Deadlift', 'Dumbbell Rear Delt Raise'];
      final days = [
        day('strength', [
          'Band Front Raise', 'Backpack Bent-Over Row', 'Handstand Push Up', 'Dumbbell Alternate Seated Hammer Curl',
          'EZ Bar Seated Close Grip Concentration Curl', 'Kettlebell Two Arm Military Press', 'Band Pull Through',
        ], const ['Barbell Reverse Preacher Curl', 'Band Standing Twisting Crunch', 'Machine Lateral Raise', 'Standing Single Leg Curl']),
        day('endurance', d1, d1),
        day('hypertrophy', const [
          'Plate-Loaded Shoulder Press', 'Smith Seated Shoulder Press', 'Bodyweight Rear Delt Raise', 'Cable Upright Row',
          'Kettlebell Bent Press',
        ], const ['Spider Crawl Push Up', 'Calf Press on Leg Press', 'Towel Triceps Extension', 'Cable Reverse Crunch',
          'Smith Full Squat', 'Hindu Pushup', 'Barbell Lunge', 'Leg Press']),
      ];
      final ctx = SessionBudgetContext(minutes: 30, planGoal: 'strength', level: 'beginner', lighterPhase: false,
          focusGroups: const {}, archetypeByName: {for (final e in byName.entries) e.key: SessionBudget.archetypeOfRow(e.value)});
      List<PopulatedDay> alloc(bool on) {
        SessionSetAllocator.debugArmSwap = on;
        try {
          return SessionSetAllocator.allocate(days: days, ctx: ctx, rowsByName: byName, is6Day: false, balancedWeek: true);
        } finally {
          SessionSetAllocator.debugArmSwap = true;
        }
      }
      final off = alloc(false), on = alloc(true);
      expect(setsOf(off[0]), [('Band Front Raise', 3), ('Backpack Bent-Over Row', 3), ('Handstand Push Up', 3),
          ('Dumbbell Alternate Seated Hammer Curl', 2)]);
      expect(setsOf(on[0]), [('Band Front Raise', 3), ('Backpack Bent-Over Row', 3),
          ('Dumbbell Alternate Seated Hammer Curl', 3), ('Kettlebell Two Arm Military Press', 2)]);
      expect(SequencingEngine.openerOf(days[0].exercisesA)?.exerciseName, 'Kettlebell Two Arm Military Press');
      expect(SequencingEngine.openerOf(on[0].exercisesA)?.exerciseName, 'Kettlebell Two Arm Military Press');
      expect(SessionSetAllocator.debugLastStats!['A']!.minimumSeats[0],
          [(name: 'Kettlebell Two Arm Military Press', group: 'Triceps')]);
    });

    test('a swapped-out row leaves floorSeats and countForced (the oracle excuses only rows the plan holds)', () {
      var checked = 0;
      for (final order in const [
        ['fly', 'heavy', 'row', 'pullover', 'mine', 'ARM'],
        ['fly', 'row', 'heavy', 'mine', 'ARM'],
        ['fly', 'pullover', 'heavy', 'row', 'mine', 'ARM'],
        ['row', 'fly', 'pullover', 'mine', 'ARM'],
        ['fly', 'pullover', 'row', 'mine', 'ARM'],
      ]) {
        for (final minutes in [30, 45]) {
          for (final level in ['beginner', 'intermediate', 'advanced']) {
            for (var k = 0; k <= 10; k++) {
              final (f, days) = openerDays(order, 'curl', k);
              final on = runArm(f, days, on: true, minutes: minutes, level: level);
              final st = SessionSetAllocator.debugLastStats!['A']!;
              for (var d = 0; d < on.length; d++) {
                final present = names(on[d].exercisesA).toSet();
                final why = '$order $minutes $level custom $k day $d';
                for (final x in st.floorSeats[d] ?? const <FloorSeat>[]) {
                  expect(present, contains(x.name), reason: '$why floor');
                }
                for (final x in st.countForced[d] ?? const <({String name, int sets})>[]) {
                  expect(present, contains(x.name), reason: '$why forced');
                }
              }
              checked++;
            }
          }
        }
      }
      expect(checked, 330);
    });
  });

  group('victims, round 1', () {
    test('a victim that frees too little is restored and the walk takes the next one', () {
      // hold1 (last, 1 set) is tried first and frees too little time; hold0 (8 sets) is then taken.
      for (final (k, h0, h1, sets) in const [
        (3, 8, 1, [('row', 4), ('mine', 3), ('hold1', 1), ('curlA', 3)]),
        (4, 6, 1, [('row', 3), ('mine', 4), ('hold1', 1), ('curlA', 3)]),
        (5, 3, 1, [('row', 2), ('mine', 5), ('hold1', 1), ('curlA', 3)]),
      ]) {
        final f = lib();
        final on = runArm(f, week(f, custom: k, hold0Sets: h0, hold1Sets: h1), on: true);
        expect(setsOf(on[0]), sets, reason: 'custom $k, holds $h0 / $h1');
      }
    });

    test('a budgeted row with no budget group (Forearms) is a victim too', () {
      final f = libB(pullover: const ['Forearms']);
      final on = runArm(f, weekB(f), on: true);
      expect(names(on[0].exercisesA), ['fly', 'row', 'mine', 'curlA']);
    });

    test('a row with no budget group (Forearms) is a victim like an over-served row: it serves no group', () {
      final f = lib(hold1: const ['Forearms']);
      final on = runArm(f, week(f), on: true);
      expect(names(on[0].exercisesA), ['row', 'mine', 'hold0', 'curlA']);
    });
  });

  group('armFits (the seat check, pure)', () {
    final f = lib();
    // The swap runs only in the allowance world, whose forcing bound is 0.
    BudgetLedger fresh({int minutes = 30}) =>
        BudgetLedger(f.ctx(const [], minutes: minutes, level: 'beginner'), 2, allowance: true);

    test('the session cap of every group of the arm row', () {
      final l = fresh();
      expect(SessionSetAllocator.armFits(l, 0, const {'Biceps'}, 'Biceps', 10, 0), isTrue);
      l.add(0, const {'Biceps'}, l.cap('Biceps') - 1, 0);
      expect(SessionSetAllocator.armFits(l, 0, const {'Biceps'}, 'Biceps', 10, 0), isFalse, reason: 'cap - 1 + 2');
    });

    test('the weekly top of every OTHER group (the target itself is at 0, so its own top never binds)', () {
      final l = fresh();
      l.add(1, const {'Chest'}, l.weeklyTop('Chest') - 1, 0);
      expect(SessionSetAllocator.armFits(l, 0, const {'Biceps', 'Chest'}, 'Biceps', 10, 0), isFalse);
      final m = fresh();
      m.add(1, const {'Biceps'}, m.weeklyTop('Biceps') - 1, 0);
      // Not reachable in the allocator (the target is at 0), but the check is per other group by design.
      expect(SessionSetAllocator.armFits(m, 0, const {'Biceps'}, 'Biceps', 10, 0), isTrue);
    });

    test('time: within the forcing bound, or no longer than the day was before the swap', () {
      final l = fresh();
      final left = l.secondsLeft(0);
      expect(SessionSetAllocator.armFits(l, 0, const {'Biceps'}, 'Biceps', left, left), isTrue, reason: 'exact fill');
      expect(SessionSetAllocator.armFits(l, 0, const {'Biceps'}, 'Biceps', left + 1, left), isFalse);
      // A day already 100 s over: the arm row may cost what the victim freed, no more.
      l.add(0, const {}, 0, left + 100);
      expect(SessionSetAllocator.armFits(l, 0, const {'Biceps'}, 'Biceps', 0, -100), isTrue);
      expect(SessionSetAllocator.armFits(l, 0, const {'Biceps'}, 'Biceps', 1, -100), isFalse);
      // A victim that freed 60 s on that day: 60 s of arm row fit, 61 do not.
      l.add(0, const {}, 0, -60);
      expect(SessionSetAllocator.armFits(l, 0, const {'Biceps'}, 'Biceps', 60, -100), isTrue);
      expect(SessionSetAllocator.armFits(l, 0, const {'Biceps'}, 'Biceps', 61, -100), isFalse);
    });
  });

  group('the swap never passes a bound the plan kept without it', () {
    test('time, the session cap and the weekly top, over a sweep (hold and budgeted fixtures)', () {
      var runs = 0;
      for (final minutes in [30, 45]) {
        for (final level in ['beginner', 'intermediate']) {
          for (var k = 0; k <= 10; k++) {
            for (final chest in [0, 2, 4, 6]) {
              for (final (f, days) in [
                () {
                  final f = lib();
                  return (f, week(f, custom: k));
                }(),
                () {
                  final f = libB(arm: const ['Biceps', 'Chest']);
                  return (f, weekB(f, custom: k, chestDay1: chest));
                }(),
              ]) {
                final off = runArm(f, days, on: false, minutes: minutes, level: level);
                final on = runArm(f, days, on: true, minutes: minutes, level: level);
                final ctx = f.ctx(days, minutes: minutes, level: level);
                final ledger = BudgetLedger(ctx, days.length);
                for (final b in [false, true]) {
                  List<List<PlannedExercise>> rows(List<PopulatedDay> out) =>
                      [for (final d in out) b ? d.exercisesB : d.exercisesA];
                  final lOff = SessionSetAllocator.plainLedgerForTest(rows(off), ctx, f.rows);
                  final lOn = SessionSetAllocator.plainLedgerForTest(rows(on), ctx, f.rows);
                  final why = '$minutes min, $level, custom $k, chest $chest, ${b ? 'B' : 'A'}';
                  for (var d = 0; d < days.length; d++) {
                    final bound = SessionBudget.allowanceSeconds.toDouble();
                    final overOn = -lOn.secondsLeft(d), overOff = -lOff.secondsLeft(d);
                    expect(overOn <= (overOff > bound ? overOff : bound) + 1e-6, isTrue, reason: '$why day $d time');
                    for (final g in const ['Chest', 'Back', 'Biceps', 'Glutes']) {
                      final on1 = lOn.session(d, g), off1 = lOff.session(d, g);
                      expect(on1 <= ledger.cap(g) || on1 <= off1, isTrue, reason: '$why day $d $g cap');
                    }
                  }
                  for (final g in const ['Chest', 'Back', 'Biceps', 'Glutes']) {
                    final on1 = lOn.week(g), off1 = lOff.week(g);
                    expect(on1 <= ledger.weeklyTop(g) || on1 <= off1, isTrue, reason: '$why $g top');
                  }
                }
                runs++;
              }
            }
          }
        }
      }
      expect(runs, 352);
    });
  });

  group('where it runs', () {
    test('60 and 90 minutes: never (the swap runs only in the allowance world)', () {
      for (final minutes in [60, 90]) {
        for (var k = 0; k <= 12; k++) {
          final f = lib();
          expect(shape(runArm(f, week(f, custom: k), on: true, minutes: minutes)),
              shape(runArm(f, week(f, custom: k), on: false, minutes: minutes)),
              reason: '$minutes minutes, custom $k');
        }
      }
    });

    test('only Biceps and Triceps: a Calves or Core arm row is never swapped in', () {
      for (final g in ['Calves', 'Core', 'Chest']) {
        final f = lib(arm: [g]);
        expect(shape(runArm(f, week(f), on: true, minutes: 45)), shape(runArm(f, week(f), on: false, minutes: 45)),
            reason: g);
        expect(shape(runArm(f, week(f), on: true)), shape(runArm(f, week(f), on: false)), reason: g);
      }
      final t = lib(arm: const ['Triceps']);
      expect(names(runArm(t, week(t), on: true)[0].exercisesA), contains('curlA'), reason: 'Triceps is swapped in');
    });

    test('the kill switch (balanced week off): the swap does not run, the plan is R', () {
      final f = lib();
      final on = runArm(f, week(f), on: true, balancedWeek: false);
      final off = runArm(f, week(f), on: false, balancedWeek: false);
      expect(shape(on), shape(off));
      expect(names(on[0].exercisesA), isNot(contains('curlA')));
    });

    test('a custom-filler sweep at 30 / 45 minutes: rows per day never change, and an added row is a minimum seat', () {
      var swapped = 0;
      for (final minutes in [30, 45]) {
        for (var k = 0; k <= 12; k++) {
          final f = lib();
          final off = runArm(f, week(f, custom: k), on: false, minutes: minutes);
          final on = runArm(f, week(f, custom: k), on: true, minutes: minutes);
          final seats = SessionSetAllocator.debugLastStats!['A']!.minimumSeats;
          for (var d = 0; d < on.length; d++) {
            expect(on[d].exercisesA.length, off[d].exercisesA.length, reason: '$minutes min, custom $k, day $d');
            expect(on[d].exercisesB.length, off[d].exercisesB.length, reason: '$minutes min, custom $k, day $d B');
            // S8 keeps a re-run only in the first run's world (round 1 B5), so the two never differ in the stamp.
            expect(on[d].allowance, off[d].allowance, reason: '$minutes min, custom $k, day $d stamp');
            final added = names(on[d].exercisesA).toSet().difference(names(off[d].exercisesA).toSet());
            for (final n in added) {
              expect(seats[d]?.map((m) => m.name), contains(n), reason: '$minutes min, custom $k, day $d: $n');
              swapped++;
            }
          }
        }
      }
      expect(swapped, 2, reason: 'measured: 30 min custom 3, 45 min custom 9');
    });
  });
}
