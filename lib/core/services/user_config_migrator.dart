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

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';

class UserConfigMigrator {
  UserConfigMigrator._();

  /// `migrationBox` flag key. Survives `clearAllData()`.
  ///
  /// v1 (Test #10.1) migrated 6 critical keys.
  /// v2 (Test #11.1) sweeps the remaining 25 user-scoped keys.
  /// A device that already ran v1 will have the v1 flag set; running v2
  /// uses a NEW flag so the additional 25 keys still migrate. (The 6
  /// v1 keys are no-ops on a v2 run because they're already gone from
  /// configBox.)
  static const String _flagKey = 'config_to_user_migration_v2_done';

  /// All user-scoped keys migrated to `userBox`.
  ///
  /// Test #10.1 (2026-05-04): seed 6 critical keys (onboarding gate +
  /// subscription state) — the leak reproducer + revenue impact.
  ///
  /// Test #11.1 (2026-05-04 same day): full sweep — every remaining
  /// user-specific key in `configBox` migrated, closing the
  /// cross-account leak class entirely.
  ///
  /// Two keys deliberately stay in `configBox` (see `_intentionallyShared`
  /// below) — they cross sessions by design.
  ///
  /// Audit references:
  ///   docs/superpowers/plans/2026-05-04-cross-account-leak-hotfix-plan.md
  ///   docs/superpowers/plans/2026-05-04-test-11-1-full-config-migration.md
  static const List<String> userScopedKeys = [
    // ----- Test #10.1 seed (6 keys) -----
    // Onboarding gate — THE leak vector. Once leaked it routes new
    // users straight past `/onboarding/mission-brief` into `/home`,
    // surfacing the previous user's data.
    'onboarding_completed',
    // Subscription state — PRO entitlement.
    'isPro', 'expiresAt', 'plan', 'lastVerifiedAt', 'localActivationAt',
    // Expiry-banner state (diagnose 2026-06-06) — `pro_lapsed_at` marker +
    // `expiry_banner_dismissed_date`. MUST be user-scoped: a leaked configBox
    // copy would show User B a "PRO expired / RENEW" banner for an account that
    // was never theirs. Stamps are also session-gated (see isPro) so they never
    // seed configBox in the first place.
    'pro_lapsed_at', 'expiry_banner_dismissed_date',

    // ----- Test #11.1 sweep (25 keys) -----
    // AI prediction card (per-user AI-generated text)
    'prediction_text', 'prediction_date', 'prediction_stale',
    'prediction_generated_at',
    // AI behavior + chat (per-user trial window, telegram link, channel)
    'pattern_insights', 'last_ai_greeting_date', 'ai_trial_start',
    'telegram_connected', 'coach_channel',
    // Rate limit counters (per-user free-tier window — leaking these
    // lets a sign-out → sign-up cycle reset 50/day caps).
    'ai_text_log_count_today', 'scan_meal_count_today',
    'cart_auditor_count_today', 'last_daily_reset',
    // Workout plan + travel + swap state (per-user plan window, swap
    // budget, travel suspension)
    'plan_start_date', 'plan_end_date', 'preferred_training_days',
    'last_phase_profile', // ⑧ 2-int (W2.5) repeat-content G5 baseline (per-user)
    'phase_repeat_nudge_pending', // ⑧ 3-a2 (W2.5) local-only low-adherence nudge (per-user)
    'swap_week_start', 'swaps_this_week', 'travel_start', 'travel_end',
    // Diet plan (per-user saved plan)
    'saved_diet_plan',
    // Onboarding replay flag — set during authenticated onboarding,
    // read by sync replay on next launch. Same user across both sides.
    'pending_onboarding_sync',
    // Profile state
    'progress_photo_count', 'first_report_viewed',
    'profile_nudge_dismissed_at',
  ];

  /// Keys that intentionally stay in shared `configBox`.
  ///
  /// These are NOT user-scoped — they cross sessions or pre-date the
  /// authenticated session. Migrating them would break their use case.
  ///
  ///   - `pending_referral_code`: written BEFORE auth (sign-in screen
  ///     captures referral code from URL/clipboard), read AFTER auth in
  ///     `_ensureLocalUser`. The whole point is to survive across the
  ///     "no user → user" boundary.
  ///   - `logout_in_progress`: set during `signOut` (session being torn
  ///     down), read on next cold launch in `main.dart` BEFORE any auth
  ///     check. Single-device cold-launch flag, not user-scoped.
  ///
  /// Documented here so future audits don't try to migrate them.
  // ignore: unused_field
  static const List<String> _intentionallyShared = [
    'pending_referral_code',
    'logout_in_progress',
    // Unit 3 obs 6 — per-device/browser PWA-install-banner dismiss preference
    // (web only; not user data). Documentation-only list; no gate reads it.
    'pwa_banner_dismissed',
    // audit-fixwave 2026-07-02 / F16 — health-sync enablement is a DEVICE
    // capability, not user data: Health Connect / Google Fit is bound to the
    // physical device, and whatever it exposes syncs to the currently-logged-in
    // account regardless of who toggled it (health rows are written into the
    // user-scoped healthBox via wrapUserScopedBox and pushed under the live
    // auth token — no cross-user data leak). A stale "enabled" flag after an
    // account switch at worst means User B re-toggles; it never routes A's data
    // to B. So `health_sync_enabled` deliberately stays device-scoped rather
    // than being added to userScopedKeys (which, without also moving the reader,
    // would be a half-migration). This is the explicit maintainer decision the
    // audit asked for. Reviewer C (R2) independently confirmed no cross-account leak.
    'health_sync_enabled',
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
      } catch (e, st) {
        failures[key] = e;
        // audit-2026-05-11 H-42 — telemetry pair.
        debugPrint('[UserConfigMigrator] copy $key failed: $e');
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'user_config_migrator_copy_key'));
      }
    }

    // Set the flag even if some keys failed — so we don't re-run on
    // every signup. Failed keys are logged; if a critical one fails,
    // the cross-account guard's verify-after-clear will catch the
    // resulting leak when the next user signs in.
    try {
      await migBox.put(_flagKey, true);
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[UserConfigMigrator] flag write failed: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'user_config_migrator_flag_write'));
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
