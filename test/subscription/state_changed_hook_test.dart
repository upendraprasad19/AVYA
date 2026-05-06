// APK Test #12.2 / cold-start reactivity — pins the SubscriptionService
// onStateChanged hook contract.
//
// Bug: `refreshFromSupabase` is fire-and-forget on splash. It writes
// `isPro=true` to Hive when server confirms PRO, but Riverpod's
// `subscriptionInfoProvider` cache held the initial `isPro=false`
// snapshot — UI never rebuilt. Founder observation 2026-05-06: "i'm
// not seeing pro pill on profile. May be it is reading from local
// phone data."
//
// Fix: SubscriptionService.onStateChanged static hook. Wired from
// app.dart initState to invalidate subscriptionInfoProvider +
// trialInfoProvider + messageLimitProvider on every state write.

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_state_changed');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    SubscriptionService.onStateChanged = null;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    for (final name in [
      HiveService.configBoxName,
      HiveService.migrationBoxName,
    ]) {
      if (Hive.isBoxOpen(name)) await Hive.box(name).close();
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.instance.markInitializedForTests();
    SubscriptionService.onStateChanged = null;
  });

  test('writeSubscriptionState fires onStateChanged hook', () async {
    var fireCount = 0;
    SubscriptionService.onStateChanged = () => fireCount += 1;

    await SubscriptionService.instance.writeSubscriptionState(
      isPro: true,
      expiresAt: '2026-12-31T00:00:00Z',
      plan: 'monthly',
    );

    expect(fireCount, 1,
        reason: 'every state write must trigger reactivity hook');
  });

  test('hook absent → writeSubscriptionState still succeeds', () async {
    SubscriptionService.onStateChanged = null;
    // Should not throw, should not block the write.
    await SubscriptionService.instance.writeSubscriptionState(
      isPro: true,
      expiresAt: '2026-12-31T00:00:00Z',
      plan: 'monthly',
    );
  });

  test('hook throws → write still completes (best-effort)', () async {
    SubscriptionService.onStateChanged = () {
      throw StateError('simulated invalidation failure');
    };

    // Must not throw — the catch in subscription_service swallows.
    await SubscriptionService.instance.writeSubscriptionState(
      isPro: true,
      expiresAt: '2026-12-31T00:00:00Z',
      plan: 'monthly',
    );
  });
}
