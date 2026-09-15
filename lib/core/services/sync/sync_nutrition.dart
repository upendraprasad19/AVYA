part of '../sync_service.dart';

/// audit-fixwave 2026-07-02 / F5 (NUT-02) — pure grouping: coalesce same-slot
/// (date, meal_type) nutrition logs into ONE payload (union items + summed
/// totals + earliest created_at). One entry per slot so the natural-key upsert
/// (user_id,date,meal_type) never drops a second same-slot meal (the NUT-02
/// data-loss). Logs with a null/empty natural key pass through unmerged (the
/// sync loop's null-key telemetry guard handles them). Pure (no Hive) so the
/// merge contract is unit-testable directly.
List<Map<String, dynamic>> mergeNutritionLogsBySlot(
    List<Map<String, dynamic>> logs) {
  final bySlot = <String, Map<String, dynamic>>{};
  for (final log in logs) {
    final date = (log['date'] as String?)?.trim();
    final meal = (log['meal_type'] as String?)?.trim();
    if (date == null || date.isEmpty || meal == null || meal.isEmpty) {
      bySlot[' raw ${bySlot.length}'] = log; // pass through unmerged
      continue;
    }
    final slot = '$date $meal';
    final acc = bySlot[slot];
    if (acc == null) {
      bySlot[slot] = {
        'date': date,
        'meal_type': meal,
        'total_calories': (log['total_calories'] as num?) ?? 0,
        'total_protein': (log['total_protein'] as num?) ?? 0,
        'total_carbs': (log['total_carbs'] as num?) ?? 0,
        'total_fat': (log['total_fat'] as num?) ?? 0,
        'total_fiber': (log['total_fiber'] as num?) ?? 0,
        'items': [...((log['items'] as List?) ?? const [])],
        if (log['created_at'] != null) 'created_at': log['created_at'],
      };
    } else {
      acc['total_calories'] = (acc['total_calories'] as num) +
          ((log['total_calories'] as num?) ?? 0);
      acc['total_protein'] = (acc['total_protein'] as num) +
          ((log['total_protein'] as num?) ?? 0);
      acc['total_carbs'] =
          (acc['total_carbs'] as num) + ((log['total_carbs'] as num?) ?? 0);
      acc['total_fat'] =
          (acc['total_fat'] as num) + ((log['total_fat'] as num?) ?? 0);
      acc['total_fiber'] =
          (acc['total_fiber'] as num) + ((log['total_fiber'] as num?) ?? 0);
      (acc['items'] as List).addAll((log['items'] as List?) ?? const []);
      final accCreated = acc['created_at'] as String?;
      final logCreated = log['created_at'] as String?;
      if (logCreated != null &&
          (accCreated == null || logCreated.compareTo(accCreated) < 0)) {
        acc['created_at'] = logCreated;
      }
    }
  }
  return bySlot.values.toList();
}

/// audit-fixwave B-pass — signature of a nutrition item for the restore union:
/// `<lowercased-trimmed-name>|<qty.toFixed(1)>`. Empty when unnameable.
String nutritionItemSig(dynamic it) {
  if (it is! Map) return '';
  final n =
      (it['name'] ?? it['food_name'] ?? '').toString().toLowerCase().trim();
  final q = it['quantity_g'] ?? it['serving_g'];
  final qd = (q is num) ? q.toDouble() : 0.0;
  return n.isEmpty ? '' : '$n|${qd.toStringAsFixed(1)}';
}

/// audit-fixwave B-pass — true when [localItems] already holds at least as many
/// of EVERY cloud item (by signature MULTISET count) — i.e. local is a superset,
/// so the restore can skip (local-wins). Counting, not set-membership, so a
/// genuine duplicate serving that only cloud has is not falsely "already local".
bool nutritionLocalSlotIsSuperset(List<dynamic> localItems, List<dynamic> cloudItems) {
  if (cloudItems.isEmpty) return false;
  final lc = <String, int>{};
  for (final it in localItems) {
    final s = nutritionItemSig(it);
    if (s.isNotEmpty) lc[s] = (lc[s] ?? 0) + 1;
  }
  final cc = <String, int>{};
  for (final it in cloudItems) {
    final s = nutritionItemSig(it);
    if (s.isNotEmpty) cc[s] = (cc[s] ?? 0) + 1;
  }
  return cc.entries.every((e) => (lc[e.key] ?? 0) >= e.value);
}

