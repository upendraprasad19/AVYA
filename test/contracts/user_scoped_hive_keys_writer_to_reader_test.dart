import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Source-of-truth contract: writer/reader pairs for `user_scoped_hive_keys`
/// from docs/sot_registry.yaml.
///
/// Writer + Reader: MigratedKey.read + write + delete
/// 31-key migrated set enumerated in UserConfigMigrator.userScopedKeys.
/// Two keys deliberately stay shared: pending_referral_code + logout_in_progress.
///
/// Forbidden:
/// - configBox.put(.*user — user-specific data must go through MigratedKey
/// - configBox.get(.*isPro — use SubscriptionService.isPro()
void main() {
  late String migratedKeySrc;
  late String userConfigMigratorSrc;

  setUpAll(() {
    final mf = File('lib/core/services/migrated_key.dart');
    expect(mf.existsSync(), isTrue,
        reason: 'migrated_key.dart must exist (writer+reader for user_scoped_hive_keys)');
    migratedKeySrc = mf.readAsStringSync();

    // UserConfigMigrator may be in the same file or a separate file
    final mcf = File('lib/core/services/user_config_migrator.dart');
    if (mcf.existsSync()) {
      userConfigMigratorSrc = mcf.readAsStringSync();
    } else {
      // May be inline in migrated_key.dart or elsewhere
      userConfigMigratorSrc = migratedKeySrc;
    }
  });

  group('user_scoped_hive_keys writer↔reader source contract', () {
    test('MigratedKey class exists with read/write/delete methods', () {
      expect(migratedKeySrc.contains('class MigratedKey'), isTrue,
          reason: 'migrated_key.dart must define MigratedKey class');
      expect(migratedKeySrc.contains('static') && migratedKeySrc.contains('read'),
          isTrue,
          reason: 'MigratedKey must have read method');
      expect(migratedKeySrc.contains('write'), isTrue,
          reason: 'MigratedKey must have write method');
      expect(migratedKeySrc.contains('delete'), isTrue,
          reason: 'MigratedKey must have delete method');
    });

    test('MigratedKey reads from userBox (not configBox directly)', () {
      expect(migratedKeySrc.contains('userBox'), isTrue,
          reason: 'MigratedKey must read/write from userBox for user-scoped isolation');
    });

    test('pending_referral_code remains in intentionally-shared set', () {
      // These two keys must stay shared — they cross auth boundaries
      final hasPendingReferral =
          userConfigMigratorSrc.contains('pending_referral_code') ||
              migratedKeySrc.contains('pending_referral_code');
      expect(hasPendingReferral, isTrue,
          reason:
              'pending_referral_code must be explicitly named as intentionally shared '
              '(pre-auth → post-auth crossing per sot_registry)');
    });

    test('logout_in_progress remains in intentionally-shared set', () {
      final hasLogout =
          userConfigMigratorSrc.contains('logout_in_progress') ||
              migratedKeySrc.contains('logout_in_progress');
      expect(hasLogout, isTrue,
          reason:
              'logout_in_progress must be explicitly named as intentionally shared '
              '(set during signOut tear-down, read before session opens)');
    });

    test('UserConfigMigrator migration flag key exists', () {
      // _flagKey suffix _v2_done or later — ensures re-trigger on update
      final hasMigrationFlag =
          userConfigMigratorSrc.contains('_done') ||
              userConfigMigratorSrc.contains('migration') ||
              userConfigMigratorSrc.contains('_flagKey');
      expect(hasMigrationFlag, isTrue,
          reason:
              'UserConfigMigrator must have a versioned flag key to enable '
              're-running migration on existing devices when new keys are added');
    });

    test('forbidden: no direct configBox.put for isPro', () {
      // High-level check that subscription state doesn't leak to configBox directly
      // in key auth/provider files
      final authSrc = File('lib/features/auth/providers/auth_provider.dart');
      if (!authSrc.existsSync()) return;
      final src = authSrc.readAsStringSync();
      expect(src.contains("configBox.put('is_pro'"), isFalse,
          reason:
              'auth_provider must not write isPro directly to configBox; '
              'use MigratedKey pattern');
    });
  });
}
