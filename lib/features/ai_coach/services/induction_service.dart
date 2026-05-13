import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

/// Single source for induction state. Idempotency lives here — [hasCommitted]
/// and [inductionCompleted] are the canonical guards.
///
/// Hive keys (in coachBox):
///   committed_at              ISO datetime when user tapped I COMMIT
///   committed_to_lt_cdr       bool, set true on commitment
///   induction_completed_at    ISO datetime when 5-question muster finished
///   why_now / definition_of_winning / known_injuries / typical_wake_time /
///   preferred_workout_time / body_part_priorities  → muster answers
class InductionService {
  static final InductionService instance = InductionService._();
  InductionService._();

  bool get hasCommitted =>
      HiveService.instance.coachBox.get('committed_to_lt_cdr') == true;

  bool get inductionCompleted =>
      HiveService.instance.coachBox.get('induction_completed_at') != null;

  /// Records the I COMMIT tap. Writes Hive immediately, fires sync to Supabase
  /// fire-and-forget per CLAUDE.md §15.
  Future<void> recordCommitment() async {
    final now = DateTime.now().toIso8601String();
    await HiveService.instance.coachBox.put('committed_at', now);
    await HiveService.instance.coachBox.put('committed_to_lt_cdr', true);
    final userId =
        (HiveService.instance.userBox.get('profile') as Map?)?['id'] as String?;
    if (userId != null) {
      unawaited(SyncService.instance.syncCoachMemoryNow(userId));
    }
  }

  static const _allowedMusterKeys = {
    'why_now',
    'definition_of_winning',
    'known_injuries',
    'typical_wake_time',
    'preferred_workout_time',
    'body_part_priorities',
  };

