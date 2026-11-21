// Unit 3D-b (OI-175, d80; plan docs/plans/2026-11-16-generator-step3d-hold-weeks.md section 2.2):
// the "you are here" marker during a hold.
//
// - `weekChipLit`: the selected week is lit, except during a hold when the user has not picked a week.
// - On the real WeekSelector: during a hold W4 is not lit; a tap on W2 lights W2; a tap on W4 lights W4
//   (tapping the week already shown sets picked); an invalidation clears the pick; the PRO groups are
//   unaffected; the date sub-label shows only on a lit chip.
// - The card word: H1 says Peak and H4 says Deload from the copied stamps; a lifted deload source says Baseline.
@Timeout(Duration(minutes: 3))
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_write_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/date_utils.dart' show formatDateKey;
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/widgets/week_selector.dart';

import 'log_exercise/card_harness.dart';

const _sel2 = SelectedWeek(2);
const _sel4 = SelectedWeek(4);
const _picked4 = SelectedWeek(4, picked: true);
const _picked2 = SelectedWeek(2, picked: true);

/// plan_start Monday 2026-06-01. [characters] stamps each week's rows (index 0 = week 1); [week4Override] lets
/// a test stamp week 4's workout days differently (a lifted deload).
Future<void> _seedPlan({
  List<String> characters = const ['baseline', 'overreach', 'peak', 'deload'],
  String? week4WorkoutOverride,
}) async {
  final start = DateTime(2026, 6, 1);
  await MigratedKey.write('plan_start_date', start.toIso8601String());
  await MigratedKey.write('plan_end_date', start.add(const Duration(days: 27)).toIso8601String());
  for (var week = 1; week <= 4; week++) {
    for (var d = 0; d < 7; d++) {
      final date = start.add(Duration(days: (week - 1) * 7 + d));
      final rest = d == 6;
      var character = characters[week - 1];
      // A lifted deload rewrites only some planned workout rows (deload_evaluator): a mixed week.
      if (week == 4 && !rest && week4WorkoutOverride != null && d < 3) character = week4WorkoutOverride;
      await WorkoutWriteService.instance.upsertScheduled(
        date: date,
        entry: {
          'type': rest ? 'rest' : 'workout',
          'date': formatDateKey(date),
          'week': week,
          'phase': 1,
          'status': rest ? 'rest' : 'planned',
          'week_character': character,
          'exercises': const <Map<String, dynamic>>[],
        },
        source: WriteSource.schedSwap,
      );
    }
  }
}

Future<void> _clear() async {
  final box = HiveService.instance.workoutBox;
  for (final k in box.keys.where((k) => k.toString().startsWith('schedule_')).toList()) {
    await box.delete(k);
  }
  await MigratedKey.delete('plan_start_date');
  await MigratedKey.delete('plan_end_date');
}

Future<void> _takeHolds(int count) async {
  // H1 on the Monday after plan_end, then one per following week.
  for (var i = 0; i < count; i++) {
    setTestClockTo(DateTime(2026, 6, 29 + 7 * i, 10));
    final out = await WorkoutScheduleWriteService.instance.holdWeek();
    expect(out, HoldWeekOutcome.written);
  }
}

/// The chip's own container (the one with the decoration).
BoxDecoration _chipDecoration(WidgetTester tester, int week) {
  final container = tester.widget<Container>(find
      .descendant(of: find.byKey(ValueKey('week-$week')), matching: find.byType(Container))
      .first);
  return container.decoration! as BoxDecoration;
}

bool _lit(WidgetTester tester, int week) => _chipDecoration(tester, week).color == AppColors.accent;

