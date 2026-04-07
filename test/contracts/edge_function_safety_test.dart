import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Safety tests for Edge Function deployment configuration and JWT handling.
///
/// **ROOT CAUSE (Fix 1):** The Supabase API gateway's `verify_jwt: true`
/// silently rejected valid JWTs before our function code ever ran. 100+
/// Edge Function calls returned 401, and the ai_chat_started_at column
/// was always NULL because the function body never executed.
///
/// **Fix:** Deploy with `verify_jwt: false` and validate JWT manually
/// inside the function using proper Base64URL decoding.
///
/// These tests verify the function source code contains the right patterns.
void main() {
  group('Edge Function: ai-proxy JWT handling', () {
    late String aiProxySource;

    setUpAll(() {
      final file = File('supabase/functions/ai-proxy/index.ts');
      expect(file.existsSync(), isTrue,
          reason: 'ai-proxy/index.ts must exist');
      aiProxySource = file.readAsStringSync();
    });

    test('uses Base64URL-safe decode (not raw atob)', () {
      // JWT payload uses Base64URL encoding with '-' and '_' characters.
      // Standard atob() expects '+' and '/' — it silently corrupts the decode.
      // The fix: replace('-', '+') and replace('_', '/')
      // Note: The source may use single or double quotes — check both.
      expect(
          aiProxySource.contains('replace(/-/g, "+")') ||
              aiProxySource.contains("replace(/-/g, '+')"),
          isTrue,
          reason:
              'Must convert Base64URL "-" to standard Base64 "+" before atob()');
      expect(
          aiProxySource.contains('replace(/_/g, "/")') ||
              aiProxySource.contains("replace(/_/g, '/')"),
          isTrue,
          reason:
              'Must convert Base64URL "_" to standard Base64 "/" before atob()');
    });

    test('adds Base64 padding before decode', () {
      // Base64 requires length to be a multiple of 4.
      // JWT payloads strip padding. We must re-add it.
      expect(aiProxySource, contains('base64.length % 4'),
          reason: 'Must pad Base64 string to multiple of 4 before atob()');
      // Source may use single or double quotes for the padding char
      expect(
          aiProxySource.contains("+= '='") ||
              aiProxySource.contains('+= "="'),
          isTrue,
          reason: 'Must add "=" padding characters');
    });

    test('checks JWT expiry manually', () {
      // Since verify_jwt is false, we must check exp claim ourselves
      expect(aiProxySource, contains('exp'),
          reason: 'Must read JWT exp claim for manual expiry check');
      expect(
          aiProxySource,
          matches(RegExp(
              r'Date\.now\(\)\s*/\s*1000\s*>\s*exp|exp\s*<\s*Date\.now\(\)\s*/\s*1000')),
          reason: 'Must compare current time against JWT exp claim');
    });

    test('extracts user_id from sub claim', () {
      // The user's UUID comes from the JWT 'sub' claim
      expect(aiProxySource, contains('.sub'),
          reason: 'Must extract user ID from JWT sub claim');
    });

    test('has manual JWT validation code (verify_jwt is disabled)', () {
      // Since verify_jwt is false on deployment, the function MUST
      // validate JWT manually. Check for the key comment/code.
      expect(
          aiProxySource.contains('verify_jwt') ||
              aiProxySource.contains('Manual') ||
              aiProxySource.contains('decodeJwt') ||
              aiProxySource.contains('atob'),
          isTrue,
          reason:
              'Function must contain manual JWT validation since '
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
