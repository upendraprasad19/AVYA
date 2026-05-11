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
    test('routes through WorkoutWriteService + fires syncProgressNow', () {
      final src = _src(
          'lib/features/train/providers/train_provider.dart');
      // Plan A Task A-13: completeWorkout routes per-exercise saves +
      // schedule completion through WorkoutWriteService. The service
      // fires unawaited(SyncService.instance.syncWorkoutData()) +
      // pushSnapshot internally per write — train_provider only needs
      // to fire syncProgressNow (separate row, not in the write service).
      expect(src, contains('WorkoutWriteService.instance.logExercise'));
      expect(src, contains('WorkoutWriteService.instance.markCompleted'));
      expect(src, contains('unawaited(SyncService.instance.syncProgressNow())'));
    });
  });

  group('sync gap — conversational_log_handler submitWorkoutDraft', () {
    test('fires syncWorkoutData + pushSnapshot at end of submitWorkoutDraft',
        () {
      // C-8 (audit-2026-05-11) — submitWorkoutDraft now delegates to
      // WorkoutWriteService.logExercise + markCompleted. Each of those
      // fires `unawaited(SyncService.instance.syncWorkoutData())` +
      // `unawaited(SyncService.instance.pushSnapshot())` internally.
      // The handler keeps an additional defensive `pushSnapshot()`
      // call so the chat → confirmation → home transition has fresh
      // AI snapshot even when the WriteService onInvalidate hook
      // isn't wired.
      final handlerSrc = _src(
          'lib/features/ai_coach/services/conversational_log_handler.dart');
      expect(
        handlerSrc,
        contains('WorkoutWriteService.instance.logExercise('),
        reason:
            'submitWorkoutDraft must route per-exercise writes through '
            'WorkoutWriteService.logExercise so they inherit '
            'syncWorkoutData + pushSnapshot fan-out.',
      );
      expect(
        handlerSrc,
        contains('WorkoutWriteService.instance.markCompleted('),
        reason:
            'submitWorkoutDraft must route schedule-completion through '
            'WorkoutWriteService.markCompleted which fires '
            'syncWorkoutData + pushSnapshot.',
      );
      expect(handlerSrc,
          contains('unawaited(SyncService.instance.pushSnapshot())'),
          reason: 'Defensive pushSnapshot at end of submitWorkoutDraft.');

      // Verify the WriteService still funnels through syncWorkoutData +
      // pushSnapshot so the delegation actually preserves the contract.
      final writeSvc =
          _src('lib/core/services/workout_write_service.dart');
      expect(writeSvc,
          contains('unawaited(SyncService.instance.syncWorkoutData())'),
          reason:
              'WorkoutWriteService must call syncWorkoutData so chat-confirmed '
              'workouts reach cloud.');
      expect(writeSvc,
          contains('unawaited(SyncService.instance.pushSnapshot())'),
          reason:
              'WorkoutWriteService must call pushSnapshot so AI coach gets '
              'fresh workout context.');
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

  group('sync gap — NutritionWriteService.deleteLog', () {
    // Architectural shift since Test #6: the SyncService.syncNutritionData
    // call moved from inline-in-DeleteNutritionLogNotifier into
    // NutritionWriteService.deleteLog (which is what the notifier now
    // delegates to). Sync IS fired; only the owning file changed.
    // CLAUDE.md §15 sync fan-out contract: syncNutritionData() must be
    // called on every nutrition delete path.
    test(
      'fires syncNutritionData + pushSnapshot inside NutritionWriteService.deleteLog '
      '(architectural shift since Test #6 — sync moved from DeleteNutritionLogNotifier '
      'into the WriteService)',
      () {
        final src = _src(
            'lib/core/services/nutrition_write_service.dart');
        final deleteLogIdx = src.indexOf('Future<WriteResult> deleteLog(');
        expect(deleteLogIdx, greaterThan(0),
            reason: 'deleteLog method must exist on NutritionWriteService');
        // Bound the method body: find the next top-level method after deleteLog.
        final tail = src.substring(deleteLogIdx);
        final nextMethodIdx =
            tail.indexOf(RegExp(r'\n  Future<', multiLine: true), 1);
        final bodyEnd = nextMethodIdx > 0 ? nextMethodIdx : tail.length;
        final body = tail.substring(0, bodyEnd);
        expect(body, contains('syncNutritionData'),
            reason: 'deleteLog must fan out to syncNutritionData per '
                'CLAUDE.md §15 sync fan-out contract');
        expect(body, contains('pushSnapshot'),
            reason: 'deleteLog must also push AI snapshot per sync pattern');
      },
    );
  });

  group('sync gap — nutrition_provider SavedMealsNotifier.saveMealPreset', () {
    test('routes through NutritionWriteService.saveMealPreset', () {
      // C-12 (audit-2026-05-11) — Hive write + sync fan-out lifted
      // into NutritionWriteService. Notifier delegates; service fires
      // syncNutritionData + pushSnapshot.
      final notifierSrc = _src(
          'lib/features/nutrition/providers/nutrition_provider.dart');
      expect(
        notifierSrc.contains('Future<void> saveMealPreset('),
        isTrue,
        reason: 'saveMealPreset must still exist on the notifier',
      );
      // saveMealPreset is the only method in the file that delegates
      // to `NutritionWriteService.instance.saveMealPreset` — check the
      // whole-file source rather than a sliced body (multi-line param
      // blocks defeat the `\n  }` end-marker heuristic).
      expect(
        notifierSrc.contains('NutritionWriteService.instance.saveMealPreset('),
        isTrue,
        reason:
            'Notifier must route through NutritionWriteService.saveMealPreset '
            'so the Hive write + sync fan-out match the SoT contract.',
      );

      // Verify the service still funnels through sync.
      final svcSrc =
          _src('lib/core/services/nutrition_write_service.dart');
      expect(
        svcSrc,
        contains('unawaited(SyncService.instance.syncNutritionData())'),
        reason: 'WriteService must call syncNutritionData.',
      );
      expect(
        svcSrc,
        contains('unawaited(SyncService.instance.pushSnapshot())'),
        reason: 'WriteService must call pushSnapshot.',
      );
    });
  });

  group('sync gap — nutrition_provider SavedMealsNotifier.deleteSavedMeal', () {
    test('routes through NutritionWriteService.deleteSavedMeal', () {
      // C-12 — same pattern as saveMealPreset above.
      final notifierSrc = _src(
          'lib/features/nutrition/providers/nutrition_provider.dart');
      expect(
        notifierSrc.contains('Future<void> deleteSavedMeal('),
        isTrue,
        reason: 'deleteSavedMeal must still exist on the notifier',
      );
      expect(
        notifierSrc.contains('NutritionWriteService.instance.deleteSavedMeal('),
        isTrue,
        reason:
            'Notifier must route through NutritionWriteService.deleteSavedMeal.',
      );
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
