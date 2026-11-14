// scripts/patch_food_database_v4.dart
//
// One-shot, idempotent asset patch for the diet-plan Unit 1 batch
// (docs/plans/diet-food-quality.md §3.5-§3.6, 2026-11-14). Run from the repo
// root:  dart run scripts/patch_food_database_v4.dart
//
// 1. is_ultra_processed -> true for the reviewed id list below (sodas, colas,
//    packaged juices/energy drinks, jams, chocolate drinks/spreads, instant
//    noodles, packaged parota/cake, deli meats, processed cheese slices, mass
//    gainers, nuggets). Produced by a keyword sweep over every non-UPF row,
//    then read row by row; fresh juices, home-style shakes, fresh lime soda,
//    coconut water and plain carbonated water were deliberately left false.
// 2. is_ultra_processed -> false for plain roasted chana / makhana.
// 3. Appends seven everyday rows under NEW ids F1442-F1448 (derived *_std
//    fields computed from the per-100 g values so they cannot disagree).
// 4. Writes is_everyday on EVERY row: true EXACTLY for the ids of the curated
//    catalog (lib/features/nutrition/services/diet_plan_catalog.dart, imported
//    below so the two cannot drift), false for every other row. Reader: the
//    swap sheet (diet_plan_swap.dart) — a catalog food whose row says false is
//    never offered, so a later asset update can retire a food without a code
//    release. The generator does NOT read it (a v3 box must still generate).
//
// The script prints a summary and exits non-zero if an expected id is
// missing, so a stale asset cannot be half-patched silently.

import 'dart:convert';
import 'dart:io';

import 'package:icanbefitter/features/nutrition/services/diet_plan_catalog.dart';

const forceUpfIds = <String>[
  'F0035', 'F0522', 'F0523', 'F0524', 'F0525', 'F0526', 'F0527', 'F0528',
  'F0530', 'F0531', 'F0532', 'F0768', 'F0818', 'F0842', 'F0903', 'F0961',
  'F1198', 'F1199', 'F1200', 'F1208', 'F1212', 'F1220', 'F1224', 'F1228',
  'F1232', 'F1248', 'F1250', 'F1251', 'F1252', 'F1253', 'F1260', 'F1261',
  'F1264', 'F1268', 'F1274', 'F1275', 'F1297', 'F1301', 'F1306', 'F1308',
  'F1313', 'F1318', 'F1330', 'F1331', 'F1342', 'F1355', 'F1364', 'F1372',
  'F1377', 'F1379', 'F1380', 'F1382', 'F1383', 'F1397', 'F1400', 'F1403',
  'F1406', 'F1414', 'F1418', 'F1421', 'F1429',
  // review round 2: instant noodles, a protein wafer, an instant poha mix,
  // two packaged breads (NOVA ultra-processed)
  'F1368', 'F1407', 'F1381', 'F1300', 'F1420',
];

const notUpfIds = <String>['F0708', 'F0709', 'F0710'];

/// New rows: id, name, category, serving desc, serving g, per-100 g
/// (kcal, protein, carbs, fat, fiber), vegan, meal_fit.
const newRows = <List<Object>>[
  ['F1442', 'Kanda Poha', 'staples', '1 plate', 150, 167, 3.3, 26.7, 5.3, 1.6, true, ['breakfast', 'snack']],
  ['F1443', 'Vegetable Dalia', 'staples', '1 bowl', 200, 110, 3.5, 19.0, 2.5, 2.6, true, ['breakfast']],
  ['F1444', 'Khaman Dhokla', 'staples', '2 pieces', 70, 160, 6.0, 21.5, 5.5, 1.8, true, ['breakfast', 'snack']],
  ['F1445', 'Besan Chilla', 'staples', '1 chilla', 70, 200, 10.0, 21.5, 8.5, 3.5, true, ['breakfast']],
  ['F1446', 'Moong Dal Chilla', 'staples', '1 chilla', 70, 171, 11.4, 21.5, 4.3, 3.0, true, ['breakfast']],
  ['F1447', 'Vegetable Raita', 'dairy', '1 bowl', 150, 60, 3.3, 5.3, 2.7, 0.8, false, ['lunch', 'dinner']],
  ['F1448', 'Kachumber Salad', 'vegetables', '1 bowl', 150, 27, 1.3, 5.3, 0.2, 1.4, true, ['lunch', 'dinner']],
];

double _r1(num v) => (v * 10).round() / 10;

void main() {
  final asset = File('assets/data/food_database.json');
  final rows =
      (jsonDecode(asset.readAsStringSync()) as List).cast<Map<String, dynamic>>();
  final byId = {for (final r in rows) r['id'] as String: r};
  var failed = false;

  for (final id in [...forceUpfIds, ...notUpfIds]) {
    if (!byId.containsKey(id)) {
      stderr.writeln('MISSING id $id');
      failed = true;
    }
  }
  if (failed) exit(1);

  for (final id in forceUpfIds) {
    byId[id]!['is_ultra_processed'] = true;
  }
  for (final id in notUpfIds) {
    byId[id]!['is_ultra_processed'] = false;
  }

  var appended = 0;
  for (final n in newRows) {
    final id = n[0] as String;
    if (byId.containsKey(id)) continue; // idempotent
    final g = (n[4] as int).toDouble();
    double std(num per100) => _r1(per100 * g / 100);
    final row = <String, dynamic>{
      'id': id,
      'name': n[1],
      'category': n[2],
      'calories_per_100g': n[5],
      'protein_per_100g': n[6],
      'carbs_per_100g': n[7],
      'fat_per_100g': n[8],
      'fiber_per_100g': n[9],
      'standard_serving_desc': n[3],
      'standard_serving_g': n[4],
      'calories_std': std(n[5] as num),
      'protein_std': std(n[6] as num),
      'carbs_std': std(n[7] as num),
      'fat_std': std(n[8] as num),
      'is_indian': true,
      'is_veg': true,
      'is_vegan': n[10],
      'source': 'icanbefitter_seed_v4',
      'is_ultra_processed': false,
      'meal_fit': n[11],
    };
    rows.add(row);
    byId[id] = row;
    appended++;
  }

  // Catalog ids are checked AFTER the append (F1442-F1448 are catalog ids).
  final catalogIds = {for (final e in kDietPlanCatalog) e.foodId};
  for (final id in catalogIds) {
    if (!byId.containsKey(id)) {
      stderr.writeln('MISSING catalog id $id');
      failed = true;
    }
  }
  if (failed) exit(1);

  var everyday = 0;
  for (final r in rows) {
    final e = catalogIds.contains(r['id']);
    r['is_everyday'] = e;
    if (e) everyday++;
  }

  asset.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows));
  stdout.writeln('UPF->true ${forceUpfIds.length}, UPF->false '
      '${notUpfIds.length}, appended $appended, rows ${rows.length}, '
      'is_everyday=true $everyday');
}
