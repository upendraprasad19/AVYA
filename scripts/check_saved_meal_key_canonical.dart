// scripts/check_saved_meal_key_canonical.dart
//
// Diagnose b8d5c2 (2026-06-03) — source-grep gate. Pins the rule that
// `saved_meal_*` Hive keys are CONSTRUCTED in exactly one canonical place:
// `NutritionWriteService.savedMealKey(name)` → `saved_meal_<nameHash>`.
//
// Two documented mirrors are allowlisted:
//
//   - `lib/core/services/sync/sync_nutrition.dart` — `_restoreSavedMeals`
//     reconstructs the canonical key from a cloud `user_saved_meals` row during
//     restore (cloud carries the name, not the local Hive key); the mirror is
//     documented and pinned equal to the helper by
//     `test/contracts/saved_meal_key_canonical_test.dart`.
//   - `lib/core/services/saved_meal_key_migrator.dart` — the one-shot migrator
//     CALLS `NutritionWriteService.savedMealKey` (no literal construction), so it
//     does not even trip this gate; listed here only for documentation.
//
// Mirrors gate 17 (`check_exlog_key_canonical.dart`) + `check_nlog_key_canonical.dart`.
// Closes the writer/restore key-drift that duplicated saved meals on restore
// (the saveMealPreset writer formerly keyed by `saved_meal_<ms>`).
//
// Usage: dart run scripts/check_saved_meal_key_canonical.dart

import 'dart:io';

void main() {
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    stderr.writeln('[saved-meal-key-canonical] FAIL: lib/ does not exist');
    exit(1);
  }

  // Only the canonical helper + the documented restore mirror may emit a
  // `saved_meal_<...>` literal.
  const allowlist = <String>{
    'lib/core/services/nutrition_write_service.dart',
    'lib/core/services/sync/sync_nutrition.dart',
  };

  // Patterns that indicate a `saved_meal_*` Hive key is being CONSTRUCTED by
  // hand (interpolation / concat), NOT just referenced as a prefix
  // (`startsWith('saved_meal_')` is a read and does not match).
  final patterns = <RegExp>[
    RegExp(r"""['"]saved_meal_\$"""), // 'saved_meal_$var or "saved_meal_$var
    RegExp(r"""['"]saved_meal_\$\{"""), // 'saved_meal_${expr
    RegExp(r"""['"]saved_meal_['"]\s*\+"""), // 'saved_meal_' + …
  ];

  final offenders = <String>[];

  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.dart')) continue;

    final relPath = entity.path.replaceAll('\\', '/');
    if (allowlist.contains(relPath)) continue;

    // Strip BOTH block (/* */) and line (//) comments first so commentary about
    // the legacy shape never trips the gate
    // (feedback_source_grep_strip_comments_first). Block comments are blanked but
    // keep their newlines so reported line numbers stay accurate.
    final content = entity.readAsStringSync().replaceAllMapped(
        RegExp(r'/\*.*?\*/', dotAll: true),
        (m) => m[0]!.replaceAll(RegExp(r'[^\n]'), ' '));
    final lines = content.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final idx = raw.indexOf('//');
      final line = idx >= 0 ? raw.substring(0, idx) : raw;
      for (final p in patterns) {
        if (p.hasMatch(line)) {
          offenders.add('$relPath:${i + 1}: ${raw.trimRight()}');
          break;
        }
      }
    }
  }

  if (offenders.isEmpty) {
    stdout.writeln('[saved-meal-key-canonical] PASS — every `saved_meal_*` Hive '
        'key in lib/ is constructed via NutritionWriteService.savedMealKey or '
        'the documented restore mirror.');
    exit(0);
  }

  stderr.writeln('[saved-meal-key-canonical] FAIL — ${offenders.length} site(s) '
      'construct a `saved_meal_*` Hive key outside the canonical helper:');
  for (final v in offenders) {
    stderr.writeln('  $v');
  }
  stderr.writeln('');
  stderr.writeln('Fix: delegate to NutritionWriteService.savedMealKey(name). '
      'It produces `saved_meal_<nameHash>` — the same key the restore derives '
      'and the cloud (user_id,name) natural key. See diagnose b8d5c2.');
  exit(1);
}
