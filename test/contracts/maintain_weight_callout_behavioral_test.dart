// OI-518: the Weekly Report weight card treated every goal that is not Cut as "wants to
// gain": a Maintain user drifting down 1 kg inside the 3 kg band got "Adjust your
// nutrition to stay on track" and one drifting up got a date to a hold-weight target.
//
// BEHAVIOURAL: the REAL `WeightProjectionCallout` is pumped from explicit weigh-ins and
// the rendered text, icon and colour are read back. No Hive, no provider scope.
// Source pins at the bottom are presence only (the call site in the screen).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/onboarding/target_weight_check.dart';
import 'package:icanbefitter/features/profile/widgets/weight_projection_callout.dart';

const _dot = '·';

/// Two weigh-ins 14 days apart (weeksDiff 2.0).
List<Map<String, dynamic>> _entries(double first, double last) => [
      {'date': '2026-11-04', 'weight_kg': first},
      {'date': '2026-11-18', 'weight_kg': last},
    ];

class _Fixture {
  const _Fixture(this.goal, this.first, this.last, this.target, {this.text})
      : fresh = false;

  /// A Maintain fixture on the FRESH clock: the last weigh-in (2026-11-18) is one day
  /// old, so no "as of" suffix is drawn and `text` is the bare line.
  const _Fixture.maintain(this.first, this.last, this.target, {this.text})
      : goal = 'general_fitness',
        fresh = true;
  final String goal;
  final double first;
  final double last;
  final double target;

  /// The exact text under the callout; null = nothing is drawn.
  final String? text;

  /// Pump on [_freshNow] (the weigh-ins are one day old) instead of [_now].
  final bool fresh;
}

// Far from any wall clock the suite could run on: an eta row that ignores `now` goes red today.
final _now = DateTime(2031, 3, 5);

/// The day after the last weigh-in of [_entries], in IST (11:30 on 2026-11-19): a Maintain
/// line pumped on it is fresh, so the suffix cannot appear by accident.
final _freshNow = DateTime.utc(2026, 11, 19, 6);

String _key(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Two weigh-ins 14 days apart ending on [lastKey] (a valid `YYYY-MM-DD`).
List<Map<String, dynamic>> _entriesEndingOn(String lastKey, double first, double last) => [
      {
        'date': _key(parseDateKeyUtc(lastKey)!.subtract(const Duration(days: 14))),
        'weight_kg': first,
      },
      {'date': lastKey, 'weight_kg': last},
    ];

Future<void> _pump(WidgetTester tester, _Fixture f) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: WeightProjectionCallout(
        entries: _entries(f.first, f.last),
        targetWeight: f.target,
        goal: f.goal,
        now: f.fresh ? _freshNow : _now,
      ),
    ),
  ));
}

Finder get _texts => find.descendant(
    of: find.byType(WeightProjectionCallout), matching: find.byType(Text));

