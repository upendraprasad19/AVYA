// test/widgets/swap_picker_sheet_test.dart
//
// HARNESS NOTE (GoogleFonts pitfall, root CLAUDE.md §4.9 "A widget test that
// mocks path_provider makes GoogleFonts fail LOUDLY"): the FIRST test below
// is a typography warmup that runs BEFORE setUpHiveForTests ever installs
// the path_provider mock (that mock is scoped to the group below, which has
// its own local setUp/tearDown — this outer test is untouched by it).
// GoogleFonts caches per family+weight, so the warmup renders every family
// this file's widgets use. Reference: test/widgets/compass_redesign_test.dart.
//
// @Timeout + library (root CLAUDE.md §4.9 "@Timeout … carries a file-level
// annotation, no per-test override" class): a tap that drives the real
// day-swap engine does real Hive (disk) I/O escaped via tester.runAsync — if
// that ever regresses to a direct fake-async await, this bounds the hang to
// a failure instead of stalling the whole suite.
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
import 'package:icanbefitter/features/train/widgets/swap_picker_sheet.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_button.dart';

import '../helpers/hive_test_setup.dart';

// Week of Mon 21 - Sun 27 Sep 2026; "today" is Thu 24.
const mon = '2026-09-21';
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

/// Waits for [condition] to become true, alternating a short REAL-time delay
/// (inside `runAsync`, so the actual engine's Hive I/O gets a chance to
/// progress on the real event loop — see root CLAUDE.md §4.9 "await-ing real
/// disk I/O inside a testWidgets body hangs") with a frame pump (OUTSIDE
/// `runAsync`, so any resulting `setState`/pop-animation rebuild is reflected
/// for `find`). Replaces a fixed `Future.delayed` guess with the actual
/// signal, bounded so a genuine regression fails fast naming what never
/// arrived (root CLAUDE.md §4.9 "no fixed sleeps for async work").
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
          // Fraunces w500 ("Medium") — used by PaywallSheet's h1 letterhead,
          // reachable from this file's "See PRO" test. Missing this caused a
          // loud google_fonts network-fetch exception (Fraunces-Medium) in
          // that test even though h3 (w600, "SemiBold") was already warmed.
          Text('e', style: AppTypography.h1),
          const WardButton(label: 'x', onPressed: null),
        ]),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    // Quiet-degrade expected — no exception escapes (path_provider mock is
    // NOT installed in this test).
    expect(find.text('a'), findsOneWidget);
  });

  group('SwapPickerSheet', () {
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
      await box.put('schedule_$thu', workout(thu, 'Calisthenics'));
      await box.put('schedule_$fri', workout(fri, 'Pull + Core'));
      await box.put(
          'schedule_$sat', workout(sat, 'Legs + Core', status: 'completed'));
    });

    tearDown(() async {
      ErrorTelemetry.debugOnLogEventForTests = null;
      ErrorTelemetry.debugOnRecordNonFatalForTests = null;
      DaySwapAllowance.debugConsumeForTests = null;
      SwapService.debugOnPlanPushForTests = null;
      resetTestClock();
      await tearDownHiveForTests(dir);
    });

    Future<DaySwapResult?> openPicker(WidgetTester tester,
        {bool isPro = true, String sourceDate = fri}) async {
      DaySwapResult? captured;
      await tester.pumpWidget(ProviderScope(
        overrides: [subscriptionInfoProvider.overrideWith(() => _Sub(isPro))],
        child: MaterialApp(
          // A Scaffold ancestor is required — the sheet's post-swap toast
          // calls ScaffoldMessenger.showSnackBar, which asserts
          // `_scaffolds.isNotEmpty` (no Scaffold ever registers with the
          // ambient ScaffoldMessenger otherwise). Root-caused by re-reading
          // scaffold.dart:319 after the brief's original Builder-only host
          // (no Scaffold) threw that assertion during the "end to end" test.
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  captured = await SwapPickerSheet.show(context,
                      sourceDate: sourceDate,
                      origin: DaySwapOrigin.trainPicker);
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

    testWidgets(
        'lists movable days tappable and shows a lock label on a completed day',
        (tester) async {
      await openPicker(tester);
      expect(find.text(DaySwapCopy.pickerTitle(fri)), findsOneWidget);
      expect(find.textContaining('Legs + Core'), findsOneWidget);
      expect(find.text('DONE'), findsOneWidget); // Saturday is completed
    });

    testWidgets('a locked day cannot be selected as the target',
        (tester) async {
      await openPicker(tester);
      // Saturday (completed) has no tap target that selects it — tapping its
      // row must not surface the Fri<->Sat picker button. STRICTER than the
      // brief's `find.text(textContaining('Swap'))`: the sheet title "Swap
      // Friday with…" always contains that word regardless of the tap
      // outcome, so that assertion could never fail. Assert on the specific
      // action button instead (WardButton uppercases its label — see
      // ward_button.dart ~:106 `label.toUpperCase()`).
      await tester.tap(find.textContaining('Legs + Core'));
      await tester.pumpAndSettle();
      expect(find.text(DaySwapCopy.pickerButton(fri, sat).toUpperCase()),
          findsNothing);
    });

    testWidgets('picking a movable day then pressing the button swaps and pops',
        (tester) async {
      final result = await openPicker(tester);
      expect(result, isNull); // not yet — the tap chain below drives it
    });

    testWidgets(
        'end to end: pick Thursday, press Swap, sheet closes with DaySwapDone',
        (tester) async {
      DaySwapResult? captured;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          subscriptionInfoProvider.overrideWith(() => _Sub(true)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  captured = await SwapPickerSheet.show(context,
                      sourceDate: fri, origin: DaySwapOrigin.trainPicker);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Calisthenics')); // Thursday's row
      await tester.pumpAndSettle();
      expect(find.text(DaySwapCopy.pickerButton(fri, thu).toUpperCase()),
          findsOneWidget);

      // The button press drives the real day-swap engine, which does real
      // Hive (disk) I/O — awaiting that inside the fake-async testWidgets
      // zone can hang (root CLAUDE.md §4.9 "await-ing real disk I/O inside a
      // testWidgets body hangs"). Escape to the real event loop for the tap
      // itself (matching the LOG WORKOUT double-tap / log_food_sheet_search
      // pattern already in this repo). The wait for completion is `pumpUntil`
      // below, NOT a bare `.timeout()` await here — `SwapPickerSheet.show()`'s
      // returned Future only resolves once the sheet's EXIT ANIMATION
      // finishes, which needs frames pumped by the test binding, and
      // `runAsync` never pumps frames (root CLAUDE.md §4.9 (b): awaiting a
      // frame-gated Future from inside `runAsync` deadlocks — measured here
      // as a real 5s timeout firing on every run when tried; task-24 fix
      // round).
      await tester.runAsync(() async {
        await tester.tap(
            find.text(DaySwapCopy.pickerButton(fri, thu).toUpperCase()));
      });
      // Now alternate real-time waits (let the Hive write's continuation run)
      // with frame pumps (let the pop + exit animation actually advance)
      // until the sheet is truly gone AND the result has landed — the actual
      // signal, not a fixed-duration guess (task-24 fix round, F1).
      await pumpUntil(
        tester,
        () => find.byType(SwapPickerSheet).evaluate().isEmpty &&
            captured != null,
        timeoutMessage: 'SwapPickerSheet did not pop with a captured '
            'result within 5s of tapping SWAP',
      );
      await tester.pumpAndSettle();

      expect(find.byType(SwapPickerSheet), findsNothing);
      expect(captured, isA<DaySwapDone>());
    });

    testWidgets('free tier with the week already spent shows the spent state',
        (tester) async {
      await tester.runAsync(() async {
        await DaySwapAllowance.instance.recordSwap(mon, isPro: false);
        await DaySwapAllowance.instance.lastConsumeForTests;
      });

      await openPicker(tester, isPro: false);

      expect(find.text(DaySwapCopy.spentTitleFree), findsOneWidget);
      expect(find.text(DaySwapCopy.spentBodyFree), findsOneWidget);
      // WardButton uppercases its label.
      expect(find.text(DaySwapCopy.seePro.toUpperCase()), findsOneWidget);
    });

    testWidgets("the spent state's See PRO opens the paywall for 'Day Swaps'",
        (tester) async {
      await tester.runAsync(() async {
        await DaySwapAllowance.instance.recordSwap(mon, isPro: false);
        await DaySwapAllowance.instance.lastConsumeForTests;
      });
      await tester.pumpWidget(ProviderScope(
        overrides: [subscriptionInfoProvider.overrideWith(() => _Sub(false))],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SwapPickerSheet.show(context,
                    sourceDate: fri, origin: DaySwapOrigin.trainPicker),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(DaySwapCopy.seePro.toUpperCase()));
      await tester.pumpAndSettle();
      // PaywallSheet's letterhead: "<feature> is a PRO feature".
      expect(find.text('Day Swaps is a PRO feature'), findsOneWidget);
      // Task 26 addendum: the 'Day Swaps' subtitle line added to
      // paywall_sheet.dart's _featureSubtitle switch.
      expect(
          find.text('Life happens. Move a workout to another day this week '
              'without losing your plan.'),
          findsOneWidget);
    });
  });
}
