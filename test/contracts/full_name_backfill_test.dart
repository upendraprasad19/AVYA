// H-3 (audit-2026-05-11) — regression test for the email-signup
// full_name self-heal in `_ensureLocalUser`. Pre-fix the upsert ran
// with `ignoreDuplicates: true` and seeded `full_name` from
// `email.split('@').first`. The seed stuck forever — AI coach +
// weekly recap addressed users by their email prefix for the
// lifetime of the account.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String relPath) => File(relPath).readAsStringSync();

void main() {
  // Audit 2026-05-20 / A1: full_name backfill logic relocated from
  // auth_provider.dart into AuthSessionBootstrapper.hydrateFromCloud
  // (lib/core/services/auth_session_bootstrapper.dart). Source-grep
  // checks both files for the canonical writer. Per
  // `feedback_source_grep_false_confidence.md`, this is presence-only.
  group('H-3 full_name backfill (auth_provider OR bootstrapper)', () {
    test(
      'auth-stack carries a self-heal update for users.full_name',
      () {
        final authSrc = _src('lib/features/auth/providers/auth_provider.dart');
        final bootstrapperSrc =
            _src('lib/core/services/auth_session_bootstrapper.dart');
        final ensureSomewhere = authSrc.contains('_ensureLocalUser') ||
            bootstrapperSrc.contains('hydrateFromCloud');
        expect(ensureSomewhere, isTrue,
            reason: '_ensureLocalUser OR AuthSessionBootstrapper.hydrateFromCloud must exist.');

        final readsHiveProfile = authSrc.contains("userBox.get('profile')") ||
            bootstrapperSrc.contains("userBox.get('profile')");
        expect(readsHiveProfile, isTrue,
            reason:
                'auth-stack must read local Hive profile to find a real '
                'onboarding full_name to self-heal.');

        final selfHealsName =
            authSrc.contains("update({'full_name': localName})") ||
                bootstrapperSrc.contains("update({'full_name': localName})");
        expect(selfHealsName, isTrue,
            reason:
                'auth-stack must self-heal users.full_name from the local '
                'profile when local name looks real (non-empty + letter + '
                'not == email prefix). Pre-fix the email-prefix seed stuck '
                'via ignoreDuplicates and never got corrected.');
      },
    );

    test(
      'self-heal guards against overwriting with email-prefix or empty',
      () {
        final authSrc = _src('lib/features/auth/providers/auth_provider.dart');
        final bootstrapperSrc =
            _src('lib/core/services/auth_session_bootstrapper.dart');
        final emailPrefixCheck =
            authSrc.contains("user.email!.split('@').first") ||
                bootstrapperSrc.contains("user.email!.split('@').first") ||
                authSrc.contains(".split('@').first") ||
                bootstrapperSrc.contains(".split('@').first");
        expect(emailPrefixCheck, isTrue,
            reason: 'Email-prefix derivation must be present so the guard '
                'can compare localName against it.');

        final nonEmptyGuard = authSrc.contains('localName.isNotEmpty') ||
            bootstrapperSrc.contains('localName.isNotEmpty');
        expect(nonEmptyGuard, isTrue,
            reason: 'Non-empty guard must be present to avoid wiping '
                'full_name with a blank local profile.');

        final inequalityGuard =
            authSrc.contains('localName != emailPrefix') ||
                bootstrapperSrc.contains('localName != emailPrefix');
        expect(inequalityGuard, isTrue,
            reason: 'Inequality guard must be present so self-heal does '
                'not no-op into re-writing the email-prefix value.');
      },
    );
  });
}
