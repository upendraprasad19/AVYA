part of '../sync_service.dart';

/// Community sync — user-contributed custom exercises and foods.
///
/// Sync direction: local custom items pushed to cloud immediately on
/// create (community contribution); approved community items pulled
/// periodically into local exerciseBox / foodBox so the seeded library
/// grows over time.
///
/// Static `_customEntityId` namespace helper stays on the SyncService
/// class — extension methods reference it via `SyncService._customEntityId(...)`.
extension SyncServiceCommunity on SyncService {
  /// One-shot backfill: iterate customBox, (a) assign deterministic ids to
  /// entries that have none (F8/F22 pre-existing entries), and (b) repair
  /// custom exercises with null/missing `logging_type` (F12). Fire-and-
  /// forget from `checkAndSync()`.
  Future<void> _backfillCustomEntityIds() async {
    try {
      // APK Test #12.7 — open the session before iterating customBox.
      final userId = await _ensureSessionOpen();
      if (userId == null) return;
      final box = _hive.customBox;
      var idRepaired = 0;
      var loggingTypeRepaired = 0;
      for (final key in box.keys.toList()) {
        final raw = box.get(key);
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final name = map['name'] as String?;
        if (name == null || name.isEmpty) continue;
        final type = map['type'] as String?;
        final entityType = type == 'food' ? 'food' : 'exercise';

        var mutated = false;
        // F8/F22 — stable id
        final existingId = map['id'] as String?;
        if (existingId == null || existingId.isEmpty) {
          map['id'] = SyncService._customEntityId(userId, entityType, name);
          mutated = true;
          idRepaired++;
        }
        // F12 — logging_type repair (exercises only)
        if (entityType == 'exercise') {
          final lt = map['logging_type'] as String?;
          if (lt == null || lt.isEmpty) {
            final nLower = name.toLowerCase();
            String inferred;
            if (nLower.contains('hold') || nLower.contains('plank') ||
                nLower.contains('handstand') || nLower.contains('l-sit')) {
              inferred = 'timed';
            } else if (nLower.contains('run') || nLower.contains('row') ||
                nLower.contains('bike') || nLower.contains('walk')) {
              inferred = 'cardio';
            } else {
              final equipment = map['equipment_needed'];
              final isBodyweight = equipment is List && equipment.isEmpty;
              inferred = isBodyweight ? 'bodyweight_reps' : 'weight_reps';
            }
            map['logging_type'] = inferred;
            mutated = true;
            loggingTypeRepaired++;
          }
        }

        if (mutated) {
          await box.put(key, map);
        }
      }
      if (idRepaired > 0 || loggingTypeRepaired > 0) {
        debugPrint('[SyncService] backfilled ids=$idRepaired '
            'loggingType=$loggingTypeRepaired');
        unawaited(_syncCustomItems());
      }
    } catch (e, st) {
      debugPrint('[SyncService._backfillCustomEntityIds] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_if'));
      try {
        await _reportSyncFailure(opType: 'backfill_custom_entity_ids', error: e);
      } catch (_) {}
    }
  }

  /// Public wrapper so immediate-save call sites (the create-custom-exercise
  /// sheet, the create-custom-food sheet) can push to Supabase without
  /// waiting for the next weekly sync. Catches its own errors.
  Future<void> syncCustomItemsNow() => _syncCustomItems();

  /// Pushes user-created custom foods and exercises to Supabase
  /// for community contribution.
  ///
  /// Historical bug fixed 2026-04-18: the writer
  /// (`create_custom_exercise_sheet._save`, line 85) stores each exercise
  /// at its own Hive key `custom_exercise_<ms>`, but this function used to
  /// only look at a list key `customBox.get('custom_exercises')` — a
  /// single aggregate List that nobody ever wrote to. Result: custom
  /// exercises never synced. Observed 2026-04-18 on icanbefitter@gmail.com
  /// after creating "L Sit" — user_custom_exercises stayed at 0 rows.
  ///
  /// New behavior: iterate `customBox.keys` by prefix. Falls back to the
  /// legacy list-key path for any old-shape boxes still in the wild.
  Future<void> _syncCustomItems() async {
    var exerciseSuccessCount = 0;
    var foodSuccessCount = 0;
    try {
      final userId = _supabase.currentUser?.id;
      if (userId == null) return;

      final customBox = _hive.customBox;

      // ── Primary path: per-key entries ──
      for (final key in customBox.keys) {
        if (key is! String) continue;
        final raw = customBox.get(key);
        if (raw is! Map) continue;

        if (key.startsWith('custom_exercise_')) {
          final payload = _projectCustomExercise(raw, userId);
          if (kDebugMode) {
            debugPrint(
              '[SyncService] upsert user_custom_exercises '
              'name=${payload['name']} user=$userId id=${payload['id']}',
            );
          }
          try {
            await _supabase.client
                .from('user_custom_exercises')
                .upsert(payload, onConflict: 'id');
            exerciseSuccessCount++;
          } catch (e, st) {
            debugPrint(
              '[SyncService._syncCustomItems] exercise '
              '"${payload['name']}" key=$key: $e',
            );
            // audit-2026-05-11 H-42 — telemetry pair.
            unawaited(ErrorTelemetry.recordNonFatal(e, st,
                reason: 'sync_service_if_8'));
            try {
              await _reportSyncFailure(opType: 'upsert_custom_exercise', error: e);
            } catch (_) {}
          }
        } else if (key.startsWith('custom_food_')) {
          final payload = _projectCustomFood(raw, userId);
          if (kDebugMode) {
            debugPrint(
              '[SyncService] upsert user_custom_foods '
              'name=${payload['name']} user=$userId id=${payload['id']}',
            );
          }
          try {
            await _supabase.client
                .from('user_custom_foods')
                .upsert(payload, onConflict: 'id');
            foodSuccessCount++;
          } catch (e, st) {
            debugPrint(
              '[SyncService._syncCustomItems] food '
              '"${payload['name']}" key=$key: $e',
            );
            // audit-2026-05-11 H-42 — telemetry pair.
            unawaited(ErrorTelemetry.recordNonFatal(e, st,
                reason: 'sync_service_if_9'));
            try {
              await _reportSyncFailure(opType: 'upsert_custom_food', error: e);
            } catch (_) {}
          }
        }
      }

      // ── Legacy path: aggregate list keys ──
      // Kept for back-compat with devices that still have the old shape
      // (never-shipped but safe guard).
      final legacyExercises = customBox.get('custom_exercises');
      if (legacyExercises is List) {
        for (final item in legacyExercises.cast<Map>()) {
          try {
            await _supabase.client
                .from('user_custom_exercises')
                .upsert(_projectCustomExercise(item, userId), onConflict: 'id');
          } catch (e, st) {
            debugPrint('[SyncService._syncCustomItems] legacy exercise: $e');
            // audit-2026-05-11 H-42 — telemetry pair.
            unawaited(ErrorTelemetry.recordNonFatal(e, st,
                reason: 'sync_service_if_10'));
            try {
              await _reportSyncFailure(opType: 'upsert_custom_exercise_legacy', error: e);
            } catch (_) {}
          }
        }
      }
      final legacyFoods = customBox.get('custom_foods');
      if (legacyFoods is List) {
        for (final item in legacyFoods.cast<Map>()) {
          try {
            await _supabase.client
                .from('user_custom_foods')
                .upsert(_projectCustomFood(item, userId), onConflict: 'id');
          } catch (e, st) {
            debugPrint('[SyncService._syncCustomItems] legacy food: $e');
            // audit-2026-05-11 H-42 — telemetry pair.
            unawaited(ErrorTelemetry.recordNonFatal(e, st,
                reason: 'sync_service_if_11'));
            try {
              await _reportSyncFailure(opType: 'upsert_custom_food_legacy', error: e);
            } catch (_) {}
          }
        }
      }

      await _setTimestamp(SyncService._lastCustomSyncKey);
      // E.14.A · audit-2026-05-16 — success-path emission. One event
      // per batch with per-table counts so the audit can distinguish
      // "user has zero custom items" from "this loop silently throws".
      if (exerciseSuccessCount > 0 || foodSuccessCount > 0) {
        unawaited(ErrorTelemetry.logEvent('upsert_custom_items_success',
            message:
                'exercises=$exerciseSuccessCount foods=$foodSuccessCount'));
      }
    } catch (e, st) {
      debugPrint('[SyncService._syncCustomItems] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_catch_8'));
      try {
        await _reportSyncFailure(opType: 'sync_custom_items', error: e);
      } catch (_) {}
    }
  }

  /// Projects a Hive custom-exercise map to ONLY the columns that exist
  /// on the `user_custom_exercises` Supabase table. The Hive map carries
  /// extras (`is_custom`, `type`) that PostgREST 400-rejects; before
  /// 2026-04-18 the sync spread them verbatim into the upsert and every
  /// call silently failed, which is why user_custom_exercises stayed at
  /// 0 rows even after the list-vs-per-key wiring fix.
  ///
  /// Schema reminder (DB truth, verified via information_schema):
  ///   id uuid NOT NULL, user_id uuid NOT NULL, name text NOT NULL,
  ///   logging_type text NOT NULL, category text, primary_muscles
  ///   text[], equipment_needed text[], notes text, default_sets int,
  ///   default_reps text, default_rest_secs int, default_duration_secs
  ///   int, submitted_to_library bool, approved_for_library bool,
  ///   times_used int, created_at timestamptz.
  Map<String, dynamic> _projectCustomExercise(
    Map source,
    String userId,
  ) {
    final src = Map<String, dynamic>.from(source);
    final defaultDur = src['default_duration_seconds'] ?? src['default_duration_secs'];
    return <String, dynamic>{
      'id': src['id'],
      'user_id': userId,
      if (src['name'] != null) 'name': src['name'],
      if (src['logging_type'] != null) 'logging_type': src['logging_type'],
      if (src['category'] != null) 'category': src['category'],
      if (src['primary_muscles'] is List)
        'primary_muscles': (src['primary_muscles'] as List).cast<String>(),
      if (src['equipment_needed'] is List)
        'equipment_needed': (src['equipment_needed'] as List).cast<String>(),
      if (src['notes'] != null) 'notes': src['notes'],
      if (src['default_sets'] != null) 'default_sets': src['default_sets'],
      if (src['default_reps'] != null)
        'default_reps': src['default_reps'].toString(),
      if (src['default_rest_secs'] != null)
        'default_rest_secs': src['default_rest_secs'],
      if (defaultDur != null) 'default_duration_secs': defaultDur,
      if (src['submitted_to_library'] != null)
        'submitted_to_library': src['submitted_to_library'],
      if (src['approved_for_library'] != null)
        'approved_for_library': src['approved_for_library'],
      if (src['times_used'] != null) 'times_used': src['times_used'],
      if (src['created_at'] != null) 'created_at': src['created_at'],
    };
  }

  /// Projects a Hive custom-food map to the `user_custom_foods` schema:
  ///   id uuid NOT NULL, user_id uuid NOT NULL, name text NOT NULL,
  ///   calories_per_100g numeric, protein_per_100g numeric,
  ///   carbs_per_100g numeric, fat_per_100g numeric, fiber_per_100g
  ///   numeric, standard_serving_desc text, standard_serving_g numeric,
  ///   calories_std numeric, protein_std numeric, carbs_std numeric,
  ///   fat_std numeric, times_logged int, submitted_to_db bool,
  ///   approved bool, created_at timestamptz.
  Map<String, dynamic> _projectCustomFood(
    Map source,
    String userId,
  ) {
    final src = Map<String, dynamic>.from(source);
    return <String, dynamic>{
      'id': src['id'],
      'user_id': userId,
      if (src['name'] != null) 'name': src['name'],
      if (src['calories_per_100g'] != null)
        'calories_per_100g': src['calories_per_100g'],
      if (src['protein_per_100g'] != null)
        'protein_per_100g': src['protein_per_100g'],
      if (src['carbs_per_100g'] != null)
        'carbs_per_100g': src['carbs_per_100g'],
      if (src['fat_per_100g'] != null) 'fat_per_100g': src['fat_per_100g'],
      if (src['fiber_per_100g'] != null)
        'fiber_per_100g': src['fiber_per_100g'],
      if (src['standard_serving_desc'] != null)
        'standard_serving_desc': src['standard_serving_desc'],
      if (src['standard_serving_g'] != null)
        'standard_serving_g': src['standard_serving_g'],
      if (src['calories_std'] != null) 'calories_std': src['calories_std'],
      if (src['protein_std'] != null) 'protein_std': src['protein_std'],
      if (src['carbs_std'] != null) 'carbs_std': src['carbs_std'],
      if (src['fat_std'] != null) 'fat_std': src['fat_std'],
      if (src['times_logged'] != null) 'times_logged': src['times_logged'],
      if (src['submitted_to_db'] != null)
        'submitted_to_db': src['submitted_to_db'],
      if (src['approved'] != null) 'approved': src['approved'],
      if (src['created_at'] != null) 'created_at': src['created_at'],
    };
  }

  /// [preFetched] (C3 single-call): injected `user_custom_exercises` rows;
  /// legacy callers omit it → network read. Plan §4.
  Future<void> _restoreCustomExercises(String userId,
      {Object? preFetched = _kNoInject}) async {
    try {
      final rows = identical(preFetched, _kNoInject)
          ? await _supabase.client
              .from('user_custom_exercises')
              .select()
              .eq('user_id', userId)
          : (preFetched as List? ?? const []);

      if (rows.isEmpty) return;

      final items = rows
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();

      // H-13 (audit-2026-05-11) — write PER-KEY entries so the
      // writer (`_syncCustomItems`) + every UI reader
      // (`your_foods_section`, `train_screen`, `workout_schedule_service`)
      // can see them. Pre-fix this wrote to the legacy
      // `custom_exercises` LIST key, which no current consumer reads
      // → restored items vanished from getCustomExercises() and
      // never re-synced to cloud (since _syncCustomItems scans
      // `custom_exercise_*` per-key only).
      //
      // Local key uses cloud row's `id` (deterministic v5 UUID) so
      // repeated restores on the same device don't duplicate rows.
      // Dedup by name (case-insensitive) against existing per-key
      // entries already in customBox.
      final customBox = _hive.customBox;
      final existingNames = <String>{};
      for (final k in customBox.keys) {
        if (k is! String || !k.startsWith('custom_exercise_')) continue;
        final v = customBox.get(k);
        if (v is Map) {
          final n = (v['name'] as String? ?? '').toLowerCase().trim();
          if (n.isNotEmpty) existingNames.add(n);
        }
      }

      for (final item in items) {
        final name = (item['name'] as String? ?? '').toLowerCase().trim();
        if (name.isEmpty) continue;
        if (existingNames.contains(name)) continue;
        final id = (item['id'] as String?) ??
            'restore_${DateTime.now().microsecondsSinceEpoch}';
        // APK Test #15.4 / A5 — stamp `type: 'exercise'` so legacy
        // readers that filter by `ex['type'] == 'exercise'` see the
        // restored entry. Cloud `user_custom_exercises` has no `type`
        // column; without this every reader except those that grew
        // key-prefix fallback would skip it. Pinned by
        // `test/widgets/swap_sheet_custom_exercises_test.dart`.
        item['type'] = 'exercise';
        await customBox.put('custom_exercise_$id', item);
        existingNames.add(name);
      }
    } catch (e, st) {
      debugPrint('[SyncService._restoreCustomExercises] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_for_15'));
      try {
        await _reportSyncFailure(opType: 'restore_custom_exercises', error: e);
      } catch (_) {}
    }
  }

  /// [preFetched] (C3 single-call): injected `user_custom_foods` rows; legacy
  /// callers omit it → network read. Plan §4.
  Future<void> _restoreCustomFoods(String userId,
      {Object? preFetched = _kNoInject}) async {
    try {
      final rows = identical(preFetched, _kNoInject)
          ? await _supabase.client
              .from('user_custom_foods')
              .select()
              .eq('user_id', userId)
          : (preFetched as List? ?? const []);

      if (rows.isEmpty) return;

      final items = rows
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();

      // H-13 (audit-2026-05-11) — same per-key restore as
      // _restoreCustomExercises above. Local key uses cloud row's
      // `id` so repeated restores don't duplicate.
      final customBox = _hive.customBox;
      final existingNames = <String>{};
      for (final k in customBox.keys) {
        if (k is! String || !k.startsWith('custom_food_')) continue;
        final v = customBox.get(k);
        if (v is Map) {
          final n = (v['name'] as String? ?? '').toLowerCase().trim();
          if (n.isNotEmpty) existingNames.add(n);
        }
      }

      for (final item in items) {
        final name = (item['name'] as String? ?? '').toLowerCase().trim();
        if (name.isEmpty) continue;
        if (existingNames.contains(name)) continue;
        final id = (item['id'] as String?) ??
            'restore_${DateTime.now().microsecondsSinceEpoch}';
        await customBox.put('custom_food_$id', item);
        existingNames.add(name);
      }
    } catch (e, st) {
      debugPrint('[SyncService._restoreCustomFoods] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_for_16'));
      try {
        await _reportSyncFailure(opType: 'restore_custom_foods', error: e);
      } catch (_) {}
    }
  }

  // ── Sync: Community Items (approved by 10+ users) ─────────

  /// Pulls approved community foods/exercises from Supabase into local Hive.
  /// Called on app launch to keep the local database growing.
  Future<void> syncCommunityItems() async {
    // H-14 (audit-2026-05-11) — paginate + apply a hard ceiling.
    // Pre-fix the queries had no `.limit()` or `.range()` so every
    // app launch downloaded the FULL approved community library
    // (potentially thousands of rows) over the user's cellular
    // connection. At 1000 community items a sync would burn ~500KB
    // of bandwidth per launch. Now: 500 rows per page, 10-page
    // ceiling (5000 rows max) for any single sync run.
    const int pageSize = 500;
    const int maxPages = 10;

    try {
      final lastSync = _hive.syncBox.get('last_community_sync');
      final sinceDate = lastSync != null
          ? DateTime.tryParse(lastSync.toString())?.toIso8601String()
          : '2020-01-01T00:00:00Z';
      final since = sinceDate ?? '2020-01-01T00:00:00Z';

      // Pull approved community foods — paginated.
      final foodBox = _hive.foodBox;
      for (int page = 0; page < maxPages; page++) {
        final from = page * pageSize;
        final to = from + pageSize - 1;
        final foods = await _supabase.client
            .from('user_custom_foods')
            .select()
            .eq('approved', true)
            .gte('created_at', since)
            .order('created_at', ascending: true)
            .range(from, to);
        if (foods.isEmpty) break;
        for (final row in foods) {
          final map = Map<String, dynamic>.from(row as Map);
          final id = map['id']?.toString();
          if (id != null && id.isNotEmpty && foodBox.get(id) == null) {
            map['source'] = 'community';
            await foodBox.put(id, map);
          }
        }
        if (foods.length < pageSize) break;
      }

      // Pull approved community exercises — paginated.
      final exerciseBox = _hive.exerciseBox;
      for (int page = 0; page < maxPages; page++) {
        final from = page * pageSize;
        final to = from + pageSize - 1;
        final exercises = await _supabase.client
            .from('user_custom_exercises')
            .select()
            .eq('approved_for_library', true)
            .gte('created_at', since)
            .order('created_at', ascending: true)
            .range(from, to);
        if (exercises.isEmpty) break;
        for (final row in exercises) {
          final map = Map<String, dynamic>.from(row as Map);
          final id = map['id']?.toString();
          if (id != null && id.isNotEmpty && exerciseBox.get(id) == null) {
            map['source'] = 'community';
            // ⑥ slice B2 — normalize equipment_needed to the canonical vocab at
            // this write seam so STORED community rows match the seed (slice A).
            // Kill-switch `disable_community_equipment_normalize` (default ON →
            // normalize; == true → verbatim raw store = prior behavior).
            await exerciseBox.put(
              id,
              EquipmentVocab.normalizedEquipmentRow(
                map,
                enabled: _hive.configBox
                        .get('disable_community_equipment_normalize') !=
                    true,
              ),
            );
          }
        }
        if (exercises.length < pageSize) break;
      }

      await _hive.syncBox.put('last_community_sync', DateTime.now().toIso8601String());
    } catch (e, st) {
      debugPrint('[SyncService.syncCommunityItems] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_for_22'));
      try {
        await _reportSyncFailure(opType: 'sync_community_items', error: e);
      } catch (_) {}
    }
  }

  // ── SyncDomain public forwarders for community helpers (A6 migration) ──

  Future<void> pushCustomItemsForSyncDomain() async {
    await _syncCustomItems();
  }

  Future<void> restoreCustomItemsForSyncDomain() async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return;
    await _restoreCustomExercises(userId);
    await _restoreCustomFoods(userId);
  }
}
