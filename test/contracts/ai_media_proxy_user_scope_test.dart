// Contract test — `ai-media-proxy/index.ts` MUST assert the Storage URL
// belongs to the authenticated user BEFORE the service-role fetch.
//
// Closes OI-28 (audit-2026-05-17 Hermes F3). Pre-fix `fetchImageAsBase64`
// only validated the URL started with `${SUPABASE_URL}/storage/v1/object/`
// — any authenticated user could supply ANOTHER user's private Storage
// URL and the service-role fetch would happily pull the bytes + send
// them to Gemini. RLS doesn't apply to service role; application code is
// the only guard.
//
// This test pins the FOUR critical assertions:
//   1. `fetchImageAsBase64` takes `authUserId` as its second arg.
//   2. The function asserts `path.startsWith(${authUserId}/)`.
//   3. An ALLOWED_BUCKETS allowlist exists.
//   4. The 403 "authorization" error_type is used when scope check fails.
//
// Lens L23 (service-role authz defense-in-depth) — see
// `docs/audit/LENS_REGISTRY.md`.

import 'dart:io';
import 'package:test/test.dart';

const _path = 'supabase/functions/ai-media-proxy/index.ts';

void main() {
  group('ai-media-proxy OI-28 user-scope contract', () {
    test('fetchImageAsBase64 signature requires authUserId', () {
      final src = File(_path).readAsStringSync();
      // Match `async function fetchImageAsBase64(...args...): Promise<...>`
      final sigRegex = RegExp(
        r'async\s+function\s+fetchImageAsBase64\s*\(([^)]*)\)',
        multiLine: true,
      );
      final match = sigRegex.firstMatch(src);
      expect(match, isNotNull,
          reason: 'fetchImageAsBase64 declaration not found');
      final params = match!.group(1)!;
      expect(
        params.contains('authUserId'),
        isTrue,
        reason:
            'fetchImageAsBase64 must accept `authUserId` parameter so it can '
            'assert Storage path user-scope. Without it the OI-28 SSRF fix '
            'is incomplete.',
      );
    });

    test('parseStorageUrl helper exists', () {
      final src = File(_path).readAsStringSync();
      expect(
        RegExp(r'function\s+parseStorageUrl\s*\(').hasMatch(src),
        isTrue,
        reason:
            'expected `parseStorageUrl` helper. Without it, the URL → bucket+path '
            'decomposition lives inline + cannot be unit-tested for the 3 '
            'Storage URL shapes (public / sign / authenticated).',
      );
    });

    test('ALLOWED_BUCKETS allowlist is enforced', () {
      final src = File(_path).readAsStringSync();
      expect(
        src.contains('ALLOWED_BUCKETS'),
        isTrue,
        reason: 'expected ALLOWED_BUCKETS allowlist constant',
      );
      // The 3 user-tagged buckets per migration 070.
      expect(src.contains('chat-media'), isTrue);
      expect(src.contains('coach-media'), isTrue);
      expect(src.contains('progress-photos'), isTrue);
      // Allowlist check inside fetchImageAsBase64.
      expect(
        RegExp(r'ALLOWED_BUCKETS\.has\s*\(').hasMatch(src),
        isTrue,
        reason: 'expected `ALLOWED_BUCKETS.has(...)` check',
      );
    });

    test('user-scope assertion uses path.startsWith(authUserId)', () {
      final src = File(_path).readAsStringSync();
      // The assertion must reference both `path` (or `parsed.path`) and
      // the `authUserId` parameter. We accept either explicit form.
      final scopeCheck = RegExp(
        r'parsed\.path\.startsWith\s*\(\s*`\$\{authUserId\}/`\s*\)',
      );
      expect(
        scopeCheck.hasMatch(src),
        isTrue,
        reason:
            'expected `parsed.path.startsWith(`\${authUserId}/`)` assertion. '
            'Without it any authenticated user can request any Storage path. '
            'Matches Storage RLS shape: `(storage.foldername(name))[1] = '
            '(auth.uid())::text`.',
      );
    });

    test('403 authorization error fires on path mismatch', () {
      final src = File(_path).readAsStringSync();
      // Look for HttpError(403, "authorization", ...) near the path-scope
      // check. The constructor signature is `new HttpError(status, type, msg)`.
      final errorRegex = RegExp(
        r'HttpError\s*\(\s*403\s*,\s*["' "'" r']authorization["' "'" r']',
      );
      expect(
        errorRegex.hasMatch(src),
        isTrue,
        reason:
            'expected `HttpError(403, "authorization", ...)` when the user-scope '
            'check fails. Pre-fix there was no 403 path at all; client error '
            'mapping needs the 403 + "authorization" error_type to render the '
            'right user message.',
      );
    });

    test('fetchImageAsBase64 call passes userId', () {
      final src = File(_path).readAsStringSync();
      // The serve() handler must pass `userId` as the second argument.
      // Allow whitespace + newlines between args (the call spans 3 lines
      // in the canonical Prettier-style layout).
      final callRegex = RegExp(
        r'await\s+fetchImageAsBase64\s*\(\s*media_url\s*,\s*userId\s*,?\s*\)',
        multiLine: true,
        dotAll: true,
      );
      expect(
        callRegex.hasMatch(src),
        isTrue,
        reason:
            'expected serve handler to call '
            '`await fetchImageAsBase64(media_url, userId)` (any whitespace/newline). '
            'The OI-28 fix is incomplete if the handler still calls with one arg.',
      );
    });
  });
}
