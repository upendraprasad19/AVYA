part of '../sync_service.dart';

/// Sync + restore for the workout domain — the largest extraction in
/// the part-file split.
///
/// Cloud tables touched: workout_logs (sessions), workout_log_exercises
/// (per-exercise summaries), workout_log_sets (per-set rows),
/// workout_schedule_completions, scheduled_workouts, workout_templates
/// (+ template_exercises), streaks, user_progress.plan_json
/// (workout-plan blob).
///
/// `syncWorkoutData()` is the SoT fan-out entry point pinned by
/// `test/contracts/sync_fanout_contract_test.dart` (CLAUDE.md §15) — it
/// MUST keep calling all 6 helpers: _syncWorkoutLogs, _syncExerciseLogs,
/// _syncScheduleCompletions, _syncWorkoutTemplates, _syncScheduledWorkouts,
/// _syncStreaks.
///
/// Domain-specific helpers `_resolveCompletedAt` + `_dateFromKey` co-extracted.
/// Static helpers (_deterministicId, etc.) stay on SyncService class; this
/// extension calls them via `SyncService._foo(...)` (auto-qualified).
extension SyncServiceWorkout on SyncService {
  /// Push workout logs + exercise logs + schedule completions to Supabase.
  /// Call this after a workout is completed for near-realtime backup.
  Future<void> syncWorkoutData() async {
    if (SyncService.pausedForSimulation) return; // sim bulk-backfill
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
        // UNIQUE on (user_id, date, workout_name); switch the upsert to
        // target it so re-syncs merge instead of producing fresh dupes.
        // Drift-fix 2026-05-25 F3+F4 — column renamed from exercise_name
        // → workout_name (matches semantic: it's the session label, e.g.
        // "Push A", never a per-exercise identifier). Dead `notes: log[id]`
        // stuffing dropped (log['id'] never set by WorkoutWriteService).
        //
        // Audit 2026-05-15 — belt-and-suspenders null-key guard. If the
        // Hive row is missing `date` OR `workout_name` (the natural-key
        // columns), the upsert would either send null/empty values that
        // PostgREST 23502-rejects, or worse — collapse multiple rows
        // onto a single null-keyed row in cloud. Skip and emit telemetry
        // so a future column-nullability regression doesn't silently
        // swallow data.
        // audit-2026-05-16 E.12 — `sets_completed`, `rpe` columns dropped
        // from workout_logs in migration 067 (cloud was 100% NULL). Hive
        // fields retained for restore round-trip + migrators.
        final wlogDate = (log['date'] as String?)?.trim();
        final wlogName = (log['workout_name'] as String?)?.trim();
        if (wlogDate == null ||
            wlogDate.isEmpty ||
            wlogName == null ||
            wlogName.isEmpty) {
          unawaited(ErrorTelemetry.logEvent(
            'sync_skipped_null_natural_key',
            message:
                'table=workout_logs key=$key date_null=${wlogDate == null || wlogDate.isEmpty} name_null=${wlogName == null || wlogName.isEmpty}',
          ));
          continue;
        }
        await _supabase.client.from('workout_logs').upsert({
          // Fix 2026-06-02 (cross-user PK collision): OMIT the client id. Was
          // `_deterministicId('wlog_<date>')` (date-only, no user) → two users
          // completing a workout on the SAME date generated the SAME uuid →
          // cross-user collision on workout_logs_pkey (23505); whoever synced
          // second silently lost their session-summary row. Omitting id (the
          // proven cure: nutrition_logs c9f2a7 / workout_templates a8b2c7 /
          // scheduled_workouts c8e4a1) → gen_random_uuid() on insert, existing
          // id kept on conflict; the user-inclusive natural key
          // (user_id,date,workout_name) below merges re-syncs. Existing rows
          // self-heal on next sync — no re-key.
          'user_id': userId,
          'workout_name': wlogName,
          'date': wlogDate,
          'logged_at': resolved,
          'duration_seconds': log['duration_seconds'],
          'created_at': resolved,
        }, onConflict: 'user_id,date,workout_name');
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
        final workoutLogId = SyncService._deterministicId('workout_$date');
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
        // Audit 2026-05-15 — belt-and-suspenders null-key guard. Skip the
        // upsert when the natural-key triple (workout_log_id, exercise_id,
        // set_number) has any null/empty member. Prevents a future
        // column-nullability regression from quietly merging unrelated
        // exercises onto a single null-keyed cloud row.
        final wlIdGuard = workoutLogId.trim();
        final exIdGuard = exerciseId.trim();
        if (wlIdGuard.isEmpty || exIdGuard.isEmpty) {
          unawaited(ErrorTelemetry.logEvent(
            'sync_skipped_null_natural_key',
            message:
                'table=workout_log_exercises key=$key workout_log_id_null=${wlIdGuard.isEmpty} exercise_id_null=${exIdGuard.isEmpty} set_number_null=false',
          ));
          continue;
        }
        // Guard: workout_log_exercises.reps is the CUMULATIVE total (Σ set
        // reps). Clamp to the wle_reps_realistic bound (<=10000, migration 084)
        // so an out-of-range value (a migrator duration->reps leak, a parse
        // glitch) is CLAMPED + logged (op_type wle_reps_out_of_range) instead
        // of being silently rejected by Postgres (23514) and lost. diagnose e7b3c9.
        final rawReps = (log['reps_completed'] as num?)?.toInt();
        final clampedReps =
            rawReps == null ? null : rawReps.clamp(0, 10000).toInt();
        if (rawReps != null && rawReps != clampedReps) {
          unawaited(ErrorTelemetry.logEvent(
            'wle_reps_out_of_range',
            message:
                'raw=$rawReps clamped=$clampedReps exercise=${log['exercise_name']}',
          ));
        }
        await _supabase.client.from('workout_log_exercises').upsert({
          // id OMITTED (fix 2026-06-02 cross-user collision) — gen_random_uuid()
          // on insert / kept on conflict. The natural key below now includes
          // user_id so two users with the same date+exercise+set don't collide.
          'workout_log_id': workoutLogId,
          'user_id': userId,
          'exercise_id': exerciseId,
          'exercise_name': log['exercise_name'] ?? '',
          'logging_type': log['logging_type'],
          'set_number': summarySetCount,
          'reps': clampedReps,
          'weight_kg': log['weight_kg'],
          'duration_seconds': aggregateDurationSecs,
          'distance_km': log['distance_km'],
          'is_pr': log['is_pr'] ?? false,
          'has_warmup_sets': log['has_warmup_sets'] ?? false,
          'completed_at': completedAt,
          // Fix 2026-06-02: user_id added to the conflict key (matching new
          // index uniq_wle_user_wlog_ex_set) — workout_log_id is date-only, so
          // without user_id two users' same-date+exercise+set rows collided and
          // DO UPDATE could overwrite the OTHER user's row (cross-user corruption).
        }, onConflict: 'user_id,workout_log_id,exercise_id,set_number');

        // ── PER-SET ROWS (F4) ──
        // Upserts a row per set into `workout_log_sets`. Natural key is
        // (workout_log_id, exercise_id, set_number) → idempotent across
        // re-syncs and retries. Source: legacy `sets_detail` OR the new
        // WorkoutWriteService `sets` list (Plan A A-5).
        if (resolvedSets.isNotEmpty) {
          final rows = <Map<String, dynamic>>[];
          // Audit 2026-05-15 — belt-and-suspenders null-key guard.
          // Mirrors the summary-row guard above; ensures we never push
          // per-set rows whose natural-key parents (workout_log_id /
          // exercise_id) are empty even if a future code path bypasses
          // the summary-row early-continue.
          final perSetWlId = workoutLogId.trim();
          final perSetExId = exerciseId.trim();
          if (perSetWlId.isEmpty || perSetExId.isEmpty) {
            unawaited(ErrorTelemetry.logEvent(
              'sync_skipped_null_natural_key',
              message:
                  'table=workout_log_sets key=$key workout_log_id_null=${perSetWlId.isEmpty} exercise_id_null=${perSetExId.isEmpty}',
            ));
          } else {
            for (final sm in resolvedSets) {
              final setNum = (sm['set_number'] as num?)?.toInt();
              if (setNum == null) {
                unawaited(ErrorTelemetry.logEvent(
                  'sync_skipped_null_natural_key',
                  message:
                      'table=workout_log_sets key=$key workout_log_id_null=false exercise_id_null=false set_number_null=true',
                ));
                continue;
              }
              // Guard: workout_log_sets.reps must satisfy wls_reps_realistic
              // (<=10000, migration 085). Clamp + log an out-of-range per-set
              // value (e.g. a migrator duration->reps leak) so the row is never
              // silently rejected by Postgres (23514) and lost — the per-set
              // rows back the receipt/Train/weekly-report sums. Mirrors the wle
              // clamp on the summary row above. diagnose d9a4f2.
              final rawSetReps = (sm['reps'] as num?)?.toInt();
              final clampedSetReps =
                  rawSetReps == null ? null : rawSetReps.clamp(0, 10000).toInt();
              if (rawSetReps != null && rawSetReps != clampedSetReps) {
                unawaited(ErrorTelemetry.logEvent(
                  'wls_reps_out_of_range',
                  message:
                      'raw=$rawSetReps clamped=$clampedSetReps set=$setNum exercise=$exerciseId',
                ));
              }
              rows.add({
                'user_id': userId,
                'workout_log_id': workoutLogId,
                'exercise_id': exerciseId,
                'set_number': setNum,
                'weight_kg': sm['weight_kg'],
                'reps': clampedSetReps,
                'duration_secs': sm['duration_seconds'] ?? sm['duration_sec'],
                'distance_km': sm['distance_km'],
                'completed_at': completedAt,
              });
            }
          }
          if (rows.isNotEmpty) {
            try {
              await _supabase.client
                  // Fix 2026-06-02: user_id added to the conflict key (matching
                  // new index uniq_wls_user_wlog_ex_set) — prevents cross-user
                  // collision on the date-only workout_log_id. (id was already
                  // omitted — gen_random_uuid() default.)
                  .from('workout_log_sets')
                  .upsert(rows, onConflict: 'user_id,workout_log_id,exercise_id,set_number');
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

      // audit-2026-05-16 F3-1.3 — `duration_seconds` lives on the
      // `wlog_<dateStr>` workout-log row (written by
      // `WorkoutWriteService.markCompleted`), NOT on the schedule entry.
      // Pre-fix this projection pulled the field directly off the schedule
      // entry map, which never has it → cloud column was 100% NULL (11/11
      // rows). Look up the matching wlog by IST date and pull the field
      // from there. Absent → omit from payload (column is nullable;
      // absence beats null on the wire).
      // (Anti-regression test in test/contracts/schedule_completion_duration_*
      // bans the pre-fix shape `<entry>[<key>]` so don't restore it.)
      final wlog = workoutBox.get('wlog_$date');
      final durationSeconds =
          wlog is Map ? (wlog['duration_seconds'] as num?)?.toInt() : null;

      try {
        final payload = <String, dynamic>{
          'user_id': userId,
          'scheduled_date': date,
          'day_of_week': entry['day_of_week']?.toString(),
          'workout_name': entry['workout_name'],
          if (durationSeconds != null) 'duration_seconds': durationSeconds,
          'completed_at':
              entry['completed_at'] ?? DateTime.now().toIso8601String(),
        };
        await _supabase.client
            .from('workout_schedule_completions')
            .upsert(payload, onConflict: 'user_id,scheduled_date');
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
          'id': SyncService._deterministicId('streak_${userId}_$weekStart'),
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

  /// Pulls workout session logs from cloud workout_logs into local Hive.
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
          // Drift-fix 2026-05-29 (closes-diagnose 7c2a8b): migration 068b
          // renamed workout_logs.exercise_name → workout_name. The write
          // side (line ~133) already emits workout_name; this restore reader
          // still read the dead `exercise_name` key, so every restored
          // session relabelled to the literal "Workout". Read workout_name.
          'workout_name': map['workout_name'] ?? 'Workout',
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
        // APK Test #16.1 / Agent A — single SoT for exlog key. The
        // previous "Bug #1 fix" comment claimed parity with
        // WorkoutWriteService.exlogKey but still used `name.hashCode`
        // (platform-unstable) over a substring(0, 10) date (could be
        // UTC date if cloud row carries UTC completed_at). Founder
        // observed 26+ phantom exlog rows for May 14 after restore.
        // Now delegates to WorkoutWriteService.exlogKey — UUID v5 over
        // lowercase+trim(name) + IST date — so restore writes the same
        // canonical key the WriteService produces. Re-restore is now
        // truly idempotent.
        DateTime dateForKey;
        try {
          dateForKey = completedAt.isNotEmpty
              ? DateTime.parse(completedAt)
              : DateTime.now();
        } catch (_) {
          dateForKey = DateTime.now();
        }
        final logId = WorkoutWriteService.exlogKey(dateForKey, name);
        final dateStr = WorkoutWriteService.istDateStr(dateForKey);

        final logMap = <String, dynamic>{
          'id': logId,
          'type': 'exercise_log',
          'exercise_name': name,
          'date': dateStr,
          'logging_type': map['logging_type'] ?? 'weight_reps',
          'is_pr': map['is_pr'] ?? false,
          'has_warmup_sets': map['has_warmup_sets'] ?? false,
          'created_at': completedAt,
          // audit-2026-05-16 reader-side / Obs 1 — project cloud
          // `workout_log_id` to Hive so session-scoped receipt filters
          // (`WorkoutReceiptData.fromExerciseLogs(date, workoutLogId)`)
          // can match restored rows. Pre-fix the field was dropped on
          // restore — multi-session days surfaced as "View Card does
          // nothing" because the session filter rejected every row.
          // Fall back to canonical `wlog_<istDate>` (matches the writer
          // default at workout_write_service.dart:164) when the cloud
          // row has no explicit workout_log_id.
          'workout_log_id': map['workout_log_id'] as String? ??
              WorkoutWriteService.wlogKey(dateForKey),
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

  // ── SyncDomain scaffold accessors (audit 2026-05-20 / A6) ──
  //
  // Public forwarders for `_syncStreaks` / `_restoreStreaks` so the new
  // `lib/core/services/sync_domains/streaks_sync_domain.dart` wrapper
  // can invoke them without `part of` privilege. These two methods are
  // the proof-of-pattern for the SyncDomain interface migration; the
  // remaining `_syncXxx` / `_restoreXxx` pairs gain similar accessors
  // as each part-file is migrated in follow-up batches.
  //
  // The private methods remain the source of truth; these are thin
  // delegators by design (no behavioural change). The `userId` arg is
  // resolved internally via `_ensureSessionOpen()` for the public
  // shape SyncDomain demands (zero-arg push/restore).

  /// Public delegator for [_syncStreaks]. Resolves `userId` via
  /// `_ensureSessionOpen()`; returns silently when no session is open.
  Future<void> pushStreaksForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _syncStreaks(userId);
  }

  /// Public delegator for [_restoreStreaks]. Resolves `userId` via
  /// `_ensureSessionOpen()`; returns silently when no session is open.
  Future<void> restoreStreaksForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _restoreStreaks(userId);
  }

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

  /// Restores the workout plan from Supabase `plan_json` on a new device.
  ///
  /// Restore-skip bug (closes-diagnose: 2026-06-06-restore-plan-json-skip):
  /// this used to early-return when a local `current_plan` already existed. But
  /// on a reinstall a plan can be locally (re)generated before/around restore,
  /// so the exercise-rich `plan_json.schedules` snapshot (and the correct
  /// `plan_start_date`) was NEVER applied — every not-yet-completed day then
  /// rendered "REST DAY / No exercises scheduled" (the cloud `scheduled_workouts`
  /// table has no exercises/name column to rehydrate from) and the week number
  /// was computed off a stale plan_start. We now ALWAYS apply the snapshot's
  /// plan_start_date / plan_end_date / schedules (completed-day-preserving
  /// merge); only the `current_plan` object is left untouched when a local one
  /// already exists.
  Future<void> _restoreWorkoutPlan(String userId) async {
    try {
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

      // Seed the plan object when missing, but don't clobber a (possibly
      // fresher) local one.
      if (plan != null && _hive.workoutBox.get('current_plan') == null) {
        await _hive.workoutBox.put('current_plan',
            plan is Map ? Map<String, dynamic>.from(plan) : plan);
      }
      // plan_start / plan_end are the synced source of truth for the current
      // phase window — always re-anchor them (the skip leaving these stale is
      // what inflated the displayed week number).
      if (planStart != null) {
        await MigratedKey.write('plan_start_date', planStart);
      }
      if (planEnd != null) {
        await MigratedKey.write('plan_end_date', planEnd);
      }
      if (schedules is Map) {
        for (final entry in schedules.entries) {
          final key = entry.key.toString();
          if (!key.startsWith('schedule_')) continue;
          final incoming = entry.value;
          if (incoming is! Map) continue;
          // Completed-day-preserving merge — extracted to
          // PlanIntegrityReconciler.mergeScheduleEntry and SHARED with the boot
          // heal so the restore + reconciler can't drift (APK Test #12.9 kept:
          // a local `status:'completed'` is authoritative and survives the
          // frozen plan_json snapshot).
          final existing = _hive.workoutBox.get(key);
          final merged = PlanIntegrityReconciler.mergeScheduleEntry(
            existing is Map ? Map<String, dynamic>.from(existing) : null,
            Map<String, dynamic>.from(incoming),
          );
          await _hive.workoutBox.put(key, merged);
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
        // audit-2026-05-16 E.12 — migration 067 dropped
        // workout_templates.description + estimated_duration_mins (template
        // builder UI never exposes these inputs; 100% NULL across all
        // live rows). Hive `description` field is retained for the restore
        // round-trip (cloud read returns null → empty in Hive).
        await _supabase.client.from('workout_templates').upsert({
          'user_id': userId,
          'name': tmplName,
          'workout_type': tmpl['workout_focus'] ?? tmpl['workout_type'] ?? 'custom',
          'source': 'user',
          'is_active': true,
          'created_at':
              tmpl['created_at'] ?? DateTime.now().toIso8601String(),
          if (tmpl['last_used_at'] != null)
            'last_used_at': tmpl['last_used_at'],
        }, onConflict: 'user_id,name');

        // SELECT the real cloud id post-upsert so child rows FK
        // correctly. Pre-fix used `SyncService._deterministicId('tmpl|user|name')`
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
          // audit-2026-05-16 E.12 — migration 067 dropped exercise_id from
          // template_exercises. The pre-fix `isUuid` UUID-shape check
          // gated the projection of that column; with the column gone,
          // the variable is dead. Removed to satisfy analyzer.
          try {
            await _supabase.client.from('template_exercises').upsert({
              // APK Test #12.8 / Bug #4 — `id` omitted; child UUID
              // generated by cloud default on first insert. On conflict
              // (template_id, order_index), the existing row's id is
              // preserved and other fields are updated.
              'template_id': cloudTmplId,
              // audit-2026-05-16 E.12 — migration 067 dropped 5 columns
              // from template_exercises (exercise_id, rest_seconds,
              // prescribed_weight, prescribed_time_secs, notes — all 100%
              // NULL in prod, no UI writers). Projection trimmed to the
              // surviving columns. Hive-side fields are retained for the
              // restore round-trip (cloud → Hive reads of dropped columns
              // return null, which is the expected default).
              'exercise_name': ex['exercise_name'] ?? ex['name'] ?? '',
              'order_index': i,
              'logging_type': ex['logging_type'] ?? 'weight_reps',
              if (ex['sets'] != null)
                'prescribed_sets': ex['sets'] is int
                    ? ex['sets']
                    : int.tryParse(ex['sets'].toString()),
              if (ex['reps'] != null) 'prescribed_reps': ex['reps'].toString(),
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

  /// Pushes full scheduled workout definitions to Supabase.
  /// Complements _syncScheduleCompletions which only pushes completed status.
  ///
  /// APK Test #14 / Bug B.1 — self-healing template_id resolution.
  /// Pre-fix used `SyncService._deterministicId(rawTemplateId)` to coerce the Hive
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
        // lookup. Pre-fix used `SyncService._deterministicId(rawTemplateId)` which
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

  // ── SyncDomain public forwarders for workout helpers (A6 migration) ──
  //
  // One pair per `_syncX(userId)` / `_restoreX(userId[, since])` private
  // helper that maps to a [SyncDomain] wrapper class under
  // `lib/core/services/sync_domains/`. Each forwarder is a thin
  // delegator: it resolves `userId` via `_ensureSessionOpen()` (so the
  // zero-arg [SyncDomain.push] / [SyncDomain.restore] contract holds)
  // and then calls the existing private helper. No behavioural change.
  //
  // The legacy fan-out (syncWorkoutData / restoreFromCloudForUser) keeps
  // calling the private helpers directly until [SyncFlags] flips for
  // the corresponding domain. See `lib/core/services/sync_flags.dart`.

  /// Default `since` for cloud→local pulls. Matches the literal at
  /// every `restoreFromCloud*` call site so the wrapper path can be
  /// flipped in without changing the cloud query semantics.
  static const String _kSyncDomainRestoreSince = '2020-01-01T00:00:00Z';

  Future<void> pushWorkoutLogsForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _syncWorkoutLogs(userId);
  }

  Future<void> restoreWorkoutLogsForSyncDomain({String? since}) async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _restoreWorkoutLogs(userId, since ?? _kSyncDomainRestoreSince);
  }

  Future<void> pushExerciseLogsForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _syncExerciseLogs(userId);
  }

  Future<void> restoreExerciseLogsForSyncDomain({String? since}) async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _restoreExerciseLogs(userId, since ?? _kSyncDomainRestoreSince);
  }

  Future<void> pushScheduleCompletionsForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _syncScheduleCompletions(userId);
  }

  Future<void> restoreScheduleCompletionsForSyncDomain({String? since}) async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _restoreScheduleCompletions(userId, since ?? _kSyncDomainRestoreSince);
  }

  Future<void> pushWorkoutPlanForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _syncWorkoutPlan(userId);
  }

  Future<void> restoreWorkoutPlanForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _restoreWorkoutPlan(userId);
  }

  Future<void> pushWorkoutTemplatesForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _syncWorkoutTemplates(userId);
  }

  Future<void> restoreWorkoutTemplatesForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _restoreWorkoutTemplates(userId);
  }

  Future<void> pushScheduledWorkoutsForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _syncScheduledWorkouts(userId);
  }

  Future<void> restoreScheduledWorkoutsForSyncDomain({String? since}) async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _restoreScheduledWorkouts(userId, since ?? _kSyncDomainRestoreSince);
  }
}
