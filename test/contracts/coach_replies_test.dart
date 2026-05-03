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
  });
}
