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

    test('checkbox shown only in the sign-up step builder', () {
      // Email-first flow (2026-07): the checkbox is no longer gated by a
      // manual sign-in/sign-up toggle — it lives unconditionally inside the
      // sign-up-only step builder, reached automatically via the
      // server-side email-registration check.
      expect(src, contains('_buildEmailStepSignUp'),
          reason: 'Sign-up-only fields (checkbox, referral) must live in '
              'their own step builder, not gated inline by a manual toggle');
    });

    test('button enabled field gates on _privacyAccepted', () {
      expect(src, contains('enabled: _privacyAccepted'),
          reason: 'CREATE ACCOUNT button must be disabled when unchecked');
    });

    test('sign_in_screen links to icanbefitter.com/privacy', () {
      expect(src, contains('icanbefitter.com/privacy'),
          reason: 'Privacy Policy URL must be present in sign-up checkbox');
    });
  });

  // ── Source assertions: cloud restore ─────────────────────────
  //
  // Audit 2026-05-20 / A1: cloud-terms-restore logic relocated from
  // auth_provider.dart into AuthSessionBootstrapper.hydrateFromCloud
  // (lib/core/services/auth_session_bootstrapper.dart). The source-grep
  // assertions now look in BOTH files — auth_provider for any remaining
  // surface, AuthSessionBootstrapper for the canonical writer. Per
  // `feedback_source_grep_false_confidence.md`, this is presence-only;
  // the behavioral test lives at
  // `test/contracts/auth_session_bootstrapper_test.dart`.
  group('cloud terms restore (auth_provider OR bootstrapper)', () {
    late String authSrc;
    late String bootstrapperSrc;
    setUpAll(() {
      authSrc = _src('lib/features/auth/providers/auth_provider.dart');
      bootstrapperSrc = _src(
          'lib/core/services/auth_session_bootstrapper.dart');
    });

    test('queries terms_accepted_at from users table', () {
      final inAuth = authSrc.contains('terms_accepted_at');
      final inBootstrapper = bootstrapperSrc.contains('terms_accepted_at');
      expect(inAuth || inBootstrapper, isTrue,
          reason:
              'terms_accepted_at must be read from Supabase users table in '
              'auth_provider OR auth_session_bootstrapper.');
    });

    test('queries terms_version from users table', () {
      final inAuth = authSrc.contains('terms_version');
      final inBootstrapper = bootstrapperSrc.contains('terms_version');
      expect(inAuth || inBootstrapper, isTrue,
          reason:
              'terms_version must be read from Supabase users table.');
    });

    test('writes terms_accepted_at to Hive on restore', () {
      final pattern = "userBox.put('terms_accepted_at'";
      final inAuth = authSrc.contains(pattern);
      final inBootstrapper = bootstrapperSrc.contains(pattern);
      expect(inAuth || inBootstrapper, isTrue,
          reason: 'Must write cloud terms timestamp to Hive on restore.');
    });

    test('writes terms_version to Hive on restore', () {
      final pattern = "userBox.put('terms_version'";
      final inAuth = authSrc.contains(pattern);
      final inBootstrapper = bootstrapperSrc.contains(pattern);
      expect(inAuth || inBootstrapper, isTrue,
          reason: 'Must write cloud terms version to Hive on restore.');
    });
  });

  // audit-fixwave 2026-07-02 / F15 — the TermsModal source-assertion group was
  // removed with the dead TermsModal widget (zero call sites; the sign-in
  // trigger was removed in the Test #4 / OBS-A batch). The live terms-acceptance
  // write lives in sign_in_screen.dart (asserted above) and is now pinned by the
  // `terms_acceptance` SoT concept + terms_acceptance_writer_to_reader_test.
}
