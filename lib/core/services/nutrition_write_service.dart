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
import 'subscription_service.dart';
import 'sync_service.dart';
import 'usage_counter_service.dart';
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
///   4. Increment per-source counter (if applicable)
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

    // 5. Counter increment per source
    final counterFeature = _counterFeatureForSource(source);
    if (counterFeature != null) {
      // Use try/catch — if SubscriptionService isn't initialized in tests
      // we still want the write to succeed.
      try {
        final isPro = SubscriptionService.instance.isPro();
        unawaited(
            UsageCounterService.instance.increment(counterFeature, isPro));
      } catch (e) {
        debugPrint(
            '[NutritionWriteService] counter increment skipped (non-fatal): $e');
      }
    }

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
    throw UnimplementedError('Implemented in Task C-6');
  }

  /// Soft-deletes with undo (matches DeleteNutritionLogNotifier pattern).
  Future<WriteResult> deleteLog({
    required String logKey,
    bool allowUndo = true,
  }) async {
    throw UnimplementedError('Implemented in Task C-7');
  }

  /// Atomic water log write.
  Future<WriteResult> logWater({
    required DateTime date,
    required int ml,
    int? urineColor,
  }) async {
    throw UnimplementedError('Implemented in Task C-8');
  }

  /// Re-log of an existing saved meal template.
  Future<WriteResult> relogSavedMeal({
    required String savedMealKey,
    required DateTime date,
    required String mealType,
  }) async {
    throw UnimplementedError('Implemented in Task C-8');
  }

  /// Promote a logged meal to a saved template.
  Future<WriteResult> saveMealAsTemplate({
    required String sourceLogKey,
    String? customName,
  }) async {
    throw UnimplementedError('Implemented in Task C-8');
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
