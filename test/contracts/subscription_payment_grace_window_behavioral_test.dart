// BEHAVIORAL contract for subscription_payment_grace_window:
//
// IMPORTANT: isPro() does NOT consult isPaymentInFlight. The payment grace
// window only suppresses downgrade in verifyFromServer() and
// refreshFromSupabase(). This test therefore:
//   A. Tests isPro() expiry boundary — expired expiresAt → isPro() = false;
//      future expiresAt → isPro() = true.
//   B. Tests isPaymentInFlight boundaries independently:
//      - started_at within 10 min → isPaymentInFlight = true
//      - started_at > 10 min ago → isPaymentInFlight = false
//      - clearPaymentInFlight() → isPaymentInFlight = false immediately
//
// Run: flutter test test/contracts/subscription_payment_grace_window_behavioral_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
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

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('sub_grace_window_');
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
    await HiveUserSession.closeAll();
    await HiveService.instance.configBox.clear();
  });

  tearDown(() async {
    // isPro() on an expired (or cross-account) subscription fires a
    // fire-and-forget _downgradeLocally() — an async chain whose FIRST op
    // (isPro := false) runs synchronously, but whose later deletes
    // (expiresAt, plan, localActivationAt, lastVerified) are DEFERRED past an
    // await. If a deferred delete(expiresAt) lands during the NEXT test's
    // write→read gap it nulls the freshly-written expiry, and isPro() then
    // returns kDebugMode (true in tests, line ~355) instead of the expected
    // false. That cross-test contamination passes locally but flakes in CI
    // (slower event loop). Drain the deferred chain here so each test's
    // fire-and-forget async stays confined to itself. (Pure test-isolation
    // fix — production isPro() is correct: isPro := false short-circuits every
    // subsequent call before the expiresAt-null branch is reached.)
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  });

  // ignore: deprecated_member_use
  final sub = SubscriptionService.instance;

  const userA = 'test-sub-grace-aaaa-0033-aabb';

  group('isPro() expiry boundary', () {
    test('future expiresAt → isPro() returns true', () async {
      await HiveUserSession.openForUser(userA);

      final futureExpiry = DateTime.now()
          .add(const Duration(days: 30))
          .toIso8601String();
      await MigratedKey.write('isPro', true);
      await MigratedKey.write('expiresAt', futureExpiry);

      expect(sub.isPro(), isTrue,
          reason: 'active subscription with future expiry must return isPro=true');
    });

    test('expiresAt in the past → isPro() returns false (expired)', () async {
      await HiveUserSession.openForUser(userA);

      final pastExpiry = DateTime.now()
          .subtract(const Duration(seconds: 1))
          .toIso8601String();
      await MigratedKey.write('isPro', true);
      await MigratedKey.write('expiresAt', pastExpiry);

      expect(sub.isPro(), isFalse,
          reason:
              'subscription expired 1 second ago — isPro() must return false immediately; '
              'there is no grace window inside isPro()');
    });

    test('isPro=false in Hive → isPro() returns false regardless of expiresAt',
        () async {
      await HiveUserSession.openForUser(userA);

      final futureExpiry = DateTime.now()
          .add(const Duration(days: 30))
          .toIso8601String();
      await MigratedKey.write('isPro', false);
      await MigratedKey.write('expiresAt', futureExpiry);

      expect(sub.isPro(), isFalse,
          reason: 'isPro flag = false → short-circuit; expiry date irrelevant');
    });

    test('expiresAt exactly now is treated as expired', () async {
      await HiveUserSession.openForUser(userA);

      // Set expiry to a moment in the past — even by a tiny margin, isAfter
      // evaluates false for the exact same DateTime. Using subtract(0) is still
      // in the past due to processing time between writes and the isAfter call.
      final justExpired = DateTime.now()
          .subtract(const Duration(milliseconds: 1))
          .toIso8601String();
      await MigratedKey.write('isPro', true);
      await MigratedKey.write('expiresAt', justExpired);

      expect(sub.isPro(), isFalse,
          reason: 'expired by even 1ms → isPro() must return false');
    });
  });

  group('isPaymentInFlight — 10-min grace window boundary', () {
    test('markPaymentInFlight → isPaymentInFlight = true within 10 min',
        () async {
      await HiveUserSession.openForUser(userA);
      await MigratedKey.delete('paymentInFlightOrder');
      await MigratedKey.delete('paymentInFlightUntil');

      await sub.markPaymentInFlight(orderId: 'order_test_001');

      expect(sub.isPaymentInFlight, isTrue,
          reason: 'payment marked in-flight just now → must be within 10-min window');
    });

    test('stale started_at > 10 min ago → isPaymentInFlight = false', () async {
      await HiveUserSession.openForUser(userA);

      // Write a started_at that is 11 minutes in the past.
      final staleStart = DateTime.now()
          .subtract(const Duration(minutes: 11))
          .toIso8601String();
      await MigratedKey.write('paymentInFlightOrder', <String, dynamic>{
        'order_id': 'order_stale_test',
        'started_at': staleStart,
      });

      expect(sub.isPaymentInFlight, isFalse,
          reason:
              'started_at > 10 min ago → grace window expired; '
              'isPaymentInFlight must return false');
    });

    test('clearPaymentInFlight → isPaymentInFlight = false immediately',
        () async {
      await HiveUserSession.openForUser(userA);

      // Set in-flight.
      await sub.markPaymentInFlight(orderId: 'order_clear_test');
      expect(sub.isPaymentInFlight, isTrue,
          reason: 'precondition: in-flight');

      // Clear.
      await sub.clearPaymentInFlight();
      expect(sub.isPaymentInFlight, isFalse,
          reason: 'clearPaymentInFlight must synchronously end the grace window');
    });

    test('no paymentInFlightOrder key → isPaymentInFlight = false', () async {
      await HiveUserSession.openForUser(userA);
      await MigratedKey.delete('paymentInFlightOrder');
      await MigratedKey.delete('paymentInFlightUntil');

      expect(sub.isPaymentInFlight, isFalse,
          reason: 'absent key → isPaymentInFlight must default to false');
    });

    test(
        'isPro() does NOT return true during payment grace window when expiry is past',
        () async {
      await HiveUserSession.openForUser(userA);

      // Mark payment in-flight.
      await sub.markPaymentInFlight(orderId: 'order_no_grace_in_ispro');

      // Write an expired subscription.
      final pastExpiry = DateTime.now()
          .subtract(const Duration(seconds: 1))
          .toIso8601String();
      await MigratedKey.write('isPro', true);
      await MigratedKey.write('expiresAt', pastExpiry);

      // CRITICAL: isPro() must still return false even though the payment
      // grace window is active. The grace window only suppresses downgrade in
      // verifyFromServer() and refreshFromSupabase(), NOT in isPro() itself.
      expect(sub.isPaymentInFlight, isTrue, reason: 'precondition: in-flight');
      expect(sub.isPro(), isFalse,
          reason:
              'isPro() does NOT check isPaymentInFlight — '
              'expired expiresAt → isPro()=false regardless of in-flight state');
    });
  });
}