  /// Records a single muster answer to [HiveService.coachBox] AND bridges
  /// the value to [userBox['profile']] for keys that map to profile
  /// fields. Per CLAUDE.md §15 "Source of Truth Rules" — the muster is
  /// the SoT for these facts; profile reads from a mirrored copy so Edit
  /// Profile and plan generator see the values.
  ///
  /// Throws [ArgumentError] on unknown key. Profile-bridge failures are
  /// logged via [ErrorTelemetry] but do not throw — the coachBox write
  /// already succeeded; the bridge re-runs on next attempt.
  Future<void> recordMusterAnswer(String key, dynamic value) async {
    if (!_allowedMusterKeys.contains(key)) {
      throw ArgumentError('Unknown muster key: $key');
    }
    await HiveService.instance.coachBox.put(key, value);

    // B2b — bridge into userBox['profile'].
    try {
      await _bridgeToProfile(key, value);
    } catch (e, st) {
      debugPrint('[InductionService._bridgeToProfile] $key failed: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'muster_bridge_to_profile'));
    }
  }

  Future<void> _bridgeToProfile(String musterKey, dynamic value) async {
    final Map<String, dynamic> fields;
    switch (musterKey) {
      case 'known_injuries':
        fields = {'injuries': (value as List).cast<String>()};
      case 'typical_wake_time':
        fields = {'wake_up_time': value as String};
      case 'preferred_workout_time':
        fields = {'preferred_workout_time': value as String};
      case 'body_part_priorities':
        final v = (value as List).cast<String>();
        // Only bridge single-select (B2d). Multi-select legacy data
        // (length > 1) is left in coachBox without a fuzzy guess.
        if (v.length != 1) return;
        fields = {'physique_focus': v.first};
      default:
        // why_now / definition_of_winning — no profile mapping.
        return;
    }

    await UserRepository.instance.updateProfileFields(fields);

    final uid = SupabaseService.instance.currentUser?.id;
    if (uid != null) {
      unawaited(SyncService.instance.syncProfileNow(uid));
      unawaited(SyncService.instance.pushSnapshot());
    }
  }

  /// Marks the muster complete. Writes Hive + fires sync + pushSnapshot
  /// fire-and-forget per CLAUDE.md §15.
  Future<void> completeMuster() async {
    final now = DateTime.now().toIso8601String();
    await HiveService.instance.coachBox.put('induction_completed_at', now);
    final userId =
        (HiveService.instance.userBox.get('profile') as Map?)?['id'] as String?;
    if (userId != null) {
      unawaited(SyncService.instance.syncCoachMemoryNow(userId));
      unawaited(SyncService.instance.pushSnapshot());
    }
  }

  /// Migration flag key for the one-shot bridge backfill. Stored in
  /// [HiveService.migrationBox] which is NEVER cleared by clearAllData()
  /// — keeps the backfill from re-running after a sign-out + sign-in.
  static const String _backfillFlagKey =
      'muster_bridge_backfill_v1_done';

  /// APK Test #15.4 / B2 — one-shot backfill of pre-bridge muster
  /// answers into [userBox['profile']]. Called from
  /// `auth_provider._ensureLocalUser` after `HiveUserSession.openForUser`
  /// succeeds.
  ///
  /// Idempotency rules:
  /// - Gated by [_backfillFlagKey] in `migrationBox` — runs at most once
  ///   per device lifetime per migration version.
  /// - Only writes to a profile field if the field is currently at its
  ///   default value. User-edited values are NEVER clobbered.
  /// - Skips multi-select legacy `body_part_priorities` (length > 1) —
  ///   no fuzzy guess; user can re-pick via Edit Profile.
  ///
  /// Non-fatal on failure: logs + telemeters; flag stays unset so the
  /// backfill retries on next launch. Never throws.
  Future<void> backfillMusterToProfileIfNeeded() async {
    try {
      final mig = HiveService.instance.migrationBox;
      if (mig.get(_backfillFlagKey) == true) return;

      final coach = HiveService.instance.coachBox;
      final profile = UserRepository.instance.getProfile() ?? {};
      final updates = <String, dynamic>{};

      // injuries
      final cbInjuries = coach.get('known_injuries');
      if (cbInjuries is List && cbInjuries.isNotEmpty) {
        final existing = profile['injuries'];
        final isDefault = existing == null ||
            (existing is List &&
                (existing.isEmpty ||
                    (existing.length == 1 && existing.first == 'none')));
        if (isDefault) {
          updates['injuries'] = cbInjuries.cast<String>();
        }
      }

      // wake_up_time
      final cbWake = coach.get('typical_wake_time');
      if (cbWake is String && cbWake.isNotEmpty) {
        final existing = profile['wake_up_time'];
        if (existing == null || (existing is String && existing.isEmpty)) {
          updates['wake_up_time'] = cbWake;
        }
      }

      // preferred_workout_time
      final cbWorkout = coach.get('preferred_workout_time');
      if (cbWorkout is String && cbWorkout.isNotEmpty) {
        if (profile['preferred_workout_time'] == null) {
          updates['preferred_workout_time'] = cbWorkout;
        }
      }

      // physique_focus — single-select legacy data only.
      final cbBodyParts = coach.get('body_part_priorities');
      if (cbBodyParts is List && cbBodyParts.length == 1) {
        final v = cbBodyParts.first as String;
        const validEnum = {
          'balanced', 'glutes_legs', 'chest_shoulders_arms', 'strength',
        };
        final currentDefault =
            (profile['physique_focus'] as String?) == 'balanced';
        if (validEnum.contains(v) && currentDefault && v != 'balanced') {
          updates['physique_focus'] = v;
        }
      }

      if (updates.isNotEmpty) {
        await UserRepository.instance.updateProfileFields(updates);
        final uid = SupabaseService.instance.currentUser?.id;
        if (uid != null) {
          unawaited(SyncService.instance.syncProfileNow(uid));
          unawaited(SyncService.instance.pushSnapshot());
        }
      }

      await mig.put(_backfillFlagKey, true);
    } catch (e, st) {
      debugPrint('[InductionService.backfillMusterToProfileIfNeeded] $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'muster_bridge_backfill'));
      // Don't set the flag on failure — retry next launch.
    }
  }
}
