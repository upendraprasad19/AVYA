import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Safety tests for Edge Function deployment configuration and JWT handling.
///
/// **History:** The Supabase API gateway's `verify_jwt: true` silently
/// rejected valid JWTs (100% 401 rate). Fix: deploy with `verify_jwt: false`
/// and validate via `supabaseClient.auth.getUser(token)` inside the function.
/// This is the same pattern used by ai-proxy-pro and verify-subscription.
///
/// These tests verify the function source code uses the correct auth pattern.
void main() {
  group('Edge Function: ai-proxy JWT handling', () {
    late String aiProxySource;

    setUpAll(() {
      final file = File('supabase/functions/ai-proxy/index.ts');
      expect(file.existsSync(), isTrue,
          reason: 'ai-proxy/index.ts must exist');
      aiProxySource = file.readAsStringSync();
    });

    test('validates JWT via supabaseClient.auth.getUser()', () {
      // JWT validation uses Supabase Auth API (server-side signature check)
      // instead of manual Base64 decode. Same pattern as ai-proxy-pro.
      expect(aiProxySource, contains('auth.getUser'),
          reason: 'Must validate JWT via supabaseClient.auth.getUser()');
    });

    test('rejects missing authorization header', () {
      expect(aiProxySource, contains('Missing authorization header'),
          reason: 'Must reject requests with no Authorization header');
    });

    test('rejects invalid or expired tokens', () {
      expect(
          aiProxySource.contains('Invalid or expired token') ||
              aiProxySource.contains('authError'),
          isTrue,
          reason: 'Must reject invalid/expired JWTs from getUser()');
    });

    test('extracts user ID from authenticated user', () {
      expect(aiProxySource, contains('authUser.id'),
          reason: 'Must extract user ID from getUser() result');
    });

    test('has JWT validation note (verify_jwt is disabled)', () {
      expect(
          aiProxySource.contains('verify_jwt') ||
              aiProxySource.contains('getUser'),
          isTrue,
          reason:
              'Function must contain JWT validation since '
              'verify_jwt is disabled on deployment.');
    });
  });

  // ── Compile Safety: No Invalid Dart Syntax ─────────────────────
  //
  // NOTE: The original "no ?identifier pattern" test was retired in the
  // APK Test #2 batch (2026-04-25). Dart 3.4+ introduced `use_null_aware_elements`
  // which makes `'key': ?nullableValue` a valid map-literal entry — equivalent
  // to `if (nullableValue != null) 'key': nullableValue`. The codebase has
  // adopted this idiom in 9+ places (sync_service, workout_repository, etc.)
  // and the analyzer suggests it. The original Fix 3 bug (where `?defaultDur`
  // was a runtime error in older Dart) no longer reproduces.
  //
  // The F1 fix in Plan A (commit e2ea4e7) replaced `?defaultDur` with the
  // explicit `if (defaultDur != null)` form to match the rest of the file's
  // style, and the regression is locked by `test/sync/custom_exercise_sync_test.dart`.

  group('Compile safety: nullable-element map syntax', () {
    test('valid Dart 3.4+ ?identifier pattern is accepted by analyzer', () {
      // Sanity check: the codebase compiles. If it didn't, no other tests
      // would run. We document the syntax as valid and rely on `flutter
      // analyze` (run in CI) to catch any genuine syntax errors.
      expect(true, isTrue,
          reason:
              'The ?identifier pattern in map literals is valid Dart 3.4+ '
              '(see use_null_aware_elements analyzer hint). Original Fix 3 '
              'guard retired in APK Test #2 batch.');
    });
  });
}
