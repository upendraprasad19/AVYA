import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// APK Test #15.1 / Bug D — ai-media-proxy generic fallback must emit
/// telemetry so unmatched errors get a root-cause breadcrumb.
///
/// Pre-fix: when the photo-analysis flow caught an exception that didn't
/// match any of the specific patterns (Image too large, 5xx, PRO required,
/// SocketException, etc.), the user saw "Sorry, I couldn't analyse that
/// photo. Please try again." — but nothing was written to client_errors.
/// Founder reported repeated failures; we had zero data to diagnose.
///
/// Fix: in the generic fallback else-branch, log
/// `ai_media_proxy_unknown_error` with a clipped (500 char) version of
/// the original exception string. Next user report has actionable
/// telemetry attached.
///
/// closes-diagnose: 2026-05-12-ai-media-proxy-telemetry-d8e5b3
void main() {
  late String src;

  setUpAll(() {
    src = File('lib/features/ai_coach/providers/ai_coach_provider.dart')
        .readAsStringSync();
  });

  group('ai-media-proxy generic fallback telemetry', () {
    test('ErrorTelemetry imported into ai_coach_provider', () {
      expect(
        src.contains(
            "import 'package:icanbefitter/core/services/error_telemetry.dart'"),
        isTrue,
        reason:
            'ErrorTelemetry must be imported so the generic fallback can '
            'log an event for ops visibility.',
      );
    });

    test('generic fallback emits ai_media_proxy_unknown_error event', () {
      expect(
        src.contains("'ai_media_proxy_unknown_error'"),
        isTrue,
        reason:
            'The else-branch where errorMsg defaults to "Sorry, I couldn\'t '
            'analyse that photo." must call ErrorTelemetry.logEvent with '
            'op_type ai_media_proxy_unknown_error so unmatched failures '
            'leave a breadcrumb in client_errors. closes-diagnose: '
            '2026-05-12-ai-media-proxy-telemetry-d8e5b3',
      );
    });

    test('error message is clipped to 500 chars (db column safety)', () {
      // client_errors.error_message has a reasonable size bound; clip
      // long stack traces / payload dumps before writing.
      expect(
        src.contains('errStr2.length > 500'),
        isTrue,
        reason:
            'The fallback must clip the error string to a reasonable size '
            'before writing to client_errors. Some exceptions include full '
            'stack traces that would blow out the error_message column.',
      );
    });
  });
}
