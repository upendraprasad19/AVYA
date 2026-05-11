// T-12 / audit-2026-05-11 — WriteService-bypass detector.
//
// CLAUDE.md §15 "Hive field-name contract" + "Sync fan-out contract"
// names two services as the sole writers for workout / nutrition Hive
// rows:
//   - WorkoutWriteService — writes exlog_* and wlog_* (logExercise,
//     markCompleted).
//   - NutritionWriteService — writes nlog_* and saved_meal_*
//     (logMeal, saveMealPreset, saveMealAsTemplate).
//
// Test #8 + audit C-8/C-12 closed half a dozen bypass sites that
// silently wrote the legacy field shape. Without a grep-style
// guardrail, new code can re-open the class. This test scans every
// file under lib/ for direct writes to those four prefixes outside an
// explicit allowlist.
//
// Allowlist rationale:
//   - The WriteServices themselves own the writes.
//   - SyncService writes raw rows during restore (cloud → Hive
//     round-trip uses the same shape, but originates from a different
//     source).
//   - Test fixtures and contract tests under test/ are excluded by
//     filesystem walk.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files allowed to write `exlog_*` / `wlog_*` keys directly. Anything
/// else must route through `WorkoutWriteService`.
const _workoutPrefixAllowlist = <String>[
  'lib/core/services/workout_write_service.dart',
  'lib/core/services/sync_service.dart',
  // Legacy repository — slated for removal in Phase 8. Tracked
  // separately; the existing call sites here are the legacy fallback
  // path WorkoutWriteService delegates to via the deprecation shim.
  'lib/features/train/repositories/workout_repository.dart',
];

/// Files allowed to write `nlog_*` / `saved_meal_*` keys directly.
/// Anything else must route through `NutritionWriteService`.
const _nutritionPrefixAllowlist = <String>[
  'lib/core/services/nutrition_write_service.dart',
  'lib/core/services/sync_service.dart',
];

/// Forbidden patterns. Each regex matches a direct Hive put whose key
/// string literal starts with the named prefix. We accept either
/// `workoutBox.put('exlog_...'` (top-level helper) or `box.put(...)`
/// inside an obvious workoutBox context — but most production code
/// uses the explicit `<box>.put(` form so the regex stays tight.
final _workoutForbiddenPatterns = <RegExp>[
  // workoutBox.put('exlog_<...>', ...) — direct write of exercise log.
  RegExp(r'''workoutBox\.put\(\s*['"]exlog_'''),
  // workoutBox.put('exlog_${...}', ...) — interpolated key.
  RegExp(r'''workoutBox\.put\(\s*['"]exlog_\$'''),
  // wlog_ variants.
  RegExp(r'''workoutBox\.put\(\s*['"]wlog_'''),
  RegExp(r'''workoutBox\.put\(\s*['"]wlog_\$'''),
  // Also catch the `'exlog_<ts>_<hash>'` and `'wlog_<ts>'` literal
  // form even when typed into a separate `final id = '...'` first by
  // requiring the key string literal to be `put(<id>` after a
  // declaration of `id = 'exlog_…'` in the same function.
];

final _nutritionForbiddenPatterns = <RegExp>[
  RegExp(r'''nutritionBox\.put\(\s*['"]nlog_'''),
  RegExp(r'''nutritionBox\.put\(\s*['"]nlog_\$'''),
  RegExp(r'''nutritionBox\.put\(\s*['"]saved_meal_'''),
  RegExp(r'''nutritionBox\.put\(\s*['"]saved_meal_\$'''),
];

