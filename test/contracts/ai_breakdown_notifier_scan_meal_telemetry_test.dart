// Scan Meal failed instantly on any full-resolution camera photo because
// ai-proxy rejects payloads over ~5.6MB decoded before ever calling Gemini
// (diagnose scan-meal-image-too-large). This test pins that the ScanMealNotifier
// catch block records telemetry via ErrorTelemetry.recordNonFatal(reason:
// 'scan_meal_notifier_scan_image') whenever scanImage() throws — a real call
// through the real method body, not a source-grep. This mirrors the
// ai_breakdown_notifier_save_meal_telemetry_test.dart fault-injection pattern.
//
// Writer: nutrition_provider.dart ScanMealNotifier.scanImage
// Reader: ErrorTelemetry.recordNonFatal -> client_errors
//         (op_type = 'scan_meal_notifier_scan_image')

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ErrorTelemetry.debugOnRecordNonFatalForTests = null;
    ScanMealNotifier.throwBeforeScanForTest = null;
  });

  tearDown(() {
    ErrorTelemetry.debugOnRecordNonFatalForTests = null;
    ScanMealNotifier.throwBeforeScanForTest = null;
  });

  test(
      'ScanMealNotifier.scanImage records telemetry on failure via ErrorTelemetry.recordNonFatal',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(scanMealProvider.notifier);

    Object? capturedError;
    String? capturedReason;
    ErrorTelemetry.debugOnRecordNonFatalForTests =
        (error, stack, {required reason, extra}) {
      capturedError = error;
      capturedReason = reason;
    };

    final injected = StateError('simulated ai-proxy failure');
    ScanMealNotifier.throwBeforeScanForTest = injected;

    await notifier.scanImage([1, 2, 3]);

    expect(capturedReason, 'scan_meal_notifier_scan_image',
        reason:
            'the catch block must report via ErrorTelemetry with this exact '
            'op_type so a recurrence is diagnosable in client_errors');
    expect(capturedError, same(injected));
  });
}
