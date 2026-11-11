// Unit 1B-F, Task 1 (docs/plans/2026-11-10-generator-1bf-flip.md, Ruling 5; OI-489): the allocator's library timed
// rows ("holds") are spent first, like every row the budget does not size, but a hold ranked AFTER a slot that time
// alone refuses may give way to it, when that slot would give the day (and the week, in this variant) its FIRST
// credit for one of its groups. Guards: never the day's only credit for a group; never below the count floor; a hold
// crediting a major group gives way only to a slot that brings a major; a hold crediting a focus group likewise
// (guard (e), prototype H3); decided before anything is evicted; holds scanned last first. Ruling 5c: the empty-day
// guard's forced lead runs the same scan without the first-credit condition (it comes in either way), so the day ends
// inside its minutes when a hold may give way.
//
// Pure Dart over crafted fixtures. Every expected list was worked by hand from the plan's rule at 30 minutes:
// budget 1440 s, count floor 4; a compound lift ('M') at 2 sets costs 336 s, an isolation ('I') 256.8 s, a hold
// ('B') at 3 sets and 60 s rest 324 s, at 4 sets 444 s. Each test states the time arithmetic it rests on, and the
// costs are asserted once below so a change to the budget model reddens that test, not every fixture silently.
import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_set_allocator.dart';

import '../helpers/session_budget_fixtures.dart';

/// The crafted library: lifts, and timed holds.
Fx lib() {
  final f = Fx();
  f.row('chest', ['Chest']);
  f.row('chest2', ['Chest']);
  f.row('back', ['Lats']);
  f.row('hinge', ['Hamstrings', 'Glutes']);
  f.row('quad', ['Quads']);
  f.row('bi', ['Biceps'], type: 'isolation', reps: '10-15');
  f.row('tri', ['Triceps'], type: 'isolation', reps: '10-15');
  f.row('crunchpress', ['Chest', 'Core']);
  for (final h in ['plank', 'hollow', 'deadbug', 'birddog']) {
    f.row(h, ['Core'], type: 'isolation', reps: '30-60', logging: 'timed');
  }
  f.row('calfhold', ['Calves'], type: 'isolation', reps: '30-60', logging: 'timed');
  f.row('curlhold', ['Biceps'], type: 'isolation', reps: '30-60', logging: 'timed');
  f.row('wallsit', ['Quads'], type: 'isolation', reps: '30-60', logging: 'timed');
  f.row('sqhold', ['Quads'], type: 'isolation', reps: '30-60', logging: 'timed');
  f.row('dead', [], type: 'isolation', reps: '30-60', logging: 'timed');
  f.row('calfplank', ['Core', 'Calves'], type: 'isolation', reps: '30-60', logging: 'timed');
  f.row('chestbi', ['Chest', 'Biceps']);
  // Core, like the holds before them, so only the logging type keeps them from giving way.
  f.row('jog', ['Core'], type: 'cardio', reps: '30-60', logging: 'cardio');
  f.row('rowerg', ['Core'], type: 'cardio', reps: '30-60', logging: 'distance');
  for (var i = 1; i <= 4; i++) {
    f.row('c$i', ['Chest']);
  }
  return f;
}

/// A hold as the selector emits it: a library timed row at [sets] sets and 60 s rest.
PlannedExercise hold(Fx f, String name, {int sets = 3, String? customOrigin, String logging = 'timed'}) =>
    f.ex(name, sets: sets, logging: logging, rest: 60, customOrigin: customOrigin);

List<String> names(PopulatedDay d, {bool b = false}) =>
    [for (final e in (b ? d.exercisesB : d.exercisesA)) e.exerciseName];

