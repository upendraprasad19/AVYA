// Drift-fix batch 2026-05-24 / F2 nutrition — pins the single-SoT rule
// for `nlog_*` Hive key construction.
//
// `NutritionWriteService.computeLogKey(istDate, mealType, items)` is
// the only legal constructor of `nlog_*` Hive keys. Every other lib/
// path MUST delegate to that helper.
//
// Two documented mirrors are allowlisted:
//   - lib/core/services/sync_service.dart — `_nlogKeyForRestore`
//     reconstructs the canonical key during restore.
//   - lib/core/services/nlog_key_migrator.dart — one-shot migrator
//     rewriting legacy key shapes to canonical.
//
// Mirrors `scripts/check_nlog_key_canonical.dart` (the build-gate)
// but runs as part of `flutter test` so the gate also fails the
// pre-commit hook + CI pipeline rather than only the APK build.
//
// Per feedback_source_grep_strip_comments_first.md, this test strips
// BOTH line comments (`//`) and block comments (`/* ... */`) before
// pattern-matching so explanatory commentary about the old key shapes
// cannot false-positive the gate.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nlog_* canonical writer allowlist', () {
    test('only 3 files emit `nlog_*` Hive key construction', () {
      // Files that legitimately reference the prefix.
      const allowlist = <String>{
        'lib/core/services/nutrition_write_service.dart',
        'lib/core/services/sync_service.dart',
        'lib/core/services/nlog_key_migrator.dart',
      };

      final patterns = <RegExp>[
        RegExp(r"""['"]nlog_\$"""),
        RegExp(r"""['"]nlog_\$\{"""),
        RegExp(r"""['"]nlog_['"]\s*\+"""),
      ];

      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue, reason: 'lib/ must exist');

      final offenders = <String>[];

      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;
        final relPath = entity.path.replaceAll('\\', '/');
        if (allowlist.contains(relPath)) continue;

        // Read full source and strip block comments first so
        // explanatory /* ... */ commentary about the old shape
        // doesn't trigger the gate. Then walk line-by-line and strip
        // line comments per line. Preserves line numbering for
        // accurate offender messages.
        final source = entity.readAsStringSync();
        final stripped = _stripBlockComments(source);
        final lines = stripped.split('\n');
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

      expect(offenders, isEmpty,
          reason: 'Construct `nlog_*` keys via '
              'NutritionWriteService.computeLogKey(istDate, mealType, items). '
              'Offenders: ${offenders.join(' | ')}');
    });
  });
}

/// Strip `/* ... */` block comments from [source], preserving newline
/// characters inside the comment so downstream line numbers stay
/// stable. Non-greedy: handles consecutive blocks correctly.
String _stripBlockComments(String source) {
  final buffer = StringBuffer();
  var i = 0;
  while (i < source.length) {
    if (i + 1 < source.length &&
        source[i] == '/' &&
        source[i + 1] == '*') {
      // Find closing */
      final end = source.indexOf('*/', i + 2);
      if (end < 0) {
        // Unterminated — bail; emit rest as-is.
        buffer.write(source.substring(i));
        break;
      }
      // Preserve newlines inside the comment to keep line numbers stable.
      for (var j = i; j < end + 2; j++) {
        if (source[j] == '\n') buffer.write('\n');
      }
      i = end + 2;
    } else {
      buffer.write(source[i]);
      i++;
    }
  }
  return buffer.toString();
}
