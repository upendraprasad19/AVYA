// HARNESS NOTE (GoogleFonts pitfall, root CLAUDE.md §4.9 "A widget test that
// mocks path_provider makes GoogleFonts fail LOUDLY"): the FIRST test below
// is a typography warmup that runs BEFORE setUpHiveForTests ever installs
// the path_provider mock (that mock is scoped to the group below, which has
// its own local setUp/tearDown — this outer test is untouched by it).
// GoogleFonts caches per family+weight, so the warmup renders every family
// this file reaches — including SwapConfirmSheet, which the drop tests open.
// Reference: test/widgets/compass_redesign_test.dart,
// test/widgets/swap_picker_sheet_test.dart.
//
// @Timeout + library (root CLAUDE.md §4.9 + .claude/skills/debugging/SKILL.md
// §2.73 widget-test-hang class): this batch's Tasks 24/27 hit 20+ minute
// hangs straight through --timeout from unwrapped real I/O in a testWidgets
// body. All Hive I/O here happens in setUp/tearDown (not inside a
// testWidgets body), so no runAsync wrapping is needed in the test bodies
// themselves — @Timeout is still the bounded-regression backstop.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_allowance.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_copy.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/swap_service.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/train/widgets/day_swap_drag_wrapper.dart';

import '../helpers/hive_test_setup.dart';

// Week of Mon 21 - Sun 27 Sep 2026; "today" is Thu 24.
const thu = '2026-09-24';
const fri = '2026-09-25';
const sat = '2026-09-26';

Map<String, dynamic> workout(String date, String name,
        {String status = 'planned'}) =>
    {
      'date': date,
      'type': 'workout',
      'workout_name': name,
      'status': status,
      'exercises': <Map<String, dynamic>>[],
    };

