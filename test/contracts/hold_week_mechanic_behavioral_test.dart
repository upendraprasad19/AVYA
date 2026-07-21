// BEHAVIORAL TEST — hold_week_materialization (free-tier "Hold the Line")
//
// Concept:  hold_week_materialization
// Writer:   lib/core/services/workout_schedule_write_service.dart holdWeek()
// Reader:   Hive schedule_* rows + MigratedKey('plan_end_date' / 'plan_start_date')
//
// Pins the mechanic the ×2 review converged on. Each assertion FAILS if the
// mechanic regresses to redoWeek4's behavior:
//   1. First hold sources the PEAK week (plan_start+14), FLAT loads, stamps
//      'week'=4+N / is_hold / hold_ordinal, extends plan_end.  (not the
//      trailing/deload week; not 'week_number'; no decay)
//   2. rollStart is a Monday and a whole number of weeks from plan_start.
//   3. Every 4th hold sources the DELOAD week (plan_start+21).
//   4. Ordinal is gap-proof — a late return counts holds taken, not span.
//   5. Crash-idempotent — a partial hold at rollStart recomputes the SAME
//      ordinal on retry (no deload-cadence drift).
//   6. holdWeek NEVER writes plan_start (the #6 phantom-phase constraint).
//   7. A concurrent double-call yields exactly ONE hold.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
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

