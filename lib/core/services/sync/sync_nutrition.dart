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
        // Now we explicitly project the schema-matching columns and
        // coerce the id to a deterministic v5 UUID via _deterministicId.
        // NutritionRepository.syncLogToSupabase (the hot-path writer)
        // uses the same namespace so immediate writes + this replay
        // collapse to the same row.
        final logCloudId = SyncService._deterministicId(key);
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
            final itemCloudId = SyncService._deterministicId('${key}_item_$i');
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
        // F4 · Test #9 — coerce id from raw Hive key
        // 'saved_meal_<hash>' to deterministic v5 UUID. Same failure class
        // as _syncScheduledWorkouts.template_id (F3); same fix pattern as
        // _syncWorkoutTemplates (since 2026-04-18).
        final hiveId = (meal['id'] as String?) ?? key.toString();
        await _supabase.client.from('user_saved_meals').upsert({
          'id': SyncService._deterministicId(hiveId),
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
        final localKey = SyncService._nlogKeyForRestore(
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
}
