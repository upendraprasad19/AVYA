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
import 'package:icanbefitter/core/utils/ist_date.dart';
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

  /// One-shot backfill: iterate customBox, (a) assign deterministic ids to
  /// entries that have none (F8/F22 pre-existing entries), and (b) repair
  /// custom exercises with null/missing `logging_type` (F12). Fire-and-
  /// forget from `checkAndSync()`.
  Future<void> _backfillCustomEntityIds() async {
    try {
      // APK Test #12.7 — open the session before iterating customBox.
      final userId = await _ensureSessionOpen();
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
    } catch (e, st) {
      debugPrint('[SyncService._backfillCustomEntityIds] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_if'));
      try {
        await _reportSyncFailure(opType: 'backfill_custom_entity_ids', error: e);
      } catch (_) {}
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

  /// Push workout logs + exercise logs + schedule completions to Supabase.
  /// Call this after a workout is completed for near-realtime backup.
  Future<void> syncWorkoutData() async {
    try {
      // APK Test #12.7 — every WorkoutWriteService.logExercise fires
      // this fire-and-forget. If we land before _ensureLocalUser, every
      // workoutBox read throws StateError → cloud silently empty.
      final userId = await _ensureSessionOpen();
      if (userId == null) return;

      // APK Test #14 / Bug B.1 — templates must complete BEFORE schedules
      // so the schedule FK lookup (`workout_templates.id`) succeeds. Pre-fix
      // both ran inside `Future.wait`; on cold start the schedule push
      // would race the template push and hit 23503. See
      // docs/diagnoses/2026-05-10-fk-violation-saturday-c8e4a1.md.
      await _safeRestoreOp(
          'sync_workout_templates', _syncWorkoutTemplates(userId));

      await Future.wait(
        [
          _safeRestoreOp('sync_workout_logs', _syncWorkoutLogs(userId)),
          _safeRestoreOp('sync_exercise_logs', _syncExerciseLogs(userId)),
          _safeRestoreOp('sync_schedule_completions', _syncScheduleCompletions(userId)),
          // F1 · Test #9 — close the templates / schedules / streaks
          // gap. These used to wait up to 24h for weeklyFullSync(); now
          // push on the same fire-and-forget cycle as logs.
          // (templates run sequentially above per APK Test #14 / Bug B.1)
          _safeRestoreOp('sync_scheduled_workouts', _syncScheduledWorkouts(userId)),
          _safeRestoreOp('sync_streaks', _syncStreaks(userId)),
        ],
        eagerError: false,
      );
    } catch (e, st) {
      // Offline — will sync on next weekly sync.
      debugPrint('[SyncService.syncWorkoutData] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_sync_workout_data'));
      try {
        await _reportSyncFailure(opType: 'sync_workout_data', error: e);
      } catch (_) {}
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
      // APK Test #12.7 — fire-and-forget call from
      // NutritionWriteService.logMeal. Same race as syncWorkoutData.
      final userId = await _ensureSessionOpen();
      if (userId == null) return;

      await Future.wait(
        [
          _safeRestoreOp('sync_nutrition_logs', _syncNutritionLogs(userId)),
          _safeRestoreOp('sync_water_logs', _syncWaterLogs(userId)),
          // F2 · Test #9 — saved meals join the per-mutation path
          // so they reach cloud immediately on save instead of next-day batch.
          _safeRestoreOp('sync_saved_meals', _syncSavedMeals(userId)),
        ],
        eagerError: false,
      );
    } catch (e, st) {
      // Offline — will sync on next daily full sync.
      debugPrint('[SyncService.syncNutritionData] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_sync_nutrition_data'));
      try {
        await _reportSyncFailure(opType: 'sync_nutrition_data', error: e);
      } catch (_) {}
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

  // ── PRO Realtime Sync ──────────────────────────────────────

  /// Subscribes to Supabase realtime channels for instant cross-device
  /// sync. PRO only — enables Telegram-logged data to appear in the
  /// app immediately without waiting for the 24h batch pull.
  Future<void> subscribeToRealtimeSync() async {
    if (_realtimeSubscription != null) return; // Already subscribed

    final userId = _supabase.currentUser?.id;
    if (userId == null) return;

    // Test #12.6 — refresh JWT before opening the realtime channel.
    // Realtime subscribes carry the access token in the WebSocket
    // upgrade; if the token expired while the app was backgrounded
    // we get `RealtimeSubscribeException: Token has expired N seconds
    // ago` on the first message and the stream errors permanently.
    // refreshSession is idempotent and cheap when token is fresh.
    try {
      await _supabase.client.auth.refreshSession();
    } catch (e, st) {
      debugPrint('[realtime] refreshSession failed before subscribe: $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_subscribe_to_realtime_sync'));
      // Non-fatal — subscription may still succeed if token is valid.
    }

    _attachRealtimeStream(userId, attempt: 1);
  }

  /// Internal: opens the weight_logs stream. On token-expired errors
  /// from the channel, refreshes JWT and re-subscribes once.
  void _attachRealtimeStream(String userId, {required int attempt}) {
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

            // Test #12.6 — Token-expired reconnect (one-shot). If the
            // channel errored with "Token has expired", refresh the JWT
            // and re-subscribe once. Subsequent failures fall through
            // (no infinite retry loop).
            final msg = e.toString().toLowerCase();
            final isTokenExpired = msg.contains('token has expired') ||
                msg.contains('jwt expired') ||
                msg.contains('expired_token');
            if (isTokenExpired && attempt < 2) {
              // ignore: discarded_futures
              _reconnectRealtimeWithRefreshedJwt(userId, attempt + 1);
            }
          },
        );
  }

  Future<void> _reconnectRealtimeWithRefreshedJwt(
    String userId,
    int attempt,
  ) async {
    try {
      await _realtimeSubscription?.cancel();
    } catch (_) {}
    _realtimeSubscription = null;
    try {
      await _supabase.client.auth.refreshSession();
    } catch (e, st) {
      debugPrint('[realtime] refreshSession on reconnect failed: $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_catch_4'));
      return; // can't recover without a fresh token
    }
    _attachRealtimeStream(userId, attempt: attempt);
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
        // APK Test #12.7 — preserve original timestamp. Read from any of
        // {created_at, completed_at, *_ms} or fall back to the IST date
        // parsed from the Hive key. Empty-string `completed_at` (which
        // older restores wrote into Hive) is filtered by the helper —
        // this stops the cloud rejecting with `invalid input syntax for
        // type timestamp with time zone: ""`.
        final resolved = _resolveCompletedAt(
          log,
          dateKeyPrefix: log['date'] as String? ?? _dateFromKey(key),
          hiveKey: key,
        );
        // `logged_at` and `created_at` are timestamptz columns. Send
        // null when the source was an empty string AND we have no
        // alternate authoring time (helper's last-resort path); the
        // null branch is friendlier to PostgREST than a fabricated
        // wall-clock that misrepresents history.
        // Audit 2026-05-12 P2-F — include `rpe` in the projection so
        // weekly-report stops rendering "N/A" for sessions where the user
        // (or AI coach via tool calls) supplied a rating-of-perceived-
        // exertion. Cloud column was always there; client just never
        // shipped the field. Safe to send null when Hive doesn't have it.
        // Audit 2026-05-12 P2-E — onConflict was 'id'; same class as P0-A.
        // Live data had 27 rows for 8 sessions (founder's account had 4-6
        // dupes for each completed workout). Migration 062 added natural
        // UNIQUE on (user_id, date, exercise_name); switch the upsert to
        // target it so re-syncs merge instead of producing fresh dupes.
        await _supabase.client.from('workout_logs').upsert({
          'id': _deterministicId(key),
          'user_id': userId,
          'exercise_name': log['workout_name'],
          'date': log['date'],
          'logged_at': resolved,
          'sets_completed': log['sets_completed'],
          'duration_seconds': log['duration_seconds'],
          if (log['rpe'] != null) 'rpe': log['rpe'],
          'notes': log['id'], // store local ID for reference
          'created_at': resolved,
        }, onConflict: 'user_id,date,exercise_name');
      } catch (e, st) {
        debugPrint('[SyncService._syncWorkoutLogs] Failed key=$key: $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_for'));
        try {
          await _reportSyncFailure(opType: 'upsert_workout_log', error: e);
        } catch (_) {}
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

        // Plan A A-5: support BOTH the legacy `sets_completed`/`sets_detail`
        // shape and the new WorkoutWriteService shape (`set_number` count +
        // `sets` list). Resolve per-set list once; reuse for summary +
        // per-set rows.
        final List<Map<String, dynamic>> resolvedSets =
            _resolvePerSetList(log);
        final int summarySetCount = resolvedSets.isNotEmpty
            ? resolvedSets.length
            : (log['sets_completed'] as num?)?.toInt() ??
                (log['set_number'] as num?)?.toInt() ??
                1;
        // APK Test #12.7 — preserve the row's authoring time instead of
        // re-stamping every backlog entry to NOW. The helper checks
        // created_at → completed_at → updated_at_ms → completed_at_ms →
        // IST date prefix from the Hive key. Without this, the founder's
        // 2026-05-05 / 2026-05-06 workouts (sat in Hive ~24h waiting for
        // the silent-sync fix) would have uploaded with completed_at =
        // NOW, breaking the AI coach's date filters.
        final String completedAt = _resolveCompletedAt(
          log,
          dateKeyPrefix: date.isNotEmpty ? date : _dateFromKey(key),
          hiveKey: key,
        );

        // Audit 2026-05-12 P0-A — onConflict was 'id', but live schema has a
        // partial UNIQUE on (workout_log_id, exercise_id, set_number). When a
        // Hive key for the same exercise mutates (e.g. name re-normalize) the
        // deterministic `id` shifts, the natural unique trips first, and the
        // upsert raises 23505 + orphan sets accumulate in workout_log_sets
        // (per-set rows succeed in their own try-block). 31 errors over 24h
        // in production. Switch to the natural key so PostgREST merges instead
        // of inserting. The PK `id` is still UNIQUE but is no longer the
        // conflict target — duplicate rows from the legacy 'id' path become
        // unreachable but harmless (next sync overwrites the natural-key row).
        //
        // Bug a2b3c4 (APK Test #15.3) — duration_seconds aggregate. The
        // WorkoutWriteService Hive shape carries per-set durations inside
        // `sets[]` entries (`duration_sec` canonical; `duration_seconds`
        // legacy after restore). The pre-fix line `log['duration_seconds']`
        // resolved to null for every WriteService row → cloud column was
        // dead schema data. Consumers (receipt, train_screen,
        // weekly-report) all worked around by summing per-set rows from
        // workout_log_sets. Populate the aggregate so future analytics
        // queries joining workout_log_exercises directly see the correct
        // total seconds for timed/cardio exercises.
        final loggingType = log['logging_type'] as String?;
        final isTimedOrCardio =
            loggingType == 'timed' || loggingType == 'cardio';
        int aggregateDurationSecs = 0;
        if (isTimedOrCardio && resolvedSets.isNotEmpty) {
          for (final s in resolvedSets) {
            final raw =
                s['duration_sec'] ?? s['duration_seconds'];
            aggregateDurationSecs += (raw as num?)?.toInt() ?? 0;
          }
        }
        await _supabase.client.from('workout_log_exercises').upsert({
          'id': _deterministicId(key),
          'workout_log_id': workoutLogId,
          'user_id': userId,
          'exercise_id': exerciseId,
          'exercise_name': log['exercise_name'] ?? '',
          'logging_type': log['logging_type'],
          'set_number': summarySetCount,
          'reps': log['reps_completed'],
          'weight_kg': log['weight_kg'],
          'duration_seconds': aggregateDurationSecs,
          'distance_km': log['distance_km'],
          'is_pr': log['is_pr'] ?? false,
          'has_warmup_sets': log['has_warmup_sets'] ?? false,
          'completed_at': completedAt,
        }, onConflict: 'workout_log_id,exercise_id,set_number');

        // ── PER-SET ROWS (F4) ──
        // Upserts a row per set into `workout_log_sets`. Natural key is
        // (workout_log_id, exercise_id, set_number) → idempotent across
        // re-syncs and retries. Source: legacy `sets_detail` OR the new
        // WorkoutWriteService `sets` list (Plan A A-5).
        if (resolvedSets.isNotEmpty) {
          final rows = <Map<String, dynamic>>[];
          for (final sm in resolvedSets) {
            final setNum = (sm['set_number'] as num?)?.toInt();
            if (setNum == null) continue;
            rows.add({
              'user_id': userId,
              'workout_log_id': workoutLogId,
              'exercise_id': exerciseId,
              'set_number': setNum,
              'weight_kg': sm['weight_kg'],
              'reps': sm['reps'],
              'duration_secs': sm['duration_seconds'] ?? sm['duration_sec'],
              'distance_km': sm['distance_km'],
              'completed_at': completedAt,
            });
          }
          if (rows.isNotEmpty) {
            try {
              await _supabase.client
                  .from('workout_log_sets')
                  .upsert(rows, onConflict: 'workout_log_id,exercise_id,set_number');
            } catch (e, st) {
              debugPrint(
                  '[SyncService._syncExerciseLogs] per-set push failed key=$key: $e');
              // audit-2026-05-11 H-42 — telemetry pair.
              unawaited(ErrorTelemetry.recordNonFatal(e, st,
                  reason: 'sync_service_if_7'));
              try {
                await _reportSyncFailure(opType: 'upsert_workout_log_sets', error: e);
              } catch (_) {}
            }
          }
        }
      } catch (e, st) {
        debugPrint('[SyncService._syncExerciseLogs] Failed key=$key: $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_catch_5'));
        try {
          await _reportSyncFailure(opType: 'upsert_exercise_log', error: e);
        } catch (_) {}
      }
    }
  }

  /// APK Test #12.7 — Preserve original Hive timestamp when projecting
  /// to a cloud row. Returns an ISO-8601 UTC string that prefers the
  /// real authoring time over `DateTime.now()` so backlog flushes don't
  /// re-stamp every old workout to today's date.
  ///
  /// Resolution order (most authoritative first):
  /// 1. `created_at` (string ISO) — already-canonical timestamp
  /// 2. `completed_at` (string ISO) — older paths used this name
  /// 3. `updated_at_ms` (int millisecondsSinceEpoch) — WorkoutWriteService
  /// 4. `completed_at_ms` (int millisecondsSinceEpoch) — markCompleted /
  ///    NutritionWriteService
  /// 5. `logged_at` (string ISO) — alternate naming in some legacy paths
  /// 6. `dateKeyPrefix` argument — IST date parsed from the Hive key
  ///    (`exlog_2026-05-05_<hash>` → `2026-05-05`); rendered as the
  ///    start of that IST day in UTC (-05:30 offset → 18:30Z prev day)
  ///    so the cloud `date::date` extraction still lands on the right
  ///    IST date for downstream filters.
  /// 7. Fallback: `DateTime.now().toUtc().toIso8601String()` and emit a
  ///    debug log + telemetry event so we know we hit the dead branch.
  String _resolveCompletedAt(
    Map<String, dynamic> row, {
    String? dateKeyPrefix,
    String? hiveKey,
  }) {
    // 1 / 2 / 5 — string ISO timestamps. Reject empty strings (a stale
    // restore loop wrote `''` into Hive at one point).
    for (final field in const ['created_at', 'completed_at', 'logged_at']) {
      final v = row[field];
      if (v is String && v.isNotEmpty) return v;
    }
    // 3 / 4 — millisecondsSinceEpoch ints written by the WriteServices.
    for (final field in const ['updated_at_ms', 'completed_at_ms']) {
      final v = row[field];
      if (v is num && v > 0) {
        return DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: false)
            .toUtc()
            .toIso8601String();
      }
    }
    // 6 — IST date prefix from the Hive key. Returns the IST midnight
    // for that date, expressed in UTC. `2026-05-05` → `2026-05-04T18:30:00Z`
    // which falls back to `2026-05-05` after IST shift on the cloud.
    if (dateKeyPrefix != null && dateKeyPrefix.length >= 10) {
      try {
        final iso = '${dateKeyPrefix.substring(0, 10)}T00:00:00+05:30';
        final parsed = DateTime.tryParse(iso);
        if (parsed != null) {
          return parsed.toUtc().toIso8601String();
        }
      } catch (_) {/* fall through */}
    }
    // 7 — true last-resort. Telemetry + debug log so we can spot the
    // dead branch in production.
    debugPrint(
      '[SyncService._resolveCompletedAt] fallback to NOW for key=$hiveKey '
      '(no created_at / completed_at / *_ms / dateKeyPrefix found)',
    );
    ErrorTelemetry.logEvent(
      'sync_completed_at_fallback',
      message: 'hiveKey=${hiveKey ?? '<unknown>'}',
    );
    return DateTime.now().toUtc().toIso8601String();
  }

  /// Extract the `YYYY-MM-DD` prefix from a Hive key shaped like
  /// `exlog_2026-05-05_<hash>` or `wlog_2026-05-05`. Returns null if the
  /// key is too short or doesn't match (legacy timestamp-suffixed keys
  /// like `wlog_1775500200000` will fail this and fall through to other
  /// fields in `_resolveCompletedAt`).
  String? _dateFromKey(String? key) {
    if (key == null) return null;
    // Skip the prefix (`exlog_` / `wlog_`).
    final firstUnderscore = key.indexOf('_');
    if (firstUnderscore < 0 || firstUnderscore + 11 > key.length) return null;
    final candidate = key.substring(firstUnderscore + 1, firstUnderscore + 11);
    if (candidate.length != 10) return null;
    if (candidate[4] != '-' || candidate[7] != '-') return null;
    return candidate;
  }

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
      } catch (e, st) {
        debugPrint('[SyncService._syncScheduleCompletions] Failed key=$key: $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_for_2'));
        try {
          await _reportSyncFailure(opType: 'upsert_schedule_completion', error: e);
        } catch (_) {}
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
        // Audit 2026-05-12 P0-B — onConflict was 'id', but live schema has a
        // partial UNIQUE on (user_id, date, meal_type). When client-side
        // dedup key rotates (e.g. meal renamed) the natural unique trips
        // first, raising 23505 + per-item rows orphan. 16 errors over 24h
        // in production. Switch to natural key so PostgREST merges instead
        // of failing.
        await _supabase.client.from("nutrition_logs").upsert(
          parentPayload,
          onConflict: "user_id,date,meal_type",
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
              // Per-item projection — schema-matched. nutrition_log_items
              // currently has columns: id, log_id, food_id, food_name,
              // quantity_g, calories, protein, carbs, fat, created_at.
              // `fiber` is not yet a column on this table (a future
              // migration will add it for parity with nutrition_logs);
              // we deliberately skip it here so the upsert doesn't 400.
              // Plan C-4 (Test #6): close obs #23 by making sure every
              // Hive nlog_* row produces N nutrition_log_items rows on
              // sync — verified in test/nutrition_write_service/
              // logMeal_creates_logs_and_items_atomically_test.dart.
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
            } catch (itemErr, st) {
              debugPrint('[SyncService._syncNutritionLogs] item $i: $itemErr');
              // audit-2026-05-11 H-42 — telemetry pair.
              unawaited(ErrorTelemetry.recordNonFatal(itemErr, st,
                  reason: 'sync_service_for_3'));
              try {
                await _reportSyncFailure(opType: 'upsert_nutrition_log_item', error: itemErr);
              } catch (_) {}
            }
          }
        }
      } catch (e, st) {
        debugPrint('[SyncService._syncNutritionLogs] $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_catch_6'));
        try {
          await _reportSyncFailure(opType: 'upsert_nutrition_log', error: e);
        } catch (_) {}
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
    } catch (e, st) {
      debugPrint('[SyncService.syncWeightNow] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_sync_weight_now'));
      try {
        await _reportSyncFailure(opType: 'sync_weight_now', error: e);
      } catch (_) {}
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
        try {
          await _supabase.client.from('sleep_logs').upsert({
            'id': _deterministicId('sleep_logs_$dateStr'),
            'user_id': userId,
            'date': dateStr,
            'duration_hrs': hours,
            if (log['quality'] != null) 'quality': log['quality'],
            'created_at': log['created_at'] ?? DateTime.now().toIso8601String(),
          }, onConflict: 'id');
        } catch (e, st) {
          debugPrint('[SyncService.syncSleepNow] list-item $dateStr: $e');
          // audit-2026-05-11 H-42 — telemetry pair.
          unawaited(ErrorTelemetry.recordNonFatal(e, st,
              reason: 'sync_service_for_4'));
          try {
            await _reportSyncFailure(opType: 'upsert_sleep_log_chat', error: e);
          } catch (_) {}
        }
      }
    } catch (e, st) {
      debugPrint('[SyncService.syncSleepNow] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_catch_7'));
      try {
        await _reportSyncFailure(opType: 'sync_sleep_now', error: e);
      } catch (_) {}
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
    } catch (e, st) {
      debugPrint('[SyncService.syncMeasurementsNow] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_sync_measurements_now'));
      try {
        await _reportSyncFailure(opType: 'sync_measurements_now', error: e);
      } catch (_) {}
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
      } catch (e, st) {
        debugPrint('[SyncService._syncWeightLogs] $key: $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_for_5'));
        try {
          await _reportSyncFailure(opType: 'upsert_weight_log', error: e);
        } catch (_) {}
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
      } catch (e, st) {
        debugPrint('[SyncService._syncMeasurements] $key: $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_for_6'));
        try {
          await _reportSyncFailure(opType: 'upsert_body_measurement', error: e);
        } catch (_) {}
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
      } catch (e, st) {
        debugPrint('[SyncService._syncSleepLogs] $key: $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_for_7'));
        try {
          await _reportSyncFailure(opType: 'upsert_sleep_log', error: e);
        } catch (_) {}
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
      } catch (e, st) {
        debugPrint('[SyncService._syncStepsLogs] $key: $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_for_8'));
        try {
          await _reportSyncFailure(opType: 'upsert_daily_steps', error: e);
        } catch (_) {}
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
      } catch (e, st) {
        debugPrint('[SyncService._syncUrineColorLogs] $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_for_9'));
        try {
          await _reportSyncFailure(opType: 'upsert_urine_color_log', error: e);
        } catch (_) {}
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
      } catch (e, st) {
        debugPrint('[SyncService._syncWaterLogs] $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_for_10'));
        try {
          await _reportSyncFailure(opType: 'upsert_water_log', error: e);
        } catch (_) {}
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
      if (weekStart.isEmpty) continue;
      // APK Test #12.7 — explicit projection instead of `...data` spread.
      // Cloud `streaks` schema has: id, user_id, week_start,
      // workouts_planned, workouts_completed, is_streak_maintained,
      // created_at. The Hive row carries extras (`local_id` from the
      // train_provider write, `source: 'cloud_restore'` from
      // `_restoreStreaks`) that DON'T exist on the cloud table —
      // sending them returned `Could not find the 'source' column of
      // 'streaks'` (PGRST204) on every sync.
      try {
        final payload = <String, dynamic>{
          'id': _deterministicId('streak_${userId}_$weekStart'),
          'user_id': userId,
          'week_start': weekStart,
          if (data['workouts_planned'] != null)
            'workouts_planned': data['workouts_planned'],
          if (data['workouts_completed'] != null)
            'workouts_completed': data['workouts_completed'],
          if (data['is_streak_maintained'] != null)
            'is_streak_maintained': data['is_streak_maintained'],
          if (data['created_at'] != null) 'created_at': data['created_at'],
        };
        await _supabase.client
            .from('streaks')
            .upsert(payload, onConflict: 'user_id,week_start');
      } catch (e, st) {
        debugPrint('[SyncService._syncStreaks] $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_for_11'));
        try {
          await _reportSyncFailure(opType: 'upsert_streak', error: e);
        } catch (_) {}
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
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_sync_profile_now'));
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
  /// Called fire-and-forget from [SavedMealsNotifier.relogSavedMeal] so that the
  /// counter stays in sync with the cloud copy. The private [_syncSavedMeals] does
  /// the actual upsert work; this is the public wrapper that resolves the user-id
  /// and delegates.
  Future<void> syncSavedMealsNow() async {
    try {
      final userId = _supabase.currentUser?.id;
      if (userId == null) return;
      await _syncSavedMeals(userId);
    } catch (e, st) {
      debugPrint('[SyncService.syncSavedMealsNow] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_sync_saved_meals_now'));
      try {
        await _reportSyncFailure(opType: 'sync_saved_meals_now', error: e);
      } catch (_) {}
    }
  }

  /// Immediately pushes user_progress to Supabase (total_workouts_done, streaks, etc.).
  /// Called fire-and-forget after every workout completion.
  Future<void> syncProgressNow() async {
    try {
      final userId = _supabase.currentUser?.id;
      if (userId == null) return;
      await _syncUserProgress(userId);
    } catch (e, st) {
      debugPrint('[SyncService.syncProgressNow] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_sync_progress_now'));
      try {
        await _reportSyncFailure(opType: 'sync_progress_now', error: e);
      } catch (_) {}
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
      if (_hasValue(p['injuries'])) 'injuries': p['injuries'] is List ? p['injuries'] : <String>[],
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
      if (_hasValue(p['preferred_workout_time']))
        'preferred_workout_time': p['preferred_workout_time'],
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
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_put_if_present'));
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
          } catch (e, st) {
            debugPrint(
              '[SyncService._syncCustomItems] exercise '
              '"${payload['name']}" key=$key: $e',
            );
            // audit-2026-05-11 H-42 — telemetry pair.
            unawaited(ErrorTelemetry.recordNonFatal(e, st,
                reason: 'sync_service_if_8'));
            try {
              await _reportSyncFailure(opType: 'upsert_custom_exercise', error: e);
            } catch (_) {}
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
          } catch (e, st) {
            debugPrint(
              '[SyncService._syncCustomItems] food '
              '"${payload['name']}" key=$key: $e',
            );
            // audit-2026-05-11 H-42 — telemetry pair.
            unawaited(ErrorTelemetry.recordNonFatal(e, st,
                reason: 'sync_service_if_9'));
            try {
              await _reportSyncFailure(opType: 'upsert_custom_food', error: e);
            } catch (_) {}
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
          } catch (e, st) {
            debugPrint('[SyncService._syncCustomItems] legacy exercise: $e');
            // audit-2026-05-11 H-42 — telemetry pair.
            unawaited(ErrorTelemetry.recordNonFatal(e, st,
                reason: 'sync_service_if_10'));
            try {
              await _reportSyncFailure(opType: 'upsert_custom_exercise_legacy', error: e);
            } catch (_) {}
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
          } catch (e, st) {
            debugPrint('[SyncService._syncCustomItems] legacy food: $e');
            // audit-2026-05-11 H-42 — telemetry pair.
            unawaited(ErrorTelemetry.recordNonFatal(e, st,
                reason: 'sync_service_if_11'));
            try {
              await _reportSyncFailure(opType: 'upsert_custom_food_legacy', error: e);
            } catch (_) {}
          }
        }
      }

      await _setTimestamp(_lastCustomSyncKey);
    } catch (e, st) {
      debugPrint('[SyncService._syncCustomItems] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_catch_8'));
      try {
        await _reportSyncFailure(opType: 'sync_custom_items', error: e);
      } catch (_) {}
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
        // APK Test #12.8 / Bug #1 — Hive key MUST mirror what
        // [WorkoutWriteService.wlogKey] produces (`wlog_<istDateStr>`)
        // so a re-restore replaces the same row instead of creating a
        // sibling keyed by raw millisecond timestamp.
        final dateStr =
            (map['date'] as String?) ??
                (loggedAt.length >= 10
                    ? loggedAt.substring(0, 10)
                    : istDateStr(DateTime.now()));
        final logId = 'wlog_$dateStr';

        await _hive.workoutBox.put(logId, {
          'id': logId,
          'type': 'workout_log',
          'workout_name': map['exercise_name'] ?? 'Workout',
          'date': dateStr,
          'completed_at': loggedAt,
          'sets_completed': map['sets_completed'],
          'duration_seconds': map['duration_seconds'],
          'source': 'cloud_restore',
        });
      }
    } catch (e, st) {
      debugPrint('[SyncService._restoreWorkoutLogs] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_for_12'));
      try {
        await _reportSyncFailure(opType: 'restore_workout_logs', error: e);
      } catch (_) {}
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
      } catch (e, st) {
        // Non-fatal — falls back to summary-only restore.
        debugPrint('[SyncService._restoreExerciseLogs] per-set fetch failed: $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_for_13'));
        try {
          await _reportSyncFailure(opType: 'restore_exercise_log_sets_fetch', error: e);
        } catch (_) {}
      }

      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final completedAt = map['completed_at'] as String? ?? '';
        final name = map['exercise_name'] as String? ?? '';
        // APK Test #12.6 IST sweep — see feedback_use_ist_throughout.md
        final dateStr = completedAt.length >= 10
            ? completedAt.substring(0, 10)
            : istDateStr(DateTime.now());
        // APK Test #12.8 / Bug #1 — Hive key MUST mirror what
        // [WorkoutWriteService.exlogKey] produces. Pre-fix used
        // `exlog_<rawMs>_<name.hashCode>` which (a) drifts off the
        // IST date contract and (b) skipped lowercase+trim normalization,
        // so a re-restore created a sibling row alongside the local
        // exlog written by the WriteService — founder ended up with
        // 30+ exlog entries for one workout day on May 4.
        final nameNormalized = name.toLowerCase().trim();
        final logId = 'exlog_${dateStr}_${nameNormalized.hashCode}';

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
        // D2 (Test #11): write canonical Hive field name `set_number` (total
        // completed sets) instead of legacy `sets_completed`. Cloud column
        // `set_number` maps 1:1 — semantics unchanged, only the Hive key fixed.
        if (map['set_number'] != null) {
          logMap['set_number'] = map['set_number'];
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
          // D2 (Test #11): write canonical Hive field name `sets` (per-set
          // Map list) instead of legacy `sets_detail`. Consumers (receipt
          // rendering, AI snapshot, PR rescan) all key off `sets` per
          // CLAUDE.md §15 "Hive field-name contract".
          logMap['sets'] = setsDetail;

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
    } catch (e, st) {
      debugPrint('[SyncService._restoreExerciseLogs] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_for_14'));
      try {
        await _reportSyncFailure(opType: 'restore_exercise_logs', error: e);
      } catch (_) {}
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
    } catch (e, st) {
      debugPrint('[SyncService._restoreScheduleCompletions] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_if_12'));
      try {
        await _reportSyncFailure(opType: 'restore_schedule_completions', error: e);
      } catch (_) {}
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

      // H-13 (audit-2026-05-11) — write PER-KEY entries so the
      // writer (`_syncCustomItems`) + every UI reader
      // (`your_foods_section`, `train_screen`, `workout_schedule_service`)
      // can see them. Pre-fix this wrote to the legacy
      // `custom_exercises` LIST key, which no current consumer reads
      // → restored items vanished from getCustomExercises() and
      // never re-synced to cloud (since _syncCustomItems scans
      // `custom_exercise_*` per-key only).
      //
      // Local key uses cloud row's `id` (deterministic v5 UUID) so
      // repeated restores on the same device don't duplicate rows.
      // Dedup by name (case-insensitive) against existing per-key
      // entries already in customBox.
      final customBox = _hive.customBox;
      final existingNames = <String>{};
      for (final k in customBox.keys) {
        if (k is! String || !k.startsWith('custom_exercise_')) continue;
        final v = customBox.get(k);
        if (v is Map) {
          final n = (v['name'] as String? ?? '').toLowerCase().trim();
          if (n.isNotEmpty) existingNames.add(n);
        }
      }

      for (final item in items) {
        final name = (item['name'] as String? ?? '').toLowerCase().trim();
        if (name.isEmpty) continue;
        if (existingNames.contains(name)) continue;
        final id = (item['id'] as String?) ??
            'restore_${DateTime.now().microsecondsSinceEpoch}';
        await customBox.put('custom_exercise_$id', item);
        existingNames.add(name);
      }
    } catch (e, st) {
      debugPrint('[SyncService._restoreCustomExercises] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_for_15'));
      try {
        await _reportSyncFailure(opType: 'restore_custom_exercises', error: e);
      } catch (_) {}
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

      // H-13 (audit-2026-05-11) — same per-key restore as
      // _restoreCustomExercises above. Local key uses cloud row's
      // `id` so repeated restores don't duplicate.
      final customBox = _hive.customBox;
      final existingNames = <String>{};
      for (final k in customBox.keys) {
        if (k is! String || !k.startsWith('custom_food_')) continue;
        final v = customBox.get(k);
        if (v is Map) {
          final n = (v['name'] as String? ?? '').toLowerCase().trim();
          if (n.isNotEmpty) existingNames.add(n);
        }
      }

      for (final item in items) {
        final name = (item['name'] as String? ?? '').toLowerCase().trim();
        if (name.isEmpty) continue;
        if (existingNames.contains(name)) continue;
        final id = (item['id'] as String?) ??
            'restore_${DateTime.now().microsecondsSinceEpoch}';
        await customBox.put('custom_food_$id', item);
        existingNames.add(name);
      }
    } catch (e, st) {
      debugPrint('[SyncService._restoreCustomFoods] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_for_16'));
      try {
        await _reportSyncFailure(opType: 'restore_custom_foods', error: e);
      } catch (_) {}
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
    } catch (e, st) {
      debugPrint('[SyncService._restoreWeightLogs] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_for_17'));
      try {
        await _reportSyncFailure(opType: 'restore_weight_logs', error: e);
      } catch (_) {}
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
        final cloudId = map['id'] as String? ?? '';
        if (cloudId.isEmpty) continue;

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

        // APK Test #12.8 / Bug #1 — derive deterministic local Hive key
        // from row data, NOT from the cloud UUID. Pre-fix the cloud
        // UUID was used directly as the Hive key — every restore wrote
        // a sibling row alongside the existing `nlog_<istDate>_<meal>_<hash>`
        // local row. NutritionWriteService.computeLogKey is the canonical
        // shape: `nlog_<istDate>_<mealType>_<itemsHash>`. We mirror its
        // 32-bit `Object.hashCode` of `name.toLowerCase().trim()|qty.toFixed(1)`
        // so the same row collapses on cloud→local round-trip.
        final mealType = (map['meal_type'] as String?) ?? 'meal';
        final dateForKey = (map['date'] as String?) ??
            ((map['created_at'] as String?)?.substring(0, 10) ??
                istDateStr(DateTime.now()));
        final localKey = _nlogKeyForRestore(
          dateStr: dateForKey,
          mealType: mealType,
          items: (map['items'] as List?) ?? const [],
        );
        map['id'] = localKey;
        map['log_key'] = localKey;
        await _hive.nutritionBox.put(localKey, map);
      }
    } catch (e, st) {
      debugPrint('[SyncService._restoreNutritionLogs] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_if_13'));
      try {
        await _reportSyncFailure(opType: 'restore_nutrition_logs', error: e);
      } catch (_) {}
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
    } catch (e, st) {
      debugPrint('[SyncService._restoreMeasurements] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_for_18'));
      try {
        await _reportSyncFailure(opType: 'restore_measurements', error: e);
      } catch (_) {}
    }
  }

  Future<void> _restoreUserProfile(String userId) async {
    try {
      final rows = await _supabase.client
          .from('user_profile')
          .select()
          .eq('user_id', userId)
          .limit(1);

      // APK Test #12.8 / Bug #2 — `full_name` + `email` live on
      // `public.users`, NOT on `user_profile`. Pre-fix the restore only
      // queried `user_profile`, so post-reinstall `userBox['profile']
      // ['full_name']` stayed null and home greeting rendered "USER".
      // Merge `users` columns into the same profile map.
      Map<String, dynamic> usersRow = const {};
      try {
        final u = await _supabase.client
            .from('users')
            .select('full_name, email')
            .eq('id', userId)
            .maybeSingle();
        if (u != null) {
          usersRow = Map<String, dynamic>.from(u);
        }
      } catch (e, st) {
        // Non-fatal — profile restore still proceeds with whatever the
        // user_profile row carries.
        debugPrint('[SyncService._restoreUserProfile] users select: $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_if_14'));
      }

      if (rows.isEmpty && usersRow.isEmpty) return;
      final cloud = rows.isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(rows.first as Map);
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
        // APK Test #12.8 / Bug #2 — `users` columns layered last so
        // canonical `full_name` + `email` always win when present.
        for (final e in usersRow.entries)
          if (e.value != null) e.key: e.value,
        // Stamp the canonical user id so cross-account isolation checks
        // (splash_screen profile-id-vs-session) keep working when only
        // the `users` row was found.
        'id': userId,
      };
      await _hive.userBox.put('profile', merged);
    } catch (e, st) {
      debugPrint('[SyncService._restoreUserProfile] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_catch_9'));
      try {
        await _reportSyncFailure(opType: 'restore_user_profile', error: e);
      } catch (_) {}
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
    } catch (e, st) {
      debugPrint('[SyncService._restoreUserProgress] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_restore_user_progress'));
      try {
        await _reportSyncFailure(opType: 'restore_user_progress', error: e);
      } catch (_) {}
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
    } catch (e, st) {
      debugPrint('[SyncService._restoreWaterLogs] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_if_15'));
      try {
        await _reportSyncFailure(opType: 'restore_water_logs', error: e);
      } catch (_) {}
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
    } catch (e, st) {
      debugPrint('[SyncService._restoreSleepLogs] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_for_19'));
      try {
        await _reportSyncFailure(opType: 'restore_sleep_logs', error: e);
      } catch (_) {}
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
    } catch (e, st) {
      debugPrint('[SyncService._restoreStepsLogs] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_for_20'));
      try {
        await _reportSyncFailure(opType: 'restore_steps_logs', error: e);
      } catch (_) {}
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
    } catch (e, st) {
      debugPrint('[SyncService._restoreStreaks] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_for_21'));
      try {
        await _reportSyncFailure(opType: 'restore_streaks', error: e);
      } catch (_) {}
    }
  }

  // ── Sync: Workout Plan + User Progress ─────────────────────

  /// Pushes the current workout plan (plan JSON + schedule entries + dates)
  /// to Supabase user_progress.plan_json so it can be restored on new device.
  Future<void> _syncWorkoutPlan(String userId) async {
    try {
      final workoutBox = _hive.workoutBox;

      final plan = workoutBox.get('current_plan');
      if (plan == null) return;

      final planStart = MigratedKey.read<String>('plan_start_date');
      final planEnd = MigratedKey.read<String>('plan_end_date');

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
    } catch (e, st) {
      debugPrint('[SyncService._syncWorkoutPlan] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_if_16'));
      try {
        await _reportSyncFailure(opType: 'sync_workout_plan', error: e);
      } catch (_) {}
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
    } catch (e, st) {
      debugPrint('[SyncService._syncUserProgress] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_sync_user_progress'));
      try {
        await _reportSyncFailure(opType: 'sync_user_progress', error: e);
      } catch (_) {}
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
        await MigratedKey.write('plan_start_date', planStart);
      }
      if (planEnd != null) {
        await MigratedKey.write('plan_end_date', planEnd);
      }
      if (schedules != null && schedules is Map) {
        for (final entry in schedules.entries) {
          final key = entry.key.toString();
          if (!key.startsWith('schedule_')) continue;
          // APK Test #12.9 — defensive merge: never clobber a local
          // `status:'completed'` with a stale `status:'planned'` from
          // the plan_json snapshot. Cloud-authoritative state (already
          // applied by `_restoreScheduledWorkouts` upstream OR persisted
          // by an earlier completion that hasn't been synced back into
          // plan_json) must survive a re-run of this method.
          final existing = _hive.workoutBox.get(key);
          final incoming = entry.value is Map
              ? Map<String, dynamic>.from(entry.value as Map)
              : entry.value;
          if (existing is Map && incoming is Map) {
            final existingMap = Map<String, dynamic>.from(existing);
            if (existingMap['status'] == 'completed') {
              // Preserve completed status + completed_at from local;
              // overlay other plan-snapshot fields (workout_name,
              // exercises[], type) which are still useful.
              final merged = Map<String, dynamic>.from(incoming);
              merged['status'] = 'completed';
              if (existingMap['completed_at'] != null) {
                merged['completed_at'] = existingMap['completed_at'];
              }
              await _hive.workoutBox.put(key, merged);
              continue;
            }
          }
          await _hive.workoutBox.put(key, incoming);
        }
      }
    } catch (e, st) {
      debugPrint('[SyncService._restoreWorkoutPlan] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_if_17'));
      try {
        await _reportSyncFailure(opType: 'restore_workout_plan', error: e);
      } catch (_) {}
    }
  }

  // ── Sync: Community Items (approved by 10+ users) ─────────

  /// Pulls approved community foods/exercises from Supabase into local Hive.
  /// Called on app launch to keep the local database growing.
  Future<void> syncCommunityItems() async {
    // H-14 (audit-2026-05-11) — paginate + apply a hard ceiling.
    // Pre-fix the queries had no `.limit()` or `.range()` so every
    // app launch downloaded the FULL approved community library
    // (potentially thousands of rows) over the user's cellular
    // connection. At 1000 community items a sync would burn ~500KB
    // of bandwidth per launch. Now: 500 rows per page, 10-page
    // ceiling (5000 rows max) for any single sync run.
    const int pageSize = 500;
    const int maxPages = 10;

    try {
      final lastSync = _hive.syncBox.get('last_community_sync');
      final sinceDate = lastSync != null
          ? DateTime.tryParse(lastSync.toString())?.toIso8601String()
          : '2020-01-01T00:00:00Z';
      final since = sinceDate ?? '2020-01-01T00:00:00Z';

      // Pull approved community foods — paginated.
      final foodBox = _hive.foodBox;
      for (int page = 0; page < maxPages; page++) {
        final from = page * pageSize;
        final to = from + pageSize - 1;
        final foods = await _supabase.client
            .from('user_custom_foods')
            .select()
            .eq('approved', true)
            .gte('created_at', since)
            .order('created_at', ascending: true)
            .range(from, to);
        if (foods.isEmpty) break;
        for (final row in foods) {
          final map = Map<String, dynamic>.from(row as Map);
          final id = map['id']?.toString();
          if (id != null && id.isNotEmpty && foodBox.get(id) == null) {
            map['source'] = 'community';
            await foodBox.put(id, map);
          }
        }
        if (foods.length < pageSize) break;
      }

      // Pull approved community exercises — paginated.
      final exerciseBox = _hive.exerciseBox;
      for (int page = 0; page < maxPages; page++) {
        final from = page * pageSize;
        final to = from + pageSize - 1;
        final exercises = await _supabase.client
            .from('user_custom_exercises')
            .select()
            .eq('approved_for_library', true)
            .gte('created_at', since)
            .order('created_at', ascending: true)
            .range(from, to);
        if (exercises.isEmpty) break;
        for (final row in exercises) {
          final map = Map<String, dynamic>.from(row as Map);
          final id = map['id']?.toString();
          if (id != null && id.isNotEmpty && exerciseBox.get(id) == null) {
            map['source'] = 'community';
            await exerciseBox.put(id, map);
          }
        }
        if (exercises.length < pageSize) break;
      }

      await _hive.syncBox.put('last_community_sync', DateTime.now().toIso8601String());
    } catch (e, st) {
      debugPrint('[SyncService.syncCommunityItems] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_for_22'));
      try {
        await _reportSyncFailure(opType: 'sync_community_items', error: e);
      } catch (_) {}
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
        // APK Test #12.8 / Bug #4 — drop `id` from the upsert payload
        // entirely. Pre-fix Test #12.7 derived `id` from (user_id, name)
        // and passed it to the upsert with `onConflict: 'user_id,name'`.
        // Cloud's pre-migration-050 rows have DIFFERENT id values (the
        // `keepers` from the migration 050 dedup). On conflict Postgres
        // tried to UPDATE the existing row's id to the new derived
        // value → blocked by `template_exercises_template_id_fkey`
        // (and the same on `scheduled_workouts.template_id`,
        // `workout_logs.template_id`) → 23503 fatal. Founder log
        // showed 8 such errors in 10s.
        //
        // Fix: omit `id` so PostgREST's upsert keeps the existing id on
        // conflict (UPDATE) and uses the column default `gen_random_uuid()`
        // on first INSERT. Then SELECT the real cloud id by (user_id,
        // name) BEFORE inserting child template_exercises rows so they
        // FK to the correct parent.
        final tmplName = (tmpl['name'] as String?)?.trim() ?? 'Untitled';
        final exercises = tmpl['exercises'] as List? ?? [];

        // Upsert template header — `id` deliberately omitted.
        await _supabase.client.from('workout_templates').upsert({
          'user_id': userId,
          'name': tmplName,
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
        }, onConflict: 'user_id,name');

        // SELECT the real cloud id post-upsert so child rows FK
        // correctly. Pre-fix used `_deterministicId('tmpl|user|name')`
        // which only matched on greenfield first-insert; pre-existing
        // rows kept their migration-050 keeper id and the FK lookup
        // mismatched → 23503.
        String? cloudTmplId;
        try {
          final parentRow = await _supabase.client
              .from('workout_templates')
              .select('id')
              .eq('user_id', userId)
              .eq('name', tmplName)
              .maybeSingle();
          cloudTmplId = parentRow?['id'] as String?;
        } catch (idErr, st) {
          debugPrint(
              '[SyncService._syncWorkoutTemplates] parent id lookup: $idErr');
          // audit-2026-05-11 H-42 — telemetry pair.
          unawaited(ErrorTelemetry.recordNonFatal(idErr, st,
              reason: 'sync_service_for_23'));
        }
        if (cloudTmplId == null || cloudTmplId.isEmpty) {
          // Without a valid parent id we can't push children safely.
          // Skip silently — next sync will retry.
          continue;
        }

        // Backlog #2 (post-Test-#15) — switched from DELETE-then-INSERT
        // to UPSERT now that migration 051 added UNIQUE (template_id,
        // order_index). Each row is independently upserted; a network
        // blip on row N leaves rows 0..N-1 + N+1..end intact (latter are
        // upserts, not inserts, so they update unchanged rows). Next
        // sync retries row N alone. No "torn" template state.
        //
        // closes-diagnose: 2026-05-10-template-exercises-upsert-a8b2c7
        // (migration 051 header has the full rationale).
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
              // APK Test #12.8 / Bug #4 — `id` omitted; child UUID
              // generated by cloud default on first insert. On conflict
              // (template_id, order_index), the existing row's id is
              // preserved and other fields are updated.
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
            }, onConflict: 'template_id,order_index');
          } catch (exErr, st) {
            debugPrint('[SyncService._syncWorkoutTemplates] exercise $i: $exErr');
            // audit-2026-05-11 H-42 — telemetry pair.
            unawaited(ErrorTelemetry.recordNonFatal(exErr, st,
                reason: 'sync_service_for_24'));
            try {
              await _reportSyncFailure(opType: 'upsert_template_exercise', error: exErr);
            } catch (_) {}
          }
        }

        // APK Test #15.1 / Bug B — vacuum the tail. Migration 051
        // (Test #15 / Backlog #2) added UNIQUE(template_id, order_index)
        // and switched DELETE-then-INSERT → upsert with onConflict.
        // That fix preserved no-torn-state on partial failure but
        // introduced a NEW failure mode: when a template shrinks
        // (15 exercises → 5), only slots 0..4 are upserted; slots
        // 5..14 from the prior version remain orphaned in cloud.
        // Restore pulls all 15, founder sees 15-exercise "triplicates"
        // on his Back Day A / Leg Day A / Push Day templates.
        //
        // Tail vacuum bounds the cloud row count to exactly the local
        // exercises.length. One round-trip per template. Idempotent.
        // Network failure on the DELETE leaves stale tail rows (same
        // as today's status quo before this commit) — no regression.
        //
        // closes-diagnose: 2026-05-12-template-exercises-tail-vacuum-b3c8d2
        try {
          await _supabase.client
              .from('template_exercises')
              .delete()
              .eq('template_id', cloudTmplId)
              .gte('order_index', exercises.length);
        } catch (vacErr, st) {
          debugPrint(
              '[SyncService._syncWorkoutTemplates] tail vacuum failed: $vacErr');
          unawaited(ErrorTelemetry.recordNonFatal(vacErr, st,
              reason: 'sync_template_exercises_tail_vacuum'));
          // Non-fatal — same stale-tail state as pre-fix.
        }
      } catch (e, st) {
        debugPrint('[SyncService._syncWorkoutTemplates] $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_catch_10'));
        try {
          await _reportSyncFailure(opType: 'upsert_workout_template', error: e);
        } catch (_) {}
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

      // APK Test #12.9 — collect canonical Hive keys we're about to
      // write so we can sweep stragglers afterward. Pre-12.9 the user's
      // workoutBox accumulated stale `tmpl_<ms>` and `tmpl_<id.hash>`
      // keys from earlier APK builds with broken restore-key formulas
      // (or local saves never pushed to cloud). Logout-login DOES wipe
      // the namespaced box on disk, but in-place APK upgrades over a
      // populated box don't, and any other future writer that puts a
      // template-shaped Hive entry would also accumulate. Sweep
      // ensures the templates list always matches the cloud set
      // exactly after restore.
      final canonicalKeys = <String>{};

      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final id = map['id'] as String? ?? '';
        if (id.isEmpty) continue;
        // APK Test #12.8 / Bug #1 — derive deterministic Hive key from
        // (lower(name)) NOT from the cloud UUID hash. Pre-fix
        // `'tmpl_${id.hashCode}'` produced a Hive key that didn't
        // collide with the locally-saved `tmpl_<ms>` key on the same
        // template, doubling the templates list on every cold restore.
        // (user_id, name) is the canonical identity per migration 050;
        // we omit user_id from the key since the userBox is already
        // user-scoped and the migrator handles cross-user isolation.
        final tmplName = (map['name'] as String? ?? '').toLowerCase().trim();
        final hiveKey = tmplName.isEmpty
            ? 'tmpl_${id.hashCode.toUnsigned(32).toRadixString(16)}'
            : 'tmpl_${tmplName.hashCode.toUnsigned(32).toRadixString(16)}';
        canonicalKeys.add(hiveKey);
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
            // APK Test #15.1 / Bug A — `sets` MUST be int (Hive readers
            // cast as int?). Pre-fix this stringified prescribed_sets,
            // which then flowed through _normalizeExercises unchanged
            // into the schedule entry, crashing home_screen._buildTodayRow
            // with `type 'String' is not a subtype of type 'int?'` when
            // the founder scheduled a custom template for today.
            // closes-diagnose: 2026-05-12-schedule-int-coercion-a2f9e1
            'sets': _coerceInt(ex['prescribed_sets'], fallback: 3),
            // `reps` stays String — exercise library uses ranges like
            // "8-12" so a single int can't represent all values.
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

      // APK Test #12.9 — sweep stale `tmpl_*` keys not in canonical
      // cloud set. Skipped when cloud returned zero rows (defensive:
      // a transient query failure could otherwise wipe local-only
      // unsynced templates). The skip is safe because if cloud truly
      // has zero templates, the user has nothing to lose by keeping
      // local stragglers visible until next successful sync.
      if (canonicalKeys.isNotEmpty) {
        final stale = <String>[];
        for (final k in _hive.workoutBox.keys) {
          if (k is String &&
              k.startsWith('tmpl_') &&
              !canonicalKeys.contains(k)) {
            stale.add(k);
          }
        }
        if (stale.isNotEmpty) {
          await _hive.workoutBox.deleteAll(stale);
          unawaited(ErrorTelemetry.logEvent(
            'templates_stale_keys_swept',
            message:
                'count=${stale.length} canonical=${canonicalKeys.length}',
          ));
        }
      }
    } catch (e, st) {
      debugPrint('[SyncService._restoreWorkoutTemplates] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_if_18'));
      try {
        await _reportSyncFailure(opType: 'restore_workout_templates', error: e);
      } catch (_) {}
    }
  }

  // ── Gap 3: Scheduled Workouts ──────────────────────────────

  /// Pushes full scheduled workout definitions to Supabase.
  /// Complements _syncScheduleCompletions which only pushes completed status.
  ///
  /// APK Test #14 / Bug B.1 — self-healing template_id resolution.
  /// Pre-fix used `_deterministicId(rawTemplateId)` to coerce the Hive
  /// `tmpl_<ms>` key into a v5 UUID. But cloud `workout_templates.id` is
  /// generated by `gen_random_uuid()` post-migration-050 keeper-merge:
  /// the v5 hash NEVER matches the cloud id, so every push that carried
  /// a non-null template_id slammed into `scheduled_workouts_template_id_fkey`
  /// 23503. Founder log on 2026-05-10 12:45 UTC: 10 such errors in 5s.
  ///
  /// New flow: lookup-by-(user_id, name) against cloud, mirroring how
  /// `_syncWorkoutTemplates` already resolves the cloud id post-upsert
  /// (lines 3499-3511). Per-call cache so a week's worth of schedule
  /// rows sharing the same template don't N×SELECT. On 23503, retry
  /// once after re-running `_syncWorkoutTemplates(userId)`; on second
  /// 23503, fall back to `template_id: null` so `status='completed'`
  /// + `completed_at` still reach cloud.
  ///
  /// Diagnose: docs/diagnoses/2026-05-10-fk-violation-saturday-c8e4a1.md
  Future<void> _syncScheduledWorkouts(String userId) async {
    final workoutBox = _hive.workoutBox;

    // APK Test #14 / Bug B.1 — per-call cache of template_name → cloud
    // UUID. A week's worth of schedule rows that share the same template
    // would otherwise N×SELECT. `null` cached values mark known-misses
    // so we don't re-query for an orphan template repeatedly.
    final templateNameToCloudId = <String, String?>{};

    // Tracks whether we've already attempted a one-shot
    // `_syncWorkoutTemplates(userId)` recovery this call. Bounds work
    // to one re-push regardless of how many schedule rows hit 23503.
    bool templatesResynced = false;

    /// Resolve the cloud `workout_templates.id` for a Hive `tmpl_<ms>`
    /// raw key by reading the local template's name and SELECTing the
    /// cloud row that matches `(user_id, lower-trim name)`.
    ///
    /// Returns null when the local template is missing (template was
    /// deleted upstream), the local template has no name, or the cloud
    /// SELECT errors. Cache hits (including null) short-circuit.
    Future<String?> resolveCloudTemplateId(String? rawHiveTemplateId) async {
      if (rawHiveTemplateId == null || rawHiveTemplateId.isEmpty) return null;

      // Look up the local template Map in workoutBox to extract its
      // name. Falls back to entry-level workout_name if the local row
      // is gone (deleted upstream); cloud lookup uses the same
      // (user_id, name) onConflict as `_syncWorkoutTemplates`.
      String? tmplName;
      final localTmpl = workoutBox.get(rawHiveTemplateId);
      if (localTmpl is Map) {
        final n = (localTmpl['name'] as String?)?.trim();
        if (n != null && n.isNotEmpty) tmplName = n;
      }
      if (tmplName == null) return null;

      // Cache key on the trimmed name — cloud `onConflict` is
      // `user_id,name` so identical names dedupe correctly.
      if (templateNameToCloudId.containsKey(tmplName)) {
        return templateNameToCloudId[tmplName];
      }

      try {
        final parentRow = await _supabase.client
            .from('workout_templates')
            .select('id')
            .eq('user_id', userId)
            .eq('name', tmplName)
            .maybeSingle();
        final cloudId = parentRow?['id'] as String?;
        templateNameToCloudId[tmplName] = cloudId;
        return cloudId;
      } catch (e, st) {
        debugPrint(
            '[SyncService._syncScheduledWorkouts] resolveCloudTemplateId($tmplName): $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_if_19'));
        templateNameToCloudId[tmplName] = null;
        return null;
      }
    }

    for (final key in workoutBox.keys) {
      if (key is! String || !key.startsWith('schedule_')) continue;
      final raw = workoutBox.get(key);
      if (raw is! Map) continue;
      final entry = Map<String, dynamic>.from(raw);
      final date = entry['date'] as String?;
      if (date == null) continue;

      try {
        final parsedDate = DateTime.tryParse(date);
        final rawTemplateId = entry['template_id']?.toString();

        // APK Test #14 / Bug B.1 — resolve cloud template_id by NAME
        // lookup. Pre-fix used `_deterministicId(rawTemplateId)` which
        // hashed the local Hive key — never matched cloud's
        // gen_random_uuid() id, so every push 23503'd. See
        // docs/diagnoses/2026-05-10-fk-violation-saturday-c8e4a1.md.
        String? cloudTemplateId = await resolveCloudTemplateId(rawTemplateId);

        // APK Test #12.7 — sanitize completed_at. An empty string in
        // Hive (legacy code path) reaches PostgREST as `""` and Postgres
        // 22007s with `invalid input syntax for type timestamp with time
        // zone: ""`. Send null when empty/missing; pass through real
        // ISO strings unchanged.
        final rawCompletedAt = entry['completed_at'];
        final completedAt = (rawCompletedAt is String && rawCompletedAt.isNotEmpty)
            ? rawCompletedAt
            : null;

        Map<String, dynamic> payload(String? tmplId) => <String, dynamic>{
              'user_id': userId,
              if (tmplId != null) 'template_id': tmplId,
              'scheduled_date': date,
              'week_number': entry['week'] ?? entry['week_number'],
              'day_of_week': parsedDate?.weekday ?? entry['day_of_week'],
              'status': entry['status'] ?? 'planned',
              'completed_at': completedAt,
            };

        try {
          await _supabase.client
              .from('scheduled_workouts')
              .upsert(payload(cloudTemplateId),
                  onConflict: 'user_id,scheduled_date');
        } on Object catch (firstErr) {
          // APK Test #14 / Bug B.1 — distinguish 23503 (FK violation on
          // template_id) from other failures. PostgrestException's code
          // is exposed via toString(); auth_provider.dart:483 uses the
          // same `eStr.contains('23503')` convention.
          final errStr = firstErr.toString();
          final isFkViolation = errStr.contains('23503');
          if (!isFkViolation) {
            rethrow;
          }

          // First-time-this-call: re-run `_syncWorkoutTemplates` to
          // ensure the parent row exists, then re-resolve and retry.
          if (!templatesResynced) {
            templatesResynced = true;
            try {
              await _syncWorkoutTemplates(userId);
            } catch (resyncErr, st) {
              debugPrint(
                  '[SyncService._syncScheduledWorkouts] templates resync: $resyncErr');
              // audit-2026-05-11 H-42 — telemetry pair.
              unawaited(ErrorTelemetry.recordNonFatal(resyncErr, st,
                  reason: 'sync_service_if_20'));
            }
            // Clear cache so the post-resync lookup hits cloud fresh
            // instead of returning the stale null/miss.
            templateNameToCloudId.clear();
            cloudTemplateId = await resolveCloudTemplateId(rawTemplateId);

            try {
              await _supabase.client
                  .from('scheduled_workouts')
                  .upsert(payload(cloudTemplateId),
                      onConflict: 'user_id,scheduled_date');
              // Recovery succeeded — log telemetry event.
              try {
                await _reportSyncFailure(
                  opType: 'scheduled_workout_fk_recovered',
                  error: 'tmpl=$rawTemplateId date=$date',
                );
              } catch (_) {}
              continue;
            } on Object catch (secondErr) {
              final secondStr = secondErr.toString();
              if (!secondStr.contains('23503')) {
                rethrow;
              }
              // Fall through to null-template fallback below.
            }
          }

          // Second 23503 (or repeat-FK after a prior row already used
          // the recovery slot): null-template fallback. Status +
          // completed_at still reach cloud so the calendar tick survives;
          // template attribution is the only loss.
          try {
            await _supabase.client
                .from('scheduled_workouts')
                .upsert(payload(null),
                    onConflict: 'user_id,scheduled_date');
            try {
              await _reportSyncFailure(
                opType: 'scheduled_workout_template_orphaned',
                error: 'tmpl=$rawTemplateId date=$date',
              );
            } catch (_) {}
          } catch (fallbackErr, st) {
            // Fallback itself failed — surface as the original op_type
            // so retry-queue accounting stays consistent.
            debugPrint(
                '[SyncService._syncScheduledWorkouts] fallback upsert: $fallbackErr');
            // audit-2026-05-11 H-42 — telemetry pair.
            unawaited(ErrorTelemetry.recordNonFatal(fallbackErr, st,
                reason: 'sync_service_catch_11'));
            try {
              await _reportSyncFailure(
                  opType: 'upsert_scheduled_workout', error: fallbackErr);
            } catch (_) {}
          }
        }
      } catch (e, st) {
        debugPrint('[SyncService._syncScheduledWorkouts] $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_catch_12'));
        try {
          await _reportSyncFailure(opType: 'upsert_scheduled_workout', error: e);
        } catch (_) {}
      }
    }
  }

  /// Restores scheduled workouts from Supabase (supplement to plan restore).
  ///
  /// APK Test #15.3 / Bug 4a (closes-diagnose: 9e2c1a) — cloud
  /// `scheduled_workouts` has NO `workout_name` / NO `exercises`
  /// columns (verified live against `dedsavbjuwgarrhphgnl`). The
  /// display content for a template-assigned day lives in
  /// `workout_templates.name` + `template_exercises.*` and is only
  /// reachable via JOIN. Pre-fix this method pulled the bare cloud
  /// row, so on fresh-install restore the plan-generator default
  /// (`workout_name = "PUSH A"`) survived in Hive even when
  /// `template_id` pointed at the user's "Leg Day A" template
  /// assignment. The today-card header rendered the stale plan-gen
  /// name. Founder hit this on +22 install 2026-05-12.
  ///
  /// Fix: embed the parent template + its exercises via PostgREST
  /// select syntax and hydrate `workout_name` / `workout_focus` /
  /// `exercises[]` / `type='custom_template'` whenever the embed
  /// resolves. Rows where `template_id IS NULL` (rest days, plan-gen
  /// entries) keep the existing merge — local data survives.
  Future<void> _restoreScheduledWorkouts(String userId, String since) async {
    try {
      // APK Test #15.3 / Bug 4a — direct query with embed instead of
      // _fetchAllRows so we can pull the parent template + its
      // exercises in a single round trip. Page size 1000 mirrors
      // _fetchAllRows; in practice no user has anywhere near 1000
      // scheduled workouts (one row per day).
      final rows = await _supabase.client
          .from('scheduled_workouts')
          .select(
            '*, template:template_id('
            'id, name, workout_type, '
            'template_exercises(*)'
            ')',
          )
          .eq('user_id', userId)
          .gte('scheduled_date', since.substring(0, 10))
          .order('scheduled_date')
          .range(0, 999);

      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final date = map['scheduled_date'] as String? ?? '';
        if (date.isEmpty) continue;
        final key = 'schedule_$date';
        // APK Test #12.8 / Bug #3 — pre-fix this returned early when a
        // schedule entry already existed locally (typically because the
        // _restoreWorkoutPlan path populated it first with status='planned').
        // Result: cloud-side `status='completed'` + `completed_at` for May
        // 5/6/7 never reached Hive, so the calendar showed DONE only for
        // May 4 even though all four days were complete in the cloud.
        // Now we MERGE: existing local fields (workout_name, exercises[],
        // type) survive while cloud-authoritative fields (status,
        // completed_at, week_number, day_of_week) are overlaid.
        final existing = _hive.workoutBox.get(key);
        final existingMap = existing is Map
            ? Map<String, dynamic>.from(existing)
            : <String, dynamic>{};
        final cloudStatus = map['status'] as String?;
        final cloudCompletedAt = map['completed_at'] as String?;

        // APK Test #14 / Bug B.2 — timestamp-aware merge for
        // status/completed_at. Pre-fix this was unconditionally
        // cloud-authoritative, which destroyed local 'completed' state
        // any time `_syncScheduledWorkouts` push had failed (see Bug
        // B.1 — FK violations) since cloud still held the older
        // 'planned' row. Founder's Saturday completion vanished on
        // every cold-start restore for exactly this reason.
        //
        // Rules:
        //   • local completed + cloud planned + local has completed_at
        //       → keep local (cloud is stale; push must have failed).
        //         Bug B.3's one-shot migrator handles re-push.
        //   • local completed + cloud completed + both timestamps
        //       → take whichever has the LATER completed_at.
        //   • otherwise → existing rule (cloud authoritative).
        //
        // Diagnose: docs/diagnoses/2026-05-10-restore-overwrite-d9b2c5.md
        final localStatus = existingMap['status'] as String?;
        final localCompletedAt = existingMap['completed_at'] as String?;

        String? mergedStatus = cloudStatus;
        String? mergedCompletedAt = cloudCompletedAt;

        if (localStatus == 'completed' &&
            cloudStatus == 'planned' &&
            localCompletedAt != null &&
            localCompletedAt.isNotEmpty) {
          // Cloud is stale (push failed). Keep local; Bug B.3 migrator
          // re-pushes on next launch.
          mergedStatus = 'completed';
          mergedCompletedAt = localCompletedAt;
        } else if (localStatus == 'completed' &&
            cloudStatus == 'completed' &&
            localCompletedAt != null &&
            localCompletedAt.isNotEmpty &&
            cloudCompletedAt != null &&
            cloudCompletedAt.isNotEmpty) {
          // Both completed — newest timestamp wins.
          mergedCompletedAt =
              (localCompletedAt.compareTo(cloudCompletedAt) > 0)
                  ? localCompletedAt
                  : cloudCompletedAt;
          mergedStatus = 'completed';
        }

        // APK Test #15.3 / Bug 4a — hydrate workout_name + exercises[]
        // from the embedded template when one is assigned. Without
        // this, the today-card header renders the plan-gen default
        // ("PUSH A") instead of the user's template ("Leg Day A").
        //
        // closes-diagnose: 2026-05-12-restore-template-schedule-gap-9e2c1a
        String? hydratedWorkoutName;
        String? hydratedWorkoutFocus;
        List<Map<String, dynamic>>? hydratedExercises;
        bool templateResolved = false;

        if (map['template_id'] != null) {
          final templateEmbed = map['template'];
          if (templateEmbed is Map) {
            final tmpl = Map<String, dynamic>.from(templateEmbed);
            final tmplName = tmpl['name'] as String?;
            if (tmplName != null && tmplName.isNotEmpty) {
              hydratedWorkoutName = tmplName;
              hydratedWorkoutFocus =
                  (tmpl['workout_type'] as String?) ?? 'Custom';
              templateResolved = true;

              // Mirror _restoreWorkoutTemplates exercise mapping
              // (lines ~3938-3962). prescribed_sets → sets via
              // _coerceInt(fallback: 3) — Hive readers cast sets as
              // int? and an unchecked stringified value would crash
              // home_screen._buildTodayRow (closes-diagnose: a2f9e1).
              final exerciseRows = tmpl['template_exercises'] as List? ?? [];
              final sortedExercises = List.from(exerciseRows);
              sortedExercises.sort((a, b) =>
                  ((a as Map)['order_index'] as int? ?? 0)
                      .compareTo((b as Map)['order_index'] as int? ?? 0));

              hydratedExercises = sortedExercises.map((e) {
                final ex = Map<String, dynamic>.from(e as Map);
                return <String, dynamic>{
                  'exercise_name': ex['exercise_name'],
                  'name': ex['exercise_name'],
                  'exercise_id': ex['exercise_id'],
                  'id': ex['exercise_id'],
                  'logging_type': ex['logging_type'] ?? 'weight_reps',
                  'sets': _coerceInt(ex['prescribed_sets'], fallback: 3),
                  // `reps` stays String — library uses ranges like "8-12".
                  'reps': ex['prescribed_reps']?.toString() ?? '10',
                  'weight_kg': ex['prescribed_weight'],
                  'rest_seconds': ex['rest_seconds'],
                  'rest_secs': ex['rest_seconds'],
                  'notes': ex['notes'],
                };
              }).toList();
            }
          } else {
            // template_id set but embed null — template was deleted
            // (FK SET NULL would zero it; an RLS-hidden row would
            // also surface as null embed). Don't overwrite local
            // workout_name/exercises with empties.
            unawaited(ErrorTelemetry.logEvent(
              'restore_scheduled_workouts_template_missing',
              message: 'date=$date template_id=${map['template_id']}',
            ));
          }
        }

        final merged = <String, dynamic>{
          ...existingMap,
          'date': date,
          // When the template resolved, force the type to
          // 'custom_template' (overrides any stale local type written
          // by plan-gen). Otherwise preserve existing behavior.
          'type': templateResolved
              ? 'custom_template'
              : (existingMap['type'] ??
                  (map['template_id'] != null ? 'custom_template' : 'workout')),
          if (map['template_id'] != null) 'template_id': map['template_id'],
          if (mergedStatus != null && mergedStatus.isNotEmpty)
            'status': mergedStatus,
          if (mergedCompletedAt != null && mergedCompletedAt.isNotEmpty)
            'completed_at': mergedCompletedAt,
          if (map['week_number'] != null) 'week': map['week_number'],
          if (map['week_number'] != null) 'week_number': map['week_number'],
          if (map['day_of_week'] != null) 'day_of_week': map['day_of_week'],
          // APK Test #15.3 / Bug 4a — overlay template-derived display
          // content LAST so it wins over the existingMap spread above.
          if (hydratedWorkoutName != null) 'workout_name': hydratedWorkoutName,
          if (hydratedWorkoutFocus != null)
            'workout_focus': hydratedWorkoutFocus,
          if (hydratedExercises != null) 'exercises': hydratedExercises,
          'source': 'cloud_restore',
        };
        await _hive.workoutBox.put(key, merged);
      }
    } catch (e, st) {
      debugPrint('[SyncService._restoreScheduledWorkouts] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_if_21'));
      try {
        await _reportSyncFailure(opType: 'restore_scheduled_workouts', error: e);
      } catch (_) {}
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
        // F4 · Test #9 — coerce id from raw Hive key
        // 'saved_meal_<hash>' to deterministic v5 UUID. Same failure class
        // as _syncScheduledWorkouts.template_id (F3); same fix pattern as
        // _syncWorkoutTemplates (since 2026-04-18).
        final hiveId = (meal['id'] as String?) ?? key.toString();
        await _supabase.client.from('user_saved_meals').upsert({
          'id': _deterministicId(hiveId),
          'user_id': userId,
          'name': meal['name'] ?? 'Unnamed Meal',
          'items': meal['items'],
          'total_calories': meal['total_calories'],
          'total_protein': meal['total_protein'],
          'times_used': meal['times_used'] ?? 0,
          'created_at': meal['created_at'] ?? DateTime.now().toIso8601String(),
        }, onConflict: 'id');
      } catch (e, st) {
        debugPrint('[SyncService._syncSavedMeals] $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_for_25'));
        try {
          await _reportSyncFailure(opType: 'upsert_saved_meal', error: e);
        } catch (_) {}
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
        // APK Test #12.8 / Bug #1 — derive deterministic Hive key from
        // (user_id, lower(name)) instead of the cloud UUID. Pre-fix
        // `'saved_meal_${id.hashCode}'` produced a per-cloud-uuid Hive
        // row that did not collide with the locally-written
        // `saved_meal_<nameHash>` key, doubling the saved-meals list
        // on every restore. Identity = (user, name) — match the rule
        // used by NutritionRepository for local saves.
        final name = (map['name'] as String? ?? '').toLowerCase().trim();
        final hiveKey = name.isEmpty
            ? 'saved_meal_${id.hashCode.toUnsigned(32).toRadixString(16)}'
            : 'saved_meal_${name.hashCode.toUnsigned(32).toRadixString(16)}';

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
    } catch (e, st) {
      debugPrint('[SyncService._restoreSavedMeals] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_for_26'));
      try {
        await _reportSyncFailure(opType: 'restore_saved_meals', error: e);
      } catch (_) {}
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
    } catch (e, st) {
      debugPrint('[SyncService._syncUserPreferences] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_sync_user_preferences'));
      try {
        await _reportSyncFailure(opType: 'upsert_user_preferences', error: e);
      } catch (_) {}
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
    } catch (e, st) {
      debugPrint('[SyncService._restoreUserPreferences] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_restore_user_preferences'));
      try {
        await _reportSyncFailure(opType: 'restore_user_preferences', error: e);
      } catch (_) {}
    }
  }

  // ── Gap 7: AI Coach Interactions ───────────────────────────

  /// Pushes AI coach interactions to Supabase.
  ///
  /// Audit 2026-05-12 P2-B — pre-fix this was a hot double-write path. The
  /// `ai-proxy` Edge Function ALREADY writes an authoritative
  /// `ai_coach_interactions` row server-side at every chat turn (channel =
  /// 'app'). Then this method walked the Hive coachBox and re-upserted each
  /// entry with `channel: 'in_app'`, producing 81 phantom-duplicate rows
  /// vs. 22 legitimate 'app' rows in the live table (79% noise).
  /// Interaction-volume analytics were inflated 4× by this double-write.
  ///
  /// New behaviour: skip the upsert by default. The 'app' rows from
  /// ai-proxy ARE the source of truth. If `entry['id']` is non-null AND
  /// shaped like a UUID, the server already received this turn, so we have
  /// nothing to add. The pre-fix path only existed to catch "edge-case
  /// local-only entries" — those were always rare and the cost (4× row
  /// inflation) wasn't worth the catch.
  Future<void> _syncCoachInteractions(String userId) async {
    final coachBox = _hive.coachBox;
    for (final key in coachBox.keys) {
      if (key is! String || !key.startsWith('coach_')) continue;
      final raw = coachBox.get(key);
      if (raw is! Map) continue;
      final entry = Map<String, dynamic>.from(raw);

      try {
        final rawId = entry['id'];
        // Audit 2026-05-12 P2-B — server already wrote the authoritative
        // row when id is a real UUID (ai-proxy emits one on every turn).
        // Skip the duplicate 'in_app' write.
        if (rawId is String && _looksLikeUuid(rawId)) {
          continue;
        }
        // Edge case: pre-server entry with no UUID. Persist with a
        // deterministic v5 UUID under a clearer channel so server-side
        // analytics can isolate this fallback path if it becomes
        // surprisingly hot.
        final cloudId = _deterministicId('coach|$userId|$key');
        await _supabase.client.from('ai_coach_interactions').upsert({
          'id': cloudId,
          'user_id': userId,
          'channel': 'in_app_orphan',
          'user_message': entry['user_message'] ?? '',
          'ai_response': entry['ai_response'] ?? '',
          'model_used': entry['model_used'] ?? 'unknown',
          'created_at': entry['created_at'] ?? DateTime.now().toIso8601String(),
        }, onConflict: 'id');
      } catch (e, st) {
        debugPrint('[SyncService._syncCoachInteractions] $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_for_27'));
        try {
          await _reportSyncFailure(opType: 'upsert_coach_interaction', error: e);
        } catch (_) {}
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
        // APK Test #12.8 / Bug #1 — derive deterministic Hive key from
        // (user_id, created_at). Pre-fix `'coach_${id.hashCode}'` keyed
        // by the cloud UUID's hash, which never matches the local-write
        // key `coach_<created_at_ms>` produced by `ai_coach_repository`
        // — every cold restore appended a sibling row. The cloud
        // `created_at` ISO string is stable and globally unique per
        // user-message turn so it collapses cloud→local on round-trip.
        final createdAt = map['created_at'] as String? ?? '';
        final ts =
            DateTime.tryParse(createdAt)?.millisecondsSinceEpoch ?? 0;
        final hiveKey = ts > 0
            ? 'coach_$ts'
            : 'coach_${id.hashCode.toUnsigned(32).toRadixString(16)}';

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
    } catch (e, st) {
      debugPrint('[SyncService._restoreCoachInteractions] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_for_28'));
      try {
        await _reportSyncFailure(opType: 'restore_coach_interactions', error: e);
      } catch (_) {}
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
            'typical_wake_time, preferred_workout_time, body_part_priorities, '
            'coach_notes',
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

      // A6 — coach_notes: restore AI coach memory so it's available
      // between reinstall and the next 11 PM IST extraction run.
      // Cloud column is `coach_notes` (singular table, see migration set);
      // Hive field-name contract preserves `coaching_notes` so consumers
      // (`coachBox.get('coaching_notes')`) keep working unchanged.
      final notes = row['coach_notes'];
      if (notes != null) {
        await coach.put('coaching_notes', notes);
      }
    } catch (e, st) {
      debugPrint('[SyncService._restoreCoachMemory] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_if_22'));
      unawaited(_reportSyncFailure(
        opType: 'restore_coach_memory',
        error: e,
      ));
    }
  }

  // ── Restore-completeness push (Theme A push side) ─────────

  /// Pushes the user's streak-freeze state to the three new columns on
  /// `user_progress` (migration 048). One upsert per call — cheap and
  /// idempotent. Called fire-and-forget from every Hive mutation site
  /// in WorkoutRepository + home_provider per CLAUDE.md §15.
  Future<void> syncFreezes() async {
    try {
      final userId = _supabase.currentUser?.id;
      if (userId == null) return;
      final progress = _hive.userBox.get('progress');
      if (progress == null) return;
      final p = Map<String, dynamic>.from(progress as Map);
      // APK Test #14 / Bug D.2 — fallback bumped 2 -> 1 to match the new
      // free-tier baseline (cloud default also moved to 1 via migration 050).
      // PRO clients overwrite to 3 on next ladder refill.
      final available = (p['streak_freezes_available'] as int?) ?? 1;
      final usedRaw = p['streak_freeze_used_dates'];
      final used = (usedRaw is List)
          ? usedRaw.map((e) => e.toString()).toList()
          : <String>[];
      final lastRefill = p['streak_freezes_last_refill'] as String?;
      await _supabase.client.from('user_progress').upsert({
        'user_id': userId,
        'streak_freezes_available': available,
        'streak_freezes_used_dates': used,
        if (lastRefill != null) 'streak_freezes_last_refill': lastRefill,
      }, onConflict: 'user_id');
    } catch (e, st) {
      debugPrint('[SyncService.syncFreezes] error: $e\n$st');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_sync_freezes'));
      try {
        await _reportSyncFailure(opType: 'sync_freezes', error: e);
      } catch (_) {}
    }
  }

  /// Inserts (or upserts by [entry]'s id) a single notification inbox entry
  /// to the `notifications_inbox` cloud table (migration 048).
  /// Called fire-and-forget from [NotificationInboxService.record] per
  /// CLAUDE.md §15.
  ///
  /// [entry] is the `AppNotification.toJson()` map — keys: id, category,
  /// title, body, created_at, priority, read. The cloud column is
  /// `notif_type` (matches AppNotification.category.name).
  Future<void> syncNotificationsInboxEntry(Map<String, dynamic> entry) async {
    try {
      final userId = _supabase.currentUser?.id;
      if (userId == null) return;
      final id = entry['id'] as String?;
      if (id == null || id.isEmpty) return;
      final row = <String, dynamic>{
        'id': id,
        'user_id': userId,
        'notif_type': entry['category'] as String? ?? 'system',
        'title': entry['title'] as String? ?? '',
        'body': entry['body'] as String? ?? '',
        'payload': <String, dynamic>{
          'priority': entry['priority'],
          'read': entry['read'],
        },
        'created_at': entry['created_at'] as String? ??
            DateTime.now().toUtc().toIso8601String(),
        if (entry['read'] == true)
          'read_at': entry['created_at'] as String? ??
              DateTime.now().toUtc().toIso8601String(),
      };
      await _supabase.client
          .from('notifications_inbox')
          .upsert(row, onConflict: 'id');
    } catch (e, st) {
      debugPrint('[SyncService.syncNotificationsInboxEntry] error: $e\n$st');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_sync_notifications_inbox_entry'));
      try {
        await _reportSyncFailure(
            opType: 'sync_notifications_inbox_entry', error: e);
      } catch (_) {}
    }
  }

  /// Pushes the user's saved diet plan to the `saved_diet_plans` cloud
  /// table (migration 048). One row per user — upserts on conflict.
  /// Called fire-and-forget from [DietPlanScreen._savePlan] per
  /// CLAUDE.md §15.
  Future<void> syncSavedDietPlan(Map<String, dynamic> planJson) async {
    try {
      final userId = _supabase.currentUser?.id;
      if (userId == null) return;
      await _supabase.client.from('saved_diet_plans').upsert({
        'user_id': userId,
        'plan_json': planJson,
        'saved_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');
    } catch (e, st) {
      debugPrint('[SyncService.syncSavedDietPlan] error: $e\n$st');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_sync_saved_diet_plan'));
      try {
        await _reportSyncFailure(opType: 'sync_saved_diet_plan', error: e);
      } catch (_) {}
    }
  }

  // ── Restore completeness — pull side (Theme A) ─────────────

  /// A1 — Restores streak-freeze state from `user_progress` cloud columns
  /// (migration 048) into the `progress` map in `userBox`.
  ///
  /// Freeze fields are stored inside `userBox['progress']` (a Map) to
  /// match the read pattern in [WorkoutRepository] and [home_provider].
  /// We merge on top of the existing local map so any IST-rollover data
  /// written since the last sync is not lost.
  Future<void> _restoreFreezes(String userId) async {
    try {
      final res = await _supabase.client
          .from('user_progress')
          .select(
            'streak_freezes_available, streak_freezes_used_dates, '
            'streak_freezes_last_refill',
          )
          .eq('user_id', userId)
          .maybeSingle();
      if (res == null) return;

      final box = _hive.userBox;
      final existing = box.get('progress');
      final existingMap = existing is Map
          ? Map<String, dynamic>.from(existing)
          : <String, dynamic>{};

      // APK Test #14 / Bug D.2 — fallback bumped 2 -> 1 (cf. line 4332).
      existingMap['streak_freezes_available'] =
          res['streak_freezes_available'] ?? 1;

      final usedRaw = res['streak_freezes_used_dates'];
      existingMap['streak_freeze_used_dates'] = (usedRaw is List)
          ? usedRaw.map((e) => e.toString()).toList()
          : <String>[];

      final lastRefill = res['streak_freezes_last_refill'];
      if (lastRefill != null) {
        existingMap['streak_freezes_last_refill'] = lastRefill.toString();
      }

      await box.put('progress', existingMap);
    } catch (e, st) {
      debugPrint('[SyncService._restoreFreezes] error: $e\n$st');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_if_23'));
      try {
        await _reportSyncFailure(opType: 'restore_freezes', error: e);
      } catch (_) {}
    }
  }

  /// A4 — Restores last 200 notifications inbox rows from
  /// `notifications_inbox` cloud table (migration 048) into
  /// `notificationsBox`.
  ///
  /// Cloud column `notif_type` maps back to the Hive `category` field —
  /// e.g. `notif_type: 'pr'` → `category: 'pr'`. The mapping is
  /// symmetric with [syncNotificationsInboxEntry] which writes
  /// `'notif_type': entry['category']`. We store the row in the same
  /// shape as [AppNotification.toJson] so [NotificationInboxService.readAll]
  /// can parse it without any special-casing.
  ///
  /// Uses the notification `id` as the Hive key (not `notif_$id`) to
  /// match what [NotificationInboxService.record] writes.
  Future<void> _restoreNotificationsInbox(String userId) async {
    try {
      final rows = await _supabase.client
          .from('notifications_inbox')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(200);

      final box = _hive.notificationsBox;
      for (final rawRow in rows as List) {
        final r = Map<String, dynamic>.from(rawRow as Map);
        final id = r['id'] as String?;
        if (id == null || id.isEmpty) continue;

        // Map cloud → Hive shape expected by AppNotification.fromJson.
        // notif_type  → category (same string, e.g. 'coach', 'pr', 'system')
        // read_at     → read: true/false
        final payload = r['payload'];
        final payloadMap = payload is Map
            ? Map<String, dynamic>.from(payload)
            : <String, dynamic>{};

        final hiveEntry = <String, dynamic>{
          'id': id,
          'category': r['notif_type'] as String? ?? 'system',
          'title': r['title'] as String? ?? '',
          'body': r['body'] as String? ?? '',
          'created_at': r['created_at'] as String? ??
              DateTime.now().toUtc().toIso8601String(),
          'priority': payloadMap['priority'] as String? ?? 'normal',
          'read': r['read_at'] != null || payloadMap['read'] == true,
        };

        await box.put(id, hiveEntry);
      }
    } catch (e, st) {
      debugPrint('[SyncService._restoreNotificationsInbox] error: $e\n$st');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_for_29'));
      try {
        await _reportSyncFailure(
            opType: 'restore_notifications_inbox', error: e);
      } catch (_) {}
    }
  }

  /// A5 — Restores the user's saved diet plan from `saved_diet_plans`
  /// cloud table (migration 048) into `userBox['saved_diet_plan']`
  /// (migrated from configBox in Test #11.1).
  ///
  /// One row per user (PRIMARY KEY on user_id). On conflict the cloud
  /// row wins — the user may have saved an updated plan on another device.
  Future<void> _restoreSavedDietPlan(String userId) async {
    try {
      final res = await _supabase.client
          .from('saved_diet_plans')
          .select('plan_json')
          .eq('user_id', userId)
          .maybeSingle();
      if (res == null) return;
      final planJson = res['plan_json'];
      if (planJson == null) return;
      await MigratedKey.write('saved_diet_plan', planJson);
    } catch (e, st) {
      debugPrint('[SyncService._restoreSavedDietPlan] error: $e\n$st');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_restore_saved_diet_plan'));
      try {
        await _reportSyncFailure(opType: 'restore_saved_diet_plan', error: e);
      } catch (_) {}
    }
  }

  /// A2 — Restores last 20 rank promotion rows from `rank_promotions`
  /// cloud table into `userBox['rank_promotions_history']`.
  ///
  /// Stored as a raw list of maps so [promotionHistoryProvider] can
  /// optionally fall back to this cache when offline; no schema
  /// translation needed (keys already match cloud column names).
  Future<void> _restoreRankPromotions(String userId) async {
    try {
      final rows = await _supabase.client
          .from('rank_promotions')
          .select()
          .eq('user_id', userId)
          .order('achieved_at', ascending: false)
          .limit(20);
      await _hive.userBox.put('rank_promotions_history', rows);
    } catch (e, st) {
      debugPrint('[SyncService._restoreRankPromotions] error: $e\n$st');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_restore_rank_promotions'));
      try {
        await _reportSyncFailure(
            opType: 'restore_rank_promotions', error: e);
      } catch (_) {}
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
