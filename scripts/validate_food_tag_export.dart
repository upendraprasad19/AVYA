// scripts/validate_food_tag_export.dart
//
// Diet-plan meal-quality batch (2026-09-17): validates the founder's
// HTML-exported tagged food database BEFORE it replaces
// assets/data/food_database.json.
//
// Usage:
//   dart run scripts/validate_food_tag_export.dart <path-to-export.json>
//
// Checks:
//   1. Row count identical to the current asset (1431).
//   2. Row ORDER identical (same id sequence).
//   3. Every LEGACY field byte-identical per row (only the two new fields
//      are allowed to differ: meal_fit, is_ultra_processed).
//   4. Every row fully tagged: is_ultra_processed is a bool, meal_fit is a
//      list whose values are all in {breakfast, lunch, dinner, snack}.
//   5. Pinned spot-checks (regression floor for the heuristic + review):
//      every Pringles/Maggi/Special K row => UPF true; Idli/Roti => false.
//
// Exit 0 = valid (safe to swap the asset); exit 1 = details printed.

import 'dart:convert';
import 'dart:io';

const _legacyFields = [
  'id', 'name', 'category', 'calories_per_100g', 'protein_per_100g',
  'carbs_per_100g', 'fat_per_100g', 'fiber_per_100g',
  'standard_serving_desc', 'standard_serving_g',
  'calories_std', 'protein_std', 'carbs_std', 'fat_std',
  'is_indian', 'is_veg', 'is_vegan', 'source',
];
const _validSlots = {'breakfast', 'lunch', 'dinner', 'snack'};

int _failures = 0;

void fail(String msg) {
  _failures++;
  stdout.writeln('FAIL: $msg');
}

bool _jsonEqual(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run scripts/validate_food_tag_export.dart <export.json>');
    exit(1);
  }
  final exportPath = args.first;
  final exportFile = File(exportPath);
  if (!exportFile.existsSync()) {
    stderr.writeln('FATAL: export file not found: $exportPath');
    exit(1);
  }
  final assetFile = File('assets/data/food_database.json');
  if (!assetFile.existsSync()) {
    stderr.writeln('FATAL: run from repo root — assets/data/food_database.json not found');
    exit(1);
  }

  final exported = (jsonDecode(exportFile.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final current = (jsonDecode(assetFile.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();

  // 1. row count
  if (exported.length != current.length) {
    fail('row count: export=${exported.length} vs asset=${current.length}');
  }

  // 2. order + 3. legacy fields byte-identical
  var legacyChecked = 0;
  for (var i = 0; i < exported.length && i < current.length; i++) {
    final e = exported[i];
    final c = current[i];
    if (e['id'] != c['id']) {
      fail('row $i: id order changed (export=${e['id']} asset=${c['id']})');
      continue;
    }
    for (final f in _legacyFields) {
      if (!_jsonEqual(e[f], c[f])) {
        fail('row ${c['id']} (${'name'}: ${c['name']}): legacy field "$f" changed: '
            '${jsonEncode(c[f])} -> ${jsonEncode(e[f])}');
      }
      legacyChecked++;
    }
  }
  stdout.writeln('row order + legacy fields checked: $legacyChecked field comparisons over ${current.length} rows');

  // 4. fully tagged with valid values
  var untagged = 0;
  for (final row in exported) {
    final upf = row['is_ultra_processed'];
    if (upf is! bool) {
      fail('row ${row['id']} (${row['name']}): is_ultra_processed not a bool ($upf)');
      untagged++;
    }
    final fit = row['meal_fit'];
    if (fit is! List) {
      fail('row ${row['id']} (${row['name']}): meal_fit missing/not a list');
      untagged++;
    } else {
      // Empty list is a LEGAL tagged state = "never generated" (the five
      // alcohol rows are deliberately cleared by the founder).
      for (final s in fit) {
        if (!_validSlots.contains(s)) {
          fail('row ${row['id']} (${row['name']}): invalid meal_fit slot "$s"');
        }
      }
    }
  }
  if (untagged == 0) {
    stdout.writeln('all ${exported.length} rows fully tagged with valid slot values');
  }

  // 5. pinned spot-checks
  bool isUpfNamed(String name) => exported
      .where((r) => (r['name'] as String).toLowerCase().contains(name.toLowerCase()))
      .every((r) => r['is_ultra_processed'] == true);

  if (!isUpfNamed('pringles')) {
    fail('spot-check: some Pringles row is not UPF=true (case-insensitive sweep)');
  } else {
    stdout.writeln('spot-check OK: all Pringles rows UPF=true');
  }
  if (!isUpfNamed('maggi')) {
    fail('spot-check: some Maggi row is not UPF=true');
  } else {
    stdout.writeln('spot-check OK: all Maggi rows UPF=true');
  }
  if (!isUpfNamed('special k')) {
    fail('spot-check: some Special K row is not UPF=true');
  } else {
    stdout.writeln('spot-check OK: all Special K rows UPF=true');
  }
  for (final clean in ['idli', 'roti (whole wheat)', 'almonds']) {
    final rows = exported.where((r) =>
        (r['name'] as String).toLowerCase() == clean.toLowerCase()).toList();
    if (rows.isEmpty) {
      fail('spot-check: expected row "$clean" not found by exact name');
    } else if (rows.any((r) => r['is_ultra_processed'] == true)) {
      fail('spot-check: "$clean" must be UPF=false');
    } else {
      stdout.writeln('spot-check OK: "$clean" UPF=false');
    }
  }

  if (_failures > 0) {
    stdout.writeln('');
    stdout.writeln('VALIDATION FAILED: $_failures failure(s). Asset NOT swapped.');
    exit(1);
  }
  stdout.writeln('');
  stdout.writeln('VALIDATION PASSED — export is safe to swap into assets/data/food_database.json');
}
