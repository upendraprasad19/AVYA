// Source-grep contract for gate() routing high-value features through
// verifyFromServer.
//
// Originally landed as T-6 of `audit_2026_05_11_t1_t11_contracts_test.dart`.
// Split per concept per tech-debt audit 2026-05-20 T12.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String relPath) => File(relPath).readAsStringSync();

void main() {
  group('T-6 gate() routes high-value features through verifyFromServer', () {
    late String src;
    setUpAll(() {
      src = _src('lib/core/services/subscription_service.dart');
    });

    test('_highValueFeatures set contains the 3 server-verified features', () {
      expect(src.contains('_highValueFeatures'), isTrue);
      expect(src.contains('featurePhases2To12'), isTrue,
          reason: 'phases_2_to_12 must be server-verified.');
      expect(src.contains('featureAiCoachUnlimited'), isTrue,
          reason: 'ai_coach_unlimited must be server-verified.');
      expect(src.contains('featureProgressPhotos'), isTrue,
          reason:
              'progress_photos must be server-verified (Storage write surface).');
    });

    test('gate() calls verifyFromServer for high-value features', () {
      // OI-44 Unit 6 renamed gate() -> gateAndVerify() and changed the return
      // type from `void` to `Future<void>` (so a caller can finally await the
      // decision — diagnose 7b3eaf). This used to pin the literal `void gate(`,
      // which is a SPELLING, not the contract. Pin the method that actually
      // routes high-value features instead.
      final gateIdx = src.indexOf('Future<void> gateAndVerify(');
      expect(gateIdx, greaterThan(0),
          reason: 'the high-value routing entry point must exist '
              '(gateAndVerify; gate() survives only as a @Deprecated shim).');
      final body = src.substring(
          gateIdx, (gateIdx + 6000).clamp(0, src.length));
      expect(
        body.contains('verifyFromServer'),
        isTrue,
        reason: 'gate() body must call verifyFromServer for the '
            '_highValueFeatures set. Local-only check is insufficient '
            'for features that write to Storage / spend cloud quota.',
      );
    });
  });
}
