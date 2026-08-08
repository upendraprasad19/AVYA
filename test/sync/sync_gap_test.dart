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

    test('_logSleep routes through HealthWriteService.logSleep '
        '(audit-2026-05-16 F2-R3)', () {
      // Post-F2-R3 (closes-diagnose 2026-05-16-sleep-dual-key):
      // _logSleep no longer writes healthBox directly OR fires sync
      // calls inline. It delegates to HealthWriteService.logSleep —
      // same pattern _logMeasurement already follows per E.7 — and the
      // canonical writer fires syncSleepNow + pushSnapshot internally.
      // The pre-fix "direct write + adjacent pushSnapshot" pattern was
      // the dual-key writer asymmetry that surfaced as AI-logged sleep
      // being invisible to canonical per-day readers.
      final src = _src(
          'lib/features/ai_coach/services/conversational_log_handler.dart');
      expect(src.contains('HealthWriteService.instance.logSleep'), isTrue,
          reason: '_logSleep must delegate to HealthWriteService.logSleep '
              'so the canonical per-day key + sync fan-out are emitted by '
              'the WriteService, not by the caller.');
    });

    test('routes through HealthWriteService.logMeasurement (audit-2026-05-16 E.7)', () {
      // Post-E.7: _logMeasurement no longer writes healthBox directly.
      // It calls HealthWriteService.instance.logMeasurement which
      // internally fires syncMeasurementsNow + pushSnapshot. The
      // canonical sync emission point is the WriteService, not the
      // caller.
      final src = _src(
          'lib/features/ai_coach/services/conversational_log_handler.dart');
      expect(src.contains('HealthWriteService.instance.logMeasurement'), isTrue,
          reason: '_logMeasurement must route through '
              'HealthWriteService.logMeasurement (E.7 canonical writer).');
    });
  });

  group('sync gap — NutritionWriteService.deleteLog', () {
    // Architectural shift since Test #6: the SyncService.syncNutritionData
    // call moved from inline-in-DeleteNutritionLogNotifier into
    // NutritionWriteService.deleteLog (which is what the notifier now
    // delegates to). Sync IS fired; only the owning file changed.
    // docs/architecture/sync.md sync fan-out contract: syncNutritionData() must be
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
                'docs/architecture/sync.md sync fan-out contract');
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
    test('routes through HealthWriteService.logSleep (audit-2026-05-16 E.7)', () {
      // Post-E.7: BiometricNotifier.logSleep no longer writes healthBox
      // directly (closes F2-R2 IST drift + the F-A WriteService asymmetry).
      // It calls HealthWriteService.instance.logSleep which internally
      // fires syncSleepNow + pushSnapshot. Canonical sync emission point
      // is now the WriteService.
      final src = _src(
          'lib/features/profile/providers/profile_provider.dart');
      final logSleepIdx = src.indexOf(
          'Future<void> logSleep({required double hours, required String quality})');
      expect(logSleepIdx, isNot(-1));
      expect(src.contains('HealthWriteService.instance.logSleep'), isTrue,
          reason: 'BiometricNotifier.logSleep must route through '
              'HealthWriteService.logSleep (E.7 canonical writer). The '
              'WriteService bakes IST into the date key (closes F2-R2) and '
              'internally fires syncSleepNow + pushSnapshot.');
    });
  });

  group('sync gap — swap_sheet._onConfirm', () {
    test('fires syncWorkoutData + pushSnapshot on successful swap', () {
      final src = _src('lib/features/home/widgets/swap_sheet.dart');
      expect(src, contains('unawaited(SyncService.instance.syncWorkoutData())'));
      expect(src, contains('unawaited(SyncService.instance.pushSnapshot())'));
    });
  });

  group('sync gap — coach_memory_service.extractAndAppendCoachingNotes', () {
    test('fires pushSnapshotNow after coachBox put', () {
      // Tech-debt audit 2026-05-20 / A10 split ai_coach_repository.dart
      // (2127 LOC) into shim + 3 services. The coaching_notes WRITER
      // (extractCoachingNotes / extractAndAppendCoachingNotes) moved
      // into coach_memory_service.dart. The `coachBox.put('coaching_notes', ...)`
      // is at coach_memory_service.dart:138. Read both shim + new home.
      // H1b Part B1 (B-fix-2, 2026-06-28): the call is now the EAGER, durable
      // `pushSnapshotNow()` (bypasses the new pushSnapshot coalescer) — this is
      // the ONLY prompt sync of freshly-extracted coaching_notes, so it must not
      // be deferred to a coalescer trailing pass that could be lost.
      final paths = const [
        'lib/features/ai_coach/repositories/ai_coach_repository.dart',
        'lib/features/ai_coach/services/coach_memory_service.dart',
      ];
      final src = paths.map((p) => _src(p)).join('\n\n');
      final coachPutIdx = src.indexOf("coachBox.put('coaching_notes'");
      expect(coachPutIdx, isNot(-1),
          reason: 'coaching_notes write must exist in coach_memory_service '
              "(post-A10 split). Looked for `coachBox.put('coaching_notes'`.");
      final pushIdx = src.indexOf(
          'unawaited(SyncService.instance.pushSnapshotNow())', coachPutIdx);
      expect(pushIdx, isNot(-1),
          reason: 'pushSnapshotNow must fire after the coaching_notes write so '
              'the AI snapshot includes the freshly extracted notes (eager — '
              'not the coalesced pushSnapshot).');
      expect(pushIdx > coachPutIdx, isTrue);
    });
  });

  group('sync gap — splash_screen checkAndSync wrapped with unawaited', () {
    test('checkAndSync is wrapped with unawaited', () {
      // Tech-debt audit 2026-05-20 / A7 wrapped SyncService in a
      // Riverpod provider. Splash now calls
      // `unawaited(ref.read(syncServiceProvider).checkAndSync())` instead
      // of `unawaited(SyncService.instance.checkAndSync())`. Accept
      // either shape — both are valid "fire-and-forget checkAndSync"
      // calls. The invariant is "checkAndSync is not awaited", not the
      // particular accessor used.
      final src = _src('lib/features/auth/screens/splash_screen.dart');
      final hasSingletonForm = src
          .contains('unawaited(SyncService.instance.checkAndSync())');
      final hasProviderForm = RegExp(
              r'unawaited\(\s*ref\.read\(\s*syncServiceProvider\s*\)\.checkAndSync\(\s*\)\s*\)')
          .hasMatch(src);
      expect(hasSingletonForm || hasProviderForm, isTrue,
          reason: 'splash_screen must fire checkAndSync as fire-and-forget '
              '(unawaited(...)) via either SyncService.instance.checkAndSync() '
              '(legacy) or ref.read(syncServiceProvider).checkAndSync() '
              '(post-A7). Without unawaited, splash blocks on cloud round-trip.');
    });
  });
}
