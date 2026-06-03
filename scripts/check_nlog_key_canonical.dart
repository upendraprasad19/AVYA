// scripts/check_nlog_key_canonical.dart
//
// Drift-fix batch 2026-05-24 / F2 nutrition — source-grep gate. Pins
// the rule that `nlog_*` Hive keys are constructed in exactly ONE
// place: `lib/core/services/nutrition_write_service.dart` via the
// static helper `NutritionWriteService.computeLogKey(...)`.
//
// Two documented mirrors exist (and are allowlisted):
//
//   - `lib/core/services/sync_service.dart` — `_nlogKeyForRestore`
//     reconstructs the canonical key from a raw cloud nutrition_logs
//     row during restore. Cloud doesn't carry the FoodItem[] list
//     directly; the mirror is documented and round-trip-tested.
//
//   - `lib/core/services/nlog_key_migrator.dart` — one-shot migrator
//     that legitimately walks legacy `nlog_*` key shapes and rewrites
//     them to canonical. Migration mirrors are necessary.
//
// Mirrors gate 17 (`check_exlog_key_canonical.dart`) shipped APK Test
// #16.1. Closes follow-up risk surface F2 from the 2026-05-24
// writer-reader-drift-detector first run.
//
// Usage: dart run scripts/check_nlog_key_canonical.dart

import 'dart:io';

void main() {
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    stderr.writeln('[nlog-key-canonical] FAIL: lib/ does not exist');
    exit(1);
  }

  // Only the canonical helper + the documented restore + migration
  // mirrors may emit `nlog_` literals.
  const allowlist = <String>{
    'lib/core/services/nutrition_write_service.dart',
    'lib/core/services/sync_service.dart',
    'lib/core/services/nlog_key_migrator.dart',
  };

  // Patterns that indicate an `nlog_*` Hive key is being CONSTRUCTED
  // by hand (string concat or interpolation), NOT just referenced as
  // a prefix.
  final patterns = <RegExp>[
    RegExp(r"""['"]nlog_\$"""),       // 'nlog_$var or "nlog_$var
    RegExp(r"""['"]nlog_\$\{"""),     // 'nlog_${expr or "nlog_${expr
    RegExp(r"""['"]nlog_['"]\s*\+"""),// 'nlog_' + … or "nlog_" + …
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
    stdout.writeln('[nlog-key-canonical] PASS — every `nlog_*` Hive '
        'key in lib/ is constructed via '
        'NutritionWriteService.computeLogKey or the documented '
        'restore/migration mirrors.');
    exit(0);
  }

  stderr.writeln(
      '[nlog-key-canonical] FAIL — ${offenders.length} site(s) '
      'construct an `nlog_*` Hive key outside the canonical helper:');
  for (final v in offenders) {
    stderr.writeln('  $v');
  }
  stderr.writeln('');
  stderr.writeln('Fix: delegate to '
      'NutritionWriteService.computeLogKey(istDate, mealType, items). '
      'The helper lives at lib/core/services/nutrition_write_service.dart '
      'and produces `nlog_<istDateStr>_<mealType>_<v5hash8>`. See '
      'docs/superpowers/specs/2026-05-24-drift-fix-batch-design.md.');
  exit(1);
}
