import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
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

  /// Called on every app launch. Determines what needs syncing and
  /// triggers the appropriate operations in the background.
  ///
  /// Never blocks the UI — failures are silently ignored.
  Future<void> checkAndSync() async {
    try {
      if (!_supabase.isAuthenticated) return;

      // Check if a weekly full sync is needed.
      final lastFull = _getTimestamp(_lastFullSyncKey);
      if (lastFull == null ||
          DateTime.now().difference(lastFull) >= _fullSyncInterval) {
        await weeklyFullSync();
      }

      // Push any pending custom items immediately.
      await _syncCustomItems();
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
      ]);

      await _setTimestamp(_lastFullSyncKey);
    } catch (_) {
      // Partial sync failure — next launch will retry.
    }
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

  Future<void> _syncUserProfile(String userId) async {
    final userBox = _hive.userBox;
    final profile = userBox.get('profile');
    if (profile == null) return;

    await _supabase.client.from('user_profile').upsert({
      ...Map<String, dynamic>.from(profile as Map),
      'user_id': userId,
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
