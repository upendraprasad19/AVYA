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
      // Phase 2 Unit C — include the first-pro-grant flag so it
      // survives reinstalls and cross-device scenarios. The column
      // was added by migration 095 (default false; backfill covers
      // ever-PRO users). Only push when it is explicitly true so
      // brand-new free users don't stomp a backfill-true cloud row
      // with false on first sync.
      final grantDone =
          p['streak_freezes_first_pro_grant_done'] as bool? ?? false;
      await _supabase.client.from('user_progress').upsert({
        'user_id': userId,
        'streak_freezes_available': available,
        'streak_freezes_used_dates': used,
        if (lastRefill != null) 'streak_freezes_last_refill': lastRefill,
        if (grantDone) 'streak_freezes_first_pro_grant_done': true,
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
      // E.14.A · audit-2026-05-16 — success-path emission. The audit
      // could not distinguish "user never saved a diet plan" from
      // "this call has been silently failing for a week".
      unawaited(ErrorTelemetry.logEvent('upsert_saved_diet_plans_success'));
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
            'streak_freezes_last_refill, '
            'streak_freezes_first_pro_grant_done',
          )
          .eq('user_id', userId)
          .maybeSingle();
      if (res == null) return;

      final box = _hive.userBox;
      final existing = box.get('progress');
      final existingMap = existing is Map
          ? Map<String, dynamic>.from(existing)
          : <String, dynamic>{};

      // Refill-aware merge (a8f3d1). `used_dates` is PER-WEEK (cleared on refill),
      // so the merge keys on last_refill. Pre-fix this lumped equal-refill into
      // cloud-wins AND unconditionally overwrote used_dates → a freeze consumed
      // locally during the background-restore window (slow-boot flip, ADR-0014,
      // lands /home BEFORE this Step C runs) was wiped + the freeze refunded
      // (spurious streak break). The (available, last_refill) max-merge half was
      // Bug 9c4a17; used_dates was the unguarded leg. Clamp(0,3) kept (f8c1a5).
      final cloudLastRefillRaw = res['streak_freezes_last_refill'];
      final usedRaw = res['streak_freezes_used_dates'];
      final merged = StreakProgressService.mergeFreezeProgress(
        localAvailable: (existingMap['streak_freezes_available'] as int?) ??
            (res['streak_freezes_available'] as int?) ??
            1,
        localUsed: (existingMap['streak_freeze_used_dates'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[],
        localLastRefill: existingMap['streak_freezes_last_refill'] as String?,
        cloudAvailable: (res['streak_freezes_available'] as int?) ?? 1,
        cloudUsed: (usedRaw is List)
            ? usedRaw.map((e) => e.toString()).toList()
            : const <String>[],
        cloudLastRefill:
            cloudLastRefillRaw == null ? null : cloudLastRefillRaw.toString(),
      );
      existingMap['streak_freezes_available'] = merged.available;
      existingMap['streak_freeze_used_dates'] = merged.usedDates;
      if (merged.lastRefill != null) {
        existingMap['streak_freezes_last_refill'] = merged.lastRefill;
      }
      // Phase 2 Unit C — restore the grant-done flag from cloud so a
      // reinstall doesn't phantom-grant 3 freezes on first boot.
      // Only overwrite local with cloud=true (never regress a local
      // true back to cloud false — cloud backfill may lag first sync).
      final cloudGrantDone =
          res['streak_freezes_first_pro_grant_done'] as bool? ?? false;
      if (cloudGrantDone) {
        existingMap['streak_freezes_first_pro_grant_done'] = true;
      }
      await box.put('progress', existingMap);
      if (merged.scheduleSyncUp) {
        unawaited(SyncService.instance.syncFreezes());
      }
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

  /// E.10 (F4-S2 / audit 2026-05-16) — Restores the user's current
  /// non-expired referral code from `referral_codes` cloud table
  /// (migration 035 + 037) into `userBox['referral_code']`.
  ///
  /// The cloud table has `UNIQUE(user_id)` so there is at most one
  /// active row per user. We filter by `expires_at > now()` (matching
  /// the 7-day window introduced in migration 037) and stash the most
  /// recent code so [InviteFriendsSheet] can render without hitting the
  /// network on cold-start. If the local cache is missing or expired,
  /// the UI still calls [SupabaseService.getOrCreateReferralCode] which
  /// upserts a fresh row.
  ///
  /// FK quirk (CLAUDE.md §7): `referral_codes.user_id` is the ONLY
  /// user-scoped FK pointing at `auth.users(id)` rather than
  /// `public.users(id)` — because codes are generated before the
  /// onboarding sync path inserts the user into `public.users`. The
  /// restore path is FK-direction-agnostic (we SELECT by user_id, not
  /// JOIN), so no special handling is required here.
  Future<void> _restoreReferralCodes(String userId) async {
    try {
      final res = await _supabase.client
          .from('referral_codes')
          .select('code, expires_at, created_at')
          .eq('user_id', userId)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (res == null) return;
      final code = res['code'] as String?;
      final expiresAt = res['expires_at'];
      if (code == null || code.isEmpty) return;
      await _hive.userBox.put('referral_code', <String, dynamic>{
        'code': code,
        if (expiresAt != null) 'expires_at': expiresAt.toString(),
        if (res['created_at'] != null)
          'created_at': res['created_at'].toString(),
      });
    } catch (e, st) {
      debugPrint('[SyncService._restoreReferralCodes] error: $e\n$st');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_restore_referral_codes'));
      try {
        await _reportSyncFailure(
            opType: 'restore_referral_codes', error: e);
      } catch (_) {}
    }
  }

  /// E.10 (F4-S2 / audit 2026-05-16) — Restores up to 50 referral
  /// redemption audit rows from `referral_redemptions` cloud table
  /// (migration 037) into `userBox['referral_redemption_history']`.
  ///
  /// Pulled for BOTH sides of the relationship — the user may be the
  /// referrer (someone used their code) or the referee (they used
  /// someone else's code). Stored as a raw list of maps so the
  /// Profile → Invite Friends sheet can render an audit list without
  /// hitting the network. 50-row cap is plenty (rare-enough event).
  ///
  /// FK note (CLAUDE.md §7): both `referrer_id` and `referee_id` FK to
  /// `public.users(id)` (corrected 2026-05-12 P3-A). Both columns are
  /// indexed (idx_referral_redemptions_referrer + the implicit unique
  /// index on referee_id), so the `OR` filter is cheap. PostgREST
  /// uses comma-separated `or=` syntax via the `.or()` builder.
  Future<void> _restoreReferralRedemptions(String userId) async {
    try {
      final rows = await _supabase.client
          .from('referral_redemptions')
          .select(
            'code, referrer_id, referee_id, days_granted_each, created_at',
          )
          .or('referrer_id.eq.$userId,referee_id.eq.$userId')
          .order('created_at', ascending: false)
          .limit(50);
      await _hive.userBox.put('referral_redemption_history', rows);
    } catch (e, st) {
      debugPrint('[SyncService._restoreReferralRedemptions] error: $e\n$st');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_restore_referral_redemptions'));
      try {
        await _reportSyncFailure(
            opType: 'restore_referral_redemptions', error: e);
      } catch (_) {}
    }
  }

  // ── SyncDomain public forwarders for restore-completeness helpers (A6) ──

  Future<void> restoreFreezesForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _restoreFreezes(userId);
  }

  Future<void> restoreNotificationsInboxForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _restoreNotificationsInbox(userId);
  }

  Future<void> restoreSavedDietPlanForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _restoreSavedDietPlan(userId);
  }

  Future<void> restoreRankPromotionsForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _restoreRankPromotions(userId);
  }

  Future<void> restoreReferralCodesForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _restoreReferralCodes(userId);
  }

  Future<void> restoreReferralRedemptionsForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _restoreReferralRedemptions(userId);
  }
}
