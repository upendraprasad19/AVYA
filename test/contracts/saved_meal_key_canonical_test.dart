import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';

/// Diagnose b8d5c2 — pins the saved-meal Hive-key canonical contract:
///  1. `saved_meal_*` keys are CONSTRUCTED only via
///     `NutritionWriteService.savedMealKey` or the documented restore mirror
///     (mirrors `scripts/check_saved_meal_key_canonical.dart`).
///  2. The writer helper and the restore mirror produce the SAME key for a name
///     — the bug (saved meals duplicated on restore) WAS writer⇄restore key
///     disagreement (`saved_meal_<ms>` vs `saved_meal_<nameHash>`).
void main() {
  test('no lib/ site constructs a saved_meal_* key outside the canonical helper',
      () {
    const allowlist = {
      'lib/core/services/nutrition_write_service.dart',
      'lib/core/services/sync/sync_nutrition.dart',
    };
    final patterns = [
      RegExp(r"""['"]saved_meal_\$"""),
      RegExp(r"""['"]saved_meal_\$\{"""),
      RegExp(r"""['"]saved_meal_['"]\s*\+"""),
    ];
    final offenders = <String>[];
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final rel = e.path.replaceAll('\\', '/');
      if (allowlist.contains(rel)) continue;
      // Strip block + line comments first (feedback_source_grep_strip_comments_first).
      final content = e.readAsStringSync().replaceAllMapped(
          RegExp(r'/\*.*?\*/', dotAll: true),
          (m) => m[0]!.replaceAll(RegExp(r'[^\n]'), ' '));
      final lines = content.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final raw = lines[i];
        final idx = raw.indexOf('//');
        final line = idx >= 0 ? raw.substring(0, idx) : raw;
        if (patterns.any((p) => p.hasMatch(line))) {
          offenders.add('$rel:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason:
            'construct via NutritionWriteService.savedMealKey instead: $offenders');
  });

  test('savedMealKey is a STABLE UUID-v5 shape, not String.hashCode / ms (F3/F6)',
      () {
    final k = NutritionWriteService.savedMealKey('Chicken Rice');
    // saved_meal_<full v5 uuid> — deterministic across Dart SDK versions
    // (hashCode is not) AND 122-bit (no 32-bit saved-meal hash collision).
    expect(
        RegExp(r'^saved_meal_[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
                r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
            .hasMatch(k),
        isTrue,
        reason: 'must be a full v5 UUID, never a 32-bit hashCode or 13-digit ms');
    expect(NutritionWriteService.savedMealKey('Chicken Rice'), k,
        reason: 'deterministic');
    expect(NutritionWriteService.savedMealKey('Paneer Bowl'),
        isNot(NutritionWriteService.savedMealKey('Chicken Rice')),
        reason: 'distinct names → distinct keys');
  });

  test('savedMealKey is case/whitespace-insensitive (same meal → same key)', () {
    expect(NutritionWriteService.savedMealKey('Paneer Bowl'),
        NutritionWriteService.savedMealKey('  paneer bowl  '));
  });
}
