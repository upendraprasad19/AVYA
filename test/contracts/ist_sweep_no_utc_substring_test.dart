// APK Test #12.6 — IST sweep contract test.
//
// Pins the requirement that no production `lib/` file constructs a
// date-key string via `DateTime.now().toIso8601String().substring(0, 10)`.
// That pattern returns the UTC date for UTC `DateTime`s and the local
// date for local `DateTime`s — but never the IST date — and is the
// recurring class behind every "writer wrote IST, reader read UTC,
// data invisible after 18:30 IST" bug we've shipped (Tests #6 → #12).
//
// The canonical helper is `lib/core/utils/ist_date.dart::istDateStr`.
// The single legal exception is the helper file itself, which uses the
// pattern internally as part of its IST math.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no production lib/ file uses DateTime.now().toIso8601String().substring(0, 10)',
      () {
    // Allowlist: the helper itself may use the substring/ISO pattern
    // inside its implementation. Every other lib/ path must go through
    // `istDateStr(...)` so date-keys agree across writers/readers.
    const allowlist = <String>{
      'lib/core/utils/ist_date.dart',
    };

    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'lib/ must exist');

    final offenders = <String>[];

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;

      // Normalize to forward slashes for cross-platform comparison.
      final relPath = entity.path.replaceAll('\\', '/');
      if (allowlist.contains(relPath)) continue;

      final content = entity.readAsStringSync();
      // Strip line/block comments so commentary about the bad pattern
      // doesn't trigger the test (e.g. CHANGELOG-style annotations).
      final stripped = content
          .replaceAll(RegExp(r'//.*'), '')
          .replaceAll(RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '');

      // Match the canonical bad pattern, allowing whitespace inside
      // the .substring(0, 10) parens.
      final pat = RegExp(
        r"DateTime\.now\(\)\s*\.toIso8601String\(\)\s*\.substring\(\s*0\s*,\s*10\s*\)",
      );
      if (pat.hasMatch(stripped)) {
        offenders.add(relPath);
      }
    }

    expect(offenders, isEmpty,
        reason:
            'Use istDateStr(DateTime.now()) instead of '
            'DateTime.now().toIso8601String().substring(0, 10). '
            'Offenders: ${offenders.join(', ')}');
  });
}
