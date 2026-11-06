// scripts/append_vegan_protein_rows.dart
//
// One-off append (2026-09-17 diet-plan-meal-quality batch): the vegan
// archetype on the REAL 1431-row DB lands below the 95% protein floor on
// most seeds (116-148g vs >=142.5g) because the DB's vegan anchor pool is
// thin (Soybean 30.6, Soy Chunks cooked 27, Tofu Firm 21.4, then dals at
// 8-18g). Sanctioned fallback from plan-review rounds 2-3: add
// protein-dense Indian vegan rows under NEW ids (never modify original
// rows). New ids continue the sequence from F1432.
//
// Usage: dart run scripts/append_vegan_protein_rows.dart   (from repo root)

import 'dart:convert';
import 'dart:io';

Map<String, dynamic> _row(String id, String name, String cat, num cal,
    num prot, num carb, num fat, num fiber, num servingG, String desc) {
  final factor = servingG / 100.0;
  return {
    'id': id,
    'name': name,
    'category': cat,
    'calories_per_100g': cal,
    'protein_per_100g': prot,
    'carbs_per_100g': carb,
    'fat_per_100g': fat,
    'fiber_per_100g': fiber,
    'standard_serving_desc': desc,
    'standard_serving_g': servingG,
    'calories_std': (cal * factor).toDouble(),
    'protein_std': (prot * factor).toDouble(),
    'carbs_std': (carb * factor).toDouble(),
    'fat_std': (fat * factor).toDouble(),
    'is_indian': true,
    'is_veg': true,
    'is_vegan': true,
    'is_ultra_processed': false,
    'meal_fit': cat == 'nuts_seeds' ? ['snack'] : ['lunch', 'dinner'],
    'source': 'icanbefitter_seed',
  };
}

final _newRows = <Map<String, dynamic>>[
  // The founder's own coach-made diet charts use exactly this item
  // ("Soya Chunks (Nutrela) 50gm = 26.25g protein") — the highest-density
  // vegan protein in Indian kitchens.
  _row('F1432', 'Soya Chunks (Nutrela, dry)', 'pulses', 345, 52, 33, 0.5, 13, 50, '50g'),
  _row('F1433', 'Sattu (Roasted Chana Flour)', 'pulses', 413, 22, 53, 5, 11, 40, '40g'),
  _row('F1434', 'Chana (Black Chickpeas, boiled)', 'pulses', 164, 8.9, 27, 2.6, 7.6, 150, '1 bowl'),
  _row('F1435', 'Edamame (cooked)', 'pulses', 121, 11.9, 9, 5, 5.2, 100, '1 cup'),
  _row('F1436', 'Soy Flour', 'pulses', 446, 34.5, 30, 8, 9, 30, '30g'),
  _row('F1437', 'Hemp Seeds', 'nuts_seeds', 553, 31.5, 8.7, 48, 4, 20, '20g'),
  _row('F1438', 'Pumpkin Seeds', 'nuts_seeds', 559, 30, 11, 49, 6, 20, '20g'),
  _row('F1439', 'Tempeh (cooked)', 'protein', 193, 20.3, 7.6, 11, 4.5, 100, '100g'),
  _row('F1440', 'Seitan (cooked)', 'protein', 141, 25, 5, 2, 1.2, 100, '100g'),
  _row('F1441', 'Green Peas (dried)', 'pulses', 341, 20.5, 60, 1.2, 15, 50, '50g'),
];

void main() {
  final asset = File('assets/data/food_database.json');
  final rows =
      (jsonDecode(asset.readAsStringSync()) as List).cast<Map<String, dynamic>>();
  final ids = rows.map((r) => r['id']).toSet();
  for (final row in _newRows) {
    if (ids.contains(row['id'])) {
      stdout.writeln('SKIP (already present): ${row['id']} ${row['name']}');
      continue;
    }
    rows.add(row);
    stdout.writeln('APPENDED: ${row['id']} ${row['name']} '
        '(${row['protein_std']}g protein/serving)');
  }
  asset.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows));
  stdout.writeln('asset written: ${rows.length} rows');
}
