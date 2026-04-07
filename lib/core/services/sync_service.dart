import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
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

  /// Duration between full syncs (7 days).
  static const Duration _fullSyncInterval = Duration(days: 7);

  // ── Public API ──────────────────────────────────────────────

  /// Active realtime subscription (PRO only, for Telegram cross-channel).
  StreamSubscription? _realtimeSubscription;

  /// Called on every app launch. Determines what needs syncing and
  /// triggers the appropriate operations in the background.
  ///
  /// Never blocks the UI — failures are silently ignored.
  Future<void> checkAndSync() async {
    try {
      if (!_supabase.isAuthenticated) return;

      final userId = _supabase.currentUser?.id;
      if (userId == null) return;

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

      // Pull approved community foods/exercises.
      await syncCommunityItems();

      // PRO users: subscribe to realtime for instant Telegram sync.
      if (SubscriptionService.instance.isPro()) {
        subscribeToRealtimeSync();
      }
    } catch (e) {
      // Offline or error — silently skip.
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
  /// Triggered on app launch if >7 days since last full sync.
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
  /// PRO users get 90 days of history; free users get 30 days.
  Future<void> restoreFromCloud(String userId) async {
    try {
      final isPro = SubscriptionService.instance.isPro();
      final days = isPro ? 90 : 30;
      final since =
          DateTime.now().subtract(Duration(days: days)).toIso8601String();

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
        .listen((rows) {
          for (final row in rows) {
            final date = row['date'] as String? ?? '';
            final key = 'weight_$date';
            if (_hive.healthBox.get(key) == null) {
              _hive.healthBox.put(key, {
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
          'user_id': userId,
          'exercise_name': log['workout_name'],
          'date': log['date'],
          'logged_at': log['completed_at'],
          'sets_completed': log['sets_completed'],
          'duration_seconds': log['duration_seconds'],
          'notes': log['id'], // store local ID for dedup
          'created_at': log['completed_at'] ?? DateTime.now().toIso8601String(),
        }, onConflict: 'id');
      } catch (e) {
        // Skip individual failures.
        debugPrint('[SyncService._syncWorkoutLogs] $e');
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
        await _supabase.client.from('workout_log_exercises').upsert({
          'workout_log_id': log['id'],
          'user_id': userId,
          'exercise_id': log['id'] ?? key,
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
        // Skip individual failures.
        debugPrint('[SyncService._syncExerciseLogs] $e');
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
        // Skip individual failures.
        debugPrint('[SyncService._syncScheduleCompletions] $e');
      }
    }
  }

  Future<void> _syncNutritionLogs(String userId) async {
    final nutritionBox = _hive.nutritionBox;
    for (final key in nutritionBox.keys) {
      if (key is! String || !key.startsWith("nlog_")) continue;
      final log = nutritionBox.get(key);
      if (log == null) continue;
      try {
        await _supabase.client.from("nutrition_logs").upsert({
          ...Map<String, dynamic>.from(log as Map), "user_id": userId,
        }, onConflict: "id");
      } catch (e) {
        debugPrint('[SyncService._syncNutritionLogs] $e');
      }
    }
  }

  Future<void> _syncWeightLogs(String userId) async {
    final healthBox = _hive.healthBox;
    final logs = healthBox.get('weight_logs');
    if (logs == null) return;

    final items = (logs as List).whereType<Map>();
    for (final log in items) {
      await _supabase.client.from('weight_logs').upsert({
        ...Map<String, dynamic>.from(log),
        'user_id': userId,
      }, onConflict: 'id');
    }
  }

  Future<void> _syncMeasurements(String userId) async {
    final healthBox = _hive.healthBox;
    final logs = healthBox.get('body_measurements');
    if (logs == null) return;

    final items = (logs as List).whereType<Map>();
    for (final log in items) {
      await _supabase.client.from('body_measurements').upsert({
        ...Map<String, dynamic>.from(log),
        'user_id': userId,
      }, onConflict: 'id');
    }
  }

  Future<void> _syncSleepLogs(String userId) async {
    final healthBox = _hive.healthBox;
    final logs = healthBox.get('sleep_logs');
    if (logs == null) return;

    final items = (logs as List).whereType<Map>();
    for (final log in items) {
      await _supabase.client.from('sleep_logs').upsert({
        ...Map<String, dynamic>.from(log),
        'user_id': userId,
      }, onConflict: 'id');
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
      await _supabase.client.from('streaks').upsert({
        ...Map<String, dynamic>.from(log),
        'user_id': userId,
      }, onConflict: 'id');
    }
  }

  /// Immediately pushes the local Hive profile to Supabase user_profile.
  /// Safe to call from anywhere — only sends columns that exist in the schema.
  Future<void> syncProfileNow(String userId) => _syncUserProfile(userId);

  Future<void> _syncUserProfile(String userId) async {
    final userBox = _hive.userBox;
    final profile = userBox.get('profile');
    if (profile == null) return;

    final p = Map<String, dynamic>.from(profile as Map);

    // Only send columns that exist in the user_profile Supabase table.
    await _supabase.client.from('user_profile').upsert({
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
      if (p['bmr'] != null) 'bmr': p['bmr'],
      if (p['tdee'] != null) 'tdee': p['tdee'],
      if (p['diet_preference'] != null) 'diet_preference': p['diet_preference'],
      if (p['city'] != null) 'city': p['city'],
      if (p['body_fat_percent'] != null) 'body_fat_percent': p['body_fat_percent'],
      if (p['body_fat_assessed_at'] != null) 'body_fat_assessed_at': p['body_fat_assessed_at'],
      if (p['injuries'] != null) 'injuries': p['injuries']?.toString(),
    }, onConflict: 'user_id');
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

  // ── Private Restore Helpers (Cloud → Hive) ──────────────────

  Future<void> _restoreWorkoutLogs(String userId, String since) async {
    try {
      final rows = await _supabase.client
          .from('workout_logs')
          .select()
          .eq('user_id', userId)
          .gte('created_at', since)
          .order('created_at')
          .limit(5000);

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
      final rows = await _supabase.client
          .from('workout_log_exercises')
          .select()
          .eq('user_id', userId)
          .gte('completed_at', since)
          .order('completed_at')
          .limit(5000);

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
          .order('scheduled_date')
          .limit(5000);

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
      final rows = await _supabase.client
          .from('weight_logs')
          .select()
          .eq('user_id', userId)
          .gte('created_at', since)
          .limit(5000);

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
      final rows = await _supabase.client
          .from('nutrition_logs')
          .select()
          .eq('user_id', userId)
          .gte('created_at', since)
          .limit(5000);

      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final id = map['id'] as String? ?? '';
        if (_hive.nutritionBox.get(id) != null) continue;
        await _hive.nutritionBox.put(id, {
          ...map,
          'source': 'cloud_restore',
        });
      }
    } catch (e) {
      debugPrint('[SyncService._restoreNutritionLogs] $e');
    }
  }

  Future<void> _restoreMeasurements(String userId, String since) async {
    try {
      final rows = await _supabase.client
          .from('body_measurements')
          .select()
          .eq('user_id', userId)
          .gte('created_at', since)
          .limit(5000);

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
      final rows = await _supabase.client
          .from('water_logs')
          .select()
          .eq('user_id', userId)
          .gte('date', since.substring(0, 10)) // date is a DATE column, use date part only
          .limit(5000);

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
          .gte('created_at', since)
          .limit(5000);

      if (rows.isEmpty) return;

      final healthBox = _hive.healthBox;
      // Get existing local sleep logs
      final existingRaw = healthBox.get('sleep_logs');
      final existing = existingRaw is List ? List<Map>.from(existingRaw) : <Map>[];
      final existingIds = existing
          .map((e) => e['id']?.toString() ?? '')
          .toSet();

      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final id = map['id']?.toString() ?? '';
        if (id.isNotEmpty && !existingIds.contains(id)) {
          existing.add({...map, 'source': 'cloud_restore'});
        }
      }

      await healthBox.put('sleep_logs', existing);
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
      final existingIds = existing
          .map((e) => e['id']?.toString() ?? '')
          .toSet();

      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final id = map['id']?.toString() ?? '';
        if (id.isNotEmpty && !existingIds.contains(id)) {
          existing.add({...map, 'source': 'cloud_restore'});
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
