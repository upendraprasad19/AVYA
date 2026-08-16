part of '../sync_service.dart';

/// Canonical 8-4-4-4-12 hex UUID shape.
///
/// Shape-only on purpose (diagnose a4f1c8): we are not validating a uuid, we
/// are rejecting the ids that provably CANNOT cast to Postgres `uuid` and so
/// can only ever return 22P02. Anything that would cast is left alone.
final _uuidShapeRe = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

bool isUuidShaped(String s) => _uuidShapeRe.hasMatch(s);

/// APK Test #11 — Theme A push + restore for the 4 Hive-only surfaces
/// that previously vanished on reinstall: streak freezes, notifications
/// inbox, saved diet plan, rank promotions. See CLAUDE.md §15
/// "Restore-completeness sync" for the canonical contract.
extension SyncServiceRestoreCompleteness on SyncService {
  // ── Restore-completeness push (Theme A push side) ─────────

  /// Pushes the user's streak-freeze state to the three new columns on
  /// `user_progress` (migration 048). Called fire-and-forget from every
  /// Hive mutation site in WorkoutRepository + home_provider per CLAUDE.md
  /// §15.
  ///
  /// Unit 3b (OI-45 cross-device half, e6b9c4): routes through the
  /// `update_streak_progress` optimistic-lock RPC (migration 056/090/091/096
  /// — live, correct, was dormant: zero callers before this fix) instead of
  /// a raw version-blind upsert. Device A consumes a freeze (available: 1->0)
  /// while device B has a stale read (available: 1) and refills (->2) was
  /// the exact race migration 056's own header names; the RPC existed but
  /// nothing called it.
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

      // expected_version defaults to 0 for a local install that has never
      // seen a version back from the cloud yet — matches the RPC's own
      // fresh-row contract (p_expected_version <> 0 on a NOT-FOUND row
      // returns NULL, forcing a re-read rather than a phantom insert).
      final expectedVersion =
          (p['streak_progress_version'] as num?)?.toInt() ?? 0;
      final firstAttempt = await _supabase.client.rpc(
        'update_streak_progress',
        params: {
          'p_user_id': userId,
          'p_expected_version': expectedVersion,
          'p_freezes_available': available,
          'p_freeze_used_dates': used,
          'p_freezes_last_refill': lastRefill,
        },
      );
      final firstVersion = (firstAttempt as num?)?.toInt();
      if (firstVersion != null) {
        SyncService._stampProgressVersion(firstVersion, userId: userId);
      } else {
        // Version mismatch — a concurrent device's write landed first.
        // Bounded: one re-fetch + reconcile + retry, then drop (matches
        // this codebase's fire-and-forget-self-heals-on-next-write
        // philosophy, not a new queue).
        await _retrySyncFreezesOnceAfterConflict(
          userId: userId,
          localAvailable: available,
          localUsed: used,
          localLastRefill: lastRefill,
        );
      }

      // streak_freezes_first_pro_grant_done is deliberately NOT in
      // update_streak_progress's signature — excluded from the optimistic
      // lock. It is monotonic one-directional (false -> true, never
      // regresses) and only ever pushed when locally true, so a
      // cross-device race on it is provably harmless: worst case is a
      // redundant "true" write that doesn't change the final state.
      // Extending the RPC signature would add migration risk for a field
      // that structurally cannot lose data from a race. Kept as a plain
      // upsert, same as before this fix.
      if (grantDone) {
        await _supabase.client.from('user_progress').upsert({
          'user_id': userId,
          'streak_freezes_first_pro_grant_done': true,
        }, onConflict: 'user_id');
      }
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

