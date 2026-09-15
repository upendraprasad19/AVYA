// test/contracts/terms_acceptance_writer_to_reader_test.dart
//
// SoT contract for terms_acceptance (audit-fixwave 2026-07-02 / F15). The DPDP
// ToS/Privacy acceptance write had no drift-protection concept. Comment-stripped.
//
// Updated 2026-08-02 (closes-diagnose: b3f9e7) — the write moved OUT of
// sign_in_screen.dart (which now only captures the consent values at CREATE
// ACCOUNT tap time and passes them through to signUpWithEmail) and INTO
// auth_provider.dart's _ensureLocalUser, which stamps Hive only AFTER
// HiveUserSession.openForUser has actually opened the box. The pre-fix write
// lived directly in sign_in_screen.dart and threw StateError on every call
// (no session existed yet) — see docs/diagnoses/2026-08-02-terms-accepted-
// dead-write-b3f9e7.md. These are PRESENCE checks only; the actual runtime
// behavior (throws-before-openForUser / persists-after) is pinned by the
// genuine Hive round-trip in test/contracts/terms_acceptance_behavioral_test.dart
// — per feedback_source_grep_false_confidence.md, source-grep alone is not
// sufficient and is not this concept's behavioral_test_path.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/read_screen_source.dart';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  final signin = _strip(
      File('lib/features/auth/screens/sign_in_screen.dart').readAsStringSync());
  final authProvider = _strip(
      File('lib/features/auth/providers/auth_provider.dart')
          .readAsStringSync());
  final boot = _strip(File('lib/core/services/auth_session_bootstrapper.dart')
      .readAsStringSync());
  final restoringScreen = _strip(
      readRestoringScreenSource());

  group('terms_acceptance writer→reader contract', () {
    test('sign_in_screen captures consent + passes it into signUpWithEmail',
        () {
      expect(signin.contains('termsAcceptedAt:'), isTrue,
          reason: 'CREATE ACCOUNT must capture the consent timestamp and '
              'pass it through to signUpWithEmail — it must NOT write to '
              'Hive directly here (no session/Hive box exists yet at tap '
              'time; see diagnose b3f9e7).');
      expect(signin.contains('termsVersion:'), isTrue);
      expect(signin.contains('AppConstants.termsVersion'), isTrue,
          reason: 'terms_version must reference AppConstants.termsVersion so '
              'bumping the constant forces re-acceptance app-wide — a '
              'hardcoded literal would silently de-sync.');
      expect(signin.contains('DateTime.now().toUtc().toIso8601String()'),
          isTrue,
          reason: 'terms_accepted_at must use a UTC ISO instant — the cloud '
              'column is timestamptz; IST applies to date-keys only.');
      expect(
        signin.contains(
            "import 'package:icanbefitter/core/constants/app_constants.dart'"),
        isTrue,
      );
    });

    test('auth_provider stamps terms_accepted_at + terms_version in userBox',
        () {
      expect(authProvider.contains("'terms_accepted_at'"), isTrue,
          reason: 'DPDP acceptance must be stamped to Hive in '
              '_ensureLocalUser, AFTER HiveUserSession.openForUser has run '
              '(diagnose b3f9e7) — not before, at UI tap time.');
      expect(authProvider.contains("'terms_version'"), isTrue);
    });

    test(
        'auth_provider write is positioned AFTER HiveUserSession.openForUser '
        '(ordering regression guard)', () {
      // B-pass review finding 1 (2026-08-02): the original bug WAS an
      // ordering bug — the write executed before openForUser had run. A
      // pure presence check (previous test) would stay green even if a
      // future edit moved the write block back above openForUser, silently
      // reintroducing diagnose b3f9e7. The genuine Hive round-trip in
      // terms_acceptance_behavioral_test.dart proves the general mechanics
      // (throws-before / persists-after) but calls neither
      // _ensureLocalUser nor signUpWithEmail, so it can't catch a real
      // ordering regression either. This index comparison closes that gap:
      // both anchor strings occur exactly once in auth_provider.dart (the
      // definition site, not the call sites), so a strict textual-order
      // check is unambiguous.
      final openForUserIndex =
          authProvider.indexOf('HiveUserSession.openForUser(');
      final termsWriteIndex = authProvider.indexOf("'terms_accepted_at'");
      expect(openForUserIndex, greaterThanOrEqualTo(0),
          reason: 'HiveUserSession.openForUser( call not found in '
              'auth_provider.dart — has it been renamed/moved to another '
              'file?');
      expect(termsWriteIndex, greaterThanOrEqualTo(0),
          reason: "'terms_accepted_at' literal not found in "
              'auth_provider.dart.');
      expect(termsWriteIndex, greaterThan(openForUserIndex),
          reason: 'The terms_accepted_at Hive write must appear AFTER '
              'HiveUserSession.openForUser( in auth_provider.dart — writing '
              'before it throws StateError (the box is not open yet), '
              'silently swallowed by the surrounding catch (_) {}. This is '
              'the exact regression diagnose b3f9e7 documents.');
    });

    test('bootstrapper projects/hydrates the terms fields', () {
      expect(boot.contains('terms_accepted_at'), isTrue);
      expect(boot.contains('hydrateFromCloud'), isTrue,
          reason: 'the bootstrapper projects terms to cloud + re-hydrates');
    });

    test('bootstrapper has the phone-OTP consent fallback wired into '
        'hydrateFromCloud', () {
      // closes-diagnose: b3f9e7 — Part B. Phone OTP's verifyOtp DOES reach
      // _ensureLocalUser -> hydrateFromCloud, so the fallback firing from
      // there is correct for that path.
      expect(boot.contains('shouldStampFallbackTermsConsent'), isTrue,
          reason: 'The pure fallback-decision helper must exist.');
      expect(boot.contains('ensureTermsConsentFallback'), isTrue,
          reason: 'hydrateFromCloud must call the extracted fallback method '
              '(not re-inline the logic — see plan-review round 1 finding: '
              'hydrateFromCloud is unreachable for Google OAuth, so this '
              'method must be callable from elsewhere too).');
    });

    test(
        'restoring_screen calls ensureTermsConsentFallback — Google OAuth\'s '
        'REAL convergence point (plan-review round 1, 2026-08-02)', () {
      // Round-1 plan-review finding (blocking): hydrateFromCloud has exactly
      // one call site in the whole repo (auth_provider.dart's
      // _ensureLocalUser), which signInWithGoogle() never reaches — it only
      // starts the OAuth redirect and returns. The post-redirect re-entry
      // path is RestoringScreen._kickoffRestore -> resolveDestination +
      // SyncService.restoreFromCloudForUser, NEITHER of which is
      // hydrateFromCloud. Wiring the fallback only into hydrateFromCloud
      // (this file's own original B-pass-reviewed version) fixed phone OTP
      // but left the one channel called out as urgent — Google OAuth,
      // "went live in production today" — completely unfixed. This test
      // pins the actual fix: restoring_screen.dart must call
      // AuthSessionBootstrapper.instance.ensureTermsConsentFallback(...)
      // itself, from a point after Hive session is confirmed open.
      expect(restoringScreen.contains('ensureTermsConsentFallback'), isTrue,
          reason: 'restoring_screen.dart must call '
              'AuthSessionBootstrapper.instance.ensureTermsConsentFallback '
              '— hydrateFromCloud alone does not cover Google OAuth.');
      expect(
        restoringScreen.contains('AuthSessionBootstrapper.instance'),
        isTrue,
      );
    });

    test(
        'restoring_screen: BOTH ensureTermsConsentFallback call sites are '
        'positioned AFTER their own method\'s HiveUserSession.openForUser '
        '(ordering regression guard — plan-review round 2, 2026-08-02)', () {
      // Round-2 finding (MODERATE): the presence-only test above would stay
      // green even if a future edit moved either call before its
      // openForUser, or deleted one of the two call sites (the _goHome
      // fast-branch and _ensureOwnershipBeforeHome cover DIFFERENT cohorts —
      // warm-resume vs cold-start — so losing either silently reintroduces
      // round-1's gap for that cohort). Unlike auth_provider.dart (where
      // both anchor strings are globally unique), restoring_screen.dart has
      // MULTIPLE openForUser calls and TWO fallback calls, so this test
      // bounds each check to its own method's text span rather than a bare
      // whole-file indexOf — mirroring the round-2 reviewer's exact
      // recommendation.
      const goHomeStart = 'Future<void> _goHome(';
      const ensureOwnershipStart = 'Future<void> _ensureOwnershipBeforeHome(';
      const stampOnboardingStart =
          'Future<void> _stampOnboardingCompletedAt(';

      final goHomeStartIdx = restoringScreen.indexOf(goHomeStart);
      final ensureOwnershipStartIdx =
          restoringScreen.indexOf(ensureOwnershipStart);
      final stampOnboardingStartIdx =
          restoringScreen.indexOf(stampOnboardingStart);
      expect(goHomeStartIdx, greaterThanOrEqualTo(0),
          reason: '_goHome method signature not found — renamed/moved?');
      expect(ensureOwnershipStartIdx, greaterThan(goHomeStartIdx),
          reason: '_ensureOwnershipBeforeHome not found after _goHome — '
              'method order changed?');
      expect(stampOnboardingStartIdx, greaterThan(ensureOwnershipStartIdx),
          reason: '_stampOnboardingCompletedAt not found after '
              '_ensureOwnershipBeforeHome — method order changed?');

      final goHomeBody =
          restoringScreen.substring(goHomeStartIdx, ensureOwnershipStartIdx);
      final ensureOwnershipBody = restoringScreen.substring(
          ensureOwnershipStartIdx, stampOnboardingStartIdx);

      for (final entry in {
        '_goHome fast branch': goHomeBody,
        '_ensureOwnershipBeforeHome': ensureOwnershipBody,
      }.entries) {
        final openForUserIdx =
            entry.value.indexOf('HiveUserSession.openForUser(');
        final fallbackIdx = entry.value.indexOf('ensureTermsConsentFallback(');
        expect(openForUserIdx, greaterThanOrEqualTo(0),
            reason: '${entry.key}: HiveUserSession.openForUser( not found '
                'in this method\'s body.');
        expect(fallbackIdx, greaterThanOrEqualTo(0),
            reason: '${entry.key}: ensureTermsConsentFallback( not found '
                'in this method\'s body — has the call site been removed?');
        expect(fallbackIdx, greaterThan(openForUserIdx),
            reason: '${entry.key}: ensureTermsConsentFallback( must appear '
                'AFTER HiveUserSession.openForUser( within this method — '
                'calling it before the Hive session opens throws '
                'StateError (diagnose b3f9e7).');
      }
    });
  });
}
