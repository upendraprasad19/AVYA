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
        // Rank-evaluation columns (migration 081, diagnose b9f4d2). The server
        // cron `evaluate-rank-promotions` SELECTs these to evaluate the ladder;
        // pre-081 they didn't exist → the cron read null → only ever granted SD2.
        // Source of truth is the CLIENT (schedule-aware streak walk + the F18
        // deployment counter). current_streak_days + last_workout_date are
        // already stamped into `progress` by train_provider on workout
        // completion; deployments_complete by UserRepository.updateProgress.
        if (p['deployments_complete'] != null) 'deployments_complete': p['deployments_complete'],
        if (p['current_streak_days'] != null) 'current_streak_days': p['current_streak_days'],
        if (p['last_workout_date'] != null) 'last_workout_date': p['last_workout_date'],
        if (p['longest_gap_days'] != null) 'longest_gap_days': p['longest_gap_days'],
        // Stamp updated_at on every push — there is NO DB trigger on
        // user_progress, so without this the column stays frozen at created_at
        // even as the row's data advances, and any "changed-since" /
        // incremental-sync / conflict logic keyed on it is wrong (diagnose a2d8f4).
        'updated_at': DateTime.now().toUtc().toIso8601String(),
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

  /// Pushes user preferences to Supabase user_preferences table.
  Future<void> _syncUserPreferences(String userId) async {
    try {
      final prefs = _hive.userBox.get('preferences');
      if (prefs == null) return;
      final p = Map<String, dynamic>.from(prefs as Map);

      // audit-2026-05-16 E.12 — migration 067 dropped
      // `user_preferences.biggest_obstacle` (no UI writer; 100% NULL).
      await _supabase.client.from('user_preferences').upsert({
        'user_id': userId,
        'motivational_style': p['motivational_style'] ?? 'encouraging',
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
