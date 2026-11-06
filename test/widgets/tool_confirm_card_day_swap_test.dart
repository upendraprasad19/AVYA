// No existing test/widgets/tool_confirm_card_test.dart exists (glob checked
// 2026-09-27) — this widget had ZERO test coverage before this batch. Scoped
// to the day-swap addition only, per spec §9 Testing "Widgets: ... the coach
// card."
//
// HARNESS NOTE (GoogleFonts pitfall, common-pitfalls / test/widgets/
// compass_redesign_test.dart): the FIRST test below is a typography warmup
// that runs BEFORE any path_provider mock exists — GoogleFonts caches per
// family+weight there and degrades quietly. The remaining tests install the
// setUpHiveForTests mock via EXPLICIT per-test helper calls (never a global
// `setUp()`, which would precede the warmup and install the mock for every
// test including it), or the mock answers GoogleFonts' fetch-and-save path
// and the network failure hangs/errors loudly. Discovered live: the brief's
// original draft used a bare top-level `setUp()`/`tearDown()`, which hung
// `flutter test` for this file with zero output for 30+ minutes in this
// worktree — restructured to this repo's own established fix pattern.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';
import 'package:icanbefitter/features/ai_coach/widgets/tool_confirm_card.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';

import '../helpers/hive_test_setup.dart';

/// Renders every AppTypography style ToolConfirmCard uses, so GoogleFonts
/// caches them (DM Sans w400 via `body`/`bodyM`, w600 via `titleS`) before
/// any path_provider mock is installed. `.copyWith(fontWeight: ...)` calls
/// downstream in the card do not re-trigger a fetch — the static fields
/// below are the only points that do.
class _FontWarmup extends StatelessWidget {
  const _FontWarmup();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('a', style: AppTypography.body),
        Text('b', style: AppTypography.bodyM),
        Text('c', style: AppTypography.titleS),
      ],
    );
  }
}

// PRO, so the allowance line reads "… 3 swaps this week." (the swap tool is
// PRO-only; with no override the default free tier renders "1 swap").
class _Sub extends SubscriptionInfoNotifier {
  @override
  SubscriptionInfoData build() => SubscriptionInfoData(isPro: true);
}

const thu = '2026-09-24'; // "today" (clock set below)
const fri = '2026-09-25';
const sat = '2026-09-26';

Map<String, dynamic> workout(String date, String name) => {
      'date': date,
      'type': 'workout',
      'workout_name': name,
      'status': 'planned',
      'exercises': <Map<String, dynamic>>[],
    };

ToolIntent swapIntent() => ToolIntent(
      id: 'i1',
      type: 'swap_workout_days',
      payload: {'dateA': fri, 'dateB': sat},
      confirmationClass: ConfirmationClass.reviewable,
      previewSummary: 'Swap $fri and $sat',
      createdAt: DateTime.now(),
    );

void main() {
  testWidgets('typography warmup — GoogleFonts caches before any Hive mock',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: _FontWarmup())));
    await tester.pump(const Duration(seconds: 1));
    // Quiet-degrade expected — no exception escapes (path_provider mock is
    // NOT installed in this test).
    expect(find.text('a'), findsOneWidget);
  });

  late Directory dir;

  Future<void> setUpHive() async {
    dir = await setUpHiveForTests();
    setTestClockTo(DateTime.utc(2026, 9, 24, 4, 30)); // Thu 24, 10:00 IST
    final box = HiveService.instance.workoutBox;
    await box.put('schedule_$fri', workout(fri, 'Pull + Core'));
    await box.put('schedule_$sat', workout(sat, 'Legs + Core'));
  }

  Future<void> tearDownHive() async {
    resetTestClock();
    await tearDownHiveForTests(dir);
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [subscriptionInfoProvider.overrideWith(() => _Sub())],
      child: MaterialApp(
        home: Scaffold(body: ToolConfirmCard(intent: swapIntent())),
      ),
    ));
    await tester.pump();
  }

  testWidgets('renders the coach-card title, both move lines and the allowance line',
      (tester) async {
    await tester.runAsync(setUpHive);
    await pump(tester);
    expect(find.textContaining('Swap Fri 25 and Sat 26'), findsOneWidget);
    expect(find.textContaining('Pull + Core FRI'), findsOneWidget);
    expect(find.textContaining('Legs + Core SAT'), findsOneWidget);
    expect(find.textContaining('swaps this week'), findsOneWidget);
    await tester.runAsync(tearDownHive);
  });

  testWidgets('shows Apply / Dismiss and the SWAP DAYS header', (tester) async {
    await tester.runAsync(setUpHive);
    await pump(tester);
    expect(find.text('APPLY'), findsOneWidget);
    expect(find.text('DISMISS'), findsOneWidget);
    expect(find.text('SWAP DAYS'), findsOneWidget);
    await tester.runAsync(tearDownHive);
  });

  testWidgets('shows the 3-rest warning line when the swap creates a fresh 3-run',
      (tester) async {
    await tester.runAsync(setUpHive);
    // Exact fixture, re-derived against the REAL DaySwapRules.restRunWarning
    // + _runs algorithm (day_swap_rules.dart, read in full):
    //   beforeSet = union of dates in PRE-swap rest runs of length>=3 only.
    //   flagged   = union of POST-swap rest runs of length>=3 that contain
    //               at least one date NOT in beforeSet.
    // Week Mon21..Sun27: seed Wed23+Thu24(today) as REST (a length-2 run,
    // BELOW the >=3 threshold, so beforeSet is EMPTY), Fri25 stays the base
    // workout, and Sat26 becomes REST (overriding the base setUp's workout
    // row). Swapping Fri<->Sat: Fri's post-swap content is Sat's (rest) ->
    // Fri becomes rest; Sat's post-swap content is Fri's (workout) -> Sat
    // stays non-rest. Post-swap: Wed23,Thu24,Fri25 are all rest — a FRESH
    // 3-run, none of whose dates were in the (empty) beforeSet -> flagged.
    Map<String, dynamic> rest(String date) => {
          'date': date,
          'type': 'rest',
          'workout_name': 'Rest Day',
          'status': 'rest',
          'exercises': <Map<String, dynamic>>[],
        };
    await tester.runAsync(() async {
      final box = HiveService.instance.workoutBox;
      await box.put('schedule_2026-09-23', rest('2026-09-23')); // Wed
      await box.put('schedule_$thu', rest(thu)); // Thu ("today")
      // Fri stays the base setUp's workout row (Pull + Core) — untouched.
      await box.put('schedule_$sat', rest(sat)); // Sat: workout -> rest
    });
    await pump(tester);
    // DaySwapCopy.restRunWarningLine(RestRunWarning(runDates: [Wed,Thu,Fri]))
    // == 'Heads-up: this leaves Wed, Thu and Fri as rest days in a row.'
    expect(
        find.textContaining('Heads-up: this leaves Wed, Thu and Fri as rest days in a row.'),
        findsOneWidget);
    await tester.runAsync(tearDownHive);
  });
}
