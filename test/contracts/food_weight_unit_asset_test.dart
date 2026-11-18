// test/contracts/food_weight_unit_asset_test.dart
//
// OI-517 (docs/plans/diet-grams-toggle.md sections 3, 5, 6): the audited set of
// LIQUID rows in assets/data/food_database.json carries `weight_unit: "ml"`
// (absent = grams), nothing else does, and no solid / yogurt row slipped in.
// The set was decided row by row from `scripts/report_serving_weights.dart`
// (never inferred at render time: a name match returns Broccoli (steamed) and
// Tuna in Water). Changing the set is a deliberate edit of BOTH this list and
// the asset, plus a `_foodLibraryVersion` bump in seed_service.dart.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _liquidIds = <String>{
  'F0031', 'F0032', 'F0033', 'F0034', 'F0062', 'F0063', 'F0064', 'F0065',
  'F0066', 'F0067', 'F0068', 'F0377', 'F0378', 'F0379', 'F0380', 'F0381',
  'F0382', 'F0383', 'F0387', 'F0409', 'F0485', 'F0486', 'F0487', 'F0488',
  'F0489', 'F0490', 'F0491', 'F0492', 'F0493', 'F0494', 'F0495', 'F0496',
  'F0497', 'F0498', 'F0499', 'F0500', 'F0501', 'F0502', 'F0503', 'F0504',
  'F0505', 'F0506', 'F0507', 'F0508', 'F0509', 'F0510', 'F0511', 'F0512',
  'F0513', 'F0514', 'F0515', 'F0516', 'F0517', 'F0518', 'F0519', 'F0520',
  'F0521', 'F0522', 'F0523', 'F0524', 'F0525', 'F0526', 'F0527', 'F0528',
  'F0529', 'F0530', 'F0531', 'F0532', 'F0533', 'F0534', 'F0535', 'F0536',
  'F0537', 'F0622', 'F0889', 'F0890', 'F0959', 'F0960', 'F0961', 'F0962',
  'F0963', 'F0964', 'F0965', 'F0966', 'F1094', 'F1095', 'F1096', 'F1097',
  'F1100', 'F1105', 'F1106', 'F1107', 'F1108', 'F1109', 'F1208', 'F1212',
  'F1213', 'F1220', 'F1224', 'F1228', 'F1229', 'F1232', 'F1233', 'F1235',
  'F1244', 'F1246', 'F1247', 'F1248', 'F1251', 'F1254', 'F1260', 'F1268',
  'F1280', 'F1290', 'F1291', 'F1299', 'F1303', 'F1306', 'F1318', 'F1327',
  'F1330', 'F1342', 'F1352', 'F1377', 'F1378', 'F1380', 'F1382', 'F1393',
  'F1397', 'F1411', 'F1425', 'F1429',
};

void main() {
  final rows = (jsonDecode(File('assets/data/food_database.json')
          .readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();

  test('exactly the audited liquid rows carry weight_unit ml', () {
    final flagged = {
      for (final r in rows)
        if (r.containsKey('weight_unit')) r['id'] as String,
    };
    expect(flagged, _liquidIds);
    for (final r in rows.where((r) => r.containsKey('weight_unit'))) {
      expect(r['weight_unit'], 'ml', reason: r['id'] as String);
    }
  });

  test('every row whose description is a millilitre figure is flagged', () {
    final mlDesc = RegExp(r'\d\s*ml\b', caseSensitive: false);
    for (final r in rows) {
      final desc = (r['standard_serving_desc'] as String? ?? '');
      if (mlDesc.hasMatch(desc)) {
        expect(r['weight_unit'], 'ml',
            reason: '${r['id']} ${r['name']} "$desc"');
      }
    }
  });

  test('no yogurt, curd, powder or cheese row is a liquid', () {
    final solid = RegExp(r'yogurt|yoghurt|dahi|skyr|curd|ricotta|paneer|cheese',
        caseSensitive: false);
    for (final r in rows.where((r) => r.containsKey('weight_unit'))) {
      expect(solid.hasMatch(r['name'] as String), isFalse,
          reason: '${r['id']} ${r['name']}');
    }
  });
}
