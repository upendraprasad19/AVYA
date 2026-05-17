// Regression test for audit-2026-05-16 reader-side / F3-2.1 —
// onboarding-completed triplicate-storage split-brain.
//
// `RestoringScreen._stampOnboardingCompletedAt` self-heal path read
// `HiveService.instance.configBox.get('onboarding_completed', ...)` directly.
// Post-Test-#11.1, `UserConfigMigrator` v2 moves `onboarding_completed`
// from `configBox` to per-user `userBox`. Devices that ran the migration
// have the value in `userBox` — reading directly from `configBox`
// returns the empty/default value, causing the self-heal path to skip
// onboarded users and route them back through `/onboarding`.
//
// Fix: read via `MigratedKey.readWithDefault<bool>('onboarding_completed',
// false)` — the helper checks `userBox` first, falls back to `configBox`
// for pre-migration installs. closes-diagnose:
// 2026-05-16-onboarding-triplicate-storage
//
// Source-grep contract test — pins the read pattern so a refactor can't
// silently revert to direct configBox access.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String src;

  setUpAll(() {
    src = File('lib/features/auth/screens/restoring_screen.dart')
        .readAsStringSync();
  });

  group('RestoringScreen onboarding read path', () {
    test('self-heal reads onboarding_completed via MigratedKey', () {
      // The fix uses MigratedKey.readWithDefault. Match the exact pattern.
      final hasMigratedKeyRead = RegExp(
        r"MigratedKey\.readWithDefault<bool>\(\s*'onboarding_completed'",
      ).hasMatch(src);
      expect(hasMigratedKeyRead, isTrue,
          reason:
              'Self-heal must read onboarding_completed via MigratedKey '
              'so it sees post-migration userBox values AND pre-migration '
              'configBox values. Pre-fix bypassed the migration helper.');
    });

    test('self-heal does NOT read onboarding_completed directly from configBox',
        () {
      // The pre-fix bug. Pin its absence.
      final hasDirectConfigRead = RegExp(
        r"configBox[\s\S]{0,60}?get\(\s*'onboarding_completed'",
      ).hasMatch(src);
      expect(hasDirectConfigRead, isFalse,
          reason:
              'configBox.get(\'onboarding_completed\') returns the empty '
              'value on devices that have run UserConfigMigrator v2 — '
              'must use MigratedKey instead.');
    });

    test('MigratedKey is imported', () {
      expect(
          src.contains(
              "import 'package:icanbefitter/core/services/migrated_key.dart'"),
          isTrue,
          reason: 'MigratedKey import must be present.');
    });
  });
}
