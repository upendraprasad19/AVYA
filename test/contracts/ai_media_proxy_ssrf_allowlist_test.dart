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
  });
}
