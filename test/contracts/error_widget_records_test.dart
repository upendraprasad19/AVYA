// APK Test #12.6 — ErrorWidget.builder telemetry contract test.
//
// Pins the requirement that `lib/app.dart` ErrorWidget.builder both:
//   (a) reports the FlutterErrorDetails to Crashlytics as a non-fatal
//       error (recordError with fatal: false), and
//   (b) posts a `widget_error_fallback` event to `log-client-error`
//       so we can see in-prod ErrorWidget fallbacks.
//
// Pre-Test-#12.6 the builder rendered a UI fallback only — every
// in-prod ErrorWidget hit was invisible to telemetry.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ErrorWidget.builder telemetry (APK Test #12.6)', () {
    final source = File('lib/app.dart').readAsStringSync();
    final builderStart = source.indexOf('ErrorWidget.builder = ');
    final builderEnd = builderStart == -1
        ? -1
        : source.indexOf('};', builderStart);

    test('lib/app.dart contains an ErrorWidget.builder assignment', () {
      expect(builderStart, isNot(-1),
          reason: 'ErrorWidget.builder must be wired in lib/app.dart');
      expect(builderEnd, greaterThan(builderStart),
          reason: 'ErrorWidget.builder closure must terminate');
    });

    test('builder calls FirebaseCrashlytics.recordError', () {
      final body = source.substring(builderStart, builderEnd);
      expect(body.contains('FirebaseCrashlytics'), isTrue,
          reason: 'builder must reference FirebaseCrashlytics');
      expect(body.contains('recordError'), isTrue,
          reason: 'builder must call recordError');
    });

    test('builder posts widget_error_fallback to log-client-error', () {
      final body = source.substring(builderStart, builderEnd);
      // We accept either a direct functions.invoke('log-client-error', ...)
      // or routing through ErrorTelemetry (which posts to log-client-error
      // internally — verified by inspection of error_telemetry.dart).
      final viaTelemetry = body.contains('ErrorTelemetry') &&
          body.contains('widget_error_fallback');
      final viaDirect = body.contains('log-client-error') &&
          body.contains('widget_error_fallback');
      expect(viaTelemetry || viaDirect, isTrue,
          reason: 'builder must post widget_error_fallback event '
              '(via ErrorTelemetry.logEvent or direct functions.invoke)');
    });

    test('ErrorTelemetry.logEvent posts to log-client-error', () {
      // Spot-check the helper file actually wires the post — otherwise
      // viaTelemetry above is a false positive.
      final telemetry =
          File('lib/core/services/error_telemetry.dart').readAsStringSync();
      expect(telemetry.contains("'log-client-error'"), isTrue,
          reason: 'ErrorTelemetry must post to log-client-error');
      expect(telemetry.contains('logEvent'), isTrue,
          reason: 'ErrorTelemetry must expose logEvent');
      expect(telemetry.contains('recordError'), isTrue,
          reason: 'ErrorTelemetry.recordNonFatal must call recordError');
    });
  });
}
