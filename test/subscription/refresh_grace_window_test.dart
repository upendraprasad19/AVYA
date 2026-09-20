// APK Test #12.1 — pins the second downgrade path (`refreshFromSupabase`)
// honors the payment grace window.
//
// Bug class: Test #12 added `paymentInFlightUntil` + grace check inside
// `verifyFromServer`, but missed the parallel `refreshFromSupabase`
// path called by splash on cold start. Founder reported PRO unlock
// didn't reflect after Razorpay test payment + restart — server query
// returned no row (test mode webhook lag), `_downgradeLocally()` ran,
// PRO state wiped despite the optimistic write minutes earlier.
//
// This test pins the contract that `refreshFromSupabase`:
//   1. Returns early when `isPaymentInFlight` is true (no server query).
//   2. Returns early when `localActivationAt` is within 10 min,
//      regardless of whether `isPro()` happens to read true at that
//      moment (cold-start session race resilient).

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
    tempDir = await Directory.systemTemp.createTemp('test_refresh_grace');
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

  group('Source-grep contract — refreshFromSupabase guards (APK Test #12.1)',
      () {
    final source = File(
      'lib/core/services/subscription_service.dart',
    ).readAsStringSync();

    test('refreshFromSupabase checks isPaymentInFlight before server query',
        () {
      // Locate the method body.
      final body = RegExp(
        r'Future<void> refreshFromSupabase\(\) async \{(.*?)\n  \}',
        dotAll: true,
      ).firstMatch(source);
      expect(body, isNotNull,
          reason: 'Could not locate refreshFromSupabase method');

      final code = body!.group(1)!;

      // Must reference isPaymentInFlight — otherwise no grace window guard.
      expect(code.contains('isPaymentInFlight'), isTrue,
          reason: 'refreshFromSupabase must check isPaymentInFlight to '
              'avoid downgrading the optimistic state during a webhook lag');
    });

    test('localActivationAt grace path no longer requires isPro()=true', () {
      final body = RegExp(
        r'Future<void> refreshFromSupabase\(\) async \{(.*?)\n  \}',
        dotAll: true,
      ).firstMatch(source);
      expect(body, isNotNull);

      final code = body!.group(1)!;

      // Pre-Test-#12.1 the grace check was `if (localActivation != null && isPro())`.
      // The `&& isPro()` conditional made the guard fail during cold-start
      // session-restore race conditions. Removed in Test #12.1.
      expect(
        code.contains('localActivation != null && isPro()'),
        isFalse,
        reason: 'localActivation grace must NOT require isPro()=true — '
            'cold-start session race makes that conditional unreliable',
      );
    });
  });

  group('isPaymentInFlight read contract (APK Test #12.1)', () {
    test('true while grace window open, false after it expires', () async {
      // 5-min-future timestamp → in flight
      final future =
          DateTime.now().add(const Duration(minutes: 5)).toIso8601String();
      await MigratedKey.write('paymentInFlightUntil', future);
      expect(SubscriptionService.instance.isPaymentInFlight, isTrue);

      // Past timestamp → expired
      final past =
          DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String();
      await MigratedKey.write('paymentInFlightUntil', past);
      expect(SubscriptionService.instance.isPaymentInFlight, isFalse);

      // Absent → not in flight
      await MigratedKey.delete('paymentInFlightUntil');
      expect(SubscriptionService.instance.isPaymentInFlight, isFalse);
    });
  });
}
