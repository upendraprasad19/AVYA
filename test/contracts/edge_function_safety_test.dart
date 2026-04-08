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

  group('Compile safety: no invalid Dart syntax patterns', () {
    test('no ?identifier pattern in map literals (Fix 3)', () {
      // Bug: 'exercise_logs': ?exerciseLogs was invalid Dart syntax.
      // The ? prefix on an identifier is only valid in null-aware operations
      // like ?. or ?? — not as a standalone value in a map literal.
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue);

      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        final lines = source.split('\n');

        for (int i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          // Match pattern: 'key': ?identifier  (invalid Dart)
          // But NOT: 'key': ?.something  or  'key': ?? something
          final match = RegExp(r"'[^']+'\s*:\s*\?[a-zA-Z_]\w*\s*[,}]")
              .hasMatch(line);
          expect(match, isFalse,
              reason:
                  '${entity.path}:${i + 1}: Contains "?identifier" in map literal. '
                  'This is invalid Dart. Use the variable name directly or null-aware operators.');
        }
      }
    });
  });
}
