// Bug f8c1a5 regression test (APK Test #16.2) — Layer 2.
//
// Pins that StreakFreezeClampMigrator.runIfNeeded is invoked from
// auth_provider._ensureLocalUser, AFTER UserConfigMigrator.runIfNeeded
// (so the streak freeze map lives in userBox by the time we clamp it).
//
// Source-grep contract.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'f8c1a5 — auth_provider._ensureLocalUser invokes StreakFreezeClampMigrator after UserConfigMigrator',
      () {
    final src = File('lib/features/auth/providers/auth_provider.dart')
        .readAsStringSync();

    // Strip comments so we don't accidentally match a TODO / explanatory comment.
    final stripped = src
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '')
        .split('\n')
        .map((l) => l.replaceFirst(RegExp(r'//.*$'), ''))
        .join('\n');

    final userConfigIdx =
        stripped.indexOf('UserConfigMigrator.runIfNeeded(');
    expect(userConfigIdx, isNonNegative,
        reason:
            'UserConfigMigrator.runIfNeeded() invocation missing from auth_provider — '
            're-baseline this test against the new orchestration site.');

    final streakClampIdx =
        stripped.indexOf('StreakFreezeClampMigrator.runIfNeeded(');
    expect(streakClampIdx, isNonNegative,
        reason:
            'StreakFreezeClampMigrator.runIfNeeded() must be invoked from '
            '_ensureLocalUser so the one-shot Hive repair runs on every '
            'authenticated session.');
    expect(streakClampIdx, greaterThan(userConfigIdx),
        reason:
            'StreakFreezeClampMigrator must run AFTER UserConfigMigrator so '
            'the user-scoped progress map has already been migrated into userBox '
            'before we attempt to clamp it.');
  });

  test(
      'f8c1a5 — StreakFreezeClampMigrator gates on migrationBox flag streak_freeze_clamp_v1_done',
      () {
    final src = File('lib/core/services/streak_freeze_clamp_migrator.dart')
        .readAsStringSync();

    // Strip comments.
    final stripped = src
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '')
        .split('\n')
        .map((l) => l.replaceFirst(RegExp(r'//.*$'), ''))
        .join('\n');

    expect(stripped.contains("streak_freeze_clamp_v1_done"), isTrue,
        reason:
            'StreakFreezeClampMigrator must gate on the migrationBox flag '
            '"streak_freeze_clamp_v1_done" so it runs exactly once per device.');
    expect(stripped.contains('hive.migrationBox'), isTrue,
        reason:
            'Gating must use migrationBox (NEVER cleared by clearAllData) '
            'so the flag survives sign-out / sign-up cycles. userBox would '
            'reset on cross-account guard and let the migrator re-run.');
  });
}
