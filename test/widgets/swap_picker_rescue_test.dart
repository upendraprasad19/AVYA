// OI-348 P3 (docs/plans/oi348-landing3d.md §3.6): the shared day-swap picker
// with the missed-day rescue. A missed day pairs ONLY with today (a rest day);
// a locked SOURCE day says so instead of listing targets (the Home long-press
// opened the picker on any day); the footer and the refund toast line.
//
// Harness: same as test/widgets/swap_picker_sheet_test.dart (typography warmup
// before any Hive mock; real engine I/O through tester.runAsync + pumpUntil).
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_allowance.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_copy.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_result.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_rules.dart';
import 'package:icanbefitter/core/services/day_swap/missed_day_rescue_flag.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/swap_service.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/train/widgets/swap_picker_sheet.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

import '../helpers/hive_test_setup.dart';

// Week of Mon 21 - Sun 27 Sep 2026; "today" is Fri 25 (a rest day).
const tue = '2026-09-22';
const wed = '2026-09-23';
const fri = '2026-09-25';
const sat = '2026-09-26';

class _Sub extends SubscriptionInfoNotifier {
  _Sub(this.pro);
  final bool pro;
  @override
  SubscriptionInfoData build() => SubscriptionInfoData(isPro: pro);
}

Map<String, dynamic> workout(String date, String name) => {
      'date': date,
      'type': 'workout',
      'workout_name': name,
      'status': 'planned',
      'exercises': [
        {'exercise_name': '$name A', 'sets': 3}
      ],
    };

Map<String, dynamic> rest(String date) => {
      'date': date,
      'type': 'rest',
      'workout_name': 'Rest Day',
      'status': 'rest',
      'exercises': <Map<String, dynamic>>[],
    };

Future<void> pumpUntil(WidgetTester tester, bool Function() condition,
    {required String timeoutMessage}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail(timeoutMessage);
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets('typography warmup', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Text('a', style: AppTypography.h3),
          Text('b', style: AppTypography.bodySm),
          Text('c', style: AppTypography.monoXs),
          Text('d', style: AppTypography.body),
          Text('e', style: AppTypography.h1),
          const WardButton(label: 'x', onPressed: null),
          const WardChip(label: 'PAST', tone: WardChipTone.neutral),
        ]),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('a'), findsOneWidget);
  });

  test('pairLock: a past day pairs only with today', () {
    expect(DaySwapRules.pairLock(wed, fri, fri), isNull);
    expect(DaySwapRules.pairLock(fri, wed, fri), isNull);
    expect(DaySwapRules.pairLock(fri, sat, fri), isNull);
    expect(DaySwapRules.pairLock(sat, '2026-09-27', fri), isNull);
    expect(DaySwapRules.pairLock(wed, sat, fri)?.date, wed);
    expect(DaySwapRules.pairLock(sat, wed, fri)?.date, wed);
    expect(DaySwapRules.pairLock(tue, wed, fri)?.date, tue);
    expect(DaySwapRules.pairLock(wed, sat, fri)?.reason, DaySwapRefusal.past);
  });

  group('SwapPickerSheet rescue', () {
    late Directory dir;

    setUp(() async {
      dir = await setUpHiveForTests();
      setTestClockTo(DateTime.utc(2026, 9, 25, 4, 30)); // Fri 25, 10:00 IST
      ErrorTelemetry.debugOnLogEventForTests = (op, {message}) {};
      ErrorTelemetry.debugOnRecordNonFatalForTests =
          (e, st, {required reason, extra}) {};
      DaySwapAllowance.debugConsumeForTests = (_) async => null;
      SwapService.debugOnPlanPushForTests = () {};
      final box = HiveService.instance.workoutBox;
      await box.put('schedule_$tue', rest(tue));
      await box.put('schedule_$wed', workout(wed, 'Legs'));
      await box.put('schedule_$fri', rest(fri));
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

    DaySwapResult? captured;

    Future<void> openPicker(WidgetTester tester, String sourceDate) async {
      captured = null;
      await tester.pumpWidget(ProviderScope(
        overrides: [subscriptionInfoProvider.overrideWith(() => _Sub(false))],
        child: MaterialApp(
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
    }

    Finder button(String a, String b) =>
        find.text(DaySwapCopy.pickerButton(a, b).toUpperCase());

    testWidgets('from today (rest): the missed Wed and Sat are both pickable',
        (tester) async {
      await openPicker(tester, fri);
      await tester.tap(find.text('Legs'));
      await tester.pumpAndSettle();
      expect(button(fri, wed), findsOneWidget);
      await tester.tap(find.text('Legs + Core'));
      await tester.pumpAndSettle();
      expect(button(fri, sat), findsOneWidget);
      expect(find.text(DaySwapCopy.pickerFooterRescue), findsOneWidget);
    });

    testWidgets('from the missed Wed: only today; Sat says TODAY ONLY',
        (tester) async {
      await openPicker(tester, wed);
      await tester.tap(find.text('Legs + Core'));
      await tester.pumpAndSettle();
      expect(button(wed, sat), findsNothing);
      // B-pass F5: Sat is not past (its chip says TODAY ONLY); past days
      // still say PAST.
      expect(find.text(DaySwapCopy.pickerTodayOnlyChip), findsOneWidget);
      expect(find.text('PAST'), findsWidgets);
      await tester.tap(find.textContaining('· ${DaySwapCopy.pickerTodayTag}'));
      await tester.pumpAndSettle();
      expect(button(wed, fri), findsOneWidget);
    });

    testWidgets('from Sat: the missed Wed is not pickable', (tester) async {
      await openPicker(tester, sat);
      await tester.tap(find.text('Legs'));
      await tester.pumpAndSettle();
      expect(button(sat, wed), findsNothing);
    });

    testWidgets('a locked source says why and lists no day', (tester) async {
      await openPicker(tester, tue); // a past rest day
      expect(find.text(DaySwapCopy.sourceLockedLine(DaySwapRefusal.past, tue)),
          findsOneWidget);
      expect(find.text('Legs'), findsNothing);
      expect(find.text('Legs + Core'), findsNothing);
    });

    testWidgets('kill switch: the old footer, and Wed stays put',
        (tester) async {
      // Real disk I/O must run outside the fake-async zone (CLAUDE.md 4.9).
      await tester.runAsync(() => HiveService.instance.configBox
          .put(kDisableMissedDayRescueKey, true));
      await openPicker(tester, fri);
      expect(find.text(DaySwapCopy.pickerFooter), findsOneWidget);
      await tester.tap(find.text('Legs'));
      await tester.pumpAndSettle();
      expect(button(fri, wed), findsNothing);
    });

    testWidgets('a rescue that gives the freeze back says so in the toast',
        (tester) async {
      await tester.runAsync(() => HiveService.instance.userBox.put('progress', {
            'streak_freezes_available': 0,
            'streak_freeze_used_dates': [wed],
            'streak_freezes_last_refill': '2026-09-21',
          }));
      await openPicker(tester, fri);
      await tester.tap(find.text('Legs'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(button(fri, wed));
      });
      await pumpUntil(
        tester,
        () => find.byType(SwapPickerSheet).evaluate().isEmpty &&
            captured != null,
        timeoutMessage: 'the picker did not pop after the rescue',
      );
      await tester.pump();
      expect(captured, isA<DaySwapDone>());
      expect((captured! as DaySwapDone).freezeRefunded, isTrue);
      expect(find.textContaining(DaySwapCopy.freezeRefundedLine),
          findsOneWidget);
    });
  });
}
