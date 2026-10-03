// scripts/patch_food_upf_tags.dart
//
// One-off patch (2026-09-17 diet-plan-meal-quality batch): flags branded/
// ultra-processed rows the heuristic keywords missed AND the founder's
// HTML glance did not catch (found via the real-DB vegan/composition
// debug run). Keyword list in generate_food_tag_review.dart updated with
// the same names so a re-run reproduces this patch.
//
// Usage: dart run scripts/patch_food_upf_tags.dart   (run from repo root)

import 'dart:convert';
import 'dart:io';

const _forceUpfIds = [
  'F1351', // Smith & Jones Pasta Masala (packaged instant pasta)
  'F1349', // Nestle Milkybar Moosha (chocolate dairy dessert)
  'F1326', // Yoga Bar Daily 10g Protein Bar
  'F1367', // Yoga bar 20g protein oats+
  'F1409', // Pintos Peanut Butter Dark Chocolate Creamy
  'F1207', // Jaouda Perly (branded flavored dairy drink)
];

void main() {
  final asset = File('assets/data/food_database.json');
  final rows =
      (jsonDecode(asset.readAsStringSync()) as List).cast<Map<String, dynamic>>();
  var patched = 0;
  for (final row in rows) {
    if (_forceUpfIds.contains(row['id'])) {
      row['is_ultra_processed'] = true;
      patched++;
      stdout.writeln('UPF=true: ${row['id']} ${row['name']}');
    }
  }
  if (patched != _forceUpfIds.length) {
    stderr.writeln('WARN: expected ${_forceUpfIds.length} rows, patched $patched');
  }
  asset.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows));
  stdout.writeln('asset written ($patched rows patched)');
}