Color? _color(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

String _src(String path) => File(path)
    .readAsLinesSync()
    .map((l) => l.replaceFirst(RegExp(r'//.*$'), ''))
    .join('\n');

void main() {
  testWidgets('typography warmup: GoogleFonts caches before any other pump',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Text('warmup', style: AppTypography.bodySm),
    ));
  });

  group('one fixture per ProjectionCalloutKind, drawn through the real widget', () {
    final rows = <ProjectionCalloutKind, _Fixture>{
      // Cut falling toward a target ABOVE the last weigh-in: the OI-191 none.
      ProjectionCalloutKind.none: const _Fixture('lose_fat', 79, 77, 78),
      ProjectionCalloutKind.adjust:
          const _Fixture('lose_fat', 77, 78, 70, text: 'Adjust your diet to stay on track'),
      ProjectionCalloutKind.reached:
          const _Fixture('lose_fat', 79, 78, 78, text: 'You\'ve reached your goal weight!'),
      // 2 kg per 2 weeks, 8 kg to go: 8 weeks from the injected 2031-03-05 = 2031-04-30.
      ProjectionCalloutKind.eta: const _Fixture('lose_fat', 80, 78, 70,
          text: 'At current rate, you\'ll reach 70kg in ~8 weeks (around Apr 2031)'),
      ProjectionCalloutKind.onTarget: const _Fixture.maintain(76, 74, 75,
          text: 'Holding the line $_dot 1.0 kg from your 75 kg target'),
      ProjectionCalloutKind.offTarget: const _Fixture.maintain(76, 79, 75,
          text:
              '4.0 kg above your 75 kg target $_dot adjust your nutrition to hold the line'),
    };

    test('the table covers every kind, so a new kind needs a row', () {
      expect(rows.keys.toSet(), ProjectionCalloutKind.values.toSet());
    });

    for (final e in rows.entries) {
      testWidgets('${e.key.name}: the fixture IS that kind and draws its text',
          (tester) async {
        final f = e.value;
        // The fixture is tied to its key: pasted under the wrong kind it fails here.
        expect(
          projectionCalloutKind(
              goal: f.goal, firstW: f.first, lastW: f.last, weeksDiff: 2, target: f.target),
          e.key,
        );
        await _pump(tester, f);
        if (f.text == null) {
          expect(_texts, findsNothing);
        } else {
          expect(find.text(f.text!), findsOneWidget);
          expect(_texts, findsOneWidget);
        }
      });
    }
  });

  group('Maintain', () {
    testWidgets('falling inside the band is the hold line, never "Adjust"',
        (tester) async {
      await _pump(tester, const _Fixture.maintain(76, 74, 75));
      expect(find.textContaining('Adjust your'), findsNothing);
      expect(find.text('Holding the line $_dot 1.0 kg from your 75 kg target'),
          findsOneWidget);
    });

    testWidgets('rising inside the band is the hold line, never a date',
        (tester) async {
      await _pump(tester, const _Fixture.maintain(74, 76, 75));
      expect(find.textContaining('At current rate'), findsNothing);
      expect(find.textContaining('weeks'), findsNothing);
      expect(find.text('Holding the line $_dot 1.0 kg from your 75 kg target'),
          findsOneWidget);
    });

    testWidgets('a flat series inside the band draws the hold line (no division)',
        (tester) async {
      await _pump(tester, const _Fixture.maintain(75.4, 75.4, 75));
      expect(find.text('Holding the line $_dot 0.4 kg from your 75 kg target'),
          findsOneWidget);
    });

    testWidgets('right on the target says so', (tester) async {
      await _pump(tester, const _Fixture.maintain(75, 75, 75));
      expect(find.text('Holding the line $_dot right on your 75 kg target'),
          findsOneWidget);
    });

    testWidgets('beyond the band below the target says below', (tester) async {
      await _pump(tester, const _Fixture.maintain(74, 71.6, 75));
      expect(
          find.text(
              '3.4 kg below your 75 kg target $_dot adjust your nutrition to hold the line'),
          findsOneWidget);
    });

    testWidgets('the band edge: 3.0 is on target, 3.1 is off target', (tester) async {
      await _pump(tester, const _Fixture.maintain(76, 78.3, 75.3));
      expect(find.textContaining('Holding the line $_dot 3.0 kg'), findsOneWidget);
      await _pump(tester, const _Fixture.maintain(76, 78.4, 75.3));
      expect(find.textContaining('3.1 kg above'), findsOneWidget);
    });

    testWidgets(
        'the gap is the rule\'s own tenths: 66.9 against 70.0 reads 3.1 below, '
        'not a truncated 3.0', (tester) async {
      // (70.0 - 66.9) * 10 = 30.999999999999943: round() 31, truncate() 30.
      await _pump(tester, const _Fixture.maintain(66, 66.9, 70.0));
      expect(
          find.text(
              '3.1 kg below your 70 kg target $_dot adjust your nutrition to hold the line'),
          findsOneWidget);
    });

    testWidgets('a fractional target keeps its decimal, a whole one drops it',
        (tester) async {
      await _pump(tester, const _Fixture.maintain(75, 75.8, 74.8));
      expect(find.textContaining('your 74.8 kg target'), findsOneWidget);
      await _pump(tester, const _Fixture.maintain(75, 75.8, 75.0));
      expect(find.textContaining('your 75 kg target'), findsOneWidget);
    });

    testWidgets('on target: green check and the ok colour; off target: warning and warn',
        (tester) async {
      await _pump(tester, const _Fixture.maintain(76, 74, 75));
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber), findsNothing);
      expect(_color(tester, 'Holding the line $_dot 1.0 kg from your 75 kg target'),
          AppColors.ok);

      await _pump(tester, const _Fixture.maintain(76, 79, 75));
      expect(find.byIcon(Icons.warning_amber), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(
          _color(tester,
              '4.0 kg above your 75 kg target $_dot adjust your nutrition to hold the line'),
          AppColors.warn);
    });

    testWidgets('both Maintain lines wrap instead of overflowing a narrow card',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // offTarget (the longer line) and onTarget (its own Expanded).
      await _pump(tester, const _Fixture.maintain(76, 79, 75));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('adjust your nutrition to hold the line'),
          findsOneWidget);
      await _pump(tester, const _Fixture.maintain(76, 74, 75));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Holding the line'), findsOneWidget);
    });
  });

  group('Cut and Build are unchanged', () {
    testWidgets('a Build moving the wrong way says nutrition', (tester) async {
      await _pump(tester, const _Fixture('build_muscle', 75, 74, 80));
      expect(find.text('Adjust your nutrition to stay on track'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber), findsOneWidget);
    });

    testWidgets('a Cut at its target is reached, with the check icon', (tester) async {
      await _pump(tester, const _Fixture('lose_fat', 79, 78, 78));
      expect(find.text('You\'ve reached your goal weight!'), findsOneWidget);
      expect(_color(tester, 'You\'ve reached your goal weight!'), AppColors.ok);
    });

    testWidgets('a flat series with the target exactly 0.5 kg away draws nothing '
        'and does not throw (it used to take Infinity.ceil())', (tester) async {
      await _pump(tester, const _Fixture('lose_fat', 80.0, 80.0, 79.5));
      expect(tester.takeException(), isNull);
      expect(_texts, findsNothing);
      await _pump(tester, const _Fixture('build_muscle', 80.0, 80.0, 80.5));
      expect(tester.takeException(), isNull);
      expect(_texts, findsNothing);
    });
  });

  group('empty shapes', () {
    testWidgets('fewer than two weigh-ins draws nothing', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WeightProjectionCallout(
            entries: [
              {'date': '2026-11-18', 'weight_kg': 75.0}
            ],
            targetWeight: 75,
            goal: 'general_fitness',
          ),
        ),
      ));
      expect(_texts, findsNothing);
    });

    testWidgets('an empty list draws nothing and does not throw', (tester) async {
      // Without the length guard `entries.first` throws on an empty list.
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: WeightProjectionCallout(
            entries: [],
            targetWeight: 75,
            goal: 'general_fitness',
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(_texts, findsNothing);
    });

    testWidgets('an unreadable LAST date draws nothing', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WeightProjectionCallout(
            entries: [
              {'date': '2026-11-04', 'weight_kg': 75.0},
              {'date': 'not-a-date', 'weight_kg': 75.0},
            ],
            targetWeight: 75,
            goal: 'general_fitness',
          ),
        ),
      ));
      expect(_texts, findsNothing);
    });

    testWidgets('an unreadable date draws nothing', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WeightProjectionCallout(
            entries: [
              {'date': 'not-a-date', 'weight_kg': 75.0},
              {'date': '2026-11-18', 'weight_kg': 75.0},
            ],
            targetWeight: 75,
            goal: 'general_fitness',
          ),
        ),
      ));
      expect(_texts, findsNothing);
    });

    testWidgets(
        'two weigh-ins a day apart: Maintain draws its line (no history gate), '
        'Cut and Build still draw nothing', (tester) async {
      Future<void> pumpGoal(String goal, double target) =>
          tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: WeightProjectionCallout(
                entries: [
                  {'date': '2026-11-17', 'weight_kg': 75.0},
                  {'date': '2026-11-18', 'weight_kg': 75.0},
                ],
                targetWeight: target,
                goal: goal,
                now: _freshNow,
              ),
            ),
          ));
      await pumpGoal('general_fitness', 75);
      expect(find.text('Holding the line $_dot right on your 75 kg target'),
          findsOneWidget);
      await pumpGoal('lose_fat', 70);
      expect(_texts, findsNothing);
      await pumpGoal('build_muscle', 80);
      expect(_texts, findsNothing);
    });
  });

  group('Maintain: "as of <date>" when the last weigh-in is old', () {
    final onLine = 'Holding the line $_dot 1.0 kg from your 75 kg target';
    final offLine =
        '4.0 kg above your 75 kg target $_dot adjust your nutrition to hold the line';

    DateTime at(int y, int m, int d, [int h = 6, int min = 0]) =>
        DateTime.utc(y, m, d, h, min);

    Future<void> pumpMaintain(WidgetTester tester, String lastKey, DateTime now,
        {double first = 76, double last = 74, String goal = 'general_fitness',
        double target = 75, List<Map<String, dynamic>>? entries}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WeightProjectionCallout(
            entries: entries ?? _entriesEndingOn(lastKey, first, last),
            targetWeight: target,
            goal: goal,
            now: now,
          ),
        ),
      ));
    }

    for (final (label, last, line) in [
      ('onTarget', 74.0, 'Holding the line $_dot 1.0 kg from your 75 kg target'),
      ('offTarget', 79.0,
          '4.0 kg above your 75 kg target $_dot adjust your nutrition to hold the line'),
    ]) {
      testWidgets('$label: 7 days old draws the bare line, 8 days adds the suffix',
          (tester) async {
        await pumpMaintain(tester, '2026-11-19', at(2026, 11, 26), last: last);
        expect(find.text(line), findsOneWidget);
        await pumpMaintain(tester, '2026-11-18', at(2026, 11, 26), last: last);
        expect(find.text('$line $_dot as of 18 Nov'), findsOneWidget);
        expect(find.text(line), findsNothing);
      });
    }

    testWidgets('the suffix is part of the SAME single line (one Text)', (tester) async {
      await pumpMaintain(tester, '2026-11-03', at(2026, 11, 26));
      expect(_texts, findsOneWidget);
      expect(find.text('$onLine $_dot as of 3 Nov'), findsOneWidget);
    });

    testWidgets('a last weigh-in in another year prints the year', (tester) async {
      // IST is already 2027-01-01 00:30 here.
      await pumpMaintain(tester, '2026-12-23', at(2026, 12, 31, 19));
      expect(find.text('$onLine $_dot as of 23 Dec 2026'), findsOneWidget);
    });

    testWidgets('today is the IST day: 19:00 UTC is already tomorrow in IST',
        (tester) async {
      // UTC date 2026-11-25 would make the age 7 (no suffix); IST 2026-11-26 makes it 8.
      await pumpMaintain(tester, '2026-11-18', at(2026, 11, 25, 19));
      expect(find.text('$onLine $_dot as of 18 Nov'), findsOneWidget);
    });

    testWidgets('the IST conversion happens ONCE (no double 5:30 shift)', (tester) async {
      // 14:00 UTC = 19:30 IST on the 25th (age 7, bare). A second shift reads 01:00 on
      // the 26th (age 8) and would print the suffix.
      await pumpMaintain(tester, '2026-11-18', at(2026, 11, 25, 14));
      expect(find.text(onLine), findsOneWidget);
    });

    testWidgets('IST midnight is the flip: 23:59 IST bare, 00:01 IST suffix',
        (tester) async {
      await pumpMaintain(tester, '2026-11-18', at(2026, 11, 25, 18, 29));
      expect(find.text(onLine), findsOneWidget);
      await pumpMaintain(tester, '2026-11-18', at(2026, 11, 25, 18, 31));
      expect(find.text('$onLine $_dot as of 18 Nov'), findsOneWidget);
      // exactly IST midnight is already the next day
      await pumpMaintain(tester, '2026-11-18', at(2026, 11, 25, 18, 30));
      expect(find.text('$onLine $_dot as of 18 Nov'), findsOneWidget);
    });

    testWidgets('three weigh-ins: the LAST decides the gap, the date and the suffix',
        (tester) async {
      // The middle weigh-in sits 1 kg from the last and 8 days before it; only the last
      // (2026-11-18, 74 kg) may feed the words and the "as of" date.
      await pumpMaintain(tester, '', at(2026, 11, 26), entries: [
        {'date': '2026-11-04', 'weight_kg': 76.0},
        {'date': '2026-11-10', 'weight_kg': 75.0},
        {'date': '2026-11-18', 'weight_kg': 74.0},
      ]);
      expect(find.text('$onLine $_dot as of 18 Nov'), findsOneWidget);
      await pumpMaintain(tester, '', at(2026, 11, 26), entries: [
        {'date': '2026-11-04', 'weight_kg': 76.0},
        {'date': '2026-11-10', 'weight_kg': 75.0},
        {'date': '2026-11-18', 'weight_kg': 79.0},
      ]);
      expect(find.text('$offLine $_dot as of 18 Nov'), findsOneWidget);
    });

    testWidgets('three weigh-ins: a Cut takes its span from the first and the LAST date',
        (tester) async {
      // The middle entry is on the first day: a read of the middle date as "last" would
      // make the span 0 weeks and draw nothing.
      await pumpMaintain(tester, '', _now, goal: 'lose_fat', target: 70, entries: [
        {'date': '2026-11-04', 'weight_kg': 80.0},
        {'date': '2026-11-04', 'weight_kg': 79.0},
        {'date': '2026-11-18', 'weight_kg': 78.0},
      ]);
      expect(
          find.text('At current rate, you\'ll reach 70kg in ~8 weeks (around Apr 2031)'),
          findsOneWidget);
    });

    testWidgets('a future-dated last weigh-in never prints a suffix', (tester) async {
      await pumpMaintain(tester, '2026-12-05', at(2026, 11, 19));
      expect(find.text(onLine), findsOneWidget);
    });

    testWidgets('a last date that only DateTime.tryParse accepts draws the line bare',
        (tester) async {
      // The first entry stays a valid key; only the LAST is lenient-parseable. The
      // clock is far past every one of them, so a suffix would print if the keys parsed.
      for (final key in ['20261118', '2026-11-18T10:00:00', '2026-02-31']) {
        await pumpMaintain(tester, key, at(2026, 12, 1), entries: [
          {'date': '2026-11-04', 'weight_kg': 76.0},
          {'date': key, 'weight_kg': 74.0},
        ]);
        expect(find.text(onLine), findsOneWidget, reason: key);
      }
    });

    testWidgets('a stale Cut or Build row shows no suffix, only Maintain does',
        (tester) async {
      await pumpMaintain(tester, '2026-11-03', at(2026, 11, 26),
          goal: 'lose_fat', first: 80, last: 78, target: 70);
      expect(find.textContaining('as of'), findsNothing);
      expect(find.textContaining('At current rate'), findsOneWidget);
      await pumpMaintain(tester, '2026-11-03', at(2026, 11, 26),
          goal: 'build_muscle', first: 75, last: 76, target: 80);
      expect(find.textContaining('as of'), findsNothing);
      expect(find.textContaining('At current rate'), findsOneWidget);
      // adjust and reached, on the same stale clock
      await pumpMaintain(tester, '2026-11-03', at(2026, 11, 26),
          goal: 'lose_fat', first: 77, last: 78, target: 70);
      expect(find.text('Adjust your diet to stay on track'), findsOneWidget);
      await pumpMaintain(tester, '2026-11-03', at(2026, 11, 26),
          goal: 'lose_fat', first: 79, last: 78, target: 78);
      expect(find.text('You\'ve reached your goal weight!'), findsOneWidget);
    });

    testWidgets('the longest line still wraps on a 320 px card', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pumpMaintain(tester, '2026-12-23', at(2026, 12, 31, 19), last: 79);
      expect(tester.takeException(), isNull);
      expect(find.text('$offLine $_dot as of 23 Dec 2026'), findsOneWidget);
    });
  });

  group('parseDateKeyUtc / maintainAsOfSuffix (pure)', () {
    test('a valid key is that UTC calendar date', () {
      expect(parseDateKeyUtc('2026-11-18'), DateTime.utc(2026, 11, 18));
      expect(parseDateKeyUtc('2028-02-29'), DateTime.utc(2028, 2, 29));
    });

    test('anything that is not exactly a real YYYY-MM-DD is null', () {
      for (final bad in [
        '',
        '20261118',
        '2026-11-18T10:00:00',
        '2026-11-18x',
        ' 2026-11-18',
        '2026-11-18 ',
        '12026-11-18',
        '2026-12-32',
        '2026-13-01',
        '2026-00-10',
        '2026-04-31',
        '2026-02-31',
        '2027-02-29',
        '2026-1-5',
        '2026-11-1',
        '2026-1-05',
        '026-11-18',
      ]) {
        expect(parseDateKeyUtc(bad), isNull, reason: bad);
      }
    });

    test('the suffix is empty up to 7 days, set from 8', () {
      expect(maintainAsOfSuffix(lastDateKey: '2026-11-12', now: _freshNow), '');
      expect(maintainAsOfSuffix(lastDateKey: '2026-11-11', now: _freshNow),
          ' $_dot as of 11 Nov');
      expect(kMaintainStaleAfterDays, 7);
    });

    test('a very old key still prints, with its year', () {
      expect(maintainAsOfSuffix(lastDateKey: '2014-03-05', now: _freshNow),
          ' $_dot as of 5 Mar 2014');
    });

    test('an unreadable or future key is empty', () {
      expect(maintainAsOfSuffix(lastDateKey: '', now: _freshNow), '');
      expect(maintainAsOfSuffix(lastDateKey: 'not-a-date', now: _freshNow), '');
      expect(maintainAsOfSuffix(lastDateKey: '2026-12-31', now: _freshNow), '');
    });

    test('the day count is calendar days: a DST week does not move it', () {
      // 2026-03-01 to 2026-03-09 is 8 days across the US spring-forward on the 8th.
      expect(
          maintainAsOfSuffix(lastDateKey: '2026-03-01', now: DateTime.utc(2026, 3, 9, 12)),
          ' $_dot as of 1 Mar');
      expect(
          maintainAsOfSuffix(lastDateKey: '2026-03-02', now: DateTime.utc(2026, 3, 9, 12)),
          '');
    });
  });

  group('WeightProjectionLine: the profile map to the rendered text', () {
    Future<void> pumpLine(WidgetTester tester, Map<String, dynamic> profile,
        List<Map<String, dynamic>> entries,
        {bool fresh = false}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WeightProjectionLine(
              profile: profile, entries: entries, now: fresh ? _freshNow : _now),
        ),
      ));
    }

    testWidgets('a Maintain profile reads its goal and target from the map',
        (tester) async {
      await pumpLine(tester,
          {'primary_goal': 'general_fitness', 'target_weight_kg': 75.0}, _entries(76, 74), fresh: true);
      expect(find.text('Holding the line $_dot 1.0 kg from your 75 kg target'),
          findsOneWidget);
    });

    testWidgets('the line forwards its clock to the suffix: a 2031 clock makes 2026-11-18 old',
        (tester) async {
      await pumpLine(tester,
          {'primary_goal': 'general_fitness', 'target_weight_kg': 75.0}, _entries(76, 74));
      expect(find.text('Holding the line $_dot 1.0 kg from your 75 kg target $_dot as of 18 Nov 2026'),
          findsOneWidget);
    });

    testWidgets('an int target (a num) is read the same', (tester) async {
      await pumpLine(tester,
          {'primary_goal': 'general_fitness', 'target_weight_kg': 75}, _entries(74, 79),
          fresh: true);
      expect(
          find.text(
              '4.0 kg above your 75 kg target $_dot adjust your nutrition to hold the line'),
          findsOneWidget);
    });

    testWidgets(
        'with NO injected clock the line reads the app clock seam (nowWall): '
        'the production path, which the screen takes', (tester) async {
      addTearDown(resetTestClock);
      final profile = {'primary_goal': 'general_fitness', 'target_weight_kg': 75.0};
      Future<void> pumpApp() => tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: WeightProjectionLine(
                  profile: profile, entries: _entriesEndingOn('2026-11-18', 76, 74)),
            ),
          ));
      // 14:00 UTC = 19:30 IST on the 25th: 7 days old, no suffix (a double IST shift
      // would read the 26th and print one).
      setTestClockTo(DateTime.utc(2026, 11, 25, 14));
      await pumpApp();
      expect(find.text('Holding the line $_dot 1.0 kg from your 75 kg target'),
          findsOneWidget);
      // The next day: 8 days old, the suffix (a fixed or missing clock cannot print it).
      setTestClockTo(DateTime.utc(2026, 11, 26, 6));
      await pumpApp();
      expect(
          find.text('Holding the line $_dot 1.0 kg from your 75 kg target $_dot as of 18 Nov'),
          findsOneWidget);
      // A clock far in the future: old, with the year.
      setTestClockTo(DateTime.utc(2031, 3, 5, 6));
      await pumpApp();
      expect(
          find.text(
              'Holding the line $_dot 1.0 kg from your 75 kg target $_dot as of 18 Nov 2026'),
          findsOneWidget);
    });

    testWidgets('a Cut profile keeps its date sentence, from the injected clock',
        (tester) async {
      await pumpLine(tester,
          {'primary_goal': 'lose_fat', 'target_weight_kg': 70.0}, _entries(80, 78));
      expect(
          find.text('At current rate, you\'ll reach 70kg in ~8 weeks (around Apr 2031)'),
          findsOneWidget);
    });

    testWidgets('the goal comes from primary_goal, not from the target or the entries',
        (tester) async {
      // Same weigh-ins and target, two goals: the words differ only by the goal.
      await pumpLine(tester,
          {'primary_goal': 'build_muscle', 'target_weight_kg': 75.0}, _entries(76, 74));
      expect(find.textContaining('Holding the line'), findsNothing);
      expect(find.text('Adjust your nutrition to stay on track'), findsOneWidget);
    });

    testWidgets('the LAST entry decides: the entries are read oldest first',
        (tester) async {
      await pumpLine(tester,
          {'primary_goal': 'general_fitness', 'target_weight_kg': 75.0}, _entries(80, 76),
          fresh: true);
      expect(find.text('Holding the line $_dot 1.0 kg from your 75 kg target'),
          findsOneWidget);
    });

    testWidgets('no target (absent, 0) or fewer than two weigh-ins draws nothing',
        (tester) async {
      await pumpLine(tester, {'primary_goal': 'general_fitness'}, _entries(76, 74));
      expect(find.byType(Text), findsNothing);
      await pumpLine(tester,
          {'primary_goal': 'general_fitness', 'target_weight_kg': 0}, _entries(76, 74));
      expect(find.byType(Text), findsNothing);
      await pumpLine(tester,
          {'primary_goal': 'general_fitness', 'target_weight_kg': 75.0},
          [_entries(76, 74).first]);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('a Cut with no target (absent or 0) draws nothing, not "Adjust your diet"',
        (tester) async {
      // Moving the wrong way with remaining = target - last = -77: the old kind WOULD say
      // `adjust` for a missing target; the line's own target guard is what hides it.
      await pumpLine(tester, {'primary_goal': 'lose_fat'}, _entries(77, 78));
      expect(find.byType(Text), findsNothing);
      await pumpLine(tester,
          {'primary_goal': 'lose_fat', 'target_weight_kg': 0}, _entries(77, 78));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('the callout sits 10 px under the chart', (tester) async {
      await pumpLine(tester,
          {'primary_goal': 'general_fitness', 'target_weight_kg': 75.0}, _entries(76, 74));
      final pad = tester.widget<Padding>(find
          .descendant(of: find.byType(WeightProjectionLine), matching: find.byType(Padding))
          .first);
      expect(pad.padding, const EdgeInsets.only(top: 10));
    });

    testWidgets('a profile with NO goal keeps the non-Maintain path (accepted residue)',
        (tester) async {
      await pumpLine(tester, {'target_weight_kg': 75.0}, _entries(76, 74));
      expect(find.textContaining('Holding the line'), findsNothing);
      expect(find.text('Adjust your nutrition to stay on track'), findsOneWidget);
    });
  });

  group('the Weekly Report screen hands the profile to the callout (presence only)', () {
    final screen = _src('lib/features/profile/screens/reports_screen.dart');

    /// The text of the `WeightProjectionLine(` call: from its open paren to the matching
    /// close, whitespace and a trailing comma removed, so the pin compares the ARGUMENTS
    /// exactly (a token elsewhere in the file, a comment, or a re-derived expression
    /// cannot satisfy it).
    String callArguments() {
      final at = screen.indexOf('WeightProjectionLine(');
      expect(at, greaterThanOrEqualTo(0), reason: 'the screen no longer builds the callout');
      var depth = 0;
      for (var i = screen.indexOf('(', at); i < screen.length; i++) {
        if (screen[i] == '(') depth++;
        if (screen[i] == ')') depth--;
        if (depth == 0) {
          return screen
              .substring(at, i + 1)
              .replaceAll(RegExp(r'\s+'), '')
              .replaceAll(',)', ')');
        }
      }
      fail('unbalanced call');
    }

    test('the call hands over the raw profile and the filtered weigh-ins, nothing else', () {
      expect(callArguments(), 'WeightProjectionLine(profile:profile,entries:filtered)');
    });

    test('the screen builds the line exactly once', () {
      expect('WeightProjectionLine('.allMatches(screen).length, 1);
    });

    test('the screen no longer decides the callout itself', () {
      expect(screen.contains('_buildProjectionCallout'), isFalse);
      expect(screen.contains("goal.contains('lose')"), isFalse);
    });
  });
}
