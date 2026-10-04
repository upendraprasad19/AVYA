// test/widgets/swap_confirm_sheet_test.dart
//
// HARNESS NOTE (GoogleFonts pitfall, root CLAUDE.md §4.9): see
// swap_picker_sheet_test.dart's header — same warmup pattern, same reference
// (test/widgets/compass_redesign_test.dart).
//
// @Timeout + library — same rationale as swap_picker_sheet_test.dart: the
// SWAP button drives the real day-swap engine's Hive (disk) I/O, escaped via
// tester.runAsync; this bounds a regression to a failure, not a stall.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_allowance.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_copy.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_result.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/swap_service.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/train/widgets/swap_confirm_sheet.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_button.dart';

import '../helpers/hive_test_setup.dart';

const wed = '2026-09-23';
const thu = '2026-09-24';
const fri = '2026-09-25';
const sat = '2026-09-26';

class _Sub extends SubscriptionInfoNotifier {
  _Sub(this.pro);
  final bool pro;
  @override
  SubscriptionInfoData build() => SubscriptionInfoData(isPro: pro);
}

Map<String, dynamic> workout(String date, String name,
        {String status = 'planned'}) =>
    {
      'date': date,
      'type': 'workout',
      'workout_name': name,
      'status': status,
      'exercises': <Map<String, dynamic>>[],
    };

Map<String, dynamic> rest(String date) => {
      'date': date,
      'type': 'rest',
      'workout_name': 'Rest Day',
      'status': 'rest',
      'exercises': <Map<String, dynamic>>[],
    };

DaySwapDayState day(String date, Map<String, dynamic> row) => DaySwapDayState(
      date: date,
      row: row,
      lock: null,
      isMoved: false,
      title: DaySwapCopy.titleOf(row),
    );

