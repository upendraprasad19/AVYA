// APK Test #16.1 / Agent A — pins the single-SoT rule for `exlog_*`
// Hive key construction.
//
// `WorkoutWriteService.exlogKey(date, name)` is the only legal
// constructor of `exlog_*` Hive keys. Every other lib/ path MUST
// delegate to that helper.
//
// Mirrors `scripts/check_exlog_key_canonical.dart` (the build-gate)
// but runs as part of `flutter test` so the gate also fails the
// pre-commit hook + CI pipeline rather than only the APK build.
//
// Pre-fix offenders (closed by this batch):
//   - lib/core/services/sync/sync_workout.dart:587
//     `_restoreExerciseLogs` used `exlog_<utc-substring>_<name.hashCode>`
//   - lib/features/train/repositories/workout_repository.dart:1133
//     `logSetWithPrRescan` used `exlog_<ms>_<name.hashCode>`
//
// hashCode is platform-unstable; `ms` makes every re-log a fresh key.
// Both writers now delegate to `WorkoutWriteService.exlogKey`.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only WorkoutWriteService constructs `exlog_*` Hive keys', () {
    // Files that legitimately reference the prefix.
    const allowlist = <String>{
      'lib/core/services/workout_write_service.dart',
      'lib/core/services/exlog_key_migrator.dart',
    };

    final patterns = <RegExp>[
      RegExp(r"""['"]exlog_\$"""),
      RegExp(r"""['"]exlog_\$\{"""),
      RegExp(r"""['"]exlog_['"]\s*\+"""),
    ];

    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'lib/ must exist');

    final offenders = <String>[];

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;
      final relPath = entity.path.replaceAll('\\', '/');
      if (allowlist.contains(relPath)) continue;

      final lines = entity.readAsLinesSync();
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
        reason: 'Construct `exlog_*` keys via '
            'WorkoutWriteService.exlogKey(date, name). '
            'Offenders: ${offenders.join(' | ')}');
  });
}