void main() {
  late Directory tempDir;
  const fakeUserId = 'aaaaaaaa-bbbb-cccc-dddd-000000000021';

  // plan_start = Monday 2026-06-01; plan_end = +27 = Sunday 2026-06-28.
  final planStart = DateTime(2026, 6, 1);
  final planEnd = planStart.add(const Duration(days: 27));

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('holdweek_behavioral_');
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
    await MigratedKey.write('plan_start_date', planStart.toIso8601String());
    await MigratedKey.write('plan_end_date', planEnd.toIso8601String());
    // Seed 4 weeks; each day carries a `src_week` marker (survives the verbatim
    // copy) so we can assert WHICH week a hold sourced. wk3 = Peak, wk4 = deload.
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
            'src_week': week,
            'status': 'planned',
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
    final box = HiveService.instance.workoutBox;
    for (final k in box.keys
        .where((k) => k.toString().startsWith('schedule_'))
        .toList()) {
      await box.delete(k);
    }
    await HiveUserSession.closeAll();
  });

  Map? rowAt(DateTime date) {
    final raw = HiveService.instance.workoutBox
        .get('schedule_${formatDateKey(date)}');
    return raw is Map ? raw : null;
  }

  test(
      'first hold sources the Peak week, hold_ordinal=1, week=5, is_hold, FLAT '
      'loads; extends plan_end', () async {
    setTestClockTo(DateTime(2026, 6, 29, 10)); // Monday right after plan_end
    final rollStart = DateTime(2026, 6, 29);

    await WorkoutScheduleWriteService.instance.holdWeek();

    final first = rowAt(rollStart);
    expect(first, isNotNull);
    expect(first!['src_week'], 3,
        reason: 'must copy the PEAK week (wk3), not the trailing deload week');
    expect(first['hold_ordinal'], 1);
    expect(first['is_hold'], true);
    expect(first['week'], 5,
        reason: "stamp 'week'=4+N (the field the push maps to week_number)");
    final ex = (first['exercises'] as List).cast<Map>().first;
    expect(ex['weight'], 103.0, reason: 'FLAT — the Peak load is copied verbatim');

    final newEnd = MigratedKey.read<String>('plan_end_date');
    expect(DateTime.parse(newEnd!), rollStart.add(const Duration(days: 6)));
  });

  test('rollStart is a Monday and (rollStart - plan_start) % 7 == 0', () async {
    setTestClockTo(DateTime(2026, 7, 1, 9)); // Wednesday
    await WorkoutScheduleWriteService.instance.holdWeek();
    final rollStart = DateTime(2026, 6, 29); // Monday of that week (backdate)
    expect(rollStart.weekday, DateTime.monday);
    expect(rowAt(rollStart), isNotNull,
        reason: "materialized at THIS week's Monday (backdate)");
    expect(rollStart.difference(planStart).inDays % 7, 0);
  });

  test('every 4th hold sources the deload week; earlier holds the Peak',
      () async {
    final rollStarts = <DateTime>[];
    for (int i = 0; i < 4; i++) {
      setTestClockTo(DateTime(2026, 6, 29).add(Duration(days: i * 7 + 2)));
      await WorkoutScheduleWriteService.instance.holdWeek();
      rollStarts.add(DateTime(2026, 6, 29).add(Duration(days: i * 7)));
    }
    expect(rowAt(rollStarts[0])!['src_week'], 3);
    expect(rowAt(rollStarts[0])!['hold_ordinal'], 1);
    expect(rowAt(rollStarts[2])!['src_week'], 3);
    expect(rowAt(rollStarts[2])!['hold_ordinal'], 3);
    expect(rowAt(rollStarts[3])!['src_week'], 4,
        reason: 'the 4th hold (N%4==0) copies the deload week');
    expect(rowAt(rollStarts[3])!['hold_ordinal'], 4);
  });

  test('a late return numbers the hold by holds-taken, not calendar span',
      () async {
    setTestClockTo(DateTime(2026, 6, 29, 10));
    await WorkoutScheduleWriteService.instance.holdWeek();
    expect(rowAt(DateTime(2026, 6, 29))!['hold_ordinal'], 1);

    // Vanish for weeks, then return far later → this is hold 2, not hold ~9.
    setTestClockTo(DateTime(2026, 8, 5, 10)); // Wednesday, weeks later (gap)
    await WorkoutScheduleWriteService.instance.holdWeek();
    final rollStart2 = DateTime(2026, 8, 3); // Monday of that week
    expect(rowAt(rollStart2)!['hold_ordinal'], 2,
        reason: 'gap-proof — a span-based ordinal would mis-fire the cadence');
  });

  test('a crash-partial hold at rollStart recomputes to the SAME ordinal on '
      'retry', () async {
    setTestClockTo(DateTime(2026, 6, 29, 10));
    final rollStart = DateTime(2026, 6, 29);
    // Simulate a CRASHED hold 1: rows stamped hold_ordinal=1 at rollStart, but
    // plan_end NOT yet extended (crash before the final write).
    for (int d = 0; d < 7; d++) {
      final date = rollStart.add(Duration(days: d));
      await WorkoutWriteService.instance.upsertScheduled(
        date: date,
        entry: {
          'type': 'workout',
          'date': formatDateKey(date),
          'week': 5,
          'is_hold': true,
          'hold_ordinal': 1,
          'src_week': 3,
          'status': 'planned',
          'exercises': <Map<String, dynamic>>[],
        },
        source: WriteSource.schedSwap,
      );
    }
    expect(MigratedKey.read<String>('plan_end_date'), planEnd.toIso8601String());

    await WorkoutScheduleWriteService.instance.holdWeek();

    expect(rowAt(rollStart)!['hold_ordinal'], 1,
        reason: 'the crash-partial AT rollStart is excluded from the ordinal '
            'scan → retry is idempotent (not bumped to 2)');
    expect(MigratedKey.read<String>('plan_end_date'),
        rollStart.add(const Duration(days: 6)).toIso8601String());
  });

  test('holdWeek NEVER writes plan_start (the #6 phantom-phase constraint)',
      () async {
    final before = MigratedKey.read<String>('plan_start_date');
    setTestClockTo(DateTime(2026, 6, 29, 10));
    await WorkoutScheduleWriteService.instance.holdWeek();
    setTestClockTo(DateTime(2026, 7, 8, 10));
    await WorkoutScheduleWriteService.instance.holdWeek();
    expect(MigratedKey.read<String>('plan_start_date'), before,
        reason: 'moving plan_start would pull hold rows into pastPhaseBlocks '
            'and let current_phase over-advance');
  });

  test('two overlapping holdWeek calls yield exactly ONE hold', () async {
    setTestClockTo(DateTime(2026, 6, 29, 10));
    final rollStart = DateTime(2026, 6, 29);
    final f1 = WorkoutScheduleWriteService.instance.holdWeek();
    final f2 = WorkoutScheduleWriteService.instance.holdWeek(); // mutex → no-op
    await Future.wait([f1, f2]);

    expect(rowAt(rollStart)!['hold_ordinal'], 1);
    expect(MigratedKey.read<String>('plan_end_date'),
        rollStart.add(const Duration(days: 6)).toIso8601String(),
        reason: 'exactly one hold — plan_end extended once, not twice');
  });
}
