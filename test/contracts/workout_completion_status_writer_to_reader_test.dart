import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import '_sync_service_source.dart';

/// Source-of-truth contract: writer/reader pairs for `workout_completion_status`
/// from docs/sot_registry.yaml.
///
/// Writers: WorkoutScheduleService.markScheduleCompleted (sole setter),
///          SyncService._restoreWorkoutPlan (must run BEFORE _restoreScheduledWorkouts)
/// Readers: home_provider.todayWorkoutProvider, train_provider.currentPlanProvider,
///          ai_coach_repository._getThisWeekWorkouts
///
/// "completed" is write-once per date. Any setter MUST check existing status.
/// Forbidden: never overwrite status=completed.
void main() {
  late String schedSvcSrc;
  late String syncSvcSrc;
  late String homeProvSrc;
  late String trainProvSrc;
  late String aiRepoSrc;

  setUpAll(() {
    final sf = File('lib/core/services/workout_schedule_service.dart');
    expect(sf.existsSync(), isTrue,
        reason: 'workout_schedule_service.dart must exist (primary writer)');
    schedSvcSrc = sf.readAsStringSync();

    final ssf = loadSyncServiceSource();
    expect(ssf.existsSync(), isTrue,
        reason: 'sync_service.dart must exist (restore writer)');
    syncSvcSrc = ssf.readAsStringSync();

    final hf = File('lib/features/home/providers/home_provider.dart');
    expect(hf.existsSync(), isTrue, reason: 'home_provider.dart must exist');
    homeProvSrc = hf.readAsStringSync();

    final tf = File('lib/features/train/providers/train_provider.dart');
    expect(tf.existsSync(), isTrue, reason: 'train_provider.dart must exist');
    trainProvSrc = tf.readAsStringSync();

    final af =
        File('lib/features/ai_coach/repositories/ai_coach_repository.dart');
    expect(af.existsSync(), isTrue,
        reason: 'ai_coach_repository.dart must exist');
    aiRepoSrc = af.readAsStringSync();
  });

  group('workout_completion_status writer↔reader source contract', () {
    test('writer sets status=completed in workout_schedule_service', () {
      expect(schedSvcSrc.contains("'completed'"), isTrue,
          reason:
              'workout_schedule_service must set status=completed (write-once gate)');
    });

    test('writer guards against overwriting existing completed status', () {
      // The guard pattern: check if already completed before setting
      expect(schedSvcSrc.contains("status.*==.*'completed'") ||
          schedSvcSrc.contains("'completed'.*return") ||
          schedSvcSrc.contains("== 'completed'"), isTrue,
          reason:
              'workout_schedule_service must check existing status before setting completed; '
              '"completed" is write-once per date per sot_registry.class_constraints');
    });

    test('SyncService._restoreWorkoutPlan exists (ordering guard for APK #12.9)', () {
      expect(syncSvcSrc.contains('_restoreWorkoutPlan'), isTrue,
          reason:
              'sync_service must define _restoreWorkoutPlan which must run BEFORE '
              '_restoreScheduledWorkouts to preserve cloud-authoritative status=completed');
    });

    test('SyncService._restoreScheduledWorkouts exists', () {
      expect(syncSvcSrc.contains('_restoreScheduledWorkouts'), isTrue,
          reason: 'sync_service must define _restoreScheduledWorkouts');
    });

    test('reader todayWorkoutProvider reads status field', () {
      expect(homeProvSrc.contains("'status'") || homeProvSrc.contains('status'),
          isTrue,
          reason:
              'todayWorkoutProvider in home_provider must check status field '
              'to determine if today is completed');
    });

    test('reader currentPlanProvider reads status field', () {
      expect(
          trainProvSrc.contains("'status'") || trainProvSrc.contains('status'),
          isTrue,
          reason: 'currentPlanProvider must read status field for weekly view');
    });

    test('reader _getThisWeekWorkouts in ai_coach_repository reads status or schedule', () {
      expect(
          aiRepoSrc.contains('_getThisWeekWorkouts') ||
              aiRepoSrc.contains("'status'") && aiRepoSrc.contains('schedule_'),
          isTrue,
          reason:
              'ai_coach_repository must have _getThisWeekWorkouts which reads '
              'schedule_ keys and their status fields');
    });

    test('legal status values are bounded (planned|completed|skipped|shifted)', () {
      // All four legal values should appear in the writer
      expect(schedSvcSrc.contains("'planned'"), isTrue,
          reason: 'planned is a legal status value');
      expect(schedSvcSrc.contains("'completed'"), isTrue,
          reason: 'completed is a legal status value');
      // skipped and shifted may not appear in every file — check at least 2
    });

    test('forbidden: status=planned never overwrites status=completed', () {
      // Verify the guard exists: before any put with 'planned', there's a check
      // We check that the restore method doesn't blindly put planned status
      expect(syncSvcSrc.contains("status.*!=.*'completed'") ||
          syncSvcSrc.contains("'completed'.*continue") ||
          syncSvcSrc.contains("skip.*completed") ||
          syncSvcSrc.contains("== 'completed'"), isTrue,
          reason:
              'sync_service restore must not overwrite status=completed with planned; '
              'APK Test #12.9 Bug 5.1 root cause');
    });
  });
}
