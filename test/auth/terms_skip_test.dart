// Regression tests for the Q2 privacy/terms implementation: source-code
// structural assertions - welcome footer, the sign-up consent notice (no
// checkbox since 2026-10-16), cloud restore. They don't open real Hive (avoids
// filesystem setup in CI) and give regression protection without
// production-code changes.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _src(String relativePath) {
  final file = File('${Directory.current.path}/$relativePath');
  return file.readAsStringSync();
}

void main() {
  // The 'TermsModal gate logic' group was removed 2026-10-16 (OI-305 review):
  // it tested a test-local copy of a gate whose widget no longer exists in lib/
  // (nothing compares terms_version; OI-346), so it could not fail on any real
  // change.

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
  // OI-305 (founder decision 2026-10-16): the email sign-up consent is a
  // "By tapping CREATE ACCOUNT, you agree to ..." notice, NOT a checkbox. This
  // group used to pin the unchecked checkbox (the 2026-08-24 Play-launch
  // change); it is repointed, not loosened: the new design is pinned by what it
  // must be and by what must stay gone. Presence-only, said honestly; the
  // behaviour (button enabled without a tick, the tap stamps time + version) is
  // test/auth/sign_up_consent_notice_test.dart.
  group('sign_in_screen: consent notice (no checkbox)', () {
    late String src;
    late String code; // comments stripped
    setUpAll(() {
      src = _src('lib/features/auth/screens/sign_in_screen.dart');
      code = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
    });

    test('_ConsentNotice is shown in the sign-up step', () {
      // With the trailing comma: the use in the Column, not the class's own
      // `const _ConsentNotice();` constructor.
      expect(code, contains('const _ConsentNotice(),'));
      expect(code, contains('By tapping CREATE ACCOUNT, you agree to our '));
    });

    test('the checkbox row and its state field are gone', () {
      expect(code, isNot(contains('_PrivacyCheckboxRow')));
      expect(code, isNot(contains('_privacyAccepted')));
      expect(code, isNot(contains('Checkbox(')));
    });

    test('CREATE ACCOUNT is not gated on any consent state', () {
      final call = RegExp(
        r"label:\s*'CREATE ACCOUNT'[\s\S]*?onPressed:",
      ).firstMatch(code);
      expect(call, isNotNull,
          reason: 'could not find the CREATE ACCOUNT button call at all - '
              'this guard has stopped checking anything');
      expect(call!.group(0), isNot(contains('enabled:')),
          reason: 'the form validation is the only gate on the button');
    });

    test('sign-up-only fields live in their own step builder', () {
      // Email-first flow (2026-07): the consent notice and the referral field
      // live unconditionally inside the sign-up-only step builder, reached
      // automatically via the server-side email-registration check.
      expect(src, contains('_buildEmailStepSignUp'));
    });

    test('sign_in_screen links to icanbefitter.com/privacy and /terms', () {
      expect(src, contains('icanbefitter.com/privacy'));
      expect(src, contains('icanbefitter.com/terms'));
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
