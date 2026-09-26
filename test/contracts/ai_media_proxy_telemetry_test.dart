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

  group('sendWithMedia catch — EVERY branch telemetered (A5/OI-226, f7a2c9, '
      '2026-09-21)', () {
    // Pre-fix, only the generic fallback branch (tested above) called
    // ErrorTelemetry — the other 6 branches (no-internet, image-too-large,
    // storage-upload-incomplete, message-too-long, PRO-required,
    // Gemini-502/503/504) showed the user a distinct error chat bubble with
    // ZERO telemetry, confirmed live via client_errors returning zero rows
    // for a fully-reproduced Gemini-error/storage-timeout incident. Bounded,
    // position-scoped (not a whole-file `contains`, which could pass even if
    // the new log call were unreachable or misplaced — the exact
    // feedback_green_check_input_set_width class): extracts sendWithMedia's
    // own catch block and asserts the unconditional log call appears BEFORE
    // the first branch condition, proving it truly fires unconditionally.
    test('ai_coach_send_with_media_failed logged BEFORE any branch check',
        () {
      final catchStart = src.indexOf('} catch (e) {\n      final errStr2 =');
      expect(catchStart, greaterThanOrEqualTo(0),
          reason: 'sendWithMedia\'s catch block opening not found — '
              'has the method been restructured?');
      final firstBranch = src.indexOf(
          "if (errStr2.contains('Failed host lookup')", catchStart);
      final telemetryCall = src.indexOf(
          "ErrorTelemetry.logEvent('ai_coach_send_with_media_failed'",
          catchStart);
      expect(firstBranch, greaterThan(catchStart));
      expect(
        telemetryCall >= 0 && telemetryCall < firstBranch,
        isTrue,
        reason: 'ai_coach_send_with_media_failed must be logged BEFORE the '
            'branch chain so every branch (not just the fallback) leaves a '
            'client_errors breadcrumb — mirrors the sibling send() method\'s '
            'own unconditional-log-at-top-of-catch pattern.',
      );
    });
  });
}
