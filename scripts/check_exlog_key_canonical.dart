// scripts/check_exlog_key_canonical.dart
//
// Gate: 17
//
// APK Test #16.1 / Agent A — source-grep gate. Pins the rule that
// `exlog_*` Hive keys are constructed in exactly ONE place:
// `lib/core/services/workout_write_service.dart` via the static
// helper `WorkoutWriteService.exlogKey(date, name)`.
//
// Pre-fix (founder observation on +24 APK install, May 14 2026), THREE
// different formulas were in use across `lib/`:
//
//   1. CANONICAL — `exlog_<istDateStr>_<uuidV5(name)[0:8]>`
//      (workout_write_service.dart:823)
//   2. ROGUE A   — `exlog_<dateStr>_<name.hashCode>`
//      (sync/sync_workout.dart:587 in _restoreExerciseLogs)
//   3. ROGUE B   — `exlog_<ms>_<name.hashCode>`
//      (train/repositories/workout_repository.dart:1133 in
//       logSetWithPrRescan, called by AI coach `logPR` tool)
//
// hashCode is platform-unstable and `ms` makes every re-log a new key
// → restore + PR re-claim could each duplicate rows. The migrator
// heals data; this gate prevents regression by failing the build on
// any future code that builds an `exlog_*` key by hand.
//
// Detection — scan lib/**/*.dart for either string concat or
// interpolation that emits a literal `exlog_` prefix immediately
// followed by something other than a closing quote. The canonical
// helper file is the only allowed producer.
//
// Tests + the migrator are also allowed (they reason about legacy
// shapes by design).
//
// Usage: dart run scripts/check_exlog_key_canonical.dart

import 'dart:io';

void main() {
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    stderr.writeln('[exlog-key-canonical] FAIL: lib/ does not exist');
    exit(1);
  }

  // Only the canonical helper + the one-shot migrator may emit
  // `exlog_` literals. The migrator legitimately constructs canonical
  // keys via `WorkoutWriteService.exlogKey` (no rogue concat), but it
  // also matches `oldKey.startsWith('exlog_')` and stringly references
  // `'exlog_key_migration_v8'` — both are NOT key construction.
  // The allowlist therefore covers the few well-audited files.
  const allowlist = <String>{
    'lib/core/services/workout_write_service.dart',
    'lib/core/services/exlog_key_migrator.dart',
  };

  // Patterns that indicate an `exlog_*` Hive key is being CONSTRUCTED
  // by hand (string concat or interpolation), NOT just referenced as
  // a prefix. We flag any line that contains `'exlog_$` (interpolation
  // immediately after the prefix) or `'exlog_' +` (concat) or
  // `"exlog_${` / `'exlog_${` (interpolation block).
  //
  // We do NOT flag `.startsWith('exlog_')` or `'exlog_key_migration_v8'`
  // or any single-quoted string that ends with `_'` (mere reference).
  final patterns = <RegExp>[
    RegExp(r"""['"]exlog_\$"""),       // 'exlog_$var or "exlog_$var
    RegExp(r"""['"]exlog_\$\{"""),     // 'exlog_${expr or "exlog_${expr
    RegExp(r"""['"]exlog_['"]\s*\+"""),// 'exlog_' + … or "exlog_" + …
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
    stdout.writeln('[exlog-key-canonical] PASS — every `exlog_*` Hive '
        'key in lib/ is constructed via WorkoutWriteService.exlogKey.');
    exit(0);
  }

  stderr.writeln(
      '[exlog-key-canonical] FAIL — ${offenders.length} site(s) '
      'construct an `exlog_*` Hive key outside the canonical helper:');
  for (final v in offenders) {
    stderr.writeln('  $v');
  }
  stderr.writeln('');
  stderr.writeln('Fix: delegate to '
      'WorkoutWriteService.exlogKey(date, exerciseName). The helper '
      'lives at lib/core/services/workout_write_service.dart:823 and '
      'produces `exlog_<istDateStr>_<uuidV5(name)[0:8]>` — the only '
      'shape readers (receipt, AI snapshot, PR rescan, restore) '
      'understand. See APK Test #16.1 diagnose-doc.');
  exit(1);
}
