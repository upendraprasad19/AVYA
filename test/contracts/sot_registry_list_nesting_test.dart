// A `      - file:` list item in docs/sot_registry.yaml must sit under a key that
// opens a block list (`    readers:` / `    writers:` with no value). Batch B1
// appended five reader blocks after a `contract_test_path: <path>` scalar; every
// registry gate is line-based, so they passed, while a YAML loader reads them as
// a broken scalar and the readers never join the concept (B-pass F3).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every 6-space list item follows a key that opens a block list', () {
    final lines = File('docs/sot_registry.yaml').readAsLinesSync();
    final key = RegExp(r'^    ([A-Za-z_]+):(.*)$');
    String? lastKey;
    var lastKeyOpensList = false;
    final bad = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final m = key.firstMatch(lines[i]);
      if (m != null) {
        lastKey = m.group(1);
        lastKeyOpensList = m.group(2)!.trim().isEmpty;
        continue;
      }
      if (lines[i].startsWith('  - ')) {
        lastKey = null;
        lastKeyOpensList = false;
        continue;
      }
      if (lines[i].startsWith('      - ') && !lastKeyOpensList) {
        bad.add('line ${i + 1}: list item under `$lastKey:`');
      }
    }
    expect(bad, isEmpty, reason: bad.take(10).join('\n'));
  });
}
