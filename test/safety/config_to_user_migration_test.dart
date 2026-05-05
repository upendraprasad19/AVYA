// Test #10.1 + #11.1 — UserConfigMigrator copies user-specific keys from
// shared `configBox` into the per-user `userBox`, then deletes them
// from `configBox`. Idempotent via the `migrationBox` flag.
//
// v1 (Test #10.1): 6 critical keys (onboarding gate + subscription).
// v2 (Test #11.1): full sweep of 25 additional user-scoped keys.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/user_config_migrator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_migrator');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    // Fresh boxes per test — close + delete to reset state.
    for (final name in [
      HiveService.configBoxName,
      HiveService.migrationBoxName,
      HiveService.userBoxName,
      'userBox_aaaaaaaa',
    ]) {
      if (Hive.isBoxOpen(name)) {
        await Hive.box(name).close();
      }
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
    // Open shared boxes (matching HiveService.init).
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.instance.markInitializedForTests();
  });

  test('copies onboarding_completed and PRO state from configBox to userBox',
      () async {
    // Seed configBox as if it's a pre-migration install.
    final cfg = HiveService.instance.configBox;
    await cfg.put('onboarding_completed', true);
    await cfg.put('isPro', true);
    await cfg.put('expiresAt', '2030-01-01T00:00:00Z');
    await cfg.put('plan', 'monthly');
    await cfg.put('lastVerifiedAt', '2026-05-04T00:00:00Z');
    await cfg.put('localActivationAt', '2026-05-04T00:00:00Z');
    // Plus a key that should stay in configBox.
    await cfg.put('units_metric', true);

    // Open per-user box.
    const fakeUserId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    await HiveUserSession.openForUser(fakeUserId);

    // Run migration.
    final result = await UserConfigMigrator.runIfNeeded();

    // All 6 critical keys copied (lastVerifiedAt matches the constant
    // SubscriptionService._lastVerifiedKey, NOT 'lastVerified').
    expect(result.copiedKeys, containsAll(<String>[
      'onboarding_completed', 'isPro', 'expiresAt',
      'plan', 'lastVerifiedAt', 'localActivationAt',
    ]));

    // userBox now has them.
    final userBox = HiveService.instance.userBox;
    expect(userBox.get('onboarding_completed'), true);
    expect(userBox.get('isPro'), true);
    expect(userBox.get('plan'), 'monthly');

    // configBox lost the migrated keys.
    expect(cfg.containsKey('onboarding_completed'), isFalse);
    expect(cfg.containsKey('isPro'), isFalse);

    // Device-level key untouched.
    expect(cfg.get('units_metric'), true);

    // Flag set so re-run is a no-op (Test #11.1 bumped flag to v2).
    final mig = HiveService.instance.migrationBox;
    expect(mig.get('config_to_user_migration_v2_done'), true);

    // Second run is no-op.
    final secondRun = await UserConfigMigrator.runIfNeeded();
    expect(secondRun.copiedKeys, isEmpty);
    expect(secondRun.failures, isEmpty);

    await HiveUserSession.closeAll();
  });

  test('v2 sweep — copies all 25 deferred user-scoped keys', () async {
    // Seed configBox with the full v2 deferred set.
    final cfg = HiveService.instance.configBox;
    final v2Seed = <String, dynamic>{
      // AI prediction
      'prediction_text': 'You will hit 75kg by July.',
      'prediction_date': '2026-05-01T10:00:00Z',
      'prediction_stale': false,
      'prediction_generated_at': '2026-05-01T10:00:00Z',
      // AI behavior
      'pattern_insights': {'date': '2026-05-04', 'count': 2},
      'last_ai_greeting_date': '2026-05-04',
      'ai_trial_start': '2026-04-15T08:00:00Z',
      'telegram_connected': false,
      'coach_channel': 'in_app',
      // Rate counters
      'ai_text_log_count_today': 7,
      'scan_meal_count_today': 1,
      'cart_auditor_count_today': 0,
      'last_daily_reset': '2026-05-04',
      // Workout plan + travel + swap
      'plan_start_date': '2026-04-21T00:00:00Z',
      'plan_end_date': '2026-05-18T00:00:00Z',
      'preferred_training_days': <int>[0, 2, 4],
      'swap_week_start': '2026-04-28',
      'swaps_this_week': 1,
      'travel_start': null,
      'travel_end': null,
      // Diet plan
      'saved_diet_plan': {'goal': 'lose_fat', 'meals': []},
      // Onboarding replay
      'pending_onboarding_sync': false,
      // Profile state
      'progress_photo_count': 3,
      'first_report_viewed': true,
      'profile_nudge_dismissed_at': '2026-05-02T12:00:00Z',
    };
    for (final entry in v2Seed.entries) {
      await cfg.put(entry.key, entry.value);
    }
    // Plus a device-level key that must NOT be migrated.
    await cfg.put('units_metric', true);
    // Plus the two intentionally-shared keys — must stay in configBox.
    await cfg.put('pending_referral_code', 'AVYA-12345678');
    await cfg.put('logout_in_progress', true);

    const fakeUserId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    await HiveUserSession.openForUser(fakeUserId);

    final result = await UserConfigMigrator.runIfNeeded();

    // Every v2 key copied.
    expect(result.copiedKeys, containsAll(v2Seed.keys));
    expect(result.failures, isEmpty);

    // userBox now holds the v2 values.
    final userBox = HiveService.instance.userBox;
    expect(userBox.get('prediction_text'), 'You will hit 75kg by July.');
    expect(userBox.get('ai_text_log_count_today'), 7);
    expect(userBox.get('preferred_training_days'), [0, 2, 4]);
    expect(userBox.get('first_report_viewed'), true);

    // configBox lost the migrated keys.
    for (final key in v2Seed.keys) {
      expect(cfg.containsKey(key), isFalse,
          reason: 'configBox should not retain migrated key "$key"');
    }

    // Device-level + intentionally-shared keys untouched.
    expect(cfg.get('units_metric'), true);
    expect(cfg.get('pending_referral_code'), 'AVYA-12345678');
    expect(cfg.get('logout_in_progress'), true);

    // v2 flag set.
    final mig = HiveService.instance.migrationBox;
    expect(mig.get('config_to_user_migration_v2_done'), true);

    await HiveUserSession.closeAll();
  });

  test('intentionally-shared keys are NOT in userScopedKeys', () {
    // Defense-in-depth: if someone adds `pending_referral_code` or
    // `logout_in_progress` to userScopedKeys later, this test catches it
    // — those keys MUST stay in configBox to cross the auth boundary.
    expect(UserConfigMigrator.userScopedKeys, isNot(contains('pending_referral_code')));
    expect(UserConfigMigrator.userScopedKeys, isNot(contains('logout_in_progress')));
  });
}
