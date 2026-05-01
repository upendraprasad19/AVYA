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

  // Note: the original "no ?identifier in map literals" check was retired
  // 2026-04-28. Dart 3.4+ added `use_null_aware_elements` lint making
  // `?identifier` a VALID nullable-element shorthand for
  // `if (x != null) 'key': x`. CLAUDE.md §19 documents this. The codebase
  // actively uses the syntax (`?dobIso`, `?wakeIso`, `?defaultDur`, etc.).
  // Removing the check keeps the test file as a placeholder for future
  // Edge Function safety contracts.
}
