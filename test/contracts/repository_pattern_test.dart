// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/read_screen_source.dart';

/// Source-scan contract test: CLAUDE.md rule #4 — repository pattern for all
/// data access. No widget may call Supabase.instance.client.from() or invoke
/// Edge Functions directly.
///
/// These tests scan the migrated profile widget files and assert that all
/// direct Supabase table queries and Edge Function invocations have been
/// replaced by repository calls.
void main() {
  group('Repository pattern — profile widgets (CLAUDE.md rule #4)', () {
    test(
        'submissions_screen.dart does not call Supabase.instance.client.from() directly',
        () async {
      final source = await File(
              'lib/features/profile/screens/submissions_screen.dart')
          .readAsString();
      expect(
        source,
        isNot(contains("Supabase.instance.client.from(")),
        reason:
            'submissions_screen.dart must use SubmissionsRepository (CLAUDE.md rule #4)',
      );
    });

    // audit-2026-05-16 E.8 — `my_submissions_screen.dart` DELETED. The
    // legacy `/profile/my-submissions` route + widget were superseded by
    // the canonical `/profile/submissions` (SubmissionsScreen tabbed
    // view) in Test #1 / S1 batch (2026-04-24); 3 weeks of zero deep-link
    // hits proved no caller depended on it. Founder approved Phase D
    // NEEDS_DECISION 2 Option A. The previous test case asserting this
    // legacy screen used SubmissionsRepository is removed — the file
    // doesn't exist anymore.

    test(
        'profile_screen.dart does not query user_custom_exercises or users table directly',
        () async {
      final source =
          await Future.value(readScreenSource('profile'));
      expect(
        source,
        isNot(contains(".from('user_custom_exercises")),
        reason:
            'profile_screen.dart must not query user_custom_exercises directly — use SubmissionsRepository (CLAUDE.md rule #4)',
      );
      // Hard-delete is canonical (Test #11 H1 + audit-2026-05-16 E.8 deleted
      // the soft-delete shim). profile_screen.dart must NEVER reach into
      // `users` directly to flag a deletion — only the `delete-account`
      // Edge Function (via DeleteAccountScreen) is allowed to write this
      // table for deletion purposes.
      expect(
        source,
        isNot(contains(".from('users').update({")),
        reason:
            "profile_screen.dart must not write to the users table directly. "
            "Use the delete-account Edge Function via DeleteAccountScreen "
            "(audit-2026-05-16 E.8 removed UserRepository.softDeleteAccount).",
      );
    });

    test(
        'edit_profile_screen.dart does not invoke assess-body-composition Edge Function directly',
        () async {
      final source = await File(
              'lib/features/profile/screens/edit_profile_screen.dart')
          .readAsString();
      expect(
        source,
        isNot(contains("functions.invoke(\n        'assess-body-composition'")),
        reason:
            'edit_profile_screen.dart must use UserRepository.assessBodyComposition() (CLAUDE.md rule #4)',
      );
      // Belt-and-suspenders: check for the exact literal that was present before migration.
      expect(
        source,
        isNot(contains("functions.invoke(\n          'assess-body-composition'")),
        reason:
            'edit_profile_screen.dart must use UserRepository.assessBodyComposition() (CLAUDE.md rule #4)',
      );
      expect(
        source,
        isNot(contains("'assess-body-composition'")),
        reason:
            "edit_profile_screen.dart must not reference 'assess-body-composition' Edge Function directly — use UserRepository (CLAUDE.md rule #4)",
      );
    });
  });
}
