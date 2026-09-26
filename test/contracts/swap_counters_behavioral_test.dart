// BEHAVIORAL CONTRACT TEST — swap_counters
//
// Concept:   swap_counters
// Writer:    lib/core/services/swap_service.dart
//            (swapDays → _incrementSwapCount)
// Reader:    Hive read-back via MigratedKey.read / MigratedKey.readWithDefault
//
// Assert:
//   1. After a successful swapDays, swaps_this_week == 1.
//   2. After a second swap in the same week, swaps_this_week == 2.
//   3. When swap_week_start holds a DIFFERENT Monday than the current week,
//      _getSwapsUsedThisWeek returns 0 (week rollover is detected).
//   4. A cross-week swap (dateA and dateB in different ISO weeks) is rejected
//      with a non-null error string — never increments the counter.
//
//   These asserts FAIL if:
//   - _swapsThisWeekKey ('swaps_this_week') constant drifts.
//   - _swapWeekStartKey ('swap_week_start') constant drifts.
//   - _normalizeToMonday logic changes week-boundary semantics.
//   - MigratedKey.read is replaced with a different storage layer.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
// ignore: deprecated_member_use
import 'package:icanbefitter/core/services/swap_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/date_utils.dart' show formatDateKey;
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

// The Monday of a week that is NOT the current week.
// Pick a date far in the future so it can never coincidentally be this week.
final _pastMonday = DateTime(2020, 1, 6); // Monday 6 Jan 2020

// A Monday in the future used as our "current" test week.
// 2026-07-06 is a Monday.
final _testMonday = DateTime(2026, 7, 6);
final _testWednesday = DateTime(2026, 7, 8);
final _testThursday = DateTime(2026, 7, 9);
final _nextMonday = DateTime(2026, 7, 13); // different week

