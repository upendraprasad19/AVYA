// Source-grep contract for isPro() null-expiry kDebugMode guard.
//
// Originally landed as T-5 of `audit_2026_05_11_t1_t11_contracts_test.dart`.
// Split per concept per tech-debt audit 2026-05-20 T12.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String relPath) => File(relPath).readAsStringSync();

void main() {
  group('T-5 isPro() null-expiry kDebugMode guard', () {
    late String src;
    setUpAll(() {
      src = _src('lib/core/services/subscription_service.dart');
    });

    test('null expiry returns kDebugMode in release (not true)', () {
      // The guard must explicitly return `kDebugMode` (or false) when
      // expiresAt is null. Pre-fix: `return true` would let a rooted
      // device tamper with Hive to drop the expiresAt and gain PRO.
      expect(
        src.contains('kDebugMode'),
        isTrue,
        reason: 'isPro() must consult kDebugMode for the null-expiry '
            'path — null-expiry should grant PRO only in dev builds, '
            'never in release.',
      );
    });
  });
}
