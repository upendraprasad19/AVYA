// BEHAVIORAL CONTRACT TEST — referral_redemption (diagnose c7b4d2)
//
// Concept: referral_redemption
// Writer:  AuthNotifier.signUpWithEmail(referralCode:) → auth user metadata
//          `referral_code` (sign_in_screen CREATE ACCOUNT passes the field)
// Reader:  OnboardingNotifier.completeOnboarding → resolveReferralCode(stash,
//          userMetadata) → redeem-referral AFTER the users upsert
//
// The bug: the sign-in screen redeemed on AuthStatus.success from its own text
// field. With email confirmation on, sign-up ends with AuthStatus.info (no
// session), and the later sign-in is a fresh screen with an empty field — so
// the code the user typed was silently dropped.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/onboarding/providers/onboarding_provider.dart'
    show resolveReferralCode;

String _stripComments(String s) => s
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  group('resolveReferralCode', () {
    test('the Welcome-screen stash wins over metadata', () {
      expect(resolveReferralCode(' AVYA-1 ', {'referral_code': 'AVYA-2'}),
          'AVYA-1');
    });

    test('falls back to the code stored at sign-up (the c7b4d2 fix)', () {
      expect(resolveReferralCode('', {'referral_code': ' AVYA-2 '}), 'AVYA-2');
      expect(resolveReferralCode('   ', {'referral_code': 'AVYA-2'}), 'AVYA-2');
    });

    test('nothing to redeem resolves to empty', () {
      expect(resolveReferralCode('', null), '');
      expect(resolveReferralCode('', {}), '');
      expect(resolveReferralCode('', {'referral_code': '  '}), '');
      expect(resolveReferralCode('', {'referral_code': 42}), '',
          reason: 'a non-string metadata value is ignored, never stringified');
    });
  });

  group('wiring', () {
    final auth = _stripComments(
        File('lib/features/auth/providers/auth_provider.dart')
            .readAsStringSync());
    final signIn = _stripComments(
        File('lib/features/auth/screens/sign_in_screen.dart')
            .readAsStringSync());
    final onboarding = _stripComments(
        File('lib/features/onboarding/providers/onboarding_provider.dart')
            .readAsStringSync());

    test('signUpWithEmail stores the code in auth metadata', () {
      expect(auth.contains("data: code.isEmpty ? null : {'referral_code': code}"),
          isTrue);
    });

    test('CREATE ACCOUNT passes the referral field to signUpWithEmail', () {
      expect(signIn.contains('referralCode: _referralController.text'), isTrue);
    });

    test('the sign-in screen no longer redeems (it ran before the users row '
        'existed and only when a session came back)', () {
      expect(signIn.contains('redeem-referral'), isFalse);
      expect(signIn.contains('pending_referral_code'), isFalse);
    });

    test('onboarding resolves the code from the stash AND user metadata', () {
      expect(onboarding.contains('resolveReferralCode(stash, userMetadata)'),
          isTrue);
      expect(onboarding.contains('currentUser?.userMetadata'), isTrue);
    });
  });
}
