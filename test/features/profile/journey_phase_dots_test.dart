import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/features/profile/widgets/journey_phase_dots.dart';

/// OI-348 Landing 3a (P1): the Profile journey card past Phase XII. Before
/// the fix the card drew phases 1-12 only, so from Phase 13 every dot read
/// completed and none read current, and the name line read
/// "Phase 13 — Phase 13".
Color _colorOf(WidgetTester tester, int phase) {
  final box = tester.widget<Container>(find.byKey(ValueKey('journey_dot_$phase')));
  return (box.decoration! as BoxDecoration).color!;
}

Future<void> _pump(WidgetTester tester, int phase, {bool isPro = true}) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: JourneyPhaseDots(currentPhase: phase, isPro: isPro),
        ),
      ),
    ));

void main() {
  test('the journey card renders JourneyPhaseDots and journeyPhaseName', () {
    final s = File('lib/features/profile/screens/profile/journey_timeline.dart')
        .readAsStringSync();
    expect(s, contains('JourneyPhaseDots('));
    expect(s, contains('journeyPhaseName(stats.currentPhase)'));
    expect(s, isNot(contains('List.generate(12')));
  });

  test('block start', () {
    expect(journeyDotBlockStart(1), 1);
    expect(journeyDotBlockStart(12), 1);
    expect(journeyDotBlockStart(13), 13);
    expect(journeyDotBlockStart(24), 13);
    expect(journeyDotBlockStart(25), 25);
    expect(journeyDotBlockStart(0), 1);
  });

  test('name cycles past 12, never "Phase N"', () {
    expect(journeyPhaseName(1), 'Foundation');
    expect(journeyPhaseName(12), 'Legend');
    expect(journeyPhaseName(13), 'Foundation');
    expect(journeyPhaseName(14), 'Building');
  });

  for (final (phase, completed) in [(1, 0), (12, 11), (13, 0), (24, 11), (25, 0)]) {
    testWidgets('phase $phase: 12 dots, exactly one current, '
        '$completed completed', (tester) async {
      await _pump(tester, phase);
      final start = journeyDotBlockStart(phase);
      var current = 0, done = 0;
      for (var p = start; p < start + 12; p++) {
        final c = _colorOf(tester, p);
        if (c == AppColors.accent) current++;
        if (c == AppColors.ok) done++;
      }
      expect(current, 1);
      expect(done, completed);
      expect(_colorOf(tester, phase), AppColors.accent);
      expect(find.byKey(ValueKey('journey_dot_${start + 12}')), findsNothing);
    });
  }

  testWidgets('free user: Phase I is never dimmed, later phases are',
      (tester) async {
    await _pump(tester, 1, isPro: false);
    expect(_colorOf(tester, 2), AppColors.bgRaise.withValues(alpha: 0.5));
  });

  testWidgets('free user past XII: future dots dimmed', (tester) async {
    await _pump(tester, 13, isPro: false);
    // (Absolute phase vs block index for the "Phase I is free" rule cannot
    // be told apart on screen: a block's first dot is never a future phase.)
    expect(_colorOf(tester, 14), AppColors.bgRaise.withValues(alpha: 0.5));
  });
}

