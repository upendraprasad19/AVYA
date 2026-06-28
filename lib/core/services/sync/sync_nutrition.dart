part of '../sync_service.dart';

/// Sync + restore for nutrition domain: nutrition_logs (+ per-item items),
/// water_logs, user_saved_meals.
///
/// `syncNutritionData()` is the SoT fan-out entry point pinned by
/// `test/contracts/sync_fanout_contract_test.dart` — its body MUST
/// continue to call `_syncNutritionLogs`, `_syncWaterLogs`, and
/// `_syncSavedMeals` (CLAUDE.md §15).
///
/// Static helper `_nlogKeyForRestore` stays on the SyncService class
/// alongside the other deterministic-id helpers — extension methods
/// reference it via `SyncService._nlogKeyForRestore(...)`.
extension SyncServiceNutrition on SyncService {
  /// Push nutrition logs + water logs to Supabase.
  /// Call this after a meal is logged (text AI / scan meal / manual / barcode)
  /// or after water is updated, so the daily sync isn't the only safety net.
  ///
  /// Fire-and-forget: offline failure logs silently and retries on next
  /// full sync. Never throws to the caller.
  /// Coalesced fire-and-forget entry (per-write). A burst collapses to 1–2
  /// cloud passes via [SyncCoalescer] (Unit H / H1a). Awaited callers (the sim
  /// harness) MUST use [syncNutritionDataNow]. Kill-switch
  /// `disable_sync_debounce` bypasses the coalescer.
  Future<void> syncNutritionData() async {
    if (SyncService.pausedForSimulation) return; // sim bulk-backfill (guard FIRST)
    if (_syncDebounceDisabled) {
      await syncNutritionDataNow();
      return;
    }
    await _nutritionCoalescer.trigger(syncNutritionDataNow);
  }

