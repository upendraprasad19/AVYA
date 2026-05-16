import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/health_sync_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/result.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/sync_error.dart';
import 'package:icanbefitter/core/services/sync_queue.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/models/coach_memory.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

part 'sync/sync_coach.dart';
part 'sync/sync_community.dart';
part 'sync/sync_health.dart';
part 'sync/sync_nutrition.dart';
part 'sync/sync_profile.dart';
part 'sync/sync_realtime.dart';
part 'sync/sync_restore_completeness.dart';
part 'sync/sync_workout.dart';

/// Result of a [SyncService.restoreFromCloudForUser] call.
class RestoreResult {
  final bool succeeded;
  final bool cancelled;
  final Object? error;

  RestoreResult.success()
      : succeeded = true,
        cancelled = false,
        error = null;

  RestoreResult.cancelled()
      : succeeded = false,
        cancelled = true,
        error = null;

  RestoreResult.failed(this.error)
      : succeeded = false,
        cancelled = false;
}

/// Handles background data sync between Hive (local) and Supabase (cloud).
///
/// Schedule:
///   - Immediately: custom foods/exercises (community contribution)
///   - Daily 11 PM IST: user_daily_snapshot for AI context
///   - Weekly (app launch if >7 days): full sync of all logs
///   - On restore (new device): pull full history from Supabase
/// APK Test #15.1 / Bug A — defensive int coercion for Hive map fields
/// whose cloud-side representation may be int, num, or String.
///
/// `_restoreWorkoutTemplates` historically stringified `prescribed_sets`
/// into the local Hive shape; home_screen + day_detail_sheet read it as
/// `int?` and crashed. Coerce at the writer instead of patching every
/// reader. Accepts int, num, String (parseable), or null → fallback.
///
/// closes-diagnose: 2026-05-12-schedule-int-coercion-a2f9e1
int _coerceInt(dynamic value, {required int fallback}) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  return fallback;
}

class SyncService {
  SyncService._();
  static final SyncService _instance = SyncService._();
  static SyncService get instance => _instance;

  final HiveService _hive = HiveService.instance;
  final SupabaseService _supabase = SupabaseService.instance;

  /// APK Test #12.7 — class fix for the "HiveUserSession not opened"
  /// silent-sync regression. Call this at the top of every public sync
  /// entry point that touches user-scoped boxes. Idempotent
  /// (`HiveUserSession.openForUser` returns immediately when the same
  /// id is already open). Returns the auth uid on success, or null when
  /// no Supabase session is live (caller should short-circuit).
  ///
  /// This closes the cold-start race where `pushSnapshot()` /
  /// `syncWorkoutData()` fire from `WorkoutWriteService` before
  /// `_ensureLocalUser` has run on the auth side — every box read used
  /// to throw `HiveUserSession not opened`, the `unawaited` swallowed
  /// the StateError, and the cloud silently received nothing.
  Future<String?> _ensureSessionOpen() =>
      HiveUserSession.ensureOpenedForCurrentSession();

  // ── Restore cancellation flag ───────────────────────────────

  /// Set to true by [cancelInflightRestore] to abort a running
  /// [restoreFromCloudForUser] call between restore steps.
  bool _restoreCancelled = false;

  /// Signals any in-flight [restoreFromCloudForUser] to abort between steps.
  /// Safe to call even if no restore is running.
  void cancelInflightRestore() {
    _restoreCancelled = true;
  }

  // ── Hive syncBox Keys ───────────────────────────────────────

  static const String _lastSnapshotKey = 'last_snapshot_sync';
  static const String _lastFullSyncKey = 'last_full_sync';
  static const String _lastCustomSyncKey = 'last_custom_sync';

  /// Duration between full syncs (1 day — safe because all upserts are idempotent).
  static const Duration _fullSyncInterval = Duration(days: 1); // daily full sync on app launch

  /// Deterministic UUID generator for sync IDs.
  /// Converts Hive keys (e.g. `wlog_1775500200000`) into stable UUIDs
  /// so repeated syncs don't create duplicate rows.
  static const _uuidGen = Uuid();
  static const _syncNamespace = '6ba7b810-9dad-11d1-80b4-00c04fd430c8';

  static String _deterministicId(String localKey) {
    return _uuidGen.v5(_syncNamespace, localKey);
  }

  /// APK Test #12.7 — true when [s] structurally looks like a v4/v5 UUID.
  /// 36 chars, hyphens at 8/13/18/23, hex elsewhere. Used by the coach
  /// sync path so server-already-UUID ids skip the v5 hashing detour.
  static bool _looksLikeUuid(String s) {
    if (s.length != 36) return false;
    if (s[8] != '-' || s[13] != '-' || s[18] != '-' || s[23] != '-') {
      return false;
    }
    for (var i = 0; i < s.length; i++) {
      if (i == 8 || i == 13 || i == 18 || i == 23) continue;
      final c = s.codeUnitAt(i);
      final isDigit = c >= 0x30 && c <= 0x39;
      final isLowerHex = c >= 0x61 && c <= 0x66;
      final isUpperHex = c >= 0x41 && c <= 0x46;
      if (!isDigit && !isLowerHex && !isUpperHex) return false;
    }
    return true;
  }

