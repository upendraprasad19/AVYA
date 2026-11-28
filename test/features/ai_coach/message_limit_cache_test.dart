// test/features/ai_coach/message_limit_cache_test.dart
//
// Verifies the O(1) Hive-cached MessageLimitNotifier (APK Test #11 M5).
//
// Covers:
//   1. incrementToday writes the counter to Hive with today's IST key.
//   2. build() returns the cached value without a coachBox scan when a
//      cache entry already exists for today.
//   3. build() seeds the cache on a miss (new day / first run).
//   4. pruneOld() removes keys older than 7 days and preserves recent ones.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';

import '../../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  // ── helpers ──────────────────────────────────────────────────────

  String todayKey() => 'msg_count_${istDateStr(DateTime.now())}';

  // ── tests ────────────────────────────────────────────────────────

  test('incrementToday persists correct count for today IST date', () async {
    final box = HiveService.instance.userBox;
    await box.delete(todayKey()); // Start fresh.

    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Initialise the provider (reads 0 from scan on cache miss).
    expect(container.read(messageLimitProvider), 0);

    // Increment twice.
    await container.read(messageLimitProvider.notifier).incrementToday();
    await container.read(messageLimitProvider.notifier).incrementToday();

    expect(box.get(todayKey()), 2,
        reason: 'Hive should persist the incremented count under today\'s IST key');
    expect(container.read(messageLimitProvider), 2,
        reason: 'Riverpod state should reflect the incremented count');
  });

  // B-pass finding (usage-counter-race batch, 2026-07-30): this class's
  // sibling UsageCounterService.increment() has a behavioral concurrent-
  // dispatch test proving no lost update under Future.wait;
  // incrementToday()'s own defensive lock (added the same batch, same
  // shape) had only a source-grep presence test — this closes that
  // COVERAGE gap with the same behavioral standard.
  //
  // HONEST RESULT, same as the sibling test: verified by reverting the
  // lock and re-running — this construction did NOT fail without it either.
  // Same mechanism as UsageCounterService.increment() (see
  // usage_counter_service_race_behavioral_test.dart's header): the read is
  // synchronous and Hive's Box.put() lands in-memory before its own first
  // await, so a same-device Future.wait([a, b]) can't actually interleave
  // two identical-shape read-then-write calls. This test therefore pins the
  // INVARIANT (never a lost update — true today, now explicit via the lock
  // rather than an implicit execution-order coincidence a future refactor
  // could break), not a bug-catch. The lock stays as defense-in-depth,
  // matching its own doc comment.
  test(
      '2 concurrent incrementToday() calls both land — no lost update',
      () async {
    final box = HiveService.instance.userBox;
    await box.delete(todayKey());

    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(messageLimitProvider), 0);
    final notifier = container.read(messageLimitProvider.notifier);

    await Future.wait([
      notifier.incrementToday(),
      notifier.incrementToday(),
    ]);

    expect(box.get(todayKey()), 2,
        reason: 'both concurrent increments must be counted. True today '
            'even without the lock (verified by reverting it) — this pins '
            'the invariant so a future change to the read/write shape that '
            'reopens the window gets caught.');
    expect(container.read(messageLimitProvider), 2);
  });

  test('build() returns cached value O(1) when entry already exists', () async {
    final box = HiveService.instance.userBox;
    await box.put(todayKey(), 7); // Pre-seed the cache.

    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(messageLimitProvider), 7,
        reason: 'build() must return the pre-seeded Hive value without scanning coachBox');
  });

  test('build() seeds cache from scan when no entry for today', () async {
    final box = HiveService.instance.userBox;
    await box.delete(todayKey()); // Simulate a new IST day.
    // coachBox is empty in this test — repository scan returns 0.

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final value = container.read(messageLimitProvider);
    expect(value, 0,
        reason: 'Cache miss should fall back to repository scan (0 for empty coachBox)');
    // After read, the cache should be seeded.
    expect(box.get(todayKey()), 0,
        reason: 'build() should write the scan result back to Hive to seed the cache');
  });

  test('incrementToday after pre-seeded build() produces correct running total',
      () async {
    final box = HiveService.instance.userBox;
    await box.put(todayKey(), 5); // Simulate 5 messages already sent today.

    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(messageLimitProvider); // Reads 5 from cache.

    await container.read(messageLimitProvider.notifier).incrementToday(); // → 6
    await container.read(messageLimitProvider.notifier).incrementToday(); // → 7

    expect(container.read(messageLimitProvider), 7);
    expect(box.get(todayKey()), 7);
  });

  test('pruneOld removes keys older than 7 days', () async {
    final box = HiveService.instance.userBox;
    await box.put('msg_count_2026-01-01', 99); // Old key.
    await box.put(todayKey(), 5);              // Today — must survive.

    await MessageLimitNotifier.pruneOld();

    expect(box.get('msg_count_2026-01-01'), null,
        reason: 'Key older than 7 days should be deleted');
    expect(box.get(todayKey()), 5,
        reason: 'Today\'s key must be preserved');
  });

  test('pruneOld keeps keys within the last 7 days', () async {
    final box = HiveService.instance.userBox;
    final recent = istDateStr(DateTime.now().subtract(const Duration(days: 3)));
    await box.put('msg_count_$recent', 3);

    await MessageLimitNotifier.pruneOld();

    expect(box.get('msg_count_$recent'), 3,
        reason: 'Key only 3 days old should not be pruned');
  });

  test('pruneOld silently skips malformed msg_count_* keys', () async {
    final box = HiveService.instance.userBox;
    await box.put('msg_count_not-a-date', 1);

    await expectLater(MessageLimitNotifier.pruneOld(), completes);
  });
}