  /// Non-coalesced nutrition-domain push — runs the full fan-out NOW. Called by
  /// awaited callers (the sim harness) and internally by [syncNutritionData]'s
  /// coalescer. Pinned by `sync_fanout_contract_test`: MUST call all 3 helpers.
  Future<void> syncNutritionDataNow() async {
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
      debugPrint('[SyncService.syncNutritionDataNow] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_sync_nutrition_data'));
      try {
        await _reportSyncFailure(opType: 'sync_nutrition_data', error: e);
      } catch (_) {}
    }
  }

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

  // ── Push helpers ────────────────────────────────────────────

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
        // We explicitly project only the schema-matching columns. The id
        // handling is covered by Diagnose c9f2a7 below — `id` is OMITTED so
        // the natural-key upsert never rewrites a FK-referenced PK.
        // Audit 2026-05-15 — null-natural-key guard, hoisted FIRST (Diagnose
        // c9f2a7 needs date+meal_type both to resolve the canonical cloud
        // id below AND as the upsert arbiter). A missing key would otherwise
        // produce a partial row with NULL natural-key columns + a
        // deterministic id, which PostgREST would 23502 (or worse, merge
        // unrelated rows onto a single null-keyed cloud row). Skip +
        // telemetry instead.
        final nlogDate = (log['date'] as String?)?.trim();
        final nlogMeal = (log['meal_type'] as String?)?.trim();
        if (nlogDate == null ||
            nlogDate.isEmpty ||
            nlogMeal == null ||
            nlogMeal.isEmpty) {
          unawaited(ErrorTelemetry.logEvent(
            'sync_skipped_null_natural_key',
            message:
                'table=nutrition_logs key=$key date_null=${nlogDate == null || nlogDate.isEmpty} meal_type_null=${nlogMeal == null || nlogMeal.isEmpty}',
          ));
          continue;
        }

        // Diagnose c9f2a7 (2026-06-01) — found live driving the AI coach as
        // amar: EVERY nutrition sync failed with
        //   PostgrestException 23503 "update or delete on table
        //   nutrition_logs violates foreign key constraint
        //   nutrition_log_items_log_id_fkey — Key is still referenced".
        // The upsert conflicts on the natural key (user_id,date,meal_type).
        // The nlog_ Hive key embeds an itemsHash, so the SAME (date,meal_type)
        // yields a DIFFERENT _deterministicId whenever the item set changes
        // (re-log / edit / coach-merge), and other writers (the headless sim,
        // legacy keys) seeded rows under yet other ids. Pre-fix the payload
        // sent `id: _deterministicId(key)` — so when a cloud row already
        // existed for the natural key under a DIFFERENT id, ON CONFLICT DO
        // UPDATE tried to rewrite that row's PK `id`. nutrition_log_items.log_id
        // FK-references the PK with ON DELETE CASCADE but ON UPDATE NO ACTION,
        // so Postgres rejected the PK change (23503) and the WHOLE parent
        // upsert + its child items silently failed to reach cloud — nutrition
        // never backed up for that user (offline-first hides it;
        // reinstall/device-switch loses the data).
        //
        // This is a recurrence of the SAME class fixed for workout_templates
        // (APK Test #12.8 / Bug #4, diagnose a8b2c7) and scheduled_workouts
        // (APK Test #14 / Bug B.1, diagnose c8e4a1) — nutrition_logs was the
        // last sync still sending a derived id. Same cure: OMIT `id` from the
        // payload so PostgREST keeps the existing row's id on conflict (DO
        // UPDATE only sets the columns present) and uses the column default
        // gen_random_uuid() on first insert — the PK is never rewritten, so
        // the FK is never tripped. Then resolve the real cloud id by the
        // natural key for the children's log_id.
        final parentPayload = <String, dynamic>{
          // `id` deliberately OMITTED — see above (never rewrite the PK).
          'user_id': userId,
          'date': nlogDate,
          'meal_type': nlogMeal,
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
        // onConflict on the natural key (Audit 2026-05-12 P0-B): the live
        // schema has UNIQUE (user_id, date, meal_type), so PostgREST merges
        // instead of 23505-ing when a dedup key rotates. With `id` omitted the
        // DO UPDATE never touches the PK → no 23503.
        await _supabase.client.from("nutrition_logs").upsert(
          parentPayload,
          onConflict: "user_id,date,meal_type",
        );

        // Resolve the real cloud id (gen_random_uuid() on insert, or the
        // pre-existing id on conflict) so the child nutrition_log_items FK to
        // the correct parent. If this lookup fails the parent has already
        // landed safely; skip the children this pass and let the next sync
        // retry them.
        String? logCloudId;
        try {
          final parentRow = await _supabase.client
              .from('nutrition_logs')
              .select('id')
              .eq('user_id', userId)
              .eq('date', nlogDate)
              .eq('meal_type', nlogMeal)
              .maybeSingle();
          logCloudId = parentRow?['id'] as String?;
        } catch (idErr, st) {
          debugPrint(
              '[SyncService._syncNutritionLogs] parent id lookup: $idErr');
          unawaited(ErrorTelemetry.recordNonFatal(idErr, st,
              reason: 'sync_service_nutrition_parent_id'));
        }
        if (logCloudId == null || logCloudId.isEmpty) {
          continue;
        }

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
            try {
              // Per-item projection — schema-matched. nutrition_log_items
              // columns (post-migration 068): id, log_id, food_id,
              // food_name, quantity_g, calories, protein, carbs, fat,
              // fiber, created_at.
              //
              // Drift-fix batch 2026-05-24:
              //   T3 / F3 — dropped dead fallback reads on `food_name`
              //     and `serving_g`; FoodItem.toMap() (the canonical
              //     writer) only emits `name` + `quantity_g`.
              //   T4 / F4 — added `fiber` projection alongside
              //     migration 068.
              //
              // Plan C-4 (Test #6): close obs #23 by making sure every
              // Hive nlog_* row produces N nutrition_log_items rows on
              // sync — verified in test/nutrition_write_service/
              // logMeal_creates_logs_and_items_atomically_test.dart.
              await _supabase.client.from('nutrition_log_items').upsert({
                // `id` OMITTED (gen_random_uuid default) — Diagnose f7e3a1
                // (2026-06-03): the old `id: _deterministicId('${key}_item_$i')`
                // had NO user component (the nlog key embeds date+meal+itemsHash,
                // never user_id), so two users logging the same food in the same
                // meal-type on the same date produced the SAME item uuid →
                // onConflict:'id' DO UPDATE STOLE the row (flipped its log_id to
                // the other user's parent). Same cross-user class as d4b8e2. Cure:
                // omit id + a parent-scoped, POSITION-stable arbiter
                // (log_id, item_index). food_name is NOT a safe arbiter — a meal
                // legitimately holds the same food twice (12 live groups), so
                // (log_id, food_name) would merge + lose data. item_index (the
                // item's position in the meal) is unique within the user-scoped
                // log, idempotent on re-sync, and never merges legit duplicates.
                'log_id': logCloudId,
                'item_index': i,
                'food_name': item['name'] ?? '',
                if (item['quantity_g'] != null)
                  'quantity_g': item['quantity_g'],
                if (item['calories'] != null) 'calories': item['calories'],
                if (item['protein'] != null) 'protein': item['protein'],
                if (item['carbs'] != null) 'carbs': item['carbs'],
                if (item['fat'] != null) 'fat': item['fat'],
                'fiber': item['fiber'] ?? 0,
              }, onConflict: 'log_id,item_index');
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
        // Diagnose f7e3a1 (2026-06-03) — the old `id: _deterministicId(hiveId)`
        // where hiveId = `saved_meal_<...>` had NO user component, so two users
        // who saved a meal with the same name produced the SAME uuid →
        // onConflict:'id' DO UPDATE OVERWROTE one user's meal with the other's
        // (and flipped `user_id`). Same cross-user class as d4b8e2. Cure: omit id
        // (gen_random_uuid default) + the user-scoped natural key (user_id, name)
        // as the arbiter — a saved meal's identity IS (user, name). Both columns
        // are NOT NULL → non-partial unique index, no 42P10; the cloud table is
        // empty today, so zero existing-data risk on the index. (NB: the LOCAL
        // writer saveMealPreset currently keys Hive by `saved_meal_<ms>`, which
        // disagrees with the restore's `saved_meal_<nameHash>` — a separate
        // restore-duplication drift surfaced by the f7e3a1 B-pass, tracked as a
        // follow-up; the cloud (user_id,name) key dedups regardless.)
        //
        // Null/empty name guard — (user_id, name) is the arbiter, so a blank name
        // would be an invalid key AND would merge distinct nameless meals. Skip +
        // telemetry, mirroring the nutrition_logs null-natural-key guard above.
        final savedName = (meal['name'] as String?)?.trim();
        if (savedName == null || savedName.isEmpty) {
          unawaited(ErrorTelemetry.logEvent(
            'sync_skipped_null_natural_key',
            message: 'table=user_saved_meals key=$key',
          ));
          continue;
        }
        await _supabase.client.from('user_saved_meals').upsert({
          // `id` deliberately OMITTED — never rewrite the PK on conflict.
          'user_id': userId,
          'name': savedName,
          'items': meal['items'],
          'total_calories': meal['total_calories'],
          'total_protein': meal['total_protein'],
          'times_used': meal['times_used'] ?? 0,
          'created_at': meal['created_at'] ?? DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,name');
        // E.14.A · audit-2026-05-16 — success-path emission. Lets the
        // next audit distinguish "user has zero saved meals" from
        // "_syncSavedMeals silently throws on every run".
        unawaited(ErrorTelemetry.logEvent('upsert_user_saved_meals_success',
            message: 'name=${meal['name']}'));
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

  // ── Pull helpers ────────────────────────────────────────────

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

        // Extract items from joined nutrition_log_items, in stable meal-position
        // order (diagnose f7e3a1): the cloud arbiter is (log_id, item_index), so
        // sorting restored items by item_index makes per-item order deterministic
        // and renders any one-time backfill created_at-tie swap invisible
        // (content returns in its original emit position).
        final itemRows = (map['nutrition_log_items'] as List? ?? []).toList()
          ..sort((a, b) => (((a as Map)['item_index'] as num?) ?? 0)
              .compareTo(((b as Map)['item_index'] as num?) ?? 0));
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
        final localKey = SyncService._nlogKeyForRestore(
          dateStr: dateForKey,
          mealType: mealType,
          items: (map['items'] as List?) ?? const [],
        );
        map['id'] = localKey;
        map['log_key'] = localKey;
        // Local-wins / additive restore (slow-boot guard 4e8b1d): never
        // overwrite a local meal the user just logged during the background
        // restore (it may not have synced yet). closes-diagnose: e4a8b1.
        if (_hive.nutritionBox.get(localKey) == null) {
          await _hive.nutritionBox.put(localKey, map);
        }
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
        // b8d5c2 — derive the local key by CALLING the canonical writer helper
        // (single source of truth → no writer/restore drift). Empty-name rows
        // (degenerate) keep the id-hash fallback.
        final rawName = (map['name'] as String?) ?? '';
        final hiveKey = rawName.trim().isEmpty
            ? 'saved_meal_${id.hashCode.toUnsigned(32).toRadixString(16)}'
            : NutritionWriteService.savedMealKey(rawName);

        // Local-wins / additive restore (slow-boot guard 4e8b1d): keep the
        // local saved meal (identity = user+name) rather than overwriting it
        // with the cloud copy while the background restore runs.
        if (_hive.nutritionBox.get(hiveKey) != null) continue;
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

  // ── SyncDomain public forwarders for nutrition helpers (A6 migration) ──
  // See lib/core/services/sync_flags.dart for the per-domain flag gate.

  static const String _kSyncDomainRestoreSinceNutrition = '2020-01-01T00:00:00Z';

  Future<void> pushNutritionLogsForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _syncNutritionLogs(userId);
  }

  Future<void> restoreNutritionLogsForSyncDomain({String? since}) async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _restoreNutritionLogs(userId, since ?? _kSyncDomainRestoreSinceNutrition);
  }

  Future<void> pushWaterLogsForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _syncWaterLogs(userId);
  }

  Future<void> restoreWaterLogsForSyncDomain({String? since}) async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _restoreWaterLogs(userId, since ?? _kSyncDomainRestoreSinceNutrition);
  }

  Future<void> pushSavedMealsForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _syncSavedMeals(userId);
  }

  Future<void> restoreSavedMealsForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _restoreSavedMeals(userId);
  }
}
