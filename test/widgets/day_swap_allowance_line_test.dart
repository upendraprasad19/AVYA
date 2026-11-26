// HARNESS NOTE (GoogleFonts pitfall, root CLAUDE.md §4.9 "A widget test that
// mocks path_provider makes GoogleFonts fail LOUDLY"): the FIRST test below
// is a typography warmup that runs BEFORE setUpHiveForTests ever installs
// the path_provider mock (that mock is scoped to the group below, which has
// its own local setUp/tearDown — this outer test is untouched by it).
// GoogleFonts caches per family+weight, so the warmup renders every family
// this file's widget uses. Reference: test/widgets/compass_redesign_test.dart,
// test/widgets/swap_picker_sheet_test.dart.
//
// @Timeout + library (root CLAUDE.md §4.9 + .claude/skills/debugging/SKILL.md
// §2.73 widget-test-hang class): every real Hive write inside a testWidgets
// body is escaped via tester.runAsync — a bare `await box.put` directly in a
// testWidgets body can hang the fake-async zone for 20+ minutes straight
// through --timeout, which this batch's Tasks 24/27 hit literally.
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';

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
import 'package:icanbefitter/features/train/widgets/day_swap_allowance_line.dart';

import '../helpers/hive_test_setup.dart';

// Week of Mon 21 - Sun 27 Sep 2026; "today" is Thu 24.
const mon = '2026-09-21';
const fri = '2026-09-25';

class _Sub extends SubscriptionInfoNotifier {
  _Sub(this.pro);
  final bool pro;
  @override
  SubscriptionInfoData build() => SubscriptionInfoData(isPro: pro);
}

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

  group('DaySwapAllowanceLine', () {
    late Directory dir;

    setUp(() async {
      dir = await setUpHiveForTests();
      setTestClockTo(DateTime.utc(2026, 9, 24, 4, 30)); // Thu 24, 10:00 IST
      ErrorTelemetry.debugOnLogEventForTests = (op, {message}) {};
      ErrorTelemetry.debugOnRecordNonFatalForTests =
          (e, st, {required reason, extra}) {};
      DaySwapAllowance.debugConsumeForTests = (_) async => null;
      SwapService.debugOnPlanPushForTests = () {};
    });

    tearDown(() async {
      ErrorTelemetry.debugOnLogEventForTests = null;
      ErrorTelemetry.debugOnRecordNonFatalForTests = null;
      DaySwapAllowance.debugConsumeForTests = null;
      SwapService.debugOnPlanPushForTests = null;
      unawaited(
          HiveService.instance.configBox.delete('disable_day_swap_train_ui'));
      resetTestClock();
      await tearDownHiveForTests(dir);
    });

    Future<void> pump(WidgetTester tester, {required bool isPro}) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [subscriptionInfoProvider.overrideWith(() => _Sub(isPro))],
        child: const MaterialApp(
          home: Scaffold(body: DaySwapAllowanceLine(anyDateInWeek: fri)),
        ),
      ));
      await tester.pump();
    }

    testWidgets('free tier shows the 1-swap allowance line', (tester) async {
      await pump(tester, isPro: false);
      const expected = DayAllowance(weekStart: mon, used: 0, limit: 1);
      expect(
        find.text(DaySwapCopy.allowanceLine(expected, currentWeekStart: mon)),
        findsOneWidget,
      );
      expect(find.text(DaySwapCopy.allowanceHint), findsOneWidget);
    });

    testWidgets('PRO tier shows the 3-swap allowance line', (tester) async {
      await pump(tester, isPro: true);
      const expected = DayAllowance(weekStart: mon, used: 0, limit: 3);
      expect(
        find.text(DaySwapCopy.allowanceLine(expected, currentWeekStart: mon)),
        findsOneWidget,
      );
    });

    testWidgets('the kill switch hides the whole line', (tester) async {
      await tester.runAsync(() => HiveService.instance.configBox
          .put('disable_day_swap_train_ui', true));
      await pump(tester, isPro: true);
      expect(find.byType(DaySwapAllowanceLine), findsOneWidget);
      expect(find.textContaining('swaps left'), findsNothing);
      expect(find.text(DaySwapCopy.allowanceHint), findsNothing);
    });
  });
}
