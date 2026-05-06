// APK Test #12 / Task C-1 — payment grace window contract.
//
// Pins the behavior added to SubscriptionService:
//   - markPaymentInFlight() writes a future timestamp via MigratedKey
//   - clearPaymentInFlight() removes it
//   - isPaymentInFlight reflects current time vs stored timestamp
//
// The full verifyFromServer loop (network call → grace check →
// downgrade-or-not) is exercised at the call-site level in the
// RazorpayService integration test; this contract test pins the
// state-machine primitives so a refactor can't drop the grace window
// silently.

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_payment_grace');
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
  });

  group('Payment grace window (APK Test #12 / Task C-1)', () {
    test('isPaymentInFlight is false when key absent', () {
      expect(SubscriptionService.instance.isPaymentInFlight, isFalse);
    });

    test('markPaymentInFlight sets a future-ish timestamp', () async {
      await SubscriptionService.instance.markPaymentInFlight();
      expect(SubscriptionService.instance.isPaymentInFlight, isTrue);

      // The stored value should be a parseable ISO string at least
      // 9 minutes in the future (allow slop for test scheduling).
      final raw = MigratedKey.read<dynamic>('paymentInFlightUntil');
      expect(raw, isNotNull);
      final until = DateTime.parse(raw.toString());
      final delta = until.difference(DateTime.now()).inMinutes;
      expect(delta, inInclusiveRange(9, 10),
          reason: 'grace window should be ~10 minutes');
    });

    test('clearPaymentInFlight removes the marker', () async {
      await SubscriptionService.instance.markPaymentInFlight();
      expect(SubscriptionService.instance.isPaymentInFlight, isTrue);

      await SubscriptionService.instance.clearPaymentInFlight();
      expect(SubscriptionService.instance.isPaymentInFlight, isFalse);
      expect(MigratedKey.read<dynamic>('paymentInFlightUntil'), isNull);
    });

    test('expired grace window reads as not-in-flight', () async {
      // Manually write a past timestamp.
      final pastIso =
          DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String();
      await MigratedKey.write('paymentInFlightUntil', pastIso);
      expect(SubscriptionService.instance.isPaymentInFlight, isFalse);
    });
  });
}
