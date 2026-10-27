// Spec §13 #3 / plan deviation D8 — DONE must win over the swapped-day glyph
// on the Home weekly-calendar strip. Behavioral (not source-grep): pumps the
// real widget over a seeded schedule row, so it fails if the precedence
// regresses even when the source still contains both branches in some order.
//
// HARNESS NOTE (GoogleFonts pitfall, root CLAUDE.md §4.9 "A widget test that
// mocks path_provider makes GoogleFonts fail LOUDLY"): the FIRST test below
// is a typography warmup that runs BEFORE setUpHiveForTests ever installs
// the path_provider mock (that mock is scoped to the group below, which has
// its own local setUp/tearDown). GoogleFonts caches per family+weight, so
// the warmup renders every family WeeklyCalendar's _buildIndicator uses
// (AppTypography.body — DM Sans w400 — and AppTypography.monoXs — mono w600).
//
// @Timeout + library (root CLAUDE.md §4.9 "carries a file-level annotation,
// no per-test override" class): the Hive seed below is real disk I/O escaped
// via tester.runAsync — if that ever regresses to a direct fake-async await,
// this bounds the hang to a failure instead of stalling the whole suite.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/home/widgets/weekly_calendar.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  testWidgets('typography warmup — GoogleFonts caches before any Hive mock',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Text('a', style: AppTypography.body),
          Text('b', style: AppTypography.monoXs),
        ]),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    // Quiet-degrade expected — no exception escapes (path_provider mock is
    // NOT installed in this test).
    expect(find.text('a'), findsOneWidget);
  });

  group('WeeklyCalendar swap precedence (D8)', () {
    late Directory dir;

    setUp(() async {
      dir = await setUpHiveForTests();
    });

    tearDown(() async {
      await tearDownHiveForTests(dir);
    });

    testWidgets(
        'a completed AND swapped day shows the check, not the 🔄 glyph',
        (tester) async {
      final today = DateTime.now();
      final todayKey = istDateStr(today);
      await tester.runAsync(() => HiveService.instance.workoutBox.put(
            'schedule_$todayKey',
            {
              'date': todayKey,
              'type': 'workout',
              'workout_name': 'Pull + Core',
              'status': 'completed',
              'is_swapped': true,
              'original_date': todayKey,
              'exercises': <Map<String, dynamic>>[],
            },
          ));

      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: WeeklyCalendar())),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.text('\u{1F504}'), findsNothing);
    });

    testWidgets(
        'a planned (not completed) swapped day still shows the 🔄 glyph',
        (tester) async {
      final today = DateTime.now();
      final todayKey = istDateStr(today);
      await tester.runAsync(() => HiveService.instance.workoutBox.put(
            'schedule_$todayKey',
            {
              'date': todayKey,
              'type': 'workout',
              'workout_name': 'Legs + Core',
              'status': 'planned',
              'is_swapped': true,
              'original_date': todayKey,
              'exercises': <Map<String, dynamic>>[],
            },
          ));

      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: WeeklyCalendar())),
      ));
      await tester.pumpAndSettle();

      expect(find.text('\u{1F504}'), findsOneWidget);
    });
  });
}
