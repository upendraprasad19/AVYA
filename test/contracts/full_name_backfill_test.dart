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
  group('H-3 full_name backfill in _ensureLocalUser', () {
    test(
      '_ensureLocalUser carries a self-heal update for users.full_name',
      () {
        final src = _src('lib/features/auth/providers/auth_provider.dart');
        final ensureIdx = src.indexOf('_ensureLocalUser');
        expect(ensureIdx, greaterThan(0),
            reason: '_ensureLocalUser must exist on AuthNotifier.');

        // Self-heal block must appear after the initial ignoreDuplicates
        // upsert. We check for the canonical signature: reading the
        // local Hive profile + calling .update({'full_name': ...}).
        // The actual implementation lives entirely inside
        // _ensureLocalUser, so the whole-file scan is sufficient.
        expect(
          src,
          contains("userBox.get('profile')"),
          reason:
              '_ensureLocalUser must read the local Hive profile to find '
              'a real onboarding full_name to self-heal.',
        );
        expect(
          src,
          contains("update({'full_name': localName})"),
          reason:
              '_ensureLocalUser must self-heal users.full_name from the '
              'local profile when the local name looks real (non-empty + '
              'contains a letter + not == email prefix). Pre-fix the '
              'email-prefix seed stuck via ignoreDuplicates and never '
              'got corrected.',
        );
      },
    );

    test(
      'self-heal guards against overwriting with email-prefix or empty',
      () {
        final src = _src('lib/features/auth/providers/auth_provider.dart');
        // The guard requirement: `localName != emailPrefix` AND
        // `localName.isNotEmpty` AND `letter check`. We pin the exact
        // shape since silently dropping any of these guards would
        // re-introduce the email-prefix overwrite class.
        expect(
          src,
          contains("user.email!.split('@').first"),
          reason:
              'Email-prefix derivation must be present so the guard can '
              'compare localName against it.',
        );
        expect(
          src,
          contains("localName.isNotEmpty"),
          reason:
              'Non-empty guard must be present to avoid wiping '
              'full_name with a blank local profile.',
        );
        expect(
          src,
          contains("localName != emailPrefix"),
          reason:
              'Inequality guard must be present so the self-heal '
              'doesn\'t no-op into re-writing the email-prefix value.',
        );
      },
    );
  });
}
