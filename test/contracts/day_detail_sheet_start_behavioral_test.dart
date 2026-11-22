// BEHAVIORAL CONTRACT TEST — diagnose 7c3e91 (Home calendar day sheet START).
//
// Before: `DayDetailSheet._buildStartButton` was `onTap: () => Navigator.pop()`
// since the first commit (ef878afb, 2026-03-24). Tapping START WORKOUT on
// today's calendar day closed the sheet and started nothing. The 2026-07-20
// "Home START dead-end" fix (b7f30a) swept callers of `startWorkout`, and this
// button never called it, so it was never found.
//
// Now: the host passes `onStart` (home_screen `_startTodayWorkout`, the SAME
// path as the Today card). The sheet closes FIRST, then calls it. With no
// `onStart` the button is DISABLED, never a button that only closes the sheet.
//
// MUTATION: delete `onStart?.call();` in day_detail_sheet.dart -> test 1 fails.
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/home/widgets/day_detail_sheet.dart';

import '../features/train/log_exercise/card_harness.dart' show renderFontsFirst;

Map<String, dynamic> _plannedWorkout() => {
      'type': 'workout',
      'status': 'planned',
      'workout_name': 'FULL BODY + CORE',
      'exercises': <Map<String, dynamic>>[],
    };

/// A page with one button that opens the sheet exactly as Home does.
Future<void> _openSheet(
  WidgetTester tester, {
  required DateTime date,
  VoidCallback? onStart,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => DayDetailSheet.show(
              context,
              date: date,
              schedule: _plannedWorkout(),
              onStart: onStart,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('fonts degrade first', renderFontsFirst);

  testWidgets("today's START WORKOUT closes the sheet THEN calls onStart once",
      (tester) async {
    var called = 0;
    await _openSheet(tester, date: DateTime.now(), onStart: () => called++);
    expect(find.text('START WORKOUT'), findsOneWidget);

    await tester.tap(find.text('START WORKOUT'));
    await tester.pumpAndSettle();

    // Called exactly once, and the sheet closed.
    expect(called, 1);
    expect(find.text('START WORKOUT'), findsNothing);
  });

  testWidgets('no onStart: the button is DISABLED, the sheet stays open',
      (tester) async {
    await _openSheet(tester, date: DateTime.now());
    final ink = tester.widget<InkWell>(find
        .ancestor(
            of: find.text('START WORKOUT'), matching: find.byType(InkWell))
        .first);
    expect(ink.onTap, isNull,
        reason: 'a START button with no start path must not look alive');

    await tester.tap(find.text('START WORKOUT'));
    await tester.pumpAndSettle();
    expect(find.text('START WORKOUT'), findsOneWidget);
  });

  testWidgets('a day that is not today stays disabled even with onStart',
      (tester) async {
    var called = 0;
    await _openSheet(tester,
        date: DateTime.now().add(const Duration(days: 2)),
        onStart: () => called++);
    await tester.tap(find.text('START WORKOUT'));
    await tester.pumpAndSettle();
    expect(called, 0);
    expect(find.text('START WORKOUT'), findsOneWidget);
  });

  test('home_screen hands the sheet the SAME start path as the Today card', () {
    final src = File('lib/features/home/screens/home_screen.dart')
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    // One shared method, used by the card AND the sheet; no second copy of
    // the begin-workout sequence.
    expect(RegExp(r'_startTodayWorkout\(context, ref\)').allMatches(src).length,
        2,
        reason: 'the Today card and the day sheet both call it');
    expect('beginWorkoutWithReadiness('.allMatches(src).length, 1,
        reason: 'the start sequence lives in ONE method');
  });
}
