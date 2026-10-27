// Regression contract for bug b9c4f1 (Obs#7, 2026-06-13 live web E2E): on the AI
// food-analysis result card the item name rendered one char per line (vertical)
// because the name's Expanded was starved to ~0 width by 5 fixed-width macro
// columns. Pins maxLines: 1 + ellipsis on the name Text. Source-grep, comment-
// stripped.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _strip(String src) {
  var s = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  s = s
      .split('\n')
      .map((line) {
        final m = RegExp(r'(?<!:)//').firstMatch(line);
        return m == null ? line : line.substring(0, m.start);
      })
      .join('\n');
  return s;
}

void main() {
  test('b9c4f1 — food-card item name is single-line + ellipsis (no vertical wrap)',
      () {
    final src = _strip(File('lib/features/nutrition/widgets/ai_breakdown_card.dart')
        .readAsStringSync());

    final nameIdx = src.indexOf('item.name');
    expect(nameIdx, isNot(-1), reason: 'the item name Text must exist');

    // Within the name Text widget (the ~200 chars following `item.name`), both
    // maxLines: 1 and TextOverflow.ellipsis must be declared.
    final window =
        src.substring(nameIdx, nameIdx + 200 > src.length ? src.length : nameIdx + 200);
    expect(window.contains('maxLines: 1'), isTrue,
        reason: 'item name Text must be single-line so a starved Expanded cannot '
            'wrap it one char per line');
    expect(window.contains('TextOverflow.ellipsis'), isTrue,
        reason: 'item name Text must ellipsis-truncate, not vertical-wrap');
  });
}
