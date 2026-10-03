import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/services/error_telemetry.dart';
import '../../../core/services/hive_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/utils/ist_date.dart';

/// Single canonical writer for the `userBox['profile']` map.
///
/// Tech-debt audit 2026-05-20 finding A4: prior to this service, the
/// profile map was mutated in 7 sites scattered across auth, home,
/// ai_coach, workout_schedule_service, sync_profile, user_repository
/// and tool_dispatcher. There was no chokepoint to enforce future
/// invariants (BMR recompute on weight change, badge revalidation on
/// goal change, IST stamping of `updated_at`, sync fan-out).
///
/// Same architectural shape as [WorkoutWriteService] /
/// [NutritionWriteService] / [HealthWriteService] per docs/architecture/sync.md
/// "Source of Truth Rules". Profile is a single-keyed Hive entry
/// (`userBox['profile']`), so the mutex is global rather than
/// per-(date, exerciseName).
///
/// Every public method:
///   1. Acquires the singleton mutex so concurrent goal/weight/profile
///      edits merge serially instead of racing on read-modify-write.
///   2. Stamps `updated_at` (IST ISO-8601) on the resulting map.
///   3. Performs the single `userBox.put('profile', ...)`.
///   4. Fires `SyncService.syncProfileNow(userId)` fire-and-forget
///      so the upstream user_profile row stays current (skipped when
///      no authenticated user OR when [skipSync] is true — used by
///      restore-class writes that should NOT push back to cloud).
///   5. On exception: `ErrorTelemetry.recordNonFatal` with reason
///      `profile_write_service_<method>`.
class ProfileWriteService {
  ProfileWriteService._();
  static final ProfileWriteService instance = ProfileWriteService._();

  /// Singleton mutex serialising every profile mutation. The profile
  /// map is single-keyed in Hive (`userBox['profile']`), so concurrent
  /// callers (e.g. AI coach goal change + home weight tile firing
  /// within a few milliseconds) MUST queue rather than racing on the
  /// read-modify-write cycle.
  Completer<void>? _lock;

  // ─────────────────────────────────────────────────────────────
  //  Public API
  // ─────────────────────────────────────────────────────────────

  /// Full-shape replace. Use when the caller already constructed the
  /// canonical profile map (post-sign-in cloud merge, brand-new user
  /// stub creation). [profile] is written verbatim except for the
  /// `updated_at` stamp this service applies.
  ///
  /// [skipSync] = true is reserved for restore-class callers (cloud
  /// → Hive hydration) that must NOT re-push to cloud — otherwise we
  /// create a sync loop. Default false.
  Future<void> updateProfile(
    Map<String, dynamic> profile, {
    bool skipSync = false,
  }) async {
    await _withLock(() async {
      try {
        final stamped = Map<String, dynamic>.from(profile);
        stamped['updated_at'] = istNow().toIso8601String();
        await HiveService.instance.userBox.put('profile', stamped);
        if (!skipSync) _fireSync();
      } catch (e, st) {
        debugPrint('[ProfileWriteService.updateProfile] $e\n$st');
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'profile_write_service_update_profile'));
        rethrow;
      }
    });
  }

  /// Partial merge over the existing profile map. Keys in [patch]
  /// overwrite existing keys; keys absent from [patch] survive.
  ///
  /// If no existing profile is present, [patch] becomes the new
  /// profile (callers should usually call [updateProfile] for the
  /// brand-new-user case so they own the full shape — but we don't
  /// fight them on it here).
  Future<void> patchProfile(Map<String, dynamic> patch) async {
    await _withLock(() async {
      try {
        final box = HiveService.instance.userBox;
        final existing = box.get('profile');
        final base = existing is Map
            ? Map<String, dynamic>.from(existing)
            : <String, dynamic>{};
        final merged = <String, dynamic>{...base, ...patch};
        merged['updated_at'] = istNow().toIso8601String();
        await box.put('profile', merged);
        _fireSync();
      } catch (e, st) {
        debugPrint('[ProfileWriteService.patchProfile] $e\n$st');
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'profile_write_service_patch_profile'));
        rethrow;
      }
    });
  }

  /// Single-field convenience. Equivalent to
  /// `patchProfile({field: value})` but communicates intent at
  /// call-site for the common case of one goal / one weight change.
  Future<void> updateField(String field, dynamic value) async {
    await patchProfile(<String, dynamic>{field: value});
  }

  // ─────────────────────────────────────────────────────────────
  //  Internals
  // ─────────────────────────────────────────────────────────────

  /// Fire SyncService.syncProfileNow if we have a logged-in user.
  /// Fire-and-forget per docs/architecture/sync.md — Hive write already succeeded
  /// so a cloud push failure must not flip the local mutation's
  /// success bit.
  void _fireSync() {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null || userId.isEmpty) return;
    unawaited(SyncService.instance.syncProfileNow(userId));
  }

  Future<void> _withLock(Future<void> Function() op) async {
    while (_lock != null) {
      try {
        await _lock!.future;
      } catch (_) {/* swallowed; holder will release */}
    }
    final c = Completer<void>();
    _lock = c;
    try {
      await op();
    } finally {
      _lock = null;
      if (!c.isCompleted) c.complete();
    }
  }
}
