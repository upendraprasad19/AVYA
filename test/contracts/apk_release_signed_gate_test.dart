// test/contracts/apk_release_signed_gate_test.dart
//
// Gate 48 (scripts/check_apk_release_signed.dart) — asserts a built APK is
// signed with the release cert (CN=ICANBEFITTER), not the Android debug key.
// Founded 2026-06-05: the gitignored key.properties → debug-sign fallback is
// the most likely reason APK +32 never installed over the founder's +28.
//
// Behavioral coverage of the pure parse/verdict functions (no apksigner needed)
// + source-grep wiring (pre-commit case-skip + Gate 33 allowlist + /build-apk).

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../scripts/check_apk_release_signed.dart'
    show parseSigner, evaluateSigner, SignerInfo, kExpectedSha256;

const _releaseOut = '''
Verifies
Verified using v2 scheme (APK Signature Scheme v2): true
V2 Signer: certificate DN: CN=ICANBEFITTER, OU=Mobile, O=ICANBEFITTER, L=Mumbai, ST=MH, C=IN
V2 Signer: certificate SHA-256 digest: 436eacbb5cdcd7876fd9819ff5d37dde97bbc7be17e1cd2498f27ba4d2f322d8
''';

const _debugOut = '''
Verifies
Verified using v2 scheme (APK Signature Scheme v2): true
Signer #1 certificate DN: C=US, O=Android, CN=Android Debug
Signer #1 certificate SHA-256 digest: 0000000000000000000000000000000000000000000000000000000000000000
''';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');

void main() {
  group('Gate 48 — parseSigner (pure)', () {
    test('extracts DN + SHA from "V2 Signer:" output', () {
      final info = parseSigner(_releaseOut);
      expect(info.dn, contains('ICANBEFITTER'));
      expect(info.sha256,
          '436eacbb5cdcd7876fd9819ff5d37dde97bbc7be17e1cd2498f27ba4d2f322d8');
    });
    test('extracts DN from "Signer #1" debug output', () {
      expect(parseSigner(_debugOut).dn, contains('Android Debug'));
    });
    test('no signer lines → nulls', () {
      final info = parseSigner('Verifies\nDONE\n');
      expect(info.dn, isNull);
      expect(info.sha256, isNull);
    });
  });

  group('Gate 48 — evaluateSigner (pure verdict)', () {
    test('release cert + matching pinned SHA → PASS', () {
      expect(evaluateSigner(parseSigner(_releaseOut)).ok, isTrue);
    });
    test('debug-signed → FAIL, message names DEBUG', () {
      final v = evaluateSigner(parseSigner(_debugOut));
      expect(v.ok, isFalse);
      expect(v.message.toUpperCase(), contains('DEBUG'));
    });
    test('release DN but wrong SHA → FAIL (mismatch — wrong keystore)', () {
      final v = evaluateSigner(const SignerInfo('CN=ICANBEFITTER, O=ICANBEFITTER',
          'deadbeef00000000000000000000000000000000000000000000000000000000'));
      expect(v.ok, isFalse);
      expect(v.message.toLowerCase(), contains('mismatch'));
    });
    test('unparseable signer → FAIL', () {
      expect(evaluateSigner(const SignerInfo(null, null)).ok, isFalse);
    });
    test('pin disabled + org present + not debug → PASS (soft mode)', () {
      expect(
        evaluateSigner(const SignerInfo('CN=ICANBEFITTER, O=ICANBEFITTER', 'x'),
                expectedSha: '')
            .ok,
        isTrue,
      );
    });
  });

  group('Gate 48 — wiring', () {
    test('pinned SHA equals the +33 release cert', () {
      expect(kExpectedSha256,
          '436eacbb5cdcd7876fd9819ff5d37dde97bbc7be17e1cd2498f27ba4d2f322d8');
    });
    test('gate is skipped by the pre-commit dynamic loop (case block)', () {
      expect(File('scripts/pre-commit.sh').readAsStringSync(),
          contains('check_apk_release_signed.dart'));
    });
    test('gate is in check_gate_scripts_wired allowlist', () {
      expect(_strip(File('scripts/check_gate_scripts_wired.dart').readAsStringSync()),
          contains("'check_apk_release_signed.dart':"));
    });
    test('/build-apk invokes the gate with --release post-build', () {
      expect(File('.claude/commands/build-apk.md').readAsStringSync(),
          contains('check_apk_release_signed.dart --release'));
    });
  });
}
