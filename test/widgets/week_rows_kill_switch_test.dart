// HARNESS NOTE (GoogleFonts pitfall, root CLAUDE.md §4.9 "A widget test that
// mocks path_provider makes GoogleFonts fail LOUDLY"): the FIRST test below
// is a typography warmup that runs BEFORE setUpHiveForTests ever installs
// the path_provider mock (that mock is scoped to the group below, which has
// its own local setUp/tearDown — this outer test is untouched by it).
// GoogleFonts caches per family+weight; the ON-switch cases below reach
// DaySwapAllowanceLine's bodySm+monoXs (DaySwapRowTrailing renders no text
// at all when the day has no swap-provider data, so its own families are
// not exercised here). Reference: test/widgets/day_swap_allowance_line_test.dart.
//
// task-25-fix1 (F2): week_rows.dart's own caller-side additions
// (DaySwapRowTrailing + its 8px gap; the allowance-line footer's own 8px
// gap + Column wrapper) were unconditional even when the kill switch was
// off, so the switch never produced a truly byte-identical pre-feature
// layout (task-25-review.md finding 2). `_buildCompactRow`/
// `_buildCompactWeekRows` are private extension methods on
// `_TrainScreenState` (`week_rows.dart` is `part of screen.dart`) and
// pumping the real `TrainScreen` was explicitly rejected for Task 25 itself
// (heavy screen, GoogleFonts/path_provider risk, no existing harness — see
// task-25-brief.md's own Notes) — so the two conditional insertions were
// extracted to top-level, directly-testable functions
// (`daySwapRowTrailingSlot`, `wrapWithDaySwapAllowanceFooter`) that
// `week_rows.dart` now calls instead of inlining the logic. A `part of` file's
// public top-level declarations are visible to anyone importing the main
// library file, so this test imports `screen.dart` itself — a static import
// only, it does not construct or pump `TrainScreen`.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/train/screens/train/screen.dart';
import 'package:icanbefitter/features/train/widgets/day_swap_allowance_line.dart';
import 'package:icanbefitter/features/train/widgets/day_swap_row_trailing.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  testWidgets('typography warmup — GoogleFonts caches before any Hive mock',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Text('a', style: AppTypography.bodySm),
          Text('b', style: AppTypography.monoXs),
        ]),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    // Quiet-degrade expected — no exception escapes (path_provider mock is
    // NOT installed in this test).
    expect(find.text('a'), findsOneWidget);
  });

  group('week_rows.dart kill-switch byte-identity (F2)', () {
    late Directory dir;

    setUp(() async {
      dir = await setUpHiveForTests();
    });

    tearDown(() async {
      await HiveService.instance.configBox
          .delete('disable_day_swap_train_ui');
      await tearDownHiveForTests(dir);
    });

    group('daySwapRowTrailingSlot (the per-row trailing insertion)', () {
      testWidgets(
          'is empty with the switch OFF — matches the pre-feature Row exactly',
          (tester) async {
        await tester.runAsync(() => HiveService.instance.configBox
            .put('disable_day_swap_train_ui', true));
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Row(children: [
              const Text('A'),
              ...daySwapRowTrailingSlot('2026-09-25'),
              const Text('B'),
            ]),
          ),
        ));
        await tester.pump();
        final row = tester.widget<Row>(find.byType(Row));
        // Pre-feature shape: exactly the two rows this test built the Row
        // with, nothing inserted.
        expect(row.children.length, 2);
        expect(find.byType(DaySwapRowTrailing), findsNothing);
        expect(find.byType(SizedBox), findsNothing);
      });

      testWidgets('is empty for a day with no real calendar date, switch ON',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Row(children: [
              const Text('A'),
              ...daySwapRowTrailingSlot(null),
              const Text('B'),
            ]),
          ),
        ));
        await tester.pump();
        final row = tester.widget<Row>(find.byType(Row));
        expect(row.children.length, 2);
        expect(find.byType(DaySwapRowTrailing), findsNothing);
      });

      testWidgets(
          'inserts the widget + its 8px gap for a dated day, switch ON',
          (tester) async {
        await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Row(children: [
                const Text('A'),
                ...daySwapRowTrailingSlot('2026-09-25'),
                const Text('B'),
              ]),
            ),
          ),
        ));
        await tester.pump();
        // DaySwapRowTrailing wraps its own content in a Row too, so the
        // OUTER one (mine, first in tree order) is the one under test.
        final row = tester.widgetList<Row>(find.byType(Row)).first;
        // A, DaySwapRowTrailing, SizedBox, B.
        expect(row.children.length, 4);
        expect(find.byType(DaySwapRowTrailing), findsOneWidget);
        expect(find.byType(SizedBox), findsOneWidget);
      });
    });

    group('wrapWithDaySwapAllowanceFooter (the below-card footer)', () {
      testWidgets(
          'returns the card unchanged with the switch OFF — no Column, no gap, no line',
          (tester) async {
        await tester.runAsync(() => HiveService.instance.configBox
            .put('disable_day_swap_train_ui', true));
        const card = Text('CARD');
        final wrapped = wrapWithDaySwapAllowanceFooter(card, '2026-09-21');
        // The strongest form of "byte-identical": the exact same instance
        // comes back, not merely an equivalent-looking tree.
        expect(identical(wrapped, card), isTrue);
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: wrapped)));
        await tester.pump();
        expect(find.byType(Column), findsNothing);
        expect(find.byType(DaySwapAllowanceLine), findsNothing);
      });

      testWidgets('returns the card unchanged when the week has no dated day',
          (tester) async {
        const card = Text('CARD');
        final wrapped = wrapWithDaySwapAllowanceFooter(card, null);
        expect(identical(wrapped, card), isTrue);
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: wrapped)));
        await tester.pump();
        expect(find.byType(Column), findsNothing);
      });

      testWidgets(
          'wraps with a Column + gap + DaySwapAllowanceLine, switch ON, dated week',
          (tester) async {
        const card = Text('CARD');
        final wrapped = wrapWithDaySwapAllowanceFooter(card, '2026-09-21');
        expect(identical(wrapped, card), isFalse);
        await tester.pumpWidget(
            ProviderScope(child: MaterialApp(home: Scaffold(body: wrapped))));
        await tester.pump();
        // DaySwapAllowanceLine has its own internal Column too, so there
        // are two in the tree — the OUTER one (mine, first in tree order)
        // is the one under test.
        expect(find.byType(Column), findsNWidgets(2));
        final outerColumn = tester.widgetList<Column>(find.byType(Column)).first;
        // card, SizedBox, DaySwapAllowanceLine.
        expect(outerColumn.children.length, 3);
        expect(find.byType(DaySwapAllowanceLine), findsOneWidget);
      });
    });
  });
}
