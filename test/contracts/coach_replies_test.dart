import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/ai_coach/copy/coach_replies.dart';

/// F17 · Test #9 — reply copy contract.
void main() {
  group('CoachReplies', () {
    test('welcomeBridge is on-brand (Bridge + Recruit + action words)', () {
      final w = CoachReplies.welcomeBridge;
      expect(w.contains('Bridge'), isTrue);
      expect(w.contains('Recruit'), isTrue);
      expect(w.contains('Workouts'), isTrue);
      expect(w.contains('nutrition'), isTrue);
      expect(w.contains('recovery'), isTrue);
    });

    test('freeImageCounter(4) shows "4 of 5 free analyses left"', () {
      expect(CoachReplies.freeImageCounter(4),
          contains('4 of 5 free analyses left'));
    });

    test('freeImageCounter(1) shows "Last free analysis used"', () {
      expect(CoachReplies.freeImageCounter(1),
          contains('Last free analysis used'));
    });

    test('freeImageCounter(0) shows "used your 5 free analyses"', () {
      expect(CoachReplies.freeImageCounter(0),
          contains('used your 5 free analyses'));
    });

    test('imagePaywallExhausted mentions Upgrade to PRO', () {
      expect(CoachReplies.imagePaywallExhausted,
          contains('Upgrade to PRO'));
    });

    test('videoPaywall mentions PRO + form check / technique', () {
      expect(CoachReplies.videoPaywall, contains('PRO'));
      expect(CoachReplies.videoPaywall, contains('form check'));
    });

    // OI-162 slice 3b — the fail-CLOSED refusal copy. B-pass finding 3: this
    // string shipped with ZERO assertions, and it is the exact text a real
    // production refusal shows when the quota ledger is unreadable.
    test('imageQuotaUnavailable never claims the user spent their quota', () {
      final c = CoachReplies.imageQuotaUnavailable;
      // The WHOLE POINT of this copy existing separately: reusing
      // imagePaywallExhausted would tell a user who may have spent NOTHING
      // that they had used all 5. Pin the absence, not just the presence.
      expect(c.contains('used your 5'), isFalse,
          reason: 'this refusal fires on a DB error, not on exhaustion — '
              'claiming a spent quota here is a lie');
      expect(c.contains('Upgrade'), isFalse,
          reason: 'this is not a paywall; upselling on an infrastructure '
              'failure is both wrong and unactionable');
      expect(c, contains('Recruit'), reason: 'on-brand (Wardroom voice)');
      expect(c.toLowerCase(), contains('again'),
          reason: 'the user must be told it is retryable');
      // MIRROR: the real paywall must still say the opposite, or this test
      // would keep passing after someone merged the two strings back together.
      expect(CoachReplies.imagePaywallExhausted, contains('used your 5'));
      expect(CoachReplies.imagePaywallExhausted, contains('Upgrade'));
    });

    test('imageQuotaUnavailable is byte-identical on client and server', () {
      // The two files each declare themselves a MIRROR of the other, and
      // nothing enforced it. A drifted pair is invisible: the server string is
      // what users see, the client copy is the fallback, and they can disagree
      // for months. Extract the TS literal and compare.
      final ts = File('supabase/functions/_shared/coach_replies.ts')
          .readAsStringSync();
      final decl = RegExp(
        r'imageQuotaUnavailable:\s*((?:\s*[' "'" r'"][^' "'" r'"]*[' "'" r'"]\s*\+?)+)\s*,',
      ).firstMatch(ts);
      expect(decl, isNotNull,
          reason: 'imageQuotaUnavailable must exist in the server copy file');
      final serverText = RegExp("['\"]([^'\"]*)['\"]")
          .allMatches(decl!.group(1)!)
          .map((m) => m.group(1)!)
          .join();
      expect(serverText, CoachReplies.imageQuotaUnavailable,
          reason: 'client and server copies of imageQuotaUnavailable have '
              'DRIFTED. Both files call themselves a mirror of the other; '
              'update both or neither.');
    });
  });
}
