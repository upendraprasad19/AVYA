part of '../sync_service.dart';

/// APK Test #11 — Theme A push + restore for the 4 Hive-only surfaces
/// that previously vanished on reinstall: streak freezes, notifications
/// inbox, saved diet plan, rank promotions. See CLAUDE.md §15
/// "Restore-completeness sync" for the canonical contract.
extension SyncServiceRestoreCompleteness on SyncService {
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
}
