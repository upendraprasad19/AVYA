// Regression test for audit 2026-05-16 / F3-1.2 (terms_accepted_at DPDP gap).
//
// Bug: `users.terms_accepted_at` + `users.terms_version` were 100% NULL in
// cloud (4/4 rows across all users) because the sign-up flow uses an inline
// pre-checked checkbox (per APK Test #2 / Q2) and the checkbox tick never
// wrote to `userBox['terms_accepted_at']` / `userBox['terms_version']`.
// The existing upward sync at `auth_provider.dart:505-516` is gated on a
// non-null Hive value, so it never fired. DPDP §22 audit gap.
//
// This is a source-grep contract test: it scans `sign_in_screen.dart` and
// asserts BOTH writes are present AND that both appear lexically BEFORE
// the `authNotifier.signUpWithEmail(` call site. If a future edit reorders
// the writes after signUp (or drops them entirely), the test fails before
// the next APK ships.
//
// Mirrors the shape of test/contracts/coach_notes_upward_sync_test.dart
// (sibling fix from the same Phase E batch).
//
// closes-diagnose: 2026-05-16-terms-accepted-at-dpdp

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('terms_accepted_at + terms_version are stamped on sign-up', () {
    late String src;

    setUpAll(() {
      final file = File('lib/features/auth/screens/sign_in_screen.dart');
      expect(file.existsSync(), isTrue,
          reason: 'sign_in_screen.dart must exist at the expected path');
      src = file.readAsStringSync();
    });

    test('userBox.put(terms_accepted_at, ...) is present', () {
      expect(
        src.contains("userBox.put(") &&
            src.contains("'terms_accepted_at'"),
        isTrue,
        reason:
            'sign_in_screen.dart must call HiveService.instance.userBox.put('
            "'terms_accepted_at', ...) inside the sign-up branch. "
            'Without this, cloud users.terms_accepted_at stays NULL (DPDP §22 gap).',
      );
    });

    test('userBox.put(terms_version, ...) is present', () {
      expect(
        src.contains("userBox.put(") && src.contains("'terms_version'"),
        isTrue,
        reason:
            'sign_in_screen.dart must call HiveService.instance.userBox.put('
            "'terms_version', AppConstants.termsVersion) inside the sign-up "
            'branch. Required so the cloud `users.terms_version` column tracks '
            'which ToS version the user accepted.',
      );
    });

    test('terms_version write uses AppConstants.termsVersion (not a literal)',
        () {
      expect(
        src.contains('AppConstants.termsVersion'),
        isTrue,
        reason:
            'terms_version must reference AppConstants.termsVersion so bumping '
            'the constant forces re-acceptance across the app. A hardcoded '
            'string (e.g. "v1") would silently de-sync from the rest of the '
            'codebase on a version bump.',
      );
    });

    test('terms writes occur BEFORE signUpWithEmail call (lexical order)', () {
      final acceptedAtIdx = src.indexOf("'terms_accepted_at'");
      final versionIdx = src.indexOf("'terms_version'");
      final signUpIdx = src.indexOf('authNotifier.signUpWithEmail(');

      expect(acceptedAtIdx, isNot(-1),
          reason: 'terms_accepted_at write must be present');
      expect(versionIdx, isNot(-1),
          reason: 'terms_version write must be present');
      expect(signUpIdx, isNot(-1),
          reason: 'authNotifier.signUpWithEmail(...) call must be present');

      expect(
        acceptedAtIdx < signUpIdx,
        isTrue,
        reason:
            "userBox.put('terms_accepted_at', ...) must appear BEFORE the "
            'authNotifier.signUpWithEmail(...) call in the source file. '
            'Stamping after signUp would race the post-auth `_ensureLocalUser` '
            "sync — Hive could still be empty when the first SELECT/UPDATE "
            'runs against `public.users`.',
      );
      expect(
        versionIdx < signUpIdx,
        isTrue,
        reason:
            "userBox.put('terms_version', ...) must appear BEFORE the "
            'authNotifier.signUpWithEmail(...) call in the source file.',
      );
    });

    test('UTC timestamp is used (timestamptz cloud column contract)', () {
      // The cloud column users.terms_accepted_at is timestamptz. The IST
      // date-key contract (CLAUDE.md §15) applies to date columns + Hive
      // date keys only, NOT timestamps. Using a local-time ISO string would
      // be ambiguous in cloud; UTC is the canonical interchange form.
      expect(
        src.contains('DateTime.now().toUtc().toIso8601String()'),
        isTrue,
        reason:
            'terms_accepted_at must be stamped with DateTime.now().toUtc()'
            '.toIso8601String() — the column is timestamptz, and UTC is the '
            'canonical interchange form. Do NOT use istDateStr or a naive '
            'DateTime.now().toIso8601String() here.',
      );
    });

    test('AppConstants is imported by sign_in_screen.dart', () {
      expect(
        src.contains(
            "import 'package:icanbefitter/core/constants/app_constants.dart'"),
        isTrue,
        reason:
            'sign_in_screen.dart must import AppConstants so '
            'AppConstants.termsVersion resolves. A missing import would fail '
            'the build immediately, but pin this so future refactors do not '
            'accidentally collapse the import while leaving a stale reference.',
      );
    });
  });
}
