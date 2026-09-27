// HARNESS NOTE (GoogleFonts pitfall, root CLAUDE.md §4.9 "A widget test that
// mocks path_provider makes GoogleFonts fail LOUDLY"): the FIRST test below
// is a typography warmup that runs BEFORE setUpHiveForTests ever installs
// the path_provider mock (that mock is scoped to the group below, which has
// its own local setUp/tearDown — this outer test is untouched by it).
// GoogleFonts caches per family+weight, so the warmup renders every family
// this file reaches — including SwapPickerSheet, which one test opens.
// Reference: test/widgets/compass_redesign_test.dart,
// test/widgets/swap_picker_sheet_test.dart.
//
// @Timeout + library (root CLAUDE.md §4.9 + .claude/skills/debugging/SKILL.md
// §2.73 widget-test-hang class): every real Hive write inside a testWidgets
// body is escaped via tester.runAsync — a bare `await box.put` directly in a
// testWidgets body can hang the fake-async zone for 20+ minutes straight
// through --timeout, which this batch's Tasks 24/27 hit literally.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

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
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/train/widgets/day_swap_row_trailing.dart';

import '../helpers/hive_test_setup.dart';

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
        {String status = 'planned', bool isSwapped = false}) =>
    {
      'date': date,
      'type': 'workout',
      'workout_name': name,
      'status': status,
      'is_swapped': isSwapped,
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
          Text('d', style: AppTypography.body),
        ]),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    // Quiet-degrade expected — no exception escapes (path_provider mock is
    // NOT installed in this test).
    expect(find.text('a'), findsOneWidget);
  });

  group('DaySwapRowTrailing', () {
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
      HiveService.instance.configBox.delete('disable_day_swap_train_ui');
      resetTestClock();
      await tearDownHiveForTests(dir);
    });

    Future<void> pump(WidgetTester tester, String date,
        {bool isPro = true}) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [subscriptionInfoProvider.overrideWith(() => _Sub(isPro))],
        child:
            MaterialApp(home: Scaffold(body: DaySwapRowTrailing(date: date))),
      ));
      await tester.pump();
    }

    testWidgets('shows the ⇅ affordance on a movable day', (tester) async {
      await pump(tester, fri);
      expect(find.byIcon(Icons.swap_vert), findsOneWidget);
      expect(find.bySemanticsLabel(DaySwapCopy.swapSemanticsLabel(fri)),
          findsOneWidget);
    });

    testWidgets('hides the ⇅ affordance on a completed day', (tester) async {
      await pump(tester, sat);
      expect(find.byIcon(Icons.swap_vert), findsNothing);
    });

    testWidgets('hides the ⇅ affordance when the kill switch is set',
        (tester) async {
      await tester.runAsync(() => HiveService.instance.configBox
          .put('disable_day_swap_train_ui', true));
      await pump(tester, fri);
      expect(find.byIcon(Icons.swap_vert), findsNothing);
    });

    testWidgets('tapping ⇅ opens the shared picker', (tester) async {
      await pump(tester, fri);
      await tester.tap(find.byIcon(Icons.swap_vert));
      await tester.pumpAndSettle();
      expect(find.text(DaySwapCopy.pickerTitle(fri)), findsOneWidget);
    });

    testWidgets('shows the MOVED tag for a swapped, not-yet-completed day',
        (tester) async {
      await tester.runAsync(() => HiveService.instance.workoutBox
          .put('schedule_$fri', workout(fri, 'Legs + Core', isSwapped: true)));
      await pump(tester, fri);
      expect(find.text(DaySwapCopy.movedTag), findsOneWidget);
    });

    testWidgets('the MOVED tag stays even when the kill switch is set',
        (tester) async {
      await tester.runAsync(() => HiveService.instance.workoutBox
          .put('schedule_$fri', workout(fri, 'Legs + Core', isSwapped: true)));
      await tester.runAsync(() => HiveService.instance.configBox
          .put('disable_day_swap_train_ui', true));
      await pump(tester, fri);
      expect(find.text(DaySwapCopy.movedTag), findsOneWidget);
      expect(find.byIcon(Icons.swap_vert), findsNothing);
    });
  });
}
