// test/ai_coach/food_log_counter_increments_from_chat_test.dart
//
// B-11: pin the contract that chat-mode food log decrements the same
// visible counter as the LogFood sheet AI tab. The increment is wired
// centrally inside NutritionWriteService — passing
// NutritionWriteSource.aiCoachTool maps to featureAiTextLogPro. This
// test asserts that mapping (the source-of-truth) so any future drift
// fails fast.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/nutrition_write_source.dart';
import 'package:icanbefitter/core/services/usage_counter_service.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  test('NutritionWriteSource.aiCoachTool maps to featureAiTextLogPro',
      () async {
    final feature = NutritionWriteService.counterFeatureForSource(
      NutritionWriteSource.aiCoachTool,
    );
    expect(feature, AppConstants.featureAiTextLogPro,
        reason:
            'aiCoachTool source must increment featureAiTextLogPro so the '
            'chat-mode food log decrements the same counter as the LogFood '
            'sheet AI tab (spec §5.5 obs #15).');
  });

  test('aiText source ALSO maps to featureAiTextLogPro (parity)', () async {
    final feature = NutritionWriteService.counterFeatureForSource(
      NutritionWriteSource.aiText,
    );
    expect(feature, AppConstants.featureAiTextLogPro);
  });

  test('UsageCounterService.increment advances the visible counter',
      () async {
    // Smoke-test the increment path that NutritionWriteService.logMeal
    // calls after a successful aiCoachTool write. We bypass the writer
    // and increment directly — the wiring contract is pinned by the
    // mapping test above.
    HiveService.instance.configBox; // ensure box is open
    const isPro = false;

    final before = UsageCounterService.instance.used(
      AppConstants.featureAiTextLogPro,
      isPro,
    );
    await UsageCounterService.instance.increment(
      AppConstants.featureAiTextLogPro,
      isPro,
    );
    final after = UsageCounterService.instance.used(
      AppConstants.featureAiTextLogPro,
      isPro,
    );
    expect(after, before + 1);
  });

  test('prelog source intentionally returns null (no counter burn)',
      () async {
    // Spec: speculative pre-logs should NOT burn the daily AI text quota
    // until the user confirms. Pinning this so a future "fix" doesn't
    // accidentally start charging the meter on prelog writes.
    final feature = NutritionWriteService.counterFeatureForSource(
      NutritionWriteSource.prelog,
    );
    expect(feature, isNull);
  });
}
