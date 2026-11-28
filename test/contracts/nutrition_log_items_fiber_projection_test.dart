// test/contracts/nutrition_log_items_fiber_projection_test.dart
//
// Drift-fix batch 2026-05-24 / F4 nutrition (P2).
//
// Pins that the cloud `nutrition_log_items` projection in
// `sync_nutrition.dart` includes the `fiber` key — added 2026-05-24
// alongside migration 068 which ships the column. Without this key
// in the projection, the cloud column would stay 0 forever for new
// logs, defeating the purpose of the additive schema change.

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('sync_nutrition.dart projects fiber to nutrition_log_items', () {
    final file = File('lib/core/services/sync/sync_nutrition.dart');
    expect(file.existsSync(), isTrue,
        reason: 'sync_nutrition.dart must exist at the expected path');

    final source = file.readAsStringSync();

    // Strip block + line comments per
    // feedback_source_grep_strip_comments_first.md so explanatory
    // comments don't trigger a false positive when the projection
    // is removed.
    final stripped = _stripComments(source);

    // The fiber key must appear in the per-item projection. We don't
    // pin exact line content — just that the string `'fiber':` (or
    // `"fiber":`) appears in the file's executable code.
    final hasFiber = stripped.contains("'fiber':") ||
        stripped.contains('"fiber":');

    expect(
      hasFiber,
      isTrue,
      reason: 'sync_nutrition.dart must project `fiber` to '
          '`nutrition_log_items`. Add `\'fiber\': item[\'fiber\'] ?? 0,` '
          'to the per-item projection block. See migration 068.',
    );
  });
}

String _stripComments(String src) {
  // Remove /* ... */ blocks first.
  final block = RegExp(r'/\*[\s\S]*?\*/');
  var out = src.replaceAll(block, '');
  // Then remove // line comments.
  final line = RegExp(r'//.*');
  out = out.replaceAll(line, '');
  return out;
}
