// BEHAVIORAL TEST — Unit 3D-b (OI-175, d57): "Keep training Phase 1" is the
// Monday-aligned hold week, always on.
//
// Concept:  hold_week_materialization (+ the covered rule every hold reader shares)
// Writer:   lib/core/services/workout_schedule_write_service.dart holdWeek() / _holdWeekLocked()
// Readers:  lib/core/services/workout_schedule_read_service.dart latestCoveredHoldDate(),
//           maxCoveredHoldOrdinalBefore(), holdWeeks(), holdOrdinalForDate()
// Plan:     docs/plans/2026-11-16-generator-step3d-hold-weeks.md section 2.1, section 3
//
// Real Hive; `nowWall()` pinned through its seam. The two callers (the widget
// half) are tested in test/features/train/hold_week_callers_test.dart.
@Timeout(Duration(minutes: 4))
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/app_events_service.dart';
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

const _user = 'aaaaaaaa-bbbb-cccc-dddd-0000000003d7';

WorkoutScheduleWriteService get _write => WorkoutScheduleWriteService.instance;
WorkoutScheduleReadService get _read => WorkoutScheduleReadService.instance;

Map? _row(DateTime d) {
  final raw = HiveService.instance.workoutBox.get('schedule_${formatDateKey(d)}');
  return raw is Map ? raw : null;
}

int _holdRowCount() => HiveService.instance.workoutBox.values
    .where((v) => v is Map && v['is_hold'] == true)
    .length;

DateTime _planEnd() => DateTime.parse(MigratedKey.read<String>('plan_end_date')!);

int _events(String name) =>
    AppEventsService.debugCapture!.where((e) => e.event == name).length;

/// Seeds a 4-week plan from [start] (a Monday): plan_start, plan_end (+27) and
/// 28 planned rows, each carrying `src_week` so a test can see which week a
/// hold copied (week 3 = Peak, week 4 = deload).
Future<void> _seedPlan(DateTime start) async {
  await MigratedKey.write('plan_start_date', start.toIso8601String());
  await MigratedKey.write(
      'plan_end_date', start.add(const Duration(days: 27)).toIso8601String());
  for (var week = 1; week <= 4; week++) {
    for (var d = 0; d < 7; d++) {
      final date = start.add(Duration(days: (week - 1) * 7 + d));
      await WorkoutWriteService.instance.upsertScheduled(
        date: date,
        entry: {
          'type': d == 6 ? 'rest' : 'workout',
          'date': formatDateKey(date),
          'week': week,
          'phase': 1,
          'src_week': week,
          'status': d == 6 ? 'rest' : 'planned',
          'exercises': <Map<String, dynamic>>[
            {'name': 'Squat', 'sets': 3, 'reps': 5, 'weight': 100.0 + week},
          ],
        },
        source: WriteSource.schedSwap,
      );
    }
  }
}

Future<void> _clearSchedule() async {
  final box = HiveService.instance.workoutBox;
  for (final k in box.keys
      .where((k) => k.toString().startsWith('schedule_'))
      .toList()) {
    await box.delete(k);
  }
}

/// A hand-written hold row (the shape `holdWeek` writes).
Future<void> _putHoldRow(DateTime date, int ordinal) async {
  await HiveService.instance.workoutBox.put('schedule_${formatDateKey(date)}', {
    'type': 'workout',
    'date': formatDateKey(date),
    'week': 4 + ordinal,
    'phase': 1,
    'status': 'planned',
    'is_hold': true,
    'hold_ordinal': ordinal,
    'exercises': const <Map<String, dynamic>>[],
  });
}

