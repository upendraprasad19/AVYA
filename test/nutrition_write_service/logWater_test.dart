// ignore_for_file: file_names

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';

import 'helpers/nws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(nwsTestSetup);
  tearDown(nwsTestTeardown);

  test('logWater accumulates ml + writes water_<date>', () async {
    final r1 = await NutritionWriteService.instance
        .logWater(date: DateTime(2026, 5, 1), ml: 250);
    expect(r1.success, true);
    expect(r1.logKey, 'water_2026-05-01');

    await NutritionWriteService.instance
        .logWater(date: DateTime(2026, 5, 1), ml: 500, urineColor: 3);

    final m = Map<String, dynamic>.from(
        HiveService.instance.nutritionBox.get('water_2026-05-01') as Map);
    expect(m['ml'], 750);
    expect(m['urine_color'], 3);
  });

  test('logWater rejects ml <= 0', () async {
    final r = await NutritionWriteService.instance
        .logWater(date: DateTime(2026, 5, 1), ml: 0);
    expect(r.success, false);
  });
}
