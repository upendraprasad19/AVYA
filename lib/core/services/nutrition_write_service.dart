import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';
import '../utils/ist_date.dart';
import '../../features/home/providers/home_provider.dart'
    show aiInsightProvider, nutritionSummaryProvider, recentFoodLogsProvider;
import '../../features/nutrition/providers/nutrition_provider.dart'
    show dailyNutritionProvider, foodLogProvider, macroTargetsProvider;
import 'error_telemetry.dart';
import 'hive_service.dart';
import 'nutrition_write_source.dart';
import 'sync_service.dart';
import 'write_result.dart';

/// Single canonical writer for `nutrition_logs` + `nutrition_log_items`.
/// Every nutrition mutation in the app routes through one of these 7
/// methods. Direct `Hive.box('nutrition').put('nlog_*', ...)` writes
/// are forbidden outside this file (regression test in
/// `test/sync/sync_gap_test.dart` enforces).
///
/// All methods:
///   1. Validate input (rejects empty items / bad mealType / etc.)
///   2. Compute deterministic Hive key
///   3. Hive write (single put)
///   4. [Counter increment REMOVED — Test #11 M1. Counters now fire at the
///      API-call site so client UI agrees with server quota. See
///      _counterFeatureForSource for the feature→key mapping.]
///   5. Invalidate canonical Riverpod provider batch
///   6. Fire-and-forget cloud sync (writes BOTH nutrition_logs AND
///      nutrition_log_items rows in same transaction)
///   7. Return WriteResult
class NutritionWriteService {
  NutritionWriteService._();
  static final instance = NutritionWriteService._();

  /// Allowed values for `mealType`.
  static const Set<String> _allowedMealTypes = {
    'breakfast',
    'lunch',
    'dinner',
    'snacks',
  };

  /// Riverpod container set by `main.dart` so the service can invalidate
  /// providers without holding a `WidgetRef`. Mirrors Plan A's pattern
  /// in WorkoutWriteService.
  ProviderContainer? _container;
  void attachContainer(ProviderContainer c) => _container = c;

  /// Creates a `nutrition_logs` row + N `nutrition_log_items` rows
  /// atomically. Increments counter per source.
  Future<WriteResult> logMeal({
    required DateTime date,
    required String mealType,
    required List<FoodItem> items,
    int? overrideTotalCals,
    int? overrideTotalProtein,
    required NutritionWriteSource source,
  }) async {
    // 1. Validate
    if (items.isEmpty) {
      return WriteResult.fail(
        'logMeal: items list is empty (rejected to prevent ghost row)',
      );
    }
    if (!isAllowedMealType(mealType)) {
      return WriteResult.fail(
        'logMeal: mealType "$mealType" not in {breakfast,lunch,dinner,snacks}',
      );
    }

    // 2. Compute key (IST-anchored — caller passes IST DateTime)
    final key = computeLogKey(istDate: date, mealType: mealType, items: items);

    // 3. Compute totals (Atwater fallback per item if calories=0)
    final totalCals = overrideTotalCals ??
        items.fold<double>(0, (a, i) => a + i.kcalWithFallback).round();
    final totalProtein = overrideTotalProtein ??
        items.fold<double>(0, (a, i) => a + i.protein).round();
    final totalCarbs = items.fold<double>(0, (a, i) => a + i.carbs).round();
    final totalFat = items.fold<double>(0, (a, i) => a + i.fat).round();
    final totalFiber = items.fold<double>(0, (a, i) => a + i.fiber).round();

    final dateStr = istDateStr(date);

    final payload = <String, dynamic>{
      // APK Test #12.6 / Obs 7 — `id` field is what `_showEditMacrosSheet`
      // and `TodaysMealsCard` dismissible reads (alongside `log_key`).
      // Pre-fix only `log_key` was set → readers' `meal['id']` returned null
      // → edit silently no-op'd, dismissible had no key. Stamp both for
      // forward + legacy compat. Same value for both.
      'id': key,
      'log_key': key,
      'date': dateStr,
      'meal_type': mealType,
      'total_calories': totalCals,
      'total_protein': totalProtein,
      'total_carbs': totalCarbs,
      'total_fat': totalFat,
      'total_fiber': totalFiber,
      'items': items.map((i) => i.toMap()).toList(),
      'source': source.name,
      'logged_at': DateTime.now().toUtc().toIso8601String(),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

    // 4. Hive write (FC6: clamp absurd calorie/macro values first)
    _clampMealPayload(payload);
    try {
      await HiveService.instance.nutritionBox.put(key, payload);
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[NutritionWriteService] Hive put failed: $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'nutrition_write_service_log_meal_hive_put'));
      return WriteResult.fail('Hive write failed: $e');
    }

