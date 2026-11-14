// Diet plan Unit 1 (2026-11-14, docs/plans/diet-food-quality.md §3.3, §4):
// the curated generator's kill switch, DietPlanFlags.curatedEnabled.
//
// Behavioral: real Hive configBox in a temp dir — absent ⇒ curated, `true` ⇒
// legacy, an unopened box ⇒ curated (safe default). The screen routing is a
// PRESENCE pin (the screen is not pumped here; stated).
//
// Mutations: invert the getter's comparison (the first two tests redden);
// make _generateFreshPlan call one generator unconditionally (the pin reddens).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_flags.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  test('unopened box ⇒ curated (safe default)', () async {
    await Hive.close();
    expect(DietPlanFlags.curatedEnabled, isTrue);
  });

  group('with Hive', () {
    late Directory tempDir;
    setUp(() async => tempDir = await setUpHiveForTests());
    tearDown(() async => tearDownHiveForTests(tempDir));

    test('key absent ⇒ curated', () {
      expect(HiveService.instance.configBox
          .containsKey(DietPlanFlags.disableCuratedKey), isFalse);
      expect(DietPlanFlags.curatedEnabled, isTrue);
    });

    test('key true ⇒ legacy', () async {
      await HiveService.instance.configBox
          .put(DietPlanFlags.disableCuratedKey, true);
      expect(DietPlanFlags.curatedEnabled, isFalse);
    });

    test('key false ⇒ curated', () async {
      await HiveService.instance.configBox
          .put(DietPlanFlags.disableCuratedKey, false);
      expect(DietPlanFlags.curatedEnabled, isTrue);
    });
  });

  test('PRESENCE: _generateFreshPlan routes through the flag', () {
    final src = File('lib/features/nutrition/screens/diet_plan_screen.dart')
        .readAsStringSync();
    final body = src.substring(src.indexOf('void _generateFreshPlan'),
        src.indexOf('_MealPlan _servicePlanToScreenPlan'));
    expect(
        RegExp(r'DietPlanFlags\.curatedEnabled\s*\?\s*CuratedDietPlanGenerator\.instance\.generate\(inputs\)\s*:\s*DietPlanGenerator\.instance\.generate\(inputs\)')
            .hasMatch(body),
        isTrue);
    expect(body.contains('HiveService'), isFalse,
        reason: 'the screen must not read Hive directly (CLAUDE.md §4.4 r4)');
  });
}
