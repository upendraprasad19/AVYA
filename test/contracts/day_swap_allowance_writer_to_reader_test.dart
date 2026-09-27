// BEHAVIORAL CONTRACT TEST — day_swap_allowance
//
// Writer: DaySwapAllowance.recordSwap / the server-reply write in _consume
//         (lib/core/services/day_swap/day_swap_allowance.dart)
// Reader: DaySwapAllowance.current — Hive userBox key `day_swap_allowance`
// Spec 2026-09-26-day-swapper-design §5.3.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_allowance.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_result.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';

import '../helpers/hive_test_setup.dart';

const week = '2026-09-21';
const nextWeek = '2026-09-28';
const lastWeek = '2026-09-14';

void main() {
  late Directory dir;
  final nonFatals = <String>[];
  final allowance = DaySwapAllowance.instance;

  setUp(() async {
    dir = await setUpHiveForTests();
    // `hive_test_setup.dart`'s shared-box list omits `migrationBox`
    // (HiveService.migrationBoxName), so the FIRST `openForUser` inside
    // `setUpHiveForTests` already hits HiveUserSession's "migrationBox
    // unavailable" / "failed to set legacy migration flag" catches — silent
    // here only because the test hook below isn't installed yet. Opening it
    // now (before any explicit second `openForUser` inside a test body)
    // lets `_migrateLegacySharedBoxes` complete cleanly for every user this
    // suite switches to, so `nonFatals` reflects DaySwapAllowance only —
    // never HiveUserSession's own unrelated migration bookkeeping.
    await Hive.openBox(HiveService.migrationBoxName);
    setTestClockTo(DateTime.utc(2026, 9, 24, 4, 30)); // Thu 24 Sep, 10:00 IST
    nonFatals.clear();
    ErrorTelemetry.debugOnRecordNonFatalForTests =
        (e, st, {required reason, extra}) => nonFatals.add(reason);
    DaySwapAllowance.debugConsumeForTests = (_) async => null;
  });

  tearDown(() async {
    ErrorTelemetry.debugOnRecordNonFatalForTests = null;
    DaySwapAllowance.debugConsumeForTests = null;
    resetTestClock();
    await tearDownHiveForTests(dir);
  });

  test('a fresh week reads 0 used with the built-in limit', () {
    expect(allowance.current(week, isPro: false),
        const DayAllowance(weekStart: week, used: 0, limit: 1));
    expect(allowance.current(week, isPro: true),
        const DayAllowance(weekStart: week, used: 0, limit: 3));
  });

  test('recordSwap counts on the phone and the reader sees it', () async {
    final after = await allowance.recordSwap(week, isPro: true);
    await allowance.lastConsumeForTests;
    expect(after, const DayAllowance(weekStart: week, used: 1, limit: 3));
    expect(allowance.current(week, isPro: true).used, 1);
    final raw = HiveService.instance.userBox.get(DaySwapAllowance.hiveKey);
    expect((raw as Map)[week]['used'], 1);
  });

  test('weeks are independent', () async {
    await allowance.recordSwap(week, isPro: true);
    await allowance.lastConsumeForTests;
    expect(allowance.current(nextWeek, isPro: true).used, 0);
  });

  test('the server reply overwrites the phone copy (server wins)', () async {
    DaySwapAllowance.debugConsumeForTests =
        (_) async => {'allowed': true, 'used': 3, 'limit': 3};
    await allowance.recordSwap(week, isPro: true);
    await allowance.lastConsumeForTests;
    expect(allowance.current(week, isPro: true),
        const DayAllowance(weekStart: week, used: 3, limit: 3));
  });

  test('server_seen_at_ms is stamped from the test clock seam, not the '
      'real wall clock', () async {
    // A fixed instant far from "real now" — if the write ever regressed to
    // a raw DateTime.now(), this would fail because the stamped value would
    // be the actual system time, not this fixture's.
    final fixed = DateTime.utc(2026, 9, 24, 9, 15);
    setTestClockTo(fixed);
    DaySwapAllowance.debugConsumeForTests =
        (_) async => {'allowed': true, 'used': 1, 'limit': 3};
    await allowance.recordSwap(week, isPro: true);
    await allowance.lastConsumeForTests;
    final raw =
        HiveService.instance.userBox.get(DaySwapAllowance.hiveKey) as Map;
    expect((raw[week] as Map)['server_seen_at_ms'], fixed.millisecondsSinceEpoch);
  });

  test('a late, lower server reply never lowers the count (out-of-order replies)',
      () async {
    final replies = <Completer<Map<String, dynamic>?>>[];
    DaySwapAllowance.debugConsumeForTests = (_) {
      final c = Completer<Map<String, dynamic>?>();
      replies.add(c);
      return c.future;
    };
    await allowance.recordSwap(week, isPro: true);
    final firstCall = allowance.lastConsumeForTests;
    await allowance.recordSwap(week, isPro: true);
    final secondCall = allowance.lastConsumeForTests;
    // The second swap's reply lands first, then the first swap's.
    replies[1].complete({'allowed': true, 'used': 2, 'limit': 3});
    await secondCall;
    replies[0].complete({'allowed': true, 'used': 1, 'limit': 3});
    await firstCall;
    expect(allowance.current(week, isPro: true).used, 2);
  });

  test('a LOWER count from the newest reply still wins (server correction)',
      () async {
    DaySwapAllowance.debugConsumeForTests =
        (_) async => {'allowed': true, 'used': 2, 'limit': 3};
    await allowance.recordSwap(week, isPro: true);
    await allowance.lastConsumeForTests;
    expect(allowance.current(week, isPro: true).used, 2);
    // Support refunded a swap on the server; the next reply says 1.
    DaySwapAllowance.debugConsumeForTests =
        (_) async => {'allowed': true, 'used': 1, 'limit': 3};
    await allowance.recordSwap(week, isPro: true);
    await allowance.lastConsumeForTests;
    expect(allowance.current(week, isPro: true).used, 1,
        reason: 'a high-water guard would pin this at 2 for the rest of the week');
  });

  test('allowed:false (the EF sends used = limit) marks the week spent',
      () async {
    DaySwapAllowance.debugConsumeForTests =
        (_) async => {'allowed': false, 'used': 1, 'limit': 1};
    await allowance.recordSwap(week, isPro: false);
    await allowance.lastConsumeForTests;
    expect(allowance.current(week, isPro: false).spent, isTrue);
  });

  test('no answer keeps the phone copy (fail open)', () async {
    await allowance.recordSwap(week, isPro: true);
    await allowance.lastConsumeForTests;
    expect(allowance.current(week, isPro: true).used, 1);
    expect(nonFatals, isEmpty);
  });

  test('a throwing call keeps the phone copy and records one non-fatal',
      () async {
    DaySwapAllowance.debugConsumeForTests = (_) async => throw Exception('500');
    await allowance.recordSwap(week, isPro: true);
    await allowance.lastConsumeForTests;
    expect(allowance.current(week, isPro: true).used, 1);
    expect(nonFatals, ['day_swap_allowance_consume']);
  });

  test('a server limit applies only to the tier it was seen under', () async {
    DaySwapAllowance.debugConsumeForTests =
        (_) async => {'allowed': true, 'used': 1, 'limit': 1};
    await allowance.recordSwap(week, isPro: false);
    await allowance.lastConsumeForTests;
    expect(allowance.current(week, isPro: false).limit, 1);
    // Upgraded since: the built-in PRO limit applies until the next reply.
    expect(allowance.current(week, isPro: true).limit, 3);
    expect(allowance.current(week, isPro: true).used, 1);
  });

  test('past weeks are pruned on the next write', () async {
    await HiveService.instance.userBox.put(DaySwapAllowance.hiveKey, {
      lastWeek: {'used': 1},
    });
    await allowance.recordSwap(week, isPro: true);
    await allowance.lastConsumeForTests;
    final raw =
        HiveService.instance.userBox.get(DaySwapAllowance.hiveKey) as Map;
    expect(raw.containsKey(lastWeek), isFalse);
    expect(raw.containsKey(week), isTrue);
  });

  test('a reply that lands after an account switch writes nothing', () async {
    final gate = Completer<Map<String, dynamic>?>();
    DaySwapAllowance.debugConsumeForTests = (_) => gate.future;
    await allowance.recordSwap(week, isPro: true);
    await HiveUserSession.closeAll();
    await HiveUserSession.openForUser('99999999-aaaa-bbbb-cccc-000000000000');
    gate.complete({'allowed': true, 'used': 3, 'limit': 3});
    await allowance.lastConsumeForTests;
    expect(HiveService.instance.userBox.get(DaySwapAllowance.hiveKey), isNull);
    expect(nonFatals, isEmpty, reason: 'a closed box is skipped, not thrown');
  });

  test('every write bumps revision (the allowance provider listens)',
      () async {
    final before = allowance.revision.value;
    await allowance.recordSwap(week, isPro: true);
    await allowance.lastConsumeForTests;
    expect(allowance.revision.value, greaterThan(before));
  });
}
