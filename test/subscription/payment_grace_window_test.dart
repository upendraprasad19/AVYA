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

import 'package:icanbefitter/core/constants/payment_timing.dart';
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

    test('markPaymentInFlight records event-based order_id + started_at',
        () async {
      // H-41 (audit-2026-05-11) — event-based shape replaces the
      // pure ISO `until` timestamp. Stored under
      // `paymentInFlightOrder` as { order_id, started_at }.
      await SubscriptionService.instance
          .markPaymentInFlight(orderId: 'order_test_h41');
      expect(SubscriptionService.instance.isPaymentInFlight, isTrue);
      expect(
        SubscriptionService.instance.paymentInFlightOrderId,
        'order_test_h41',
      );

      // The stored map must carry order_id + a parseable started_at.
      final raw = MigratedKey.read<dynamic>('paymentInFlightOrder');
      expect(raw, isA<Map>(),
          reason: 'event-based key holds a {order_id, started_at} map');
      final m = raw as Map;
      expect(m['order_id'], 'order_test_h41');
      final startedAt = DateTime.parse(m['started_at'].toString());
      // started_at must be very recent (< 5s slop for test scheduling).
      final delta = DateTime.now().difference(startedAt).inSeconds;
      expect(delta, inInclusiveRange(0, 5),
          reason: 'started_at should be ~now');

      // Legacy key must be cleared so the two shapes don't co-exist.
      expect(MigratedKey.read<dynamic>('paymentInFlightUntil'), isNull);
    });

    test('clearPaymentInFlight removes the event-based marker', () async {
      await SubscriptionService.instance
          .markPaymentInFlight(orderId: 'order_test_clear');
      expect(SubscriptionService.instance.isPaymentInFlight, isTrue);

      await SubscriptionService.instance.clearPaymentInFlight();
      expect(SubscriptionService.instance.isPaymentInFlight, isFalse);
      expect(SubscriptionService.instance.paymentInFlightOrderId, isNull);
      expect(MigratedKey.read<dynamic>('paymentInFlightOrder'), isNull);
      expect(MigratedKey.read<dynamic>('paymentInFlightUntil'), isNull);
    });

    Future<void> seedStartedAgo(Duration ago, {String order = 'order_seeded'}) {
      return MigratedKey.write('paymentInFlightOrder', <String, dynamic>{
        'order_id': order,
        'started_at': DateTime.now().subtract(ago).toIso8601String(),
      });
    }

    test('marker older than the derived window reads as not-in-flight', () async {
      // OI-182: was "11 min ago" against a 10-minute literal. The window is now
      // DERIVED from the retry schedule (kPaymentGraceWindow, 21m45s), so the
      // "expired" seed is defined relative to it, one minute past.
      await seedStartedAgo(kPaymentGraceWindow + const Duration(minutes: 1),
          order: 'order_expired');
      expect(SubscriptionService.instance.isPaymentInFlight, isFalse,
          reason: 'older than kPaymentGraceWindow exceeds the fallback ceiling');
    });

    test('marker inside the window but PAST the old 10-minute literal is still in flight',
        () async {
      // The OI-182 regression: a paying user whose webhook is late, checked at
      // minute 17. Under the old 10-minute constant this read false and
      // verifyFromServer/refreshFromSupabase would _downgradeLocally() them.
      await seedStartedAgo(const Duration(minutes: 17));
      expect(SubscriptionService.instance.isPaymentInFlight, isTrue,
          reason: '17 min < kPaymentGraceWindow — the last retry may not have fired yet');
    });

    test('the window covers every retry: started (retry delay + activation budget) ago is in flight',
        () async {
      // Credit honestly: under the OLD 10-min literal the d=60s and d=5m legs
      // are ALSO true (285s / 525s < 600s). Only the d=15m leg (1125s) — and the
      // 17-minute test above — redden against the old constant. The loop is
      // still worth having: it is what ties the assertion to the schedule.
      for (final d in kVerificationRetryDelays) {
        await seedStartedAgo(d + kActivationPhasesBudget);
        expect(SubscriptionService.instance.isPaymentInFlight, isTrue,
            reason: 'a retry scheduled at +$d after Phase 1+2 must still be inside grace');
      }
    });

    test('the boundary is the derived window itself, not a rounder number', () async {
      await seedStartedAgo(kPaymentGraceWindow - const Duration(seconds: 5));
      expect(SubscriptionService.instance.isPaymentInFlight, isTrue);
      await seedStartedAgo(kPaymentGraceWindow + const Duration(seconds: 5));
      expect(SubscriptionService.instance.isPaymentInFlight, isFalse);
    });

    test('legacy paymentInFlightUntil key is honoured for back-compat',
        () async {
      // Devices that upgrade across the H-41 refactor may still have
      // the legacy ISO key in Hive. isPaymentInFlight must respect it
      // until the next event-based write supersedes it.
      final future =
          DateTime.now().add(const Duration(minutes: 5)).toIso8601String();
      await MigratedKey.write('paymentInFlightUntil', future);
      expect(SubscriptionService.instance.isPaymentInFlight, isTrue);
    });
  });
}
