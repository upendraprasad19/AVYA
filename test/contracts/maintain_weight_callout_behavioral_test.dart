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
import 'package:icanbefitter/features/onboarding/target_weight_check.dart';
import 'package:icanbefitter/features/profile/widgets/weight_projection_callout.dart';

const _dot = '·';

/// Two weigh-ins 14 days apart (weeksDiff 2.0).
List<Map<String, dynamic>> _entries(double first, double last) => [
      {'date': '2026-11-04', 'weight_kg': first},
      {'date': '2026-11-18', 'weight_kg': last},
    ];

class _Fixture {
  const _Fixture(this.goal, this.first, this.last, this.target, {this.text});
  final String goal;
  final double first;
  final double last;
  final double target;

  /// The exact text under the callout; null = nothing is drawn.
  final String? text;
}

final _now = DateTime(2026, 11, 18);

Future<void> _pump(WidgetTester tester, _Fixture f) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: WeightProjectionCallout(
        entries: _entries(f.first, f.last),
        targetWeight: f.target,
        goal: f.goal,
        now: _now,
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
      // 2 kg per 2 weeks, 8 kg to go: 8 weeks from 2026-11-18 = 2027-01-13.
      ProjectionCalloutKind.eta: const _Fixture('lose_fat', 80, 78, 70,
          text: 'At current rate, you\'ll reach 70kg in ~8 weeks (around Jan 2027)'),
      ProjectionCalloutKind.onTarget: const _Fixture('general_fitness', 76, 74, 75,
          text: 'Holding the line $_dot 1.0 kg from your 75 kg target'),
      ProjectionCalloutKind.offTarget: const _Fixture('general_fitness', 76, 79, 75,
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
      await _pump(tester, const _Fixture('general_fitness', 76, 74, 75));
      expect(find.textContaining('Adjust your'), findsNothing);
      expect(find.text('Holding the line $_dot 1.0 kg from your 75 kg target'),
          findsOneWidget);
    });

    testWidgets('rising inside the band is the hold line, never a date',
        (tester) async {
      await _pump(tester, const _Fixture('general_fitness', 74, 76, 75));
      expect(find.textContaining('At current rate'), findsNothing);
      expect(find.textContaining('weeks'), findsNothing);
      expect(find.text('Holding the line $_dot 1.0 kg from your 75 kg target'),
          findsOneWidget);
    });

    testWidgets('a flat series inside the band draws the hold line (no division)',
        (tester) async {
      await _pump(tester, const _Fixture('general_fitness', 75.4, 75.4, 75));
      expect(find.text('Holding the line $_dot 0.4 kg from your 75 kg target'),
          findsOneWidget);
    });

    testWidgets('right on the target says so', (tester) async {
      await _pump(tester, const _Fixture('general_fitness', 75, 75, 75));
      expect(find.text('Holding the line $_dot right on your 75 kg target'),
          findsOneWidget);
    });

    testWidgets('beyond the band below the target says below', (tester) async {
      await _pump(tester, const _Fixture('general_fitness', 74, 71.6, 75));
      expect(
          find.text(
              '3.4 kg below your 75 kg target $_dot adjust your nutrition to hold the line'),
          findsOneWidget);
    });

    testWidgets('the band edge: 3.0 is on target, 3.1 is off target', (tester) async {
      await _pump(tester, const _Fixture('general_fitness', 76, 78.3, 75.3));
      expect(find.textContaining('Holding the line $_dot 3.0 kg'), findsOneWidget);
      await _pump(tester, const _Fixture('general_fitness', 76, 78.4, 75.3));
      expect(find.textContaining('3.1 kg above'), findsOneWidget);
    });

    testWidgets(
        'the gap is the rule\'s own tenths: 66.9 against 70.0 reads 3.1 below, '
        'not a truncated 3.0', (tester) async {
      // (70.0 - 66.9) * 10 = 30.999999999999943: round() 31, truncate() 30.
      await _pump(tester, const _Fixture('general_fitness', 66, 66.9, 70.0));
      expect(
          find.text(
              '3.1 kg below your 70 kg target $_dot adjust your nutrition to hold the line'),
          findsOneWidget);
    });

    testWidgets('a fractional target keeps its decimal, a whole one drops it',
        (tester) async {
      await _pump(tester, const _Fixture('general_fitness', 75, 75.8, 74.8));
      expect(find.textContaining('your 74.8 kg target'), findsOneWidget);
      await _pump(tester, const _Fixture('general_fitness', 75, 75.8, 75.0));
      expect(find.textContaining('your 75 kg target'), findsOneWidget);
    });

    testWidgets('on target: green check and the ok colour; off target: warning and warn',
        (tester) async {
      await _pump(tester, const _Fixture('general_fitness', 76, 74, 75));
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber), findsNothing);
      expect(_color(tester, 'Holding the line $_dot 1.0 kg from your 75 kg target'),
          AppColors.ok);

      await _pump(tester, const _Fixture('general_fitness', 76, 79, 75));
      expect(find.byIcon(Icons.warning_amber), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(
          _color(tester,
              '4.0 kg above your 75 kg target $_dot adjust your nutrition to hold the line'),
          AppColors.warn);
    });

    testWidgets('a long line wraps instead of overflowing a narrow card',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pump(tester, const _Fixture('general_fitness', 76, 79, 75));
      expect(tester.takeException(), isNull);
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

    testWidgets('two weigh-ins under half a week apart draw nothing, even in the band',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WeightProjectionCallout(
            entries: [
              {'date': '2026-11-17', 'weight_kg': 75.0},
              {'date': '2026-11-18', 'weight_kg': 75.0},
            ],
            targetWeight: 75,
            goal: 'general_fitness',
          ),
        ),
      ));
      expect(_texts, findsNothing);
    });
  });

  group('the Weekly Report screen hands the goal to the callout (presence only)', () {
    final screen = _src('lib/features/profile/screens/reports_screen.dart');

    /// The text of the `WeightProjectionCallout(` call: from its open paren to the
    /// matching close, so tokens elsewhere in the file cannot satisfy the pins.
    String callExtent() {
      final at = screen.indexOf('WeightProjectionCallout(');
      expect(at, greaterThanOrEqualTo(0), reason: 'the screen no longer builds the callout');
      var depth = 0;
      for (var i = screen.indexOf('(', at); i < screen.length; i++) {
        if (screen[i] == '(') depth++;
        if (screen[i] == ')') depth--;
        if (depth == 0) return screen.substring(at, i + 1);
      }
      fail('unbalanced call');
    }

    test('the call passes goal: from primary_goal', () {
      final call = callExtent();
      expect(call.contains('goal:'), isTrue);
      expect(call.contains('primary_goal'), isTrue);
    });

    test('the screen no longer decides the callout itself', () {
      expect(screen.contains('_buildProjectionCallout'), isFalse);
      expect(screen.contains("goal.contains('lose')"), isFalse);
    });
  });
}
