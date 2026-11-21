// Regression contract for APK +34 / obs 3 (diagnose d3a1c7): every authed
// Edge Function caller must send a FRESH USER token. Two failure modes fixed:
//   1. ai_service direct-HTTP fallbacks degraded the Bearer token to the anon
//      key (`... ?? AppConstants.supabaseAnonKey`) → ai-proxy 401 "Invalid or
//      expired token" → "AI is down".
//   2. sync_service called functions.invoke directly (daily-snapshot push +
//      two log-client-error) without refreshing → stale-token 401 (push_snapshot
//      lost the plan_json/coach_memory snapshot; failure telemetry vanished).
//
// Source-grep (presence-only) — the refresh primitive (ensureFreshToken /
// refreshSession) is exercised by supabase_service tests; this guards the
// callers from regressing back to anon-fallback / no-refresh.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _strip(String src) {
  var s = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  s = s
      .split('\n')
      .map((line) {
        final m = RegExp(r'(?<!:)//').firstMatch(line);
        return m == null ? line : line.substring(0, m.start);
      })
      .join('\n');
  return s;
}

void main() {
  group('authed EF callers send a fresh user token', () {
    test('ai_service never uses the anon key as the Bearer token', () {
      final src =
          _strip(File('lib/core/services/ai_service.dart').readAsStringSync());
      expect(src.contains('accessToken ?? AppConstants.supabaseAnonKey'), isFalse,
          reason:
              'authed ai-proxy/weekly-report Bearer must be a USER token, never anon');
      expect(src.contains('throw AiServiceException'), isTrue,
          reason: 'no session → fail clearly (re-auth), not a silent anon 401');
    });

    test('sync_service refreshes the token before authed EF invokes', () {
      final src = _strip(
          File('lib/core/services/sync_service.dart').readAsStringSync());
      expect('_supabase.ensureFreshToken()'.allMatches(src).length,
          greaterThanOrEqualTo(3),
          reason:
              'daily-snapshot push + the two log-client-error invokes must refresh first');
    });
  });
}
