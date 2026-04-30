import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'nutrition_write_source.dart';
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
  // ignore: unused_field
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
    throw UnimplementedError('Implemented in Task C-3');
  }

  /// Appends items to an existing meal log; recomputes totals.
  Future<WriteResult> appendItemsToMeal({
    required String existingLogKey,
    required List<FoodItem> additionalItems,
  }) async {
    throw UnimplementedError('Implemented in Task C-5');
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
}