  /// Unit 3b (e6b9c4) — bounded retry for `syncFreezes` after a version
  /// mismatch. Re-fetches the fresh cloud row, reconciles via the SAME pure
  /// merge the restore path already uses ([StreakProgressService.
  /// mergeFreezeProgress] — tested, established), retries ONCE against the
  /// fresh version, then drops (logs telemetry, does not loop). On success,
  /// writes the MERGED values back to local Hive too — not just the cloud —
  /// so local state doesn't stay diverged from what the cloud now holds.
  Future<void> _retrySyncFreezesOnceAfterConflict({
    required String userId,
    required int localAvailable,
    required List<String> localUsed,
    required String? localLastRefill,
  }) async {
    final Object? rawRes = await _supabase.client
        .from('user_progress')
        .select(
          'streak_freezes_available, streak_freezes_used_dates, '
          'streak_freezes_last_refill, streak_progress_version',
        )
        .eq('user_id', userId)
        .maybeSingle();
    if (rawRes == null) {
      // Hermes C7 (2026-07-30): was a silent return — see the twin fix in
      // sync_profile.dart's _retrySyncUserProgressOnceAfterConflict for the
      // full reasoning (both RPCs return NULL for row-absent, so this does
      // NOT prove the row doesn't exist; self-perpetuating if silent).
      unawaited(ErrorTelemetry.logEvent(
        'sync_freezes_row_absent_after_conflict',
        message: 'user=$userId — cloud row absent on retry re-fetch, '
            'dropped whole freeze snapshot',
      ));
      return;
    }
    final res = rawRes as Map;

    final cloudVersion = (res['streak_progress_version'] as num?)?.toInt();
    if (cloudVersion == null) return;

    // Hermes C2 (2026-07-30): re-read LOCAL freeze state fresh here rather
    // than trusting localAvailable/localUsed/localLastRefill — those were
    // captured in syncFreezes() BEFORE its own RPC round-trip and this
    // helper's cloud re-fetch above, so a same-device write landing in
    // that window (routine — commitConsume/commitRefill/etc. all fire
    // unawaited(syncFreezes())) would otherwise be invisible to this merge
    // and then silently undone by the write-back below (Hermes L27 F1 —
    // the single most severe finding in that pass: this retry path was
    // reproducing, inside the fix, the exact same-device race class the
    // whole batch exists to close). Falls back to the captured params
    // only if Hive genuinely has no progress map yet.
    final freshLocal = _hive.userBox.get('progress');
    final freshLocalMap =
        freshLocal is Map ? Map<String, dynamic>.from(freshLocal) : null;
    final freshAvailable =
        (freshLocalMap?['streak_freezes_available'] as int?) ?? localAvailable;
    final freshUsedRaw = freshLocalMap?['streak_freeze_used_dates'];
    final freshUsed = (freshUsedRaw is List)
        ? freshUsedRaw.map((e) => e.toString()).toList()
        : localUsed;
    final freshLastRefill =
        freshLocalMap?['streak_freezes_last_refill'] as String? ??
            localLastRefill;

    final cloudUsedRaw = res['streak_freezes_used_dates'];
    final merged = StreakProgressService.mergeFreezeProgress(
      localAvailable: freshAvailable,
      localUsed: freshUsed,
      localLastRefill: freshLastRefill,
      cloudAvailable: (res['streak_freezes_available'] as int?) ?? 1,
      cloudUsed: (cloudUsedRaw is List)
          ? cloudUsedRaw.map((e) => e.toString()).toList()
          : const <String>[],
      cloudLastRefill: res['streak_freezes_last_refill']?.toString(),
    );

    final retryResult = await _supabase.client.rpc(
      'update_streak_progress',
      params: {
        'p_user_id': userId,
        'p_expected_version': cloudVersion,
        'p_freezes_available': merged.available,
        'p_freeze_used_dates': merged.usedDates,
        'p_freezes_last_refill': merged.lastRefill,
      },
    );
    final retryVersion = (retryResult as num?)?.toInt();
    if (retryVersion == null) {
      // Second consecutive mismatch — drop rather than loop. The next
      // mutation site's own syncFreezes call (or the next restore) will
      // reconcile from a fresher snapshot.
      unawaited(ErrorTelemetry.logEvent(
        'sync_freezes_retry_dropped',
        message: 'user=$userId expected=$cloudVersion — dropped after '
            'one retry',
      ));
      return;
    }

    SyncService._stampProgressVersion(retryVersion, userId: userId);
    // Hermes C2: the RPC round-trip just above is itself another await
    // window a same-device write could land in. Re-merge whatever's fresh
    // in Hive RIGHT NOW against what the cloud now definitively holds
    // (`merged`, just confirmed by the RPC as the new cloud state) instead
    // of blindly overwriting with `merged` — folds in any write that
    // landed during this retry using the SAME reconciliation logic the
    // first merge pass (and _restoreFreezes) already rely on, rather than
    // a raw overwrite. The read-merge-put below is await-free so it's
    // atomic on the event loop (same reasoning _restoreFreezes's own
    // comment already documents for that method).
    //
    // B-pass round-2 (2026-07-30): ownership guard, same as
    // _stampProgressVersion's — that call above only protects the version
    // stamp, not THIS separate write. Without it, a sign-out/sign-in-as-
    // different-user race landing inside the single RPC await above would
    // write device-A-derived freeze data into whatever account is live now.
    if (HiveUserSession.currentOwnerFullId != userId) return;
    final box = _hive.userBox;
    final existing = box.get('progress');
    if (existing is Map) {
      final p = Map<String, dynamic>.from(existing);
      final finalUsedRaw = p['streak_freeze_used_dates'];
      final finalMerge = StreakProgressService.mergeFreezeProgress(
        localAvailable:
            (p['streak_freezes_available'] as int?) ?? merged.available,
        localUsed: (finalUsedRaw is List)
            ? finalUsedRaw.map((e) => e.toString()).toList()
            : merged.usedDates,
        localLastRefill:
            p['streak_freezes_last_refill'] as String? ?? merged.lastRefill,
        cloudAvailable: merged.available,
        cloudUsed: merged.usedDates,
        cloudLastRefill: merged.lastRefill,
      );
      p['streak_freezes_available'] = finalMerge.available;
      p['streak_freeze_used_dates'] = finalMerge.usedDates;
      if (finalMerge.lastRefill != null) {
        p['streak_freezes_last_refill'] = finalMerge.lastRefill;
      }
      await box.put('progress', p);
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
      // `notifications_inbox.id` is a uuid column, so a non-uuid id can only
      // ever produce 22P02 — a guaranteed 400 on every attempt, forever
      // (diagnose a4f1c8: legacy 'local-welcome-<micros>' ids did exactly
      // that). Skipping is correct rather than lossy: these are locally-seeded
      // rows with no cloud counterpart to reconcile against, and the writer
      // now mints real uuids so only pre-fix installs take this branch.
      if (!isUuidShaped(id)) return;
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
  /// [preFetched] (C3 single-call): injected `freezes` object|null (the 4-col
  /// `user_progress` subset). Legacy callers omit it → network `maybeSingle`
  /// read; an injected `null` is honored exactly like the network null. Plan §4.
  Future<void> _restoreFreezes(String userId,
      {Object? preFetched = _kNoInject}) async {
    try {
      final Object? rawRes = identical(preFetched, _kNoInject)
          ? await _supabase.client
              .from('user_progress')
              .select(
                'streak_freezes_available, streak_freezes_used_dates, '
                'streak_freezes_last_refill, '
                'streak_freezes_first_pro_grant_done, '
                // Unit 3b (e6b9c4) — the cross-device optimistic-lock version.
                // Must stay in sync with restore-user-snapshot/index.ts's
                // "freezes" bundle projection (H-1 shape contract).
                'streak_progress_version',
              )
              .eq('user_id', userId)
              .maybeSingle()
          : preFetched;
      if (rawRes == null) return;
      // Normalize the maybeSingle result / injected object to a typed map so
      // the merge logic below is unchanged.
      final Map res = rawRes as Map;

      final box = _hive.userBox;
      final existing = box.get('progress');
      final existingMap = existing is Map
          ? Map<String, dynamic>.from(existing)
          : <String, dynamic>{};

      // Refill-aware merge. D1 (f9d2e7): `used_dates` is now a PERMANENT ledger
      // (commitRefill prunes >365d, never clears), so mergeFreezeProgress ALWAYS
      // unions used_dates on every branch — neither a stale cloud snapshot nor a
      // fresh local consume may drop a historically-frozen day. The weekly BUDGET
      // (available, last_refill) still keys on last_refill (the 9c4a17 max-merge
      // half; a8f3d1 stopped the unconditional same-week overwrite). Clamp(0,3)
      // kept (f8c1a5). The slow-boot flip (ADR-0014) lands /home BEFORE this
      // Step C runs, so a freeze consumed locally in that window must survive —
      // the always-union guarantees it. (read→merge→put here is await-free, so
      // the read-modify-write is atomic on the event loop.)
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
      // Unit 3b (e6b9c4) — streak_progress_version is a pure server-side
      // monotonic counter; the client never invents one, only ever adopts
      // the freshest value it has seen. A fresh restore read is always at
      // least as new as whatever's local, so cloud unconditionally wins
      // (no merge needed, unlike available/used_dates/last_refill above).
      final cloudVersion = (res['streak_progress_version'] as num?)?.toInt();
      if (cloudVersion != null) {
        existingMap['streak_progress_version'] = cloudVersion;
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
  /// [preFetched] (C3 single-call): injected `notifications_inbox` rows; legacy
  /// callers omit it → network read. Plan §4.
  Future<void> _restoreNotificationsInbox(String userId,
      {Object? preFetched = _kNoInject}) async {
    try {
      final rows = identical(preFetched, _kNoInject)
          ? await _supabase.client
              .from('notifications_inbox')
              .select()
              .eq('user_id', userId)
              .order('created_at', ascending: false)
              .limit(200)
          : (preFetched as List? ?? const []);

      final box = _hive.notificationsBox;
      for (final rawRow in rows) {
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
  /// [preFetched] (C3 single-call): injected `saved_diet_plan` object|null;
  /// legacy callers omit it → network `maybeSingle` read; an injected `null` is
  /// honored like the network null. Plan §4.
  Future<void> _restoreSavedDietPlan(String userId,
      {Object? preFetched = _kNoInject}) async {
    try {
      final Object? res = identical(preFetched, _kNoInject)
          ? await _supabase.client
              .from('saved_diet_plans')
              .select('plan_json')
              .eq('user_id', userId)
              .maybeSingle()
          : preFetched;
      if (res == null) return;
      final planJson = (res as Map)['plan_json'];
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
  /// [preFetched] (C3 single-call): injected `rank_promotions` rows; legacy
  /// callers omit it → network read. Plan §4.
  Future<void> _restoreRankPromotions(String userId,
      {Object? preFetched = _kNoInject}) async {
    try {
      final rows = identical(preFetched, _kNoInject)
          ? await _supabase.client
              .from('rank_promotions')
              .select()
              .eq('user_id', userId)
              .order('achieved_at', ascending: false)
              .limit(20)
          : (preFetched as List? ?? const []);
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
  /// [preFetched] (C3 single-call): injected `referral_codes` object|null
  /// (already filtered to a non-expired limit-1 row by the EF); legacy callers
  /// omit it → network `maybeSingle` read; an injected `null` is honored like
  /// the network null. Plan §4.
  Future<void> _restoreReferralCodes(String userId,
      {Object? preFetched = _kNoInject}) async {
    try {
      final Object? rawRes = identical(preFetched, _kNoInject)
          ? await _supabase.client
              .from('referral_codes')
              .select('code, expires_at, created_at')
              .eq('user_id', userId)
              .gt('expires_at', DateTime.now().toUtc().toIso8601String())
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle()
          : preFetched;
      if (rawRes == null) return;
      final Map res = rawRes as Map;
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
  /// [preFetched] (C3 single-call): injected `referral_redemptions` rows
  /// (dual-FK matched by the EF); legacy callers omit it → network read.
  /// Plan §4.
  Future<void> _restoreReferralRedemptions(String userId,
      {Object? preFetched = _kNoInject}) async {
    try {
      final rows = identical(preFetched, _kNoInject)
          ? await _supabase.client
              .from('referral_redemptions')
              .select(
                'code, referrer_id, referee_id, days_granted_each, created_at',
              )
              .or('referrer_id.eq.$userId,referee_id.eq.$userId')
              .order('created_at', ascending: false)
              .limit(50)
          : (preFetched as List? ?? const []);
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
