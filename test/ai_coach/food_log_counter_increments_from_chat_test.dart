// test/ai_coach/food_log_counter_increments_from_chat_test.dart
//
// B-11 pinned that a chat-mode food log decremented the same visible counter
// as the LogFood sheet AI tab (aiCoachTool -> featureAiTextLogPro).
// OI-493 Landing A reversed it: the coach's meal parse is not a
// food_text_analysis call, the server trigger never counts it, so the client
// increment drifted the "X remaining" count. aiCoachTool now maps to no
// counter (the mapping is documentation; nothing increments from it — the
// behavioral pin is P7 in coach_vs_screen_meal_log_parity_test.dart).
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

  test('NutritionWriteSource.aiCoachTool maps to no counter (OI-493)',
      () async {
    final feature = NutritionWriteService.counterFeatureForSource(
      NutritionWriteSource.aiCoachTool,
    );
    expect(feature, isNull,
        reason: 'a coach meal spends no AI-text unit: the server never '
            'counts the coach parse (OI-493 Landing A, D8).');
  });

  test('aiText source ALSO maps to featureAiTextLogPro (parity)', () async {
    final feature = NutritionWriteService.counterFeatureForSource(
      NutritionWriteSource.aiText,
    );
    expect(feature, AppConstants.featureAiTextLogPro);
  });

  test('UsageCounterService.increment advances the visible counter',
      () async {
    // Smoke-test the increment path the Nutrition screen's AI-text tab uses
    // (food_logger_section._analyse).
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
