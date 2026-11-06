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
      // The catchError body must dispatch onPro since the cheap isPro()
      // check at the top already returned true. On server fail, we trust
      // local over blocking the user.
      //
      // OI-44 Unit 6 — the callback is now routed through `dispatchOnce(onPro,
      // ...)` rather than a bare `onPro()`. That was a B-pass FIX, not a
      // regression: with the bare call, `.catchError` guarded the callbacks
      // too, so a THROWING onFree() (paywall) landed here and called onPro() —
      // silently granting a PRO feature to a free user. The latch makes
      // exactly-once dispatch structural. This assertion accepts either
      // spelling so it pins the SEMANTIC (catchError leads to the PRO branch)
      // rather than one literal call shape.
      expect(
        RegExp(r'\.catchError\([\s\S]{0,500}(dispatchOnce\(\s*onPro|onPro\(\))')
            .hasMatch(stripped),
        isTrue,
        reason: 'catchError body must route to onPro — local isPro() '
            'already returned true; on server fail we trust local '
            'rather than block the user.',
      );
    });

    test('exactly-once dispatch latch guards the verify branch', () {
      // The behavioural half lives in
      // test/contracts/subscription_cqrs_behavioral_test.dart group F
      // (a throwing onFree must not escalate into a PRO grant). This pins the
      // mechanism so a refactor cannot quietly drop it.
      expect(stripped.contains('var dispatched = false'), isTrue,
          reason: 'the verify branch needs a latch so .then and .catchError '
              'cannot both fire a callback');
      expect(stripped.contains('if (dispatched) return'), isTrue,
          reason: 'the latch must short-circuit a second dispatch');
    });

    test('subscription_gate_routed telemetry emitted on every exit', () {
      // OI-44 Unit 6 — this used to demand >= 4 literal occurrences of the
      // event name. That counted CALLSITES, not exits: the verify branch's
      // four exits now share one emitter inside `dispatchOnce`, so the literal
      // count dropped to 3 while the number of instrumented exits went UP
      // (the timeout path previously logged an exit it did not take). Pinning
      // a callsite count punishes de-duplication, so this now pins the exit
      // REASONS, which is what a telemetry query actually selects on.
      final matches =
          RegExp(r"'subscription_gate_routed'").allMatches(stripped).length;
      expect(matches, greaterThanOrEqualTo(2),
          reason: 'subscription_gate_routed must still be emitted. '
              'Found $matches.');
      for (final reason in const [
        'not_pro_local',
        'verify_pro',
        'verify_failed',
        'verify_threw',
        'local_pro',
      ]) {
        expect(stripped.contains(reason), isTrue,
            reason: 'every gate exit must be distinguishable in telemetry; '
                'missing reason "$reason"');
      }
    });
  });
}
