// Bug 2026-05-22 (diagnose 7b3eaf) regression test — pins the
// .catchError + .timeout + telemetry wrapper around
// SubscriptionService.gate's verifyFromServer() path.
//
// Pre-fix: `verifyFromServer().then((verified) { if (verified) onPro; else onFree; })`
// had no .catchError and no .timeout. When verify threw or hung,
// neither onPro nor onFree fired — button taps vanished silently.
// Founder hit this on GENERATE NEXT PHASE 2026-05-21.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  final src =
      File('lib/core/services/subscription_service.dart').readAsStringSync();
  final stripped = _stripComments(src);

  group('SubscriptionService.gate — verifyFromServer wrapper', () {
    test('.timeout(Duration(seconds: 10)) on verifyFromServer', () {
      expect(
        RegExp(r'verifyFromServer\(\)\s*\.timeout\(\s*const\s+Duration\(seconds:\s*10\)')
            .hasMatch(stripped),
        isTrue,
        reason: 'verifyFromServer() chain must have .timeout(Duration('
            'seconds: 10)) so a hung server cannot leave the button '
            'tap silently no-op-ing.',
      );
    });

    test('.catchError on verifyFromServer chain', () {
      expect(
        stripped.contains('.catchError('),
        isTrue,
        reason: 'gate() must .catchError(...) on the verifyFromServer '
            'chain. Pre-fix had no error handler and dropped both '
            'onPro/onFree branches on any throw.',
      );
    });

    test('catchError falls back to onPro (trust local state on server fail)',
        () {
      // The catchError body must call onPro() since the cheap isPro()
      // check at the top of gate already returned true. On server fail,
      // we trust local over blocking the user.
      expect(
        RegExp(r'\.catchError\([\s\S]{0,400}onPro\(\)').hasMatch(stripped),
        isTrue,
        reason: 'catchError body must call onPro() — local isPro() '
            'already returned true; on server fail we trust local '
            'rather than block the user.',
      );
    });

    test('subscription_gate_routed telemetry emitted on every exit', () {
      // Want >= 4 occurrences: not_pro_local, verify_timeout,
      // verify_pro/verify_failed, verify_threw, local_pro.
      final matches =
          RegExp(r"'subscription_gate_routed'").allMatches(stripped).length;
      expect(matches, greaterThanOrEqualTo(4),
          reason: 'subscription_gate_routed must fire at every gate exit '
              '(>= 4 callsites: not_pro_local, verify_timeout, verify_'
              'pro/failed, verify_threw, local_pro). Found $matches.');
    });
  });
}
