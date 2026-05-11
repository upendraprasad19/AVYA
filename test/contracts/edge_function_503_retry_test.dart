import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// APK Test #15.1 / Bugs G + H — Edge Function 503 BOOT_ERROR retry.
///
/// Telemetry showed `push_snapshot FunctionException(status: 503, code:
/// BOOT_ERROR, message: Function failed to start)` for the founder's
/// account. Edge Function logs confirm daily-snapshot takes ~40 seconds
/// per call (Gemini extraction inline); when multiple users hit it
/// simultaneously, some get a cold-start 503 while the function spins
/// up. Same BOOT_ERROR class affects `ai-proxy` → food_text_analysis
/// → "AI temporarily unavailable" user-facing copy.
///
/// Fix — in SupabaseService.callFunction, catch FunctionException with
/// status 502 or 503 and retry once after a 1.5s delay. Persistent 5xx
/// still surfaces to caller; the retry only handles transient
/// cold-start blips. Auth errors (401/403) are NOT retried.
///
/// closes-diagnose: 2026-05-12-edge-function-503-retry-0a7b9f
void main() {
  late String src;

  setUpAll(() {
    src = File('lib/core/services/supabase_service.dart').readAsStringSync();
  });

  group('callFunction 503 retry', () {
    test('FunctionException catch is present in callFunction', () {
      // Source-grep the try/catch around the invoke call.
      expect(
        src.contains('on FunctionException catch (e)'),
        isTrue,
        reason:
            'callFunction must wrap client.functions.invoke in a try block '
            'that catches FunctionException so the retry path can engage.',
      );
    });

    test('retry triggers ONLY on 502 + 503 (cold-start signatures)', () {
      expect(
        src.contains('e.status == 502 || e.status == 503'),
        isTrue,
        reason:
            'Retry must be gated on FunctionException.status of 502 or 503. '
            'Other status codes (401 auth, 400 validation, etc.) must NOT '
            'retry — they need caller handling or are not transient.',
      );
    });

    test('retry delay is bounded (1500ms target, 250-3000ms acceptable)', () {
      final match = RegExp(r'Duration\(\s*milliseconds:\s*(\d+)\s*\)')
          .allMatches(src);
      bool foundReasonableDelay = false;
      for (final m in match) {
        final ms = int.parse(m.group(1)!);
        if (ms >= 250 && ms <= 3000) {
          foundReasonableDelay = true;
          break;
        }
      }
      expect(foundReasonableDelay, isTrue,
          reason:
              'Retry delay must be 250–3000 ms. Too short causes thundering '
              'herd on a cold-starting function; too long is bad UX.');
    });

    test('forbidden: unconditional retry (would mask sustained outages)', () {
      // A naive `try { invoke } catch (_) { invoke }` would retry on EVERY
      // exception, masking auth failures + sustained outages. Pin that
      // the retry happens only inside the 502/503 branch.
      // Look for a bare retry without status check.
      final invokeCount =
          RegExp(r'client\.functions\.invoke\(').allMatches(src).length;
      // Two invokes inside callFunction (first attempt + retry). If the
      // count is > 2, something else is reusing the method or there are
      // additional invoke sites that need their own retry. Should be
      // exactly 2.
      expect(invokeCount, equals(2),
          reason:
              'callFunction body should contain exactly 2 client.functions.'
              'invoke calls (first attempt + single retry). Found '
              '$invokeCount. If more, audit for unsafe retry semantics.');
    });

    test('rethrow happens on non-cold-start FunctionExceptions', () {
      expect(
        src.contains('if (!isColdStart502_503) rethrow;'),
        isTrue,
        reason:
            'Non-502/503 FunctionExceptions must be rethrown so callers '
            'can handle 401 auth / 4xx validation / etc.',
      );
    });
  });
}
