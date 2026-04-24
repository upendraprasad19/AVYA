// Regression tests for sync gaps closed in fix/sync-gaps.
//
// SyncService uses a static `final _instance` singleton with a private
// constructor — it cannot be overridden via dependency injection without
// modifying production code. Therefore each test below is a regex-based
// structural assertion: it reads the production source file and asserts
// that the expected `unawaited(SyncService.instance.XYZ())` call is present.
//
// This gives us regression protection without production-code changes.
// If any of these tests fail, the sync call was accidentally removed.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _src(String relativePath) {
  // flutter test sets cwd to the project root.
  final file = File('${Directory.current.path}/$relativePath');
  return file.readAsStringSync();
}

void main() {
  group('sync gap — train_provider completeWorkout', () {
    test('fires pushSnapshot after syncWorkoutData + syncProgressNow', () {
      final src = _src(
          'lib/features/train/providers/train_provider.dart');
      expect(src, contains('unawaited(SyncService.instance.syncWorkoutData())'));
      expect(src, contains('unawaited(SyncService.instance.syncProgressNow())'));
      expect(src, contains('unawaited(SyncService.instance.pushSnapshot())'));
    });
  });

  group('sync gap — conversational_log_handler submitWorkoutDraft', () {
    test('fires syncWorkoutData + pushSnapshot at end of submitWorkoutDraft',
        () {
      final src = _src(
          'lib/features/ai_coach/services/conversational_log_handler.dart');
      expect(src, contains('unawaited(SyncService.instance.syncWorkoutData())'));
      expect(src, contains('unawaited(SyncService.instance.pushSnapshot())'));
    });

    test('fires pushSnapshot at end of _logSleep', () {
      final src = _src(
          'lib/features/ai_coach/services/conversational_log_handler.dart');
      // Verify the pushSnapshot call appears after the sleep_logs put
      final sleepIdx = src.indexOf("await healthBox.put('sleep_logs', logs)");
      final pushIdx =
          src.indexOf('unawaited(SyncService.instance.pushSnapshot())', sleepIdx);
      expect(sleepIdx, isNot(-1),
          reason: 'sleep_logs put must exist');
      expect(pushIdx, isNot(-1),
          reason: 'pushSnapshot must appear after sleep_logs put');
      expect(pushIdx > sleepIdx, isTrue);
    });

    test('fires pushSnapshot at end of _logMeasurement', () {
      final src = _src(
          'lib/features/ai_coach/services/conversational_log_handler.dart');
      final measIdx = src.indexOf("await healthBox.put(key, record)");
      final pushIdx =
          src.indexOf('unawaited(SyncService.instance.pushSnapshot())', measIdx);
      expect(measIdx, isNot(-1));
      expect(pushIdx, isNot(-1),
          reason: 'pushSnapshot must appear after measurement put');
      expect(pushIdx > measIdx, isTrue);
    });
  });

  group('sync gap — nutrition_provider DeleteNutritionLogNotifier.delete', () {
    test('fires syncNutritionData + pushSnapshot after invalidations', () {
      final src = _src(
          'lib/features/nutrition/providers/nutrition_provider.dart');
      // Find the delete method context
      final deleteIdx = src.indexOf('class DeleteNutritionLogNotifier');
      final syncIdx = src.indexOf(
          'unawaited(SyncService.instance.syncNutritionData())', deleteIdx);
      final pushIdx =
          src.indexOf('unawaited(SyncService.instance.pushSnapshot())', syncIdx);
      expect(deleteIdx, isNot(-1));
      expect(syncIdx, isNot(-1));
      expect(pushIdx, isNot(-1));
      expect(pushIdx > syncIdx, isTrue);
    });
  });

  group('sync gap — nutrition_provider SavedMealsNotifier.saveMealPreset', () {
    test('fires syncNutritionData + pushSnapshot after invalidateSelf', () {
      final src = _src(
          'lib/features/nutrition/providers/nutrition_provider.dart');
      final saveMealIdx = src.indexOf('Future<void> saveMealPreset(');
      final syncIdx = src.indexOf(
          'unawaited(SyncService.instance.syncNutritionData())', saveMealIdx);
      final pushIdx =
          src.indexOf('unawaited(SyncService.instance.pushSnapshot())', syncIdx);
      expect(saveMealIdx, isNot(-1));
      expect(syncIdx, isNot(-1));
      expect(pushIdx, isNot(-1));
    });
  });

  group('sync gap — nutrition_provider SavedMealsNotifier.deleteSavedMeal', () {
    test('fires syncNutritionData + pushSnapshot after invalidateSelf', () {
      final src = _src(
          'lib/features/nutrition/providers/nutrition_provider.dart');
      final deleteMealIdx = src.indexOf('Future<void> deleteSavedMeal(');
      final syncIdx = src.indexOf(
          'unawaited(SyncService.instance.syncNutritionData())', deleteMealIdx);
      final pushIdx =
          src.indexOf('unawaited(SyncService.instance.pushSnapshot())', syncIdx);
      expect(deleteMealIdx, isNot(-1));
      expect(syncIdx, isNot(-1));
      expect(pushIdx, isNot(-1));
    });
  });

  group('sync gap — nutrition_provider CustomFoodNotifier.addCustomFood', () {
    test('fires pushSnapshot after custom food write', () {
      final src = _src(
          'lib/features/nutrition/providers/nutrition_provider.dart');
      final addFoodIdx = src.indexOf('Future<void> addCustomFood(');
      final pushIdx =
          src.indexOf('unawaited(SyncService.instance.pushSnapshot())', addFoodIdx);
      expect(addFoodIdx, isNot(-1));
      expect(pushIdx, isNot(-1));
    });
  });

  group('sync gap — edit_profile_screen._save', () {
    test('fires pushSnapshot after syncProfileNow', () {
      final src = _src(
          'lib/features/profile/screens/edit_profile_screen.dart');
      final syncProfileIdx = src.indexOf('SyncService.instance.syncProfileNow(');
      final pushIdx =
          src.indexOf('unawaited(SyncService.instance.pushSnapshot())', syncProfileIdx);
      expect(syncProfileIdx, isNot(-1));
      expect(pushIdx, isNot(-1));
      expect(pushIdx > syncProfileIdx, isTrue);
    });
  });

  group('sync gap — profile_provider BiometricNotifier.logSleep', () {
    test('fires pushSnapshot after invalidateSelf in logSleep', () {
      final src = _src(
          'lib/features/profile/providers/profile_provider.dart');
      final logSleepIdx = src.indexOf(
          'Future<void> logSleep({required double hours, required String quality})');
      final pushIdx =
          src.indexOf('unawaited(SyncService.instance.pushSnapshot())', logSleepIdx);
      expect(logSleepIdx, isNot(-1));
      expect(pushIdx, isNot(-1));
    });
  });

  group('sync gap — swap_sheet._onConfirm', () {
    test('fires syncWorkoutData + pushSnapshot on successful swap', () {
      final src = _src('lib/features/home/widgets/swap_sheet.dart');
      expect(src, contains('unawaited(SyncService.instance.syncWorkoutData())'));
      expect(src, contains('unawaited(SyncService.instance.pushSnapshot())'));
    });
  });

  group('sync gap — ai_coach_repository extractAndSaveCoachingNotes', () {
    test('fires pushSnapshot after coachBox put', () {
      final src = _src(
          'lib/features/ai_coach/repositories/ai_coach_repository.dart');
      final coachPutIdx = src.indexOf("_hive.coachBox.put('coaching_notes'");
      final pushIdx =
          src.indexOf('unawaited(SyncService.instance.pushSnapshot())', coachPutIdx);
      expect(coachPutIdx, isNot(-1));
      expect(pushIdx, isNot(-1));
      expect(pushIdx > coachPutIdx, isTrue);
    });
  });

  group('sync gap — splash_screen checkAndSync wrapped with unawaited', () {
    test('checkAndSync is wrapped with unawaited', () {
      final src = _src('lib/features/auth/screens/splash_screen.dart');
      expect(src, contains('unawaited(SyncService.instance.checkAndSync())'));
    });
  });
}
