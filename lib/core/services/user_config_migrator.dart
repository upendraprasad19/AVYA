// Test #10.1 — One-shot migration that copies user-specific keys from
// the SHARED `configBox` into the CURRENT user's `userBox`.
//
// Before this hotfix, ~22 user-specific keys lived in `configBox`
// (PRO subscription state, AI prediction text, pattern insights, rate
// limit counters, plan dates, etc.). `configBox` is NOT namespaced and
// `clearAllData()` partial-failures could leave those keys behind for
// the next user to inherit — causing the cross-account data leak class.
//
// This helper runs once per device lifetime (gated by `migrationBox`,
// which is NEVER cleared) and only when a user is signed in (so the
// per-user `userBox` is the destination). After migration, every reader
// in the codebase reads from `userBox` instead of `configBox` — see
// the Test #10.1 hotfix plan for the full list of touched callsites.
//
// Idempotent. Safe to call on every `_ensureLocalUser`. After the
// migration runs once, the flag in `migrationBox` short-circuits all
// subsequent calls.

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/hive_service.dart';

class UserConfigMigrator {
  UserConfigMigrator._();

  /// `migrationBox` flag key. Survives `clearAllData()`.
  static const String _flagKey = 'config_to_user_migration_v1_done';

  /// Keys migrated in this hotfix (Test #10.1 scope).
  ///
  /// Focus: the leak reproducer + revenue impact. Other user-specific
  /// keys (prediction text, pattern insights, rate counters, plan dates,
  /// etc.) are still in `configBox` and will be migrated in Test #11.1.
  ///
  /// Audit reference: docs/superpowers/plans/2026-05-04-cross-account-leak-hotfix-plan.md
  static const List<String> userScopedKeys = [
    // Onboarding gate — THE leak vector. Once leaked it routes new
    // users straight past `/onboarding/mission-brief` into `/home`,
    // surfacing the previous user's data.
    'onboarding_completed',
    // Subscription state — PRO entitlement. Leaked across signOut →
    // signUp until `isPro()`'s defense-in-depth profile-id check fires.
    // Move to `userBox` so it's physically isolated per user.
    // Note: 'lastVerifiedAt' (NOT 'lastVerified') matches the constant
    // in `SubscriptionService._lastVerifiedKey`.
    'isPro', 'expiresAt', 'plan', 'lastVerifiedAt', 'localActivationAt',
  ];

  /// Keys deferred to Test #11.1 — still leak vectors but lower impact.
  /// Documented here so the next batch knows the full scope.
  // ignore: unused_field
  static const List<String> _deferredKeys = [
    // AI prediction
    'prediction_text', 'prediction_date', 'prediction_stale',
    'prediction_generated_at',
    // AI behavior + chat
    'pattern_insights', 'last_ai_greeting_date', 'ai_trial_start',
    'telegram_connected', 'coach_channel',
    // Rate limit counters
    'ai_text_log_count_today', 'scan_meal_count_today',
    'cart_auditor_count_today', 'last_daily_reset',
    // Workout plan + travel + swap
    'plan_start_date', 'plan_end_date', 'preferred_training_days',
    'swap_week_start', 'swaps_this_week', 'travel_start', 'travel_end',
    // Diet plan
    'saved_diet_plan',
    // Misc per-user
    'pending_referral_code', 'pending_onboarding_sync',
    'progress_photo_count', 'first_report_viewed',
    'profile_nudge_dismissed_at', 'logout_in_progress',
  ];

  /// Runs the migration once per device. Idempotent.
  ///
  /// Caller MUST ensure `HiveUserSession.openForUser` has run for the
  /// current session before calling this — `userBox` access throws
  /// otherwise. The intended call site is `_ensureLocalUser` in
  /// auth_provider.dart, after `openForUser` and after the
  /// cross-account guard runs.
  static Future<MigrationResult> runIfNeeded() async {
    final hive = HiveService.instance;

    // Gate on migrationBox flag (NEVER cleared by clearAllData).
    final migBox = hive.migrationBox;
    if (migBox.get(_flagKey) == true) {
      return const MigrationResult.noop();
    }

    final cfg = hive.configBox;
    final userBox = hive.userBox; // GuardedBox — caller must have a session.

    final copied = <String>[];
    final failures = <String, Object>{};

    for (final key in userScopedKeys) {
      if (!cfg.containsKey(key)) continue; // nothing to migrate
      try {
        final value = cfg.get(key);
        // Only copy if userBox doesn't already hold this key — never
        // overwrite cloud-synced fresh data with stale config values.
        if (!userBox.containsKey(key)) {
          await userBox.put(key, value);
        }
        await cfg.delete(key);
        copied.add(key);
      } catch (e) {
        failures[key] = e;
        debugPrint('[UserConfigMigrator] copy $key failed: $e');
      }
    }

    // Set the flag even if some keys failed — so we don't re-run on
    // every signup. Failed keys are logged; if a critical one fails,
    // the cross-account guard's verify-after-clear will catch the
    // resulting leak when the next user signs in.
    try {
      await migBox.put(_flagKey, true);
    } catch (e) {
      debugPrint('[UserConfigMigrator] flag write failed: $e');
    }

    final result = MigrationResult(
      copiedKeys: copied,
      failures: failures,
    );
    debugPrint('[UserConfigMigrator] $result');
    return result;
  }
}

class MigrationResult {
  final List<String> copiedKeys;
  final Map<String, Object> failures;

  const MigrationResult({
    required this.copiedKeys,
    required this.failures,
  });

  const MigrationResult.noop()
      : copiedKeys = const <String>[],
        failures = const <String, Object>{};

  bool get hasFailures => failures.isNotEmpty;

  @override
  String toString() => copiedKeys.isEmpty && failures.isEmpty
      ? 'MigrationResult(noop)'
      : 'MigrationResult(copied=${copiedKeys.length}, failures=${failures.length})';
}