void main() {
  test('fixture costs (30 minutes): budget 1440, floor 4, lift 336, isolation 256.8, hold 324 / 444', () {
    final f = lib();
    expect((30 - SessionBudget.warmCoolMinutes(30)) * 60, 1440);
    expect(SessionBudget.countFloor(30), 4);
    double s(String n, int sets, int rest) =>
        SessionBudget.exerciseSeconds(archetype: SessionBudget.archetypeOfRow(f.rows[n]!), sets: sets, restSeconds: rest);
    expect(s('chest', 2, 120), 336.0);
    expect(SessionBudget.restForArchetype(SessionBudget.archetypeOfRow(f.rows['chest']!)), 120);
    expect(s('bi', 2, 75), closeTo(256.8, 1e-9));
    expect(SessionBudget.restForArchetype(SessionBudget.archetypeOfRow(f.rows['bi']!)), 75);
    expect(s('plank', 3, 60), 324.0);
    expect(s('plank', 4, 60), 444.0);
    expect(s('plank', 2, 60), 204.0);
    expect(s('plank', 4, 30), 336.0);
    expect(s('plank', 6, 60), 684.0);
    expect((60 - SessionBudget.warmCoolMinutes(60)) * 60, 3000);
    expect((45 - SessionBudget.warmCoolMinutes(45)) * 60, 2220);
    expect(SessionBudget.countFloor(45), 5);
    expect((20 - SessionBudget.warmCoolMinutes(20)) * 60, 840);
    expect(SessionBudget.countFloor(20), 3);
  });

  group('the eviction', () {
    test('a starved rank-0 lead seats after the last hold ranked after it gives way', () {
      // Holds 3 x 444 = 1332, 108 s left: chest (336) does not fit. Evicting deadbug frees 444 (552 left), chest
      // seats (216 left); bi (256.8) then cannot evict (reach 4 - 1 < floor 4) and pass A2 forces it to the floor.
      // Without the rule: the empty-day guard forces chest past the clock and deadbug stays.
      final f = lib();
      final day = f.day('hypertrophy', [
        f.ex('chest'), f.ex('bi'), hold(f, 'plank', sets: 4), hold(f, 'hollow', sets: 4), hold(f, 'deadbug', sets: 4),
      ]);
      final out = f.run([day], minutes: 30);
      expect(setsOf(out[0]), [('chest', 2), ('bi', 2), ('plank', 4), ('hollow', 4)]);
    });

    test('a starved priority-1 hinge seats after a later hold gives way; the lead lift is untouched', () {
      // Holds 3 x 324 = 972, 468 s left: chest seats (132 left); hinge (336) is starved, brings Hamstrings and Glutes.
      // Evicting deadbug frees 324 (456 left), hinge seats.
      final f = lib();
      final day = f.day('hypertrophy', [
        f.ex('chest'), f.ex('hinge'), hold(f, 'plank'), hold(f, 'hollow'), hold(f, 'deadbug'),
      ]);
      final out = f.run([day], minutes: 30);
      expect(names(out[0]), ['chest', 'hinge', 'plank', 'hollow']);
    });

    test('a slot whose groups the day already credits never evicts', () {
      // As above, but the second slot is another Chest lift: no new group, so deadbug stays and chest2 goes.
      final f = lib();
      final day = f.day('hypertrophy', [
        f.ex('chest'), f.ex('chest2'), hold(f, 'plank'), hold(f, 'hollow'), hold(f, 'deadbug'),
      ]);
      final out = f.run([day], minutes: 30);
      expect(names(out[0]), ['chest', 'plank', 'hollow', 'deadbug']);
    });

    test('a hold crediting a major group never gives way to a minor-only slot', () {
      // bi (Biceps, minor) is starved after chest seats (132 left). Last first: sqhold and wallsit credit Quads (a
      // major) and are skipped; plank is the day's only Core credit and is skipped; nothing is evicted, bi goes.
      final f = lib();
      final day = f.day('hypertrophy', [
        f.ex('chest'), f.ex('bi'), hold(f, 'plank'), hold(f, 'wallsit'), hold(f, 'sqhold'),
      ]);
      final out = f.run([day], minutes: 30);
      expect(names(out[0]), ['chest', 'plank', 'wallsit', 'sqhold']);
    });

    test('a major-group hold DOES give way to a slot that brings a major', () {
      // hinge (Hamstrings, a major) starved after chest: sqhold (Quads) gives way, Quads still credited by wallsit.
      final f = lib();
      final day = f.day('hypertrophy', [
        f.ex('chest'), f.ex('hinge'), hold(f, 'plank'), hold(f, 'wallsit'), hold(f, 'sqhold'),
      ]);
      final out = f.run([day], minutes: 30);
      expect(names(out[0]), ['chest', 'hinge', 'plank', 'wallsit']);
    });

    test("a hold that is the day's only credit for a group never gives way; the scan moves to the next", () {
      // bi starved after chest. Last first: calfhold is the only Calves credit (skipped); hollow's Core is still
      // credited by plank, so hollow gives way (324 freed, 456 left), bi seats.
      final f = lib();
      final day = f.day('hypertrophy', [
        f.ex('chest'), f.ex('bi'), hold(f, 'plank'), hold(f, 'hollow'), hold(f, 'calfhold'),
      ]);
      final out = f.run([day], minutes: 30);
      expect(names(out[0]), ['chest', 'bi', 'plank', 'calfhold']);
    });

    test('a day holding the same hold twice loses one of them, not both', () {
      // Three planks (separate rows, one name). bi starved after chest; the last plank gives way (Core still
      // credited by the other two), the other two stay.
      final f = lib();
      final day = f.day('hypertrophy', [
        f.ex('chest'), f.ex('bi'), hold(f, 'plank'), hold(f, 'plank'), hold(f, 'plank'),
      ]);
      final out = f.run([day], minutes: 30);
      expect(names(out[0]), ['chest', 'bi', 'plank', 'plank']);
    });

    test('a hold ranked AFTER the slot gives way; the same hold ranked BEFORE it does not', () {
      // after: [chest, bi, plank, hollow, deadbug] -> deadbug goes (see above).
      // before: [chest, plank, hollow, deadbug, bi]: every hold has 1 budgeted slot ahead of it (before = 1), bi is
      // rank 1, so no hold is ranked after bi; nothing is evicted and bi goes.
      final f = lib();
      final after = f.run([
        f.day('hypertrophy', [
          f.ex('chest'), f.ex('bi'), hold(f, 'plank'), hold(f, 'hollow'), hold(f, 'deadbug'),
        ])
      ], minutes: 30);
      expect(names(after[0]), ['chest', 'bi', 'plank', 'hollow']);
      final before = f.run([
        f.day('hypertrophy', [
          f.ex('chest'), hold(f, 'plank'), hold(f, 'hollow'), hold(f, 'deadbug'), f.ex('bi'),
        ])
      ], minutes: 30);
      expect(names(before[0]), ['chest', 'plank', 'hollow', 'deadbug']);
    });

    test('two holds may go for one slot; none goes when even the holds it may take leave it short', () {
      // 20 minutes: budget 840, floor 3. Holds plank 444 + deadbug 444 + hollow (2 sets) 204 = 1092, -252 left.
      // Chest (336) starved; reach 5 lets two go (5 - 2 = 3). Last first: hollow (-48), deadbug (396 >= 336): both
      // go, chest seats (60 left); plank stays (the day's last Core credit). bi then cannot evict (reach 3 - 1 < 3)
      // and pass A2 forces it to the floor of 3.
      final f = lib();
      final out = f.run([
        f.day('hypertrophy', [
          f.ex('chest'), f.ex('bi'), hold(f, 'plank', sets: 4), hold(f, 'deadbug', sets: 4), hold(f, 'hollow', sets: 2),
        ])
      ], minutes: 20);
      expect(names(out[0]), ['chest', 'bi', 'plank']);

      // The same day with a Calves hold first: hollow may go (-48), but deadbug is then the last Core credit and
      // calfhold the only Calves credit, so 336 is never reached. Decided before anything is evicted: hollow stays,
      // and the empty-day guard forces chest past the clock.
      final out2 = f.run([
        f.day('hypertrophy', [
          f.ex('chest'), f.ex('bi'), hold(f, 'calfhold', sets: 4), hold(f, 'deadbug', sets: 4), hold(f, 'hollow', sets: 2),
        ])
      ], minutes: 20);
      expect(names(out2[0]), ['chest', 'calfhold', 'deadbug', 'hollow']);
    });
  });
  group('what never gives way', () {
    test('a custom hold (a repeat pin) and a non-library timed row never give way; a pinned LIBRARY hold does', () {
      // [chest, bi, plank 444, hollow 444, X 444]: 108 s left, chest starved. With X a library hold it would go
      // (last first); as a custom or an unknown row it is not a hold, so hollow goes instead (Core still credited by
      // plank), chest seats (216 left), bi is forced by pass A2. A pinned library row carries no custom origin
      // (`buildPinnedDays` stamps only customs), so it is an ordinary hold: see the first eviction test.
      final f = lib();
      final custom = f.run([
        f.day('hypertrophy', [
          f.ex('chest'), f.ex('bi'), hold(f, 'plank', sets: 4), hold(f, 'hollow', sets: 4),
          hold(f, 'deadbug', sets: 4, customOrigin: 'repeat_pin'),
        ])
      ], minutes: 30);
      expect(names(custom[0]), ['chest', 'bi', 'plank', 'deadbug']);
      final unknown = f.run([
        f.day('hypertrophy', [
          f.ex('chest'), f.ex('bi'), hold(f, 'plank', sets: 4), hold(f, 'hollow', sets: 4), hold(f, 'mystery', sets: 4),
        ])
      ], minutes: 30);
      expect(names(unknown[0]), ['chest', 'bi', 'plank', 'mystery']);
    });

    test('cardio and distance rows never give way (logging_type, not the row\'s muscles)', () {
      final f = lib();
      for (final z in ['jog', 'rowerg']) {
        final logging = z == 'jog' ? 'cardio' : 'distance';
        final out = f.run([
          f.day('hypertrophy', [
            f.ex('chest'), f.ex('bi'), hold(f, 'plank', sets: 4), hold(f, 'hollow', sets: 4),
            hold(f, z, sets: 4, logging: logging),
          ])
        ], minutes: 30);
        final got = names(out[0]);
        expect(got, contains(z), reason: '$logging row kept');
        expect(got, contains('chest'));
        expect(got, isNot(contains('hollow')), reason: 'the library hold before it gave way instead');
      }
    });

    test('a hold with no muscle groups gives way (it credits nothing the day could lose)', () {
      // plank is the only Core credit, calfhold the only Calves credit; only `dead` (no groups) may go.
      final f = lib();
      final out = f.run([
        f.day('hypertrophy', [
          f.ex('chest'), f.ex('bi'), hold(f, 'plank', sets: 4), hold(f, 'calfhold', sets: 4), hold(f, 'dead', sets: 4),
        ])
      ], minutes: 30);
      expect(names(out[0]), ['chest', 'bi', 'plank', 'calfhold']);
    });

    test("a hold that is the day's only Core credit gives way to a slot that itself credits Core", () {
      // crunchpress (Chest + Core) starved: 2 calfholds + plank = 1332, 108 left. Last first: plank is the only Core
      // hold, but the slot credits Core, so the day keeps Core: plank goes. Without the slot's own groups in the
      // check, the second calfhold would go instead.
      final f = lib();
      final out = f.run([
        f.day('hypertrophy', [
          f.ex('crunchpress'), f.ex('bi'), hold(f, 'calfhold', sets: 4), hold(f, 'calfhold', sets: 4),
          hold(f, 'plank', sets: 4),
        ])
      ], minutes: 30);
      expect(names(out[0]), ['crunchpress', 'bi', 'calfhold', 'calfhold']);
    });
  });

  group('preconditions', () {
    test('a slot the session cap refuses never evicts, even when time also refuses it', () {
      // 60 minutes, budget 3000, lose_fat advanced (8 a day, so the 3 holds leave 5 seats; Chest session cap 8):
      // holds 1332, 1668 left; c1-c4 seat at 2 sets (Chest 8 = the cap; 324 left); chestbi (336) is refused by time
      // AND by the Chest cap: no eviction, deadbug stays.
      final f = lib();
      final out = f.run([
        f.day('hypertrophy', [
          f.ex('c1'), f.ex('c2'), f.ex('c3'), f.ex('c4'), f.ex('chestbi'),
          hold(f, 'plank', sets: 4), hold(f, 'hollow', sets: 4), hold(f, 'deadbug', sets: 4),
        ])
      ], minutes: 60, goal: 'lose_fat', level: 'advanced');
      expect(names(out[0]), ['c1', 'c2', 'c3', 'c4', 'plank', 'hollow', 'deadbug']);
    });

    test('a slot the rank-0 reservation refuses never evicts', () {
      // Lighter phase, beginner build_muscle: Chest's weekly top is its band bottom, 10. Six days lead with chest,
      // so day 0's chest leaves 10 - 2 < 2 x 5 for the later five: reserved, not seated. Holds 4 x 324 = 1296, 144
      // left. Had pass A evicted for chest (sqhold: Quads stays credited by wallsit), bi (rank 1, 256.8) would then
      // fit and seat beside three holds. It does not: bi is starved and may evict nothing (a minor slot: sqhold and
      // wallsit credit Quads, plank and calfhold are their groups' only credit). The later five chests fill Chest's
      // top, so the empty-day guard forces bi, which Ruling 5c cannot help either (the same guards): all four holds
      // stay.
      final f = lib();
      final days = [
        f.day('hypertrophy', [
          f.ex('chest'), f.ex('bi'), hold(f, 'plank'), hold(f, 'wallsit'), hold(f, 'sqhold'), hold(f, 'calfhold'),
        ]),
        for (var i = 0; i < 5; i++) f.day('hypertrophy', [f.ex('chest')]),
      ];
      final out = f.run(days, minutes: 30, level: 'beginner', lighter: true);
      expect(names(out[0]), ['bi', 'plank', 'wallsit', 'sqhold', 'calfhold']);
      expect(SessionSetAllocator.debugLastStats!['A']!.forcedDays, contains(0));
    });

    test('a slot the count band refuses never evicts', () {
      // 60 minutes, intermediate (6 a day): holds 684 + 684 + 444 = 1812, 1188 left, and they take 3 of the 6, so
      // the day seats 3 slots: chest, back, hinge (1008, 180 left). quad is refused by the COUNT (and would be by
      // time): no eviction, the third hold stays.
      final f = lib();
      final out = f.run([
        f.day('hypertrophy', [
          f.ex('chest'), f.ex('back'), f.ex('hinge'), f.ex('quad'),
          hold(f, 'plank', sets: 6), hold(f, 'hollow', sets: 6), hold(f, 'deadbug', sets: 4),
        ])
      ], minutes: 60);
      expect(names(out[0]), ['chest', 'back', 'hinge', 'plank', 'hollow', 'deadbug']);
    });

    test('an eviction frees the hold\'s count seat, so a later slot can take it', () {
      // Beginner (5 a day), 30 minutes: holds 3 x 324 = 972 take 3 seats (2 left), 468 s left. chest seats (132
      // left); back is starved: deadbug goes (456 left, seat 3 opens), back seats (120 left); quad is starved: hollow
      // goes (Core still on plank; 444 left, seat 4 opens), quad seats (108 left); bi cannot evict (plank is the
      // last Core credit). Without the freed seats, quad would be refused by the count and hollow would stay.
      final f = lib();
      final out = f.run([
        f.day('hypertrophy', [
          f.ex('chest'), f.ex('back'), f.ex('quad'), f.ex('bi'),
          hold(f, 'plank'), hold(f, 'hollow'), hold(f, 'deadbug'),
        ])
      ], minutes: 30, level: 'beginner');
      expect(names(out[0]), ['chest', 'back', 'quad', 'plank']);
    });

    test('a day of 3 slots and 1 hold never evicts (reach 4 = the floor) and keeps its count verdict', () {
      // plank 444 + chest + back (672) = 1116, 324 left; quad (336) starved; reach 4 - 1 < 4: no eviction. Pass A2
      // forces quad (-12 s, inside the 300 s bound): 4 rows, nothing below the floor.
      final f = lib();
      final out = f.run([
        f.day('hypertrophy', [f.ex('chest'), f.ex('back'), f.ex('quad'), hold(f, 'plank', sets: 4)]),
      ], minutes: 30);
      expect(names(out[0]), ['chest', 'back', 'quad', 'plank']);
      final st = SessionSetAllocator.debugLastStats!['A']!;
      expect(st.selectorThin, isEmpty);
      expect(st.belowCount, isEmpty);
      expect(st.countForced[0]!.map((e) => e.name), ['quad']);
    });

    test('the fit boundary: a slot that fits EXACTLY after one hold goes seats, with no second eviction', () {
      // plank 444 + hollow 324 + birddog (4 sets, 30 s) 336 + deadbug (2 sets) 204 = 1308, 132 left; chest (336)
      // starved; deadbug goes: 132 + 204 = 336 = need, so chest seats with 0 left. If equality did not fit, the scan
      // would try birddog next (reach 5 - 2 < 4 stops it), evict nothing, and the guard would force chest.
      final f = lib();
      final out = f.run([
        f.day('hypertrophy', [
          f.ex('chest'), hold(f, 'plank', sets: 4), hold(f, 'hollow'), f.ex('birddog', sets: 4, logging: 'timed', rest: 30),
          hold(f, 'deadbug', sets: 2),
        ])
      ], minutes: 30);
      expect(names(out[0]), ['chest', 'plank', 'hollow', 'birddog']);
      expect(SessionSetAllocator.debugLastStats!['A']!.forcedDays, isEmpty);
    });
  });

  group('the week', () {
    test('an earlier day that already seated the group at this rank blocks the eviction; a later rank does not', () {
      // Day 1: [chest, bi, plank, hollow, deadbug] at 3 sets: chest seats (132 left), bi starved at rank 1.
      // Day 0 = [back, bi]: its bi seats at rank 1 BEFORE day 1's (pass A runs rank by rank, day by day), so
      // Biceps is not new: no eviction. Day 0 = [back, tri, bi]: its bi is rank 2, so at rank 1 the week has no
      // Biceps yet: deadbug goes and day 1's bi seats.
      final f = lib();
      List<PlannedExercise> day1() =>
          [f.ex('chest'), f.ex('bi'), hold(f, 'plank'), hold(f, 'hollow'), hold(f, 'deadbug')];
      final early = f.run([f.day('hypertrophy', [f.ex('back'), f.ex('bi')]), f.day('hypertrophy', day1())],
          minutes: 30);
      expect(names(early[1]), ['chest', 'plank', 'hollow', 'deadbug']);
      final late = f.run([f.day('hypertrophy', [f.ex('back'), f.ex('tri'), f.ex('bi')]), f.day('hypertrophy', day1())],
          minutes: 30);
      expect(names(late[1]), ['chest', 'bi', 'plank', 'hollow']);
    });

    test('a kept hold on ANOTHER day that credits the group blocks the eviction', () {
      // Day 1: [chest, quad, plank, hollow, deadbug]: chest seats (132 left), quad (Quads, a major) starved.
      // Day 0 holds wallsit (Quads): the week already credits Quads, no eviction. Day 0 holds plank instead: deadbug
      // goes and quad seats.
      final f = lib();
      List<PlannedExercise> day1() =>
          [f.ex('chest'), f.ex('quad'), hold(f, 'plank'), hold(f, 'hollow'), hold(f, 'deadbug')];
      final blocked = f.run([f.day('hypertrophy', [f.ex('back'), hold(f, 'wallsit')]), f.day('hypertrophy', day1())],
          minutes: 30);
      expect(names(blocked[1]), ['chest', 'plank', 'hollow', 'deadbug']);
      final open = f.run([f.day('hypertrophy', [f.ex('back'), hold(f, 'plank')]), f.day('hypertrophy', day1())],
          minutes: 30);
      expect(names(open[1]), ['chest', 'quad', 'plank', 'hollow']);
    });

    test('a copied B day mirrors A\'s evictions by position, even with a repeated hold name', () {
      // A and B hold the same names, so B is copied from A. A evicts the LAST of three planks; B must lose that one
      // plank, not every plank.
      final f = lib();
      List<PlannedExercise> list() =>
          [f.ex('chest'), f.ex('bi'), hold(f, 'plank'), hold(f, 'plank'), hold(f, 'plank')];
      final out = f.run([f.day('hypertrophy', list(), b: list())], minutes: 30, is6Day: false);
      expect(names(out[0]), ['chest', 'bi', 'plank', 'plank']);
      expect(names(out[0], b: true), names(out[0]));
      expect(setsOf(out[0], b: true), setsOf(out[0]));
    });

    test('a day with no starved slot is left exactly as the selector built it', () {
      final f = lib();
      final out = f.run([
        f.day('hypertrophy', [f.ex('chest'), f.ex('bi'), hold(f, 'plank', sets: 2)]),
      ], minutes: 60);
      expect(names(out[0]), ['chest', 'bi', 'plank']);
      expect(out[0].exercisesA.last.sets, 2);
    });
  });

  group('the empty-day guard (Ruling 5c)', () {
    test("a forced lead whose group a hold already credits takes a later hold's time, inside the clock", () {
      // Holds 4 x 324 = 1296, 144 left; quad (336) starved. Its Quads are wallsit's already, so pass A evicts nothing
      // (no first credit) and the guard forces quad. Ruling 5c: last first, wallsit (Quads, still credited by quad
      // itself) gives way: 468 left, quad seats at 2 sets inside the clock. Without it: all four holds and quad, 1632 s.
      // A copied B day mirrors the eviction.
      final f = lib();
      List<PlannedExercise> list() =>
          [f.ex('quad'), hold(f, 'plank'), hold(f, 'hollow'), hold(f, 'deadbug'), hold(f, 'wallsit')];
      final out = f.run([f.day('hypertrophy', list(), b: list())], minutes: 30, is6Day: false);
      expect(names(out[0]), ['quad', 'plank', 'hollow', 'deadbug']);
      expect(names(out[0], b: true), names(out[0]));
      expect(SessionSetAllocator.debugLastStats!['A']!.forcedDays, contains(0));
    });

    test("never the day's only credit for a group: the scan moves to the next hold", () {
      // As above with calfhold last: the only Calves credit, skipped; wallsit gives way.
      final f = lib();
      final out = f.run([
        f.day('hypertrophy', [f.ex('quad'), hold(f, 'plank'), hold(f, 'hollow'), hold(f, 'wallsit'), hold(f, 'calfhold')]),
      ], minutes: 30);
      expect(names(out[0]), ['quad', 'plank', 'hollow', 'calfhold']);
    });

    test('a major hold never gives way to a forced minor lead; a minor hold does', () {
      // bi (Biceps, 256.8) starved behind 4 x 324; its Biceps are curlhold's, so the guard forces it. Last first:
      // sqhold and wallsit credit Quads (a major) and bi credits no major: skipped; plank is the only Core credit;
      // curlhold (Biceps, credited by bi) gives way.
      final f = lib();
      final out = f.run([
        f.day('hypertrophy', [f.ex('bi'), hold(f, 'curlhold'), hold(f, 'plank'), hold(f, 'wallsit'), hold(f, 'sqhold')]),
      ], minutes: 30);
      expect(names(out[0]), ['bi', 'plank', 'wallsit', 'sqhold']);
    });

    test('a hold ranked BEFORE the forced lead never gives way', () {
      // wallsit is ahead of quad; plank, calfhold and curlhold after it are each their group's only credit. Nothing may
      // go, so the guard forces quad past the clock (the residue the count floor and these guards leave).
      final f = lib();
      final out = f.run([
        f.day('hypertrophy', [hold(f, 'wallsit'), f.ex('quad'), hold(f, 'plank'), hold(f, 'calfhold'), hold(f, 'curlhold')]),
      ], minutes: 30);
      expect(names(out[0]), ['wallsit', 'quad', 'plank', 'calfhold', 'curlhold']);
    });

    test('never below the count floor: a lead beside three holds is forced past the clock', () {
      // Holds 3 x 444 = 1332, 108 left; reach 4 - 1 < the floor 4: nothing may go.
      final f = lib();
      final out = f.run([
        f.day('hypertrophy', [
          f.ex('quad'), hold(f, 'plank', sets: 4), hold(f, 'hollow', sets: 4), hold(f, 'wallsit', sets: 4),
        ]),
      ], minutes: 30);
      expect(names(out[0]), ['quad', 'plank', 'hollow', 'wallsit']);
    });

    test('all or nothing: when the holds that may go cannot free enough, none goes and the lead is forced', () {
      // curlhold (ahead of bi, so never a candidate) already credits Biceps: pass A leaves bi to the guard. Holds
      // 204 + 204 + 204 + 444 + 444 = 1500, -60 left; bi needs 256.8. Last first: wallsit credits Quads (a major) and
      // bi brings none: skipped; calfhold is the only Calves credit; hollow (Core, still on plank) may go, 144 freed is
      // short; plank is then the only Core credit. Nothing is evicted: bi is forced past the clock, hollow stays.
      final f = lib();
      final out = f.run([
        f.day('hypertrophy', [
          hold(f, 'curlhold', sets: 2), f.ex('bi'), hold(f, 'plank', sets: 2), hold(f, 'hollow', sets: 2),
          hold(f, 'calfhold', sets: 4), hold(f, 'wallsit', sets: 4),
        ]),
      ], minutes: 30);
      expect(names(out[0]), ['curlhold', 'bi', 'plank', 'hollow', 'calfhold', 'wallsit']);
    });

    test('focus: a Core-focus hold never gives way to a forced minor lead; the minor hold does', () {
      // bi starved behind 4 x 324 (144 left); curlhold credits Biceps, so the guard forces bi. No focus: deadbug (Core,
      // still on plank and hollow) gives way. Core focus: deadbug, hollow and plank are skipped (bi brings no major),
      // curlhold (Biceps, credited by bi itself) gives way.
      final f = lib();
      List<PlannedExercise> list() =>
          [f.ex('bi'), hold(f, 'curlhold'), hold(f, 'plank'), hold(f, 'hollow'), hold(f, 'deadbug')];
      final plain = f.run([f.day('hypertrophy', list())], minutes: 30);
      expect(names(plain[0]), ['bi', 'curlhold', 'plank', 'hollow'], reason: 'the control: no focus, deadbug goes');
      final focus = f.run([f.day('hypertrophy', list())], minutes: 30, focus: {'Core'});
      expect(names(focus[0]), ['bi', 'plank', 'hollow', 'deadbug']);
    });

    test('a lead forced by the weekly top (no slot has room) evicts like a time-forced one', () {
      // general_fitness beginner: Quads weekly top 10. Days 1-5 each seat quad at 2 sets in pass A (week 10), so day
      // 6's quad has no room and the guard takes it as the cap-forced lead. Holds 4 x 324 (144 left): birddog (Core,
      // still on the others) gives way and quad lands inside the clock.
      final f = lib();
      final out = f.run([
        for (var i = 0; i < 5; i++) f.day('hypertrophy', [f.ex('quad')]),
        f.day('hypertrophy', [f.ex('quad'), hold(f, 'plank'), hold(f, 'hollow'), hold(f, 'deadbug'), hold(f, 'birddog')]),
      ], minutes: 30, goal: 'general_fitness', level: 'beginner');
      expect(names(out[5]), ['quad', 'plank', 'hollow', 'deadbug']);
      expect(SessionSetAllocator.debugLastStats!['A']!.capForcedFirst, 1);
    });
  });

  group('focus (guard (e))', () {
    test('a Core-focus hold does NOT give way to a minor-only slot', () {
      final f = lib();
      List<PlannedExercise> list() =>
          [f.ex('chest'), f.ex('bi'), hold(f, 'plank'), hold(f, 'hollow'), hold(f, 'deadbug')];
      final focus = f.run([f.day('hypertrophy', list())], minutes: 30, focus: {'Core'});
      expect(names(focus[0]), ['chest', 'plank', 'hollow', 'deadbug']);
      final plain = f.run([f.day('hypertrophy', list())], minutes: 30);
      expect(names(plain[0]), ['chest', 'bi', 'plank', 'hollow'], reason: 'the control: no focus, deadbug goes');
    });

    test('a Core-focus hold DOES give way to a slot that brings the week a major group', () {
      final f = lib();
      final out = f.run([
        f.day('hypertrophy', [f.ex('chest'), f.ex('hinge'), hold(f, 'plank'), hold(f, 'hollow'), hold(f, 'deadbug')]),
      ], minutes: 30, focus: {'Core'});
      expect(names(out[0]), ['chest', 'hinge', 'plank', 'hollow']);
    });

    test('a rank-0 lead on the first day evicts a later focus hold (it brings the week a major)', () {
      final f = lib();
      final out = f.run([
        f.day('hypertrophy', [
          f.ex('chest'), f.ex('bi'), hold(f, 'plank', sets: 4), hold(f, 'hollow', sets: 4), hold(f, 'deadbug', sets: 4),
        ]),
      ], minutes: 30, focus: {'Core'});
      expect(names(out[0]), ['chest', 'bi', 'plank', 'hollow']);
    });

    test('a focus hold ranked LAST is skipped and the non-focus hold before it gives way to a minor slot', () {
      // 45 minutes: budget 2220, floor 5; advanced (8 a day, so the 4 holds leave 4 seats). Holds plank + calfhold +
      // calfhold + deadbug = 4 x 324 = 1296, 924 left; chest (588 left) and back (252 left) seat; bi (256.8)
      // starved, reach 7. Last first: deadbug (Core, focus) is skipped, the second calfhold goes (Calves still on
      // the first): bi seats.
      final f = lib();
      final out = f.run([
        f.day('hypertrophy', [
          f.ex('chest'), f.ex('back'), f.ex('bi'),
          hold(f, 'plank'), hold(f, 'calfhold'), hold(f, 'calfhold'), hold(f, 'deadbug'),
        ]),
      ], minutes: 45, level: 'advanced', focus: {'Core'});
      expect(names(out[0]), ['chest', 'back', 'bi', 'plank', 'calfhold', 'deadbug']);
    });

    test('a MAJOR hold ranked last is skipped and the minor hold before it gives way to a minor slot', () {
      final f = lib();
      final out = f.run([
        f.day('hypertrophy', [
          f.ex('chest'), f.ex('back'), f.ex('bi'),
          hold(f, 'plank'), hold(f, 'calfhold'), hold(f, 'calfhold'), hold(f, 'wallsit'),
        ]),
      ], minutes: 45, level: 'advanced');
      expect(names(out[0]), ['chest', 'back', 'bi', 'plank', 'calfhold', 'wallsit']);
    });

    test("the focus guard reads the HOLD's groups, any of them, and the slot's NEW credit", () {
      // chest seats (132 left); chestbi starved: its Chest is seated, so its new credit is Biceps alone (minor).
      // Every hold credits Core (focus): none gives way.
      final f = lib();
      final out = f.run([
        f.day('hypertrophy', [
          f.ex('chest'), f.ex('chestbi'), hold(f, 'plank'), hold(f, 'hollow'), hold(f, 'deadbug'),
        ]),
      ], minutes: 30, focus: {'Core'});
      expect(names(out[0]), ['chest', 'plank', 'hollow', 'deadbug']);
      // calfplank credits Core (focus) AND Calves: skipped as a focus hold; calfhold (Calves still on calfplank) goes.
      final out2 = f.run([
        f.day('hypertrophy', [
          f.ex('chest'), f.ex('bi'), hold(f, 'plank'), hold(f, 'calfhold'), hold(f, 'calfplank'),
        ]),
      ], minutes: 30, focus: {'Core'});
      expect(names(out2[0]), ['chest', 'bi', 'plank', 'calfplank']);
    });
  });
}