/// audit-fixwave B-pass — MULTISET union of local + cloud items: for each
/// signature keep max(localCount, cloudCount) item objects. This PRESERVES a
/// genuine duplicate serving (a food logged twice) while NOT double-counting an
/// already-synced item that appears in both local and cloud. (The earlier
/// set-dedup silently dropped the second identical serving — a Hermes P1.)
List<dynamic> nutritionSlotUnion(List<dynamic> localItems, List<dynamic> cloudItems) {
  final localBySig = <String, List<dynamic>>{};
  for (final it in localItems) {
    final s = nutritionItemSig(it);
    if (s.isNotEmpty) (localBySig[s] ??= <dynamic>[]).add(it);
  }
  final cloudBySig = <String, List<dynamic>>{};
  for (final it in cloudItems) {
    final s = nutritionItemSig(it);
    if (s.isNotEmpty) (cloudBySig[s] ??= <dynamic>[]).add(it);
  }
  final sigs = <String>{...localBySig.keys, ...cloudBySig.keys}.toList()..sort();
  final out = <dynamic>[];
  for (final s in sigs) {
    final local = localBySig[s] ?? const [];
    final cloud = cloudBySig[s] ?? const [];
    out.addAll(local);
    if (cloud.length > local.length) {
      out.addAll(cloud.sublist(local.length)); // the extra cloud servings only
    }
  }
  return out;
}