  /// APK Test #12.8 / Bug #1 — mirror of
  /// [NutritionWriteService.computeLogKey] used by [_restoreNutritionLogs]
  /// so cloud→local round-trip collapses to the same Hive key as the
  /// original local write. Cannot reuse `computeLogKey` directly because
  /// it takes a typed `List<FoodItem>` and we restore from raw cloud
  /// maps.
  static String _nlogKeyForRestore({
    required String dateStr,
    required String mealType,
    required List<dynamic> items,
  }) {
    // Sort by name (case-insensitive trim) for stable hash regardless
    // of cloud row ordering.
    final pairs = <String>[];
    for (final raw in items) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final name = (m['name'] ?? m['food_name'] ?? '').toString();
      final qtyRaw = m['quantity_g'] ?? m['serving_g'];
      final qty = (qtyRaw is num) ? qtyRaw.toDouble() : 0.0;
      pairs.add('${name.toLowerCase().trim()}|${qty.toStringAsFixed(1)}');
    }
    pairs.sort();
    final joined = pairs.join(';');
    // H-15 (audit-2026-05-11) — `String.hashCode` is NOT guaranteed
    // stable across Dart VM versions / isolates / platforms. Two
    // devices running the same restore could compute different
    // 8-char tags for the same `(date, meal, items)` tuple → Hive
    // ends up with two rows for what should be one logical meal.
    // Switched to UUID v5 (deterministic, cross-platform stable);
    // take the first 8 hex chars to keep the Hive key compact and
    // visually similar to the previous shape.
    final hash = _uuidGen
        .v5(_syncNamespace, joined)
        .replaceAll('-', '')
        .substring(0, 8);
    return 'nlog_${dateStr}_${mealType}_$hash';
  }

  /// Namespace for custom-entity stable IDs (F8/F22).
  /// Must match the namespace used in `CreateCustomExerciseSheet` and
  /// `NutritionNotifier.addCustomFood`.
  static const _customEntityNamespace = '5a1f0b0c-9dad-11d1-80b4-00c04fd430c8';

  /// Deterministic id for a custom entity (exercise or food).
  /// Same (userId, type, lowercased name) → same id across devices.
  static String _customEntityId(String userId, String type, String name) {
    return _uuidGen.v5(
      _customEntityNamespace,
      '$userId|$type|${name.toLowerCase()}',
    );
  }

  // ── Sync Reliability (feature-flagged) ─────────────────────

  /// When true, failed Supabase writes are enqueued in `SyncQueue` and
  /// retried with exponential backoff. Dead-lettered failures are reported
  /// to the `log-client-error` Edge Function.
  ///
  /// When false (default): existing fire-and-forget behavior is preserved —
  /// failures are logged to `debugPrint` only. This is a safety flag for
  /// the sync-reliability rollout; flip to `true` after dark-launch
  /// validation.
  bool get _syncReliabilityEnabled =>
      _hive.configBox.get('sync_reliability_v1', defaultValue: false) as bool;

  /// One-time queue initialization — registers op executors and the
  /// dead-letter telemetry hook. Must be called AFTER Hive init and
  /// BEFORE any sync path runs. Safe to call multiple times (idempotent).
  bool _queueInitialized = false;
  void initQueue() {
    if (_queueInitialized) return;
    _queueInitialized = true;

    SyncQueue.instance.registerExecutor(
      'upsert_user_profile',
      _executeUserProfileUpsert,
    );

    SyncQueue.instance.onDeadLetter = _sendDeadLetterTelemetry;
  }

  /// Executor for `upsert_user_profile` ops. The payload is the full
  /// column map (keys already mirror `user_profile` column names).
  /// Returns a typed `Result` — success or classified `SyncError`.
  Future<Result<void, SyncError>> _executeUserProfileUpsert(
    Map<String, dynamic> payload,
  ) async {
    try {
      await _supabase.client
          .from('user_profile')
          .upsert(payload, onConflict: 'user_id')
          .select()
          .single();
      return Result.ok(null);
    } catch (e) {
      return Result.err(SyncError.classify(e));
    }
  }

  /// Posts a dead-letter record to `log-client-error` Edge Function.
  /// Non-fatal — telemetry failure is swallowed (queue has already
  /// removed the op).
  Future<void> _sendDeadLetterTelemetry(PendingSyncOp op) async {
    try {
      await _supabase.client.functions.invoke(
        'log-client-error',
        body: {
          'error_code': op.lastErrorCode ?? 'UnknownError',
          'error_message': op.lastErrorMessage,
          'op_type': op.opType,
          'retry_count': op.retryCount,
          'client_version': _currentClientVersion(),
          'platform': _currentPlatform(),
        },
      );
    } catch (e, st) {
      debugPrint('[SyncService] dead-letter telemetry failed: $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_send_dead_letter_telemetry'));
    }
  }

  static String _currentPlatform() {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
    } catch (_) {/* Platform unavailable on web */}
    return 'web';
  }

  /// Audit 2026-05-12 P2-A — was `0.0.0+release` hardcoded which prevented
  /// correlating client_errors rows to APK builds. Now reads from
  /// AppConstants.appVersion (kept in sync with pubspec.yaml version).
  /// kDebugMode override preserves the historical dev/release distinction.
  static String _currentClientVersion() {
    return kDebugMode ? '${AppConstants.appVersion}+dev' : AppConstants.appVersion;
  }

  // ── Public API ──────────────────────────────────────────────

  /// Active realtime subscription (PRO only, for Telegram cross-channel).
  StreamSubscription? _realtimeSubscription;

  /// Completes when health sync finishes (or immediately if disabled).
  /// The home screen awaits this to invalidate [todayStepsProvider] at
  /// exactly the right moment instead of guessing with a fixed delay.
  Completer<void>? _healthSyncCompleter;

  /// F5 · Broadcasts after `checkAndSync` completes a restore pass so
  /// screens can invalidate cached providers (PRs, plan, stats). Emits
  /// on every successful sync cycle, not just restore-from-empty.
  final StreamController<void> _restoreCompleteController =
      StreamController<void>.broadcast();
  Stream<void> get onRestoreComplete => _restoreCompleteController.stream;

  /// Returns a Future that completes when the current health sync pass
  /// finishes writing to Hive. Returns an already-completed future when
  /// no sync is in progress or health sync is disabled.
  Future<void> get healthSyncDone =>
      _healthSyncCompleter?.future ?? Future.value();

  /// Called on every app launch. Determines what needs syncing and
  /// triggers the appropriate operations in the background.
  ///
  /// Never blocks the UI — failures are silently ignored.
  Future<void> checkAndSync() async {
    try {
      if (!_supabase.isAuthenticated) return;

      // APK Test #12.7 — defensive HiveUserSession bootstrap. Cold-start
      // path can land here before `_ensureLocalUser` ran (e.g. the
      // restoring screen kicks off other syncs in parallel). Without
      // this every user-scoped box read below throws
      // `HiveUserSession not opened` and the unawaited swallow nukes
      // the cloud upload silently.
      final userId = await _ensureSessionOpen();
      if (userId == null) return;

      // ── Health sync FIRST — steps/weight are fast local reads from
      // Health Connect and the user expects to see them immediately on
      // the home screen. All other sync tasks (restore, full sync,
      // snapshot push) are slower and can follow afterward.
      _healthSyncCompleter = Completer<void>();
      if (HealthSyncService.isEnabled()) {
        try {
          await HealthSyncService.instance.syncToHive();
          debugPrint('[SyncService.checkAndSync] Health sync completed '
              '(wroteData=${HealthSyncService.instance.lastSyncWroteData})');
        } catch (e, st) {
          debugPrint('[SyncService.checkAndSync] Health sync failed: $e');
          // audit-2026-05-11 H-42 — telemetry pair.
          unawaited(ErrorTelemetry.recordNonFatal(e, st,
              reason: 'sync_service_check_and_sync'));
        }
      }
      _healthSyncCompleter!.complete();

      // Drain any telemetry failures that were queued during the previous
      // session because _reportSyncFailure itself hit a network error.
      unawaited(drainTelemetryQueue());

      // Backfill custom-entity ids for pre-F8/F22 entries. Runs at most
      // once — the scan is O(customBox.length) and quick.
      await _backfillCustomEntityIds();

      // On reinstall / new device: if Hive workout data is empty,
      // pull everything from Supabase first.
      await _restoreIfNeeded(userId);

      // Self-heal path for the silent onboarding-sync failures observed
      // 2026-04-17 on icanbefitter@gmail.com. If `completeOnboarding`
      // couldn't land the first two upserts (user_profile + user_progress),
      // it leaves `pending_onboarding_sync = true` in configBox. Replay
      // once per launch until it sticks.
      await _replayPendingOnboardingSync(userId);

      // Pull recent cross-channel logs (Telegram → Hive, last 24h).
      await pullRecentCrossChannelLogs();

      // Pull latest fitness_summary from Supabase → Hive (updated nightly by rolling-context).
      await _syncFitnessSummary(userId);

      // Check if a weekly full sync is needed.
      final lastFull = _getTimestamp(_lastFullSyncKey);
      if (lastFull == null ||
          DateTime.now().difference(lastFull) >= _fullSyncInterval) {
        await weeklyFullSync();
      }

      // Push any pending custom items immediately.
      await _syncCustomItems();

      // Push daily snapshot + trigger coaching notes extraction.
      // Idempotent: Edge Function upserts by (user_id, snapshot_date).
      // Includes: profile, progress, workouts, nutrition, water, steps,
      // weight, PRs, coaching notes — full AI context for reports/alerts.
      try {
        await pushSnapshot();
      } catch (e, st) {
        debugPrint('[SyncService.checkAndSync] Snapshot push failed: $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_catch'));
        try {
          await _reportSyncFailure(opType: 'check_and_sync_snapshot', error: e);
        } catch (_) {}
      }

      // Pull approved community foods/exercises.
      await syncCommunityItems();

      // PRO users: subscribe to realtime for instant Telegram sync.
      if (SubscriptionService.instance.isPro()) {
        unawaited(subscribeToRealtimeSync());
      }

      // F5 · Broadcast restore-complete so screens can invalidate cached
      // providers (PRs recomputed from refreshed logs, plan from latest
      // templates, etc.).
      if (!_restoreCompleteController.isClosed) {
        _restoreCompleteController.add(null);
      }
    } catch (e, st) {
      // Offline or error — silently skip.
      // Ensure the health sync completer is resolved even on early failure
      // so the home screen doesn't hang.
      if (_healthSyncCompleter != null && !_healthSyncCompleter!.isCompleted) {
        _healthSyncCompleter!.complete();
      }
      debugPrint('[SyncService.checkAndSync] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_if_2'));
      try {
        await _reportSyncFailure(opType: 'check_and_sync', error: e);
      } catch (_) {}
    }
  }

  /// Compiles a daily snapshot from Hive data for AI context injection.
  Map<String, dynamic> compileDailySnapshot() {
    final today = istDateStr(DateTime.now());
    final aiContext = AiCoachRepository.instance.buildAiContext();

    return {
      'snapshot_date': today,
      ...aiContext,
    };
  }

  /// Pushes the daily snapshot to Supabase via the `daily-snapshot` Edge
  /// Function. The function upserts `user_daily_snapshots`, runs coaching
  /// notes extraction, and returns the latest `coach_memory` row, which
  /// we mirror into Hive `coachBox['coach_memory']` for local readers.
  Future<void> pushSnapshot() async {
    try {
      // APK Test #12.7 — open HiveUserSession before compiling the
      // snapshot. compileDailySnapshot() → AiCoachRepository.buildAiContext
      // touches every user-scoped box; without the bootstrap the call
      // throws StateError and the catch below swallows it.
      final userId = await _ensureSessionOpen();
      if (userId == null) return;

      final snapshot = compileDailySnapshot();

      final response = await _supabase.client.functions.invoke(
        'daily-snapshot',
        body: {'snapshot_json': snapshot},
      );

      if (response.status != 200) {
        debugPrint(
          '[SyncService.pushSnapshot] non-200 from daily-snapshot: ${response.status}',
        );
      }

      // Mirror coach_memory from the response into Hive (Layer 4/5 identity).
      // Wrapped defensively — a malformed/changed schema must NEVER crash sync.
      if (response.status == 200 && response.data is Map) {
        try {
          final data = response.data as Map;
          final memJson = data['coach_memory'];
          if (memJson is Map) {
            final mem = CoachMemory.fromJson(memJson);
            await mem.writeToBox(_hive.coachBox);
            debugPrint(
              '[SyncService.pushSnapshot] coach_memory mirrored to Hive',
            );
          }
        } catch (memErr, st) {
          debugPrint(
            '[SyncService.pushSnapshot] coach_memory mirror failed: $memErr',
          );
          // audit-2026-05-11 H-42 — telemetry pair.
          unawaited(ErrorTelemetry.recordNonFatal(memErr, st,
              reason: 'sync_service_if_3'));
          try {
            await _reportSyncFailure(opType: 'mirror_coach_memory_from_snapshot', error: memErr);
          } catch (_) {}
        }
      }

      await _setTimestamp(_lastSnapshotKey);
    } catch (e, st) {
      // Offline — will retry next scheduled run.
      debugPrint('[SyncService.pushSnapshot] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_catch_2'));
      try {
        await _reportSyncFailure(opType: 'push_snapshot', error: e);
      } catch (_) {}
    }
  }

  /// Pushes all workout logs, nutrition logs, weight logs, measurements,
  /// sleep logs, and streaks to Supabase.
  ///
  /// Triggered on app launch if >1 day since last full sync.
  Future<void> weeklyFullSync() async {
    try {
      final userId = _supabase.currentUser?.id;
      if (userId == null) return;

      // APK Test #14 / Bug B.1 — `_syncWorkoutTemplates` MUST complete
      // before `_syncScheduledWorkouts` starts, otherwise the schedule
      // upsert FK-references a parent row cloud doesn't have yet → 23503.
      // Pre-fix this was inside the parallel `Future.wait` and racy.
      // See docs/diagnoses/2026-05-10-fk-violation-saturday-c8e4a1.md.
      await _safeRestoreOp('sync_templates', _syncWorkoutTemplates(userId));

      await Future.wait(
        [
          _safeRestoreOp('sync_workouts', _syncWorkoutLogs(userId)),
          _safeRestoreOp('sync_exercises', _syncExerciseLogs(userId)),
          _safeRestoreOp('sync_schedule_completions', _syncScheduleCompletions(userId)),
          _safeRestoreOp('sync_nutrition', _syncNutritionLogs(userId)),
          _safeRestoreOp('sync_weight', _syncWeightLogs(userId)),
          _safeRestoreOp('sync_measurements', _syncMeasurements(userId)),
          _safeRestoreOp('sync_sleep', _syncSleepLogs(userId)),
          _safeRestoreOp('sync_steps', _syncStepsLogs(userId)), // F20
          _safeRestoreOp('sync_streaks', _syncStreaks(userId)),
          _safeRestoreOp('sync_user_profile', _syncUserProfile(userId)),
          _safeRestoreOp('sync_urine', _syncUrineColorLogs(userId)),
          _safeRestoreOp('sync_water', _syncWaterLogs(userId)),
          _safeRestoreOp('sync_workout_plan', _syncWorkoutPlan(userId)),
          _safeRestoreOp('sync_user_progress', _syncUserProgress(userId)),
          // ── New sync gap methods (templates run sequentially above) ──
          _safeRestoreOp('sync_scheduled_workouts', _syncScheduledWorkouts(userId)),
          _safeRestoreOp('sync_saved_meals', _syncSavedMeals(userId)),
          _safeRestoreOp('sync_preferences', _syncUserPreferences(userId)),
          _safeRestoreOp('sync_coach_interactions', _syncCoachInteractions(userId)),
        ],
        eagerError: false,
      );

      await _setTimestamp(_lastFullSyncKey);
    } catch (e, st) {
      // Partial sync failure — next launch will retry.
      debugPrint('[SyncService.weeklyFullSync] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_weekly_full_sync'));
      try {
        await _reportSyncFailure(opType: 'weekly_full_sync', error: e);
      } catch (_) {}
    }
  }

  // ── Workout-Specific Sync (callable after workout completion) ──

  // ── Restore from Cloud (reinstall / new device) ────────────────

  /// If `completeOnboarding` left `pending_onboarding_sync = true` in
  /// configBox, replay the Hive → Supabase push. Clears the flag on
  /// success; leaves it set for the next launch on failure.
  ///
  /// Safe no-op when:
  ///   - The flag is unset (normal healthy case).
  ///   - Hive has no profile row (logged out between attempts).
  ///
  /// This is the true safety net for the "user_profile stays all-NULL"
  /// failure mode that the inline 10 s retry misses when the user taps
  /// through to the Home screen before the retry fires.
  Future<void> _replayPendingOnboardingSync(String userId) async {
    try {
      final pending = MigratedKey.read<bool>('pending_onboarding_sync');
      if (pending != true) return;

      final profile = _hive.userBox.get('profile');
      final progress = _hive.userBox.get('progress');
      if (profile == null) {
        debugPrint('[SyncService._replayPendingOnboardingSync] '
            'flag set but Hive profile missing — clearing flag');
        await MigratedKey.delete('pending_onboarding_sync');
        return;
      }

      final p = Map<String, dynamic>.from(profile as Map);
      final pr = progress == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(progress as Map);

      await UserRepository.syncOnboardingToSupabase(
        userId: userId,
        userData: {
          'email': _supabase.currentUser?.email,
          'full_name': p['full_name'],
          'onboarding_completed': true,
          'last_active_at': DateTime.now().toIso8601String(),
        },
        profileData: {
          'date_of_birth': p['date_of_birth'],
          'gender': p['gender'],
          'height_cm': p['height_cm'],
          'current_weight_kg': p['current_weight_kg'],
          'target_weight_kg': p['target_weight_kg'],
          'primary_goal': p['primary_goal'],
          'fitness_experience': p['fitness_experience'],
          'days_per_week': p['days_per_week'],
          'equipment_access': p['equipment_access'],
          'activity_level': p['activity_level'],
          'lifestyle_activity': p['lifestyle_activity'],
          'pace_preference': p['pace_preference'],
          'diet_preference': p['diet_preference'],
          'injuries': p['injuries'] is List ? p['injuries'] : <String>[],
          'city': p['city'],
          'bmr': p['bmr'],
          'tdee': p['tdee'],
          'body_fat_percent': p['body_fat_percent'],
          'body_fat_assessed_at': p['body_fat_assessed_at'],
          'session_duration_minutes': p['session_duration_minutes'],
          'physique_focus': p['physique_focus'],
          'avatar_url': p['avatar_url'],
          'banner_url': p['banner_url'],
          'wake_up_time': p['wake_up_time'],
          'preferred_workout_time': p['preferred_workout_time'],
          'daily_calories': p['daily_calories'],
          'protein_grams': p['protein_grams'],
          'carbs_grams': p['carbs_grams'],
          'fat_grams': p['fat_grams'],
          'water_target_ml': p['water_target_ml'],
        },
        progressData: {
          'current_phase': pr['current_phase'] ?? 1,
          'current_week': pr['current_week'] ?? 1,
          'total_workouts_done': pr['total_workouts_done'] ?? 0,
          'current_streak_weeks': pr['current_streak_weeks'] ?? 0,
          'phase_started_at':
              pr['phase_started_at'] ?? DateTime.now().toIso8601String(),
          'plan_generated_at':
              pr['plan_generated_at'] ?? DateTime.now().toIso8601String(),
          'detected_experience_level': p['fitness_experience'],
        },
      );

      await MigratedKey.delete('pending_onboarding_sync');
      debugPrint('[SyncService._replayPendingOnboardingSync] success — flag cleared');
    } catch (e, st) {
      debugPrint('[SyncService._replayPendingOnboardingSync] failed: $e '
          '— flag left set; will retry next launch');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_if_4'));
      unawaited(_reportSyncFailure(
        opType: 'onboarding_sync_replay',
        error: e,
      ));
    }
  }

  /// Checks if local Hive is empty and restores from Supabase if so.
  /// Called automatically by checkAndSync() on app launch.
  Future<void> _restoreIfNeeded(String userId) async {
    // Check if there's any workout data locally. If workoutBox has
    // exercise logs or workout logs, the user hasn't reinstalled.
    bool hasLocalData = false;
    for (final key in _hive.workoutBox.keys) {
      if (key is String &&
          (key.startsWith('wlog_') || key.startsWith('exlog_'))) {
        hasLocalData = true;
        break;
      }
    }

    if (!hasLocalData) {
      await restoreFromCloud(userId);
    } else {
      // F6 · Even when Hive has workout data, pull lightweight pieces that
      // may have changed on another device or via an admin action —
      // custom items, templates, profile, progress. These are cheap
      // (small, indexed by user_id) and inexpensive to merge.
      await restoreLightweightAlways(userId);
    }
  }

  /// F6 · Lightweight restore that fires on every sign-in regardless of
  /// whether Hive has workout history. Pulls the small, frequently-drifting
  /// datasets: profile, progress, subscription-adjacent state, customs,
  /// templates. Bulk history (workout/nutrition logs) stays gated on
  /// empty-Hive so we don't re-download GBs every launch.
  Future<void> restoreLightweightAlways(String userId) async {
    try {
      await Future.wait(
        [
          _safeRestoreOp('user_profile', _restoreUserProfile(userId)),
          _safeRestoreOp('user_progress', _restoreUserProgress(userId)),
          _safeRestoreOp('custom_exercises', _restoreCustomExercises(userId)),
          _safeRestoreOp('custom_foods', _restoreCustomFoods(userId)),
          _safeRestoreOp('workout_templates', _restoreWorkoutTemplates(userId)),
          _safeRestoreOp('user_preferences', _restoreUserPreferences(userId)),
        ],
        eagerError: false,
      );
    } catch (e, st) {
      debugPrint('[SyncService.restoreLightweightAlways] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_restore_lightweight_always'));
      try {
        await _reportSyncFailure(opType: 'restore_lightweight_always', error: e);
      } catch (_) {}
    }
  }

  /// Pulls all user data from Supabase into Hive.
  /// Used on reinstall/login when Hive is empty.
  ///
  /// Restores full history for ALL users (free + PRO).
  /// Storage per user is negligible (~1-2MB/year).
  Future<void> restoreFromCloud(String userId) async {
    try {
      // Full restore for ALL users — no date limit. Data is already in Supabase
      // and storage per user is negligible (~1-2MB/year).
      const since = '2020-01-01T00:00:00Z';

      // APK Test #12.9 — _restoreWorkoutPlan must complete BEFORE
      // _restoreScheduledWorkouts so cloud-authoritative status='completed'
      // is the LAST writer to schedule_<date> keys. See
      // restoreFromCloudForUser for the full rationale.
      await _safeRestoreOp('workout_plan', _restoreWorkoutPlan(userId));

      await Future.wait(
        [
          _safeRestoreOp('workout_logs', _restoreWorkoutLogs(userId, since)),
          _safeRestoreOp('exercise_logs', _restoreExerciseLogs(userId, since)),
          _safeRestoreOp('schedule_completions', _restoreScheduleCompletions(userId, since)),
          _safeRestoreOp('custom_exercises', _restoreCustomExercises(userId)),
          _safeRestoreOp('custom_foods', _restoreCustomFoods(userId)),
          _safeRestoreOp('weight_logs', _restoreWeightLogs(userId, since)),
          _safeRestoreOp('steps_logs', _restoreStepsLogs(userId, since)), // F20
          _safeRestoreOp('nutrition_logs', _restoreNutritionLogs(userId, since)),
          _safeRestoreOp('measurements', _restoreMeasurements(userId, since)),
          _safeRestoreOp('user_profile', _restoreUserProfile(userId)),
          _safeRestoreOp('user_progress', _restoreUserProgress(userId)),
          _safeRestoreOp('water_logs', _restoreWaterLogs(userId, since)),
          _safeRestoreOp('sleep_logs', _restoreSleepLogs(userId, since)),
          _safeRestoreOp('streaks', _restoreStreaks(userId)),
          // ── New restore methods ──
          _safeRestoreOp('workout_templates', _restoreWorkoutTemplates(userId)),
          _safeRestoreOp('scheduled_workouts', _restoreScheduledWorkouts(userId, since)),
          _safeRestoreOp('saved_meals', _restoreSavedMeals(userId)),
          _safeRestoreOp('user_preferences', _restoreUserPreferences(userId)),
          _safeRestoreOp('coach_interactions', _restoreCoachInteractions(userId, since)),
          _safeRestoreOp('coach_memory', _restoreCoachMemory(userId)), // B7 — skip induction on returning device
        ],
        eagerError: false,
      );
    } catch (e, st) {
      // Partial restore is fine — app works offline with whatever we got.
      debugPrint('[SyncService.restoreFromCloud] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_restore_from_cloud'));
      try {
        await _reportSyncFailure(opType: 'restore_from_cloud', error: e);
      } catch (_) {}
    }
  }

  /// Cancellable restore used by [RestoringScreen].
  ///
  /// Returns [RestoreResult.success] when all steps complete,
  /// [RestoreResult.cancelled] if [cancelInflightRestore] was called between
  /// steps, or [RestoreResult.failed] on an unrecoverable error.
  ///
  /// The cancellation flag is reset at the start of each call so callers can
  /// safely call this multiple times.
  Future<RestoreResult> restoreFromCloudForUser() async {
    _restoreCancelled = false;
    final userId = _supabase.currentUser?.id;
    if (userId == null) {
      return RestoreResult.failed('No authenticated user');
    }

    // Test #12.6 — defensive HiveUserSession bootstrap. Cold-start path
    // (splash → /restoring) does NOT call _ensureLocalUser, so the
    // user-scoped namespaced boxes (workoutBox / nutritionBox / etc.)
    // are not yet open when this method runs. Every restore op then
    // throws `HiveUserSession not opened — cannot wrap user-scoped box
    // "<name>"` from GuardedBox, surfacing as 30+ client_errors per cold
    // start.
    //
    // openForUser is documented as idempotent for the same id (line 67-94
    // of hive_user_session.dart returns immediately when
    // _currentOwnerFullId == userId), so it is safe to call here even if
    // _ensureLocalUser already ran. This closes the race regardless of
    // upstream caller ordering.
    try {
      await HiveUserSession.openForUser(userId);
    } catch (e, st) {
      debugPrint(
        '[SyncService.restoreFromCloudForUser] openForUser failed: $e',
      );
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_if_5'));
      return RestoreResult.failed(e);
    }

    // APK Test #12.8 — restore lifecycle event so we can correlate
    // post-restore symptoms (PRO pill stuck, profile blank) with
    // whether restore even ran. Pre-12.8 we had per-op
    // _reportSyncFailure but no "started/completed" bookend to detect
    // "restore never ran" cases.
    unawaited(ErrorTelemetry.logEvent('restore_started',
        message: 'userId=${userId.substring(0, 8)}'));

    try {
      const since = '2020-01-01T00:00:00Z';

      // Step A — profile + lightweight data
      if (_restoreCancelled) return RestoreResult.cancelled();
      await Future.wait(
        [
          _safeRestoreOp('user_profile', _restoreUserProfile(userId)),
          _safeRestoreOp('user_progress', _restoreUserProgress(userId)),
          _safeRestoreOp('custom_exercises', _restoreCustomExercises(userId)),
          _safeRestoreOp('custom_foods', _restoreCustomFoods(userId)),
          _safeRestoreOp('workout_templates', _restoreWorkoutTemplates(userId)),
          _safeRestoreOp('user_preferences', _restoreUserPreferences(userId)),
          // APK Test #12.9 — moved from step B. _restoreWorkoutPlan
          // writes `schedule_*` keys from a frozen `plan_json.schedules`
          // snapshot (status='planned' for all days). _restoreScheduledWorkouts
          // (step B) overlays cloud-authoritative status='completed' from
          // the live `scheduled_workouts` table. Pre-12.9 both ran in
          // parallel via Future.wait; if `_restoreWorkoutPlan` won the
          // race it clobbered the completed status with stale 'planned'.
          // Sequential ordering (A before B) guarantees the live table
          // is the LAST writer and therefore wins.
          _safeRestoreOp('workout_plan', _restoreWorkoutPlan(userId)),
        ],
        eagerError: false,
      );

      // Step B — bulk history
      if (_restoreCancelled) return RestoreResult.cancelled();
      await Future.wait(
        [
          _safeRestoreOp('workout_logs', _restoreWorkoutLogs(userId, since)),
          _safeRestoreOp('exercise_logs', _restoreExerciseLogs(userId, since)),
          _safeRestoreOp('schedule_completions', _restoreScheduleCompletions(userId, since)),
          _safeRestoreOp('weight_logs', _restoreWeightLogs(userId, since)),
          _safeRestoreOp('steps_logs', _restoreStepsLogs(userId, since)),
          _safeRestoreOp('nutrition_logs', _restoreNutritionLogs(userId, since)),
          _safeRestoreOp('measurements', _restoreMeasurements(userId, since)),
          _safeRestoreOp('water_logs', _restoreWaterLogs(userId, since)),
          _safeRestoreOp('sleep_logs', _restoreSleepLogs(userId, since)),
          _safeRestoreOp('streaks', _restoreStreaks(userId)),
          _safeRestoreOp('scheduled_workouts', _restoreScheduledWorkouts(userId, since)),
          _safeRestoreOp('saved_meals', _restoreSavedMeals(userId)),
          _safeRestoreOp('coach_interactions', _restoreCoachInteractions(userId, since)),
          _safeRestoreOp('coach_memory', _restoreCoachMemory(userId)), // B7 — skip induction on returning device; also pulls coaching_notes (A6)
        ],
        eagerError: false,
      );

      // Step C — restore-completeness surfaces (Theme A pull side).
      // These are smaller/faster operations run sequentially after bulk
      // history so a cancellation between steps doesn't leave Hive
      // in a partially-populated state.
      if (_restoreCancelled) return RestoreResult.cancelled();
      await _safeRestoreOp('freezes', _restoreFreezes(userId));
      if (_restoreCancelled) return RestoreResult.cancelled();
      await _safeRestoreOp('notifications_inbox', _restoreNotificationsInbox(userId));
      if (_restoreCancelled) return RestoreResult.cancelled();
      await _safeRestoreOp('saved_diet_plan', _restoreSavedDietPlan(userId));
      if (_restoreCancelled) return RestoreResult.cancelled();
      await _safeRestoreOp('rank_promotions', _restoreRankPromotions(userId));
      // E.10 (F4-S2 / audit 2026-05-16) — referral surfaces.
      // Codes survive reinstall + audit history visible cross-device.
      if (_restoreCancelled) return RestoreResult.cancelled();
      await _safeRestoreOp('referral_codes', _restoreReferralCodes(userId));
      if (_restoreCancelled) return RestoreResult.cancelled();
      await _safeRestoreOp(
          'referral_redemptions', _restoreReferralRedemptions(userId));

      // A3 — Subscription refresh folded into restore as the atomic last
      // step so it's never skipped when the post-auth flow changes.
      // Fire-and-forget posture: failure keeps cached local PRO state
      // (consistent with existing refreshFromSupabase semantics).
      if (_restoreCancelled) return RestoreResult.cancelled();
      try {
        await SubscriptionService.instance.refreshFromSupabase();
      } catch (e, st) {
        // Non-fatal — keep cached subscription state.
        debugPrint('[SyncService.restoreFromCloudForUser] subscription refresh error: $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_catch_3'));
        unawaited(_reportSyncFailure(
            opType: 'subscription_refresh_on_restore', error: e));
      }

      if (_restoreCancelled) return RestoreResult.cancelled();
      // APK Test #12.8 — restore completion event. Counts every full
      // success path. If client_errors shows restore_started without a
      // matching restore_completed, the user had a silent abort
      // somewhere in steps A-C.
      unawaited(ErrorTelemetry.logEvent('restore_completed',
          message: 'userId=${userId.substring(0, 8)} status=success'));
      return RestoreResult.success();
    } catch (e) {
      debugPrint('[SyncService.restoreFromCloudForUser] $e');
      try {
        await _reportSyncFailure(opType: 'restore_from_cloud_for_user', error: e);
      } catch (_) {}
      unawaited(ErrorTelemetry.logEvent('restore_completed',
          message: 'userId=${userId.substring(0, 8)} status=failed'));
      return RestoreResult.failed(e);
    }
  }

  // ── Fitness Summary Sync (rolling-context → Hive) ───────────

  /// Fetches the latest fitness_summary from user_daily_snapshots
  /// and writes it to coachBox. Updated nightly by rolling-context cron.
  Future<void> _syncFitnessSummary(String userId) async {
    try {
      final rows = await _supabase.client
          .from('user_daily_snapshots')
          .select('snapshot_json')
          .eq('user_id', userId)
          .not('snapshot_json->fitness_summary', 'is', null)
          .order('snapshot_date', ascending: false)
          .limit(1);

      if (rows.isNotEmpty) {
        final json = rows.first['snapshot_json'] as Map<String, dynamic>?;
        final summary = json?['fitness_summary'] as String?;
        if (summary != null && summary.isNotEmpty) {
          await _hive.coachBox.put('fitness_summary', summary);
        }
      }
    } catch (e, st) {
      debugPrint('[SyncService._syncFitnessSummary] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_if_6'));
      try {
        await _reportSyncFailure(opType: 'sync_fitness_summary', error: e);
      } catch (_) {}
    }
  }

  // ── Cross-Channel Sync (Telegram → Hive) ────────────────────

  /// Pulls logs from Supabase that were created in the last 24 hours
  /// from other channels (e.g. Telegram bot). Merges into local Hive
  /// without overwriting existing entries.
  Future<void> pullRecentCrossChannelLogs() async {
    try {
      final userId = _supabase.currentUser?.id;
      if (userId == null) return;

      final since =
          DateTime.now().subtract(const Duration(hours: 24)).toIso8601String();

      await Future.wait(
        [
          _safeRestoreOp('pull_weight', _pullWeightLogs(userId, since)),
          _safeRestoreOp('pull_nutrition', _pullNutritionLogs(userId, since)),
          _safeRestoreOp('pull_measurements', _pullMeasurements(userId, since)),
        ],
        eagerError: false,
      );
    } catch (e, st) {
      // Offline or error — silently skip.
      debugPrint('[SyncService.pullRecentCrossChannelLogs] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_pull_recent_cross_channel_logs'));
      try {
        await _reportSyncFailure(opType: 'pull_cross_channel_logs', error: e);
      } catch (_) {}
    }
  }

  Future<void> _pullWeightLogs(String userId, String since) async {
    final res = await _supabase.client
        .from('weight_logs')
        .select()
        .eq('user_id', userId)
        .gte('created_at', since);

    final rows = res;
    final healthBox = _hive.healthBox;
    for (final row in rows) {
      final map = Map<String, dynamic>.from(row as Map);
      final date = map['date'] as String? ?? '';
      final key = 'weight_$date';
      // Skip if already exists locally (Hive-first wins)
      if (healthBox.get(key) != null) continue;
      await healthBox.put(key, {
        'type': 'weight_log',
        'date': date,
        'weight_kg': map['weight_kg'],
        'created_at': map['created_at'],
        'source': 'telegram',
      });
    }
  }

  Future<void> _pullNutritionLogs(String userId, String since) async {
    final res = await _supabase.client
        .from('nutrition_logs')
        .select()
        .eq('user_id', userId)
        .gte('created_at', since);

    final rows = res;
    final nutritionBox = _hive.nutritionBox;
    for (final row in rows) {
      final map = Map<String, dynamic>.from(row as Map);
      final id = map['id'] as String? ?? '';
      // Skip if already exists locally
      if (nutritionBox.get(id) != null) continue;
      await nutritionBox.put(id, {
        ...map,
        'source': map['source'] ?? 'telegram',
      });
    }
  }

  Future<void> _pullMeasurements(String userId, String since) async {
    final res = await _supabase.client
        .from('body_measurements')
        .select()
        .eq('user_id', userId)
        .gte('created_at', since);

    final rows = res;
    final healthBox = _hive.healthBox;
    for (final row in rows) {
      final map = Map<String, dynamic>.from(row as Map);
      final date = map['date'] as String? ?? '';
      final key = 'measurement_$date';
      // Merge — don't overwrite if exists (individual fields may differ)
      final existing = healthBox.get(key);
      if (existing is Map) {
        final merged = Map<String, dynamic>.from(existing);
        // Only fill in fields that are null locally
        for (final field in ['waist', 'chest', 'hips', 'arms']) {
          if (merged[field] == null && map[field] != null) {
            merged[field] = map[field];
          }
        }
        await healthBox.put(key, merged);
      } else {
        await healthBox.put(key, {
          ...map,
          'source': 'telegram',
        });
      }
    }
  }

  // ── Private Push Helpers ────────────────────────────────────

  /// Plan A A-5: normalize the per-set list across legacy `sets_detail`
  /// (had explicit `set_number`) and the new WorkoutWriteService `sets`
  /// shape (ordinal — set_number derived from index + 1).
  ///
  /// Returns a list of maps where each entry has at least `set_number`,
  /// `weight_kg`, `reps`. May also include `duration_seconds`,
  /// `duration_sec`, `distance_km`. Empty list → no per-set data
  /// available (fall back to summary-only).
  List<Map<String, dynamic>> _resolvePerSetList(Map<String, dynamic> log) {
    // Prefer legacy `sets_detail` (often has explicit set_number).
    // APK Test #12.2 / Task #7 — defensively stamp set_number from
    // index+1 if the entry lacks it. Cloud audit revealed users with
    // 33 workout_log_exercises rows but 0 workout_log_sets rows: the
    // per-set projection downstream filters entries with null
    // set_number, and pre-Test-#6 sets_detail entries may not carry
    // an explicit set_number. Stamping here unblocks per-set sync.
    final detail = log['sets_detail'];
    if (detail is List && detail.isNotEmpty) {
      final out = <Map<String, dynamic>>[];
      var idx = 0;
      for (final s in detail) {
        if (s is! Map) continue;
        final m = Map<String, dynamic>.from(s);
        if (m['set_number'] == null) {
          m['set_number'] = idx + 1;
        }
        out.add(m);
        idx += 1;
      }
      if (out.isNotEmpty) return out;
    }
    // Fallback to the new WorkoutWriteService shape: `sets` list of
    // {weight_kg, reps, duration_sec?, logged_at_ms} maps. Stamp
    // `set_number` from the array index (1-based).
    final newSets = log['sets'];
    if (newSets is List && newSets.isNotEmpty) {
      final out = <Map<String, dynamic>>[];
      for (var i = 0; i < newSets.length; i++) {
        final s = newSets[i];
        if (s is! Map) continue;
        final m = Map<String, dynamic>.from(s);
        m['set_number'] = i + 1;
        out.add(m);
      }
      return out;
    }
    return const [];
  }

  /// Public wrapper for [_reportSyncFailure] so other modules (e.g. the
  /// onboarding flow's custom catch block) can emit `client_errors`
  /// telemetry through the same code path.
  Future<void> reportSyncFailure({
    required String opType,
    required Object error,
    int retryCount = 0,
  }) => _reportSyncFailure(
        opType: opType,
        error: error,
        retryCount: retryCount,
      );

  /// Wraps a restore/sync future so one table failure cannot abort the others
  /// in a [Future.wait] call.
  ///
  /// On failure the error is logged locally and reported to `client_errors`
  /// via [_reportSyncFailure] with `opType = 'restore_<label>'`. The wrapper
  /// always completes normally so that `eagerError: false` propagation still
  /// works correctly (any remaining tasks in the wait list continue).
  Future<void> _safeRestoreOp(String label, Future<void> task) async {
    try {
      await task;
    } catch (e, st) {
      debugPrint('[sync/restore] $label failed: $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_safe_restore_op'));
      try {
        await _reportSyncFailure(opType: 'restore_$label', error: e);
      } catch (_) {}
    }
  }

  // ── Telemetry failure queue ─────────────────────────────────
  // When _reportSyncFailure itself fails (network error, 5xx, etc.) the failure
  // was previously silently dropped. The queue below persists up to 50 entries
  // in syncBox and drains them on the next checkAndSync call (app launch).

  static const String _telemetryQueueKey = 'pending_telemetry_failures';
  static const int _telemetryQueueMax = 50;

  /// Enqueues a failed telemetry report so it can be retried on next launch.
  /// Last-resort — all exceptions are swallowed to prevent infinite recursion.
  Future<void> _enqueueTelemetryFailure(String opType, Object error) async {
    try {
      final queue =
          (_hive.syncBox.get(_telemetryQueueKey) as List?)?.cast<Map>().toList() ??
              [];
      final msg = error.toString();
      queue.insert(0, {
        'op_type': opType,
        'error': msg.substring(0, msg.length.clamp(0, 500)),
        'queued_at': DateTime.now().toIso8601String(),
      });
      // Cap at max to prevent unbounded Hive growth on persistent failures.
      while (queue.length > _telemetryQueueMax) {
        queue.removeLast();
      }
      await _hive.syncBox.put(_telemetryQueueKey, queue);
    } catch (_) {
      // Last-resort — truly silent.
    }
  }

  /// Drains the telemetry failure queue, retrying each entry via
  /// [_reportSyncFailure]. Entries that succeed are removed; those that still
  /// fail are re-enqueued for the following launch.
  ///
  /// Called fire-and-forget from [checkAndSync] on every app launch.
  Future<void> drainTelemetryQueue() async {
    final queue =
        (_hive.syncBox.get(_telemetryQueueKey) as List?)?.cast<Map>().toList() ??
            [];
    if (queue.isEmpty) return;

    final remaining = <Map>[];
    for (final entry in queue) {
      try {
        await _reportSyncFailure(
          opType: (entry['op_type'] as String?) ?? 'unknown',
          error: (entry['error'] as String?) ?? 'unknown',
        );
        // Success — don't re-add to remaining.
      } catch (_) {
        remaining.add(entry); // Still failing — keep for next attempt.
      }
    }
    await _hive.syncBox.put(_telemetryQueueKey, remaining);
  }

  /// Fire-and-forget telemetry for a sync failure. Sends one row to
  /// `client_errors` via the `log-client-error` Edge Function so we stop
  /// being blind to payload-rejection failures in prod.
  ///
  /// APK Test #12.7 — also forwards to ErrorTelemetry.recordNonFatal so
  /// every sync failure gets a Crashlytics non-fatal record in addition
  /// to the `client_errors` row. This is the single funnel — every
  /// `catch (e) { _reportSyncFailure(...) }` in this file inherits the
  /// Crashlytics leg without per-callsite edits.
  Future<void> _reportSyncFailure({
    required String opType,
    required Object error,
    int retryCount = 0,
  }) async {
    // Crashlytics + secondary log-client-error path (idempotent dual
    // posting; the legacy path below stays as the canonical
    // client_errors writer for retry-queue continuity).
    // Stack is unavailable here (this function takes Object only); pass
    // null and let Crashlytics auto-capture.
    unawaited(ErrorTelemetry.recordNonFatal(error, null, reason: opType));

    try {
      final code = error.runtimeType.toString();
      // Truncate to keep the Edge Function request body reasonable — some
      // PostgrestException messages include the full echoed row which can
      // be several KB on user_profile.
      var message = error.toString();
      if (message.length > 2000) {
        message = '${message.substring(0, 2000)}…(truncated)';
      }
      await _supabase.client.functions.invoke(
        'log-client-error',
        body: {
          'error_code': code,
          'error_message': message,
          'op_type': opType,
          'retry_count': retryCount,
          'client_version': _currentClientVersion(),
          'platform': _currentPlatform(),
        },
      );
    } catch (_) {
      // Telemetry call itself failed — enqueue for next-launch retry so no
      // failure is silently dropped. _enqueueTelemetryFailure is truly silent.
      await _enqueueTelemetryFailure(opType, error);
    }
  }

  /// Immediately pushes all saved meals to Supabase `user_saved_meals`, including
  /// the updated `times_used` counter.
  ///

  /// True if `v` is a non-null, non-empty-string value.
  /// PostgREST rejects `""` for strict-typed columns (date, time, timestamptz,
  /// numeric) with "invalid input syntax" — callers must omit the field
  /// entirely rather than send the empty string.
  static bool _hasValue(dynamic v) {
    if (v == null) return false;
    if (v is String && v.trim().isEmpty) return false;
    return true;
  }

  /// True if `v` is a finite number. Excludes empty strings, NaN, and
  /// infinities that would otherwise corrupt an integer/numeric column.
  static bool _hasNumber(dynamic v) {
    if (v == null) return false;
    if (v is! num) return false;
    if (v is double && (v.isNaN || v.isInfinite)) return false;
    return true;
  }

  // ── Paginated Fetch Helper ──────────────────────────────────

  /// Fetches all rows from a Supabase table using offset-based pagination.
  /// Replaces hardcoded `.limit(5000)` to support full-history restore.
  /// Safety ceiling: 50,000 rows per table to prevent runaway fetches.
  Future<List<Map<String, dynamic>>> _fetchAllRows(
    String table,
    String userId, {
    String? dateColumn,
    String? since,
    String orderBy = 'created_at',
    int pageSize = 1000,
    String? selectColumns,
  }) async {
    const maxRows = 50000;
    final results = <Map<String, dynamic>>[];
    int offset = 0;
    while (true) {
      var query = _supabase.client
          .from(table)
          .select(selectColumns ?? '*')
          .eq('user_id', userId);
      if (dateColumn != null && since != null) {
        query = query.gte(dateColumn, since);
      }
      final rows = await query
          .order(orderBy)
          .range(offset, offset + pageSize - 1);
      for (final row in rows) {
        results.add(Map<String, dynamic>.from(row as Map));
      }
      if (rows.length < pageSize) break; // last page
      offset += pageSize;
      if (results.length >= maxRows) {
        debugPrint('[SyncService._fetchAllRows] Hit $maxRows ceiling for $table');
        break;
      }
    }
    return results;
  }

  // ── Private Restore Helpers (Cloud → Hive) ──────────────────

  // ── Restore: Water, Sleep, Streaks ──────────────────────────

  // ── Sync: Workout Plan + User Progress ─────────────────────

  // ── Gap 1+2: Workout Templates + Template Exercises ─────────

  // ── Gap 3: Scheduled Workouts ──────────────────────────────

  // ── Timestamp helpers ───────────────────────────────────────

  DateTime? _getTimestamp(String key) {
    final raw = _hive.syncBox.get(key);
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  Future<void> _setTimestamp(String key) async {
    await _hive.syncBox.put(key, DateTime.now().toIso8601String());
  }
}
