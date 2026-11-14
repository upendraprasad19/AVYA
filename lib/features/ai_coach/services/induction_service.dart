import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

/// Single source for induction state. Idempotency lives here — [hasCommitted]
/// and [inductionCompleted] are the canonical guards.
///
/// Hive keys (in coachBox):
///   committed_at              ISO datetime when user tapped I COMMIT
///   committed_to_lt_cdr       bool, set true on commitment
///   induction_completed_at    ISO datetime when the induction finished
///
/// Since onboarding-fuse-commit (2026-11-14) both stamps are written by
/// `OnboardingNotifier.finalizeLocalCommit`, the last local step of the Plan
/// screen's single I COMMIT tap. The Muster and Induction screens are gone.
///
///   body_part_priorities /
///   why_now / definition_of_winning / known_injuries / typical_wake_time /
///   preferred_workout_time    → RETIRED muster answers (the last live one,
///                             body_part_priorities, retired with the Muster
///                             screen on 2026-11-14; the rest by diagnose
///                             e2b8a4, 2026-09-19). No longer written by any
///                             live flow — injuries and wake/workout-time are
///                             either collected during onboarding
///                             (`profile['injuries']`) or left to Edit
///                             Profile (`profile['wake_up_time']` /
///                             `profile['preferred_workout_time']`), which
///                             already has UI for both. These keys are kept
///                             READABLE (never written) solely so
///                             [backfillMusterToProfileIfNeeded] can still
///                             migrate pre-existing users' old answers onto
///                             their profile.
class InductionService {
  static final InductionService instance = InductionService._();
  InductionService._();

  // Both getters read the USER-SCOPED `coachBox`, which throws
  // "HiveUserSession not opened" if accessed before openForUser has run.
  // GoRouter._authRedirect calls `inductionCompleted` at cold start (web
  // reload / deep-link / process-death restore onto /coach/*), BEFORE the
  // session opens — the throw escaped the redirect and crashed routing to a
  // "Page Not Found" error page. Short-circuit to `false` when no session is
  // open: induction state is simply unknown yet, and "not completed" is the
  // safe default (the induction flow re-evaluates once the session opens).
  // See diagnose 2026-05-30-induction-redirect-session-race.
  bool get hasCommitted {
    if (HiveUserSession.currentOwnerFullId == null) return false;
    return HiveService.instance.coachBox.get('committed_to_lt_cdr') == true;
  }

  bool get inductionCompleted {
    if (HiveUserSession.currentOwnerFullId == null) return false;
    return HiveService.instance.coachBox.get('induction_completed_at') != null;
  }

  /// Test hook: receives the uid each sync is fired for, just before the
  /// unawaited sync (which swallows its own failure and cannot be observed).
  /// Null in production.
  @visibleForTesting
  static void Function(String uid)? debugOnSyncUidForTests;

  /// The uid to sync coach memory for: the open Hive session's owner (the
  /// same source [hasCommitted] / [inductionCompleted] read), falling back
  /// to the profile's `id`. Before onboarding-fuse-commit only the profile
  /// `id` was read, and onboarding saved a profile with no `id`, so the sync
  /// was silently skipped.
  String? _syncUid() {
    final owner = HiveUserSession.currentOwnerFullId;
    if (owner != null) return owner;
    try {
      return (HiveService.instance.userBox.get('profile') as Map?)?['id']
          as String?;
    } catch (_) {
      return null;
    }
  }

  void _syncCoachMemory({bool pushSnapshot = false}) {
    final uid = _syncUid();
    if (uid == null) {
      unawaited(ErrorTelemetry.logEvent('induction_sync_skipped_no_uid'));
      return;
    }
    debugOnSyncUidForTests?.call(uid);
    unawaited(SyncService.instance.syncCoachMemoryNow(uid));
    if (pushSnapshot) unawaited(SyncService.instance.pushSnapshot());
  }

  /// Records the I COMMIT tap. Writes Hive immediately, fires sync to Supabase
  /// fire-and-forget per docs/architecture/sync.md.
  Future<void> recordCommitment() async {
    final now = DateTime.now().toIso8601String();
    await HiveService.instance.coachBox.put('committed_at', now);
    await HiveService.instance.coachBox.put('committed_to_lt_cdr', true);
    _syncCoachMemory();
  }

  /// Marks the induction complete. Writes Hive + fires sync + pushSnapshot
  /// fire-and-forget per docs/architecture/sync.md. Called from
  /// `OnboardingNotifier.finalizeLocalCommit` right after [recordCommitment]
  /// (onboarding-fuse-commit, 2026-11-14).
  Future<void> completeInduction() async {
    final now = DateTime.now().toIso8601String();
    await HiveService.instance.coachBox.put('induction_completed_at', now);
    _syncCoachMemory(pushSnapshot: true);
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