/// Sync + restore for nutrition domain: nutrition_logs (+ per-item items),
/// water_logs, user_saved_meals.
///
/// `syncNutritionData()` is the SoT fan-out entry point pinned by
/// `test/contracts/sync_fanout_contract_test.dart` — its body MUST
/// continue to call `_syncNutritionLogs`, `_syncWaterLogs`, and
/// `_syncSavedMeals` (docs/architecture/sync.md).
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
    // audit-fixwave 2026-07-02 / F5 (NUT-02) — merge same-slot logs BEFORE the
    // natural-key upsert. The cloud arbiter is (user_id,date,meal_type), so two
    // local `nlog_<date>_<meal>_<hash>` logs for the SAME slot+day would collapse
    // to one cloud row (the second overwrites the first → the first meal is lost
    // on reinstall/restore — the NUT-02 data-loss). Grouping all same-slot logs
    // into ONE payload (union items + summed totals) makes the upsert carry BOTH
    // meals' items, so nothing is dropped. Kill-switch
    // `disable_nutrition_slot_merge` reverts to the legacy per-key push.
    final mergeEnabled =
        _hive.configBox.get('disable_nutrition_slot_merge') != true;
    final logsToSync = mergeEnabled
        ? _nutritionLogsMergedBySlot()
        : _nutritionLogsRaw();
    for (final log in logsToSync) {
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
                'table=nutrition_logs date_null=${nlogDate == null || nlogDate.isEmpty} meal_type_null=${nlogMeal == null || nlogMeal.isEmpty}',
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
        // closes-diagnose e5c2d1, CLASS 1 — the guard sits AT THE SINK, one
        // statement before the write, NOT at function entry. Per
        // feedback_pause_flag_guard_the_sink: an in-flight call that is
        // already past an entry check still reaches the sink, and every await
        // between entry and here is a window the account swap can land in.
        //
        // On 2026-08-06 this produced 22 x 42501 "new row violates row-level
        // security policy for table nutrition_logs" in ~9 seconds: `userId`
        // was captured at entry and the session had since advanced to another
        // user, so PostgREST carried the NEW token while the payload carried
        // the OLD id.
        //
        // ⚠ RLS rejecting those writes was the LAST line of defence, not the
        // intended one. The SAME race with the opposite interleaving — a
        // captured id equal to the NEW user while the ROWS came from the
        // previous user's Hive box — satisfies auth.uid() = user_id and would
        // be WRITTEN, and Postgres cannot tell that from a legitimate write.
        // This client-side check is what makes the direction not matter.
        if (ownerChangedSince(userId)) return;

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
              // e5c2d1 CLASS 1 — sink guard. The parent upsert cleared its own
              // check, but every await since is a fresh swap window, and these
              // children carry the same user's payload.
              //
              // Closure R2-N9 asked whether returning here abandons a
              // half-written parent and skips the tail vacuum below. It does —
              // and that is the correct trade, because it SELF-HEALS. Verified,
              // not assumed: `_syncNutritionLogs` has no fingerprint/skip-
              // unchanged optimisation (unlike `_syncScheduledWorkouts`), so it
              // re-walks EVERY nutrition Hive row on every pass. The next pass
              // under the right owner re-upserts the parent on its natural key,
              // re-writes the items and re-runs the vacuum, fully repairing the
              // row. The alternative — finishing the unit under a session that
              // now belongs to someone else — is not repairable.
              if (ownerChangedSince(userId)) return;
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
        // audit-fixwave B-pass — item tail-vacuum. After upserting the (possibly
        // merged) slot's items at indices 0..N-1, delete any orphaned tail rows
        // (item_index >= N) left when the slot SHRANK — e.g. a same-slot meal was
        // deleted so the merged union has fewer items. Without this the deleted
        // meal's items resurrect on restore + the parent totals diverge from the
        // item list (Hermes P1). Mirrors the template_exercises tail-vacuum.
        if (items is List) {
          try {
            // e5c2d1 CLASS 1 — sink guard. A DELETE under the wrong session is
            // the most destructive shape this race can take, so it is guarded
            // like the writes rather than treated as cleanup.
            if (ownerChangedSince(userId)) return;
            await _supabase.client
                .from('nutrition_log_items')
                .delete()
                .eq('log_id', logCloudId)
                .gte('item_index', items.length);
          } catch (vErr, vSt) {
            debugPrint('[SyncService._syncNutritionLogs] item vacuum: $vErr');
            unawaited(ErrorTelemetry.recordNonFatal(vErr, vSt,
                reason: 'sync_service_nlog_item_vacuum'));
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

  /// audit-fixwave / F5 — the raw per-key nlog list (legacy push path, used
  /// when slot-merge is disabled).
  List<Map<String, dynamic>> _nutritionLogsRaw() {
    final nutritionBox = _hive.nutritionBox;
    final out = <Map<String, dynamic>>[];
    for (final key in nutritionBox.keys) {
      if (key is! String || !key.startsWith('nlog_')) continue;
      final raw = nutritionBox.get(key);
      if (raw == null) continue;
      out.add(Map<String, dynamic>.from(raw as Map));
    }
    return out;
  }

  /// audit-fixwave / F5 (NUT-02) — coalesce all same-slot (date, meal_type)
  /// nlog logs into ONE payload: union of items + summed totals + earliest
  /// created_at. One entry per slot so the (user_id,date,meal_type) upsert never
  /// drops a second same-slot meal. Logs with a null/empty natural key are
  /// passed through unmerged so the loop's existing null-key telemetry guard
  /// still fires.
  List<Map<String, dynamic>> _nutritionLogsMergedBySlot() =>
      mergeNutritionLogsBySlot(_nutritionLogsRaw());

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
        // e5c2d1 CLASS 1 — sink guard. _syncWaterLogs is a SIBLING of
        // _syncNutritionLogs under Future.wait, so a `return` there does not
        // stop this loop. Round-1 review caught exactly that: one guard in one
        // sibling left the other two running on under the swapped session.
        if (ownerChangedSince(userId)) return;
        await _supabase.client.from('water_logs').upsert({
          'user_id': userId,
          'date': date,
          'total_ml': raw,
          // audit-fixwave 2026-07-02 / F18 — populate `glasses` (derived from
          // total_ml at the 250 ml glass size) so the column is not a
          // misleading stale 0. total_ml stays the hydration SoT.
          'glasses': (raw / 250).round(),
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
        // e5c2d1 CLASS 1 — sink guard. Third sibling under the same
        // Future.wait; guarded independently for the same reason as water.
        if (ownerChangedSince(userId)) return;
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

  /// [preFetched] (C3 single-call): injected `nutrition_logs` rows, each row
  /// carrying its nested `nutrition_log_items[]` (the verbatim PostgREST embed
  /// the parser below reads). Legacy callers omit it → paginated network read.
  /// Plan `restore-single-call-c3.md` §4 (H-1 embed nesting preserved).
  Future<void> _restoreNutritionLogs(String userId, String since,
      {Object? preFetched = _kNoInject}) async {
    try {
      // Join with nutrition_log_items to restore individual food items.
      // Paginated fetch (1000 per page, max 50,000).
      final List rows;
      if (identical(preFetched, _kNoInject)) {
        final fetched = <Map<String, dynamic>>[];
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
            fetched.add(Map<String, dynamic>.from(r as Map));
          }
          if (page.length < pageSize || fetched.length >= 50000) break;
          offset += pageSize;
        }
        rows = fetched;
      } else {
        rows = preFetched as List? ?? const [];
      }

      // audit-fixwave 2026-07-02 / F5 (NUT-02) + B-pass — 3-WAY restore merge.
      // Cloud holds ONE merged row per (date,meal). Precompute each local slot's
      // item signatures + keys so, per cloud row, we can:
      //   - SKIP when the local slot already contains every cloud item (local-
      //     wins; local has >= cloud, including any unsynced local items), OR
      //   - UNION local+cloud items (dedup), delete the local slot's old keys,
      //     and write ONE merged row — restoring cloud items the local slot
      //     LACKED (no silent loss) without leaving stale rows that would
      //     re-duplicate on the next sync. The pre-B-pass per-slot-occupancy
      //     skip dropped cloud items whenever the local slot was partial
      //     (Hermes P1 data-loss).
      final mergeEnabled =
          _hive.configBox.get('disable_nutrition_slot_merge') != true;
      // Precompute each local slot's keys + ALL its items (with multiplicity —
      // a food logged twice stays twice). The multiset union below preserves
      // genuine duplicate servings (Hermes P1 fix).
      final localSlotKeys = <String, List<String>>{};
      final localSlotItems = <String, List<dynamic>>{};
      if (mergeEnabled) {
        for (final k in _hive.nutritionBox.keys) {
          if (k is! String || !k.startsWith('nlog_')) continue;
          final v = _hive.nutritionBox.get(k);
          if (v is! Map) continue;
          final d = (v['date'] as String?)?.trim();
          final m = (v['meal_type'] as String?)?.trim();
          if (d == null || d.isEmpty || m == null || m.isEmpty) continue;
          final slot = '$d $m';
          (localSlotKeys[slot] ??= <String>[]).add(k);
          (localSlotItems[slot] ??= <dynamic>[])
              .addAll((v['items'] as List? ?? const []));
        }
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
              'fiber': m['fiber'], // audit-fixwave B-pass — was dropped on restore
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
        // Local-wins / additive restore (slow-boot guard 4e8b1d) + audit-fixwave
        // B-pass 3-way merge (see the precompute above). closes-diagnose: e4a8b1.
        if (mergeEnabled) {
          final slotId = '$dateForKey $mealType';
          final cloudItems = (map['items'] as List?) ?? const [];
          final localItems = localSlotItems[slotId] ?? const [];
          // Local-wins: local already holds >= every cloud item (multiset).
          if (nutritionLocalSlotIsSuperset(localItems, cloudItems)) continue;
          // MULTISET union — keeps genuine duplicate servings, no over-count.
          final unionItems = nutritionSlotUnion(localItems, cloudItems);
          if (unionItems.isEmpty) continue; // defensive
          num sumF(String f) => unionItems.fold<num>(
              0, (a, it) => a + (((it as Map)[f] as num?) ?? 0));
          final mergedKey = SyncService._nlogKeyForRestore(
              dateStr: dateForKey, mealType: mealType, items: unionItems);
          final mergedRow = <String, dynamic>{
            ...map,
            'id': mergedKey,
            'log_key': mergedKey,
            'items': unionItems,
            'total_calories': sumF('calories').round(),
            'total_protein': sumF('protein').round(),
            'total_carbs': sumF('carbs').round(),
            'total_fat': sumF('fat').round(),
            'total_fiber': sumF('fiber').round(),
          };
          // Replace the local slot's old keys with the single merged row — no
          // loss (union includes any unsynced local items), no duplicate rows.
          for (final oldKey in (localSlotKeys[slotId] ?? const <String>[])) {
            if (oldKey != mergedKey) await _hive.nutritionBox.delete(oldKey);
          }
          // FC6 / Hermes P2-FC6-1 — bound absurd calorie/macro values on the
          // restore path too (mutates mergedRow in place; null-guards missing
          // keys). mergedRow is already Map<String, dynamic>.
          NutritionWriteService.clampRestoredNutritionRow(mergedRow);
          await _hive.nutritionBox.put(mergedKey, mergedRow);
          // Update intra-pass state (cloud has one row per slot, but be safe).
          localSlotKeys[slotId] = [mergedKey];
          localSlotItems[slotId] = unionItems;
        } else {
          // Legacy per-key local-wins (merge disabled).
          if (_hive.nutritionBox.get(localKey) == null) {
            // FC6 / Hermes P2-FC6-1 — clamp absurd calorie/macro values on the
            // restore path here too. `map` is already Map<String, dynamic>.
            NutritionWriteService.clampRestoredNutritionRow(map);
            await _hive.nutritionBox.put(localKey, map);
          }
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

  /// [preFetched] (C3 single-call): injected `water_logs` rows; legacy callers
  /// omit it → paginated network read. Plan §4.
  Future<void> _restoreWaterLogs(String userId, String since,
      {Object? preFetched = _kNoInject}) async {
    try {
      final rows = identical(preFetched, _kNoInject)
          ? await _fetchAllRows(
              'water_logs', userId,
              dateColumn: 'date', since: since.substring(0, 10), orderBy: 'date',
            )
          : (preFetched as List? ?? const []);

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
  ///
  /// [preFetched] (C3 single-call): injected `user_saved_meals` rows; legacy
  /// callers omit it → network read. Plan §4.
  Future<void> _restoreSavedMeals(String userId,
      {Object? preFetched = _kNoInject}) async {
    try {
      final rows = identical(preFetched, _kNoInject)
          ? await _supabase.client
              .from('user_saved_meals')
              .select()
              .eq('user_id', userId)
              .limit(500)
          : (preFetched as List? ?? const []);

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