void main() {
  late Directory tempDir;

  // plan_start Monday 2026-06-01; plan_end Sunday 2026-06-28.
  final planStart = DateTime(2026, 6, 1);
  final week4Thursday = DateTime(2026, 6, 25, 10);
  final week4Sunday = DateTime(2026, 6, 28, 10);
  final h1Monday = DateTime(2026, 6, 29);
  final h1Sunday = DateTime(2026, 7, 5);
  final h2Monday = DateTime(2026, 7, 6);

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('hold_d57_');
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
    WorkoutScheduleWriteService.debugHoldRowWrite = null;
    AppEventsService.debugCapture = null;
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('holdWeek: the write (section 2.1)', () {
    setUp(() async {
      await HiveUserSession.openForUser(_user);
      AppEventsService.debugCapture = [];
      await _seedPlan(planStart);
    });

    tearDown(() async {
      // Round 4 F5: the static row-write hook must never leak into the next test.
      WorkoutScheduleWriteService.debugHoldRowWrite = null;
      AppEventsService.debugCapture = null;
      resetTestClock();
      await _clearSchedule();
      await HiveUserSession.closeAll();
    });

    test('no flag set: the free-tier write is the hold (written, H1 = Peak, week 5)',
        () async {
      expect(HiveService.instance.configBox.get('enable_hold_weeks'), isNull);
      setTestClockTo(DateTime(2026, 6, 30, 9)); // Tuesday after plan_end
      expect(await _write.holdWeek(), HoldWeekOutcome.written);
      final mon = _row(h1Monday)!;
      expect(mon['is_hold'], true);
      expect(mon['hold_ordinal'], 1);
      expect(mon['week'], 5);
      expect(mon['src_week'], 3);
      expect(_planEnd(), h1Sunday);
      expect(_events('hold_week_started'), 1);
    });

    test('the double tap AFTER expiry: the second call writes nothing', () async {
      setTestClockTo(DateTime(2026, 6, 29, 9));
      expect(await _write.holdWeek(), HoldWeekOutcome.written);
      setTestClockTo(DateTime(2026, 7, 1, 20)); // two days later, same week
      expect(await _write.holdWeek(), HoldWeekOutcome.alreadyHolding);
      expect(_row(h2Monday), isNull, reason: 'no H2 written early');
      expect(_planEnd(), h1Sunday);
      expect(_events('hold_week_started'), 1);
      expect(_holdRowCount(), 7);
    });

    test('the double tap BEFORE expiry (graduation, Thursday of week 4)', () async {
      setTestClockTo(week4Thursday);
      expect(await _write.holdWeek(), HoldWeekOutcome.written,
          reason: 'the first tap writes H1 for NEXT week');
      expect(_row(h1Monday)!['hold_ordinal'], 1);
      expect(await _write.holdWeek(), HoldWeekOutcome.alreadyHolding,
          reason: 'before 3D-b the second tap wrote H2 the week after');
      expect(_row(h2Monday), isNull);
      expect(_events('hold_week_started'), 1);
    });

    test('a graduation tap on week 4\'s Sunday writes H1 for the next week',
        () async {
      setTestClockTo(week4Sunday);
      expect(await _write.holdWeek(), HoldWeekOutcome.written);
      expect(_row(h1Monday)!['hold_ordinal'], 1);
      expect(_row(DateTime(2026, 6, 28))!['is_hold'], isNull,
          reason: 'week 4 is never overwritten');
      expect(await _write.holdWeek(), HoldWeekOutcome.alreadyHolding);
    });

    test('a tap on H1\'s Sunday is alreadyHolding', () async {
      setTestClockTo(DateTime(2026, 6, 29, 9));
      await _write.holdWeek();
      setTestClockTo(DateTime(2026, 7, 5, 21));
      expect(await _write.holdWeek(), HoldWeekOutcome.alreadyHolding);
      expect(_row(h2Monday), isNull);
    });

    test('the Monday after H1 writes H2; after H2 the next is H3 (max, not min)',
        () async {
      setTestClockTo(DateTime(2026, 6, 29, 9));
      await _write.holdWeek();
      setTestClockTo(DateTime(2026, 7, 6, 9));
      expect(await _write.holdWeek(), HoldWeekOutcome.written);
      expect(_row(h2Monday)!['hold_ordinal'], 2);
      expect(_row(h2Monday)!['week'], 6);
      setTestClockTo(DateTime(2026, 7, 13, 9));
      expect(await _write.holdWeek(), HoldWeekOutcome.written);
      expect(_row(DateTime(2026, 7, 13))!['hold_ordinal'], 3);
      expect(_read.maxCoveredHoldOrdinalBefore(DateTime(2026, 7, 20)), 3);
    });

    test('the clock seam set back one week after H1: alreadyHolding, nothing written',
        () async {
      setTestClockTo(DateTime(2026, 6, 29, 9));
      await _write.holdWeek();
      setTestClockTo(DateTime(2026, 6, 23, 9)); // a week earlier (week 4)
      expect(await _write.holdWeek(), HoldWeekOutcome.alreadyHolding);
      expect(_holdRowCount(), 7);
    });

    test('a crash-partial hold retried the SAME week: same n, the whole week, plan_end moved',
        () async {
      // Three H1 rows written, plan_end not moved (the crash).
      for (var d = 0; d < 3; d++) {
        await _putHoldRow(h1Monday.add(Duration(days: d)), 1);
      }
      expect(_read.holdWeeks(), isEmpty, reason: 'uncovered rows are not a hold');
      setTestClockTo(DateTime(2026, 6, 30, 9));
      expect(await _write.holdWeek(), HoldWeekOutcome.written,
          reason: 'uncovered rows never trip the guard (`<`, not `<=`, on the ordinal too)');
      expect(_row(h1Monday)!['hold_ordinal'], 1);
      expect(_holdRowCount(), 7);
      expect(_planEnd(), h1Sunday);
    });

    test('a crash-partial hold retried a week LATER: n = 1, the orphan rows invisible',
        () async {
      for (var d = 0; d < 3; d++) {
        await _putHoldRow(h1Monday.add(Duration(days: d)), 1);
      }
      setTestClockTo(DateTime(2026, 7, 7, 9)); // Tuesday of the next week
      expect(await _write.holdWeek(), HoldWeekOutcome.written);
      expect(_row(h2Monday)!['hold_ordinal'], 1,
          reason: 'before 3D-b the orphans made this H2');
      final holds = _read.holdWeeks();
      expect(holds, hasLength(1));
      expect(holds.single.ordinal, 1);
      expect(holds.single.weekStart, h2Monday,
          reason: 'the orphan rows were never covered when the ordinal was decided, so '
              'they did not count; the hold is the new week');
    });

    test('orphans of a crash a week earlier: a planned one is deleted, a completed one keeps its row '
        'without the hold stamps (found in the 3D-b build)', () async {
      await _putHoldRow(h1Monday, 1); // planned orphan
      await HiveService.instance.workoutBox.put('schedule_${formatDateKey(DateTime(2026, 6, 30))}', {
        'type': 'workout',
        'date': '2026-06-30',
        'week': 5,
        'status': 'completed',
        'workout_name': 'Trained on the orphan',
        'is_hold': true,
        'hold_ordinal': 1,
        'exercises': const <Map<String, dynamic>>[],
      });
      setTestClockTo(DateTime(2026, 7, 7, 9));
      expect(await _write.holdWeek(), HoldWeekOutcome.written);
      expect(_row(h1Monday), isNull, reason: 'the planned orphan is gone');
      final kept = _row(DateTime(2026, 6, 30))!;
      expect(kept['status'], 'completed');
      expect(kept['workout_name'], 'Trained on the orphan');
      expect(kept.containsKey('is_hold'), isFalse);
      expect(kept.containsKey('hold_ordinal'), isFalse);
      final hold = _read.holdWeeks().single;
      expect(hold.weekStart, h2Monday);
      expect(hold.ordinal, 1);
      expect(_read.holdOrdinalForDate(DateTime(2026, 6, 30)), isNull);
    });

    test('an earlier phase\'s hold rows (dated before plan_start) do not raise n',
        () async {
      for (var d = 0; d < 7; d++) {
        await _putHoldRow(DateTime(2026, 4, 6).add(Duration(days: d)), 5);
      }
      setTestClockTo(DateTime(2026, 6, 29, 9));
      expect(await _write.holdWeek(), HoldWeekOutcome.written);
      expect(_row(h1Monday)!['hold_ordinal'], 1);
    });

    test('a failed row write (the third of seven): failed, plan_end unmoved, a retry writes the week',
        () async {
      var calls = 0;
      WorkoutScheduleWriteService.debugHoldRowWrite = (date, entry) async {
        calls++;
        if (calls == 3) return WriteResult.fail('disk full');
        return WorkoutWriteService.instance.upsertScheduled(
            date: date, entry: entry, source: WriteSource.schedSwap);
      };
      setTestClockTo(DateTime(2026, 6, 29, 9));
      expect(await _write.holdWeek(), HoldWeekOutcome.failed);
      expect(calls, 3, reason: 'the loop stops at the failure');
      expect(_planEnd(), DateTime(2026, 6, 28));
      expect(_events('hold_week_started'), 0);
      expect(_read.holdWeeks(), isEmpty, reason: 'the two written rows are uncovered');

      WorkoutScheduleWriteService.debugHoldRowWrite = null;
      expect(await _write.holdWeek(), HoldWeekOutcome.written);
      expect(_holdRowCount(), 7);
      expect(_row(h1Monday)!['hold_ordinal'], 1);
      expect(_planEnd(), h1Sunday);
    });

    test('a completed day on the target Monday keeps its content and gains the hold stamps',
        () async {
      await HiveService.instance.workoutBox.put('schedule_${formatDateKey(h1Monday)}', {
        'type': 'workout',
        'date': formatDateKey(h1Monday),
        'workout_name': 'My Template Day',
        'status': 'completed',
        'completed_at': '2026-06-29T08:00:00.000',
        'exercises': [
          {'name': 'Deadlift', 'sets': 5, 'reps': 3},
        ],
      });
      setTestClockTo(DateTime(2026, 7, 1, 9));
      expect(await _write.holdWeek(), HoldWeekOutcome.written);
      final mon = _row(h1Monday)!;
      expect(mon['status'], 'completed');
      expect(mon['workout_name'], 'My Template Day');
      expect(mon['completed_at'], '2026-06-29T08:00:00.000');
      expect(((mon['exercises'] as List).single as Map)['name'], 'Deadlift');
      expect(mon['is_hold'], true);
      expect(mon['hold_ordinal'], 1);
      expect(mon['week'], 5);
      expect(mon['src_week'], isNull, reason: 'not the Peak copy');
      // The week stays 7 contiguous hold days.
      final hold = _read.holdWeeks().single;
      expect(hold.weekStart, h1Monday);
      expect(hold.isCompleted, isTrue, reason: 'the H chip shows its tick at once');
      expect(_read.holdOrdinalForDate(h1Monday), 1);
    });

    test('a completed day on TODAY\'s target date: holdOrdinalForDate(today) holds',
        () async {
      final today = DateTime(2026, 7, 2);
      await HiveService.instance.workoutBox.put('schedule_${formatDateKey(today)}', {
        'type': 'workout',
        'date': formatDateKey(today),
        'workout_name': 'Coach Log',
        'status': 'completed',
        'exercises': const <Map<String, dynamic>>[],
      });
      setTestClockTo(DateTime(2026, 7, 2, 18));
      expect(await _write.holdWeek(), HoldWeekOutcome.written);
      expect(_row(today)!['workout_name'], 'Coach Log');
      expect(_row(today)!['status'], 'completed');
      expect(_read.holdOrdinalForDate(today), 1);
      expect(_read.activeHoldOrdinalFor(nowWall()), 1);
    });

    test('a planned (not completed) target row takes the Peak copy', () async {
      await HiveService.instance.workoutBox.put('schedule_${formatDateKey(h1Monday)}', {
        'type': 'workout',
        'date': formatDateKey(h1Monday),
        'workout_name': 'Scheduled Template',
        'status': 'planned',
        'exercises': const <Map<String, dynamic>>[],
      });
      setTestClockTo(DateTime(2026, 6, 29, 9));
      await _write.holdWeek();
      expect(_row(h1Monday)!['src_week'], 3);
      expect(_row(h1Monday)!['status'], 'planned');
    });

    test('noPlan: no plan_start -> noPlan, nothing written, no event', () async {
      await MigratedKey.delete('plan_start_date');
      setTestClockTo(DateTime(2026, 6, 29, 9));
      expect(await _write.holdWeek(), HoldWeekOutcome.noPlan);
      expect(_holdRowCount(), 0);
      expect(_events('hold_week_started'), 0);
    });

    test('inFlight: a second call while the first is writing returns inFlight',
        () async {
      final gate = Completer<void>();
      WorkoutScheduleWriteService.debugHoldRowWrite = (date, entry) async {
        await gate.future;
        return WorkoutWriteService.instance.upsertScheduled(
            date: date, entry: entry, source: WriteSource.schedSwap);
      };
      setTestClockTo(DateTime(2026, 6, 29, 9));
      final first = _write.holdWeek();
      expect(await _write.holdWeek(), HoldWeekOutcome.inFlight);
      gate.complete();
      expect(await first, HoldWeekOutcome.written);
      expect(_events('hold_week_started'), 1);
    });

    test('read cost: one _holdDatesByOrdinal walk on a 3,000-row box (recorded only)',
        () async {
      final box = HiveService.instance.workoutBox;
      // 365 schedule rows (the seeded 28 + 337 more) and wlog / exlog rows.
      for (var i = 0; i < 337; i++) {
        final d = DateTime(2025, 1, 1).add(Duration(days: i));
        await box.put('schedule_${formatDateKey(d)}', {'type': 'workout', 'status': 'planned'});
      }
      for (var i = 0; i < 2635; i++) {
        await box.put('exlog_x_$i', {'exercise_name': 'Squat', 'sets': 3});
      }
      setTestClockTo(DateTime(2026, 6, 29, 9));
      await _write.holdWeek();
      final sw = Stopwatch()..start();
      const runs = 20;
      for (var i = 0; i < runs; i++) {
        _read.holdWeeks();
      }
      sw.stop();
      final perCall = sw.elapsedMicroseconds / runs / 1000;
      // ignore: avoid_print
      print('[d57 read cost] keys=${box.length} holdWeeks() ${perCall.toStringAsFixed(2)} ms/call');
      for (final k in box.keys.where((k) => k.toString().startsWith('exlog_x_')).toList()) {
        await box.delete(k);
      }
    });
  });

  group('the covered rule: plan_end compared by DATE (round 3 A-F2, round 4 F7)', () {
    setUp(() async {
      await HiveUserSession.openForUser(_user);
      await MigratedKey.write('plan_start_date', DateTime(2026, 9, 28).toIso8601String());
      // One H1 week, Monday 2026-10-26 .. Sunday 2026-11-01.
      for (var d = 0; d < 7; d++) {
        await _putHoldRow(DateTime(2026, 10, 26).add(Duration(days: d)), 1);
      }
    });

    tearDown(() async {
      await _clearSchedule();
      await HiveUserSession.closeAll();
    });

    test('a plan_end stored with a time of day still covers the hold\'s Sunday', () async {
      await MigratedKey.write('plan_end_date', '2026-11-01T18:30:00.000');
      expect(_read.holdOrdinalForDate(DateTime(2026, 11, 1)), 1);
      expect(_read.latestCoveredHoldDate(), DateTime(2026, 11, 1));
    });

    test('a UTC "Z" plan_end 2026-11-01T18:30:00.000Z covers the Sunday (no toLocal)', () async {
      await MigratedKey.write('plan_end_date', '2026-11-01T18:30:00.000Z');
      expect(_read.holdOrdinalForDate(DateTime(2026, 11, 1)), 1);
      expect(_read.holdWeeks().single.weekStart, DateTime(2026, 10, 26));
    });

    test('a UTC "Z" plan_end 2026-10-31T18:30:00.000Z drops the Sunday (documented)', () async {
      await MigratedKey.write('plan_end_date', '2026-10-31T18:30:00.000Z');
      expect(_read.holdOrdinalForDate(DateTime(2026, 11, 1)), isNull);
      expect(_read.holdOrdinalForDate(DateTime(2026, 10, 31)), 1);
    });

    test('rows past plan_end are not covered; rows before plan_start are not either', () async {
      await MigratedKey.write('plan_end_date', '2026-10-28T00:00:00.000');
      expect(_read.latestCoveredHoldDate(), DateTime(2026, 10, 28));
      await MigratedKey.write('plan_start_date', DateTime(2026, 11, 2).toIso8601String());
      await MigratedKey.write('plan_end_date', '2026-11-29T00:00:00.000');
      expect(_read.holdWeeks(), isEmpty);
      expect(_read.maxCoveredHoldOrdinalBefore(DateTime(2026, 11, 30)), 0);
    });
  });
}
