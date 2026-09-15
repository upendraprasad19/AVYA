// APK +43 obs 1 — AiBreakdownNotifier.saveMeal's catch block previously
// swallowed any exception from NutritionWriteService.instance.logMeal with
// only a debugPrint, so a founder-reported "Could not save — try again."
// snackbar (repeatedly, only on snack, never breakfast/lunch/dinner) left
// NOTHING in client_errors to diagnose it by. This test pins that the catch
// block now reports via ErrorTelemetry.recordNonFatal(reason:
// 'ai_breakdown_notifier_save_meal') whenever the real saveMeal() body
// throws — a real call through the real method body, not a source-grep.
//
// NutritionWriteService is a hard singleton with no DI seam, and every
// throw site INSIDE logMeal() is itself already wrapped by its own
// try/catch (Hive put, provider invalidate, sync fan-out) — so nothing in
// normal operation is known to organically escape to saveMeal's outer catch
// today (the diagnose-doc covers this trace; the original production
// trigger for Obs 1 remains unidentified — this fix adds observability for
// a recurrence, it does not claim to be a root-cause fix). The fault here is
// injected via `AiBreakdownNotifier.throwBeforeLogMealForTest`, a minimal
// test-only seam mirroring the existing `serviceFailCounts` /
// `resetCircuitBreakerForTests` seams already in this class, so this test
// exercises the REAL catch block + REAL ErrorTelemetry call. Contrast with
// test/features/nutrition/ai_breakdown_save_confirmation_test.dart, whose
// fake notifiers override `saveMeal` wholesale and so can never reach this
// catch block at all.
//
// Writer: nutrition_provider.dart AiBreakdownNotifier.saveMeal
// Reader: ErrorTelemetry.recordNonFatal -> client_errors
//         (op_type = 'ai_breakdown_notifier_save_meal')
//
// APK +43 obs 1 B-pass follow-up (docs/reviews/6f1e4db85459-review.md,
// finding 2, P3): the original "negative control" below only exercised
// saveMeal's `state == null` EARLY RETURN, which never reaches the try
// block at all — it would pass identically even if the whole fix were
// reverted, so it proved nothing about the catch block's silence on the
// actually-relevant path. Added a THIRD test that drives a REAL successful
// save through the REAL NutritionWriteService.instance.logMeal (real Hive,
// via the same nwsTestSetup/nwsTestTeardown helper the NutritionWriteService
// unit suite uses) with throwBeforeLogMealForTest left null, and asserts the
// telemetry hook never fires. THAT is the case that would have gone green
// silently if, say, the fix's `unawaited(ErrorTelemetry.recordNonFatal(...))`
// call had been placed outside the catch block by mistake.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';

import '../nutrition_write_service/helpers/nws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ErrorTelemetry.debugOnRecordNonFatalForTests = null;
    AiBreakdownNotifier.throwBeforeLogMealForTest = null;
  });

  tearDown(() {
    ErrorTelemetry.debugOnRecordNonFatalForTests = null;
    AiBreakdownNotifier.throwBeforeLogMealForTest = null;
  });

  test(
      '(APK +43 obs 1) saveMeal reports ErrorTelemetry.recordNonFatal with '
      'reason ai_breakdown_notifier_save_meal when logMeal throws',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(aiBreakdownProvider.notifier);
    notifier.state = const AiBreakdownData(
      mealName: 'Evening Snack',
      totalKcal: 180,
      items: [
        AiFoodItem(
          name: 'Peanuts',
          quantity: '30g',
          calories: 180,
          protein: '8g',
          carbs: '6g',
          fat: '14g',
          fiber: 2,
        ),
      ],
    );

    Object? capturedError;
    String? capturedReason;
    ErrorTelemetry.debugOnRecordNonFatalForTests =
        (error, stack, {required reason, extra}) {
      capturedError = error;
      capturedReason = reason;
    };

    final injected = StateError('simulated logMeal failure');
    AiBreakdownNotifier.throwBeforeLogMealForTest = injected;

    final result = await notifier.saveMeal(mealType: 'snacks');

    expect(result.success, isFalse,
        reason: 'a thrown exception must surface as a failed WriteResult');
    expect(capturedReason, 'ai_breakdown_notifier_save_meal',
        reason:
            'the catch block must report via ErrorTelemetry with this exact '
            'op_type so a recurrence is diagnosable in client_errors');
    expect(capturedError, same(injected));
  });

  test(
      '(APK +43 obs 1) saveMeal does NOT call ErrorTelemetry.recordNonFatal '
      'when state is null (early-return control, no try block reached)',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(aiBreakdownProvider.notifier);
    // No state set -> saveMeal short-circuits to WriteResult.noState()
    // BEFORE the try block. This is a weak control (see the file header) —
    // kept because it still pins the early-return shape, but the test below
    // is the one that actually exercises the catch block's silence.
    var called = false;
    ErrorTelemetry.debugOnRecordNonFatalForTests =
        (error, stack, {required reason, extra}) {
      called = true;
    };

    final result = await notifier.saveMeal(mealType: 'snacks');

    expect(result.isNoState, isTrue);
    expect(called, isFalse);
  });

  group('real Hive — REAL NutritionWriteService.instance.logMeal', () {
    setUp(nwsTestSetup);
    tearDown(nwsTestTeardown);

    test(
        '(APK +43 obs 1) saveMeal does NOT call ErrorTelemetry.recordNonFatal '
        'on a real successful save (real negative control)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(aiBreakdownProvider.notifier);
      notifier.state = const AiBreakdownData(
        mealName: 'Evening Snack',
        totalKcal: 180,
        items: [
          AiFoodItem(
            name: 'Peanuts',
            quantity: '30g',
            calories: 180,
            protein: '8g',
            carbs: '6g',
            fat: '14g',
            fiber: 2,
          ),
        ],
      );

      var called = false;
      ErrorTelemetry.debugOnRecordNonFatalForTests =
          (error, stack, {required reason, extra}) {
        called = true;
      };

      // throwBeforeLogMealForTest is left null by setUp -> the REAL
      // NutritionWriteService.instance.logMeal runs, against the real Hive
      // box set up by nwsTestSetup.
      final result = await notifier.saveMeal(mealType: 'snacks');

      expect(result.success, isTrue,
          reason: 'the real write must succeed for this to be a meaningful '
              'negative control');
      final nlogs = HiveService.instance.nutritionBox.keys
          .whereType<String>()
          .where((k) => k.startsWith('nlog_'))
          .toList();
      expect(nlogs, isNotEmpty,
          reason: 'the real Hive write must actually have happened');
      expect(called, isFalse,
          reason: 'a successful save must never call ErrorTelemetry — this '
              'is the case a misplaced recordNonFatal call (e.g. outside '
              'the catch block) would have broken');
    });
  });
}
