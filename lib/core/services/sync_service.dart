import 'dart:async';
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

      // Pull recent cross-channel logs (Telegram → Hive, last 24h).
      await pullRecentCrossChannelLogs();

      // Check if a weekly full sync is needed.
      final lastFull = _getTimestamp(_lastFullSyncKey);
      if (lastFull == null ||
          DateTime.now().difference(lastFull) >= _fullSyncInterval) {
        await weeklyFullSync();
      }

      // Push any pending custom items immediately.
      await _syncCustomItems();

      // PRO users: subscribe to realtime for instant Telegram sync.
      if (SubscriptionService.instance.isPro()) {
        subscribeToRealtimeSync();
      }
    } catch (_) {
      // Offline or error — silently skip.
    }
  }

  /// Compiles a daily snapshot from Hive data for AI context injection.
  ///
  /// The snapshot contains ~300 tokens of user context:
  /// profile, this week's workouts, today's nutrition, weight, streak,
  /// PRs, detected experience, coaching_notes.
  ///
  /// Uses AiCoachRepository.buildAiContext() which already aggregates
  /// data from all Hive boxes via proper repository methods.
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
    } catch (_) {
      // Offline — will retry next scheduled run.
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
        _syncNutritionLogs(userId),
        _syncWeightLogs(userId),
        _syncMeasurements(userId),
        _syncSleepLogs(userId),
        _syncStreaks(userId),
        _syncUserProfile(userId),
        _syncUrineColorLogs(userId),
      ]);

      await _setTimestamp(_lastFullSyncKey);
    } catch (_) {
      // Partial sync failure — next launch will retry.
    }
  }

  // ── Cross-Channel Sync (Telegram → Hive) ────────────────────

  /// Pulls logs from Supabase that were created in the last 24 hours
  /// from other channels (e.g. Telegram bot). Merges into local Hive
  /// without overwriting existing entries.
  ///
  /// Called on every app launch for ALL users (free + PRO).
  /// Lightweight: one query per table, last 24h only.
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
    } catch (_) {
      // Offline or error — silently skip.
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

    // Subscribe to weight_logs inserts for this user
    _supabase.client
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

  // ── Private sync helpers ────────────────────────────────────

  Future<void> _syncWorkoutLogs(String userId) async {
    final workoutBox = _hive.workoutBox;
    final logs = workoutBox.get('workout_logs');
    if (logs == null) return;

    final items = (logs as List).cast<Map>();
    for (final log in items) {
      await _supabase.client.from('workout_logs').upsert({
        ...Map<String, dynamic>.from(log),
        'user_id': userId,
      }, onConflict: 'id');
    }
  }

  Future<void> _syncNutritionLogs(String userId) async {
    final nutritionBox = _hive.nutritionBox;
    final logs = nutritionBox.get('nutrition_logs');
    if (logs == null) return;

    final items = (logs as List).cast<Map>();
    for (final log in items) {
      await _supabase.client.from('nutrition_logs').upsert({
        ...Map<String, dynamic>.from(log),
        'user_id': userId,
      }, onConflict: 'id');
    }
  }

  Future<void> _syncWeightLogs(String userId) async {
    final healthBox = _hive.healthBox;
    final logs = healthBox.get('weight_logs');
    if (logs == null) return;

    final items = (logs as List).cast<Map>();
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

    final items = (logs as List).cast<Map>();
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

    final items = (logs as List).cast<Map>();
    for (final log in items) {
      await _supabase.client.from('sleep_logs').upsert({
        ...Map<String, dynamic>.from(log),
        'user_id': userId,
      }, onConflict: 'id');
    }
  }

  Future<void> _syncUrineColorLogs(String userId) async {
    final healthBox = _hive.healthBox;
    for (final key in healthBox.keys) {
      if (key is! String || !key.startsWith('urine_color_')) continue;
      final raw = healthBox.get(key);
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);
      final date = log['date'] as String?;
      if (date == null) continue;
      try {
        await _supabase.client.from('health_metrics').upsert({
          'user_id': userId,
          'date': date,
          'metric_type': 'urine_color',
          'value': (log['index'] as int?)?.toDouble() ?? -1,
          'label': log['label'] ?? 'unknown',
          'recorded_at': log['recorded_at'] ?? DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,date,metric_type');
      } catch (_) {
        // Table may not exist yet — skip silently.
      }
    }
  }

  Future<void> _syncStreaks(String userId) async {
    final healthBox = _hive.healthBox;
    final logs = healthBox.get('streaks');
    if (logs == null) return;

    final items = (logs as List).cast<Map>();
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
    // The Hive profile map contains extra computed fields (daily_calories,
    // protein_grams, etc.) that have no Postgres column and would cause errors.
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
    } catch (_) {
      // Silently skip.
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