    // 5. Counter increment — REMOVED from this site (Test #11 M1).
    //    Counters now increment at the API-call site so the client UI
    //    agrees with the server quota regardless of whether the user saves.
    //    • AI text  → food_logger_section.dart _analyse() success path
    //    • Scan meal → nutrition_provider.dart ScanMealNotifier.scanImage() success path
    //    • Cart auditor → nutrition_provider.dart CartAuditorNotifier.analyseCart() success path
    //    • AI coach tool → tool_dispatcher.dart _executeLogMealByText() success path
    //    The dead `_counterFeatureForSource` switch is kept for documentation
    //    and future reference (see counterFeatureForSource @visibleForTesting export).

    // 6. Provider invalidation batch (if container attached)
    _invalidateNutritionProviders();

    // 7. Fire-and-forget cloud sync (writes BOTH nutrition_logs AND
    //    nutrition_log_items per `_syncNutritionLogs`)
    try {
      unawaited(SyncService.instance.syncNutritionData());
      unawaited(SyncService.instance.pushSnapshot());
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[NutritionWriteService] sync skipped (non-fatal): $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'nutrition_write_service_sync_skipped'));
    }

    return WriteResult.ok(key);
  }

  // FC6 (diagnose 4e8f1b) — absurd-value clamp ceilings. Set FAR above any real
  // meal so no legitimate entry is corrupted; anything above is garbage /
  // injection (e.g. a coach `log_meal_by_text` override of 1,000,000 kcal —
  // there is NO upstream numeric bound). A full day is ~2500–4000 kcal.
  static const int _kMaxMealCalories = 15000;
  static const int _kMaxItemCalories = 10000;
  static const int _kMaxMacroGrams = 2000; // protein/carbs/fat; real meal <~300g
  static const int _kMaxFiberGrams = 500;

  /// Clamp absurd calorie/macro values in a meal payload IN PLACE before it is
  /// persisted. Applied at EVERY nutrition write path (logMeal / appendItemsToMeal
  /// / editLog) because per-item values resurface on re-edit (those paths
  /// recompute totals from `items[].kcalWithFallback`), so both the TOTAL and
  /// each ITEM must be bounded. Clamp-and-telemetry, NEVER reject — offline-first
  /// must not silently drop a fat-fingered-but-real entry.
  void _clampMealPayload(Map<String, dynamic> m) {
    // Pure mutation is extracted into [clampMealPayloadValues] (@visibleForTesting)
    // so the clamp behavior can be asserted without Hive. This wrapper only owns
    // the side-effect: fire clamp telemetry when the pure step actually clamped.
    if (clampMealPayloadValues(m)) {
      unawaited(ErrorTelemetry.recordNonFatal(
        Exception('nutrition value exceeded sane ceiling — clamped'),
        StackTrace.current,
        reason: 'nutrition_absurd_value_clamped',
      ));
    }
  }

  /// FC6 / Hermes P2-FC6-1 — public restore-path entry point. The nutrition
  /// restore writer ([SyncService._restoreNutritionLogs]) is production code in
  /// a different library, so it cannot call the `@visibleForTesting`
  /// [clampMealPayloadValues] directly. This thin static wrapper bounds absurd
  /// calorie/macro values on a restored row IN PLACE (delegates to the same
  /// pure clamp) so a garbage cloud row can't reintroduce the value the local
  /// write path already clamps. Null-guards missing keys (safe on any nutrition
  /// row map). Returns whether anything was clamped.
  static bool clampRestoredNutritionRow(Map<String, dynamic> m) =>
      clampMealPayloadValues(m);

  /// Pure clamp of absurd calorie/macro values in a meal payload IN PLACE.
  ///
  /// Mutates [m] (both the TOTAL fields and each `items[]` entry) and RETURNS
  /// whether anything was clamped. NO side effects — the telemetry fire lives
  /// in [_clampMealPayload]. Exposed for the FC6 regression test
  /// (`test/contracts/nutrition_calorie_clamp_test.dart`) so the clamp can be
  /// asserted without a Hive box. Behavior is identical to the prior inline
  /// implementation (diagnose 4e8f1b).
  @visibleForTesting
  static bool clampMealPayloadValues(Map<String, dynamic> m) {
    var clamped = false;
    num clampNum(dynamic v, int ceiling) {
      final n = v is num ? v : 0;
      if (n > ceiling) {
        clamped = true;
        return ceiling;
      }
      if (n < 0) {
        clamped = true;
        return 0;
      }
      return n;
    }

    m['total_calories'] = clampNum(m['total_calories'], _kMaxMealCalories).round();
    m['total_protein'] = clampNum(m['total_protein'], _kMaxMacroGrams).round();
    m['total_carbs'] = clampNum(m['total_carbs'], _kMaxMacroGrams).round();
    m['total_fat'] = clampNum(m['total_fat'], _kMaxMacroGrams).round();
    m['total_fiber'] = clampNum(m['total_fiber'], _kMaxFiberGrams).round();

    final items = m['items'];
    if (items is List) {
      for (final it in items) {
        if (it is Map) {
          it['calories'] = clampNum(it['calories'], _kMaxItemCalories).toDouble();
          it['protein'] = clampNum(it['protein'], _kMaxMacroGrams).toDouble();
          it['carbs'] = clampNum(it['carbs'], _kMaxMacroGrams).toDouble();
          it['fat'] = clampNum(it['fat'], _kMaxMacroGrams).toDouble();
          it['fiber'] = clampNum(it['fiber'], _kMaxFiberGrams).toDouble();
        }
      }
    }

    return clamped;
  }

  /// Appends items to an existing meal log; recomputes totals.
  Future<WriteResult> appendItemsToMeal({
    required String existingLogKey,
    required List<FoodItem> additionalItems,
  }) async {
    if (additionalItems.isEmpty) {
      return WriteResult.fail('appendItemsToMeal: no items to append');
    }

    final box = HiveService.instance.nutritionBox;
    final raw = box.get(existingLogKey);
    if (raw == null) {
      return WriteResult.fail('logKey $existingLogKey not found');
    }

    final m = Map<String, dynamic>.from(raw as Map);
    final existing = ((m['items'] as List?) ?? const [])
        .map((e) => FoodItem.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    final union = [...existing, ...additionalItems];

    m['items'] = union.map((i) => i.toMap()).toList();
    m['total_calories'] =
        union.fold<double>(0, (a, i) => a + i.kcalWithFallback).round();
    m['total_protein'] = union.fold<double>(0, (a, i) => a + i.protein).round();
    m['total_carbs'] = union.fold<double>(0, (a, i) => a + i.carbs).round();
    m['total_fat'] = union.fold<double>(0, (a, i) => a + i.fat).round();
    m['total_fiber'] = union.fold<double>(0, (a, i) => a + i.fiber).round();
    m['logged_at'] = DateTime.now().toUtc().toIso8601String();
    _clampMealPayload(m); // FC6

    try {
      await box.put(existingLogKey, m);
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[NutritionWriteService] append put failed: $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'nutrition_write_service_append_items_put'));
      return WriteResult.fail('Hive write failed: $e');
    }

    _invalidateNutritionProviders();
    try {
      unawaited(SyncService.instance.syncNutritionData());
      unawaited(SyncService.instance.pushSnapshot());
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[NutritionWriteService] sync skipped (non-fatal): $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'nutrition_write_service_sync_skipped'));
    }

    return WriteResult.ok(existingLogKey);
  }

  /// Edits an existing log (used by edit-meal sheet).
  Future<WriteResult> editLog({
    required String logKey,
    required Map<String, dynamic> updates,
  }) async {
    final box = HiveService.instance.nutritionBox;
    final raw = box.get(logKey);
    if (raw == null) {
      return WriteResult.fail('logKey $logKey not found');
    }
    final m = Map<String, dynamic>.from(raw as Map);

    // Apply incoming updates
    m.addAll(updates);

    // If items[] changed, recompute totals
    if (updates.containsKey('items')) {
      final rawItems = (updates['items'] as List).cast<dynamic>();
      final items = rawItems
          .map((e) => FoodItem.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (items.isEmpty) {
        return WriteResult.fail(
          'editLog: items cannot be emptied (use deleteLog)',
        );
      }
      m['items'] = items.map((i) => i.toMap()).toList();
      m['total_calories'] =
          items.fold<double>(0, (a, i) => a + i.kcalWithFallback).round();
      m['total_protein'] =
          items.fold<double>(0, (a, i) => a + i.protein).round();
      m['total_carbs'] = items.fold<double>(0, (a, i) => a + i.carbs).round();
      m['total_fat'] = items.fold<double>(0, (a, i) => a + i.fat).round();
      m['total_fiber'] = items.fold<double>(0, (a, i) => a + i.fiber).round();
    }

    m['logged_at'] = DateTime.now().toUtc().toIso8601String();
    _clampMealPayload(m); // FC6

    try {
      await box.put(logKey, m);
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[NutritionWriteService] editLog put failed: $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'nutrition_write_service_edit_log_put'));
      return WriteResult.fail('Hive write failed: $e');
    }

    _invalidateNutritionProviders();
    try {
      unawaited(SyncService.instance.syncNutritionData());
      unawaited(SyncService.instance.pushSnapshot());
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[NutritionWriteService] sync skipped (non-fatal): $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'nutrition_write_service_sync_skipped'));
    }

    return WriteResult.ok(logKey);
  }

  /// Soft-deletes with undo (matches DeleteNutritionLogNotifier pattern).
  ///
  /// When `writeAuditLog: true` (default), also appends a `recent_deletes`
  /// entry to nutritionBox capped at 10 — used by AI coach to acknowledge
  /// corrections like "you removed your lunch Biryani entry" without the
  /// user re-explaining. OI-36 (audit-2026-05-17 Hermes C1) folded this
  /// behavior INTO the WriteService so DeleteNutritionLogNotifier can
  /// delegate fully instead of writing recent_deletes directly.
  Future<WriteResult> deleteLog({
    required String logKey,
    bool allowUndo = true,
    bool writeAuditLog = true,
  }) async {
    final box = HiveService.instance.nutritionBox;
    final raw = box.get(logKey);
    if (raw == null) {
      return WriteResult.fail('logKey $logKey not found');
    }

    if (allowUndo) {
      _lastDeletedPayload = Map<String, dynamic>.from(raw as Map);
      _lastDeletedKey = logKey;
    } else {
      _lastDeletedPayload = null;
      _lastDeletedKey = null;
    }

    // OI-36 — write recent_deletes audit log BEFORE the delete so the
    // entry is still readable. Only meaningful when the deleted row is a
    // food log (has name + meal_type + date fields); skipped for
    // non-meal nutritionBox keys (water logs, etc.) so we don't pollute
    // the coach's correction history with non-food deletions.
    if (writeAuditLog && raw is Map) {
      final hasFoodMeta = (raw['food_name'] != null ||
              raw['name'] != null) &&
          raw['meal_type'] != null;
      if (hasFoodMeta) {
        try {
          final deletes = (box.get('recent_deletes') as List?)
                  ?.whereType<Map>()
                  .toList() ??
              <Map>[];
          deletes.insert(0, {
            'food_name': raw['food_name'] ?? raw['name'] ?? '',
            'meal_type': raw['meal_type'] ?? '',
            'calories': raw['total_calories'] ?? raw['calories'] ?? 0,
            'deleted_at': DateTime.now().toIso8601String(),
            'logged_date': raw['date'] ?? '',
          });
          while (deletes.length > 10) {
            deletes.removeLast();
          }
          await box.put('recent_deletes', deletes);
        } catch (e, st) {
          debugPrint(
              '[NutritionWriteService] recent_deletes audit failed (non-fatal): $e\n$st');
          unawaited(ErrorTelemetry.recordNonFatal(e, st,
              reason: 'nutrition_write_service_audit_log'));
          // Non-fatal — the delete itself still proceeds.
        }
      }
    }

    try {
      await box.delete(logKey);
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[NutritionWriteService] deleteLog failed: $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'nutrition_write_service_delete_log'));
      return WriteResult.fail('Hive delete failed: $e');
    }

    _invalidateNutritionProviders();
    try {
      unawaited(SyncService.instance.syncNutritionData());
      unawaited(SyncService.instance.pushSnapshot());
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[NutritionWriteService] sync skipped (non-fatal): $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'nutrition_write_service_sync_skipped'));
    }

    return WriteResult.ok(logKey);
  }

  /// Re-puts the last-deleted log under its original key. Returns an
  /// error WriteResult if no stash exists.
  Future<WriteResult> restoreLastDeleted() async {
    final payload = _lastDeletedPayload;
    final key = _lastDeletedKey;
    if (payload == null || key == null) {
      return WriteResult.fail('nothing to restore');
    }
    try {
      await HiveService.instance.nutritionBox.put(key, payload);
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[NutritionWriteService] restoreLastDeleted failed: $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'nutrition_write_service_restore_last_deleted'));
      return WriteResult.fail('Hive restore failed: $e');
    }
    _lastDeletedPayload = null;
    _lastDeletedKey = null;

    _invalidateNutritionProviders();
    try {
      unawaited(SyncService.instance.syncNutritionData());
      unawaited(SyncService.instance.pushSnapshot());
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[NutritionWriteService] sync skipped (non-fatal): $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'nutrition_write_service_sync_skipped'));
    }

    return WriteResult.ok(key);
  }

  // Stash for undo. Keyed by logKey.
  Map<String, dynamic>? _lastDeletedPayload;
  String? _lastDeletedKey;

  // audit-fixwave 2026-07-02 / F14 — removed dead `logWater`. It wrote a
  // `water_<date>` key to nutritionBox that NO sync helper reads (a latent
  // trap: a future caller would create water rows that never reach cloud). The
  // canonical water writer is HealthWriteService.setWaterMl → `water_ml_<istDate>`
  // → water_logs (synced by _syncWaterLogs). See diagnose d8a6f2.

  /// Re-log of an existing saved meal template.
  Future<WriteResult> relogSavedMeal({
    required String savedMealKey,
    required DateTime date,
    required String mealType,
  }) async {
    final box = HiveService.instance.nutritionBox;
    final raw = box.get(savedMealKey);
    if (raw == null) {
      return WriteResult.fail('saved meal $savedMealKey not found');
    }
    final tpl = Map<String, dynamic>.from(raw as Map);
    final items = ((tpl['items'] as List?) ?? const [])
        .map((e) => FoodItem.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();

    return logMeal(
      date: date,
      mealType: mealType,
      items: items,
      source: NutritionWriteSource.savedMealRelog,
    );
  }

  /// Promote a logged meal to a saved template.
  Future<WriteResult> saveMealAsTemplate({
    required String sourceLogKey,
    String? customName,
  }) async {
    final box = HiveService.instance.nutritionBox;
    final raw = box.get(sourceLogKey);
    if (raw == null) {
      return WriteResult.fail('sourceLogKey $sourceLogKey not found');
    }
    final src = Map<String, dynamic>.from(raw as Map);
    final rawItems = ((src['items'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (rawItems.isEmpty) {
      return WriteResult.fail('cannot template a meal with no items');
    }

    final hash = rawItems
        .map((i) =>
            '${(i['name'] ?? '').toString().toLowerCase()}|${i['quantity_g'] ?? 0}')
        .join(';')
        .hashCode
        .toUnsigned(32)
        .toRadixString(16)
        .padLeft(8, '0');
    final templateKey = 'meal_$hash';

    final name = customName ??
        (rawItems.first['name']?.toString() ?? 'Saved Meal')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

    final payload = <String, dynamic>{
      'template_key': templateKey,
      'name': name,
      'items': rawItems,
      'total_calories': src['total_calories'] ?? 0,
      'total_protein': src['total_protein'] ?? 0,
      'total_carbs': src['total_carbs'] ?? 0,
      'total_fat': src['total_fat'] ?? 0,
      'total_fiber': src['total_fiber'] ?? 0,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'is_template': true,
    };

    try {
      await box.put(templateKey, payload);
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[NutritionWriteService] saveMealAsTemplate failed: $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'nutrition_write_service_save_meal_as_template'));
      return WriteResult.fail('Hive write failed: $e');
    }

    _invalidateNutritionProviders();
    try {
      unawaited(SyncService.instance.syncNutritionData());
      unawaited(SyncService.instance.pushSnapshot());
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[NutritionWriteService] sync skipped (non-fatal): $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'nutrition_write_service_sync_skipped'));
    }

    return WriteResult.ok(templateKey);
  }

  /// C-12 (audit-2026-05-11) — save a meal preset from-scratch.
  ///
  /// Distinct from [saveMealAsTemplate] which promotes an existing
  /// `nlog_*` row. This path is used by the AI breakdown / scan /
  /// search "Save as preset" flows where the meal hasn't yet been
  /// logged. Single Hive write (`saved_meal_<ts>`) + fan-out via the
  /// canonical sync helpers — matches the WriteService SoT contract
  /// per docs/architecture/sync.md.
  Future<WriteResult> saveMealPreset({
    required String name,
    required int totalCalories,
    required int totalProtein,
    required int totalCarbs,
    required int totalFat,
    int totalFiber = 0,
    required List<Map<String, dynamic>> items,
  }) async {
    if (name.trim().isEmpty) {
      return WriteResult.fail('name must be non-empty');
    }
    final box = HiveService.instance.nutritionBox;
    final now = DateTime.now();
    // Diagnose b8d5c2 — key by the canonical name (matches the restore + the
    // cloud (user_id,name) natural key), NOT by ms-timestamp. The old
    // `saved_meal_<ms>` key disagreed with the restore's name key → a restore
    // duplicated every saved meal locally.
    final id = savedMealKey(name);
    // F4 (f7e3a1 B-pass) — preserve a prior re-log count on same-name re-save:
    // the key is the meal's identity, so re-saving UPDATES it rather than
    // silently resetting times_used to 0.
    final prior = box.get(id);
    final priorTimesUsed =
        (prior is Map ? (prior['times_used'] as num?)?.toInt() : null) ?? 0;
    final payload = <String, dynamic>{
      'id': id,
      'is_saved_meal': true,
      'name': name.trim(),
      'total_calories': totalCalories,
      'total_protein': totalProtein,
      'total_carbs': totalCarbs,
      'total_fat': totalFat,
      if (totalFiber > 0) 'total_fiber': totalFiber,
      'items': items,
      'times_used': priorTimesUsed,
      'created_at': now.toIso8601String(),
    };
    try {
      await box.put(id, payload);
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint(
          '[NutritionWriteService] saveMealPreset put failed: $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'nutrition_write_service_save_meal_preset_put'));
      return WriteResult.fail('Hive write failed: $e');
    }

    _invalidateNutritionProviders();
    try {
      unawaited(SyncService.instance.syncNutritionData());
      unawaited(SyncService.instance.pushSnapshot());
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[NutritionWriteService] sync skipped (non-fatal): $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'nutrition_write_service_sync_skipped'));
    }

    return WriteResult.ok(id);
  }

  /// C-12 (audit-2026-05-11) — delete a saved meal preset.
  ///
  /// Routes through the WriteService so the provider invalidation + sync
  /// fan-out happens consistently with every other nutrition mutation.
  Future<WriteResult> deleteSavedMeal(String savedMealKey) async {
    if (savedMealKey.isEmpty) {
      return WriteResult.fail('savedMealKey must be non-empty');
    }
    final box = HiveService.instance.nutritionBox;
    try {
      await box.delete(savedMealKey);
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint(
          '[NutritionWriteService] deleteSavedMeal delete failed: $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'nutrition_write_service_delete_saved_meal'));
      return WriteResult.fail('Hive delete failed: $e');
    }

    _invalidateNutritionProviders();
    try {
      unawaited(SyncService.instance.syncNutritionData());
      unawaited(SyncService.instance.pushSnapshot());
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[NutritionWriteService] sync skipped (non-fatal): $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'nutrition_write_service_sync_skipped'));
    }

    return WriteResult.ok(savedMealKey);
  }

  /// C-12 (audit-2026-05-11) — restore a previously-deleted food log
  /// row at its original Hive key.
  ///
  /// Used by the food-log undo flow on the nutrition screen. Distinct
  /// from [restoreLastDeleted] which relies on the in-memory stash —
  /// this variant takes the full log map so callers that have their own
  /// stash (e.g., snackbar undo handlers) can route their write through
  /// the service.
  Future<WriteResult> restoreFoodLog(Map<String, dynamic> log) async {
    final key = log['id'] as String?;
    if (key == null || key.isEmpty) {
      return WriteResult.fail('log["id"] must be a non-empty string');
    }
    try {
      await HiveService.instance.nutritionBox.put(key, log);
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint(
          '[NutritionWriteService] restoreFoodLog put failed: $e\n$st');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'nutrition_write_service_restore_food_log_put'));
      return WriteResult.fail('Hive write failed: $e');
    }

    _invalidateNutritionProviders();
    try {
      unawaited(SyncService.instance.syncNutritionData());
      unawaited(SyncService.instance.pushSnapshot());
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[NutritionWriteService] sync skipped (non-fatal): $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'nutrition_write_service_sync_skipped'));
    }

    return WriteResult.ok(key);
  }

  // ---- private helpers ----

  String? _counterFeatureForSource(NutritionWriteSource s) {
    switch (s) {
      case NutritionWriteSource.aiText:
      case NutritionWriteSource.aiCoachTool:
        return AppConstants.featureAiTextLogPro;
      case NutritionWriteSource.scan:
        return AppConstants.featureScanMealPro;
      case NutritionWriteSource.cart:
        return AppConstants.featureCartAuditorPro;
      case NutritionWriteSource.manualSearch:
      case NutritionWriteSource.barcode:
      case NutritionWriteSource.savedMealRelog:
      case NutritionWriteSource.prelog:
        return null; // free unlimited
    }
  }

  /// APK Test #12.4 / Task #3 — reactivity hook (same pattern as
  /// `SubscriptionService.onStateChanged`).
  ///
  /// Pre-fix: the service invalidated providers via `_container`
  /// captured by `attachContainer`, but **`attachContainer` was NEVER
  /// CALLED** anywhere in the codebase. So `_container` stayed null
  /// for the entire app's lifetime, and `_invalidateNutritionProviders`
  /// always early-returned. Every nutrition write since Test #6 has
  /// silently failed to refresh the UI.
  ///
  /// New approach: wire from `app.dart` initState as a callback hook.
  /// Inside the callback, invalidate the canonical provider batch
  /// using the parent ConsumerState's `ref`. Symmetric with
  /// `SubscriptionService.onStateChanged`.
  static void Function()? onStateChanged;

  void _invalidateNutritionProviders() {
    // Legacy container path — kept for back-compat in tests that wire
    // _container directly via attachContainer. Production code goes
    // through onStateChanged.
    final c = _container;
    if (c != null) {
      try {
        c.invalidate(dailyNutritionProvider);
        c.invalidate(nutritionSummaryProvider);
        c.invalidate(recentFoodLogsProvider);
        c.invalidate(macroTargetsProvider);
        c.invalidate(aiInsightProvider);
        c.invalidate(foodLogProvider);
      } catch (e, st) {
        // audit-2026-05-11 H-42 — telemetry pair.
        debugPrint('[NutritionWriteService] provider invalidate skipped: $e');
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'nutrition_write_service_provider_invalidate'));
      }
    }
    // APK Test #12.4 / Task #3 — also fire the static hook. This is
    // the production path (wired from app.dart initState).
    try {
      onStateChanged?.call();
    } catch (_) {}
  }

  // ---- private helpers exposed for testing ----

  @visibleForTesting
  static String computeLogKey({
    required DateTime istDate,
    required String mealType,
    required List<FoodItem> items,
  }) {
    final dateStr = istDateStr(istDate);
    final itemsHash = _stableItemsHash(items);
    return 'nlog_${dateStr}_${mealType}_$itemsHash';
  }

  /// Canonical Hive key for a saved-meal preset: `saved_meal_<v5(name)>`.
  ///
  /// Identity is the (lowercased, trimmed) name. `SyncService._restoreSavedMeals`
  /// derives the SAME key by CALLING this helper, and the cloud natural key is
  /// `(user_id, name)`, so the same meal collapses to ONE row on every path
  /// (write / sync / restore). Diagnose b8d5c2 (2026-06-03, surfaced by the
  /// f7e3a1 B-pass): the writer formerly keyed by `millisecondsSinceEpoch`,
  /// which disagreed with the restore's name key → a restore wrote a SECOND
  /// local row for every saved meal. `SavedMealKeyMigrator` re-keys legacy rows
  /// on boot.
  ///
  /// Uses **UUID v5** (deterministic, full 122-bit) over the name — NOT
  /// `String.hashCode`, which is unstable across Dart VM versions (the exact
  /// hazard `NlogKeyMigrator`'s H-17 note documents) AND only 32-bit (a saved-meal
  /// hash-collision would merge two distinct meals). v5 is stable across SDK
  /// upgrades and collision-free, so neither failure mode applies (f7e3a1 B-pass
  /// Findings F3 + F6).
  static String savedMealKey(String name) =>
      'saved_meal_${_itemsHashUuidGen.v5(_itemsHashNamespace, 'saved_meal|${name.toLowerCase().trim()}')}';

  /// UUID namespace for the stable items hash. NEVER change without
  /// a migration bump in `NlogKeyMigrator`.
  static const _itemsHashUuidGen = Uuid();
  static const _itemsHashNamespace =
      '6ba7b810-9dad-11d1-80b4-00c04fd430c8';

  /// H-17 (audit-2026-05-11) — was `String.hashCode` which is not
  /// stable across Dart VM versions / isolates / platforms. Devices
  /// running the same restore could produce different `_<hash>` tags
  /// for the same `(meal, items)` tuple → duplicate Hive rows for
  /// what should be one logical meal. Switched to UUID v5
  /// (deterministic, cross-platform stable); take the first 8 hex
  /// chars to keep the Hive key compact and visually identical to
  /// the prior shape. NlogKeyMigrator bumped v1 → v2 to consolidate
  /// any pre-existing rows.
  static String _stableItemsHash(List<FoodItem> items) {
    final sorted = [...items]..sort((a, b) => a.name.compareTo(b.name));
    final joined = sorted
        .map((i) =>
            '${i.name.toLowerCase().trim()}|${i.quantityG.toStringAsFixed(1)}')
        .join(';');
    return _itemsHashUuidGen
        .v5(_itemsHashNamespace, joined)
        .replaceAll('-', '')
        .substring(0, 8);
  }

  static bool isAllowedMealType(String type) =>
      _allowedMealTypes.contains(type);

  /// Returns the feature key that increments for [source], or `null` if
  /// no counter applies. Exposed for test verification.
  @visibleForTesting
  static String? counterFeatureForSource(NutritionWriteSource s) =>
      instance._counterFeatureForSource(s);
}
