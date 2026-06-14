import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';

/// Unit 4 (d-bf) — one-time heal of the FABRICATED onboarding body-fat default.
///
/// Pre-fix, a user who SKIPPED body-fat at onboarding had `body_fat_percent`
/// saved as a made-up `18.0` (`stats_screen.dart` `?? 18.0`). The profile-edit
/// recompute (`profile_provider.recalculateTargets`) consumes `body_fat_percent`
/// via Katch-McArdle, so any such user editing ANY profile field recomputed
/// their calories from a fabricated 18% body-fat.
///
/// This nulls `body_fat_percent` where it is EXACTLY 18.0 AND was never
/// explicitly assessed (`body_fat_assessed_at == null` — stepped + legacy-chat
/// onboarding never stamp it; only the AI scan / Edit-Profile does). Those users
/// revert to Mifflin (correct for a skip) on their next recompute. The rare user
/// who genuinely typed 18 at onboarding also reverts and can re-enter via Edit.
///
/// Durability (review #2): the CLOUD column is cleared FIRST via a fresh-token
/// explicit UPDATE, THEN local — because the normal profile sync OMITS nulls
/// (`sync_profile.dart` `_hasNumber`) and `_restoreUserProfile` re-hydrates a
/// non-null cloud value, so a synced-null would silently revert. Clearing cloud
/// first means a partial failure leaves the 18.0 consistent across cloud+local
/// and retries next session — never a local-null/cloud-18 split that re-hydrates.
/// NO `daily_calories` recompute (founder-locked: no silent backfill).
class BodyFatDefaultHealer {
  BodyFatDefaultHealer._();

  /// Kill-switch (device-level `configBox` flag, default off → heal active).
  static const String killSwitch = 'disable_bodyfat_heal';
  static const double _fabricatedDefault = 18.0;

  /// Idempotent — once `body_fat_percent` is null/non-18 it returns early.
  ///
  /// Call site: `auth_provider._ensureLocalUser`, after `openForUser` +
  /// `UserConfigMigrator.runIfNeeded` (cross-account-safe, once per session,
  /// BEFORE any user-initiated `recalculateTargets` can fire).
  static Future<void> runIfNeeded() async {
    try {
      final hive = HiveService.instance;
      if (hive.configBox.get(killSwitch) == true) return;

      final userBox = hive.userBox; // GuardedBox — caller holds a session.
      final raw = userBox.get('profile');
      if (raw is! Map) return;
      final profile = Map<String, dynamic>.from(raw);

      final bf = (profile['body_fat_percent'] as num?)?.toDouble();
      final assessed = profile['body_fat_assessed_at'];
      // Only the fabricated default: exactly 18.0 AND never explicitly assessed.
      if (bf != _fabricatedDefault || assessed != null) return;

      // 1) Clear the CLOUD column FIRST (durable — see class doc).
      final uid = SupabaseService.instance.currentUser?.id;
      if (uid != null) {
        // Require a FRESH token (§2.31 — a boot-adjacent web token can be
        // stale). If none (no session / refresh failed past expiry), DEFER the
        // WHOLE heal: returning here skips the local null too, so we never null
        // local while cloud may still be 18.0 (exactly the split cloud-first
        // ordering avoids). Retries next session, cloud+local stay 18.0.
        final token = await SupabaseService.instance.ensureFreshToken();
        if (token == null) return;
        await SupabaseService.instance.client
            .from('user_profile')
            .update({'body_fat_percent': null}).eq('user_id', uid);
      }

      // 2) Then null local.
      profile['body_fat_percent'] = null;
      await userBox.put('profile', profile);
      debugPrint('[BodyFatDefaultHealer] cleared fabricated body_fat 18.0');
    } catch (e, st) {
      // Leave 18.0 consistent across cloud+local — retries next session.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'bodyfat_default_heal'));
    }
  }
}