void main() {
  group('weekChipLit (pure)', () {
    test('no hold: the selected week is lit, picked or not', () {
      expect(weekChipLit(week: 4, selected: _sel4, holdingToday: false), isTrue);
      expect(weekChipLit(week: 3, selected: _sel4, holdingToday: false), isFalse);
      expect(weekChipLit(week: 4, selected: _picked4, holdingToday: false), isTrue);
    });

    test('during a hold: the default week is NOT lit; a picked week is', () {
      expect(weekChipLit(week: 4, selected: _sel4, holdingToday: true), isFalse);
      expect(weekChipLit(week: 2, selected: _sel2, holdingToday: true), isFalse);
      expect(weekChipLit(week: 4, selected: _picked4, holdingToday: true), isTrue);
      expect(weekChipLit(week: 2, selected: _picked2, holdingToday: true), isTrue);
      expect(weekChipLit(week: 3, selected: _picked2, holdingToday: true), isFalse);
    });
  });

  testWidgets('fonts degrade before any Hive mock', (tester) async {
    await renderFontsFirst(tester);
    await tester.pumpWidget(MaterialApp(
      home: Column(children: [
        for (final s in [
          AppTypography.titleS,
          AppTypography.bodyM,
          AppTypography.buttonLabel,
          AppTypography.dmSansFamily(),
        ])
          Text('x', style: s),
      ]),
    ));
  });
  tearDownAll(() async {
    resetTestClock();
    await closeHive();
  });

  late ProviderContainer container;

  Future<void> pumpSelector(WidgetTester tester) async {
    container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(builder: (context, ref, _) {
            // The Train screen's wiring (screen.dart): `.week` for the list, the chip tap selects.
            final selected = ref.watch(selectedWeekProvider).week;
            return WeekSelector(
              totalWeeks: 12,
              selectedWeek: selected,
              currentPhase: 1,
              onSelect: (w) => ref.read(selectedWeekProvider.notifier).select(w),
            );
          }),
        ),
      ),
    ));
    await tester.pump();
  }

  Future<void> setUpHolds(WidgetTester tester, int holds, {DateTime? today}) async {
    await ensureHive(tester);
    await tester.runAsync(() async {
      await HiveUserSession.openForUser('aaaaaaaa-bbbb-cccc-dddd-0000000003d8');
      await _seedPlan();
      await _takeHolds(holds);
      if (today != null) setTestClockTo(today);
    });
  }

  Future<void> tearDownHolds(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(_clear);
    resetTestClock();
  }

  testWidgets('during H1: W4 is not lit and has no date label; the H1 chip is today', (tester) async {
    await setUpHolds(tester, 1, today: DateTime(2026, 7, 1, 10));
    await pumpSelector(tester);
    expect(container.read(holdStatusProvider).todayHoldOrdinal, 1);
    expect(container.read(selectedWeekProvider).week, 4);
    for (var w = 1; w <= 4; w++) {
      expect(_lit(tester, w), isFalse, reason: 'W$w must not be gold during a hold');
    }
    expect(find.text('JUN 22–28'), findsNothing, reason: 'an unlit W4 prints no month-old range');
    await tearDownHolds(tester);
  });

  testWidgets('during H1: a tap on W2 lights W2; a tap on W4 lights W4; an invalidation clears the pick',
      (tester) async {
    await setUpHolds(tester, 1, today: DateTime(2026, 7, 1, 10));
    await pumpSelector(tester);

    await tester.tap(find.byKey(const ValueKey('week-2')));
    await tester.pump();
    expect(_lit(tester, 2), isTrue);
    expect(_lit(tester, 4), isFalse);
    expect(find.text('JUN 8–14'), findsOneWidget, reason: 'the lit chip carries its date label');

    container.invalidate(selectedWeekProvider);
    await tester.pump();
    expect(container.read(selectedWeekProvider).picked, isFalse);
    for (var w = 1; w <= 4; w++) {
      expect(_lit(tester, w), isFalse, reason: 'the invalidation cleared the pick');
    }
    // Tapping the default week picks it (picked false -> true): W4 lights.
    await tester.tap(find.byKey(const ValueKey('week-4')));
    await tester.pump();
    expect(container.read(selectedWeekProvider).picked, isTrue);
    expect(_lit(tester, 4), isTrue);
    await tearDownHolds(tester);
  });

  testWidgets('no hold (week 3 today): the default week is lit as before', (tester) async {
    await setUpHolds(tester, 0, today: DateTime(2026, 6, 17, 10));
    await pumpSelector(tester);
    expect(container.read(holdStatusProvider).isHolding, isFalse);
    expect(_lit(tester, 3), isTrue);
    expect(find.text('JUN 15–21'), findsOneWidget);
    await tearDownHolds(tester);
  });

  testWidgets('the PRO groups take holdingToday = false: W5 lights when picked during a hold',
      (tester) async {
    await setUpHolds(tester, 1, today: DateTime(2026, 7, 1, 10));
    await pumpSelector(tester);
    container.read(selectedWeekProvider.notifier).select(5);
    await tester.pump();
    // W5 is a locked chip for a free user: its colours are the lock colours either way, so the pin is that it
    // is not repainted gold and the current group shows nothing lit.
    expect(_chipDecoration(tester, 5).color, AppColors.input);
    for (var w = 1; w <= 4; w++) {
      expect(_lit(tester, w), isFalse);
    }
    await tearDownHolds(tester);
  });

  group('the card word follows the copied stamp (d80)', () {
    testWidgets('H1 says Peak, H4 says Deload', (tester) async {
      await setUpHolds(tester, 4);
      final read = WorkoutScheduleReadService.instance;
      final h1Tue = DateTime(2026, 6, 30);
      final h4Tue = DateTime(2026, 7, 21);
      await tester.runAsync(() async {
        final h1 = read.getScheduleForDate(h1Tue);
        final h4 = read.getScheduleForDate(h4Tue);
        expect(h1?['hold_ordinal'], 1);
        expect(h4?['hold_ordinal'], 4);
        expect(h1?['week_character'], 'peak');
        expect(h4?['week_character'], 'deload');
        expect(read.weekModeForRow(h1, h1Tue), 'Peak');
        expect(read.weekModeForRow(h4, h4Tue), 'Deload');
      });
      await tearDownHolds(tester);
    });

    testWidgets('a lifted deload source: H4 copies the mix, its lifted workout days say Baseline',
        (tester) async {
      await ensureHive(tester);
      await tester.runAsync(() async {
        await HiveUserSession.openForUser('aaaaaaaa-bbbb-cccc-dddd-0000000003d8');
        await _seedPlan(week4WorkoutOverride: 'working');
        await _takeHolds(4);
      });
      final read = WorkoutScheduleReadService.instance;
      await tester.runAsync(() async {
        final mon = read.getScheduleForDate(DateTime(2026, 7, 20));
        final fri = read.getScheduleForDate(DateTime(2026, 7, 24));
        expect(mon?['week_character'], 'working');
        expect(fri?['week_character'], 'deload');
        expect(read.weekModeForRow(mon, DateTime(2026, 7, 20)), 'Baseline');
        expect(read.weekModeForRow(fri, DateTime(2026, 7, 24)), 'Deload');
      });
      await tearDownHolds(tester);
    });
  });
}
