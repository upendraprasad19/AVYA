import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../../features/home/providers/home_provider.dart'
    show aiInsightProvider, nutritionSummaryProvider, recentFoodLogsProvider;
import '../../features/nutrition/providers/nutrition_provider.dart'
    show dailyNutritionProvider, macroTargetsProvider;
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

    final dateStr =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    final payload = <String, dynamic>{
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

    // 4. Hive write
    try {
      await HiveService.instance.nutritionBox.put(key, payload);
    } catch (e, st) {
      debugPrint('[NutritionWriteService] Hive put failed: $e\n$st');
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
    } catch (e) {
      debugPrint('[NutritionWriteService] sync skipped (non-fatal): $e');
    }

    return WriteResult.ok(key);
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

    try {
      await box.put(existingLogKey, m);
    } catch (e, st) {
      debugPrint('[NutritionWriteService] append put failed: $e\n$st');
      return WriteResult.fail('Hive write failed: $e');
    }

    _invalidateNutritionProviders();
    try {
      unawaited(SyncService.instance.syncNutritionData());
      unawaited(SyncService.instance.pushSnapshot());
    } catch (e) {
      debugPrint('[NutritionWriteService] sync skipped (non-fatal): $e');
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

    try {
      await box.put(logKey, m);
    } catch (e, st) {
      debugPrint('[NutritionWriteService] editLog put failed: $e\n$st');
      return WriteResult.fail('Hive write failed: $e');
    }

    _invalidateNutritionProviders();
    try {
      unawaited(SyncService.instance.syncNutritionData());
      unawaited(SyncService.instance.pushSnapshot());
    } catch (e) {
      debugPrint('[NutritionWriteService] sync skipped (non-fatal): $e');
    }

    return WriteResult.ok(logKey);
  }

  /// Soft-deletes with undo (matches DeleteNutritionLogNotifier pattern).
  Future<WriteResult> deleteLog({
    required String logKey,
    bool allowUndo = true,
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

    try {
      await box.delete(logKey);
    } catch (e, st) {
      debugPrint('[NutritionWriteService] deleteLog failed: $e\n$st');
      return WriteResult.fail('Hive delete failed: $e');
    }

    _invalidateNutritionProviders();
    try {
      unawaited(SyncService.instance.syncNutritionData());
      unawaited(SyncService.instance.pushSnapshot());
    } catch (e) {
      debugPrint('[NutritionWriteService] sync skipped (non-fatal): $e');
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
      debugPrint('[NutritionWriteService] restoreLastDeleted failed: $e\n$st');
      return WriteResult.fail('Hive restore failed: $e');
    }
    _lastDeletedPayload = null;
    _lastDeletedKey = null;

    _invalidateNutritionProviders();
    try {
      unawaited(SyncService.instance.syncNutritionData());
      unawaited(SyncService.instance.pushSnapshot());
    } catch (e) {
      debugPrint('[NutritionWriteService] sync skipped (non-fatal): $e');
    }

    return WriteResult.ok(key);
  }

  // Stash for undo. Keyed by logKey.
  Map<String, dynamic>? _lastDeletedPayload;
  String? _lastDeletedKey;

  /// Atomic water log write.
  Future<WriteResult> logWater({
    required DateTime date,
    required int ml,
    int? urineColor,
  }) async {
    if (ml <= 0) {
      return WriteResult.fail('logWater: ml must be > 0');
    }
    final dateStr =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final key = 'water_$dateStr';

    final box = HiveService.instance.nutritionBox;
    final existing = box.get(key);
    final current = existing == null
        ? <String, dynamic>{
            'date': dateStr,
            'ml': 0,
            'urine_color': null,
          }
        : Map<String, dynamic>.from(existing as Map);

    current['ml'] = ((current['ml'] as num?)?.toInt() ?? 0) + ml;
    if (urineColor != null) current['urine_color'] = urineColor;
    current['logged_at'] = DateTime.now().toUtc().toIso8601String();

    try {
      await box.put(key, current);
    } catch (e, st) {
      debugPrint('[NutritionWriteService] logWater put failed: $e\n$st');
      return WriteResult.fail('Hive write failed: $e');
    }

    _invalidateNutritionProviders();
    try {
      unawaited(SyncService.instance.syncNutritionData());
      unawaited(SyncService.instance.pushSnapshot());
    } catch (e) {
      debugPrint('[NutritionWriteService] sync skipped (non-fatal): $e');
    }

    return WriteResult.ok(key);
  }

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
      debugPrint('[NutritionWriteService] saveMealAsTemplate failed: $e\n$st');
      return WriteResult.fail('Hive write failed: $e');
    }

    _invalidateNutritionProviders();
    try {
      unawaited(SyncService.instance.syncNutritionData());
      unawaited(SyncService.instance.pushSnapshot());
    } catch (e) {
      debugPrint('[NutritionWriteService] sync skipped (non-fatal): $e');
    }

    return WriteResult.ok(templateKey);
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

  void _invalidateNutritionProviders() {
    final c = _container;
    if (c == null) return;
    try {
      c.invalidate(dailyNutritionProvider);
      c.invalidate(nutritionSummaryProvider);
      c.invalidate(recentFoodLogsProvider);
      c.invalidate(macroTargetsProvider);
      c.invalidate(aiInsightProvider);
    } catch (e) {
      debugPrint('[NutritionWriteService] provider invalidate skipped: $e');
    }
  }

  // ---- private helpers exposed for testing ----

  @visibleForTesting
  static String computeLogKey({
    required DateTime istDate,
    required String mealType,
    required List<FoodItem> items,
  }) {
    final dateStr =
        '${istDate.year.toString().padLeft(4, '0')}-${istDate.month.toString().padLeft(2, '0')}-${istDate.day.toString().padLeft(2, '0')}';
    final itemsHash = _stableItemsHash(items);
    return 'nlog_${dateStr}_${mealType}_$itemsHash';
  }

  static String _stableItemsHash(List<FoodItem> items) {
    final sorted = [...items]..sort((a, b) => a.name.compareTo(b.name));
    final joined = sorted
        .map((i) =>
            '${i.name.toLowerCase().trim()}|${i.quantityG.toStringAsFixed(1)}')
        .join(';');
    return joined.hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0');
  }

  static bool isAllowedMealType(String type) =>
      _allowedMealTypes.contains(type);

  /// Returns the feature key that increments for [source], or `null` if
  /// no counter applies. Exposed for test verification.
  @visibleForTesting
  static String? counterFeatureForSource(NutritionWriteSource s) =>
      instance._counterFeatureForSource(s);
}