void main() {
  testWidgets('typography warmup — GoogleFonts caches before any Hive mock',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Text('a', style: AppTypography.h3),
          Text('b', style: AppTypography.bodySm),
          Text('c', style: AppTypography.monoXs),
          Text('d', style: AppTypography.mono),
        ]),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    // Quiet-degrade expected — no exception escapes (path_provider mock is
    // NOT installed in this test).
    expect(find.text('a'), findsOneWidget);
  });

  group('DaySwapDragWrapper', () {
    late Directory dir;

    setUp(() async {
      dir = await setUpHiveForTests();
      setTestClockTo(DateTime.utc(2026, 9, 24, 4, 30)); // Thu 24, 10:00 IST
      ErrorTelemetry.debugOnLogEventForTests = (op, {message}) {};
      ErrorTelemetry.debugOnRecordNonFatalForTests =
          (e, st, {required reason, extra}) {};
      DaySwapAllowance.debugConsumeForTests = (_) async => null;
      SwapService.debugOnPlanPushForTests = () {};
      final box = HiveService.instance.workoutBox;
      await box.put('schedule_$thu', workout(thu, 'ROW_THU'));
      await box.put('schedule_$fri', workout(fri, 'ROW_FRI'));
      await box.put(
          'schedule_$sat', workout(sat, 'ROW_SAT', status: 'completed'));
    });

    tearDown(() async {
      ErrorTelemetry.debugOnLogEventForTests = null;
      ErrorTelemetry.debugOnRecordNonFatalForTests = null;
      DaySwapAllowance.debugConsumeForTests = null;
      SwapService.debugOnPlanPushForTests = null;
      await HiveService.instance.configBox
          .delete('disable_day_swap_train_ui');
      resetTestClock();
      await tearDownHiveForTests(dir);
    });

    Future<void> pumpThreeRows(WidgetTester tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Column(children: [
              DaySwapDragWrapper(
                  date: thu,
                  child: Container(height: 48, child: const Text('ROW_THU'))),
              DaySwapDragWrapper(
                  date: fri,
                  child: Container(height: 48, child: const Text('ROW_FRI'))),
              DaySwapDragWrapper(
                  date: sat,
                  child: Container(height: 48, child: const Text('ROW_SAT'))),
            ]),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('long-pressing a movable row lifts it and shows "moving…"',
        (tester) async {
      await pumpThreeRows(tester);
      final gesture =
          await tester.startGesture(tester.getCenter(find.text('ROW_FRI')));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      expect(find.textContaining('moving'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a locked row fades with a lock glyph while a drag is active',
        (tester) async {
      await pumpThreeRows(tester);
      final gesture =
          await tester.startGesture(tester.getCenter(find.text('ROW_FRI')));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await tester.pump();
      expect(find.byIcon(Icons.lock), findsOneWidget); // ROW_SAT (completed)
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a valid target shows the DROP TO SWAP label when hovered',
        (tester) async {
      await pumpThreeRows(tester);
      final gesture =
          await tester.startGesture(tester.getCenter(find.text('ROW_FRI')));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveTo(tester.getCenter(find.text('ROW_THU')));
      await tester.pump();
      expect(find.text(DaySwapCopy.dropToSwap), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('dropping on a valid target opens the confirm sheet',
        (tester) async {
      await pumpThreeRows(tester);
      final from = tester.getCenter(find.text('ROW_FRI'));
      final gesture = await tester.startGesture(from);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      // Queried AFTER the long-press fires, matching "a valid target shows
      // the DROP TO SWAP label when hovered" above — the brief's original
      // draft captured `to` BEFORE starting the gesture, which reproducibly
      // missed ROW_THU's DragTarget (onWillAcceptWithDetails then fired only
      // for ROW_FRI's own target, isValidTarget=false, and the drop never
      // registered). Once every valid target's chrome switches on at drag
      // START (not just on hover — see DaySwapDragWrapper.isValidTarget),
      // its CustomPaint/Stack wrapping is present from the very first
      // long-press frame, so a coordinate captured before the drag began no
      // longer matches the post-wrap render. Root-caused by instrumenting
      // onWillAcceptWithDetails/onAcceptWithDetails directly (both showed
      // zero drops onto ROW_THU with the pre-drag coordinate; both fired
      // correctly once requeried here).
      final to = tester.getCenter(find.text('ROW_THU'));
      await gesture.moveTo(to);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text(DaySwapCopy.confirmEyebrow), findsOneWidget);
    });

    // F3 (task-25-fix1 review round): DaySwapDragWrapper has the widest
    // OFF-state behavior change of the three day-swap Train widgets (an
    // entire early-return branch), yet had no OFF-state test at all.
    testWidgets(
        'with the switch OFF: long-press does not lift, no target chrome, no confirm sheet',
        (tester) async {
      await tester.runAsync(() => HiveService.instance.configBox
          .put('disable_day_swap_train_ui', true));
      await pumpThreeRows(tester);
      final from = tester.getCenter(find.text('ROW_FRI'));
      final to = tester.getCenter(find.text('ROW_THU'));
      final gesture = await tester.startGesture(from);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      // No lift: no "moving…" placeholder anywhere.
      expect(find.textContaining('moving'), findsNothing);
      await gesture.moveTo(to);
      await tester.pump();
      // No target chrome: no DROP TO SWAP label, no lock glyph on the
      // otherwise-locked ROW_SAT.
      expect(find.text(DaySwapCopy.dropToSwap), findsNothing);
      expect(find.byIcon(Icons.lock), findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();
      // No confirm sheet opened by the drop.
      expect(find.text(DaySwapCopy.confirmEyebrow), findsNothing);
    });

    // F5 (task-25-fix1 review round): the lifted-date reset was previously
    // proven only by a discarded mutation-run probe (task-25-brief.md
    // mutation 4). Standing coverage for all three drag-termination paths
    // the widget wires up: drop on a valid target, drop on an
    // invalid/locked target, and cancel outside any target.
    //
    // Observability note, load-bearing: the "moving…" placeholder is NOT a
    // reliable proxy for `_liftedDateProvider` after the gesture ends —
    // `LongPressDraggable.childWhenDragging` is governed by Flutter's OWN
    // internal drag-session state, which reverts to `child` the instant the
    // pointer is released, accepted or not, independent of this app's
    // Riverpod state. Confirmed by mutation-testing this file's F5 group
    // with every reset call removed at once: the "moving" assertions in the
    // valid-target and no-target-move cases stayed GREEN even with the
    // provider permanently stuck, while ONLY the lock-glyph assertion below
    // (residual chrome `_liftedDateProvider` drives on OTHER rows via
    // `isDragging`/`isValidTarget`, which do NOT depend on Flutter's own
    // drag-session lifecycle) went red. Every test below therefore asserts
    // the lock glyph on ROW_SAT (locked in every `pumpThreeRows` setup) as
    // the real, mutation-verified signal that the lifted date is gone; the
    // "moving" check is kept only as a same-test sanity that the LIFT itself
    // happened (asserted WHILE the drag is still active, where it is
    // reliable).
    group('F5: lifted state resets to null on every drag-termination path',
        () {
      testWidgets('drop on a valid target clears the lifted state',
          (tester) async {
        await pumpThreeRows(tester);
        final from = tester.getCenter(find.text('ROW_FRI'));
        final gesture = await tester.startGesture(from);
        await tester.pump(
            kLongPressTimeout + const Duration(milliseconds: 50));
        expect(find.textContaining('moving'), findsOneWidget);
        final to = tester.getCenter(find.text('ROW_THU'));
        await gesture.moveTo(to);
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
        // The confirm sheet is now open over the row list; the underlying
        // ROW_SAT (locked) must no longer show the drag-active lock glyph.
        expect(find.text(DaySwapCopy.confirmEyebrow), findsOneWidget);
        expect(find.byIcon(Icons.lock), findsNothing);
      });

      testWidgets(
          'drop on a locked target (not accepted) clears the lifted state',
          (tester) async {
        await pumpThreeRows(tester);
        final from = tester.getCenter(find.text('ROW_FRI'));
        final gesture = await tester.startGesture(from);
        await tester.pump(
            kLongPressTimeout + const Duration(milliseconds: 50));
        expect(find.textContaining('moving'), findsOneWidget);
        // ROW_SAT is completed (locked) — onWillAcceptWithDetails requires
        // `movable`, so this drop is never accepted.
        final to = tester.getCenter(find.text('ROW_SAT'));
        await gesture.moveTo(to);
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.lock), findsNothing);
      });

      testWidgets(
          'releasing outside any target (no move) clears the lifted state',
          (tester) async {
        await pumpThreeRows(tester);
        final gesture = await tester
            .startGesture(tester.getCenter(find.text('ROW_FRI')));
        await tester.pump(
            kLongPressTimeout + const Duration(milliseconds: 50));
        expect(find.textContaining('moving'), findsOneWidget);
        // Released over its own row: onWillAcceptWithDetails excludes
        // `details.data == date`, so this is never accepted either —
        // onDraggableCanceled fires.
        await gesture.up();
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.lock), findsNothing);
      });
    });
  });
}
