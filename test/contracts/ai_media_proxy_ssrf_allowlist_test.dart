// Source-grep contract for the ai-media-proxy SSRF allowlist.
//
// Originally landed as T-4 of `audit_2026_05_11_t1_t11_contracts_test.dart`.
// Split per concept per tech-debt audit 2026-05-20 T12.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String relPath) => File(relPath).readAsStringSync();

void main() {
  group('T-4 ai-media-proxy SSRF allowlist', () {
    late String src;
    setUpAll(() {
      src = _src('supabase/functions/ai-media-proxy/index.ts');
    });

    test('only Supabase Storage prefix is accepted', () {
      // SSRF defence — server must only fetch from the canonical
      // `${SUPABASE_URL}/storage/v1/object/` prefix. Anything else
      // → reject.
      expect(
        src.contains('/storage/v1/object/'),
        isTrue,
        reason: 'ai-media-proxy must allowlist /storage/v1/object/ '
            'URLs only. SSRF risk: attacker-supplied URL could exfiltrate '
            'or trigger internal calls.',
      );
    });

    // Unit 8 (coach-media-consent, OI-25, 2026-07-30) — the bucket-name
    // set itself was NEVER pinned by a test (only the URL-prefix defence
    // above was), which is exactly how supabase/functions/CLAUDE.md's AI
    // architecture table went stale: it named `progress-photos` +
    // `chat-attachments` — a bucket that has never existed in this
    // codebase — for weeks with nothing to catch it. Pin the real set.
    test('ALLOWED_BUCKETS is exactly chat-media, coach-media, progress-photos',
        () {
      final idx = src.indexOf('const ALLOWED_BUCKETS');
      expect(idx, greaterThan(-1),
          reason: 'ALLOWED_BUCKETS declaration moved or renamed — '
              're-baseline this test');
      final decl = src.substring(idx, (idx + 200).clamp(0, src.length));

      for (final bucket in ['chat-media', 'coach-media', 'progress-photos']) {
        expect(decl.contains('"$bucket"'), isTrue,
            reason: 'ALLOWED_BUCKETS must include "$bucket"');
      }
      expect(decl.contains('chat-attachments'), isFalse,
          reason: 'chat-attachments is a phantom bucket name that has '
              'never existed in this codebase — its presence here would '
              'mean the allowlist regressed to match the stale doc rather '
              'than the doc having been corrected to match the code.');
    });
  });
}