/// Also catch the indirect-key form: a local `final id = 'exlog_...'`
/// followed somewhere by `workoutBox.put(id, ...)`. We approximate this
/// by checking the function body for both the literal key declaration
/// AND the `workoutBox.put(id` call. Imperfect but catches the common
/// bypass shape from the C-8 fix (id was always declared inline).
final _indirectKeyPatterns = <_IndirectKey>[
  _IndirectKey(
    boxPattern: RegExp(r'''workoutBox\.put\(\s*(\w+)\s*,'''),
    keyPattern: RegExp('''=\\s*['"]exlog_'''),
    label: 'workoutBox.put(<id>, ...) where <id> = "exlog_..."',
    allowlist: _workoutPrefixAllowlist,
  ),
  _IndirectKey(
    boxPattern: RegExp(r'''workoutBox\.put\(\s*(\w+)\s*,'''),
    keyPattern: RegExp('''=\\s*['"]wlog_'''),
    label: 'workoutBox.put(<id>, ...) where <id> = "wlog_..."',
    allowlist: _workoutPrefixAllowlist,
  ),
  _IndirectKey(
    boxPattern: RegExp(r'''nutritionBox\.put\(\s*(\w+)\s*,'''),
    keyPattern: RegExp('''=\\s*['"]nlog_'''),
    label: 'nutritionBox.put(<id>, ...) where <id> = "nlog_..."',
    allowlist: _nutritionPrefixAllowlist,
  ),
  _IndirectKey(
    boxPattern: RegExp(r'''nutritionBox\.put\(\s*(\w+)\s*,'''),
    keyPattern: RegExp('''=\\s*['"]saved_meal_'''),
    label: 'nutritionBox.put(<id>, ...) where <id> = "saved_meal_..."',
    allowlist: _nutritionPrefixAllowlist,
  ),
];

class _IndirectKey {
  final RegExp boxPattern;
  final RegExp keyPattern;
  final String label;
  final List<String> allowlist;
  const _IndirectKey({
    required this.boxPattern,
    required this.keyPattern,
    required this.label,
    required this.allowlist,
  });
}

Iterable<File> _libDartFiles() sync* {
  final root = Directory('lib');
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.endsWith('.dart')) yield entity;
  }
}

String _norm(String path) => path.replaceAll('\\', '/');

void main() {
  group('T-12 WriteService bypass detector', () {
    test(
      'no direct workoutBox.put for exlog_* / wlog_* outside WorkoutWriteService',
      () {
        final offenders = <String>[];
        for (final file in _libDartFiles()) {
          final relPath = _norm(file.path);
          if (_workoutPrefixAllowlist.any((a) => relPath.endsWith(a))) {
            continue;
          }
          final src = file.readAsStringSync();
          for (final p in _workoutForbiddenPatterns) {
            if (p.hasMatch(src)) {
              offenders.add('$relPath  matches  $p');
            }
          }
        }
        expect(
          offenders,
          isEmpty,
          reason:
              'Direct workoutBox.put for exlog_*/wlog_* outside '
              'WorkoutWriteService is forbidden per CLAUDE.md §15. '
              'Route through WorkoutWriteService.logExercise / .markCompleted.',
        );
      },
    );

    test(
      'no direct nutritionBox.put for nlog_* / saved_meal_* outside NutritionWriteService',
      () {
        final offenders = <String>[];
        for (final file in _libDartFiles()) {
          final relPath = _norm(file.path);
          if (_nutritionPrefixAllowlist.any((a) => relPath.endsWith(a))) {
            continue;
          }
          final src = file.readAsStringSync();
          for (final p in _nutritionForbiddenPatterns) {
            if (p.hasMatch(src)) {
              offenders.add('$relPath  matches  $p');
            }
          }
        }
        expect(
          offenders,
          isEmpty,
          reason:
              'Direct nutritionBox.put for nlog_*/saved_meal_* outside '
              'NutritionWriteService is forbidden per CLAUDE.md §15. '
              'Route through NutritionWriteService.logMeal / .saveMealPreset.',
        );
      },
    );

    test(
      'no indirect <box>.put(<id>, ...) where <id> = "exlog_/wlog_/nlog_/saved_meal_..."',
      () {
        final offenders = <String>[];
        for (final file in _libDartFiles()) {
          final relPath = _norm(file.path);
          final src = file.readAsStringSync();
          for (final rule in _indirectKeyPatterns) {
            if (rule.allowlist.any((a) => relPath.endsWith(a))) continue;
            // First, check if the file declares such a key literal
            // anywhere. Cheap pre-filter.
            if (!rule.keyPattern.hasMatch(src)) continue;
            // Then, check it puts to the matching box at all.
            if (!rule.boxPattern.hasMatch(src)) continue;
            offenders.add('$relPath  → ${rule.label}');
          }
        }
        expect(
          offenders,
          isEmpty,
          reason:
              'Indirect WriteService bypass detected. The file declares a '
              'key literal with one of the WriteService prefixes (exlog_, '
              'wlog_, nlog_, saved_meal_) AND writes that key to the '
              'matching Hive box. This is the exact shape of the C-8 / '
              'C-12 bug class. Route through the relevant WriteService.',
        );
      },
    );
  });
}
