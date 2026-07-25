// BEHAVIORAL TEST — hold_display_read_path (free-tier "Hold the Line" display)
//
// Concept:  hold_display_read_path
// Writer:   lib/core/services/workout_schedule_write_service.dart holdWeek()
//           (stamps `is_hold` / `hold_ordinal` on each schedule_* row)
// Reader:   lib/core/services/workout_schedule_read_service.dart
//           holdWeeks() / holdOrdinalForDate() / holdWeekSessionProgress()
//           → HoldStatusData (train_provider) → HoldChipGroup / plan header /
//             HoldRoadmapStrip / plan_expired_card
//
// Every hold is materialized by calling the REAL holdWeek() writer, so these
// assertions fail if the writer's field names or cadence drift from what the
// display reads — the recurring writer/reader-drift class. A hand-built fixture
// would keep passing through exactly that drift.
//
// Ship-dark evidence (§4.12.4): the final group proves that with
// `enable_hold_weeks` OFF the legacy redoWeek4 path writes NO hold rows, so
// every hold display surface reads empty and the Train screen renders exactly
// as it did before this batch.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_write_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/date_utils.dart' show formatDateKey;
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart'
    show HoldStatusData, holdStatusProvider;
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

void main() {
  late Directory tempDir;
  const fakeUserId = 'aaaaaaaa-bbbb-cccc-dddd-000000000031';

  // plan_start = Monday 2026-06-01; plan_end = +27 = Sunday 2026-06-28.
  final planStart = DateTime(2026, 6, 1);
  final planEnd = planStart.add(const Duration(days: 27));
  // First hold rolls from the Monday after plan_end; each later hold +7d.
  final hold1Start = DateTime(2026, 6, 29);

  // ignore: deprecated_member_use_from_same_package
  final read = WorkoutScheduleReadService.instance;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('holddisplay_read_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.exerciseBoxName);
    await Hive.openBox(HiveService.foodBoxName);
    await Hive.openBox(HiveService.syncBoxName);
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    resetTestClock();
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await HiveUserSession.openForUser(fakeUserId);
    await HiveService.instance.configBox.delete('enable_hold_weeks');
    await MigratedKey.write('plan_start_date', planStart.toIso8601String());
    await MigratedKey.write('plan_end_date', planEnd.toIso8601String());
    for (int week = 1; week <= 4; week++) {
      for (int d = 0; d < 7; d++) {
        final date = planStart.add(Duration(days: (week - 1) * 7 + d));
        await WorkoutWriteService.instance.upsertScheduled(
          date: date,
          entry: {
            'type': 'workout',
            'date': formatDateKey(date),
            'week': week,
            'phase': 1,
            'status': 'planned',
            'workout_name': 'Upper Body',
            'exercises': <Map<String, dynamic>>[
              {'name': 'Squat', 'sets': 3, 'reps': 5, 'weight': 100.0 + week},
            ],
          },
          source: WriteSource.schedSwap,
        );
      }
    }
  });

  tearDown(() async {
    resetTestClock();
    await HiveService.instance.configBox.delete('enable_hold_weeks');
    final box = HiveService.instance.workoutBox;
    for (final k in box.keys
        .where((k) => k.toString().startsWith('schedule_'))
        .toList()) {
      await box.delete(k);
    }
    await HiveUserSession.closeAll();
  });

  /// Materializes [count] consecutive holds, one per week from the Monday
  /// after plan_end — the real user path (open the app during each hold week).
  Future<void> takeHolds(int count) async {
    for (var i = 0; i < count; i++) {
      setTestClockTo(hold1Start.add(Duration(days: 7 * i, hours: 10)));
      await WorkoutScheduleWriteService.instance.holdWeek();
    }
  }

  group('hold display read path', () {
    test('holdWeeks() surfaces the hold the writer just materialized', () async {
      await takeHolds(1);

      final holds = read.holdWeeks();
      expect(holds, hasLength(1));
      expect(holds.single.ordinal, 1);
      expect(holds.single.weekStart, hold1Start,
          reason: 'holds are Monday-backdated by the writer');
      expect(holds.single.isDeload, isFalse, reason: 'hold 1 sources Peak');
      expect(holds.single.isCompleted, isFalse,
          reason: 'freshly materialized rows are all `planned`');
    });

    test('every 4th hold reads as a deload — cadence mirrors the writer',
        () async {
      await takeHolds(4);

      final holds = read.holdWeeks();
      expect(holds.map((h) => h.ordinal), [1, 2, 3, 4],
          reason: 'ordinal-ascending, one entry per hold week');
      expect(holds.map((h) => h.isDeload), [false, false, false, true],
          reason: 'the writer sources the deload week on every 4th hold; '
              'display recomputes it from hold_ordinal (never stored)');
    });

    test('holdOrdinalForDate maps hold dates and only hold dates', () async {
      await takeHolds(2);

      // Every day of hold 1 reports ordinal 1, hold 2 reports 2.
      for (var d = 0; d < 7; d++) {
        expect(read.holdOrdinalForDate(hold1Start.add(Duration(days: d))), 1);
        expect(
            read.holdOrdinalForDate(
                hold1Start.add(Duration(days: 7 + d))),
            2);
      }
      // Original phase weeks are NOT holds.
      expect(read.holdOrdinalForDate(planStart), isNull);
      expect(read.holdOrdinalForDate(planEnd), isNull);
      // A date with no row at all.
      expect(read.holdOrdinalForDate(DateTime(2027, 1, 1)), isNull);
    });

    test('holdWeekSessionProgress counts completed vs scheduled days',
        () async {
      await takeHolds(1);

      expect(read.holdWeekSessionProgress(1), (completed: 0, total: 7),
          reason: 'the seeded phase is 7 workout days/week, none done yet');

      // Complete two days of the hold week. `completed_at` is left null so the
      // read service's completed-in-the-future guard is not triggered.
      for (var d = 0; d < 2; d++) {
        final date = hold1Start.add(Duration(days: d));
        final row = Map<String, dynamic>.from(
            HiveService.instance.workoutBox.get('schedule_${formatDateKey(date)}')
                as Map);
        row['status'] = 'completed';
        await WorkoutWriteService.instance.upsertScheduled(
          date: date,
          entry: row,
          source: WriteSource.schedSwap,
        );
      }

      expect(read.holdWeekSessionProgress(1), (completed: 2, total: 7));
      expect(read.holdWeeks().single.isCompleted, isTrue,
          reason: '≥1 completed day ⇒ ✓, the same rule the W chips use');
      expect(read.holdWeekSessionProgress(99), (completed: 0, total: 0),
          reason: 'unknown ordinal must not throw');
    });

    test('rest days are excluded from the session tally', () async {
      // Make one day of the source Peak week a rest day BEFORE holding, so the
      // hold copies it verbatim.
      final peakRest = planStart.add(const Duration(days: 14));
      await WorkoutWriteService.instance.upsertScheduled(
        date: peakRest,
        entry: {
          'type': 'rest',
          'date': formatDateKey(peakRest),
          'week': 3,
          'phase': 1,
          'status': 'rest',
        },
        source: WriteSource.schedSwap,
      );

      await takeHolds(1);

      expect(read.holdWeekSessionProgress(1), (completed: 0, total: 6),
          reason: 'a rest day is neither completed nor scheduled work');
    });

    test('isDeloadHold mirrors the writer cadence exactly', () {
      // The writer computes `final deload = n % 4 == 0` and never persists it;
      // this pure helper is the display-side half of that contract.
      for (final ordinal in [1, 2, 3, 5, 6, 7, 9]) {
        expect(WorkoutScheduleReadService.isDeloadHold(ordinal), isFalse,
            reason: 'H$ordinal sources Peak');
      }
      for (final ordinal in [4, 8, 12, 16]) {
        expect(WorkoutScheduleReadService.isDeloadHold(ordinal), isTrue,
            reason: 'H$ordinal sources the deload week');
      }
    });

    test('holds are unbounded — no 12-week ceiling on the display read',
        () async {
      await takeHolds(13);

      final holds = read.holdWeeks();
      expect(holds, hasLength(13),
          reason: 'free users may hold indefinitely; the hold readers must not '
              'inherit the 12-week caps other readers apply');
      expect(holds.last.ordinal, 13);
      expect(holds.last.isDeload, isFalse);
      expect(holds[11].ordinal, 12);
      expect(holds[11].isDeload, isTrue, reason: 'H12 is a 4th hold');
    });
  });

  group('ship-dark: enable_hold_weeks OFF', () {
    test('the flag defaults to OFF with no config key written', () {
      expect(HiveService.instance.configBox.get('enable_hold_weeks'), isNull);
      expect(PlanEngineFlags.holdWeeksEnabled, isFalse);
    });

    test(
        'the legacy redoWeek4 path writes NO hold rows, so every hold surface '
        'reads empty', () async {
      expect(PlanEngineFlags.holdWeeksEnabled, isFalse,
          reason: 'this test pins the OFF branch');

      // What the free-tier triggers call while the flag is OFF.
      // NOTE: redoWeek4 reads raw `DateTime.now()`, NOT the `nowWall()` seam
      // (legacy — see the clock-seam note in free-tier-hold-findings.md), so
      // its roll TARGET is not deterministic under a test clock. Nothing below
      // depends on that date: the property under test is "no hold rows, from
      // any writer, anywhere in the box".
      await WorkoutScheduleWriteService.instance.redoWeek4();

      // The repeat DID happen — plan_end advanced past the original phase.
      final newEnd = DateTime.parse(MigratedKey.read<String>('plan_end_date')!);
      expect(newEnd.isAfter(planEnd), isTrue,
          reason: 'redoWeek4 still rolls the week forward when the flag is OFF');

      // … but NOTHING the hold display reads exists, so every surface keyed on
      // `HoldStatusData.isHolding` / `holds.isNotEmpty` renders nothing:
      // the HOLDING · Hn pill, the SESSIONS readout, HoldChipGroup,
      // HoldRoadmapStrip and the today-card hold branch all no-op.
      final holdRows = HiveService.instance.workoutBox
          .toMap()
          .entries
          .where((e) =>
              e.key.toString().startsWith('schedule_') &&
              e.value is Map &&
              (e.value as Map)['is_hold'] == true)
          .toList();
      expect(holdRows, isEmpty,
          reason: 'the OFF branch must never stamp is_hold on any row');
      expect(read.holdWeeks(), isEmpty);
      expect(read.holdOrdinalForDate(hold1Start), isNull);
      expect(read.holdWeekSessionProgress(1), (completed: 0, total: 0));
    });

    test('HoldStatusData.empty is the inert display contract', () {
      const empty = HoldStatusData.empty;
      expect(empty.isHolding, isFalse);
      expect(empty.todayHoldOrdinal, isNull);
      expect(empty.holds, isEmpty);
      expect(empty.sessionsTotal, 0);
      expect(empty.sessionProgress, 0,
          reason: 'no divide-by-zero on an empty/all-rest week');
    });

    test(
        'holdStatusProvider returns empty EVEN WITH hold rows present when the '
        'flag is OFF (the rollback case)', () async {
      // The realistic ship-dark rollback: the flag was ON, holds were
      // materialized, then it was switched back OFF. Nothing may render.
      await HiveService.instance.configBox.put('enable_hold_weeks', true);
      await takeHolds(2);
      expect(read.holdWeeks(), hasLength(2),
          reason: 'precondition: the rows really are on disk');

      await HiveService.instance.configBox.put('enable_hold_weeks', false);
      expect(PlanEngineFlags.holdWeeksEnabled, isFalse);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final status = container.read(holdStatusProvider);

      expect(status.isHolding, isFalse);
      expect(status.holds, isEmpty,
          reason: 'the flag-OFF early return must fire BEFORE holdWeeks() is '
              'consulted — stale hold rows must not reach any UI surface');
      expect(status.todayHoldOrdinal, isNull);
      expect(status.sessionsTotal, 0);
    });

    test('holdStatusProvider surfaces the live hold when the flag is ON',
        () async {
      await HiveService.instance.configBox.put('enable_hold_weeks', true);
      await takeHolds(1);
      // takeHolds leaves the test clock inside hold 1, so today IS a hold day.

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final status = container.read(holdStatusProvider);

      expect(status.isHolding, isTrue);
      expect(status.todayHoldOrdinal, 1);
      expect(status.holds, hasLength(1));
      expect(status.sessionsTotal, 7);
      expect(status.sessionsCompleted, 0);
      expect(status.sessionProgress, 0);
    });
  });

  group('L1 — a completed hold day must not tick a PHASE II/III week chip', () {
    /// Completes the first workout day of the hold week starting [holdStart]
    /// through the REAL completion writer.
    Future<void> completeFirstHoldDay(DateTime holdStart) async {
      final row = Map<String, dynamic>.from(
          HiveService.instance.workoutBox
              .get('schedule_${formatDateKey(holdStart)}') as Map);
      row['status'] = 'completed';
      await WorkoutWriteService.instance.upsertScheduled(
        date: holdStart,
        entry: row,
        source: WriteSource.schedSwap,
      );
    }

    /// The week index `completedWeekNumbersFrom` would assign to [date] — it
    /// walks `plan_start + 7k`, so this is pure date arithmetic.
    int dateWeekIndex(DateTime date) =>
        date.difference(planStart).inDays ~/ 7 + 1;

    test('CONTIGUOUS hold (starts at plan_end + 1) — would have ticked week 5',
        () async {
      await takeHolds(1);
      expect(dateWeekIndex(hold1Start), 5, reason: 'precondition: week-5 slot');

      await completeFirstHoldDay(hold1Start);

      expect(read.completedWeekNumbers().contains(5), isFalse,
          reason: 'a hold completion must never credit the PHASE II W5 chip');
      expect(read.holdWeeks().single.isCompleted, isTrue,
          reason: 'the H chip keeps its own tick — the exclusion costs nothing');
    });

    test('LATE RETURN hold — lands on week 8, must still not tick', () async {
      // The realistic path: the user lapses, comes back weeks later and taps
      // "Hold the line". holdWeek() places the hold in the calendar week
      // containing TODAY, so it is NOT on the plan_start + 7k grid.
      final lateStart = DateTime(2026, 7, 20); // plan_start + 49 → week 8
      setTestClockTo(lateStart.add(const Duration(hours: 10)));
      await WorkoutScheduleWriteService.instance.holdWeek();

      final holds = read.holdWeeks();
      expect(holds.single.weekStart, lateStart,
          reason: 'hold occupies THIS week, leaving a calendar gap');
      expect(dateWeekIndex(lateStart), 8,
          reason: 'ordinal is 1 but the DATE index is 8 — they are not the same '
              'thing; this is why 4 + ordinal is a label, not a date offset');

      await completeFirstHoldDay(lateStart);

      expect(read.completedWeekNumbers().contains(8), isFalse,
          reason: 'a late hold would otherwise tick a PHASE III chip');
      expect(read.holdWeeks().single.isCompleted, isTrue);
    });

    // ⚠ CHARACTERIZATION, NOT REGRESSION. B-pass verified this case passes
    // with the L1 fix REVERTED — a date-week-15 hold is outside
    // completedWeekNumbersFrom's maxWeek:12 loop either way. It documents WHY
    // the pre-fix bug was intermittent rather than deterministic; the two cases
    // above (CONTIGUOUS, LATE RETURN) are the ones that actually fail without
    // the fix. Kept deliberately, labelled so it can't inflate apparent
    // coverage.
    test('CHARACTERIZATION: a hold beyond maxWeek was never miscounted anyway',
        () async {
      final veryLate = DateTime(2026, 9, 7); // plan_start + 98 → week 15 > 12
      setTestClockTo(veryLate.add(const Duration(hours: 10)));
      await WorkoutScheduleWriteService.instance.holdWeek();
      await completeFirstHoldDay(veryLate);

      expect(dateWeekIndex(veryLate), greaterThan(12));
      expect(read.completedWeekNumbers(), isEmpty,
          reason: 'clipped by maxWeek:12 — proves the pre-fix bug only fired '
              'for holds inside the first 12 date-weeks');
      expect(read.holdWeeks().single.isCompleted, isTrue);
    });

    test('ordinary (non-hold) week completions still tick normally', () async {
      // Regression guard: the exclusion must not break the W-chip ✓.
      final wk2Day = planStart.add(const Duration(days: 7));
      final row = Map<String, dynamic>.from(HiveService.instance.workoutBox
          .get('schedule_${formatDateKey(wk2Day)}') as Map);
      row['status'] = 'completed';
      await WorkoutWriteService.instance.upsertScheduled(
        date: wk2Day,
        entry: row,
        source: WriteSource.schedSwap,
      );

      expect(read.completedWeekNumbers().contains(2), isTrue);
    });
  });

  group('L3 — the REAL completion writer must preserve the hold stamp', () {
    test('markCompleted keeps is_hold + hold_ordinal, so the chip survives '
        'training', () async {
      await takeHolds(1);
      expect(read.holdWeeks(), hasLength(1), reason: 'precondition');

      // Drive the ACTUAL writer, not a hand-built upsertScheduled — a future
      // refactor that rebuilt the row from a template instead of merging in
      // place would silently drop the hold stamp and vanish the H chip.
      final result = await WorkoutWriteService.instance.markCompleted(
        date: hold1Start,
        workoutName: 'Upper Body',
        durationSec: 1800,
      );
      expect(result.success, isTrue, reason: 'Hive write must succeed');

      final raw = HiveService.instance.workoutBox
          .get('schedule_${formatDateKey(hold1Start)}') as Map;
      expect(raw['is_hold'], true, reason: 'the hold stamp must survive');
      expect(raw['hold_ordinal'], 1);
      expect(raw['status'], 'completed');

      final holds = read.holdWeeks();
      expect(holds, hasLength(1),
          reason: 'the hold week is still addressable after training it');
      expect(holds.single.isCompleted, isTrue);
      expect(read.holdWeekSessionProgress(1).completed, 1);
    });
  });

  group('D1 — the deployment banner drops the week counter while holding', () {
    // Source-grep (comments stripped) — the banner is deep in a screen widget
    // tree; this pins BOTH ternary arms exist. The behavioural half is covered
    // by holdStatusProvider's own tests.
    final banner = File('lib/features/train/screens/train/screen.dart')
        .readAsStringSync()
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .replaceAll(RegExp(r'//[^\n]*'), '');

    test('holding arm renders the phase WITHOUT a week counter', () {
      expect(banner.contains('holdStatus.isHolding'), isTrue);
      final holdingArm = RegExp(
          r"holdStatus\.isHolding\s*\?\s*'DEPLOYMENT 01[^']*\$\{plan\.phaseName\.toUpperCase\(\)\}'");
      expect(holdingArm.hasMatch(banner), isTrue,
          reason: 'a hold week sits OUTSIDE the phase 4 weeks — no honest '
              '"WK n OF 4" exists for it; the HOLDING pill owns the identity');
    });

    test('non-holding arm still carries the pinned WK n OF 4 literal', () {
      // phase_relative_week_label_test.dart:62 greps for this exact string.
      expect(banner.contains(r'WK ${plan.currentWeek} OF 4'), isTrue);
    });
  });

  group('hold scoping — holds belong to the phase they extend', () {
    test(
        'a PRO advance (plan_start moves forward) retires the old holds from '
        'the hold strip', () async {
      await takeHolds(2);
      expect(read.holdWeeks(), hasLength(2), reason: 'precondition');

      // Advance to the next phase: plan_start/plan_end move past the holds.
      // The hold ROWS stay on disk (they are real history) — pastPhaseBlocks()
      // owns them from here, under their real phase number.
      final nextStart = DateTime(2026, 7, 20);
      await MigratedKey.write('plan_start_date', nextStart.toIso8601String());
      await MigratedKey.write('plan_end_date',
          nextStart.add(const Duration(days: 27)).toIso8601String());

      expect(read.holdWeeks(), isEmpty,
          reason: 'stale holds must not linger in the current phase strip — '
              'they would also be RELABELLED with the new phase numeral, '
              'double-rendering history under the wrong heading');
      expect(read.holdOrdinalForDate(hold1Start), isNull);
      expect(
          HiveService.instance.workoutBox
              .get('schedule_${formatDateKey(hold1Start)}'),
          isNotNull,
          reason: 'the rows themselves are history and must NOT be deleted');
    });
  });
}
