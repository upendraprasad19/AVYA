part of '../sync_service.dart';

/// Sync + restore for user-identity surfaces: user_profile,
/// user_preferences, user_progress. Plus `users` (full_name + email)
/// merged into the profile map on restore per APK Test #12.8 / Bug #2.
///
/// Static helpers `_hasValue` + `_hasNumber` stay on the SyncService
/// class — extension methods reference them via `SyncService.<name>()`.
extension SyncServiceProfile on SyncService {
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

  /// Unit 3b round-1-review P1 fix (2026-07-30) — routes
  /// `UserRepository.syncOnboardingToSupabase`'s user_progress write through
  /// the SAME optimistic-lock RPC as the regular periodic sync, instead of a
  /// raw version-blind upsert. A raw upsert there was a THIRD unprotected
  /// writer to the fields `update_user_progress_snapshot` exists to guard:
  /// the 10s-delayed inline retry (`onboarding_provider.dart`) or a
  /// multi-launch `pending_onboarding_sync` replay (`_replayPendingOnboarding
  /// Sync` — re-reads Hive fresh each call, but a fresh LOCAL read still
  /// races a raw upsert against a DIFFERENT device's already-versioned
  /// write) could silently clobber real post-onboarding progress with stale
  /// values. Strictly safer than the prior behavior in every case: a version
  /// match now REQUIRED to write at all (old code always overwrote
  /// unconditionally), so the only new outcome is "lost the race, dropped
  /// after one retry" — which preserves whatever fresher state already
  /// landed rather than silently replacing it with day-1 onboarding values.
  ///
  /// THROWS on a genuine RPC/network exception (unlike `syncProgressNow`,
  /// which swallows) — preserves `syncOnboardingToSupabase`'s existing
  /// "throws so the caller can detect sync gaps" contract that drives the
  /// 10s retry + pending-flag replay safety net. Does NOT throw on a benign
  /// version-mismatch drop (see above — that is correct concurrent-write
  /// handling, not a failure).
  ///
  /// `progressData` uses the SAME semantic keys the 2 existing callers
  /// already build (`current_phase`, `current_week`, `total_workouts_done`,
  /// …). A key the caller omits maps to an explicit RPC NULL — COALESCE
  /// preserves the existing column on an UPDATE (e.g. the onboarding-replay
  /// path deliberately omits `current_week` to avoid stomping the
  /// program-week projection); migration 115's P2 fix COALESCEs the 4
  /// schema-defaulted columns to their real defaults on a fresh INSERT too,
  /// so an all-null fresh insert still lands the correct 1/1/0/0.
  Future<void> pushOnboardingProgressSnapshot({
    required String userId,
    required Map<String, dynamic> progressData,
  }) async {
    // Hermes C9 (2026-07-30): defensive `(x as num?)?.toInt()` casts, not
    // hard `as int?` — matches `_buildUserProgressRpcParams`'s identical
    // fields (the shared helper `_syncUserProgress` uses). A hard cast
    // throws on any non-int numeric shape (e.g. a value that round-tripped
    // through JSON as a double); `_sanitize` upstream does NOT guard these
    // fields (its `_integerOnlyColumns` allowlist contains zero progress
    // columns), so this cast was the only guard in the path. Kept as a
    // separate literal (not routed through the shared helper) because this
    // path deliberately skips the week PROJECTION logic — see that
    // helper's doc comment — onboarding-time `progressData` isn't
    // Hive-shaped and doesn't need it.
    final rpcParams = <String, dynamic>{
      'p_current_phase': (progressData['current_phase'] as num?)?.toInt(),
      'p_current_week': (progressData['current_week'] as num?)?.toInt(),
      'p_phase_started_at': progressData['phase_started_at'],
      'p_plan_generated_at': progressData['plan_generated_at'],
      'p_total_workouts_done':
          (progressData['total_workouts_done'] as num?)?.toInt(),
      'p_current_streak_weeks':
          (progressData['current_streak_weeks'] as num?)?.toInt(),
      'p_detected_experience_level':
          progressData['detected_experience_level'] as String?,
      'p_deployments_complete':
          (progressData['deployments_complete'] as num?)?.toInt(),
      'p_current_streak_days':
          (progressData['current_streak_days'] as num?)?.toInt(),
      'p_last_workout_date': progressData['last_workout_date'],
      'p_longest_gap_days': (progressData['longest_gap_days'] as num?)?.toInt(),
    };

    final rawProgress = _hive.userBox.get('progress');
    final expectedVersion = rawProgress == null
        ? 0
        : ((Map<String, dynamic>.from(rawProgress as Map)
                    ['streak_progress_version'] as num?)
                ?.toInt() ??
            0);

    final firstAttempt = await _supabase.client.rpc(
      'update_user_progress_snapshot',
      params: {
        'p_user_id': userId,
        'p_expected_version': expectedVersion,
        ...rpcParams,
      },
    );
    final firstVersion = (firstAttempt as num?)?.toInt();
    if (firstVersion != null) {
      SyncService._stampProgressVersion(firstVersion, userId: userId);
      return;
    }
    // Version mismatch — reuse the SAME bounded single-retry helper
    // _syncUserProgress uses (re-fetches the fresh version, resends the
    // SAME field values once, then drops with telemetry rather than loops).
    await _retrySyncUserProgressOnceAfterConflict(
      userId: userId,
      rpcParams: rpcParams,
    );
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
      // onboarding_completed_at — durable writer (Unit D, diagnose c4d8a2). This
      // canonical recurring profile->cloud sync was the ONLY profile path that
      // OMITTED the column, so a missed onboarding-path write left it permanently
      // NULL (→ forced re-onboard on a new device), and the restoring-screen
      // self-heal — which pushes via syncProfileNow → here — silently dropped it
      // (a no-op). Now kept in step. Guarded: never clobber an existing value
      // with null.
      if (SyncService._hasValue(p['onboarding_completed_at']))
        'onboarding_completed_at': p['onboarding_completed_at'],
      if (SyncService._hasValue(p['date_of_birth'])) 'date_of_birth': p['date_of_birth'],
      if (SyncService._hasValue(p['gender'])) 'gender': p['gender'],
      if (SyncService._hasNumber(p['height_cm'])) 'height_cm': p['height_cm'],
      if (SyncService._hasNumber(p['current_weight_kg'])) 'current_weight_kg': p['current_weight_kg'],
      if (SyncService._hasNumber(p['target_weight_kg'])) 'target_weight_kg': p['target_weight_kg'],
      if (SyncService._hasValue(p['primary_goal'])) 'primary_goal': p['primary_goal'],
      if (SyncService._hasValue(p['fitness_experience'])) 'fitness_experience': p['fitness_experience'],
      if (SyncService._hasNumber(p['days_per_week'])) 'days_per_week': (p['days_per_week'] as num).round(),
      if (SyncService._hasValue(p['equipment_access'])) 'equipment_access': p['equipment_access'],
      // ⑥ C1 — the equipment-exclusion preference (List<String>, mirrors injuries'
      // shape). Column `user_profile.equipment_exclusions text[]` (migration
      // add_equipment_exclusions_to_user_profile, applied before this line landed).
      if (SyncService._hasValue(p['equipment_exclusions']))
        'equipment_exclusions': p['equipment_exclusions'] is List ? p['equipment_exclusions'] : <String>[],
      // ⑦ OI-89 — the ADD half of the same preference. Column
      // `user_profile.equipment_owned text[]` (migration 124, applied
      // 2026-08-28 BEFORE this line shipped: user_repository.dart:721 upserts a
      // SPREAD and _sanitize does not whitelist columns, so a client carrying a
      // key the DB lacks gets a PostgREST 400 that rejects the ENTIRE row).
      //
      // Conditional-entry, not an unconditional key: a profile that never
      // answered the question must not overwrite a cloud value with [] on every
      // sync. RESTORE needs no counterpart — _restoreUserProfile uses a bare
      // .select() and merges every non-null cloud key, so it is column-agnostic.
      if (SyncService._hasValue(p['equipment_owned']))
        'equipment_owned': p['equipment_owned'] is List ? p['equipment_owned'] : <String>[],
      if (SyncService._hasValue(p['activity_level'])) 'activity_level': p['activity_level'],
      if (SyncService._hasValue(p['lifestyle_activity'])) 'lifestyle_activity': p['lifestyle_activity'],
      if (SyncService._hasValue(p['pace_preference'])) 'pace_preference': p['pace_preference'],
      if (SyncService._hasValue(p['diet_preference'])) 'diet_preference': p['diet_preference'],
      if (SyncService._hasValue(p['injuries'])) 'injuries': p['injuries'] is List ? p['injuries'] : <String>[],
      if (SyncService._hasValue(p['city'])) 'city': p['city'],
      if (SyncService._hasNumber(p['bmr'])) 'bmr': (p['bmr'] as num).round(),
      if (SyncService._hasNumber(p['tdee'])) 'tdee': (p['tdee'] as num).round(),
      if (SyncService._hasNumber(p['body_fat_percent'])) 'body_fat_percent': p['body_fat_percent'],
      if (SyncService._hasValue(p['body_fat_assessed_at'])) 'body_fat_assessed_at': p['body_fat_assessed_at'],
      if (SyncService._hasNumber(p['session_duration_minutes']))
        'session_duration_minutes': (p['session_duration_minutes'] as num).round(),
      if (SyncService._hasValue(p['physique_focus'])) 'physique_focus': p['physique_focus'],
      if (SyncService._hasValue(p['avatar_url'])) 'avatar_url': p['avatar_url'],
      if (SyncService._hasValue(p['banner_url'])) 'banner_url': p['banner_url'],
      if (SyncService._hasValue(p['wake_up_time'])) 'wake_up_time': p['wake_up_time'],
      if (SyncService._hasValue(p['preferred_workout_time']))
        'preferred_workout_time': p['preferred_workout_time'],
      // F17 · Computed nutrition targets (integer columns added migration 021).
      // Coerce to int — NutritionTargets uses ints today but defensively round
      // in case a caller ever stores a double here.
      if (SyncService._hasNumber(p['daily_calories']))
        'daily_calories': (p['daily_calories'] as num).round(),
      if (SyncService._hasNumber(p['protein_grams']))
        'protein_grams': (p['protein_grams'] as num).round(),
      if (SyncService._hasNumber(p['carbs_grams']))
        'carbs_grams': (p['carbs_grams'] as num).round(),
      if (SyncService._hasNumber(p['fat_grams']))
        'fat_grams': (p['fat_grams'] as num).round(),
      if (SyncService._hasNumber(p['water_target_ml']))
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

  /// Builds the `update_user_progress_snapshot` RPC's field params (every
  /// key but `p_user_id`/`p_expected_version`, which the caller adds) from a
  /// raw Hive `progress` map. Shared by [_syncUserProgress]'s initial build
  /// and [_retrySyncUserProgressOnceAfterConflict]'s fresh-Hive rebuild on
  /// retry (B-pass round-2, 2026-07-30) — one definition means the two can't
  /// silently drift apart the way a duplicated copy could.
  ///
  /// Defensive `(x as num?)?.toInt()` casts, not hard `as int?` — a hard
  /// cast throws on any non-int numeric shape (e.g. a value that round-
  /// tripped through JSON as a double somewhere upstream), and this is the
  /// only guard in the path (`_sanitize`'s `_integerOnlyColumns` allowlist
  /// contains zero progress columns).
  Map<String, dynamic> _buildUserProgressRpcParams(Map<String, dynamic> p) {
    // current_week PROJECTION (diagnose 2026-07-21). The Hive field is a dead
    // constant `1` (every writer sets the literal); left as-is the column
    // makes the weekly-recap push say "Week 1" forever, the weekly report say
    // "Current week: 1", and the coach read a frozen 1. Project the derived
    // PROGRAM week (1..12, "true deployment progress") into the column so the
    // two Edge Functions that read it become correct with no EF redeploy.
    // Kill-switch `disable_program_week_projection` (default-ON) restores the
    // verbatim pre-fix behaviour: the guarded passthrough of the frozen field.
    // Written UNCONDITIONALLY when ON — getProgramWeek never returns null, so
    // a restore/null-Hive user's column can't be left stale (review F1).
    final projectionOff =
        _hive.configBox.get('disable_program_week_projection') == true;
    final int? currentWeekOut =
        WorkoutScheduleReadService.instance.currentWeekColumnProjection(
      frozenWeek: (p['current_week'] as num?)?.toInt(),
      phase: (p['current_phase'] as num?)?.toInt() ?? 1,
      disabled: projectionOff,
    );

    // Every key is ALWAYS present (explicit null, not omitted) — unlike the
    // old upsert's `if (x != null) 'x': x` conditional-inclusion. The RPC's
    // SQL body does `COALESCE(p_x, existing_column)` per field, so a NULL
    // param has the SAME "don't touch this column" effect the old
    // conditional-omit had on a partial upsert; explicit-null is required
    // here because PostgREST maps every declared function parameter by
    // name and there is no DEFAULT NULL in migration 115's signature.
    return <String, dynamic>{
      'p_current_phase': (p['current_phase'] as num?)?.toInt(),
      'p_current_week': currentWeekOut,
      'p_phase_started_at': p['phase_started_at'],
      'p_plan_generated_at': p['plan_generated_at'],
      'p_total_workouts_done': (p['total_workouts_done'] as num?)?.toInt(),
      'p_current_streak_weeks': (p['current_streak_weeks'] as num?)?.toInt(),
      // F21 · detected_experience_level — seeded from onboarding answer,
      // may be overwritten by AI detection.
      'p_detected_experience_level': p['detected_experience_level'] as String?,
      // Rank-evaluation columns (migration 081, diagnose b9f4d2). The server
      // cron `evaluate-rank-promotions` SELECTs these to evaluate the ladder;
      // pre-081 they didn't exist → the cron read null → only ever granted SD2.
      // Source of truth is the CLIENT (schedule-aware streak walk + the F18
      // deployment counter). current_streak_days + last_workout_date are
      // already stamped into `progress` by train_provider on workout
      // completion; deployments_complete by UserRepository.updateProgress.
      'p_deployments_complete': (p['deployments_complete'] as num?)?.toInt(),
      'p_current_streak_days': (p['current_streak_days'] as num?)?.toInt(),
      'p_last_workout_date': p['last_workout_date'],
      'p_longest_gap_days': (p['longest_gap_days'] as num?)?.toInt(),
    };
  }

  /// Pushes local user progress (phase, week, streaks, etc.) to Supabase.
  ///
  /// Unit 3b (OI-45 cross-device half, e6b9c4): routes through the
  /// `update_user_progress_snapshot` optimistic-lock RPC (migration 115)
  /// instead of a raw version-blind upsert — the same cross-device race
  /// class migration 056 closed for the streak-freeze fields (device A and
  /// B both read a stale snapshot, whichever writes last silently wins,
  /// clobbering the other) applied here too, just with no RPC to close it
  /// until now.
  Future<void> _syncUserProgress(String userId) async {
    try {
      final progress = _hive.userBox.get('progress');
      if (progress == null) return;

      final p = Map<String, dynamic>.from(progress as Map);
      final rpcParams = _buildUserProgressRpcParams(p);

      final expectedVersion =
          (p['streak_progress_version'] as num?)?.toInt() ?? 0;
      final firstAttempt = await _supabase.client.rpc(
        'update_user_progress_snapshot',
        params: {
          'p_user_id': userId,
          'p_expected_version': expectedVersion,
          ...rpcParams,
        },
      );
      final firstVersion = (firstAttempt as num?)?.toInt();
      if (firstVersion != null) {
        SyncService._stampProgressVersion(firstVersion, userId: userId);
      } else {
        // Version mismatch — a concurrent device's write landed first.
        // Bounded: re-fetch the fresh version, resend the SAME local field
        // values once, then drop. Not a field-level merge (unlike freezes'
        // mergeFreezeProgress) — these fields are client-authoritative per
        // the comment above (cloud is a passive mirror for cron/report
        // consumption), so re-asserting local values against the fresh
        // version is the correct reconciliation, not a 3-way merge.
        await _retrySyncUserProgressOnceAfterConflict(
          userId: userId,
          rpcParams: rpcParams,
        );
      }
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

  /// Unit 3b (e6b9c4) — bounded retry for `_syncUserProgress` after a
  /// version mismatch. Re-fetches ONLY the fresh version (not the field
  /// values — local is authoritative for these fields), retries ONCE, then
  /// drops (logs telemetry, does not loop).
  Future<void> _retrySyncUserProgressOnceAfterConflict({
    required String userId,
    required Map<String, dynamic> rpcParams,
  }) async {
    final Object? rawRes = await _supabase.client
        .from('user_progress')
        .select('streak_progress_version')
        .eq('user_id', userId)
        .maybeSingle();
    if (rawRes == null) {
      // Hermes C7 (2026-07-30): was a silent return. Both RPCs return NULL
      // for row-absent (migration 115), so this state does NOT prove the
      // row genuinely doesn't exist — it's reachable via a partial restore
      // that leaves a non-zero local version with no cloud row behind it,
      // and every subsequent sync silently no-ops the same way forever
      // (self-perpetuating, Hermes L34 Finding 2). The sibling drop 11
      // lines below already telemeters; this one didn't.
      unawaited(ErrorTelemetry.logEvent(
        'sync_user_progress_row_absent_after_conflict',
        message: 'user=$userId — cloud row absent on retry re-fetch, '
            'dropped whole snapshot',
      ));
      return;
    }
    final freshVersion =
        ((rawRes as Map)['streak_progress_version'] as num?)?.toInt();
    if (freshVersion == null) return;

    // B-pass round-2 (2026-07-30): rebuild from a FRESH Hive read rather
    // than resending the params the caller captured before its own first
    // RPC attempt — mirrors the freezes-retry fix (Hermes C2), which this
    // sibling helper had NOT received despite being the exact same bug
    // class. That capture happened before this helper's own cloud re-fetch
    // above, so a routine same-device write landing in that window
    // (train_provider.dart on workout completion, UserRepository.
    // updateProgress, etc. — see this class's own rpcParams-build comment)
    // would otherwise be silently overwritten by a stale resend for every
    // COALESCE-only field (all but total_workouts_done/deployments_complete,
    // which GREATEST protects regardless of which snapshot is resent).
    //
    // B-pass round-3 (2026-07-30) caught the first version of this fix: it
    // was all-or-nothing (Hive map present -> use ONLY its fields, ignoring
    // rpcParams entirely). That's correct for _syncUserProgress's own retry
    // (same Hive source as the original attempt, so Hive always has every
    // field). It's WRONG for pushOnboardingProgressSnapshot's retry: its
    // first attempt's progressData carries fields Hive's progress map
    // never gets (detected_experience_level in particular — seeded from
    // the onboarding answer via `profile['fitness_experience']`, but
    // `saveProgress`'s onboarding write, onboarding_provider.dart:471-478,
    // never puts it in the Hive progress map at all). An all-or-nothing
    // swap silently resent NULL for that field on retry, permanently
    // dropping a real answer whenever the fresh-insert race is lost to a
    // sibling writer whose own INSERT branch also never sets it (e.g.
    // syncFreezes' fresh-insert, migration 115's own comment names this
    // exact interleaving as reachable). Fixed as a per-field merge instead:
    // prefer the fresh-Hive value when Hive actually carries that field
    // (non-null), otherwise fall back to what the ORIGINAL attempt sent —
    // never regressing a real value to NULL just because Hive doesn't
    // track that particular field for this caller. Consistent with the
    // RPC's own COALESCE semantics, where every one of these params was
    // already designed to mean "no fresher info, don't touch this column"
    // when null — never "actively clear this column".
    final freshLocal = _hive.userBox.get('progress');
    final freshParams = freshLocal is Map
        ? SyncService.mergeRpcParamsPreferringNonNull(
            _buildUserProgressRpcParams(Map<String, dynamic>.from(freshLocal)),
            rpcParams,
          )
        : rpcParams;

    final retryResult = await _supabase.client.rpc(
      'update_user_progress_snapshot',
      params: {
        'p_user_id': userId,
        'p_expected_version': freshVersion,
        ...freshParams,
      },
    );
    final retryVersion = (retryResult as num?)?.toInt();
    if (retryVersion == null) {
      // Second consecutive mismatch — drop rather than loop. The next
      // updateProgress() call's own sync (or the next restore) reconciles
      // from a fresher snapshot.
      unawaited(ErrorTelemetry.logEvent(
        'sync_user_progress_retry_dropped',
        message: 'user=$userId expected=$freshVersion — dropped after '
            'one retry',
      ));
      return;
    }
    SyncService._stampProgressVersion(retryVersion, userId: userId);
  }

  /// Pushes user preferences to Supabase user_preferences table.
  Future<void> _syncUserPreferences(String userId) async {
    try {
      // TWO INDEPENDENT SOURCES — and the independence IS the fix (OI-98 /
      // e4a1b7). This method used to open with
      //   final prefs = _hive.userBox.get('preferences');
      //   if (prefs == null) return;
      // and that guard made the whole method unreachable for most installs.
      // `userBox['preferences']` has exactly ONE writer in the tree —
      // `_restoreUserPreferences` below — and `UserRepository.savePreferences`
      // has ZERO call sites, so the key is null unless a cloud row already
      // existed to restore FROM. Measured 2026-08-26: 6 `user_preferences` rows
      // against 18 users with snapshots, and all 6 carry
      // `preferred_language='English'` (the column DEFAULT) with none at the
      // `'en'` this method writes — i.e. every row was created by an Edge
      // Function and the client has never created one. Hanging the new
      // notification column off that guard would have shipped it inert for
      // two-thirds of users while every test passed.
      final prefs = _hive.userBox.get('preferences');
      final p = prefs is Map
          ? Map<String, dynamic>.from(prefs)
          : const <String, dynamic>{};
      final notificationPrefs = NotificationPrefsRepository.read();

      final payload = buildUserPreferencesPayload(
        userId: userId,
        preferences: p,
      );

      // ⚠ notification_preferences is DELIBERATELY NOT in this payload — it
      // goes through the merge RPC below instead (B-pass Finding 1).
      //
      // A partial upsert protects sibling COLUMNS, but the value of a jsonb
      // column is still replaced WHOLESALE: PostgREST emits
      // `SET col = EXCLUDED.col`, which is assignment, not a merge. The stored
      // map is legitimately sparse — `notification_settings_screen.dart:50-56`
      // seeds from `read()` (`{}` on a fresh device) and each toggle adds ONE
      // key — so writing it through this upsert would let a device delete every
      // preference it had not personally seen:
      //   device A stores {streak_alerts:false}  -> column = {streak_alerts:false}
      //   device B stores {weekly_recap:false}   -> column = {weekly_recap:false}
      // and A's key is gone, reverting to ABSENT => SEND. That is OI-98 itself,
      // reached through the NEW home — the same defect the restore side's
      // per-key merge already guards against, missing from its mirror.

      // `coaching_notes` REMOVED from this payload (OI-98 round-3 review).
      // The client is a pure CONSUMER of that column; its writers are
      // `daily-snapshot` (extracted AI facts) and `assess-body-composition`
      // (the `last_bf_assessed_at` 30-day PRO rate-limit stamp). It was named
      // unconditionally here as `p['coaching_notes']`, and a key present with a
      // null value still lands in the generated SET list — so a client with no
      // local copy nulled the server's, destroying coach memory and reopening
      // the BF% rate limit. Harmless-looking until this batch, which adds a
      // push on every notification toggle and would have made it routine.
      if (payload.length > 1) {
        await _supabase.client
            .from('user_preferences')
            .upsert(payload, onConflict: 'user_id');
      }

      // OI-98 — PER-KEY ADDITIVE write, via migration 123's jsonb merge.
      // `||` lets the keys this device actually knows win while leaving every
      // other key stored by another device alone. The RPC is SECURITY INVOKER
      // and keys the row on `auth.uid()`, so the caller's own RLS applies and a
      // user cannot write someone else's preferences.
      //
      // Issued SEPARATELY from the upsert above, not folded into it, because
      // the two have different merge semantics and folding them would silently
      // give this one the upsert's wholesale replace. It also creates the row
      // when none exists, which is what makes the write reach the ~12 of 18
      // users who have no `user_preferences` row at all.
      if (notificationPrefs.isNotEmpty) {
        await _supabase.client.rpc(
          'merge_notification_preferences',
          params: <String, dynamic>{'p_prefs': notificationPrefs},
        );
      }
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

  /// [preFetched] / [preFetchedUsers] (C3 single-call): when injected, the
  /// `user_profile` (limit-1 array) and `users` (object|null) reads are skipped
  /// and the bundle values are merged instead. Legacy callers omit both →
  /// byte-identical network behavior. Plan `restore-single-call-c3.md` §4.
  Future<void> _restoreUserProfile(String userId,
      {Object? preFetched = _kNoInject,
      Object? preFetchedUsers = _kNoInject}) async {
    try {
      final rows = identical(preFetched, _kNoInject)
          ? await _supabase.client
              .from('user_profile')
              .select()
              .eq('user_id', userId)
              .limit(1)
          : (preFetched as List? ?? const []);

      // APK Test #12.8 / Bug #2 — `full_name` + `email` live on
      // `public.users`, NOT on `user_profile`. Pre-fix the restore only
      // queried `user_profile`, so post-reinstall `userBox['profile']
      // ['full_name']` stayed null and home greeting rendered "USER".
      // Merge `users` columns into the same profile map.
      Map<String, dynamic> usersRow = const {};
      try {
        final Object? u = identical(preFetchedUsers, _kNoInject)
            ? await _fetchUsersRowForRestore(userId)
            : preFetchedUsers;
        if (u != null) {
          usersRow = Map<String, dynamic>.from(u as Map);
        } else if (!identical(preFetchedUsers, _kNoInject)) {
          // C3 single-call restore already queried `users` through the
          // Edge Function's service-role client (RLS-immune — see
          // restore-user-snapshot/index.ts) and got a real empty result,
          // not the ambiguous stale-token race _fetchUsersRowForRestore
          // exists to retry. Retrying here would just re-ask the same
          // authoritative answer. But a genuinely-absent `users` row is
          // not an expected state for an authenticated restore (see
          // _fetchUsersRowForRestore's doc comment) — surface it distinctly
          // rather than silently matching the retry-path's shape (diagnose
          // d4e9a2 B-pass finding 1).
          unawaited(ErrorTelemetry.logEvent(
              'restore_users_row_null_via_singlecall',
              message: 'userId=${_shortUserId(userId)}'));
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
      // Audit 2026-05-20 A4 — restore-class write routed through
      // canonical service with skipSync: true. The data we just merged
      // came FROM cloud; re-pushing it would create a redundant
      // upsert loop on every restore.
      await ProfileWriteService.instance.updateProfile(merged, skipSync: true);
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

  /// Fetches the `users` row (`full_name`, `email`) for [userId] during
  /// restore, with the same proactive-refresh + one-hard-refresh-retry
  /// pattern `AuthSessionBootstrapper.resolveDestination` uses (diagnose
  /// c2e9f4). A token that expires mid-restore comes back as either a 401
  /// (thrown, caught by the caller) or an RLS-filtered EMPTY result — HTTP
  /// 200, `null` — indistinguishable from "no such row" with no exception at
  /// all. The un-retried version of this call silently dropped `full_name`
  /// from the merge in [_restoreUserProfile] on that second shape: the rest
  /// of the profile restore (from `user_profile`) succeeded, so the failure
  /// was invisible — `hasProfile=true`, `rawName=<null>` at every reader.
  /// See diagnose d4e9a2.
  ///
  /// A genuinely absent `users` row is not an expected state for an
  /// authenticated restore — the row is upserted at first sign-in
  /// (`auth_session_bootstrapper.dart` `_ensureLocalUser` /
  /// `hydrateFromCloud`) — so retrying once on `null` before accepting it is
  /// safe: it can only recover a row that is really there.
  Future<Map<String, dynamic>?> _fetchUsersRowForRestore(String userId) async {
    try {
      await _supabase.ensureFreshToken();
    } catch (e, st) {
      // Non-fatal — the select below may still succeed on the existing
      // token. Recorded so a refresh that fails EVERY restore is visible.
      debugPrint('[SyncService._fetchUsersRowForRestore] token refresh: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'restore_users_row_token_refresh_failed',
          extra: {'user_id': userId}));
    }

    Future<Map<String, dynamic>?> select() => _supabase.client
        .from('users')
        .select('full_name, email')
        .eq('id', userId)
        .maybeSingle();

    final first = await select();
    if (first != null) return first;

    // Empty result is ambiguous (genuinely no row vs RLS-filtered stale
    // token) — one retry behind a HARD refresh before accepting it, same
    // escalation resolveDestination uses for the identical shape.
    unawaited(ErrorTelemetry.logEvent('restore_users_row_empty_retrying',
        message: 'userId=${_shortUserId(userId)}'));
    try {
      await _supabase.client.auth.refreshSession();
      final retried = await select();
      unawaited(ErrorTelemetry.logEvent(
          retried != null
              ? 'restore_users_row_retry_succeeded'
              : 'restore_users_row_retry_still_empty',
          message: 'userId=${_shortUserId(userId)}'));
      return retried;
    } catch (e, st) {
      // The hard refresh itself can throw (e.g. a revoked/expired refresh
      // token on a long-idle tab) — distinguish that from "retried and
      // still empty" so it doesn't fall through to the generic outer
      // catch's shared label (diagnose d4e9a2 B-pass finding 3).
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'restore_users_row_retry_threw',
          extra: {'user_id': userId}));
      return null;
    }
  }

  static String _shortUserId(String userId) =>
      userId.length >= 8 ? userId.substring(0, 8) : userId;

  /// [preFetched] (C3 single-call): injected `user_progress` limit-1 array;
  /// legacy callers omit it → network read. Plan §4.
  Future<void> _restoreUserProgress(String userId,
      {Object? preFetched = _kNoInject}) async {
    try {
      // Bare .select() = SELECT * — this is intentional (Unit 3b, e6b9c4):
      // it means streak_progress_version rides along for free and the
      // merge below adopts it correctly (cloud-always-wins is right for a
      // server-owned optimistic-lock counter the client only ever adopts —
      // same reasoning as _restoreFreezes's explicit version handling). No
      // column list to keep in sync here, unlike _restoreFreezes /
      // restore-user-snapshot's "freezes" projection.
      //
      // ⚠ OI-83 correction. This comment used to justify the merge as
      // cloud-non-null-wins for EVERY key on the grounds that "a fresh restore
      // read is always at least as new as whatever's local." That holds for
      // streak_progress_version — the field it was actually written about —
      // and is FALSE for a client-advanced field: a device that advanced
      // locally and has not yet pushed has state strictly newer than the row
      // this read returns. The premise justified the demotion, so it is
      // corrected here rather than left to re-justify it for the next reader.
      // The three monotonic fields now go through
      // UserRepository.mergeCloudProgress; everything else is unchanged.
      final rows = identical(preFetched, _kNoInject)
          ? await _supabase.client
              .from('user_progress')
              .select()
              .eq('user_id', userId)
              .limit(1)
          : (preFetched as List? ?? const []);

      if (rows.isEmpty) return;
      final cloud = Map<String, dynamic>.from(rows.first as Map);
      cloud.remove('user_id');

      // F6 · Merge semantics (same as _restoreUserProfile), plus the OI-83
      // monotonic guard on the 3 lifetime/phase fields.
      final existing = _hive.userBox.get('progress');
      final existingMap = existing is Map
          ? Map<String, dynamic>.from(existing)
          : <String, dynamic>{};
      final result = UserRepository.mergeCloudProgress(
        local: existingMap,
        cloud: cloud,
      );
      await _hive.userBox.put('progress', result.merged);
      reportProgressDemotionsDeclined(result, source: 'restore_user_progress');
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

  /// Restores user preferences from Supabase.
  ///
  /// [preFetched] (C3 single-call): injected `user_preferences` limit-1 array;
  /// legacy callers omit it → network read. Plan §4.
  Future<void> _restoreUserPreferences(String userId,
      {Object? preFetched = _kNoInject}) async {
    try {
      final rows = identical(preFetched, _kNoInject)
          ? await _supabase.client
              .from('user_preferences')
              .select()
              .eq('user_id', userId)
              .limit(1)
          : (preFetched as List? ?? const []);

      if (rows.isEmpty) return;
      final cloud = Map<String, dynamic>.from(rows.first as Map);
      cloud.remove('user_id');

      // OI-98 / e4a1b7 — pull `notification_preferences` OUT before the merge
      // below. It belongs to `userBox['notification_preferences']`, whose sole
      // owner is NotificationPrefsRepository; the generic merge would otherwise
      // fold it into `userBox['preferences']` as well, leaving the concept in
      // TWO Hive keys with only one of them merged per-key. Nothing reads the
      // shadow copy today, which is precisely how the next reader would come to
      // pick the wrong one.
      final cloudNotificationPrefs = cloud.remove('notification_preferences');

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

      // OWNER RE-CHECK AT THE SINK — guarding BOTH writes below, not just the
      // notification one (B-pass Finding 3: the first version guarded only the
      // new call and left its older sibling two lines above exposed to the
      // identical race, which is the guard-without-its-mirror shape this very
      // batch exists to close).
      //
      // The GuardedBox assert is NOT sufficient on its own: it compares the
      // BOX's owner to the LIVE session, while `userId` was captured at this
      // method's entry and the rows below were fetched under it. After an
      // A -> B account swap where Hive has already reopened for B, that assert
      // passes happily and A's cloud data lands in B's box. `ownerChangedSince`
      // compares the captured id instead, which is the distinction that
      // matters, and its own doc says to call it AT THE WRITE SINK — one
      // statement before the write, never at function entry, so nothing can
      // await in between.
      if (ownerChangedSince(userId)) return;

      await _hive.userBox.put('preferences', merged);

      // OI-98 — THE restore leg this concept never had. Local-wins per key,
      // so a preference the user set on THIS device (including one set seconds
      // ago through RestoringScreen's 30s CONTINUE escape, while this restore
      // was still running) is never overwritten by an older cloud copy.
      if (cloudNotificationPrefs != null) {
        await NotificationPrefsRepository.adoptFromCloud(cloudNotificationPrefs);
      }
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

  // ── SyncDomain public forwarders for profile helpers (A6 migration) ──

  Future<void> pushUserProfileForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _syncUserProfile(userId);
  }

  Future<void> restoreUserProfileForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _restoreUserProfile(userId);
  }

  Future<void> pushUserProgressForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _syncUserProgress(userId);
  }

  Future<void> restoreUserProgressForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _restoreUserProgress(userId);
  }

  Future<void> pushUserPreferencesForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _syncUserPreferences(userId);
  }

  Future<void> restoreUserPreferencesForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _restoreUserPreferences(userId);
  }
}

/// Builds the `user_preferences` upsert payload. PURE — no Hive, no network.
///
/// Extracted so the WRITE path is behaviourally testable at all. The B-pass on
/// this batch found a P0 here that every test missed for exactly one reason:
/// the suite exercised the restore path and the snapshot emission, and NOTHING
/// asserted the shape of what this method sends.
///
/// TWO COLUMNS IT MUST NEVER CARRY, both learned the hard way:
///
///   - `notification_preferences` — a jsonb column is replaced WHOLESALE by an
///     upsert (`SET col = EXCLUDED.col` is assignment, not a merge), and the
///     stored map is legitimately sparse, so sending it here lets a device
///     delete every preference it has not personally seen. It goes through
///     migration 123's `merge_notification_preferences` RPC instead, which
///     merges per key.
///   - `coaching_notes` — the client is a pure CONSUMER of it. Its writers are
///     `daily-snapshot` (extracted AI facts) and `assess-body-composition` (the
///     `last_bf_assessed_at` 30-day PRO rate-limit stamp). Naming it here with a
///     null local value put an explicit NULL in the generated SET list and wiped
///     both.
///
/// Returns `{user_id: ...}` alone when there is nothing to say; the caller
/// treats a single-key payload as "skip the upsert" rather than sending a row
/// that asserts defaults over real values.
///
/// audit-2026-05-16 E.12 — migration 067 dropped
/// `user_preferences.biggest_obstacle` (no UI writer; 100% NULL).
@visibleForTesting
Map<String, dynamic> buildUserPreferencesPayload({
  required String userId,
  required Map<String, dynamic> preferences,
}) {
  final payload = <String, dynamic>{'user_id': userId};
  if (preferences.isNotEmpty) {
    payload['motivational_style'] =
        preferences['motivational_style'] ?? 'encouraging';
    payload['preferred_language'] = preferences['preferred_language'] ?? 'en';
  }
  return payload;
}
