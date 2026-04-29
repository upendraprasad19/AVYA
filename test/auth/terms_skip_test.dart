// Regression tests for Q2 privacy/terms implementation:
//   1. TermsModal gate logic (_shouldShowTermsModal equivalent).
//   2. Source-code structural assertions — welcome footer, signup checkbox,
//      cloud restore, button gate.
//
// Pure-logic tests don't open real Hive (avoids filesystem setup in CI).
// Source assertions give regression protection without production-code changes.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';

String _src(String relativePath) {
  final file = File('${Directory.current.path}/$relativePath');
  return file.readAsStringSync();
}

/// Mirrors TermsModal._alreadyAccepted() logic for pure-Dart unit testing
/// without opening Hive. Accepts the two box values directly.
bool _shouldShowTermsModal({
  required String? termsAcceptedAt,
  required String? termsVersion,
}) {
  final accepted = termsAcceptedAt is String && termsAcceptedAt.isNotEmpty;
  final versionMatch = termsVersion == AppConstants.termsVersion;
  return !(accepted && versionMatch);
}

void main() {
  // ── Pure logic: TermsModal gate ──────────────────────────────
  group('TermsModal gate logic', () {
    test('skips when current version timestamp present', () {
      expect(
        _shouldShowTermsModal(
          termsAcceptedAt: DateTime.now().toIso8601String(),
          termsVersion: AppConstants.termsVersion,
        ),
        false,
        reason: 'Modal should NOT fire when accepted at current version',
      );
    });

    test('shows when timestamp present but version stale', () {
      expect(
        _shouldShowTermsModal(
          termsAcceptedAt: DateTime.now().toIso8601String(),
          termsVersion: 'old-version',
        ),
        true,
        reason: 'Modal SHOULD fire when version is stale',
      );
    });

    test('shows when no timestamp', () {
      expect(
        _shouldShowTermsModal(
          termsAcceptedAt: null,
          termsVersion: null,
        ),
        true,
        reason: 'Modal SHOULD fire when no acceptance stamp',
      );
    });

    test('shows when empty string timestamp', () {
      expect(
        _shouldShowTermsModal(
          termsAcceptedAt: '',
          termsVersion: AppConstants.termsVersion,
        ),
        true,
        reason: 'Empty string should not count as accepted',
      );
    });
  });

  // ── Source assertions: welcome footer ────────────────────────
  group('welcome_screen: privacy footer', () {
    late String src;
    setUpAll(() {
      src = _src(
          'lib/features/onboarding/screens/welcome_screen.dart');
    });

    test('imports url_launcher', () {
      expect(src, contains("import 'package:url_launcher/url_launcher.dart'"),
          reason: 'url_launcher required for footer links');
    });

    test('footer text "By continuing" is present', () {
      expect(src, contains('By continuing, you agree to our'),
          reason: 'Welcome screen must show privacy/terms footer');
    });

    test('footer links to icanbefitter.com/privacy', () {
      expect(src, contains('icanbefitter.com/privacy'),
          reason: 'Privacy Policy URL must be present in welcome footer');
    });

    test('footer links to icanbefitter.com/terms', () {
      expect(src, contains('icanbefitter.com/terms'),
          reason: 'Terms URL must be present in welcome footer');
    });
  });

  // ── Source assertions: signup checkbox ───────────────────────
  group('sign_in_screen: privacy checkbox', () {
    late String src;
    setUpAll(() {
      src = _src('lib/features/auth/screens/sign_in_screen.dart');
    });

    test('_privacyAccepted state field present', () {
      expect(src, contains('_privacyAccepted'),
          reason: 'Checkbox state field must exist');
    });

    test('_PrivacyCheckboxRow widget used in email form', () {
      expect(src, contains('_PrivacyCheckboxRow'),
          reason: 'Checkbox row must be shown in sign-up email form');
    });

    test('checkbox gated by _isSignUp', () {
      expect(src, contains('if (_isSignUp)'),
          reason: 'Checkbox only shown during sign-up, not sign-in');
    });

    test('button enabled field gates on _privacyAccepted', () {
      expect(src, contains('!_isSignUp || _privacyAccepted'),
          reason: 'CREATE ACCOUNT button must be disabled when unchecked');
    });

    test('sign_in_screen links to icanbefitter.com/privacy', () {
      expect(src, contains('icanbefitter.com/privacy'),
          reason: 'Privacy Policy URL must be present in sign-up checkbox');
    });
  });

  // ── Source assertions: cloud restore ─────────────────────────
  group('auth_provider: cloud terms restore', () {
    late String src;
    setUpAll(() {
      src = _src('lib/features/auth/providers/auth_provider.dart');
    });

    test('queries terms_accepted_at from users table', () {
      expect(src, contains('terms_accepted_at'),
          reason:
              'auth_provider must read terms_accepted_at from Supabase users table');
    });

    test('queries terms_version from users table', () {
      expect(src, contains('terms_version'),
          reason:
              'auth_provider must read terms_version from Supabase users table');
    });

    test('writes terms_accepted_at to Hive on restore', () {
      expect(
        src,
        contains("userBox.put('terms_accepted_at'"),
        reason: 'Must write cloud terms timestamp to Hive on restore',
      );
    });

    test('writes terms_version to Hive on restore', () {
      expect(
        src,
        contains("userBox.put('terms_version'"),
        reason: 'Must write cloud terms version to Hive on restore',
      );
    });
  });

  // ── Source assertions: TermsModal gate in terms_modal.dart ───
  group('terms_modal: _alreadyAccepted guard', () {
    late String src;
    setUpAll(() {
      src = _src('lib/features/auth/widgets/terms_modal.dart');
    });

    test('checks terms_accepted_at in Hive', () {
      expect(src, contains("'terms_accepted_at'"),
          reason: 'Modal gate must read terms_accepted_at from Hive');
    });

    test('checks terms_version matches AppConstants.termsVersion', () {
      expect(src, contains('AppConstants.termsVersion'),
          reason: 'Modal gate must compare stored version to current constant');
    });

    test('barrierDismissible is false (blocking)', () {
      expect(src, contains('barrierDismissible: false'),
          reason: 'Modal must be non-dismissible until accepted');
    });
  });
}
