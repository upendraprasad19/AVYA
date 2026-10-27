// Batch B1 Task 0 — frozen reference of every PRE-EXISTING key of the shipped
// exercise library, recorded on the pre-B1 tree (5696c4c8: assets/ identical to
// main 08c077d1). Batch B adds new keys only; this test fails if any existing
// key's value changes or disappears. It replaces a `git show <sha>:` comparison,
// which CI's depth-1 checkout cannot run (.github/workflows/test.yml:128).
//
// Re-record only in a commit whose diagnose doc names each changed id, and only
// those ids — each is re-hashed over its RECORDED key set, so keys added later
// (v13's core-list fields) never enter the reference:
//   RECORD_LIBRARY_REFERENCE_IDS=E061,E070 flutter test test/contracts/exercise_library_frozen_reference_test.dart
// RECORD_LIBRARY_REFERENCE=1 re-records every row over its CURRENT keys; it was
// used once, on the pre-B1 tree.
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
    final byId = {for (final r in rows) r['id'] as String: r};
    final recordIds = Platform.environment['RECORD_LIBRARY_REFERENCE_IDS'];
    if (recordIds != null && recordIds.isNotEmpty) {
      final ref = jsonDecode(File(_fixturePath).readAsStringSync())
          as Map<String, dynamic>;
      for (final id in recordIds.split(',').map((s) => s.trim())) {
        final entry = ref[id] as Map<String, dynamic>?;
        final row = byId[id];
        if (entry == null || row == null) fail('unknown id $id');
        final keys = (entry['keys'] as List).cast<String>();
        entry['sha256'] = _rowHash(row, keys);
      }
      File(_fixturePath).writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(ref)}\n');
    }
    final ref = jsonDecode(File(_fixturePath).readAsStringSync())
        as Map<String, dynamic>;
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
