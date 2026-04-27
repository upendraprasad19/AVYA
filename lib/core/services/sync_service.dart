import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:icanbefitter/core/services/health_sync_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/result.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/sync_error.dart';
import 'package:icanbefitter/core/services/sync_queue.dart';
import 'package:icanbefitter/features/ai_coach/models/coach_memory.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

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
class SyncService {
  SyncService._();
  static final SyncService _instance = SyncService._();
  static SyncService get instance => _instance;

  final HiveService _hive = HiveService.instance;
  final SupabaseService _supabase = SupabaseService.instance;

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

  /// One-shot backfill: iterate customBox, (a) assign deterministic ids to
  /// entries that have none (F8/F22 pre-existing entries), and (b) repair
  /// custom exercises with null/missing `logging_type` (F12). Fire-and-
  /// forget from `checkAndSync()`.
  Future<void> _backfillCustomEntityIds() async {
    try {
      final userId = _supabase.currentUser?.id;
      if (userId == null) return;
      final box = _hive.customBox;
      var idRepaired = 0;
      var loggingTypeRepaired = 0;
      for (final key in box.keys.toList()) {
        final raw = box.get(key);
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final name = map['name'] as String?;
        if (name == null || name.isEmpty) continue;
        final type = map['type'] as String?;
        final entityType = type == 'food' ? 'food' : 'exercise';

        var mutated = false;
        // F8/F22 — stable id
        final existingId = map['id'] as String?;
        if (existingId == null || existingId.isEmpty) {
          map['id'] = _customEntityId(userId, entityType, name);
          mutated = true;
          idRepaired++;
        }
        // F12 — logging_type repair (exercises only)
        if (entityType == 'exercise') {
          final lt = map['logging_type'] as String?;
          if (lt == null || lt.isEmpty) {
            final nLower = name.toLowerCase();
            String inferred;
            if (nLower.contains('hold') || nLower.contains('plank') ||
                nLower.contains('handstand') || nLower.contains('l-sit')) {
              inferred = 'timed';
            } else if (nLower.contains('run') || nLower.contains('row') ||
                nLower.contains('bike') || nLower.contains('walk')) {
              inferred = 'cardio';
            } else {
              final equipment = map['equipment_needed'];
              final isBodyweight = equipment is List && equipment.isEmpty;
              inferred = isBodyweight ? 'bodyweight_reps' : 'weight_reps';
            }
            map['logging_type'] = inferred;
            mutated = true;
            loggingTypeRepaired++;
          }
        }

        if (mutated) {
          await box.put(key, map);
        }
      }
      if (idRepaired > 0 || loggingTypeRepaired > 0) {
        debugPrint('[SyncService] backfilled ids=$idRepaired '
            'loggingType=$loggingTypeRepaired');
        unawaited(_syncCustomItems());
      }
    } catch (e) {
      debugPrint('[SyncService._backfillCustomEntityIds] $e');
    }
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
    } catch (e) {
      debugPrint('[SyncService] dead-letter telemetry failed: $e');
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

  /// Placeholder — wire up `package_info_plus` in a follow-up. For now
  /// return a sentinel so server-side analytics can distinguish dev
  /// builds from release builds without adding a new dependency.
  static String _currentClientVersion() {
    return kDebugMode ? '0.0.0+dev' : '0.0.0+release';
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

      final userId = _supabase.currentUser?.id;
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
        } catch (e) {
          debugPrint('[SyncService.checkAndSync] Health sync failed: $e');
        }
      }
      _healthSyncCompleter!.complete();

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
      } catch (e) {
        debugPrint('[SyncService.checkAndSync] Snapshot push failed: $e');
      }

      // Pull approved community foods/exercises.
      await syncCommunityItems();

      // PRO users: subscribe to realtime for instant Telegram sync.
      if (SubscriptionService.instance.isPro()) {
        subscribeToRealtimeSync();
      }

      // F5 · Broadcast restore-complete so screens can invalidate cached
      // providers (PRs recomputed from refreshed logs, plan from latest
      // templates, etc.).
      if (!_restoreCompleteController.isClosed) {
        _restoreCompleteController.add(null);
      }
    } catch (e) {
      // Offline or error — silently skip.
      // Ensure the health sync completer is resolved even on early failure
      // so the home screen doesn't hang.
      if (_healthSyncCompleter != null && !_healthSyncCompleter!.isCompleted) {
        _healthSyncCompleter!.complete();
      }
      debugPrint('[SyncService.checkAndSync] $e');
    }
  }

  /// Compiles a daily snapshot from Hive data for AI context injection.
  Map<String, dynamic> compileDailySnapshot() {
    final today = DateTime.now().toIso8601String().substring(0, 10);
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
      final userId = _supabase.currentUser?.id;
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
        } catch (memErr) {
          debugPrint(
            '[SyncService.pushSnapshot] coach_memory mirror failed: $memErr',
          );
        }
      }

      await _setTimestamp(_lastSnapshotKey);
    } catch (e) {
      // Offline — will retry next scheduled run.
      debugPrint('[SyncService.pushSnapshot] $e');
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
          // ── New sync gap methods ──
          _safeRestoreOp('sync_templates', _syncWorkoutTemplates(userId)),
          _safeRestoreOp('sync_scheduled_workouts', _syncScheduledWorkouts(userId)),
          _safeRestoreOp('sync_saved_meals', _syncSavedMeals(userId)),
          _safeRestoreOp('sync_preferences', _syncUserPreferences(userId)),
          _safeRestoreOp('sync_coach_interactions', _syncCoachInteractions(userId)),
        ],
        eagerError: false,
      );

      await _setTimestamp(_lastFullSyncKey);
    } catch (e) {
      // Partial sync failure — next launch will retry.
      debugPrint('[SyncService.weeklyFullSync] $e');
    }
  }

  // ── Workout-Specific Sync (callable after workout completion) ──

  /// Push workout logs + exercise logs + schedule completions to Supabase.
  /// Call this after a workout is completed for near-realtime backup.
  Future<void> syncWorkoutData() async {
    try {
      final userId = _supabase.currentUser?.id;
      if (userId == null) return;

      await Future.wait(
        [
          _safeRestoreOp('sync_workout_logs', _syncWorkoutLogs(userId)),
          _safeRestoreOp('sync_exercise_logs', _syncExerciseLogs(userId)),
          _safeRestoreOp('sync_schedule_completions', _syncScheduleCompletions(userId)),
        ],
        eagerError: false,
      );
    } catch (e) {
      // Offline — will sync on next weekly sync.
      debugPrint('[SyncService.syncWorkoutData] $e');
    }
  }

  /// Push nutrition logs + water logs to Supabase.
  /// Call this after a meal is logged (text AI / scan meal / manual / barcode)
  /// or after water is updated, so the daily sync isn't the only safety net.
  ///
  /// Fire-and-forget: offline failure logs silently and retries on next
  /// full sync. Never throws to the caller.
  Future<void> syncNutritionData() async {
    try {
      final userId = _supabase.currentUser?.id;
      if (userId == null) return;

      await Future.wait(
        [
          _safeRestoreOp('sync_nutrition_logs', _syncNutritionLogs(userId)),
          _safeRestoreOp('sync_water_logs', _syncWaterLogs(userId)),
        ],
        eagerError: false,
      );
    } catch (e) {
      // Offline — will sync on next daily full sync.
      debugPrint('[SyncService.syncNutritionData] $e');
    }
  }

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
      final pending = _hive.configBox.get('pending_onboarding_sync');
      if (pending != true) return;

      final profile = _hive.userBox.get('profile');
      final progress = _hive.userBox.get('progress');
      if (profile == null) {
        debugPrint('[SyncService._replayPendingOnboardingSync] '
            'flag set but Hive profile missing — clearing flag');
        await _hive.configBox.delete('pending_onboarding_sync');
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
          'injuries': p['injuries']?.toString(),
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

      await _hive.configBox.delete('pending_onboarding_sync');
      debugPrint('[SyncService._replayPendingOnboardingSync] success — flag cleared');
    } catch (e) {
      debugPrint('[SyncService._replayPendingOnboardingSync] failed: $e '
          '— flag left set; will retry next launch');
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
    } catch (e) {
      debugPrint('[SyncService.restoreLightweightAlways] $e');
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
          _safeRestoreOp('workout_plan', _restoreWorkoutPlan(userId)),
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
    } catch (e) {
      // Partial restore is fine — app works offline with whatever we got.
      debugPrint('[SyncService.restoreFromCloud] $e');
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
          _safeRestoreOp('workout_plan', _restoreWorkoutPlan(userId)),
          _safeRestoreOp('water_logs', _restoreWaterLogs(userId, since)),
          _safeRestoreOp('sleep_logs', _restoreSleepLogs(userId, since)),
          _safeRestoreOp('streaks', _restoreStreaks(userId)),
          _safeRestoreOp('scheduled_workouts', _restoreScheduledWorkouts(userId, since)),
          _safeRestoreOp('saved_meals', _restoreSavedMeals(userId)),
          _safeRestoreOp('coach_interactions', _restoreCoachInteractions(userId, since)),
          _safeRestoreOp('coach_memory', _restoreCoachMemory(userId)), // B7 — skip induction on returning device
        ],
        eagerError: false,
      );

      if (_restoreCancelled) return RestoreResult.cancelled();
      return RestoreResult.success();
    } catch (e) {
      debugPrint('[SyncService.restoreFromCloudForUser] $e');
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
    } catch (e) {
      debugPrint('[SyncService._syncFitnessSummary] $e');
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
    } catch (e) {
      // Offline or error — silently skip.
      debugPrint('[SyncService.pullRecentCrossChannelLogs] $e');
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

  // ── PRO Realtime Sync ──────────────────────────────────────

  /// Subscribes to Supabase realtime channels for instant cross-device
  /// sync. PRO only — enables Telegram-logged data to appear in the
  /// app immediately without waiting for the 24h batch pull.
  void subscribeToRealtimeSync() {
    if (_realtimeSubscription != null) return; // Already subscribed

    final userId = _supabase.currentUser?.id;
    if (userId == null) return;

    // Subscribe to weight_logs inserts for this user.
    // Store the subscription so it can be cancelled on logout.
    _realtimeSubscription = _supabase.client
        .from('weight_logs')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .listen(
          (rows) async {
            try {
              for (final row in rows) {
                final date = row['date'] as String? ?? '';
                final key = 'weight_$date';
                if (_hive.healthBox.get(key) == null) {
                  await _hive.healthBox.put(key, {
                    'type': 'weight_log',
                    'date': date,
                    'weight_kg': row['weight_kg'],
                    'created_at': row['created_at'],
                    'source': 'realtime',
                  });
                }
              }
            } catch (e, st) {
              debugPrint('[realtime] weight_logs handler failed: $e\n$st');
              try {
                await _reportSyncFailure(
                  opType: 'realtime_handler_weight_logs',
                  error: e,
                );
              } catch (_) {
                // ignore: avoid_catches_without_on_clauses
              }
              // do NOT rethrow — keep stream alive
            }
          },
          onError: (e, st) {
            debugPrint('[realtime] weight_logs stream error: $e\n$st');
            // ignore: discarded_futures
            _reportSyncFailure(opType: 'realtime_stream_weight_logs', error: e)
                .catchError((_) {});
          },
        );
  }

  /// Cancels realtime subscriptions (call on app background or logout).
  void unsubscribeRealtime() {
    _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
  }

  // ── Private Push Helpers ────────────────────────────────────

  /// Pushes workout session logs (wlog_* keys) to Supabase workout_logs.
  Future<void> _syncWorkoutLogs(String userId) async {
    final workoutBox = _hive.workoutBox;
    for (final key in workoutBox.keys) {
      if (key is! String || !key.startsWith('wlog_')) continue;
      final raw = workoutBox.get(key);
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);

      try {
        await _supabase.client.from('workout_logs').upsert({
          'id': _deterministicId(key),
          'user_id': userId,
          'exercise_name': log['workout_name'],
          'date': log['date'],
          'logged_at': log['completed_at'],
          'sets_completed': log['sets_completed'],
          'duration_seconds': log['duration_seconds'],
          'notes': log['id'], // store local ID for reference
          'created_at': log['completed_at'] ?? DateTime.now().toIso8601String(),
        }, onConflict: 'id');
      } catch (e) {
        debugPrint('[SyncService._syncWorkoutLogs] Failed key=$key: $e');
      }
    }
  }

  /// Pushes individual exercise logs (exlog_* keys) to
  /// Supabase workout_log_exercises (summary) + workout_log_sets (per-set).
  ///
  /// F4 · Per-set rows preserve granular weight/reps/duration across devices.
  /// The summary row (workout_log_exercises) stays for AI features + analytics.
  Future<void> _syncExerciseLogs(String userId) async {
    final workoutBox = _hive.workoutBox;
    for (final key in workoutBox.keys) {
      if (key is! String || !key.startsWith('exlog_')) continue;
      final raw = workoutBox.get(key);
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);

      try {
        // ── SUMMARY ROW ──
        // 1 row per exercise. weight_kg = best; reps = cumulative; set_number = total.
        final date = log['date'] as String? ?? '';
        final workoutLogId = _deterministicId('workout_$date');
        final exerciseId =
            (log['exercise_name'] as String?) ?? key; // stable identity

        await _supabase.client.from('workout_log_exercises').upsert({
          'id': _deterministicId(key),
          'workout_log_id': workoutLogId,
          'user_id': userId,
          'exercise_id': exerciseId,
          'exercise_name': log['exercise_name'] ?? '',
          'logging_type': log['logging_type'],
          'set_number': log['sets_completed'] ?? 1,
          'reps': log['reps_completed'],
          'weight_kg': log['weight_kg'],
          'duration_seconds': log['duration_seconds'],
          'distance_km': log['distance_km'],
          'is_pr': log['is_pr'] ?? false,
          'has_warmup_sets': log['has_warmup_sets'] ?? false,
          'completed_at': log['created_at'] ?? DateTime.now().toIso8601String(),
        }, onConflict: 'id');

        // ── PER-SET ROWS (F4) ──
        // Upserts a row per set from the Hive `sets_detail` list. Natural key
        // is (workout_log_id, exercise_id, set_number) → idempotent across
        // re-syncs and retries.
        final setsDetail = log['sets_detail'];
        if (setsDetail is List && setsDetail.isNotEmpty) {
          final completedAt = log['created_at'] as String? ??
              DateTime.now().toIso8601String();
          final rows = <Map<String, dynamic>>[];
          for (final s in setsDetail) {
            if (s is! Map) continue;
            final sm = Map<String, dynamic>.from(s);
            final setNum = (sm['set_number'] as num?)?.toInt();
            if (setNum == null) continue;
            rows.add({
              'user_id': userId,
              'workout_log_id': workoutLogId,
              'exercise_id': exerciseId,
              'set_number': setNum,
              'weight_kg': sm['weight_kg'],
              'reps': sm['reps'],
              'duration_secs': sm['duration_seconds'],
              'distance_km': sm['distance_km'],
              'completed_at': completedAt,
            });
          }
          if (rows.isNotEmpty) {
            try {
              await _supabase.client
                  .from('workout_log_sets')
                  .upsert(rows, onConflict: 'workout_log_id,exercise_id,set_number');
            } catch (e) {
              debugPrint(
                  '[SyncService._syncExerciseLogs] per-set push failed key=$key: $e');
            }
          }
        }
      } catch (e) {
        debugPrint('[SyncService._syncExerciseLogs] Failed key=$key: $e');
      }
    }
  }

  /// Pushes completed schedule entries to workout_schedule_completions.
  Future<void> _syncScheduleCompletions(String userId) async {
    final workoutBox = _hive.workoutBox;
    for (final key in workoutBox.keys) {
      if (key is! String || !key.startsWith('schedule_')) continue;
      final raw = workoutBox.get(key);
      if (raw is! Map) continue;
      final entry = Map<String, dynamic>.from(raw);

      if (entry['status'] != 'completed') continue;

      final date = entry['date'] as String?;
      if (date == null) continue;

      try {
        await _supabase.client.from('workout_schedule_completions').upsert({
          'user_id': userId,
          'scheduled_date': date,
          'day_of_week': entry['day_of_week']?.toString(),
          'workout_name': entry['workout_name'],
          'duration_seconds': entry['duration_seconds'],
          'completed_at':
              entry['completed_at'] ?? DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,scheduled_date');
      } catch (e) {
        debugPrint('[SyncService._syncScheduleCompletions] Failed key=$key: $e');
      }
    }
  }

  Future<void> _syncNutritionLogs(String userId) async {
    final nutritionBox = _hive.nutritionBox;
    for (final key in nutritionBox.keys) {
      if (key is! String || !key.startsWith("nlog_")) continue;
      final raw = nutritionBox.get(key);
      if (raw == null) continue;
      final log = Map<String, dynamic>.from(raw as Map);
      try {
        // Diagnosed 2026-04-18: the parent-table payload used to spread
        // the full Hive map into the upsert, which included the Hive
        // string id (`nlog_<ms>`) AND extra columns (food_id, food_name,
        // quantity_g, total_fiber, source) that don't exist on
        // nutrition_logs. PostgREST 400-rejected every call and the
        // catch below swallowed it. Result: `nutrition_logs` stayed at
        // 0 rows despite dozens of food logs in Hive.
        //
        // Now we explicitly project the schema-matching columns and
        // coerce the id to a deterministic v5 UUID via _deterministicId.
        // NutritionRepository.syncLogToSupabase (the hot-path writer)
        // uses the same namespace so immediate writes + this replay
        // collapse to the same row.
        final logCloudId = _deterministicId(key);
        final parentPayload = <String, dynamic>{
          'id': logCloudId,
          'user_id': userId,
          if (log['date'] != null) 'date': log['date'],
          if (log['meal_type'] != null) 'meal_type': log['meal_type'],
          if (log['total_calories'] != null)
            'total_calories': log['total_calories'],
          if (log['total_protein'] != null)
            'total_protein': log['total_protein'],
          if (log['total_carbs'] != null)
            'total_carbs': log['total_carbs'],
          if (log['total_fat'] != null) 'total_fat': log['total_fat'],
          // Migration 034 (2026-04-24) — fiber was previously dropped from
          // the cloud projection even though Hive wrote it. AI coach's
          // `_getTodayNutrition` now references `fiber_g` so the column
          // must hydrate.
          'total_fiber': log['total_fiber'] ?? 0,
          if (log['created_at'] != null) 'created_at': log['created_at'],
        };
        await _supabase.client.from("nutrition_logs").upsert(
          parentPayload,
          onConflict: "id",
        );

        // Push individual nutrition_log_items. Same schema trap — id,
        // log_id, food_id are uuid columns. The bundled food database
        // uses string IDs like `food_indian_aloo_gobi` which are not
        // valid uuids, so we skip food_id entirely (column is nullable)
        // and use a deterministic v5 UUID for id + the parent's cloud
        // id for log_id.
        final items = log['items'];
        if (items is List) {
          for (int i = 0; i < items.length; i++) {
            final item = items[i] is Map
                ? Map<String, dynamic>.from(items[i] as Map)
                : <String, dynamic>{};
            final itemCloudId = _deterministicId('${key}_item_$i');
            try {
              await _supabase.client.from('nutrition_log_items').upsert({
                'id': itemCloudId,
                'log_id': logCloudId,
                'food_name': item['name'] ?? item['food_name'] ?? '',
                if (item['serving_g'] != null || item['quantity_g'] != null)
                  'quantity_g': item['serving_g'] ?? item['quantity_g'],
                if (item['calories'] != null) 'calories': item['calories'],
                if (item['protein'] != null) 'protein': item['protein'],
                if (item['carbs'] != null) 'carbs': item['carbs'],
                if (item['fat'] != null) 'fat': item['fat'],
              }, onConflict: 'id');
            } catch (itemErr) {
              debugPrint('[SyncService._syncNutritionLogs] item $i: $itemErr');
            }
          }
        }
      } catch (e) {
        debugPrint('[SyncService._syncNutritionLogs] $e');
      }
    }
  }

  /// Immediately pushes Hive weight logs to Supabase. Safe to call
  /// fire-and-forget from anywhere — catches its own errors.
  ///
  /// Added 2026-04-18: the weight-log save path (home_provider.logWeight)
  /// now fires this directly so the cloud `weight_logs` table fills in
  /// seconds instead of waiting for the next weekly full sync.
  Future<void> syncWeightNow() async {
    try {
      final userId = _supabase.currentUser?.id;
      if (userId == null) return;
      await _syncWeightLogs(userId);
    } catch (e) {
      debugPrint('[SyncService.syncWeightNow] $e');
    }
  }

  /// Pushes recent sleep entries to Supabase `sleep_logs`. Fire-and-forget per
  /// CLAUDE.md §15. Handles two Hive storage patterns:
  ///   • Per-day keys  `sleep_log_YYYY-MM-DD`  (standard log path)
  ///   • List key      `sleep_logs`             (conversational AI tool path)
  Future<void> syncSleepNow() async {
    try {
      final userId = _supabase.currentUser?.id;
      if (userId == null) return;
      // Handle per-day keys (standard path) via existing helper
      await _syncSleepLogs(userId);
      // Handle list key written by conversational_log_handler._logSleep
      final healthBox = _hive.healthBox;
      final listRaw = healthBox.get('sleep_logs');
      if (listRaw is! List || listRaw.isEmpty) return;
      for (final item in listRaw) {
        if (item is! Map) continue;
        final log = Map<String, dynamic>.from(item);
        final dateStr = log['date'] as String?;
        if (dateStr == null) continue;
        final hours = (log['duration_hrs'] as num?)?.toDouble() ??
            (log['sleep_hours'] as num?)?.toDouble() ??
            (log['hours'] as num?)?.toDouble();
        if (hours == null) continue;
        final id = log['id'] as String? ?? 'sleep_chat_${log['created_at'] ?? dateStr}';
        try {
          await _supabase.client.from('sleep_logs').upsert({
            'id': _deterministicId('sleep_logs_$dateStr'),
            'user_id': userId,
            'date': dateStr,
            'duration_hrs': hours,
            if (log['quality'] != null) 'quality': log['quality'],
            'created_at': log['created_at'] ?? DateTime.now().toIso8601String(),
          }, onConflict: 'id');
        } catch (e) {
          debugPrint('[SyncService.syncSleepNow] list-item $dateStr: $e');
        }
      }
    } catch (e) {
      debugPrint('[SyncService.syncSleepNow] $e');
    }
  }

  /// Pushes recent body measurements to Supabase `body_measurements`.
  /// Fire-and-forget per CLAUDE.md §15. Delegates to existing `_syncMeasurements`
  /// which reads `measurement_YYYY-MM-DD` keys — the same pattern written by
  /// conversational_log_handler._logMeasurement.
  Future<void> syncMeasurementsNow() async {
    try {
      final userId = _supabase.currentUser?.id;
      if (userId == null) return;
      await _syncMeasurements(userId);
    } catch (e) {
      debugPrint('[SyncService.syncMeasurementsNow] $e');
    }
  }

  Future<void> _syncWeightLogs(String userId) async {
    final healthBox = _hive.healthBox;
    // Writers use per-day keys like 'weight_2026-04-07', NOT a single list key.
    for (final key in healthBox.keys) {
      if (key is! String || !key.startsWith('weight_')) continue;
      final raw = healthBox.get(key);
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['type'] != 'weight_log') continue;
      try {
        await _supabase.client.from('weight_logs').upsert({
          'id': _deterministicId(key),
          'user_id': userId,
          'date': log['date'],
          'weight_kg': log['weight_kg'],
          'notes': log['notes'],
          'created_at': log['created_at'] ?? DateTime.now().toIso8601String(),
        }, onConflict: 'id');
      } catch (e) {
        debugPrint('[SyncService._syncWeightLogs] $key: $e');
      }
    }
  }

  Future<void> _syncMeasurements(String userId) async {
    final healthBox = _hive.healthBox;
    // Writers use per-day keys like 'measurement_2026-04-07'.
    for (final key in healthBox.keys) {
      if (key is! String || !key.startsWith('measurement_')) continue;
      final raw = healthBox.get(key);
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      try {
        await _supabase.client.from('body_measurements').upsert({
          'id': _deterministicId(key),
          'user_id': userId,
          'date': log['date'],
          'chest': log['chest'],
          'waist': log['waist'],
          'hips': log['hips'],
          'arms': log['arms'],
          'notes': log['notes'],
          'created_at': log['created_at'] ?? DateTime.now().toIso8601String(),
        }, onConflict: 'id');
      } catch (e) {
        debugPrint('[SyncService._syncMeasurements] $key: $e');
      }
    }
  }

  Future<void> _syncSleepLogs(String userId) async {
    final healthBox = _hive.healthBox;
    // Writers use per-day keys like 'sleep_log_2026-04-07'.
    for (final key in healthBox.keys) {
      if (key is! String || !key.startsWith('sleep_log_')) continue;
      final raw = healthBox.get(key);
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      try {
        await _supabase.client.from('sleep_logs').upsert({
          'id': _deterministicId(key),
          'user_id': userId,
          'date': log['date'],
          'duration_hrs': log['duration_hrs'],
          'quality': log['quality'],
          'bed_time': log['bed_time'],
          'wake_time': log['wake_time'],
          'notes': log['notes'],
          'created_at': log['created_at'] ?? DateTime.now().toIso8601String(),
        }, onConflict: 'id');
      } catch (e) {
        debugPrint('[SyncService._syncSleepLogs] $key: $e');
      }
    }
  }

  /// F20 · Pushes daily step totals to Supabase `daily_steps`.
  Future<void> _syncStepsLogs(String userId) async {
    final healthBox = _hive.healthBox;
    // Writers use per-day keys like 'step_2026-04-07' with
    // {type:'step_log', date, steps, source}.
    for (final key in healthBox.keys) {
      if (key is! String || !key.startsWith('step_')) continue;
      final raw = healthBox.get(key);
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      if (log['type'] != 'step_log') continue;
      final date = log['date'] as String?;
      final steps = (log['steps'] as num?)?.toInt();
      if (date == null || steps == null) continue;
      try {
        await _supabase.client.from('daily_steps').upsert({
          'user_id': userId,
          'date': date,
          'steps': steps,
          'source': log['source'] ?? 'health_connect',
          'synced_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,date');
      } catch (e) {
        debugPrint('[SyncService._syncStepsLogs] $key: $e');
      }
    }
  }

  Future<void> _syncUrineColorLogs(String userId) async {
    // Urine color data is now merged into the water_logs table
    // (health_metrics table does not exist).
    final healthBox = _hive.healthBox;
    for (final key in healthBox.keys) {
      if (key is! String || !key.startsWith('urine_color_')) continue;
      final raw = healthBox.get(key);
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      final date = log['date'] as String?;
      if (date == null) continue;
      try {
        await _supabase.client.from('water_logs').upsert({
          'user_id': userId,
          'date': date,
          'urine_color': (log['index'] as int?) ?? -1,
          'urine_status': log['label'] ?? 'unknown',
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,date');
      } catch (e) {
        debugPrint('[SyncService._syncUrineColorLogs] $e');
      }
    }
  }

  Future<void> _syncWaterLogs(String userId) async {
    final healthBox = _hive.healthBox;
    for (final key in healthBox.keys) {
      if (key is! String || !key.startsWith('water_ml_')) continue;
      final raw = healthBox.get(key);
      if (raw is! int) continue;
      // Extract date from key: "water_ml_2026-04-06" → "2026-04-06"
      final date = key.substring('water_ml_'.length);
      if (date.isEmpty) continue;
      try {
        await _supabase.client.from('water_logs').upsert({
          'user_id': userId,
          'date': date,
          'total_ml': raw,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,date');
      } catch (e) {
        debugPrint('[SyncService._syncWaterLogs] $e');
      }
    }
  }

  Future<void> _syncStreaks(String userId) async {
    final healthBox = _hive.healthBox;
    final logs = healthBox.get('streaks');
    if (logs == null) return;

    final items = (logs as List).whereType<Map>();
    for (final log in items) {
      final data = Map<String, dynamic>.from(log);
      final weekStart = data['week_start']?.toString() ?? '';
      // Remove local-only fields before sending to Supabase.
      data.remove('local_id');
      try {
        await _supabase.client.from('streaks').upsert({
          'id': _deterministicId('streak_${userId}_$weekStart'),
          ...data,
          'user_id': userId,
        }, onConflict: 'user_id,week_start');
      } catch (e) {
        debugPrint('[SyncService._syncStreaks] $e');
      }
    }
  }

  /// Immediately pushes the local Hive profile to Supabase user_profile.
  /// Safe to call from anywhere — only sends columns that exist in the schema.
  ///
  /// Wraps `_syncUserProfile` in a catch so fire-and-forget callers (e.g.
  /// `edit_profile_screen._save` line ~1615) can't leave the UI blind to a
  /// silent upsert failure. On exception, logs locally AND posts a
  /// `client_errors` telemetry row via the `log-client-error` Edge Function
  /// — this is what the old silent path was missing when all 24 onboarding
  /// fields stayed NULL on fresh signups.
  Future<void> syncProfileNow(String userId) async {
    try {
      await _syncUserProfile(userId);
    } catch (e, st) {
      debugPrint('[SyncService.syncProfileNow] user_profile upsert failed: '
          '$e\n$st');
      unawaited(_reportSyncFailure(
        opType: 'upsert_user_profile',
        error: e,
      ));
    }
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
    } catch (e) {
      debugPrint('[sync/restore] $label failed: $e');
      try {
        await _reportSyncFailure(opType: 'restore_$label', error: e);
      } catch (_) {}
    }
  }

  /// Fire-and-forget telemetry for a sync failure. Sends one row to
  /// `client_errors` via the `log-client-error` Edge Function so we stop
  /// being blind to payload-rejection failures in prod.
  Future<void> _reportSyncFailure({
    required String opType,
    required Object error,
    int retryCount = 0,
  }) async {
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
      // Telemetry must never throw — swallow everything. Local debugPrint
      // above has already left a breadcrumb for dev builds.
    }
  }

  /// Immediately pushes user_progress to Supabase (total_workouts_done, streaks, etc.).
  /// Called fire-and-forget after every workout completion.
  Future<void> syncProgressNow() async {
    try {
      final userId = _supabase.currentUser?.id;
      if (userId == null) return;
      await _syncUserProgress(userId);
    } catch (e) {
      debugPrint('[SyncService.syncProgressNow] $e');
    }
  }

  Future<void> _syncUserProfile(String userId) async {
    final userBox = _hive.userBox;
    final profile = userBox.get('profile');
    if (profile == null) return;

    final p = Map<String, dynamic>.from(profile as Map);

    // Build a payload that is safe for Postgres to accept.
    //
    // Historical bug (diagnosed 2026-04-17): this payload was blind to two
    // common Hive states that PostgREST rejects outright — causing the whole
    // upsert to 400 and the caller's fire-and-forget Future to swallow the
    // error. Result: user_profile stayed all-NULL for brand-new accounts
    // even though onboarding + Edit Profile "succeeded" from the UI's POV.
    //
    // The two offenders:
    //   1. Empty string in strict-typed columns (date, time, numeric,
    //      integer, timestamptz). e.g. `date_of_birth = ""` →
    //      "invalid input syntax for type date". Existing null-guard didn't
    //      filter empty strings written by onboarding when the user skipped
    //      DOB / wake-up-time.
    //   2. Dart `double` values landing in Postgres `integer` columns
    //      (daily_calories / protein_grams / carbs_grams / fat_grams /
    //      water_target_ml). These are normally int (NutritionTargets uses
    //      int fields), but stale Hive rows written before migration 021
    //      could hold doubles, and any future refactor on the compute side
    //      could reintroduce the mismatch silently.
    //
    // Fix: blank filter for strict columns + explicit .round() on integers.
    final payload = <String, dynamic>{
      'user_id': userId,
      if (_hasValue(p['date_of_birth'])) 'date_of_birth': p['date_of_birth'],
      if (_hasValue(p['gender'])) 'gender': p['gender'],
      if (_hasNumber(p['height_cm'])) 'height_cm': p['height_cm'],
      if (_hasNumber(p['current_weight_kg'])) 'current_weight_kg': p['current_weight_kg'],
      if (_hasNumber(p['target_weight_kg'])) 'target_weight_kg': p['target_weight_kg'],
      if (_hasValue(p['primary_goal'])) 'primary_goal': p['primary_goal'],
      if (_hasValue(p['fitness_experience'])) 'fitness_experience': p['fitness_experience'],
      if (_hasNumber(p['days_per_week'])) 'days_per_week': (p['days_per_week'] as num).round(),
      if (_hasValue(p['equipment_access'])) 'equipment_access': p['equipment_access'],
      if (_hasValue(p['activity_level'])) 'activity_level': p['activity_level'],
      if (_hasValue(p['lifestyle_activity'])) 'lifestyle_activity': p['lifestyle_activity'],
      if (_hasValue(p['pace_preference'])) 'pace_preference': p['pace_preference'],
      if (_hasValue(p['diet_preference'])) 'diet_preference': p['diet_preference'],
      if (_hasValue(p['injuries'])) 'injuries': p['injuries'].toString(),
      if (_hasValue(p['city'])) 'city': p['city'],
      if (_hasNumber(p['bmr'])) 'bmr': (p['bmr'] as num).round(),
      if (_hasNumber(p['tdee'])) 'tdee': (p['tdee'] as num).round(),
      if (_hasNumber(p['body_fat_percent'])) 'body_fat_percent': p['body_fat_percent'],
      if (_hasValue(p['body_fat_assessed_at'])) 'body_fat_assessed_at': p['body_fat_assessed_at'],
      if (_hasNumber(p['session_duration_minutes']))
        'session_duration_minutes': (p['session_duration_minutes'] as num).round(),
      if (_hasValue(p['physique_focus'])) 'physique_focus': p['physique_focus'],
      if (_hasValue(p['avatar_url'])) 'avatar_url': p['avatar_url'],
      if (_hasValue(p['banner_url'])) 'banner_url': p['banner_url'],
      if (_hasValue(p['wake_up_time'])) 'wake_up_time': p['wake_up_time'],
      // F17 · Computed nutrition targets (integer columns added migration 021).
      // Coerce to int — NutritionTargets uses ints today but defensively round
      // in case a caller ever stores a double here.
      if (_hasNumber(p['daily_calories']))
        'daily_calories': (p['daily_calories'] as num).round(),
      if (_hasNumber(p['protein_grams']))
        'protein_grams': (p['protein_grams'] as num).round(),
      if (_hasNumber(p['carbs_grams']))
        'carbs_grams': (p['carbs_grams'] as num).round(),
      if (_hasNumber(p['fat_grams']))
        'fat_grams': (p['fat_grams'] as num).round(),
      if (_hasNumber(p['water_target_ml']))
        'water_target_ml': (p['water_target_ml'] as num).round(),
    };

    if (_syncReliabilityEnabled) {
      // Route through the queue: on failure the op is persisted to Hive
      // and retried with exponential backoff instead of disappearing.
      final result = await _executeUserProfileUpsert(payload);
      if (result.isErr) {
        final err = (result as Err<void, SyncError>).error;
        debugPrint('[SyncService._syncUserProfile] enqueue after ${err.code}: '
            '${err.message}');
        await SyncQueue.instance.enqueue(
          opType: 'upsert_user_profile',
          payload: payload,
          initialError: err,
        );
      }
      return;
    }

    // Legacy path — preserves existing behavior when flag is off.
    // Failures bubble up uncaught (caller's try/catch → debugPrint).
    await _supabase.client
        .from('user_profile')
        .upsert(payload, onConflict: 'user_id')
        .select()
        .single();
  }

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

  /// Public wrapper so immediate-save call sites (the create-custom-exercise
  /// sheet, the create-custom-food sheet) can push to Supabase without
  /// waiting for the next weekly sync. Catches its own errors.
  Future<void> syncCustomItemsNow() => _syncCustomItems();

  /// Upserts coach_memory induction columns to Supabase.
  /// Only non-null Hive fields are included — preserves partial induction
  /// state without overwriting cloud columns with null when the user hasn't
  /// yet completed the muster. Uses migration 042 columns.
  /// Fire-and-forget per CLAUDE.md §15.
  Future<void> syncCoachMemoryNow(String userId) async {
    try {
      final coach = _hive.coachBox;
      final payload = <String, dynamic>{
        'user_id': userId,
      };
      // Helper: only include when non-null — preserves partial induction state.
      void putIfPresent(String key) {
        final v = coach.get(key);
        if (v != null) payload[key] = v;
      }
      putIfPresent('committed_at');
      final ltcdr = coach.get('committed_to_lt_cdr');
      if (ltcdr is bool) payload['committed_to_lt_cdr'] = ltcdr;
      putIfPresent('induction_completed_at');
      putIfPresent('why_now');
      putIfPresent('definition_of_winning');
      putIfPresent('known_injuries');
      putIfPresent('typical_wake_time');
      putIfPresent('preferred_workout_time');
      putIfPresent('body_part_priorities');

      await _supabase.client
          .from('coach_memory')
          .upsert(payload, onConflict: 'user_id')
          .select()
          .single();
    } catch (e, st) {
      debugPrint('[SyncService.syncCoachMemoryNow] coach_memory upsert failed: $e');
      unawaited(_reportSyncFailure(
        opType: 'upsert_coach_memory_induction',
        error: e,
      ));
    }
  }

  /// Pushes user-created custom foods and exercises to Supabase
  /// for community contribution.
  ///
  /// Historical bug fixed 2026-04-18: the writer
  /// (`create_custom_exercise_sheet._save`, line 85) stores each exercise
  /// at its own Hive key `custom_exercise_<ms>`, but this function used to
  /// only look at a list key `customBox.get('custom_exercises')` — a
  /// single aggregate List that nobody ever wrote to. Result: custom
  /// exercises never synced. Observed 2026-04-18 on icanbefitter@gmail.com
  /// after creating "L Sit" — user_custom_exercises stayed at 0 rows.
  ///
  /// New behavior: iterate `customBox.keys` by prefix. Falls back to the
  /// legacy list-key path for any old-shape boxes still in the wild.
  Future<void> _syncCustomItems() async {
    try {
      final userId = _supabase.currentUser?.id;
      if (userId == null) return;

      final customBox = _hive.customBox;

      // ── Primary path: per-key entries ──
      for (final key in customBox.keys) {
        if (key is! String) continue;
        final raw = customBox.get(key);
        if (raw is! Map) continue;

        if (key.startsWith('custom_exercise_')) {
          final payload = _projectCustomExercise(raw, userId);
          if (kDebugMode) {
            debugPrint(
              '[SyncService] upsert user_custom_exercises '
              'name=${payload['name']} user=$userId id=${payload['id']}',
            );
          }
          try {
            await _supabase.client
                .from('user_custom_exercises')
                .upsert(payload, onConflict: 'id');
          } catch (e) {
            debugPrint(
              '[SyncService._syncCustomItems] exercise '
              '"${payload['name']}" key=$key: $e',
            );
          }
        } else if (key.startsWith('custom_food_')) {
          final payload = _projectCustomFood(raw, userId);
          if (kDebugMode) {
            debugPrint(
              '[SyncService] upsert user_custom_foods '
              'name=${payload['name']} user=$userId id=${payload['id']}',
            );
          }
          try {
            await _supabase.client
                .from('user_custom_foods')
                .upsert(payload, onConflict: 'id');
          } catch (e) {
            debugPrint(
              '[SyncService._syncCustomItems] food '
              '"${payload['name']}" key=$key: $e',
            );
          }
        }
      }

      // ── Legacy path: aggregate list keys ──
      // Kept for back-compat with devices that still have the old shape
      // (never-shipped but safe guard).
      final legacyExercises = customBox.get('custom_exercises');
      if (legacyExercises is List) {
        for (final item in legacyExercises.cast<Map>()) {
          try {
            await _supabase.client
                .from('user_custom_exercises')
                .upsert(_projectCustomExercise(item, userId), onConflict: 'id');
          } catch (e) {
            debugPrint('[SyncService._syncCustomItems] legacy exercise: $e');
          }
        }
      }
      final legacyFoods = customBox.get('custom_foods');
      if (legacyFoods is List) {
        for (final item in legacyFoods.cast<Map>()) {
          try {
            await _supabase.client
                .from('user_custom_foods')
                .upsert(_projectCustomFood(item, userId), onConflict: 'id');
          } catch (e) {
            debugPrint('[SyncService._syncCustomItems] legacy food: $e');
          }
        }
      }

      await _setTimestamp(_lastCustomSyncKey);
    } catch (e) {
      debugPrint('[SyncService._syncCustomItems] $e');
    }
  }

  /// Projects a Hive custom-exercise map to ONLY the columns that exist
  /// on the `user_custom_exercises` Supabase table. The Hive map carries
  /// extras (`is_custom`, `type`) that PostgREST 400-rejects; before
  /// 2026-04-18 the sync spread them verbatim into the upsert and every
  /// call silently failed, which is why user_custom_exercises stayed at
  /// 0 rows even after the list-vs-per-key wiring fix.
  ///
  /// Schema reminder (DB truth, verified via information_schema):
  ///   id uuid NOT NULL, user_id uuid NOT NULL, name text NOT NULL,
  ///   logging_type text NOT NULL, category text, primary_muscles
  ///   text[], equipment_needed text[], notes text, default_sets int,
  ///   default_reps text, default_rest_secs int, default_duration_secs
  ///   int, submitted_to_library bool, approved_for_library bool,
  ///   times_used int, created_at timestamptz.
  Map<String, dynamic> _projectCustomExercise(
    Map source,
    String userId,
  ) {
    final src = Map<String, dynamic>.from(source);
    final defaultDur = src['default_duration_seconds'] ?? src['default_duration_secs'];
    return <String, dynamic>{
      'id': src['id'],
      'user_id': userId,
      if (src['name'] != null) 'name': src['name'],
      if (src['logging_type'] != null) 'logging_type': src['logging_type'],
      if (src['category'] != null) 'category': src['category'],
      if (src['primary_muscles'] is List)
        'primary_muscles': (src['primary_muscles'] as List).cast<String>(),
      if (src['equipment_needed'] is List)
        'equipment_needed': (src['equipment_needed'] as List).cast<String>(),
      if (src['notes'] != null) 'notes': src['notes'],
      if (src['default_sets'] != null) 'default_sets': src['default_sets'],
      if (src['default_reps'] != null)
        'default_reps': src['default_reps'].toString(),
      if (src['default_rest_secs'] != null)
        'default_rest_secs': src['default_rest_secs'],
      if (defaultDur != null) 'default_duration_secs': defaultDur,
      if (src['submitted_to_library'] != null)
        'submitted_to_library': src['submitted_to_library'],
      if (src['approved_for_library'] != null)
        'approved_for_library': src['approved_for_library'],
      if (src['times_used'] != null) 'times_used': src['times_used'],
      if (src['created_at'] != null) 'created_at': src['created_at'],
    };
  }

  /// Projects a Hive custom-food map to the `user_custom_foods` schema:
  ///   id uuid NOT NULL, user_id uuid NOT NULL, name text NOT NULL,
  ///   calories_per_100g numeric, protein_per_100g numeric,
  ///   carbs_per_100g numeric, fat_per_100g numeric, fiber_per_100g
  ///   numeric, standard_serving_desc text, standard_serving_g numeric,
  ///   calories_std numeric, protein_std numeric, carbs_std numeric,
  ///   fat_std numeric, times_logged int, submitted_to_db bool,
  ///   approved bool, created_at timestamptz.
  Map<String, dynamic> _projectCustomFood(
    Map source,
    String userId,
  ) {
    final src = Map<String, dynamic>.from(source);
    return <String, dynamic>{
      'id': src['id'],
      'user_id': userId,
      if (src['name'] != null) 'name': src['name'],
      if (src['calories_per_100g'] != null)
        'calories_per_100g': src['calories_per_100g'],
      if (src['protein_per_100g'] != null)
        'protein_per_100g': src['protein_per_100g'],
      if (src['carbs_per_100g'] != null)
        'carbs_per_100g': src['carbs_per_100g'],
      if (src['fat_per_100g'] != null) 'fat_per_100g': src['fat_per_100g'],
      if (src['fiber_per_100g'] != null)
        'fiber_per_100g': src['fiber_per_100g'],
      if (src['standard_serving_desc'] != null)
        'standard_serving_desc': src['standard_serving_desc'],
      if (src['standard_serving_g'] != null)
        'standard_serving_g': src['standard_serving_g'],
      if (src['calories_std'] != null) 'calories_std': src['calories_std'],
      if (src['protein_std'] != null) 'protein_std': src['protein_std'],
      if (src['carbs_std'] != null) 'carbs_std': src['carbs_std'],
      if (src['fat_std'] != null) 'fat_std': src['fat_std'],
      if (src['times_logged'] != null) 'times_logged': src['times_logged'],
      if (src['submitted_to_db'] != null)
        'submitted_to_db': src['submitted_to_db'],
      if (src['approved'] != null) 'approved': src['approved'],
      if (src['created_at'] != null) 'created_at': src['created_at'],
    };
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

  Future<void> _restoreWorkoutLogs(String userId, String since) async {
    try {
      final rows = await _fetchAllRows(
        'workout_logs', userId,
        dateColumn: 'created_at', since: since, orderBy: 'created_at',
      );

      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final loggedAt = map['logged_at'] as String? ?? '';
        final ts = DateTime.tryParse(loggedAt)?.millisecondsSinceEpoch ??
            DateTime.now().millisecondsSinceEpoch;
        final logId = 'wlog_$ts';

        // Skip if already exists
        if (_hive.workoutBox.get(logId) != null) continue;

        await _hive.workoutBox.put(logId, {
          'id': logId,
          'type': 'workout_log',
          'workout_name': map['exercise_name'] ?? 'Workout',
          'date': map['date'],
          'completed_at': loggedAt,
          'sets_completed': map['sets_completed'],
          'duration_seconds': map['duration_seconds'],
        });
      }
    } catch (e) {
      debugPrint('[SyncService._restoreWorkoutLogs] $e');
    }
  }

  Future<void> _restoreExerciseLogs(String userId, String since) async {
    try {
      final rows = await _fetchAllRows(
        'workout_log_exercises', userId,
        dateColumn: 'completed_at', since: since, orderBy: 'completed_at',
      );

      // F4 · Pre-fetch all per-set rows once and index by
      // (workout_log_id, exercise_id) so we can reconstruct the Hive
      // `sets_detail` list without a per-exercise round-trip.
      final setsByLogExercise = <String, List<Map<String, dynamic>>>{};
      try {
        final setRows = await _fetchAllRows(
          'workout_log_sets', userId,
          dateColumn: 'completed_at', since: since, orderBy: 'completed_at',
        );
        for (final raw in setRows) {
          final m = Map<String, dynamic>.from(raw as Map);
          final wlId = m['workout_log_id'] as String? ?? '';
          final exId = m['exercise_id'] as String? ?? '';
          final groupKey = '$wlId|$exId';
          setsByLogExercise
              .putIfAbsent(groupKey, () => <Map<String, dynamic>>[])
              .add(m);
        }
      } catch (e) {
        // Non-fatal — falls back to summary-only restore.
        debugPrint('[SyncService._restoreExerciseLogs] per-set fetch failed: $e');
      }

      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final completedAt = map['completed_at'] as String? ?? '';
        final name = map['exercise_name'] as String? ?? '';
        final ts = DateTime.tryParse(completedAt)?.millisecondsSinceEpoch ??
            DateTime.now().millisecondsSinceEpoch;
        final logId = 'exlog_${ts}_${name.hashCode}';

        if (_hive.workoutBox.get(logId) != null) continue;

        final dateStr = completedAt.length >= 10
            ? completedAt.substring(0, 10)
            : DateTime.now().toIso8601String().substring(0, 10);

        final logMap = <String, dynamic>{
          'id': logId,
          'type': 'exercise_log',
          'exercise_name': name,
          'date': dateStr,
          'logging_type': map['logging_type'] ?? 'weight_reps',
          'is_pr': map['is_pr'] ?? false,
          'has_warmup_sets': map['has_warmup_sets'] ?? false,
          'created_at': completedAt,
        };

        if (map['weight_kg'] != null) {
          logMap['weight_kg'] = (map['weight_kg'] as num).toDouble();
        }
        if (map['reps'] != null) logMap['reps_completed'] = map['reps'];
        if (map['set_number'] != null) {
          logMap['sets_completed'] = map['set_number'];
        }
        if (map['duration_seconds'] != null) {
          logMap['duration_seconds'] = map['duration_seconds'];
        }
        if (map['distance_km'] != null) {
          logMap['distance_km'] = (map['distance_km'] as num).toDouble();
        }

        // F4 · Reconstruct `sets_detail` from the workout_log_sets join.
        final workoutLogId = map['workout_log_id'] as String? ?? '';
        final exerciseId = map['exercise_id'] as String? ?? name;
        final groupKey = '$workoutLogId|$exerciseId';
        final setsForThisExercise = setsByLogExercise[groupKey];
        if (setsForThisExercise != null && setsForThisExercise.isNotEmpty) {
          setsForThisExercise.sort((a, b) =>
              ((a['set_number'] as num?)?.toInt() ?? 0)
                  .compareTo(((b['set_number'] as num?)?.toInt() ?? 0)));
          final setsDetail = setsForThisExercise.map((s) {
            final out = <String, dynamic>{
              'set_number': (s['set_number'] as num?)?.toInt() ?? 0,
            };
            if (s['weight_kg'] != null) {
              out['weight_kg'] = (s['weight_kg'] as num).toDouble();
            }
            if (s['reps'] != null) {
              out['reps'] = (s['reps'] as num).toInt();
            }
            if (s['duration_secs'] != null) {
              out['duration_seconds'] = (s['duration_secs'] as num).toInt();
            }
            if (s['distance_km'] != null) {
              out['distance_km'] = (s['distance_km'] as num).toDouble();
            }
            return out;
          }).toList();
          logMap['sets_detail'] = setsDetail;

          // Recompute exact per-set volume from the detail list (the
          // summary row's weight_kg × reps was a lossy max×cumulative).
          double volume = 0;
          for (final s in setsDetail) {
            final w = (s['weight_kg'] as num?)?.toDouble() ?? 0;
            final r = (s['reps'] as num?)?.toInt() ?? 0;
            volume += w * r;
          }
          logMap['volume_kg'] = volume;
        }

        await _hive.workoutBox.put(logId, logMap);

        // Rebuild date index
        final indexKey = 'exercise_log_index_$dateStr';
        final existingIndex = _hive.workoutBox.get(indexKey);
        final indexList = existingIndex is List
            ? List<String>.from(existingIndex)
            : <String>[];
        if (!indexList.contains(logId)) {
          indexList.add(logId);
          await _hive.workoutBox.put(indexKey, indexList);
        }
      }
    } catch (e) {
      debugPrint('[SyncService._restoreExerciseLogs] $e');
    }
  }

  Future<void> _restoreScheduleCompletions(
      String userId, String since) async {
    try {
      final rows = await _supabase.client
          .from('workout_schedule_completions')
          .select()
          .eq('user_id', userId)
          .gte('completed_at', since)
          .order('scheduled_date');

      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final date = map['scheduled_date'] as String? ?? '';
        final key = 'schedule_$date';

        final existing = _hive.workoutBox.get(key);
        if (existing is Map) {
          // Update existing schedule entry to completed status
          final entry = Map<String, dynamic>.from(existing);
          if (entry['status'] != 'completed') {
            entry['status'] = 'completed';
            entry['completed_at'] = map['completed_at'];
            entry['duration_seconds'] = map['duration_seconds'];
            await _hive.workoutBox.put(key, entry);
          }
        }
        // If no schedule entry exists, the plan hasn't been generated yet
        // on this device — schedule completions alone aren't useful without
        // the full plan context. Skip silently.
      }
    } catch (e) {
      debugPrint('[SyncService._restoreScheduleCompletions] $e');
    }
  }

  Future<void> _restoreCustomExercises(String userId) async {
    try {
      final rows = await _supabase.client
          .from('user_custom_exercises')
          .select()
          .eq('user_id', userId);

      if (rows.isEmpty) return;

      final items = rows
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();

      // Merge with existing custom exercises
      final existing = _hive.customBox.get('custom_exercises');
      final existingList = existing is List
          ? (existing).cast<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
          : <Map<String, dynamic>>[];

      final existingNames =
          existingList.map((e) => (e['name'] as String? ?? '').toLowerCase()).toSet();

      for (final item in items) {
        final name = (item['name'] as String? ?? '').toLowerCase();
        if (!existingNames.contains(name)) {
          existingList.add(item);
          existingNames.add(name);
        }
      }

      await _hive.customBox.put('custom_exercises', existingList);
    } catch (e) {
      debugPrint('[SyncService._restoreCustomExercises] $e');
    }
  }

  Future<void> _restoreCustomFoods(String userId) async {
    try {
      final rows = await _supabase.client
          .from('user_custom_foods')
          .select()
          .eq('user_id', userId);

      if (rows.isEmpty) return;

      final items = rows
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();

      final existing = _hive.customBox.get('custom_foods');
      final existingList = existing is List
          ? (existing).cast<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
          : <Map<String, dynamic>>[];

      final existingNames =
          existingList.map((e) => (e['name'] as String? ?? '').toLowerCase()).toSet();

      for (final item in items) {
        final name = (item['name'] as String? ?? '').toLowerCase();
        if (!existingNames.contains(name)) {
          existingList.add(item);
          existingNames.add(name);
        }
      }

      await _hive.customBox.put('custom_foods', existingList);
    } catch (e) {
      debugPrint('[SyncService._restoreCustomFoods] $e');
    }
  }

  Future<void> _restoreWeightLogs(String userId, String since) async {
    try {
      final rows = await _fetchAllRows(
        'weight_logs', userId,
        dateColumn: 'created_at', since: since, orderBy: 'created_at',
      );

      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final date = map['date'] as String? ?? '';
        final key = 'weight_$date';
        if (_hive.healthBox.get(key) != null) continue;
        await _hive.healthBox.put(key, {
          'type': 'weight_log',
          'date': date,
          'weight_kg': map['weight_kg'],
          'created_at': map['created_at'],
          'source': 'cloud_restore',
        });
      }
    } catch (e) {
      debugPrint('[SyncService._restoreWeightLogs] $e');
    }
  }

  Future<void> _restoreNutritionLogs(String userId, String since) async {
    try {
      // Join with nutrition_log_items to restore individual food items.
      // Paginated fetch (1000 per page, max 50,000).
      final rows = <Map<String, dynamic>>[];
      int offset = 0;
      const pageSize = 1000;
      while (true) {
        final page = await _supabase.client
            .from('nutrition_logs')
            .select('*, nutrition_log_items(*)')
            .eq('user_id', userId)
            .gte('created_at', since)
            .order('created_at')
            .range(offset, offset + pageSize - 1);
        for (final r in page) {
          rows.add(Map<String, dynamic>.from(r as Map));
        }
        if (page.length < pageSize || rows.length >= 50000) break;
        offset += pageSize;
      }

      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final id = map['id'] as String? ?? '';
        if (_hive.nutritionBox.get(id) != null) continue;

        // Extract items from joined nutrition_log_items
        final itemRows = map['nutrition_log_items'] as List? ?? [];
        if (itemRows.isNotEmpty) {
          final items = itemRows.map((item) {
            final m = Map<String, dynamic>.from(item as Map);
            return {
              'food_id': m['food_id'],
              'name': m['food_name'],
              'food_name': m['food_name'],
              'quantity_g': m['quantity_g'],
              'serving_g': m['quantity_g'],
              'calories': m['calories'],
              'protein': m['protein'],
              'carbs': m['carbs'],
              'fat': m['fat'],
            };
          }).toList();
          map['items'] = items;
        }

        // Remove the nested Supabase join structure
        map.remove('nutrition_log_items');
        map['source'] = 'cloud_restore';

        await _hive.nutritionBox.put(id, map);
      }
    } catch (e) {
      debugPrint('[SyncService._restoreNutritionLogs] $e');
    }
  }

  Future<void> _restoreMeasurements(String userId, String since) async {
    try {
      final rows = await _fetchAllRows(
        'body_measurements', userId,
        dateColumn: 'created_at', since: since, orderBy: 'created_at',
      );

      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final date = map['date'] as String? ?? '';
        final key = 'measurement_$date';
        if (_hive.healthBox.get(key) != null) continue;
        await _hive.healthBox.put(key, {
          ...map,
          'source': 'cloud_restore',
        });
      }
    } catch (e) {
      debugPrint('[SyncService._restoreMeasurements] $e');
    }
  }

  Future<void> _restoreUserProfile(String userId) async {
    try {
      final rows = await _supabase.client
          .from('user_profile')
          .select()
          .eq('user_id', userId)
          .limit(1);

      if (rows.isEmpty) return;
      final cloud = Map<String, dynamic>.from(rows.first as Map);
      cloud.remove('user_id'); // Don't store user_id inside the profile map

      // F2 · Merge semantics — cloud non-null fields overwrite Hive; cloud
      // nulls don't wipe Hive values (preserves local-only edits that
      // haven't synced up yet). Previously gated by
      // `if (_hive.userBox.get('profile') != null) return;` which meant
      // stale Hive never got refreshed on re-login.
      final existing = _hive.userBox.get('profile');
      final existingMap = existing is Map
          ? Map<String, dynamic>.from(existing)
          : <String, dynamic>{};
      final merged = <String, dynamic>{
        ...existingMap,
        for (final e in cloud.entries)
          if (e.value != null) e.key: e.value,
      };
      await _hive.userBox.put('profile', merged);
    } catch (e) {
      debugPrint('[SyncService._restoreUserProfile] $e');
    }
  }

  Future<void> _restoreUserProgress(String userId) async {
    try {
      final rows = await _supabase.client
          .from('user_progress')
          .select()
          .eq('user_id', userId)
          .limit(1);

      if (rows.isEmpty) return;
      final cloud = Map<String, dynamic>.from(rows.first as Map);
      cloud.remove('user_id');

      // F6 · Merge semantics (same as _restoreUserProfile).
      final existing = _hive.userBox.get('progress');
      final existingMap = existing is Map
          ? Map<String, dynamic>.from(existing)
          : <String, dynamic>{};
      final merged = <String, dynamic>{
        ...existingMap,
        for (final e in cloud.entries)
          if (e.value != null) e.key: e.value,
      };
      await _hive.userBox.put('progress', merged);
    } catch (e) {
      debugPrint('[SyncService._restoreUserProgress] $e');
    }
  }

  // ── Restore: Water, Sleep, Streaks ──────────────────────────

  Future<void> _restoreWaterLogs(String userId, String since) async {
    try {
      final rows = await _fetchAllRows(
        'water_logs', userId,
        dateColumn: 'date', since: since.substring(0, 10), orderBy: 'date',
      );

      final healthBox = _hive.healthBox;
      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final date = map['date'] as String? ?? '';
        if (date.isEmpty) continue;
        final key = 'water_ml_$date';
        final totalMl = map['total_ml'] as int?;
        if (totalMl != null && totalMl > 0) {
          // Only restore if local doesn't already have data for this date
          final existing = healthBox.get(key);
          if (existing == null || existing == 0) {
            await healthBox.put(key, totalMl);
          }
        }
        // Restore urine color if present
        final urineColor = map['urine_color'] as int?;
        if (urineColor != null && urineColor >= 0) {
          final urineKey = 'urine_color_$date';
          if (healthBox.get(urineKey) == null) {
            await healthBox.put(urineKey, {
              'date': date,
              'index': urineColor,
              'label': map['urine_status'] ?? 'unknown',
              'source': 'cloud_restore',
            });
          }
        }
      }
    } catch (e) {
      debugPrint('[SyncService._restoreWaterLogs] $e');
    }
  }

  Future<void> _restoreSleepLogs(String userId, String since) async {
    try {
      final rows = await _supabase.client
          .from('sleep_logs')
          .select()
          .eq('user_id', userId)
          .gte('created_at', since);

      if (rows.isEmpty) return;

      final healthBox = _hive.healthBox;
      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final date = map['date'] as String?;
        if (date == null) continue;
        final key = 'sleep_log_$date';
        if (healthBox.get(key) != null) continue; // Don't overwrite local data
        await healthBox.put(key, {
          ...map,
          'source': 'cloud_restore',
        });
      }
    } catch (e) {
      debugPrint('[SyncService._restoreSleepLogs] $e');
    }
  }

  /// F20 · Restore daily step totals from Supabase into healthBox.
  Future<void> _restoreStepsLogs(String userId, String since) async {
    try {
      final sinceDate = since.length >= 10 ? since.substring(0, 10) : since;
      final rows = await _fetchAllRows(
        'daily_steps', userId,
        dateColumn: 'date', since: sinceDate, orderBy: 'date',
      );
      if (rows.isEmpty) return;
      final healthBox = _hive.healthBox;
      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final date = map['date'] as String?;
        final steps = (map['steps'] as num?)?.toInt();
        if (date == null || steps == null) continue;
        final key = 'step_$date';
        // Only restore if local doesn't already have a step entry for this
        // date (covers the case where Health Connect will repopulate on
        // device-local sync).
        if (healthBox.get(key) != null) continue;
        await healthBox.put(key, {
          'type': 'step_log',
          'date': date,
          'steps': steps,
          'source': map['source'] ?? 'cloud_restore',
          'created_at': map['created_at'],
        });
      }
    } catch (e) {
      debugPrint('[SyncService._restoreStepsLogs] $e');
    }
  }

  Future<void> _restoreStreaks(String userId) async {
    try {
      final rows = await _supabase.client
          .from('streaks')
          .select()
          .eq('user_id', userId)
          .order('week_start', ascending: false)
          .limit(52);

      if (rows.isEmpty) return;

      final healthBox = _hive.healthBox;
      final existingRaw = healthBox.get('streaks');
      final existing = existingRaw is List ? List<Map>.from(existingRaw) : <Map>[];

      // Deduplicate by week_start (not cloud id) to prevent same-week duplicates.
      // Cloud data is authoritative — replace local row if conflict found.
      final existingWeekStarts = <String, int>{};
      for (int i = 0; i < existing.length; i++) {
        final ws = existing[i]['week_start']?.toString() ?? '';
        if (ws.isNotEmpty) existingWeekStarts[ws] = i;
      }

      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final weekStart = map['week_start']?.toString() ?? '';
        if (weekStart.isEmpty) continue;

        final restoredRow = <String, dynamic>{
          ...map,
          'local_id': 'streak_$weekStart',
          'source': 'cloud_restore',
        };

        if (existingWeekStarts.containsKey(weekStart)) {
          // Replace local row with cloud data (cloud is authoritative)
          existing[existingWeekStarts[weekStart]!] = restoredRow;
        } else {
          existingWeekStarts[weekStart] = existing.length;
          existing.add(restoredRow);
        }
      }

      await healthBox.put('streaks', existing);
    } catch (e) {
      debugPrint('[SyncService._restoreStreaks] $e');
    }
  }

  // ── Sync: Workout Plan + User Progress ─────────────────────

  /// Pushes the current workout plan (plan JSON + schedule entries + dates)
  /// to Supabase user_progress.plan_json so it can be restored on new device.
  Future<void> _syncWorkoutPlan(String userId) async {
    try {
      final workoutBox = _hive.workoutBox;
      final configBox = _hive.configBox;

      final plan = workoutBox.get('current_plan');
      if (plan == null) return;

      final planStart = configBox.get('plan_start_date');
      final planEnd = configBox.get('plan_end_date');

      // Collect schedule entries (schedule_YYYY-MM-DD)
      final schedules = <String, dynamic>{};
      for (final key in workoutBox.keys) {
        if (key is String && key.startsWith('schedule_')) {
          final val = workoutBox.get(key);
          if (val != null) {
            schedules[key] = val is Map ? Map<String, dynamic>.from(val) : val;
          }
        }
      }

      final planBundle = {
        'plan': plan is Map ? Map<String, dynamic>.from(plan) : plan,
        'plan_start_date': planStart,
        'plan_end_date': planEnd,
        'schedules': schedules,
        'synced_at': DateTime.now().toIso8601String(),
      };

      await _supabase.client.from('user_progress').upsert({
        'user_id': userId,
        'plan_json': planBundle,
      }, onConflict: 'user_id');
    } catch (e) {
      debugPrint('[SyncService._syncWorkoutPlan] $e');
    }
  }

  /// Pushes local user progress (phase, week, streaks, etc.) to Supabase.
  Future<void> _syncUserProgress(String userId) async {
    try {
      final progress = _hive.userBox.get('progress');
      if (progress == null) return;

      final p = Map<String, dynamic>.from(progress as Map);

      await _supabase.client.from('user_progress').upsert({
        'user_id': userId,
        if (p['current_phase'] != null) 'current_phase': p['current_phase'],
        if (p['current_week'] != null) 'current_week': p['current_week'],
        if (p['phase_started_at'] != null) 'phase_started_at': p['phase_started_at'],
        if (p['plan_generated_at'] != null) 'plan_generated_at': p['plan_generated_at'],
        if (p['total_workouts_done'] != null) 'total_workouts_done': p['total_workouts_done'],
        if (p['current_streak_weeks'] != null) 'current_streak_weeks': p['current_streak_weeks'],
        // F21 · detected_experience_level — seeded from onboarding answer,
        // may be overwritten by AI detection.
        if (p['detected_experience_level'] != null)
          'detected_experience_level': p['detected_experience_level'],
      }, onConflict: 'user_id');
    } catch (e) {
      debugPrint('[SyncService._syncUserProgress] $e');
    }
  }

  /// Restores workout plan from Supabase plan_json on new device.
  Future<void> _restoreWorkoutPlan(String userId) async {
    try {
      // Only restore if local plan is missing
      if (_hive.workoutBox.get('current_plan') != null) return;

      final rows = await _supabase.client
          .from('user_progress')
          .select('plan_json')
          .eq('user_id', userId)
          .limit(1);

      if (rows.isEmpty) return;
      final planJson = rows.first['plan_json'];
      if (planJson == null) return;

      final bundle = Map<String, dynamic>.from(planJson as Map);
      final plan = bundle['plan'];
      final planStart = bundle['plan_start_date'];
      final planEnd = bundle['plan_end_date'];
      final schedules = bundle['schedules'];

      if (plan != null) {
        await _hive.workoutBox.put('current_plan', plan is Map ? Map<String, dynamic>.from(plan) : plan);
      }
      if (planStart != null) {
        await _hive.configBox.put('plan_start_date', planStart);
      }
      if (planEnd != null) {
        await _hive.configBox.put('plan_end_date', planEnd);
      }
      if (schedules != null && schedules is Map) {
        for (final entry in schedules.entries) {
          final key = entry.key.toString();
          if (key.startsWith('schedule_')) {
            await _hive.workoutBox.put(key, entry.value is Map ? Map<String, dynamic>.from(entry.value as Map) : entry.value);
          }
        }
      }
    } catch (e) {
      debugPrint('[SyncService._restoreWorkoutPlan] $e');
    }
  }

  // ── Sync: Community Items (approved by 10+ users) ─────────

  /// Pulls approved community foods/exercises from Supabase into local Hive.
  /// Called on app launch to keep the local database growing.
  Future<void> syncCommunityItems() async {
    try {
      final lastSync = _hive.syncBox.get('last_community_sync');
      final sinceDate = lastSync != null
          ? DateTime.tryParse(lastSync.toString())?.toIso8601String()
          : '2020-01-01T00:00:00Z';

      // Pull approved community foods
      final foods = await _supabase.client
          .from('user_custom_foods')
          .select()
          .eq('approved', true)
          .gte('created_at', sinceDate ?? '2020-01-01T00:00:00Z');

      if (foods.isNotEmpty) {
        final foodBox = _hive.foodBox;
        for (final row in foods) {
          final map = Map<String, dynamic>.from(row as Map);
          final id = map['id']?.toString();
          if (id != null && id.isNotEmpty && foodBox.get(id) == null) {
            map['source'] = 'community';
            foodBox.put(id, map);
          }
        }
      }

      // Pull approved community exercises
      final exercises = await _supabase.client
          .from('user_custom_exercises')
          .select()
          .eq('approved_for_library', true)
          .gte('created_at', sinceDate ?? '2020-01-01T00:00:00Z');

      if (exercises.isNotEmpty) {
        final exerciseBox = _hive.exerciseBox;
        for (final row in exercises) {
          final map = Map<String, dynamic>.from(row as Map);
          final id = map['id']?.toString();
          if (id != null && id.isNotEmpty && exerciseBox.get(id) == null) {
            map['source'] = 'community';
            exerciseBox.put(id, map);
          }
        }
      }

      await _hive.syncBox.put('last_community_sync', DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('[SyncService.syncCommunityItems] $e');
    }
  }

  // ── Gap 1+2: Workout Templates + Template Exercises ─────────

  /// Pushes workout templates and their exercises to Supabase.
  Future<void> _syncWorkoutTemplates(String userId) async {
    final workoutBox = _hive.workoutBox;
    for (final key in workoutBox.keys) {
      if (key is! String || !key.startsWith('tmpl_')) continue;
      final raw = workoutBox.get(key);
      if (raw is! Map) continue;
      final tmpl = Map<String, dynamic>.from(raw);
      if (tmpl['type'] != 'template') continue;

      try {
        // Diagnosed 2026-04-18: the Hive template id (`tmpl_<ms>`) is a
        // raw string, but Supabase `workout_templates.id` is uuid NOT
        // NULL. Every upsert used to 400-reject. Same for child rows in
        // `template_exercises` (id + template_id + exercise_id are all
        // uuid columns; the Hive shape stores string ids from the
        // bundled exercise library). Observed: workout_templates stayed
        // at 0 rows despite a successfully saved template.
        //
        // Fix: coerce id + template_id to deterministic v5 UUIDs, and
        // skip exercise_id entirely unless it's already a valid uuid
        // (it's nullable, and the string library ids aren't meaningful
        // cross-device). exercise_name carries the real identity.
        final hiveId = tmpl['id']?.toString() ?? key;
        final cloudTmplId = _deterministicId(hiveId);
        final exercises = tmpl['exercises'] as List? ?? [];

        // Upsert template header
        await _supabase.client.from('workout_templates').upsert({
          'id': cloudTmplId,
          'user_id': userId,
          'name': tmpl['name'] ?? 'Untitled',
          if (tmpl['description'] != null) 'description': tmpl['description'],
          'workout_type': tmpl['workout_focus'] ?? tmpl['workout_type'] ?? 'custom',
          if (tmpl['estimated_duration_mins'] != null)
            'estimated_duration_mins': tmpl['estimated_duration_mins'],
          'source': 'user',
          'is_active': true,
          'created_at':
              tmpl['created_at'] ?? DateTime.now().toIso8601String(),
          if (tmpl['last_used_at'] != null)
            'last_used_at': tmpl['last_used_at'],
        }, onConflict: 'id');

        // Upsert child exercises
        for (int i = 0; i < exercises.length; i++) {
          final ex = exercises[i] is Map
              ? Map<String, dynamic>.from(exercises[i] as Map)
              : <String, dynamic>{};
          final rawExerciseId = ex['exercise_id']?.toString() ?? ex['id']?.toString();
          final isUuid = rawExerciseId != null &&
              RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
                  .hasMatch(rawExerciseId);
          try {
            await _supabase.client.from('template_exercises').upsert({
              'id': _deterministicId('${hiveId}_ex_$i'),
              'template_id': cloudTmplId,
              if (isUuid) 'exercise_id': rawExerciseId,
              'exercise_name': ex['exercise_name'] ?? ex['name'] ?? '',
              'order_index': i,
              'logging_type': ex['logging_type'] ?? 'weight_reps',
              if (ex['sets'] != null)
                'prescribed_sets': ex['sets'] is int
                    ? ex['sets']
                    : int.tryParse(ex['sets'].toString()),
              if (ex['reps'] != null) 'prescribed_reps': ex['reps'].toString(),
              if (ex['weight_kg'] != null || ex['prescribed_weight'] != null)
                'prescribed_weight': (ex['weight_kg'] ??
                        ex['prescribed_weight'])
                    .toString(),
              if (ex['time_secs'] != null || ex['prescribed_time_secs'] != null)
                'prescribed_time_secs':
                    ex['time_secs'] ?? ex['prescribed_time_secs'],
              if (ex['rest_seconds'] != null || ex['rest_secs'] != null)
                'rest_seconds': ex['rest_seconds'] ?? ex['rest_secs'],
              if (ex['notes'] != null) 'notes': ex['notes'],
            }, onConflict: 'id');
          } catch (exErr) {
            debugPrint('[SyncService._syncWorkoutTemplates] exercise $i: $exErr');
          }
        }
      } catch (e) {
        debugPrint('[SyncService._syncWorkoutTemplates] $e');
      }
    }
  }

  /// Restores workout templates (with exercises) from Supabase.
  Future<void> _restoreWorkoutTemplates(String userId) async {
    try {
      final rows = await _supabase.client
          .from('workout_templates')
          .select('*, template_exercises(*)')
          .eq('user_id', userId)
          .eq('is_active', true)
          .limit(500);

      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final id = map['id'] as String? ?? '';
        if (id.isEmpty) continue;
        final hiveKey = id.startsWith('tmpl_') ? id : 'tmpl_${id.hashCode}';
        // F6 · Always refresh template content from cloud — covers the case
        // where the user edited a template on another device. Previous
        // `if (workoutBox.get(hiveKey) != null) continue;` kept the stale
        // local version.

        // Sort exercises by order_index
        final exerciseRows = map['template_exercises'] as List? ?? [];
        exerciseRows.sort((a, b) =>
            ((a as Map)['order_index'] as int? ?? 0)
                .compareTo((b as Map)['order_index'] as int? ?? 0));

        final exercises = exerciseRows.map((e) {
          final ex = Map<String, dynamic>.from(e as Map);
          return {
            'exercise_name': ex['exercise_name'],
            'name': ex['exercise_name'],
            'exercise_id': ex['exercise_id'],
            'id': ex['exercise_id'],
            'logging_type': ex['logging_type'] ?? 'weight_reps',
            'sets': ex['prescribed_sets']?.toString() ?? '3',
            'reps': ex['prescribed_reps']?.toString() ?? '10',
            'weight_kg': ex['prescribed_weight'],
            'rest_seconds': ex['rest_seconds'],
            'rest_secs': ex['rest_seconds'],
            'notes': ex['notes'],
          };
        }).toList();

        await _hive.workoutBox.put(hiveKey, {
          'id': hiveKey,
          'type': 'template',
          'name': map['name'],
          'description': map['description'],
          'workout_focus': map['workout_type'],
          'workout_type': map['workout_type'],
          'exercises': exercises,
          'created_at': map['created_at'],
          'last_used_at': map['last_used_at'],
          'source': 'cloud_restore',
        });
      }
    } catch (e) {
      debugPrint('[SyncService._restoreWorkoutTemplates] $e');
    }
  }

  // ── Gap 3: Scheduled Workouts ──────────────────────────────

  /// Pushes full scheduled workout definitions to Supabase.
  /// Complements _syncScheduleCompletions which only pushes completed status.
  Future<void> _syncScheduledWorkouts(String userId) async {
    final workoutBox = _hive.workoutBox;
    for (final key in workoutBox.keys) {
      if (key is! String || !key.startsWith('schedule_')) continue;
      final raw = workoutBox.get(key);
      if (raw is! Map) continue;
      final entry = Map<String, dynamic>.from(raw);
      final date = entry['date'] as String?;
      if (date == null) continue;

      try {
        final parsedDate = DateTime.tryParse(date);
        await _supabase.client.from('scheduled_workouts').upsert({
          'user_id': userId,
          'template_id': entry['template_id'],
          'scheduled_date': date,
          'week_number': entry['week'] ?? entry['week_number'],
          'day_of_week': parsedDate?.weekday ?? entry['day_of_week'],
          'status': entry['status'] ?? 'planned',
          'completed_at': entry['completed_at'],
        }, onConflict: 'user_id,scheduled_date');
      } catch (e) {
        debugPrint('[SyncService._syncScheduledWorkouts] $e');
      }
    }
  }

  /// Restores scheduled workouts from Supabase (supplement to plan restore).
  Future<void> _restoreScheduledWorkouts(String userId, String since) async {
    try {
      final rows = await _fetchAllRows(
        'scheduled_workouts', userId,
        dateColumn: 'scheduled_date', since: since.substring(0, 10),
        orderBy: 'scheduled_date',
      );

      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final date = map['scheduled_date'] as String? ?? '';
        if (date.isEmpty) continue;
        final key = 'schedule_$date';
        // Skip if plan restore already populated this
        if (_hive.workoutBox.get(key) != null) continue;

        await _hive.workoutBox.put(key, {
          'date': date,
          'type': map['template_id'] != null ? 'custom_template' : 'workout',
          'template_id': map['template_id'],
          'status': map['status'] ?? 'planned',
          'completed_at': map['completed_at'],
          'week': map['week_number'],
          'week_number': map['week_number'],
          'day_of_week': map['day_of_week'],
          'source': 'cloud_restore',
        });
      }
    } catch (e) {
      debugPrint('[SyncService._restoreScheduledWorkouts] $e');
    }
  }

  // ── Gap 4: User Saved Meals ────────────────────────────────

  /// Pushes saved meals to Supabase user_saved_meals table.
  Future<void> _syncSavedMeals(String userId) async {
    final nutritionBox = _hive.nutritionBox;
    for (final key in nutritionBox.keys) {
      if (key is! String || !key.startsWith('saved_meal_')) continue;
      final raw = nutritionBox.get(key);
      if (raw is! Map) continue;
      final meal = Map<String, dynamic>.from(raw);
      if (meal['is_saved_meal'] != true) continue;

      try {
        await _supabase.client.from('user_saved_meals').upsert({
          'id': meal['id'] ?? key,
          'user_id': userId,
          'name': meal['name'] ?? 'Unnamed Meal',
          'items': meal['items'],
          'total_calories': meal['total_calories'],
          'total_protein': meal['total_protein'],
          'times_used': meal['times_used'] ?? 0,
          'created_at': meal['created_at'] ?? DateTime.now().toIso8601String(),
        }, onConflict: 'id');
      } catch (e) {
        debugPrint('[SyncService._syncSavedMeals] $e');
      }
    }
  }

  /// Restores saved meals from Supabase.
  Future<void> _restoreSavedMeals(String userId) async {
    try {
      final rows = await _supabase.client
          .from('user_saved_meals')
          .select()
          .eq('user_id', userId)
          .limit(500);

      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final id = map['id'] as String? ?? '';
        if (id.isEmpty) continue;
        final hiveKey = id.startsWith('saved_meal_') ? id : 'saved_meal_${id.hashCode}';
        if (_hive.nutritionBox.get(hiveKey) != null) continue;

        await _hive.nutritionBox.put(hiveKey, {
          'id': hiveKey,
          'is_saved_meal': true,
          'name': map['name'],
          'total_calories': map['total_calories'],
          'total_protein': map['total_protein'],
          'total_carbs': map['total_carbs'],
          'total_fat': map['total_fat'],
          'items': map['items'],
          'times_used': map['times_used'] ?? 0,
          'created_at': map['created_at'],
          'source': 'cloud_restore',
        });
      }
    } catch (e) {
      debugPrint('[SyncService._restoreSavedMeals] $e');
    }
  }

  // ── Gap 6: User Preferences ────────────────────────────────

  /// Pushes user preferences to Supabase user_preferences table.
  Future<void> _syncUserPreferences(String userId) async {
    try {
      final prefs = _hive.userBox.get('preferences');
      if (prefs == null) return;
      final p = Map<String, dynamic>.from(prefs as Map);

      await _supabase.client.from('user_preferences').upsert({
        'user_id': userId,
        'motivational_style': p['motivational_style'] ?? 'encouraging',
        'biggest_obstacle': p['biggest_obstacle'],
        'preferred_language': p['preferred_language'] ?? 'en',
        'coaching_notes': p['coaching_notes'],
      }, onConflict: 'user_id');
    } catch (e) {
      debugPrint('[SyncService._syncUserPreferences] $e');
    }
  }

  /// Restores user preferences from Supabase.
  Future<void> _restoreUserPreferences(String userId) async {
    try {
      final rows = await _supabase.client
          .from('user_preferences')
          .select()
          .eq('user_id', userId)
          .limit(1);

      if (rows.isEmpty) return;
      final cloud = Map<String, dynamic>.from(rows.first as Map);
      cloud.remove('user_id');

      // F6 · Merge semantics — cloud non-null wins, Hive preserved for nulls.
      final existing = _hive.userBox.get('preferences');
      final existingMap = existing is Map
          ? Map<String, dynamic>.from(existing)
          : <String, dynamic>{};
      final merged = <String, dynamic>{
        ...existingMap,
        for (final e in cloud.entries)
          if (e.value != null) e.key: e.value,
      };
      await _hive.userBox.put('preferences', merged);
    } catch (e) {
      debugPrint('[SyncService._restoreUserPreferences] $e');
    }
  }

  // ── Gap 7: AI Coach Interactions ───────────────────────────

  /// Pushes AI coach interactions to Supabase.
  /// Note: The AI proxy Edge Function already writes server-side,
  /// so this mainly catches edge-case local-only entries.
  Future<void> _syncCoachInteractions(String userId) async {
    final coachBox = _hive.coachBox;
    for (final key in coachBox.keys) {
      if (key is! String || !key.startsWith('coach_')) continue;
      final raw = coachBox.get(key);
      if (raw is! Map) continue;
      final entry = Map<String, dynamic>.from(raw);

      try {
        await _supabase.client.from('ai_coach_interactions').upsert({
          'id': entry['id'] ?? key,
          'user_id': userId,
          'channel': 'in_app',
          'user_message': entry['user_message'] ?? '',
          'ai_response': entry['ai_response'] ?? '',
          'model_used': entry['model_used'] ?? 'unknown',
          'created_at': entry['created_at'] ?? DateTime.now().toIso8601String(),
        }, onConflict: 'id');
      } catch (e) {
        debugPrint('[SyncService._syncCoachInteractions] $e');
      }
    }
  }

  /// Restores AI coach interactions from Supabase (for chat history on new device).
  Future<void> _restoreCoachInteractions(String userId, String since) async {
    try {
      final rows = await _supabase.client
          .from('ai_coach_interactions')
          .select()
          .eq('user_id', userId)
          .gte('created_at', since)
          .order('created_at')
          .limit(1000);

      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final id = map['id'] as String? ?? '';
        if (id.isEmpty) continue;
        final hiveKey = id.startsWith('coach_') ? id : 'coach_${id.hashCode}';
        if (_hive.coachBox.get(hiveKey) != null) continue;

        await _hive.coachBox.put(hiveKey, {
          'id': hiveKey,
          'user_message': map['user_message'] ?? '',
          'ai_response': map['ai_response'] ?? '',
          'model_used': map['model_used'] ?? 'unknown',
          'mode': 'quick',
          'is_user_message': true,
          'created_at': map['created_at'],
          'source': 'cloud_restore',
        });
      }
    } catch (e) {
      debugPrint('[SyncService._restoreCoachInteractions] $e');
    }
  }

  /// Pulls coach_memory induction state from Supabase into local coachBox.
  ///
  /// Run on restoreFromCloud so returning users (new device or post-logout)
  /// skip the InductionScreen — the cloud row already has [induction_completed_at]
  /// and all muster answers. If the user has no coach_memory row yet (un-inducted),
  /// maybeSingle() returns null and we skip silently.
  Future<void> _restoreCoachMemory(String userId) async {
    try {
      final row = await _supabase.client
          .from('coach_memory')
          .select(
            'committed_at, committed_to_lt_cdr, induction_completed_at, '
            'why_now, definition_of_winning, known_injuries, '
            'typical_wake_time, preferred_workout_time, body_part_priorities',
          )
          .eq('user_id', userId)
          .maybeSingle();
      if (row == null) return;

      final coach = _hive.coachBox;
      const keys = [
        'committed_at',
        'committed_to_lt_cdr',
        'induction_completed_at',
        'why_now',
        'definition_of_winning',
        'known_injuries',
        'typical_wake_time',
        'preferred_workout_time',
        'body_part_priorities',
      ];
      for (final key in keys) {
        final v = row[key];
        if (v != null) await coach.put(key, v);
      }
    } catch (e) {
      debugPrint('[SyncService._restoreCoachMemory] $e');
      unawaited(_reportSyncFailure(
        opType: 'restore_coach_memory',
        error: e,
      ));
    }
  }

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
