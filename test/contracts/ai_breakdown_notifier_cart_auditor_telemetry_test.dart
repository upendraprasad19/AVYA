// A5/OI-226 (f7a2c9, 2026-09-21) — CartAuditorNotifier.analyseCart had ZERO
// telemetry on either failure path (a non-200/null-data ai-proxy response,
// or a thrown exception), the exact gap live-confirmed via client_errors
// returning zero rows for a fully-reproduced incident window. Its structural
// sibling ScanMealNotifier.scanImage (nutrition_provider.dart, ~40 lines
// above this class) already had the catch-block fix
// (ai_breakdown_notifier_scan_meal_telemetry_test.dart) — this mirrors that
// exact fault-injection pattern for the catch block, plus adds bounded
// source-grep pins for BOTH notifiers' non-200 branches (a plain response
// value, not a throw — no fault-injection seam exists for that shape, so a
// position-scoped source pin is the proportionate check here, consistent
// with ai_media_proxy_telemetry_test.dart's own established convention for
// this exact kind of branch).
//
// Writer: nutrition_provider.dart CartAuditorNotifier.analyseCart
// Reader: ErrorTelemetry.recordNonFatal / logEvent -> client_errors
//         (op_type = 'cart_auditor_notifier_analyse_cart' /
//          'cart_auditor_notifier_non_200_response')

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ErrorTelemetry.debugOnRecordNonFatalForTests = null;
    CartAuditorNotifier.throwBeforeAnalyseForTest = null;
  });

  tearDown(() {
    ErrorTelemetry.debugOnRecordNonFatalForTests = null;
    CartAuditorNotifier.throwBeforeAnalyseForTest = null;
  });

  test(
      'CartAuditorNotifier.analyseCart records telemetry on failure via ErrorTelemetry.recordNonFatal',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(cartAuditorProvider.notifier);

    Object? capturedError;
    String? capturedReason;
    ErrorTelemetry.debugOnRecordNonFatalForTests =
        (error, stack, {required reason, extra}) {
      capturedError = error;
      capturedReason = reason;
    };

    final injected = StateError('simulated ai-proxy failure');
    CartAuditorNotifier.throwBeforeAnalyseForTest = injected;

    await notifier.analyseCart([1, 2, 3]);

    expect(capturedReason, 'cart_auditor_notifier_analyse_cart',
        reason:
            'the catch block must report via ErrorTelemetry with this exact '
            'op_type so a recurrence is diagnosable in client_errors');
    expect(capturedError, same(injected));
  });

  group('non-200 branch telemetry (bounded source pins — see file header)',
      () {
    late String src;

    setUpAll(() {
      src = File('lib/features/nutrition/providers/nutrition_provider.dart')
          .readAsStringSync();
    });

    test('analyseCart logs cart_auditor_notifier_non_200_response before '
        'the error-state assignment', () {
      final methodStart =
          src.indexOf('Future<void> analyseCart(List<int> imageBytes)');
      expect(methodStart, greaterThanOrEqualTo(0));
      final errorState = src.indexOf(
          "error: 'Could not analyse the cart. Please try again.'",
          methodStart);
      final telemetryCall = src.indexOf(
          "'cart_auditor_notifier_non_200_response'", methodStart);
      expect(errorState, greaterThan(methodStart));
      expect(
        telemetryCall >= 0 && telemetryCall < errorState,
        isTrue,
        reason: 'the non-200 branch (a real ai-proxy failure that never '
            'throws) must log before setting the user-visible error state — '
            'mirrors scanImage\'s own non_200 fix one class up.',
      );
    });

    // Backfills a gap found while building this test: scanImage's own
    // non-200 branch fix (round-2 plan review, 2026-09-20) shipped with NO
    // regression test at all — only its catch-block sibling did. Since this
    // exact bounded-pin shape was already being written for analyseCart,
    // mirroring it onto scanImage costs one more test and closes a real,
    // previously-untested gap in already-shipped code.
    test('scanImage (sibling) logs scan_meal_notifier_non_200_response '
        'before the error-state assignment', () {
      final methodStart =
          src.indexOf('Future<void> scanImage(List<int> imageBytes)');
      expect(methodStart, greaterThanOrEqualTo(0));
      final errorState = src.indexOf(
          "error: 'Could not analyse the image. Please try again.'",
          methodStart);
      final telemetryCall =
          src.indexOf("'scan_meal_notifier_non_200_response'", methodStart);
      expect(errorState, greaterThan(methodStart));
      expect(
        telemetryCall >= 0 && telemetryCall < errorState,
        isTrue,
        reason: 'regression pin for the pre-existing, previously-untested '
            'round-2-review fix to scanImage\'s non-200 branch.',
      );
    });
  });
}
