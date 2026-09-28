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
/// `test/contracts/sync_fanout_contract_test.dart` (docs/architecture/sync.md) — it
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
  /// Coalesced fire-and-forget entry (per-write). A burst of calls collapses
  /// to 1–2 cloud passes via [SyncCoalescer] (Unit H / H1a) instead of one full
  /// fan-out per write — the signup-storm fix. Awaited callers that need
  /// durable completion (boot migrators, the sim harness) MUST use
  /// [syncWorkoutDataNow] instead. Kill-switch `disable_sync_debounce` bypasses
  /// the coalescer (every call runs the full fan-out — the pre-Unit-H behavior).
  Future<void> syncWorkoutData() async {
    if (SyncService.pausedForSimulation) return; // sim bulk-backfill (guard FIRST)
    if (_syncDebounceDisabled) {
      await syncWorkoutDataNow();
      return;
    }
    await _workoutCoalescer.trigger(syncWorkoutDataNow);
  }

  /// Non-coalesced workout-domain push — runs the full fan-out NOW. Called by
  /// awaited callers (boot migrators, the sim harness) and internally by
  /// [syncWorkoutData]'s coalescer. Pinned by `sync_fanout_contract_test` +
  /// `sync_template_before_schedule_order_test`: MUST call all 6 helpers with
  /// `_syncWorkoutTemplates` BEFORE the parallel `Future.wait` (FK-23503 / Bug B.1).
  Future<void> syncWorkoutDataNow() async {
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
      debugPrint('[SyncService.syncWorkoutDataNow] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_sync_workout_data', skipServerPost: true));
      try {
        await _reportSyncFailure(opType: 'sync_workout_data', error: e);
      } catch (_) {}
    }
  }

  /// Pushes workout session logs (wlog_* keys) to Supabase workout_logs.
  /// day-swapper+sync-load Task 16: routed through SyncSkipIndex (domain
  /// wlog) — no pre-existing index, so this closes one leg of the OI-237
  /// write-amplification class (every historical wlog row previously
  /// re-uploaded on every pass).
  Future<void> _syncWorkoutLogs(String userId) async {
    final workoutBox = _hive.workoutBox;
    final index = SyncSkipIndex(
      box: workoutBox,
      domain: SyncSkipDomain.wlog,
      disabled: _hashSkipKillSwitchOn(SyncSkipDomain.wlog),
      ownerChangedNow: () => ownerChangedSince(userId),
      reportFailure: (op, e, st) =>
          unawaited(_reportSyncFailure(opType: op, error: e)),
    );

    final liveKeys = <String>{};
    for (final key in workoutBox.keys) {
      if (index.aborted) break;
      if (key is! String || !key.startsWith('wlog_')) continue;
      final raw = workoutBox.get(key);
      if (raw is! Map) continue;
      final log = Map<String, dynamic>.from(raw);

      try {
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
        liveKeys.add(key);

        // day-swapper+sync-load Task 16 (round-1 review D1 F1): OrNull —
        // never now() inside a fingerprinted payload, or the row would
        // never skip. `logged_at` and `created_at` are timestamptz columns
        // DEFAULT now(): omitting them on insert applies the server
        // default once, and ON CONFLICT DO UPDATE leaves an omitted
        // column untouched, so the fingerprint stays stable.
        final resolved = _resolveCompletedAtOrNull(
          log,
          dateKeyPrefix: wlogDate.isNotEmpty ? wlogDate : _dateFromKey(key),
        );

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
        final payload = <String, dynamic>{
          'user_id': userId,
          'workout_name': wlogName,
          'date': wlogDate,
          if (resolved != null) 'logged_at': resolved,
          'duration_seconds': log['duration_seconds'],
          if (resolved != null) 'created_at': resolved,
        };

        await index.pushIfChanged(
          key,
          () => SyncFingerprint.of(payload),
          () async {
            if (resolved == null) {
              unawaited(ErrorTelemetry.logEvent(
                'sync_completed_at_fallback',
                message:
                    'hiveKey=$key table=workout_logs timestamps_omitted',
              ));
            }
            await _supabase.client.from('workout_logs').upsert(payload,
                onConflict: 'user_id,date,workout_name');
            return true;
          },
        );
      } catch (e, st) {
        debugPrint('[SyncService._syncWorkoutLogs] Failed key=$key: $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_for', skipServerPost: true));
        try {
          await _reportSyncFailure(opType: 'upsert_workout_log', error: e);
        } catch (_) {}
      }
    }

    await index.commit(liveKeys: liveKeys);
  }

  /// Pushes individual exercise logs (exlog_* keys) to
  /// Supabase workout_log_exercises (summary) + workout_log_sets (per-set).
  ///
  /// F4 · Per-set rows preserve granular weight/reps/duration across devices.
  /// The summary row (workout_log_exercises) stays for AI features + analytics.
  ///
  /// Day-swapper + sync-load Task 13 — moved onto the shared `SyncSkipIndex`
  /// helper (spec §5.9). `exlogPayloadFingerprint` is UNCHANGED (plan D4), so
  /// every stored fingerprint from before this change still matches and this
  /// lands with zero re-push burst.
  Future<void> _syncExerciseLogs(String userId) async {
    final workoutBox = _hive.workoutBox;
    final exlogIndex = SyncSkipIndex(
      box: workoutBox,
      domain: SyncSkipDomain.exlog,
      disabled: _hashSkipKillSwitchOn(SyncSkipDomain.exlog),
      ownerChangedNow: () => ownerChangedSince(userId),
      reportFailure: (op, e, st) =>
          unawaited(_reportSyncFailure(opType: op, error: e)),
    );

    for (final key in workoutBox.keys) {
      if (exlogIndex.aborted) break;
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

        final summaryPayload = <String, dynamic>{
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
        };

        // ── PER-SET ROWS (F4) — resolved BEFORE either network call, so the
        // fingerprint below covers the whole bundle.
        // Upserts a row per set into `workout_log_sets`. Natural key is
        // (workout_log_id, exercise_id, set_number) → idempotent across
        // re-syncs and retries. Source: legacy `sets_detail` OR the new
        // WorkoutWriteService `sets` list (Plan A A-5).
        final pendingSetRows = <Map<String, dynamic>>[];
        if (resolvedSets.isNotEmpty) {
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
              // Guard: workout_log_sets.duration_secs must satisfy
              // wls_duration_secs_realistic (<=3600). A per-set duration >1h is
              // implausible (a set, not a session) — clamp a glitch value rather
              // than let the all-or-nothing per-set upsert 23514 and drop the
              // batch. Mirrors the reps clamp above (WI-3 constraint-parity,
              // diagnose a3e8f1).
              final rawSetDur =
                  (sm['duration_seconds'] ?? sm['duration_sec']) as num?;
              final clampedSetDur =
                  rawSetDur == null ? null : rawSetDur.clamp(0, 3600).toInt();
              if (rawSetDur != null && rawSetDur != clampedSetDur) {
                unawaited(ErrorTelemetry.logEvent(
                  'wls_duration_out_of_range',
                  message:
                      'raw=$rawSetDur clamped=$clampedSetDur set=$setNum exercise=$exerciseId',
                ));
              }
              pendingSetRows.add({
                'user_id': userId,
                'workout_log_id': workoutLogId,
                'exercise_id': exerciseId,
                'set_number': setNum,
                'weight_kg': sm['weight_kg'],
                'reps': clampedSetReps,
                'duration_secs': clampedSetDur,
                'distance_km': sm['distance_km'],
                'completed_at': completedAt,
              });
            }
          }
        }

        // OI-204 / Task 13 — the fingerprint is now a THUNK evaluated inside
        // SyncSkipIndex's own try (plan D4): a throwing fingerprint fails
        // open (push runs, nothing recorded) with no domain-specific
        // telemetry needed here any more -- the helper's debug log covers it.
        await exlogIndex.pushIfChanged(
          key,
          () => SyncService.exlogPayloadFingerprint(summaryPayload, pendingSetRows),
          () async {
            await _supabase.client.from('workout_log_exercises').upsert(
              summaryPayload,
              onConflict: 'user_id,workout_log_id,exercise_id,set_number',
            );
            // Guard AT THE SINK (e5c2d1 CLASS 1), as nlog does: an account
            // switch between the two awaits must not write the sets under a
            // stale userId (round-2 review D1 F2).
            if (ownerChangedSince(userId)) return false;
            if (pendingSetRows.isNotEmpty) {
              try {
                // Fix 2026-06-02: user_id added to the conflict key (matching
                // new index uniq_wls_user_wlog_ex_set) — prevents cross-user
                // collision on the date-only workout_log_id.
                await _supabase.client
                    .from('workout_log_sets')
                    .upsert(pendingSetRows, onConflict: 'user_id,workout_log_id,exercise_id,set_number');
              } catch (e, st) {
                debugPrint(
                    '[SyncService._syncExerciseLogs] per-set push failed key=$key: $e');
                unawaited(ErrorTelemetry.recordNonFatal(e, st,
                    reason: 'sync_service_if_7', skipServerPost: true));
                // G1 (spec §7): a catch inside pushIfChanged( must rethrow or
                // return false; -- the bundle is NOT fully synced, so nothing
                // is recorded and the whole bundle (summary + sets) re-pushes
                // next pass. Fix round 1 (2026-09-27): `_reportSyncFailure` is
                // the only path to the server-side `client_errors` row
                // (via the log-client-error Edge Function) that server
                // alerting reads -- `ErrorTelemetry.recordNonFatal` above is
                // Crashlytics-only. `unawaited` (not `await`) so the closure
                // returns promptly.
                unawaited(_reportSyncFailure(
                    opType: 'upsert_workout_log_sets', error: e));
                return false;
              }
            }
            return true;
          },
        );
      } catch (e, st) {
        debugPrint('[SyncService._syncExerciseLogs] Failed key=$key: $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_catch_5', skipServerPost: true));
        try {
          await _reportSyncFailure(opType: 'upsert_exercise_log', error: e);
        } catch (_) {}
      }
    }

    final liveExlogKeys = workoutBox.keys
        .whereType<String>()
        .where((k) => k.startsWith('exlog_'))
        .toSet();
    await exlogIndex.commit(liveKeys: liveExlogKeys);
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
    final resolved =
        _resolveCompletedAtOrNull(row, dateKeyPrefix: dateKeyPrefix);
    if (resolved != null) return resolved;
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

  /// Steps 1–6 of [_resolveCompletedAt] with NO wall-clock fallback: returns
  /// null when nothing in the row or its date prefix resolves. Use this for
  /// any value that feeds a SyncSkipIndex fingerprint (day-swapper+sync-load
  /// Task 16, round-1 review D1 F1) — a now() there never skips.
  String? _resolveCompletedAtOrNull(
    Map<String, dynamic> row, {
    String? dateKeyPrefix,
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
    return null;
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
  ///
  /// Day-swapper + sync-load Task 14 — moved onto SyncSkipIndex (domain
  /// `completion`, spec §5.9) and the completion time now comes from
  /// ScheduleCompletionTime, never `DateTime.now()` (recurrence of 5a36ad,
  /// spec §1.6). This is a brand-new index (no pre-existing stored
  /// fingerprints), so the fingerprint function is the generic
  /// `SyncFingerprint.of` rather than a bespoke one — nothing to preserve.
  Future<void> _syncScheduleCompletions(String userId) async {
    final workoutBox = _hive.workoutBox;
    final completionIndex = SyncSkipIndex(
      box: workoutBox,
      domain: SyncSkipDomain.completion,
      disabled: _hashSkipKillSwitchOn(SyncSkipDomain.completion),
      ownerChangedNow: () => ownerChangedSince(userId),
      reportFailure: (op, e, st) =>
          unawaited(_reportSyncFailure(opType: op, error: e)),
    );
    final liveDates = <String>{};

    for (final key in workoutBox.keys) {
      if (key is! String || !key.startsWith('schedule_')) continue;
      final raw = workoutBox.get(key);
      if (raw is! Map) continue;
      final entry = Map<String, dynamic>.from(raw);

      if (entry['status'] != 'completed') continue;

      final date = entry['date'] as String?;
      if (date == null) continue;
      liveDates.add(date);

      try {
        // audit-2026-05-16 F3-1.3 — `duration_seconds` lives on the
        // `wlog_<dateStr>` workout-log row (written by
        // `WorkoutWriteService.markCompleted`), NOT on the schedule entry.
        final wlog = workoutBox.get('wlog_$date');
        final durationSeconds =
            wlog is Map ? (wlog['duration_seconds'] as num?)?.toInt() : null;

        // Task 14 / spec §5.12 — resolver order: the schedule row's own
        // legacy ISO field, then its completed_at_ms; if the schedule row
        // has neither, fall back to the matching wlog's ISO completed_at
        // (spec's 3rd step; markCompleted always writes a real ISO string
        // there, workout_write_service.dart:540, so no further derivation is
        // needed). Absent -> OMIT the field entirely (never "now").
        final resolvedCompletedAt =
            ScheduleCompletionTime.scheduledCompletedAtIso(entry) ??
                (wlog is Map ? (wlog['completed_at'] as String?) : null);

        final payload = <String, dynamic>{
          'user_id': userId,
          'scheduled_date': date,
          'day_of_week': entry['day_of_week']?.toString(),
          'workout_name': entry['workout_name'],
          if (durationSeconds != null) 'duration_seconds': durationSeconds,
          if (resolvedCompletedAt != null) 'completed_at': resolvedCompletedAt,
        };

        await completionIndex.pushIfChanged(
          date,
          () => SyncFingerprint.of(payload),
          () async {
            await _supabase.client
                .from('workout_schedule_completions')
                .upsert(payload, onConflict: 'user_id,scheduled_date');
            return true;
          },
        );
      } catch (e, st) {
        debugPrint('[SyncService._syncScheduleCompletions] Failed key=$key: $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_for_2', skipServerPost: true));
        // Task 13/14 review fix round 1 (2026-09-27) — this outer catch only
        // guards the payload-build code above (pushIfChanged never rethrows;
        // a push() failure is already reported via the domain's own opType
        // through the `reportFailure` closure passed above), but it MUST
        // still keep its own `_reportSyncFailure` call so a payload-build
        // exception (before pushIfChanged is even reached) still reaches the
        // server-side client_errors table -- exactly the shape Task 13's own
        // outer catches (`_syncExerciseLogs`, `_syncNutritionLogs`) kept.
        try {
          await _reportSyncFailure(opType: 'upsert_schedule_completion', error: e);
        } catch (_) {}
      }
    }

    await completionIndex.commit(liveKeys: liveDates);
  }

  /// Pushes weekly streak snapshots (healthBox['streaks']) to Supabase.
  /// day-swapper+sync-load Task 16: routed through SyncSkipIndex (domain
  /// streak; index stored in healthBox per plan D12 — streak rows already
  /// live there).
  Future<void> _syncStreaks(String userId) async {
    final healthBox = _hive.healthBox;
    final logs = healthBox.get('streaks');
    if (logs == null) return;

    final index = SyncSkipIndex(
      box: healthBox,
      domain: SyncSkipDomain.streak,
      disabled: _hashSkipKillSwitchOn(SyncSkipDomain.streak),
      ownerChangedNow: () => ownerChangedSince(userId),
      reportFailure: (op, e, st) =>
          unawaited(_reportSyncFailure(opType: op, error: e)),
    );

    final items = (logs as List).whereType<Map>();
    final liveKeys = <String>{};
    for (final log in items) {
      if (index.aborted) break;
      final data = Map<String, dynamic>.from(log);
      final weekStart = data['week_start']?.toString() ?? '';
      if (weekStart.isEmpty) continue;
      liveKeys.add(weekStart);
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

        await index.pushIfChanged(
          weekStart,
          () => SyncFingerprint.of(payload),
          () async {
            await _supabase.client
                .from('streaks')
                .upsert(payload, onConflict: 'user_id,week_start');
            return true;
          },
        );
      } catch (e, st) {
        debugPrint('[SyncService._syncStreaks] $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_for_11', skipServerPost: true));
        try {
          await _reportSyncFailure(opType: 'upsert_streak', error: e);
        } catch (_) {}
      }
    }

    await index.commit(liveKeys: liveKeys);
  }

  /// Pulls workout session logs from cloud workout_logs into local Hive.
  /// [preFetched] (C3 single-call): injected `workout_logs` rows; legacy callers
  /// omit it → paginated network read. Plan §4.
  Future<void> _restoreWorkoutLogs(String userId, String since,
      {Object? preFetched = _kNoInject}) async {
    try {
      final rows = identical(preFetched, _kNoInject)
          ? await _fetchAllRows(
              'workout_logs', userId,
              dateColumn: 'created_at', since: since, orderBy: 'created_at',
            )
          : (preFetched as List? ?? const []);

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

        // Local-wins / additive restore (slow-boot guard 4e8b1d): keep a local
        // wlog summary that may reflect a just-completed session not yet synced
        // while the background restore runs. Only write absent rows.
        if (_hive.workoutBox.get(logId) != null) continue;
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
          // F39 (2026-06-07): `sets_completed` removed. Migration 067
          // DROPPED workout_logs.sets_completed (cloud was 100% NULL — see
          // push-side note ~line 115), so the cloud select never returns it
          // and `map['sets_completed']` was always null. Dead restore write.
          'duration_seconds': map['duration_seconds'],
          'source': 'cloud_restore',
        });
      }
    } catch (e, st) {
      debugPrint('[SyncService._restoreWorkoutLogs] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_for_12', skipServerPost: true));
      try {
        await _reportSyncFailure(opType: 'restore_workout_logs', error: e);
      } catch (_) {}
    }
  }

  /// [preFetchedExercises] / [preFetchedSets] (C3 single-call): this restore is
  /// special — it reads BOTH `workout_log_exercises` AND (a second fetch)
  /// `workout_log_sets`. When injected, both network reads are skipped and the
  /// bundle arrays are used instead; the per-set reconstruction (groupKey
  /// `'$wlId|$exId'`) is unchanged. Legacy callers omit both → two network
  /// reads, byte-identical. Plan `restore-single-call-c3.md` §4 (H-5 groupKey).
  Future<void> _restoreExerciseLogs(String userId, String since,
      {Object? preFetchedExercises = _kNoInject,
      Object? preFetchedSets = _kNoInject}) async {
    try {
      final rows = identical(preFetchedExercises, _kNoInject)
          ? await _fetchAllRows(
              'workout_log_exercises', userId,
              dateColumn: 'completed_at', since: since, orderBy: 'completed_at',
            )
          : (preFetchedExercises as List? ?? const []);

      // F4 · Pre-fetch all per-set rows once and index by
      // (workout_log_id, exercise_id) so we can reconstruct the Hive
      // `sets_detail` list without a per-exercise round-trip.
      final setsByLogExercise = <String, List<Map<String, dynamic>>>{};
      try {
        final setRows = identical(preFetchedSets, _kNoInject)
            ? await _fetchAllRows(
                'workout_log_sets', userId,
                dateColumn: 'completed_at', since: since, orderBy: 'completed_at',
              )
            : (preFetchedSets as List? ?? const []);
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
            reason: 'sync_service_for_13', skipServerPost: true));
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
          // docs/architecture/sync.md "Hive field-name contract".
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

        // Local-wins / additive restore (slow-boot guard 4e8b1d). Once returning
        // users land on /home WHILE this background restore runs, a local exlog
        // row may hold sets the user just logged (and not yet synced — e.g. a
        // network blip). NEVER overwrite it with the cloud snapshot: only write
        // rows that are absent locally. Mirrors the weight-restore pattern
        // (sync_health.dart:300). Always ensure the row is indexed — this heals
        // an orphaned-but-present row (e4a8b1). closes-diagnose: e4a8b1.
        if (_hive.workoutBox.get(logId) == null) {
          await _hive.workoutBox.put(logId, logMap);
        }
        await WorkoutWriteService.instance
            .addToExlogIndex(_hive.workoutBox, dateStr, logId);
      }
    } catch (e, st) {
      debugPrint('[SyncService._restoreExerciseLogs] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_for_14', skipServerPost: true));
      try {
        await _reportSyncFailure(opType: 'restore_exercise_logs', error: e);
      } catch (_) {}
    }
  }

  /// [preFetched] (C3 single-call): injected `workout_schedule_completions`
  /// rows; legacy callers omit it → network read. Plan §4.
  Future<void> _restoreScheduleCompletions(String userId, String since,
      {Object? preFetched = _kNoInject}) async {
    try {
      final rows = identical(preFetched, _kNoInject)
          ? await _supabase.client
              .from('workout_schedule_completions')
              .select()
              .eq('user_id', userId)
              .gte('completed_at', since)
              .order('scheduled_date')
          : (preFetched as List? ?? const []);

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
        } else if (date.isNotEmpty) {
          // BUG-F (e9b4a2): no local schedule row for this date — typically an
          // OUT-OF-PLAN-WINDOW completion (logged ad-hoc, or a past phase whose
          // current plan_json window no longer covers it). Pre-fix this was
          // skipped, so the completion never reached local Hive: the streak
          // walk (_calculateStreak reads schedule_<date> status=='completed')
          // and the past-phase scroll-back saw NOTHING after a reinstall, so
          // the streak read 0 despite real workouts (APK +34 obs 5.2).
          // Synthesize a completed row, mirroring
          // WorkoutWriteService.markCompleted's no-prior-schedule branch
          // (type='logged' counts as a workout day in the streak walk).
          // B-pass P2 (e9b4a2): write BOTH completed_at (ISO, read by
          // getScheduleForDate's stale-completion guard) AND completed_at_ms
          // (epoch, the shape WorkoutWriteService.markCompleted's synthesize
          // branch uses) so the two synthesize paths produce an identical row
          // schema — no reader drift if getScheduleForDate changes later.
          final completedAtMs =
              DateTime.tryParse((map['completed_at'] ?? '').toString())
                  ?.millisecondsSinceEpoch;
          await _hive.workoutBox.put(key, {
            'date': date,
            'workout_name': map['workout_name'] ?? 'Workout',
            'status': 'completed',
            'type': 'logged',
            'completed_at': map['completed_at'],
            'completed_at_ms': completedAtMs,
            'duration_seconds': map['duration_seconds'],
            'source': 'cloud_restore_completion',
          });
          // b3f9d1: ALSO synthesize an additive wlog_<date> row so this orphan
          // completion is COUNTED by the type=='workout_log' readers
          // (getWeeklyWorkoutCounts → "This Week" tile + frequency chart,
          // getWorkoutLogs, badge total, AI snapshot) even when the SEPARATE
          // workout_logs restore path (_restoreWorkoutLogs) has no row for this
          // date — the schedule_ row above satisfies only the streak walk. Mirror
          // the canonical wlog shape (f1c8e4: type:'workout_log' + completed_at).
          // Additive / local-wins: only fill the gap, never overwrite a real
          // logged session (which carries duration + per-exercise data).
          final wlogKey = 'wlog_$date';
          if (_hive.workoutBox.get(wlogKey) == null) {
            await _hive.workoutBox.put(wlogKey, {
              'type': 'workout_log',
              'workout_name': map['workout_name'] ?? 'Workout',
              'date': date,
              'duration_seconds': map['duration_seconds'],
              'completed_at': map['completed_at'],
              'completed_at_ms': completedAtMs,
              'source': 'cloud_restore_completion',
            });
          }
        }
      }
    } catch (e, st) {
      debugPrint('[SyncService._restoreScheduleCompletions] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_if_12', skipServerPost: true));
      try {
        await _reportSyncFailure(opType: 'restore_schedule_completions', error: e);
      } catch (_) {}
    }
  }

  /// [preFetched] (C3 single-call): injected `streaks` rows; legacy callers
  /// omit it → network read. Plan §4.
  Future<void> _restoreStreaks(String userId,
      {Object? preFetched = _kNoInject}) async {
    try {
      final rows = identical(preFetched, _kNoInject)
          ? await _supabase.client
              .from('streaks')
              .select()
              .eq('user_id', userId)
              .order('week_start', ascending: false)
              .limit(52)
          : (preFetched as List? ?? const []);

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
          reason: 'sync_service_for_21', skipServerPost: true));
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
  ///
  /// Day-swapper + sync-load Task 20 (spec §5.9 plan row): wrapped in
  /// SyncSkipIndex so an unchanged bundle stops re-uploading every pass. The
  /// stored fingerprint under kPlanBundleRowKey ('bundle') in the SAME
  /// user-scoped workoutBox IS `plan_bundle_cloud_fingerprint` (spec §5.7 L2,
  /// read by Task 22's restore-merge skip via
  /// `SyncSkipIndex.readIndex(HiveService.instance.workoutBox,
  /// SyncSkipDomain.plan.indexKey)[kPlanBundleRowKey]`). `synced_at` is a
  /// sent-at stamp (spec §5.9's fingerprint table) and is EXCLUDED from the
  /// fingerprint input so a re-push driven only by the clock never happens;
  /// it is still sent on the wire (not a past timestamp — §5.12 does not
  /// apply to it).
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

      final planCopy = plan is Map ? Map<String, dynamic>.from(plan) : plan;
      final planBundle = {
        'plan': planCopy,
        'plan_start_date': planStart,
        'plan_end_date': planEnd,
        'schedules': schedules,
        'synced_at': DateTime.now().toIso8601String(),
      };

      final index = SyncSkipIndex(
        box: workoutBox,
        domain: SyncSkipDomain.plan,
        disabled: _hashSkipKillSwitchOn(SyncSkipDomain.plan),
        ownerChangedNow: () => ownerChangedSince(userId),
        reportFailure: (op, e, st) =>
            unawaited(_reportSyncFailure(opType: op, error: e)),
      );
      await index.pushIfChanged(
        kPlanBundleRowKey,
        () => SyncFingerprint.of({
          'plan': planCopy,
          'plan_start_date': planStart,
          'plan_end_date': planEnd,
          'schedules': schedules,
        }),
        () async {
          await _supabase.client.from('user_progress').upsert({
            'user_id': userId,
            'plan_json': planBundle,
          }, onConflict: 'user_id');
          return true;
        },
      );
      await index.commit(liveKeys: {kPlanBundleRowKey});
    } catch (e, st) {
      debugPrint('[SyncService._syncWorkoutPlan] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_if_16', skipServerPost: true));
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
  /// [preFetched] (C3 single-call): injected `workout_plan` limit-1 array (the
  /// `user_progress` row carrying `plan_json`); legacy callers omit it → network
  /// read. Plan §4.
  Future<void> _restoreWorkoutPlan(String userId,
      {Object? preFetched = _kNoInject,
      Set<String>? preFetchedDeletedTemplateIds}) async {
    try {
      final rows = identical(preFetched, _kNoInject)
          ? await _supabase.client
              .from('user_progress')
              .select('plan_json')
              .eq('user_id', userId)
              .limit(1)
          : (preFetched as List? ?? const []);

      if (rows.isEmpty) return;
      final planJson = (rows.first as Map)['plan_json'];
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
      // phase window. Re-anchor them MONOTONICALLY + phase-gated (free-tier-hold
      // durability #1, PlanWindowReanchor): a hold extends plan_end locally, and
      // this stale-cloud snapshot must NOT collapse it — same phase keeps the
      // later plan_end; a fresh install / phase advance takes cloud verbatim
      // (preserving the a7d3f1 stale-plan_start heal).
      final reanchor = PlanWindowReanchor.resolve(
        localStart: MigratedKey.read<String>('plan_start_date'),
        localEnd: MigratedKey.read<String>('plan_end_date'),
        cloudStart: planStart is String ? planStart : null,
        cloudEnd: planEnd is String ? planEnd : null,
      );
      final reStart = reanchor.planStart;
      final reEnd = reanchor.planEnd;
      if (reStart != null) {
        await MigratedKey.write('plan_start_date', reStart);
      }
      if (reEnd != null) {
        await MigratedKey.write('plan_end_date', reEnd);
      }
      // Day-swapper + sync-load Task 22 (spec sec 5.7 L2): skip the WHOLE
      // merge when this device already knows the cloud holds exactly this
      // bundle -- either because THIS device just confirmed a push of it
      // (Task 20's _syncWorkoutPlan), or because a prior restore/reconcile
      // already merged it. The stored value lives at the SAME Hive slot
      // Task 20's confirmed push writes: SyncSkipIndex.readIndex(workoutBox,
      // SyncSkipDomain.plan.indexKey)[kPlanBundleRowKey]. Fingerprinted over
      // the SAME 4-key shape the push side uses ({plan, plan_start_date,
      // plan_end_date, schedules} -- synced_at excluded, spec sec 5.9's
      // fingerprint table) so a round-tripped, unchanged bundle always
      // matches regardless of which device produced it last. Scoped to ONLY
      // the schedule-merge call -- the plan-seed ('current_plan') and
      // plan-window-reanchor writes just above are cheap (at most 3 keys)
      // and independent of whether the SCHEDULE bundle changed, so they are
      // deliberately left to run every pass.
      final planFingerprintInput = Map<String, dynamic>.from(bundle)
        ..remove('synced_at');
      final downloadedPlanFingerprint = SyncFingerprint.of(planFingerprintInput);
      final storedPlanFingerprint = SyncSkipIndex.readIndex(
          _hive.workoutBox, SyncSkipDomain.plan.indexKey)[kPlanBundleRowKey];
      // A matching fingerprint says the CLOUD bundle is unchanged, not that
      // the LOCAL rows still hold it. Before Task 22 every launch re-merged,
      // which incidentally put back a schedule_<date> row deleted locally;
      // reconcile()'s needsHeal cannot, because getWeek() omits absent keys.
      // So the skip also requires every bundled key to still exist locally
      // (in-memory containsKey, no I/O); one absent key runs the full merge.
      // Merge review F3 (OI-252 ghost days): a ghost day is filtered out of
      // every merge below and so is never written, which would leave it
      // "absent" forever and defeat this skip on every launch for any
      // account that has one. A ghost day's template key is gone from this
      // phone's Hive (the delete removed it, and a deleted template is never
      // restored), so an absent row whose `tmpl_<uuid>` key is also absent
      // locally counts as accounted for. Local-only, no deleted-template
      // query. Residual: a real row deleted locally whose template is ALSO
      // missing locally is not put back until the bundle changes.
      bool bundledRowAccountedFor(Object? key, Object? value) {
        if (_hive.workoutBox.containsKey(key)) return true;
        if (value is! Map) return false;
        final tmplKey = value['template_id'];
        return tmplKey is String &&
            cloudIdFromKey(tmplKey) != null &&
            !_hive.workoutBox.containsKey(tmplKey);
      }

      final allBundledRowsPresent = schedules is Map &&
          schedules.entries
              .every((e) => bundledRowAccountedFor(e.key, e.value));
      final skipPlanMerge = SyncFlags.planMergeSkipWhenKnownEnabled &&
          storedPlanFingerprint != null &&
          storedPlanFingerprint == downloadedPlanFingerprint &&
          allBundledRowsPresent;
      if (schedules is Map && !skipPlanMerge) {
        // OI-252 (merged from main) — the `plan_json` snapshot is a frozen
        // bundle of whatever `schedule_*` rows looked like at push time, so a
        // day scheduled against a template that has since been deleted is a
        // GHOST day: applying it would resurrect exactly the reference the
        // delete was meant to remove, via a separate restore path from
        // `_restoreScheduledWorkouts`. Filtered out BEFORE the L1/L3 bundle
        // merge. The deleted-template set is resolved once, lazily (unless
        // injected for a test), and only if an entry carries a template_id,
        // so a bundle with no template days costs no extra query. Shared
        // predicate with `PlanIntegrityReconciler`'s own ghost-day filter —
        // `isGhostScheduleEntry` — so the two paths cannot drift.
        Set<String>? deletedTemplateIdsCache = preFetchedDeletedTemplateIds;
        Future<Set<String>> deletedTemplateIds() async =>
            deletedTemplateIdsCache ??= await _deletedTemplateCloudIds(userId);
        final live = <String, dynamic>{};
        for (final entry in schedules.entries) {
          final incoming = entry.value;
          if (incoming is Map &&
              incoming['template_id'] != null &&
              isGhostScheduleEntry(Map<String, dynamic>.from(incoming),
                  await deletedTemplateIds())) {
            continue;
          }
          live[entry.key.toString()] = incoming;
        }
        final result =
            await PlanIntegrityReconciler.mergeScheduleBundleIntoHive(live);
        if (result.discardedLocalArrangement) {
          unawaited(ErrorTelemetry.logEvent('swap_merge_conflict',
              message: 'source=restoreWorkoutPlan'));
        }
        // "It is set ... after a successful merge of a downloaded bundle"
        // (spec sec 5.7 L2) -- only reached when mergeScheduleBundleIntoHive
        // returns without throwing; a throw propagates to this method's own
        // try/catch below, so this line is unreached on failure and no
        // fingerprint is recorded for a merge that did not actually finish.
        await SyncSkipIndex.recordConfirmed(_hive.workoutBox,
            SyncSkipDomain.plan, kPlanBundleRowKey, downloadedPlanFingerprint);
      }
    } catch (e, st) {
      debugPrint('[SyncService._restoreWorkoutPlan] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_if_17', skipServerPost: true));
      try {
        await _reportSyncFailure(opType: 'restore_workout_plan', error: e);
      } catch (_) {}
    }
  }

  /// OI-252 (stable ID rework) — drains `PendingTemplateDeletes` by
  /// UPSERTing a tombstone per queued id. UPSERT (not UPDATE) so the
  /// tombstone can be CREATED directly even if the creating push for that
  /// id hasn't reached the cloud yet — migration 145's
  /// `workout_templates_delete_final_rename` trigger then makes the
  /// creating push's own later upsert a no-op against the now-deleted row,
  /// so the delete wins regardless of which side's write lands first
  /// (round-1 plan review, finding 2). Called BEFORE the push loop so a
  /// template deleted this session can never be re-created by its own
  /// stale in-memory copy in the same sync pass.
  Future<void> _drainPendingTemplateDeletes(String userId) async {
    for (final entry in PendingTemplateDeletes.read()) {
      var id = entry['id'] as String?;
      final name = entry['name'] as String;
      try {
        // A null id means this template was deleted while still on a
        // legacy (pre-migration) Hive key -- WorkoutWriteService cannot
        // reach Supabase itself (layering), so resolve it here, the one
        // place in this flow with both DB access and the name.
        if (id == null) {
          final rows = await _supabase.client
              .from('workout_templates')
              .select('id')
              .eq('user_id', userId)
              .eq('name', name)
              .isFilter('deleted_at', null)
              .limit(1);
          if (rows.isEmpty || rows.first['id'] is! String) {
            // Nothing live under this name -- either never synced (the
            // common case) or already deleted elsewhere. Either way
            // there is nothing to tombstone.
            await PendingTemplateDeletes.removeByName(name);
            continue;
          }
          id = rows.first['id'] as String;
        }
        await _supabase.client.from('workout_templates').upsert({
          'id': id,
          'user_id': userId,
          'name': name,
          'deleted_at': DateTime.now().toUtc().toIso8601String(),
          'is_active': false,
        }, onConflict: 'id');
        await PendingTemplateDeletes.remove(id);
      } catch (e, st) {
        debugPrint('[SyncService._drainPendingTemplateDeletes] $name: $e');
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_drain_pending_template_deletes'));
        // Left queued — retried on the next template push.
      }
    }
  }

  /// Pushes workout templates (header + exercises + tail vacuum) to
  /// Supabase workout_templates / template_exercises.
  ///
  /// day-swapper+sync-load Task 16: routed through SyncSkipIndex (domain
  /// template). The header upsert, the per-exercise upsert loop and the
  /// tail-vacuum DELETE are ONE bundle per template: any failure inside the
  /// bundle returns false (unconfirmed), so the WHOLE bundle retries next
  /// pass — every write inside is idempotent, so a retry is cheap and safe.
  /// Since OI-252 (merged from main) the header upserts the client-minted id
  /// from the Hive key (`onConflict: 'id'`), so the bundle no longer needs
  /// the post-upsert id SELECT it carried before.
  ///
  /// [forceKeys]: `tmpl_*` keys to re-push even when their fingerprint is
  /// unchanged — the `_syncScheduledWorkouts` FK recovery passes the ONE
  /// template its row could not resolve in the cloud. Without it that
  /// recovery was a no-op (the skip index still called the template
  /// confirmed) and the row fell to the orphan fallback on every pass
  /// (B-pass R1-F1).
  Future<void> _syncWorkoutTemplates(String userId,
      {Set<String> forceKeys = const <String>{}}) async {
    // OI-252 — legacy (`tmpl_<ms>` / `tmpl_<namehash>`) keys must resolve
    // to a real cloud uuid before ANYTHING here can push safely: pushing a
    // legacy-keyed row would mean re-deriving an id in this function too,
    // reintroducing the exact ambiguity the migrator exists to remove.
    // Scoped to THIS function only — never gates `_restoreIfNeeded` as a
    // whole (round-2 plan review: that would starve unrelated domains for
    // an offline user).
    final migrated = await TemplateIdentityMigrator.runIfNeeded(userId);
    if (!migrated) return;

    await _drainPendingTemplateDeletes(userId);

    final workoutBox = _hive.workoutBox;
    final index = SyncSkipIndex(
      box: workoutBox,
      domain: SyncSkipDomain.template,
      disabled: _hashSkipKillSwitchOn(SyncSkipDomain.template),
      ownerChangedNow: () => ownerChangedSince(userId),
      reportFailure: (op, e, st) =>
          unawaited(_reportSyncFailure(opType: op, error: e)),
      forcePushKeys: forceKeys,
    );

    final liveKeys = <String>{};
    for (final key in workoutBox.keys) {
      if (index.aborted) break;
      if (key is! String || !key.startsWith('tmpl_')) continue;
      final raw = workoutBox.get(key);
      if (raw is! Map) continue;
      final tmpl = Map<String, dynamic>.from(raw);
      if (tmpl['type'] != 'template') continue;
      // Defensive — the migrator above should have resolved every legacy
      // key already; skip rather than push under an ambiguous identity.
      final cloudTmplId = cloudIdFromKey(key);
      if (cloudTmplId == null) continue;
      liveKeys.add(key);

      try {
        final tmplName = (tmpl['name'] as String?)?.trim() ?? 'Untitled';
        final exercises = tmpl['exercises'] as List? ?? [];

        // day-swapper+sync-load Task 16: created_at now OMITS the field
        // rather than falling back to DateTime.now() (D2 site
        // sync_workout.dart|created_at). On insert, the column default
        // applies; on update, the column is left untouched.
        //
        // OI-252 — `id` is now the client-minted uuid (from the Hive
        // key), and the upsert targets it directly: `onConflict: 'id'`.
        // This REPLACES the old `onConflict: 'user_id,name'` + a
        // follow-up SELECT-by-name to learn the cloud id — the id is
        // already known, so that lookup (and its 23503-avoidance
        // history, still true of the OLD approach but moot now) is gone.
        // `deleted_at` is deliberately NOT sent — it is trigger-owned;
        // migration 145's `workout_templates_delete_final_rename` makes
        // this whole statement a no-op if the row is already deleted.
        //
        // audit-2026-05-16 E.12 — migration 067 dropped
        // workout_templates.description + estimated_duration_mins (template
        // builder UI never exposes these inputs; 100% NULL across all
        // live rows). Hive `description` field is retained for the restore
        // round-trip (cloud read returns null → empty in Hive).
        Map<String, dynamic> headerPayload() => <String, dynamic>{
              'id': cloudTmplId,
              'user_id': userId,
              'name': tmplName,
              'workout_type':
                  tmpl['workout_focus'] ?? tmpl['workout_type'] ?? 'custom',
              'source': 'user',
              'is_active': true,
              if (tmpl['created_at'] != null)
                'created_at': tmpl['created_at'],
              if (tmpl['last_used_at'] != null)
                'last_used_at': tmpl['last_used_at'],
            };

        await index.pushIfChanged(
          key,
          () => SyncFingerprint.of(<String, dynamic>{
            'header': headerPayload(),
            'exercises': exercises,
          }),
          () async {
            // Upsert template header on its client-minted id. Kept as a
            // single-line chain (`dead_columns_dropped_test.dart` source-greps
            // the literal `from('workout_templates').upsert(` with no
            // whitespace between).
            await _supabase.client.from('workout_templates').upsert(headerPayload(), onConflict: 'id');

            // Backlog #2 (post-Test-#15) — switched from DELETE-then-INSERT
            // to UPSERT now that migration 051 added UNIQUE (template_id,
            // order_index). Each row is independently upserted; a network
            // blip on row N leaves rows 0..N-1 + N+1..end intact (latter are
            // upserts, not inserts, so they update unchanged rows).
            //
            // closes-diagnose: 2026-05-10-template-exercises-upsert-a8b2c7
            // (migration 051 header has the full rationale).
            for (int i = 0; i < exercises.length; i++) {
              final ex = exercises[i] is Map
                  ? Map<String, dynamic>.from(exercises[i] as Map)
                  : <String, dynamic>{};
              // audit-2026-05-16 E.12 — migration 067 dropped exercise_id
              // from template_exercises. The pre-fix `isUuid` UUID-shape
              // check gated the projection of that column; with the column
              // gone, the variable is dead. Removed to satisfy analyzer.
              try {
                await _supabase.client.from('template_exercises').upsert({
                  // APK Test #12.8 / Bug #4 — `id` omitted; child UUID
                  // generated by cloud default on first insert. On
                  // conflict (template_id, order_index), the existing
                  // row's id is preserved and other fields are updated.
                  'template_id': cloudTmplId,
                  // audit-2026-05-16 E.12 — migration 067 dropped 5
                  // columns from template_exercises (exercise_id,
                  // rest_seconds, prescribed_weight, prescribed_time_secs,
                  // notes — all 100% NULL in prod, no UI writers).
                  // Projection trimmed to the surviving columns. Hive-side
                  // fields are retained for the restore round-trip (cloud
                  // → Hive reads of dropped columns return null, which is
                  // the expected default).
                  'exercise_name': ex['exercise_name'] ?? ex['name'] ?? '',
                  'order_index': i,
                  'logging_type': ex['logging_type'] ?? 'weight_reps',
                  // audit-fixwave 2026-07-02 / F17 — fall back to the
                  // exercise's default_sets/default_reps when the
                  // builder's saved map omits sets/reps, so the cloud
                  // template_exercises row is self-describing
                  // (prescribed_* was persisting NULL — benign at read
                  // time because the schedule/active-workout readers
                  // already fall back to default_sets, but a later
                  // custom-exercise edit/delete would then strand the
                  // template with no prescription).
                  if ((ex['sets'] ?? ex['default_sets']) != null)
                    'prescribed_sets': (ex['sets'] ?? ex['default_sets'])
                            is int
                        ? (ex['sets'] ?? ex['default_sets'])
                        : int.tryParse(
                            (ex['sets'] ?? ex['default_sets']).toString()),
                  if ((ex['reps'] ?? ex['default_reps']) != null)
                    'prescribed_reps':
                        (ex['reps'] ?? ex['default_reps']).toString(),
                }, onConflict: 'template_id,order_index');
              } catch (exErr, st) {
                debugPrint(
                    '[SyncService._syncWorkoutTemplates] exercise $i: $exErr');
                // audit-2026-05-11 H-42 — telemetry pair.
                unawaited(ErrorTelemetry.recordNonFatal(exErr, st,
                    reason: 'sync_service_for_24', skipServerPost: true));
                // `_reportSyncFailure` is the only path to the server-side
                // client_errors table (recordNonFatal above is Crashlytics-
                // only via skipServerPost, B2a-2b) — kept, same op string as
                // pre-Task-16.
                // `unawaited` so the closure returns promptly (Task 13
                // precedent, the exlog per-set catch).
                unawaited(_reportSyncFailure(
                    opType: 'upsert_template_exercise', error: exErr));
                // Bundle atomicity (Task 16): one failed exercise fails the
                // WHOLE bundle -- every write here is idempotent, so
                // retrying the header + all exercises + the vacuum next
                // pass is cheap.
                return false;
              }
            }

            // APK Test #15.1 / Bug B — vacuum the tail. Migration 051
            // (Test #15 / Backlog #2) added UNIQUE(template_id,
            // order_index) and switched DELETE-then-INSERT → upsert with
            // onConflict. That fix preserved no-torn-state on partial
            // failure but introduced a NEW failure mode: when a template
            // shrinks (15 exercises → 5), only slots 0..4 are upserted;
            // slots 5..14 from the prior version remain orphaned in cloud.
            //
            // Tail vacuum bounds the cloud row count to exactly the local
            // exercises.length. One round-trip per template. Idempotent.
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
              return false;
            }
            return true;
          },
        );
      } catch (e, st) {
        debugPrint('[SyncService._syncWorkoutTemplates] $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_catch_10', skipServerPost: true));
        try {
          await _reportSyncFailure(
              opType: 'upsert_workout_template', error: e);
        } catch (_) {}
      }
    }

    await index.commit(liveKeys: liveKeys);
  }

  /// OI-252 (stable ID rework) — the set of cloud `workout_templates.id`
  /// values that are soft-deleted (migration 145's `deleted_at`), for
  /// every restore-side function that must treat a deleted template's
  /// downstream data (schedule days, plan_json entries) as gone rather
  /// than as an ordinary missing reference. Independently self-contained
  /// per caller (round-2 plan review, finding 3: the templates-restore,
  /// plan-restore and schedule-restore Futures run in PARALLEL on most
  /// restore paths, so nothing here may depend on another Future's
  /// completion or on `workoutBox` state a sibling Future might still be
  /// writing).
  ///
  /// Pass [preFetchedTemplateRows] when the caller already fetched the
  /// FULL `workout_templates` set (live + deleted, e.g. `_restoreWorkoutTemplates`
  /// itself, or the C3 single-call bundle's `workout_templates` key) — no
  /// extra query. Every other caller (`_restoreWorkoutPlan`,
  /// `_restoreScheduledWorkouts`, and both `*ForSyncDomain` entry points,
  /// none of which receive templates rows) runs one light indexed query.
  Future<Set<String>> _deletedTemplateCloudIds(
    String userId, {
    List? preFetchedTemplateRows,
  }) async {
    try {
      final rows = preFetchedTemplateRows ??
          await _supabase.client
              .from('workout_templates')
              .select('id, deleted_at')
              .eq('user_id', userId)
              .not('deleted_at', 'is', null)
              .limit(1000);
      final ids = <String>{};
      for (final row in rows) {
        final map = row as Map;
        if (map['deleted_at'] == null) continue;
        final id = map['id'] as String?;
        if (id != null) ids.add(id);
      }
      return ids;
    } catch (e, st) {
      debugPrint('[SyncService._deletedTemplateCloudIds] $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_deleted_template_cloud_ids'));
      // Fail EMPTY, never fail closed-as-"everything deleted" — an
      // empty set means every downstream filter that uses it is a
      // no-op this pass, which is the safe direction (nothing the user
      // did not delete is ever removed by an uncertain answer here).
      return const {};
    }
  }

  /// Public forwarder for [_deletedTemplateCloudIds] — the boot-time
  /// [PlanIntegrityReconciler] lives in a separate file/library (it is not
  /// `part of` this one) and needs the same deleted-templates set for its
  /// own `plan_json.schedules` ghost-day filter, so it cannot reach the
  /// private method directly.
  Future<Set<String>> deletedTemplateCloudIdsForUser(String userId) =>
      _deletedTemplateCloudIds(userId);

  /// Restores workout templates (with exercises) from Supabase.
  /// [preFetched] (C3 single-call): injected `workout_templates` rows, each
  /// carrying its nested `template_exercises[]` embed (the verbatim PostgREST
  /// shape the parser reads). Legacy callers omit it → network read.
  /// Plan §4 (H-1 embed nesting preserved).
  ///
  /// OI-252 (stable ID rework) — REWRITTEN. The old restore keyed a Hive
  /// row by `tmpl_<hash(lower(name))>` (colliding with the create path's
  /// `tmpl_<ms>` only by luck of a later migrator pass) and SWEPT every
  /// local `tmpl_*` key the cloud didn't return — which deleted a
  /// not-yet-pushed local template on any transient partial response.
  /// Both are gone: the key is now `templateKeyFor(id)` (the SAME key a
  /// local create/push already uses, once the legacy-key migrator has
  /// run), and removal happens ONLY on positive evidence — a row this
  /// cloud fetch reports as `deleted_at`-set. A local row this fetch
  /// simply doesn't mention (an unpushed creation, or a fetch that
  /// legitimately returned fewer than the full set) is left alone.
  ///
  /// OI-252 B-pass finding 2 (2026-09-27) — the legacy-key migrator MUST
  /// run here too, not just in `_syncWorkoutTemplates`. This is the
  /// restore path `restoreLightweightAlways` calls on every normal
  /// sign-in once Hive already has local data (the common case for a
  /// returning user); before this fix a device holding a pre-rework
  /// legacy-keyed template (`tmpl_<ms>` / `tmpl_<namehash>`) never got it
  /// rekeyed on this path, so the cloud-authoritative copy landed under a
  /// NEW `tmpl_<uuid>` key while the old legacy row sat untouched —
  /// `TemplatesNotifier.build` filters by `type=='template'`, not key
  /// prefix, so both rendered as separate templates until
  /// `weeklyFullSync` happened to run. Scoped to this function only —
  /// never gates `_restoreIfNeeded`/`restoreLightweightAlways` as a whole
  /// (round-2 plan review: that would starve unrelated domains for an
  /// offline user). Mirrors `_syncWorkoutTemplates`'s identical gate.
  Future<void> _restoreWorkoutTemplates(String userId,
      {Object? preFetched = _kNoInject}) async {
    final migrated = await TemplateIdentityMigrator.runIfNeeded(userId);
    if (!migrated) return;

    try {
      final rows = identical(preFetched, _kNoInject)
          ? await _supabase.client
              .from('workout_templates')
              .select('*, template_exercises(*)')
              .eq('user_id', userId)
              .order('deleted_at', ascending: true, nullsFirst: true)
              .limit(500)
          : (preFetched as List? ?? const []);

      final pendingDeleteIds = PendingTemplateDeletes.read()
          .map((e) => e['id'] as String?)
          .whereType<String>()
          .toSet();

      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final id = map['id'] as String? ?? '';
        if (id.isEmpty) continue;
        final hiveKey = templateKeyFor(id);

        if (map['deleted_at'] != null) {
          // Positive evidence of a delete -- remove any local copy and
          // its schedule references. `_cleanScheduleReferencesToTemplate`
          // targets both the Hive-key AND the raw-cloud-id shapes (schedule
          // rows may hold either — see that helper's doc), so this covers
          // both. OI-252's replacement for the old canonicalKeys/deleteAll
          // stale-key SWEEP (removed entirely — a blanket "not in the
          // cloud's live set" sweep would have deleted every not-yet-pushed
          // local template on a device's first restore).
          final hadLocalCopy = _hive.workoutBox.get(hiveKey) != null;
          if (hadLocalCopy) {
            await _hive.workoutBox.delete(hiveKey);
          }
          await _cleanScheduleReferencesToTemplate(
              hiveKey: hiveKey, cloudId: id);
          if (hadLocalCopy) {
            unawaited(ErrorTelemetry.logEvent(
              'deleted_template_removed_during_restore',
              message: 'id=$id',
            ));
          }
          continue;
        }

        // An offline delete on THIS device must not be undone by a
        // restore racing ahead of its own drain — skip a row this
        // device itself queued for deletion, even though the cloud
        // still (briefly) reports it live.
        if (pendingDeleteIds.contains(id)) continue;

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

        // F6 · Always refresh template content from cloud — covers the
        // case where the user edited a template on another device.
        final restored = <String, dynamic>{
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
        };
        // Hermes h7F1 (diagnose f1c6b4): this runs on EVERY launch, so an
        // unchanged template was re-written every time. "Refresh from cloud"
        // still holds — a template that differs in any field is written —
        // but an identical one is left alone. Kill switch
        // disable_restore_write_if_changed.
        final existing = _hive.workoutBox.get(hiveKey);
        if (existing is Map &&
            SyncFlags.restoreWriteIfChangedEnabled &&
            SyncFingerprint.canonicalJson(existing) ==
                SyncFingerprint.canonicalJson(restored)) {
          continue;
        }
        await _hive.workoutBox.put(hiveKey, restored);
      }
    } catch (e, st) {
      debugPrint('[SyncService._restoreWorkoutTemplates] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_if_18', skipServerPost: true));
      try {
        await _reportSyncFailure(opType: 'restore_workout_templates', error: e);
      } catch (_) {}
    }
  }

  /// OI-252 — cleans every future, non-terminal `schedule_*`/`displaced_*`
  /// entry referencing a deleted template, matching on EITHER [hiveKey]
  /// (the shape a local `template_service.dart` assignment writes) or
  /// [cloudId] as a bare string (the shape a pre-fix
  /// `_restoreScheduledWorkouts` could have written, and the shape a
  /// not-yet-migrated device's schedule rows may still hold). Delegates
  /// to `TemplateService.cleanSyncTemplateSchedule`'s terminal-row-safe
  /// unschedule logic rather than duplicating it.
  Future<void> _cleanScheduleReferencesToTemplate({
    required String hiveKey,
    required String cloudId,
  }) async {
    try {
      await TemplateService.instance.cleanSyncTemplateSchedule(hiveKey);
      await TemplateService.instance.cleanSyncTemplateSchedule(cloudId);
    } catch (e, st) {
      debugPrint('[SyncService._cleanScheduleReferencesToTemplate] $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_clean_schedule_refs_deleted_template'));
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
    final index = SyncSkipIndex(
      box: workoutBox,
      domain: SyncSkipDomain.sched,
      disabled: _schedHashSkipDisabled,
      ownerChangedNow: () => ownerChangedSince(userId),
      reportFailure: (op, e, st) =>
          unawaited(_reportSyncFailure(opType: op, error: e)),
    );

    // A one-shot _syncWorkoutTemplates recovery attempt bounded to once per
    // call, however many rows hit 23503. Pinned by
    // test/contracts/scheduled_workouts_fk_resilience_test.dart.
    bool templatesResynced = false;

    // Local-only (no network): the template row's name on THIS phone, or
    // null when the ref is empty or the template row is not here. Feeds the
    // fingerprint (a template arriving on this phone re-pushes) and Case 2
    // below.
    String? localTemplateName(String? rawHiveTemplateId) {
      if (rawHiveTemplateId == null || rawHiveTemplateId.isEmpty) return null;
      final localTmpl = workoutBox.get(rawHiveTemplateId);
      if (localTmpl is! Map) return null;
      final n = (localTmpl['name'] as String?)?.trim();
      return (n == null || n.isEmpty) ? null : n;
    }

    // OI-252 (merged from main) — `resolveCloudTemplateId` is a PURE key
    // conversion, no network call and no cache. It REPLACES the old
    // name-based SELECT (`(user_id, name)`) entirely: a schedule's
    // `template_id` is a Hive key (`tmpl_<uuid>`) whose cloud id is embedded
    // in the key itself, once the legacy-key migrator has run. A non-uuid
    // (legacy) key returns null and takes the recovery path below, whose
    // template resync runs that migrator.
    String? resolveCloudTemplateId(String? rawHiveTemplateId) {
      if (rawHiveTemplateId == null || rawHiveTemplateId.isEmpty) return null;
      return cloudIdFromKey(rawHiveTemplateId);
    }

    final liveDates = <String>{};
    for (final key in workoutBox.keys) {
      if (index.aborted) break;
      if (key is! String || !key.startsWith('schedule_')) continue;
      final raw = workoutBox.get(key);
      if (raw is! Map) continue;
      final entry = Map<String, dynamic>.from(raw);
      final date = entry['date'] as String?;
      if (date == null) continue;
      liveDates.add(date);

      try {
        // OI-170: `parsedDate` lived here solely to feed
        // `'day_of_week': parsedDate?.weekday` — the 1..7 value that corrupted
        // every cloud round-trip. With that gone it had no other reader, so it
        // is deleted rather than left as an unused local (which is a WARNING,
        // and `flutter analyze --no-fatal-infos` at pre-push fails on warnings).
        final rawTemplateId = entry['template_id']?.toString();
        final bool hasLocalRef =
            rawTemplateId != null && rawTemplateId.isNotEmpty;
        final String? tmplName = localTemplateName(rawTemplateId);

        // day-swapper+sync-load Task 14 — never "now" for a past completion;
        // resolver order: completed_at (ISO) -> completed_at_ms -> the
        // matching wlog's completed_at -> omit. (Also covers APK Test #12.7:
        // an empty string never reaches PostgREST.)
        final String? completedAt =
            ScheduleCompletionTime.scheduledCompletedAtIso(entry);

        // day-swapper+sync-load Task 15 — payload-shape heal: send an
        // EXPLICIT `template_id: null` when the local row has no template at
        // all; omit the key only for a genuine orphan (a local ref that
        // never resolves to a cloud id). PostgREST treats an explicit null
        // and an absent key differently on upsert (NULLs the column vs.
        // leaves it untouched), so every row's first push under this scheme
        // changes payload shape and re-pushes once (the expected heal).
        // OI-252's concern — an omitted key leaving a DELETED template's
        // reference in the cloud row forever — is covered by Case 1: a
        // template delete cleans the local refs
        // (`_cleanScheduleReferencesToTemplate`), so the row pushes an
        // explicit null.
        Map<String, dynamic> buildPayload(String? tmplId,
                {required bool includeTemplateKey}) =>
            <String, dynamic>{
              'user_id': userId,
              if (includeTemplateKey) 'template_id': tmplId,
              'scheduled_date': date,
              'week_number': entry['week'] ?? entry['week_number'],
              // OI-170 — send the app's canon (0=Mon..6=Sun), not Dart's
              // `weekday` (1..7). See the original diagnose for why a
              // re-derivation (rather than the stored value) is preferred.
              'day_of_week': entry['day_of_week'] ?? dayOfWeekFromDate(date),
              'status': entry['status'] ?? 'planned',
              if (completedAt != null) 'completed_at': completedAt,
            };

        await index.pushIfChanged(
          date,
          // The LOCAL template ref, not the cloud id (spec §5.9): a changed
          // local ref or a template arriving on this phone re-pushes.
          // day-swapper+sync-load Task 15 supersedes A-fix-1 (a `completed`
          // row never skipped) — migration 149's server-side completed-day
          // guard (Task 7) makes a fingerprint-matched completed row exactly
          // as safe to skip as a planned one; see
          // docs/diagnoses/2026-06-27-sched-dirty-filter-b4f7e2.md.
          () => SyncService.schedPayloadFingerprint(<String, dynamic>{
                ...buildPayload(null, includeTemplateKey: false),
                'template_ref': hasLocalRef ? rawTemplateId : null,
                'template_name': tmplName,
              }),
          () async {
            Future<bool> upsertOnce(String? tmplId, bool includeKey) async {
              try {
                await _supabase.client.from('scheduled_workouts').upsert(
                    buildPayload(tmplId, includeTemplateKey: includeKey),
                    onConflict: 'user_id,scheduled_date');
                return true;
              } on Object catch (e) {
                // APK Test #14 / Bug B.1 — distinguish 23503 (FK violation on
                // template_id) from other failures; anything else propagates
                // to pushIfChanged's own catch, which reports it via the
                // domain's opType (SyncSkipDomain.sched.opType ==
                // 'upsert_scheduled_workout').
                if (!e.toString().contains('23503')) rethrow;
                return false;
              }
            }

            // Case 1 — no local ref: explicit null, confirmed.
            if (!hasLocalRef) return upsertOnce(null, true);
            // Case 2 — the template row is not on this phone. OI-252 (merge
            // review F2): the cloud id is inside the key, so the row's own
            // template is sent whenever the key carries one — the cloud may
            // well hold the template (restore order, another device), and a
            // swap on this phone moved this date's template_id, which an
            // omitted key would leave pointing at the PRE-swap template.
            // Only when the cloud rejects it (23503: it lacks the template
            // too) or the key is legacy is the key omitted. Either way the
            // row is CONFIRMED: template_name (null) is in the fingerprint,
            // so the template's arrival re-pushes, and an unconfirmed row
            // would re-push (and fail its FK) every pass while it is missing.
            if (tmplName == null) {
              final keyId = resolveCloudTemplateId(rawTemplateId);
              if (keyId != null && await upsertOnce(keyId, true)) return true;
              return upsertOnce(null, false);
            }

            // Case 3 — the id comes from the key (OI-252), no SELECT.
            final cloudTemplateId = resolveCloudTemplateId(rawTemplateId);
            if (cloudTemplateId != null &&
                await upsertOnce(cloudTemplateId, true)) {
              return true;
            }

            // Unresolved (a legacy key), or 23503 because the cloud lacks the
            // template. First-time-this-CALL (not per-row): re-run
            // _syncWorkoutTemplates so the parent row exists, then retry. The
            // row's own template is FORCED past the skip index: it is only
            // here because the cloud lacks it, which the index (confirmed
            // once, earlier) cannot know.
            if (!templatesResynced) {
              templatesResynced = true;
              try {
                await _syncWorkoutTemplates(userId,
                    forceKeys: <String>{rawTemplateId});
              } catch (resyncErr, st) {
                debugPrint(
                    '[SyncService._syncScheduledWorkouts] templates resync: $resyncErr');
                // audit-2026-05-11 H-42 — telemetry pair.
                unawaited(ErrorTelemetry.recordNonFatal(resyncErr, st,
                    reason: 'sync_service_if_20'));
                return false;
              }
              // OI-252 — the resync above may have run the legacy-key
              // migrator as a side effect (`_syncWorkoutTemplates` gates on
              // it), which can rewrite THIS entry's `template_id` in place
              // (legacy key → `tmpl_<uuid>`). Re-read the entry rather than
              // resolving the now-stale `rawTemplateId` captured before the
              // resync — a pure key conversion can't discover a value it
              // never received.
              final refreshed = workoutBox.get(key);
              final refreshedTemplateId = refreshed is Map
                  ? refreshed['template_id']?.toString()
                  : rawTemplateId;
              final recovered = resolveCloudTemplateId(refreshedTemplateId);
              if (recovered != null && await upsertOnce(recovered, true)) {
                unawaited(_reportSyncFailure(
                  opType: 'scheduled_workout_fk_recovered',
                  error: 'tmpl=$rawTemplateId date=$date',
                ));
                return true;
              }
            }

            // Second FK violation (or the one-shot recovery slot was
            // already used by an earlier row this pass): fall back to
            // omitting template_id so status/completed_at still reach
            // cloud. This final attempt catches ANY failure (not just
            // 23503) — matching the pre-Task-15 catch-all fallback shape —
            // and reports 'upsert_scheduled_workout' (the pre-change op
            // string) itself: a rethrow-based report via pushIfChanged
            // would only fire for a non-23503 throw, and this path is
            // reached specifically because the retryable attempts are
            // exhausted, not because this attempt is expected to fail.
            try {
              await _supabase.client.from('scheduled_workouts').upsert(
                  buildPayload(null, includeTemplateKey: false),
                  onConflict: 'user_id,scheduled_date');
            } on Object catch (e, st) {
              debugPrint(
                  '[SyncService._syncScheduledWorkouts] fallback upsert: $e');
              // audit-2026-05-11 H-42 — telemetry pair.
              unawaited(ErrorTelemetry.recordNonFatal(e, st,
                  reason: 'sync_service_catch_11', skipServerPost: true));
              unawaited(_reportSyncFailure(
                  opType: 'upsert_scheduled_workout', error: e));
              return false;
            }
            // Fallback confirmed but the template link is lost. Spec D4: an
            // id-lookup failure means "written but not confirmed complete",
            // so report + stay UNCONFIRMED — a later successful resolve
            // re-pushes WITH the template instead of being stuck on the
            // omitted-template fingerprint forever.
            unawaited(_reportSyncFailure(
              opType: 'scheduled_workout_template_orphaned',
              error: 'tmpl=$rawTemplateId date=$date',
            ));
            return false;
          },
        );
      } catch (e, st) {
        debugPrint('[SyncService._syncScheduledWorkouts] $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_catch_12', skipServerPost: true));
        // Task 13/14 review fix round 1 (2026-09-27) — this outer catch only
        // guards the payload-build code above (pushIfChanged never
        // rethrows; a push() failure is already reported via the domain's
        // own opType through the `reportFailure` closure passed above), but
        // it MUST still keep its own `_reportSyncFailure` call so a
        // payload-build exception (before pushIfChanged is even reached)
        // still reaches the server-side client_errors table — the same
        // shape `_syncExerciseLogs` / `_syncNutritionLogs` /
        // `_syncScheduleCompletions` kept (an outer catch around
        // payload-building is a disjoint path from pushIfChanged's own
        // reporting).
        try {
          await _reportSyncFailure(
              opType: 'upsert_scheduled_workout', error: e);
        } catch (_) {}
      }
    }

    await index.commit(liveKeys: liveDates);
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
  /// [preFetched] (C3 single-call): injected `scheduled_workouts` rows, each
  /// carrying its nested `template{… template_exercises[]}` embed (the verbatim
  /// PostgREST shape the parser reads). Legacy callers omit it → network read.
  /// Plan §4 (H-1 embed nesting preserved).
  Future<void> _restoreScheduledWorkouts(String userId, String since,
      {Object? preFetched = _kNoInject}) async {
    try {
      // APK Test #15.3 / Bug 4a — direct query with embed instead of
      // _fetchAllRows so we can pull the parent template + its
      // exercises in a single round trip. Page size 1000 mirrors
      // _fetchAllRows; in practice no user has anywhere near 1000
      // scheduled workouts (one row per day).
      // Free-tier-hold durability #4 — paginate instead of a single
      // .range(0,999). A long-term holder can exceed 1000 daily rows (~2.7 yr);
      // the old ascending cap dropped the CURRENT phase from the status merge.
      // The pure `paginateAll` loops (keeping the template embed) so nothing is
      // truncated; extracted for unit-testability (paginate_all_test.dart).
      final List rows;
      if (identical(preFetched, _kNoInject)) {
        rows = await paginateAll<dynamic>(
          fetchPage: (offset, pageSize) async => await _supabase.client
              .from('scheduled_workouts')
              .select(
                '*, template:template_id('
                'id, name, workout_type, deleted_at, '
                'template_exercises(*)'
                ')',
              )
              .eq('user_id', userId)
              .gte('scheduled_date', since.substring(0, 10))
              .order('scheduled_date')
              .range(offset, offset + pageSize - 1),
        );
      } else {
        rows = (preFetched as List? ?? const []);
      }

      // OI-252 — lazily-resolved fallback set of deleted cloud template ids,
      // used ONLY when a row's embed is null (legacy/RLS edge case; the
      // stable-ID rename-on-delete trigger keeps the FK alive so the embed
      // is normally present and carries `deleted_at` directly). Cached
      // across the loop so at most one extra query runs per restore call.
      Set<String>? deletedTemplateIdsCache;
      Future<Set<String>> deletedTemplateIds() async =>
          deletedTemplateIdsCache ??= await _deletedTemplateCloudIds(userId);

      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final date = map['scheduled_date'] as String? ?? '';
        if (date.isEmpty) continue;
        final key = 'schedule_$date';
        // OI-252 — the cloud id this row's template_id points at, and its
        // stable Hive-key form. `_syncScheduledWorkouts`'s push writes the
        // raw cloud uuid (payload() always sends `template_id: tmplId`
        // where tmplId is the cloud id), so that's what we read back here;
        // the LOCAL representation must always be the `tmpl_<uuid>` key.
        final rawCloudTemplateId = map['template_id'] as String?;
        final hiveTemplateKey = rawCloudTemplateId != null
            ? templateKeyFor(rawCloudTemplateId)
            : null;
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
        // Day-swapper + sync-load Task 14 (plan D3) — existingMap['completed_at']
        // is NEVER set by markCompleted on a schedule row (only completed_at_ms
        // is), so this branch's "local completed + cloud planned -> keep local"
        // rule (immediately below) could never actually fire before this fix: a
        // stale cloud `planned` row would silently demote a locally completed
        // day on every scheduled-workouts restore. ScheduleCompletionTime
        // resolves the real value (legacy ISO field, else derived from
        // completed_at_ms); still null only when existingMap truly has no
        // completion time recorded at all.
        final localCompletedAt =
            ScheduleCompletionTime.scheduledCompletedAtIso(existingMap);

        String? mergedStatus = cloudStatus;
        String? mergedCompletedAt = cloudCompletedAt;

        // Merge review F4: `rest` joins `planned` here. A cross-device day
        // swap can put a rest row on a date this phone completed but has not
        // pushed yet; taking the cloud's rest would demote a completed day
        // (spec I6), and the rest-content strip below would then erase its
        // exercises.
        if (localStatus == 'completed' &&
            (cloudStatus == 'planned' || cloudStatus == 'rest') &&
            localCompletedAt != null &&
            localCompletedAt.isNotEmpty) {
          // Cloud is stale (push failed). Keep local; Bug B.3 migrator
          // re-pushes on next launch.
          mergedStatus = 'completed';
          mergedCompletedAt = localCompletedAt;
        } else if (WorkoutScheduleReadService.isTerminalScheduleRow(
                localStatus) &&
            cloudStatus == 'planned') {
          // Review round 1 (e8f4a3) — symmetric arm: a local TERMINAL row
          // (moved/dropped) is newer truth. The workout now lives on
          // `moved_to` (or was dropped outright); the cloud still holding
          // the pre-move 'planned' row must NOT resurrect it — that is the
          // exact double-count the terminal rows were written to kill. The
          // terminal metadata (moved_to/moved_at/...) survives via the
          // `...existingMap` spread below; mergedCompletedAt stays null so
          // a terminal row never reads as completed.
          mergedStatus = localStatus;
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
        // OI-252 — true when this row's assigned template is a tombstone
        // (rename-on-delete trigger: `deleted_at` set, `is_active` false,
        // name mangled). Such a row must never hydrate template content,
        // and the schedule reference itself must be cleaned regardless of
        // whether `_restoreWorkoutTemplates` has already run this pass.
        bool templateDeleted = false;

        if (map['template_id'] != null) {
          final templateEmbed = map['template'];
          if (templateEmbed is Map) {
            final tmpl = Map<String, dynamic>.from(templateEmbed);
            if (tmpl['deleted_at'] != null) {
              templateDeleted = true;
            } else {
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
            }
          } else if (rawCloudTemplateId != null &&
              (await deletedTemplateIds()).contains(rawCloudTemplateId)) {
            // OI-252 fallback — embed null but the id shows up in a live
            // deleted-templates cross-check. Post-migration this should be
            // rare (the rename-on-delete trigger keeps the FK alive, so the
            // embed above is normally present), but a legacy/RLS edge case
            // could still surface a null embed for a tombstoned template.
            templateDeleted = true;
          } else {
            // template_id set, embed null, AND not in the deleted set —
            // genuinely unresolvable (RLS-hidden or an orphaned FK). Don't
            // overwrite local workout_name/exercises with empties.
            unawaited(ErrorTelemetry.logEvent(
              'restore_scheduled_workouts_template_missing',
              message: 'date=$date template_id=${map['template_id']}',
            ));
          }
        }

        if (templateDeleted) {
          // OI-252 — never write/keep a schedule day pointing at a deleted
          // template. Clean any local schedule reference to it (this date's
          // row AND any other row that happens to share the id/key — the
          // helper is a full sweep, same one `_restoreWorkoutTemplates`
          // calls, safe to run redundantly) and skip writing this row
          // entirely. Independent of Future-ordering: this runs whether or
          // not `_restoreWorkoutTemplates` has processed the delete yet.
          if (rawCloudTemplateId != null && hiveTemplateKey != null) {
            await _cleanScheduleReferencesToTemplate(
              hiveKey: hiveTemplateKey,
              cloudId: rawCloudTemplateId,
            );
          }
          continue;
        }

        // OI-170 — see the `day_of_week` key below. Computed once, here, so the
        // conditional-key form does not evaluate it twice.
        //
        // KILL-SWITCH (§4.6 / blast_radius `platform` requires: feature_flag).
        // Opt-OUT polarity: the fix is live by default; setting
        // `configBox['disable_day_of_week_derive'] = true` restores the LEGACY
        // path verbatim — trust whatever the cloud sent. Kept because this is a
        // platform-tier change to the restore path, and a bad derivation would
        // mis-badge every row on every device at once.
        final derivedDayOfWeek = SyncFlags.deriveDayOfWeekOnRestore
            ? (dayOfWeekFromDate(date) ?? map['day_of_week'] as int?)
            : map['day_of_week'] as int?;

        final merged = <String, dynamic>{
          ...existingMap,
          'date': date,
          // When the template resolved, force the type to
          // 'custom_template' (overrides any stale local type written
          // by plan-gen). Otherwise preserve existing behavior.
          // Spec 2026-09-26-day-swapper-design.md sec 1.4/sec 5.7 fix
          // (diagnose b6e1c8): when no template resolves and the CLOUD says
          // this day is rest, force type:'rest' regardless of any stale
          // local/template-derived type — a rest day restored onto a fresh
          // install (no local row; plan_json silent on this date) must
          // never render as a no-exercise workout. Otherwise unchanged.
          'type': templateResolved
              ? 'custom_template'
              : (cloudStatus == 'rest'
                  ? 'rest'
                  : (existingMap['type'] ??
                      (map['template_id'] != null
                          ? 'custom_template'
                          : 'workout'))),
          // OI-252 — the LOCAL representation of a scheduled workout's
          // template link is always the stable `tmpl_<uuid>` Hive-key
          // shape, never the raw cloud uuid `map['template_id']` carries.
          if (hiveTemplateKey != null) 'template_id': hiveTemplateKey,
          if (mergedStatus != null && mergedStatus.isNotEmpty)
            'status': mergedStatus,
          if (mergedCompletedAt != null && mergedCompletedAt.isNotEmpty)
            'completed_at': mergedCompletedAt,
          if (map['week_number'] != null) 'week': map['week_number'],
          if (map['week_number'] != null) 'week_number': map['week_number'],
          // OI-170 — DERIVE `day_of_week` from this row's own `scheduled_date`
          // rather than trusting the transmitted value.
          //
          // It is a pure function of the date, so it never needed to round-trip
          // at all. Trusting the wire value was actively harmful: the push at
          // `:1620` sent `parsedDate.weekday` (1..7) while the app's canon is
          // 0..6 (`tool_dispatcher.dart:695` says so explicitly;
          // `train_provider.dart:619`/`:816` compute
          // `(week-1)*7 + day_of_week + 1` and render the `D<n>` badge), and
          // this key sits AFTER the `...existingMap` spread — so the wrong
          // cloud value OVERWROTE a correct local one on every restore. Monday
          // of week 1 came back as `D2`, Sunday as `D8`.
          //
          // Deriving here also SELF-HEALS every already-corrupted cloud row
          // with no migration, which is why the fix lives on this side.
          // ⚠ Falls back to the transmitted value only when the date will not
          // parse — a row we cannot date is one we cannot derive.
          if (derivedDayOfWeek != null) 'day_of_week': derivedDayOfWeek,
          // APK Test #15.3 / Bug 4a — overlay template-derived display
          // content LAST so it wins over the existingMap spread above.
          if (hydratedWorkoutName != null) 'workout_name': hydratedWorkoutName,
          if (hydratedWorkoutFocus != null)
            'workout_focus': hydratedWorkoutFocus,
          if (hydratedExercises != null) 'exercises': hydratedExercises,
          'source': 'cloud_restore',
        };
        // Merge review F4: a day typed rest above (the cloud says rest and no
        // template resolved) must not keep the workout it replaced. The
        // `...existingMap` spread carries the old template_id, name and
        // exercises; the next push would send that template_id with a rest
        // status, and another device's restore would resolve it and rebuild
        // a `custom_template` row with status rest (the b6e1c8 hybrid). Same
        // unswitched restore type derivation as the rest type itself (spec
        // sec 11).
        if (merged['type'] == 'rest' && mergedStatus == 'rest') {
          merged.remove('template_id');
          final hadWorkout = !PlanEngineFlags.isRestDayConsideringLogged(
                  existingMap['type']) ||
              (existingMap['exercises'] is List &&
                  (existingMap['exercises'] as List).isNotEmpty);
          if (hadWorkout) {
            merged['workout_name'] = 'Rest Day';
            merged['workout_focus'] = 'Recovery & mobility';
            merged['exercises'] = <Map<String, dynamic>>[];
          }
        }
        await _hive.workoutBox.put(key, merged);
      }
    } catch (e, st) {
      debugPrint('[SyncService._restoreScheduledWorkouts] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_if_21', skipServerPost: true));
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
    // OI-189: guard FIRST, like syncWorkoutData (:31) / pushSnapshot
    // (sync_service.dart). The dev year-sim drives ~30 phase advances inside
    // its pausedForSimulation window and each now pushes plan_json via
    // generateAndSchedule(pushPlanWindow: true) — the exact per-write network
    // storm that flag exists to prevent. Also covers holdWeek / deload pushes
    // during a sim. Cloud catches up at the next weeklyFullSync, as before.
    if (SyncService.pausedForSimulation) return;
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

  /// Review round 1 (e8f4a3) — test seam: runs `_restoreScheduledWorkouts`
  /// with INJECTED cloud rows (no Supabase query), so the timestamp-merge
  /// arms are behaviorally testable (seed a local terminal row + a
  /// cloud-shaped planned row, run the REAL merge path, assert the outcome).
  @visibleForTesting
  Future<void> restoreScheduledWorkoutsForTest(
    String userId, {
    Object? preFetched,
    String? since,
  }) =>
      _restoreScheduledWorkouts(
          userId, since ?? _kSyncDomainRestoreSince,
          preFetched: preFetched);

  /// Test seam: runs `_restoreWorkoutPlan` with INJECTED
  /// `user_progress` rows AND (optionally) a pre-resolved deleted-template-id
  /// set, so the L1/L2/L3 restore-merge (spec sec 5.7, day-swapper) and the
  /// OI-252 ghost-day filter are behaviorally testable without a live
  /// Supabase call for either query the real path would otherwise make.
  @visibleForTesting
  Future<void> restoreWorkoutPlanForTest(
    String userId, {
    Object? preFetched,
    Set<String>? preFetchedDeletedTemplateIds,
  }) =>
      _restoreWorkoutPlan(
        userId,
        preFetched: preFetched,
        preFetchedDeletedTemplateIds: preFetchedDeletedTemplateIds,
      );

  /// OI-252 B-pass finding 2 — test seam: runs `_restoreWorkoutTemplates`
  /// with INJECTED cloud rows (no Supabase query for the row read itself),
  /// so the legacy-key-migrator gate this fix added is behaviorally
  /// testable. [preFetched] must be passed (even as an empty list) or this
  /// falls through to a live network call, which unit tests cannot make.
  @visibleForTesting
  Future<void> restoreWorkoutTemplatesForTest(
    String userId, {
    required Object? preFetched,
  }) =>
      _restoreWorkoutTemplates(userId, preFetched: preFetched);
}
