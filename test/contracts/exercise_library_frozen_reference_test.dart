// Batch B1 Task 0 — frozen reference of every PRE-EXISTING key of the shipped
// exercise library, recorded on the pre-B1 tree (5696c4c8: assets/ identical to
// main 08c077d1). Batch B adds new keys only; this test fails if any existing
// key's value changes or disappears. It replaces a `git show <sha>:` comparison,
// which CI's depth-1 checkout cannot run (.github/workflows/test.yml:128).
//
// Re-record only in a commit whose diagnose doc names each changed id:
//   RECORD_LIBRARY_REFERENCE=1 flutter test test/contracts/exercise_library_frozen_reference_test.dart
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/migration_ledger_hash_lib.dart' show sha256Hex;

const _fixturePath = 'test/fixtures/exercise_library_v12_row_hashes.json';

String _rowHash(Map row, List<String> keys) => sha256Hex(utf8.encode(
    jsonEncode(SplayTreeMap<String, dynamic>.from({for (final k in keys) k: row[k]}))));

void main() {
  final rows = (jsonDecode(
    File('assets/data/exercise_library.json').readAsStringSync(),
  ) as List)
      .cast<Map<String, dynamic>>();

  test('every pre-existing key of every row is unchanged', () {
    if (Platform.environment['RECORD_LIBRARY_REFERENCE'] == '1') {
      final out = SplayTreeMap<String, dynamic>();
      for (final r in rows) {
        final keys = (r.keys.toList()..sort());
        out[r['id'] as String] = {'keys': keys, 'sha256': _rowHash(r, keys)};
      }
      File(_fixturePath).writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(out)}\n');
    }
    final ref = jsonDecode(File(_fixturePath).readAsStringSync())
        as Map<String, dynamic>;
    final byId = {for (final r in rows) r['id'] as String: r};
    final bad = <String>[];
    for (final e in ref.entries) {
      final row = byId[e.key];
      final entry = e.value as Map<String, dynamic>;
      final keys = (entry['keys'] as List).cast<String>();
      if (row == null || keys.any((k) => !row.containsKey(k))) {
        bad.add('${e.key} (missing row or key)');
      } else if (_rowHash(row, keys) != entry['sha256']) {
        bad.add(e.key);
      }
    }
    expect(ref.length, 285);
    expect(bad, isEmpty, reason: 'rows whose pre-existing keys changed: $bad');
  });
}
