// scripts/fix_bpass_f1_duplicate_rows.dart
//
// One-off (2026-09-17 B-pass finding 1): of the 10 rows appended by
// append_vegan_protein_rows.dart, FOUR duplicated names already in the DB
// (Tempeh cooked F0375, Seitan cooked F0376, Hemp Seeds F0477, Edamame
// cooked F1018) — breaking the no-duplicate-names contract in
// food_database_v2_test.dart — and all 10 carried source
// 'icanbefitter_seed', inflating the pinned seed-row count 93 -> 103.
//
// Fix: REMOVE the 4 duplicate rows (the originals are strictly better for
// hemp/edamame: 9.6g vs 6.3g, 18.6g vs 11.9g per serving; anchor-pool name
// lookups resolve through the originals) and re-source the remaining 6 as
// 'icanbefitter_seed_v3'.
//
// Usage: dart run scripts/fix_bpass_f1_duplicate_rows.dart  (from repo root)

import 'dart:convert';
import 'dart:io';

const _removeIds = {'F1435', 'F1437', 'F1439', 'F1440'};
const _resourceIds = {'F1432', 'F1433', 'F1434', 'F1436', 'F1438', 'F1441'};

void main() {
  final asset = File('assets/data/food_database.json');
  final rows =
      (jsonDecode(asset.readAsStringSync()) as List).cast<Map<String, dynamic>>();

  final before = rows.length;
  rows.removeWhere((r) => _removeIds.contains(r['id']));
  stdout.writeln('removed ${before - rows.length} duplicate rows: $_removeIds');

  var resourced = 0;
  for (final row in rows) {
    if (_resourceIds.contains(row['id'])) {
      row['source'] = 'icanbefitter_seed_v3';
      resourced++;
    }
  }
  stdout.writeln('re-sourced $resourced rows -> icanbefitter_seed_v3');

  asset.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows));
  stdout.writeln('asset written: ${rows.length} rows');
}