/// Waits for [condition] to become true, alternating a short REAL-time delay
/// (inside `runAsync`, so the actual engine's Hive I/O gets a chance to
/// progress on the real event loop — see root CLAUDE.md §4.9 "await-ing real
/// disk I/O inside a testWidgets body hangs") with a frame pump (OUTSIDE
/// `runAsync`, so any resulting `setState` rebuild is reflected for `find`).
/// Replaces a fixed `Future.delayed` guess with the actual signal, bounded so
/// a genuine regression fails fast naming what never arrived (root CLAUDE.md
/// §4.9 "no fixed sleeps for async work").
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String timeoutMessage,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail(timeoutMessage);
    }
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets('typography warmup — GoogleFonts caches before any Hive mock',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Text('a', style: AppTypography.h3),
          Text('b', style: AppTypography.bodySm),
          Text('c', style: AppTypography.monoXs),
          Text('d', style: AppTypography.body),
          Text('e', style: AppTypography.mono),
          const WardButton(label: 'x', onPressed: null),
        ]),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('a'), findsOneWidget);
  });

  group('SwapConfirmSheet', () {
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
      await box.put('schedule_$fri', workout(fri, 'Pull + Core'));
      await box.put('schedule_$sat', workout(sat, 'Legs + Core'));
    });

    tearDown(() async {
      ErrorTelemetry.debugOnLogEventForTests = null;
      ErrorTelemetry.debugOnRecordNonFatalForTests = null;
      DaySwapAllowance.debugConsumeForTests = null;
      SwapService.debugOnPlanPushForTests = null;
      resetTestClock();
      await tearDownHiveForTests(dir);
    });

    Future<DaySwapResult?> openConfirm(
      WidgetTester tester, {
      bool isPro = true,
      required DaySwapDayState dayA,
      required DaySwapDayState dayB,
    }) async {
      DaySwapResult? captured;
      await tester.pumpWidget(ProviderScope(
        overrides: [subscriptionInfoProvider.overrideWith(() => _Sub(isPro))],
        child: MaterialApp(
          // Scaffold ancestor required — see swap_picker_sheet_test.dart's
          // note: the post-swap toast calls ScaffoldMessenger.showSnackBar,
          // which asserts a descendant Scaffold has registered.
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  captured = await SwapConfirmSheet.show(context,
                      dayA: dayA, dayB: dayB, origin: DaySwapOrigin.trainDrag);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return captured;
    }

    testWidgets('shows both moves, the allowance line, and no warning',
        (tester) async {
      await openConfirm(tester,
          dayA: day(fri, workout(fri, 'Pull + Core')),
          dayB: day(sat, workout(sat, 'Legs + Core')));

      expect(find.text(DaySwapCopy.confirmEyebrow), findsOneWidget);
      expect(find.text(DaySwapCopy.confirmTitle(fri, sat)), findsOneWidget);
      expect(
          find.text(DaySwapCopy.confirmMove(
              from: fri, title: 'Pull + Core', to: sat)),
          findsOneWidget);
      expect(
          find.text(
              DaySwapCopy.confirmMove(from: sat, title: 'Legs + Core', to: fri)),
          findsOneWidget);
      expect(find.textContaining('swaps this week'), findsOneWidget);
      expect(find.textContaining('rest days in a row'), findsNothing);
      // Deliberately left open at test end (matches the "a stale day..."
      // test below, which also never dismisses). A prior continuation
      // agent added a CANCEL-tap dismiss here chasing a whole-file-only
      // "FocusManager was used after being disposed" flake; re-investigated
      // 2026-09-27 (task 24, second continuation): 5 whole-file runs WITHOUT
      // any dismiss-tap here produced 4 clean passes + 1 unrelated transient
      // Hive-box contention failure (this machine runs ~13 concurrent
      // dart/flutter test processes across sibling worktrees) and ZERO
      // FocusManager reproductions — while the dismiss-tap version had
      // still reproduced the flake 2/2 per the prior agent's own report. The
      // dismiss-tap is therefore not load-bearing; removed per CLAUDE.md
      // §4.4 rule 21 (investigate a claimed fix, don't just keep it). Both
      // widgets under test own no FocusNode/TextEditingController/
      // AnimationController (grepped clean), so there is no product
      // lifecycle resource to leak — the flake is environmental/harness,
      // not a bug in swap_confirm_sheet.dart or swap_picker_sheet.dart.
    });

    testWidgets('shows the 3-rest warning line when the swap creates one',
        (tester) async {
      // The brief's original fixture (swap Fri(rest)<->Sat(workout) with
      // Thu/Fri already rest) does NOT trigger the warning: DaySwapRules
      // .restRunWarning reads the FULL Mon–Sun week, and after that swap the
      // sequence is thu=rest, fri=workout(now Sat's content), sat=rest(now
      // Fri's content) — no run of 3, it BREAKS the existing thu/fri pair
      // instead of extending it (verified by re-deriving day_swap_rules.dart
      // ~:212-232's `before`/`after` logic, not by re-running the brief's
      // fixture blind). Redesigned, STRONGER because it is now actually
      // discriminating: seed Wed+Thu as rest (a pair, not yet a 3-run) and
      // swap Fri(workout) <-> Sat(rest) — landing rest content on Fri
      // extends Wed,Thu,Fri into a 3-day run; Sat gets workout content, so
      // nothing is flagged there.
      //
      // Real Hive (disk) writes inside a testWidgets body can hang under the
      // fake-async zone (root CLAUDE.md §4.9) — escape to the real event
      // loop for the seeding writes.
      await tester.runAsync(() async {
        final box = HiveService.instance.workoutBox;
        await box.put('schedule_$wed', rest(wed));
        await box.put('schedule_$thu', rest(thu));
        await box.put('schedule_$sat', rest(sat));
      });
      final result = await openConfirm(
        tester,
        dayA: day(fri, workout(fri, 'Pull + Core')),
        dayB: day(sat, rest(sat)),
      );
      expect(result, isNull); // sheet only opened; no tap yet in this test
      expect(find.textContaining('rest days in a row'), findsOneWidget);
      // Deliberately left open at test end — see the note in the previous
      // test (the dismiss-tap a prior agent added here was not load-bearing
      // for the FocusManager flake and has been removed).
    });

    testWidgets('SWAP calls the engine and pops with DaySwapDone',
        (tester) async {
      // Inlined rather than routed through openConfirm(): that helper
      // returns its OWN local `captured` right after the 'open' tap
      // settles — i.e. BEFORE the SWAP button is ever pressed — so
      // `final captured = await openConfirm(...)` always reads null here
      // regardless of the engine's real result (found running the whole
      // file 2026-09-27: this test failed with "Actual: <null>" the moment
      // the file-hang fix above let it actually run). The outer `captured`
      // below is the SAME variable the onPressed closure assigns, matching
      // swap_picker_sheet_test.dart's "end to end" test.
      DaySwapResult? captured;
      await tester.pumpWidget(ProviderScope(
        overrides: [subscriptionInfoProvider.overrideWith(() => _Sub(true))],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  captured = await SwapConfirmSheet.show(context,
                      dayA: day(fri, workout(fri, 'Pull + Core')),
                      dayB: day(sat, workout(sat, 'Legs + Core')),
                      origin: DaySwapOrigin.trainDrag);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // WardButton uppercases its label; the engine call does real Hive
      // (disk) writes, which can hang under fake-async — escape to the real
      // event loop for the TAP itself (matching the LOG WORKOUT double-tap /
      // log_food_sheet_search pattern already in this repo). The tap itself
      // stays inside runAsync so the write can progress on the real event
      // loop; the wait for completion is `pumpUntil` below, NOT a bare
      // `.timeout()` await here — `SwapConfirmSheet.show()`'s returned Future
      // only resolves once the bottom sheet's EXIT ANIMATION finishes, which
      // needs frames pumped by the test binding, and `runAsync` never pumps
      // frames (root CLAUDE.md §4.9 (b): awaiting a frame-gated Future from
      // inside `runAsync` deadlocks — measured here as a real 5s timeout
      // firing on every run when tried; task-24 fix round).
      await tester.runAsync(() async {
        await tester.tap(find.text(DaySwapCopy.confirmSwap.toUpperCase()));
      });
      // Now alternate real-time waits (let the Hive write's continuation run)
      // with frame pumps (let the pop + exit animation actually advance)
      // until the sheet is truly gone AND the result has landed — the actual
      // signal, not a fixed-duration guess (task-24 fix round, F1).
      await pumpUntil(
        tester,
        () => find.byType(SwapConfirmSheet).evaluate().isEmpty &&
            captured != null,
        timeoutMessage: 'SwapConfirmSheet did not pop with a captured '
            'result within 5s of tapping SWAP',
      );
      await tester.pumpAndSettle();
      expect(find.byType(SwapConfirmSheet), findsNothing);
      expect(captured, isA<DaySwapDone>());
    });

    // B-pass R2-F1: the drag path opened a plain confirm sheet for a free
    // user whose weekly swap was already spent; SWAP could only answer
    // "spent", with no way to PRO. It must show the same upsell the picker
    // (Train ⇅ + Home long-press) shows.
    testWidgets('spent free user gets the upsell sheet, not a SWAP button',
        (tester) async {
      await tester.runAsync(() => HiveService.instance.userBox.put(
          DaySwapAllowance.hiveKey, {
        '2026-09-21': {'used': DaySwapAllowance.freeLimit}
      }));
      await openConfirm(tester,
          isPro: false,
          dayA: day(fri, workout(fri, 'Pull + Core')),
          dayB: day(sat, workout(sat, 'Legs + Core')));
      expect(find.text(DaySwapCopy.spentTitleFree), findsOneWidget);
      expect(find.text(DaySwapCopy.seePro.toUpperCase()), findsOneWidget);
      expect(find.text(DaySwapCopy.confirmSwap.toUpperCase()), findsNothing);
    });

    testWidgets('free user with a swap left still gets the SWAP button (mirror)',
        (tester) async {
      await openConfirm(tester,
          isPro: false,
          dayA: day(fri, workout(fri, 'Pull + Core')),
          dayB: day(sat, workout(sat, 'Legs + Core')));
      expect(find.text(DaySwapCopy.confirmSwap.toUpperCase()), findsOneWidget);
      expect(find.text(DaySwapCopy.spentTitleFree), findsNothing);
    });

    testWidgets('CANCEL pops with null and writes nothing', (tester) async {
      await openConfirm(tester,
          dayA: day(fri, workout(fri, 'Pull + Core')),
          dayB: day(sat, workout(sat, 'Legs + Core')));
      // WardButton uppercases its label. CANCEL only pops(null) — no engine
      // call, no real I/O, so no runAsync needed here.
      await tester.tap(find.text(DaySwapCopy.cancel.toUpperCase()));
      await tester.pumpAndSettle();
      final before = HiveService.instance.workoutBox.get('schedule_$fri') as Map;
      expect(before['workout_name'], 'Pull + Core');
    });

    testWidgets('a stale day (completed since the drag started) shows the error',
        (tester) async {
      // Real Hive (disk) writes made directly inside a testWidgets body
      // (outside tester.runAsync) hang under the fake-async zone (root
      // CLAUDE.md §4.9 "await-ing real disk I/O inside a testWidgets body
      // hangs until the harness gives up") — this was the ONE call site in
      // this file that still did that: every other seeding write in this
      // file runs in setUp() (a plain async callback, outside the
      // fake-async zone flutter_test wraps testWidgets bodies in) or is
      // already wrapped in runAsync (the 3-rest-warning test above).  This
      // one ran directly in the test body and hung the whole file for
      // 8+ minutes (bisection + coordinator confirmation, 2026-09-27) even
      // with the file's own @Timeout(3 min) in place, because a Timer-based
      // timeout cannot fire while the isolate never returns control past a
      // real I/O await that fake-async cannot drive to completion.
      final box = HiveService.instance.workoutBox;
      await tester.runAsync(() async {
        await box.put(
            'schedule_$sat', workout(sat, 'Legs + Core', status: 'completed'));
      });
      await openConfirm(tester,
          dayA: day(fri, workout(fri, 'Pull + Core')),
          dayB: day(sat, workout(sat, 'Legs + Core'))); // stale pre-swap state
      // The refused engine call still reads Hive state — escape to the real
      // event loop the same way the successful-swap tap above does. Unlike
      // that test, a REFUSAL never pops the sheet, so `SwapConfirmSheet.show`
      // never completes here — there is no outer Future to await directly.
      // Poll for the actual signal (the error line landing via `setState`)
      // instead of guessing a fixed delay (task-24 fix round, F1).
      await tester.runAsync(() async {
        await tester.tap(find.text(DaySwapCopy.confirmSwap.toUpperCase()));
      });
      final errorFinder =
          find.text(DaySwapCopy.staleLine(DaySwapRefusal.completed, sat));
      await pumpUntil(tester, () => errorFinder.evaluate().isNotEmpty,
          timeoutMessage: 'stale-day refusal error line never appeared '
              'within 5s of tapping SWAP');
      expect(find.byType(SwapConfirmSheet), findsOneWidget); // stays open
      expect(errorFinder, findsOneWidget);
    });
  });
}