void main() {
  late Directory tempDir;
  const fakeUserId = 'ffffffff-0000-1111-2222-000000000005';

  // Key constants that the service writes under.
  const swapsThisWeekKey = 'swaps_this_week';
  const swapWeekStartKey = 'swap_week_start';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('sc_behavioral_');
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
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await HiveUserSession.openForUser(fakeUserId);
  });

  tearDown(() async {
    // Clean up schedule entries and swap counter keys between tests.
    final box = HiveService.instance.workoutBox;
    final schedKeys = box.keys
        .where((k) => k.toString().startsWith('schedule_'))
        .toList();
    for (final k in schedKeys) {
      await box.delete(k);
    }
    // Clean MigratedKey entries.
    final userBox = HiveService.instance.userBox;
    await userBox.delete(swapsThisWeekKey);
    await userBox.delete(swapWeekStartKey);
    await HiveUserSession.closeAll();
  });

  // Helper: seed two schedule entries for the same week so swapDays can execute.
  // Both dates must be in the test week (Mon–Sun 2026-07-06..12).
  // Neither may form 3+ consecutive rest days when swapped — to avoid that,
  // seed all 7 days: Mon/Wed/Thu = workout, rest for Tue/Fri/Sat/Sun.
  Future<void> _seedWeek() async {
    for (final d in [
      _testMonday,
      _testWednesday,
      _testThursday,
    ]) {
      await WorkoutWriteService.instance.upsertScheduled(
        date: d,
        entry: {
          'type': 'workout',
          'date': formatDateKey(d),
          'day_of_week': _dayName(d.weekday),
          'status': 'planned',
          'exercises': <Map<String, dynamic>>[],
        },
        source: WriteSource.schedSwap,
      );
    }
    // Seed the rest days to fill all 7 slots (avoids null → 'rest' fallback).
    // NOTE: Only Tue/Sat/Sun are rest — NOT Fri.  Fri/Sat/Sun would be 3
    // consecutive rest days which _hasThreeConsecutiveRest blocks.
    // Fri is seeded as a workout day to keep the max run ≤ 2 (Sat+Sun).
    for (final d in [
      DateTime(2026, 7, 7), // Tue — rest
      DateTime(2026, 7, 11), // Sat — rest
      DateTime(2026, 7, 12), // Sun — rest
    ]) {
      await WorkoutWriteService.instance.upsertScheduled(
        date: d,
        entry: {
          'type': 'rest',
          'date': formatDateKey(d),
          'day_of_week': _dayName(d.weekday),
          'status': 'planned',
          'exercises': <Map<String, dynamic>>[],
        },
        source: WriteSource.schedSwap,
      );
    }
    // Fri — workout (prevents 3-consecutive-rest Fri/Sat/Sun).
    final fri = DateTime(2026, 7, 10);
    await WorkoutWriteService.instance.upsertScheduled(
      date: fri,
      entry: {
        'type': 'workout',
        'date': formatDateKey(fri),
        'day_of_week': _dayName(fri.weekday),
        'status': 'planned',
        'exercises': <Map<String, dynamic>>[],
      },
      source: WriteSource.schedSwap,
    );
  }

  // ── Test 1: swapDays increments swaps_this_week 0 → 1 ──────────────────
  test(
    'swapDays increments swaps_this_week from 0 to 1',
    () async {
      await _seedWeek();

      // ignore: deprecated_member_use
      final err = await SwapService.instance.swapDays(
        _testMonday,
        _testWednesday,
        isPro: true,
      );

      expect(
        err,
        isNull,
        reason:
            'swapDays must succeed (return null) when both dates are in the '
            'same week and have schedule entries. Error: $err',
      );

      final count = MigratedKey.readWithDefault<int>(swapsThisWeekKey, -1);
      expect(
        count,
        equals(1),
        reason:
            "swaps_this_week must be 1 after the first swap. "
            "Got $count. Possible causes: (1) _swapsThisWeekKey constant drifted "
            "from 'swaps_this_week', (2) _incrementSwapCount no longer writes "
            "via MigratedKey.write, (3) session was closed before read.",
      );
    },
  );

  // ── Test 2: second swap same week → swaps_this_week == 2 ───────────────
  test(
    'swapDays increments swaps_this_week to 2 on second swap',
    () async {
      await _seedWeek();

      // Swap 1: Mon ↔ Wed
      // ignore: deprecated_member_use
      await SwapService.instance.swapDays(
        _testMonday,
        _testWednesday,
        isPro: true,
      );
      // Swap 2: Wed ↔ Thu (after swap 1, Wed now holds Mon's workout)
      // ignore: deprecated_member_use
      final err2 = await SwapService.instance.swapDays(
        _testWednesday,
        _testThursday,
        isPro: true,
      );

      expect(
        err2,
        isNull,
        reason: 'Second swap must succeed (return null). Error: $err2',
      );

      final count = MigratedKey.readWithDefault<int>(swapsThisWeekKey, -1);
      expect(
        count,
        equals(2),
        reason:
            'swaps_this_week must be 2 after two swaps in the same week. '
            'Got $count. The increment path in _incrementSwapCount must '
            'read the existing value and add 1.',
      );
    },
  );

  // ── Test 3: week rollover — stale swap_week_start → 0 counter ───────────
  test(
    'swap_week_start from a different Monday means swaps_this_week resets to 0',
    () async {
      await _seedWeek();

      // Manually write a stale swap_week_start (a DIFFERENT Monday than testMonday).
      await MigratedKey.write(
          swapWeekStartKey, formatDateKey(_pastMonday)); // Jan 6 2020
      await MigratedKey.write(swapsThisWeekKey, 99); // stale count

      // Perform a swap in the test week (Jul 6 2026).
      // ignore: deprecated_member_use
      final err = await SwapService.instance.swapDays(
        _testMonday,
        _testWednesday,
        isPro: true,
      );

      expect(
        err,
        isNull,
        reason:
            'swapDays must succeed when swap_week_start is stale (different week). '
            'Error: $err',
      );

      // _incrementSwapCount detects the Monday mismatch and resets to 1.
      final count = MigratedKey.readWithDefault<int>(swapsThisWeekKey, -1);
      expect(
        count,
        equals(1),
        reason:
            'When swap_week_start is a DIFFERENT Monday, _incrementSwapCount '
            'must reset swaps_this_week to 1 (not 100). '
            "Got $count. The 'currentWeekStart != mondayKey' branch must "
            'overwrite the old count, not add to it.',
      );

      final weekStart = MigratedKey.read<String>(swapWeekStartKey);
      expect(
        weekStart,
        equals(formatDateKey(_testMonday)),
        reason:
            'swap_week_start must be updated to the new Monday after a '
            'week rollover.',
      );
    },
  );

  // ── Test 4: cross-week swap rejected, counter not incremented ───────────
  test(
    'swapDays rejects cross-week swap and does not increment swaps_this_week',
    () async {
      await _seedWeek();
      // Seed a schedule entry for the NEXT week's Monday.
      await WorkoutWriteService.instance.upsertScheduled(
        date: _nextMonday,
        entry: {
          'type': 'workout',
          'date': formatDateKey(_nextMonday),
          'day_of_week': 'Monday',
          'status': 'planned',
          'exercises': <Map<String, dynamic>>[],
        },
        source: WriteSource.schedSwap,
      );

      // ignore: deprecated_member_use
      final err = await SwapService.instance.swapDays(
        _testMonday,
        _nextMonday, // different ISO week
        isPro: true,
      );

      expect(
        err,
        isNotNull,
        reason:
            'swapDays MUST reject a cross-week swap (dates in different '
            'ISO weeks). Got null (success), which means the '
            'mondayA != mondayB same-week guard was removed.',
      );

      final count = MigratedKey.readWithDefault<int>(swapsThisWeekKey, 0);
      expect(
        count,
        equals(0),
        reason:
            'A rejected cross-week swap must NOT increment swaps_this_week. '
            'Got $count.',
      );
    },
  );
}

String _dayName(int weekday) {
  const names = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return names[(weekday - 1) % 7];
}
