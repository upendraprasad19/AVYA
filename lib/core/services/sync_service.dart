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
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';

/// Handles background data sync between Hive (local) and Supabase (cloud).
///
/// Schedule:
///   - Immediately: custom foods/exercises (community contribution)
///   - Daily 11 PM IST: user_daily_snapshot for AI context
///   - Weekly (app launch if >7 days): full sync of all logs
///   - On restore (new device): pull 30d (free) / 90d (PRO) from Supabase
class SyncService {
  SyncService._();
  static final SyncService _instance = SyncService._();
  static SyncService get instance => _instance;

  final HiveService _hive = HiveService.instance;
  final SupabaseService _supabase = SupabaseService.instance;

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
          .upsert(payload, onConflict: 'user_id');
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

      // On reinstall / new device: if Hive workout data is empty,
      // pull everything from Supabase first.
      await _restoreIfNeeded(userId);

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

  /// Pushes the daily snapshot to Supabase `user_daily_snapshots` table.
  Future<void> pushSnapshot() async {
    try {
      final userId = _supabase.currentUser?.id;
      if (userId == null) return;

      final snapshot = compileDailySnapshot();

      await _supabase.client.from('user_daily_snapshots').upsert({
        'user_id': userId,
        'snapshot_date': snapshot['snapshot_date'],
        'snapshot_json': snapshot,
        'created_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,snapshot_date');

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

      await Future.wait([
        _syncWorkoutLogs(userId),
        _syncExerciseLogs(userId),
        _syncScheduleCompletions(userId),
        _syncNutritionLogs(userId),
        _syncWeightLogs(userId),
        _syncMeasurements(userId),
        _syncSleepLogs(userId),
        _syncStreaks(userId),
        _syncUserProfile(userId),
        _syncUrineColorLogs(userId),
        _syncWaterLogs(userId),
        _syncWorkoutPlan(userId),
        _syncUserProgress(userId),
        // ── New sync gap methods ──
        _syncWorkoutTemplates(userId),
        _syncScheduledWorkouts(userId),
        _syncSavedMeals(userId),
        _syncUserPreferences(userId),
        _syncCoachInteractions(userId),
      ]);

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

      await Future.wait([
        _syncWorkoutLogs(userId),
        _syncExerciseLogs(userId),
        _syncScheduleCompletions(userId),
      ]);
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

      await Future.wait([
        _syncNutritionLogs(userId),
        _syncWaterLogs(userId),
      ]);
    } catch (e) {
      // Offline — will sync on next daily full sync.
      debugPrint('[SyncService.syncNutritionData] $e');
    }
  }

  // ── Restore from Cloud (reinstall / new device) ────────────────

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

      await Future.wait([
        _restoreWorkoutLogs(userId, since),
        _restoreExerciseLogs(userId, since),
        _restoreScheduleCompletions(userId, since),
        _restoreCustomExercises(userId),
        _restoreCustomFoods(userId),
        _restoreWeightLogs(userId, since),
        _restoreNutritionLogs(userId, since),
        _restoreMeasurements(userId, since),
        _restoreUserProfile(userId),
        _restoreUserProgress(userId),
        _restoreWorkoutPlan(userId),
        _restoreWaterLogs(userId, since),
        _restoreSleepLogs(userId, since),
        _restoreStreaks(userId),
        // ── New restore methods ──
        _restoreWorkoutTemplates(userId),
        _restoreScheduledWorkouts(userId, since),
        _restoreSavedMeals(userId),
        _restoreUserPreferences(userId),
        _restoreCoachInteractions(userId, since),
      ]);
    } catch (e) {
      // Partial restore is fine — app works offline with whatever we got.
      debugPrint('[SyncService.restoreFromCloud] $e');
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

      await Future.wait([
        _pullWeightLogs(userId, since),
        _pullNutritionLogs(userId, since),
        _pullMeasurements(userId, since),
      ]);
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
        .listen((rows) async {
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
        });
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
  /// Supabase workout_log_exercises table.
  Future<void> _syncExerciseLogs(String userId) async {
    final workoutBox = _hive.workoutBox;
    for (final key in workoutBox.keys) {
      if (key is! String || !key.startsWith('exlog_')) continue;
      final raw = workoutBox.get(key);
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);

      try {
        // Each row is a per-exercise SUMMARY (1 row per exercise, not per set).
        // set_number = total completed sets for this exercise.
        // reps = cumulative reps across all sets.
        // weight_kg = best (max) weight across sets.
        // workout_log_id = deterministic from date → groups exercises by workout.
        // exercise_id = exercise_name → stable identity for cross-week grouping.
        final date = log['date'] as String? ?? '';
        await _supabase.client.from('workout_log_exercises').upsert({
          'id': _deterministicId(key),
          'workout_log_id': _deterministicId('workout_$date'),
          'user_id': userId,
          'exercise_id': log['exercise_name'] ?? key,
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
        // Push aggregate nutrition_logs row
        final logForSupabase = Map<String, dynamic>.from(log);
        logForSupabase.remove('items'); // Don't store items list in the parent table
        await _supabase.client.from("nutrition_logs").upsert({
          ...logForSupabase, "user_id": userId,
        }, onConflict: "id");

        // Push individual nutrition_log_items (Gap 5)
        final items = log['items'];
        if (items is List) {
          final logId = log['id'] as String? ?? key;
          for (int i = 0; i < items.length; i++) {
            final item = items[i] is Map
                ? Map<String, dynamic>.from(items[i] as Map)
                : <String, dynamic>{};
            try {
              await _supabase.client.from('nutrition_log_items').upsert({
                'id': '${logId}_item_$i',
                'log_id': logId,
                'food_id': item['food_id'],
                'food_name': item['name'] ?? item['food_name'] ?? '',
                'quantity_g': item['serving_g'] ?? item['quantity_g'],
                'calories': item['calories'],
                'protein': item['protein'],
                'carbs': item['carbs'],
                'fat': item['fat'],
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
  Future<void> syncProfileNow(String userId) => _syncUserProfile(userId);

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

    // Mirrors every field stored in the Hive profile map that has a matching
    // user_profile column. Columns added in migration 017 (lifestyle_activity,
    // session_duration_minutes, physique_focus, body_fat_percent,
    // body_fat_assessed_at) were previously silently dropped.
    final payload = <String, dynamic>{
      'user_id': userId,
      if (p['date_of_birth'] != null) 'date_of_birth': p['date_of_birth'],
      if (p['gender'] != null) 'gender': p['gender'],
      if (p['height_cm'] != null) 'height_cm': p['height_cm'],
      if (p['current_weight_kg'] != null) 'current_weight_kg': p['current_weight_kg'],
      if (p['target_weight_kg'] != null) 'target_weight_kg': p['target_weight_kg'],
      if (p['primary_goal'] != null) 'primary_goal': p['primary_goal'],
      if (p['fitness_experience'] != null) 'fitness_experience': p['fitness_experience'],
      if (p['days_per_week'] != null) 'days_per_week': p['days_per_week'],
      if (p['equipment_access'] != null) 'equipment_access': p['equipment_access'],
      if (p['activity_level'] != null) 'activity_level': p['activity_level'],
      if (p['lifestyle_activity'] != null) 'lifestyle_activity': p['lifestyle_activity'],
      if (p['pace_preference'] != null) 'pace_preference': p['pace_preference'],
      if (p['diet_preference'] != null) 'diet_preference': p['diet_preference'],
      if (p['injuries'] != null) 'injuries': p['injuries']?.toString(),
      if (p['city'] != null) 'city': p['city'],
      if (p['bmr'] != null) 'bmr': p['bmr'],
      if (p['tdee'] != null) 'tdee': p['tdee'],
      if (p['body_fat_percent'] != null) 'body_fat_percent': p['body_fat_percent'],
      if (p['body_fat_assessed_at'] != null) 'body_fat_assessed_at': p['body_fat_assessed_at'],
      if (p['session_duration_minutes'] != null) 'session_duration_minutes': p['session_duration_minutes'],
      if (p['physique_focus'] != null) 'physique_focus': p['physique_focus'],
      if (p['avatar_url'] != null) 'avatar_url': p['avatar_url'],
      if (p['banner_url'] != null) 'banner_url': p['banner_url'],
      if (p['wake_up_time'] != null) 'wake_up_time': p['wake_up_time'],
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
        .upsert(payload, onConflict: 'user_id');
  }

  /// Pushes user-created custom foods and exercises to Supabase
  /// for community contribution.
  Future<void> _syncCustomItems() async {
    try {
      final userId = _supabase.currentUser?.id;
      if (userId == null) return;

      final customBox = _hive.customBox;

      // Custom exercises
      final customExercises = customBox.get('custom_exercises');
      if (customExercises != null) {
        final items = (customExercises as List).cast<Map>();
        for (final item in items) {
          await _supabase.client.from('user_custom_exercises').upsert({
            ...Map<String, dynamic>.from(item),
            'user_id': userId,
          }, onConflict: 'id');
        }
      }

      // Custom foods
      final customFoods = customBox.get('custom_foods');
      if (customFoods != null) {
        final items = (customFoods as List).cast<Map>();
        for (final item in items) {
          await _supabase.client.from('user_custom_foods').upsert({
            ...Map<String, dynamic>.from(item),
            'user_id': userId,
          }, onConflict: 'id');
        }
      }

      await _setTimestamp(_lastCustomSyncKey);
    } catch (e) {
      // Silently skip.
      debugPrint('[SyncService._syncCustomItems] $e');
    }
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
      // Only restore if local profile is missing
      if (_hive.userBox.get('profile') != null) return;

      final rows = await _supabase.client
          .from('user_profile')
          .select()
          .eq('user_id', userId)
          .limit(1);

      if (rows.isEmpty) return;
      final map = Map<String, dynamic>.from(rows.first as Map);
      map.remove('user_id'); // Don't store user_id inside the profile map
      await _hive.userBox.put('profile', map);
    } catch (e) {
      debugPrint('[SyncService._restoreUserProfile] $e');
    }
  }

  Future<void> _restoreUserProgress(String userId) async {
    try {
      // Only restore if local progress is missing
      if (_hive.userBox.get('progress') != null) return;

      final rows = await _supabase.client
          .from('user_progress')
          .select()
          .eq('user_id', userId)
          .limit(1);

      if (rows.isEmpty) return;
      final map = Map<String, dynamic>.from(rows.first as Map);
      map.remove('user_id');
      await _hive.userBox.put('progress', map);
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
        final tmplId = tmpl['id']?.toString() ?? key;
        final exercises = tmpl['exercises'] as List? ?? [];

        // Upsert template header
        await _supabase.client.from('workout_templates').upsert({
          'id': tmplId,
          'user_id': userId,
          'name': tmpl['name'] ?? 'Untitled',
          'description': tmpl['description'],
          'workout_type': tmpl['workout_focus'] ?? tmpl['workout_type'],
          'estimated_duration_mins': tmpl['estimated_duration_mins'],
          'source': 'user',
          'is_active': true,
          'created_at': tmpl['created_at'] ?? DateTime.now().toIso8601String(),
          'last_used_at': tmpl['last_used_at'],
        }, onConflict: 'id');

        // Upsert child exercises
        for (int i = 0; i < exercises.length; i++) {
          final ex = exercises[i] is Map
              ? Map<String, dynamic>.from(exercises[i] as Map)
              : <String, dynamic>{};
          try {
            await _supabase.client.from('template_exercises').upsert({
              'id': '${tmplId}_ex_$i',
              'template_id': tmplId,
              'exercise_id': ex['exercise_id'] ?? ex['id'],
              'exercise_name': ex['exercise_name'] ?? ex['name'] ?? '',
              'order_index': i,
              'logging_type': ex['logging_type'] ?? 'weight_reps',
              'prescribed_sets': ex['sets'] is int ? ex['sets'] : int.tryParse(ex['sets']?.toString() ?? ''),
              'prescribed_reps': ex['reps']?.toString(),
              'prescribed_weight': ex['weight_kg']?.toString() ?? ex['prescribed_weight']?.toString(),
              'prescribed_time_secs': ex['time_secs'] ?? ex['prescribed_time_secs'],
              'rest_seconds': ex['rest_seconds'] ?? ex['rest_secs'],
              'notes': ex['notes'],
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
        if (_hive.workoutBox.get(hiveKey) != null) continue;

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
      if (_hive.userBox.get('preferences') != null) return;

      final rows = await _supabase.client
          .from('user_preferences')
          .select()
          .eq('user_id', userId)
          .limit(1);

      if (rows.isEmpty) return;
      final map = Map<String, dynamic>.from(rows.first as Map);
      map.remove('user_id');
      await _hive.userBox.put('preferences', map);
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
