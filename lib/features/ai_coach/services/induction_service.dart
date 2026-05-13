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
}
