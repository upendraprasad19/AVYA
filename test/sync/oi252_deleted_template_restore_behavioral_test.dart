// OI-252 (stable ID rework, unit 2a) — a deleted workout template must not
// resurrect via restore, on ANY of the three restore paths that can carry a
// reference to it: the direct `scheduled_workouts` embed
// (`_restoreScheduledWorkouts`), and the frozen `plan_json.schedules`
// snapshot (`_restoreWorkoutPlan` + `PlanIntegrityReconciler.reconcile`,
// which share the pure `isGhostScheduleEntry` predicate).
//
// Migration 145's `workout_templates_delete_final_rename` trigger renames +
// deactivates a deleted template rather than dropping its row, so the FK
// stays alive and the embed is normally present carrying `deleted_at`. Every
// case here therefore drives the fix via that embed / a pre-resolved
// deleted-id set — no live Supabase call, no dependency on migration 145
// actually being applied to the live database yet.
//
// closes-diagnose: 2026-09-27-template-delete-resurrects-via-restore-<id>
// BEHAVIORAL: seeds the real workoutBox + runs the REAL restore/merge code
// path (`restoreScheduledWorkoutsForTest` / `restoreWorkoutPlanForTest` —
// preFetched rows, no Supabase query). Each case FAILS against the pre-fix
// code (the row is written/hydrated/kept instead of dropped/cleaned).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/plan_integrity_reconciler.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/template_identity.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
    SyncService.pausedForSimulation = true;
  });

  tearDown(() async {
    SyncService.pausedForSimulation = false;
    await tearDownHiveForTests(tempDir);
  });

  const cloudId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  final hiveKey = templateKeyFor(cloudId);

  Map? scheduleRow(String dateKey) =>
      HiveService.instance.workoutBox.get('schedule_$dateKey') as Map?;

  group('_restoreScheduledWorkouts — deleted-template embed (OI-252)', () {
    test('deleted-embed row is never written (no hydration, no ghost day)',
        () async {
      const date = '2026-12-01';
      await SyncService.instance.restoreScheduledWorkoutsForTest(
        kTestUserId,
        preFetched: [
          {
            'scheduled_date': date,
            'status': 'planned',
            'completed_at': null,
            'week_number': null,
            'day_of_week': null,
            'template_id': cloudId,
            'template': {
              'id': cloudId,
              'name': 'Leg Day A ‹del:aaaaaaaa›',
              'workout_type': 'strength',
              'deleted_at': '2026-11-30T10:00:00Z',
              'template_exercises': [],
            },
          },
        ],
      );

      expect(scheduleRow(date), isNull,
          reason: 'a schedule day whose template is a tombstone must never '
              'be written — pre-fix this hydrated the mangled tombstone '
              'name/type and wrote the row anyway');
    });

    test('deleted-embed row cleans an existing local reference (today)',
        () async {
      final date = istTodayStr();
      await HiveService.instance.workoutBox.put('schedule_$date', {
        'date': date,
        'workout_name': 'Leg Day A',
        'type': 'custom_template',
        'template_id': hiveKey,
        'status': 'planned',
        'exercises': [
          {'exercise_name': 'Squat'},
        ],
      });

      await SyncService.instance.restoreScheduledWorkoutsForTest(
        kTestUserId,
        preFetched: [
          {
            'scheduled_date': date,
            'status': 'planned',
            'completed_at': null,
            'week_number': null,
            'day_of_week': null,
            'template_id': cloudId,
            'template': {
              'id': cloudId,
              'name': 'Leg Day A ‹del:aaaaaaaa›',
              'workout_type': 'strength',
              'deleted_at': '2026-11-30T10:00:00Z',
              'template_exercises': [],
            },
          },
        ],
      );

      expect(scheduleRow(date), isNull,
          reason: 'the pre-existing local schedule reference to the deleted '
              'template must be cleaned, not left pointing at a tombstone — '
              'pre-fix this local row survived untouched');
    });

    test('live-embed row writes template_id in the tmpl_<uuid> Hive-key '
        'form, never the raw cloud uuid', () async {
      const date = '2026-12-02';
      await SyncService.instance.restoreScheduledWorkoutsForTest(
        kTestUserId,
        preFetched: [
          {
            'scheduled_date': date,
            'status': 'planned',
            'completed_at': null,
            'week_number': null,
            'day_of_week': null,
            'template_id': cloudId,
            'template': {
              'id': cloudId,
              'name': 'Push A',
              'workout_type': 'strength',
              'deleted_at': null,
              'template_exercises': [],
            },
          },
        ],
      );

      final row = scheduleRow(date);
      expect(row, isNotNull);
      expect(row!['template_id'], hiveKey,
          reason: 'the LOCAL representation must always be the stable '
              'tmpl_<uuid> key — pre-fix this wrote the raw cloud uuid, '
              'which every other local reader (e.g. cleanSyncTemplateSchedule) '
              'compares against the Hive-key form and would never match');
      expect(row['workout_name'], 'Push A');
    });
  });

  group('_restoreWorkoutPlan — plan_json ghost-day filter (OI-252)', () {
    Map<String, dynamic> planJsonBundle(String date, {String? templateId}) => {
          'plan_json': {
            'plan': null,
            'plan_start_date': null,
            'plan_end_date': null,
            'schedules': {
              'schedule_$date': {
                'date': date,
                'workout_name':
                    templateId != null ? 'From snapshot' : 'Rest',
                'type': templateId != null ? 'custom_template' : 'rest',
                if (templateId != null) 'template_id': templateId,
                'status': 'planned',
              },
            },
          },
        };

    test('a day scheduled against a deleted template is dropped, never '
        'written', () async {
      const date = '2026-12-10';
      await SyncService.instance.restoreWorkoutPlanForTest(
        kTestUserId,
        preFetched: [planJsonBundle(date, templateId: hiveKey)],
        preFetchedDeletedTemplateIds: {cloudId},
      );

      expect(scheduleRow(date), isNull,
          reason: 'a frozen plan_json snapshot must not resurrect a day '
              'scheduled against a since-deleted template — pre-fix this '
              'wrote the ghost day verbatim');
    });

    test('a day scheduled against a LIVE template is written normally',
        () async {
      const date = '2026-12-11';
      await SyncService.instance.restoreWorkoutPlanForTest(
        kTestUserId,
        preFetched: [planJsonBundle(date, templateId: hiveKey)],
        preFetchedDeletedTemplateIds: const {},
      );

      final row = scheduleRow(date);
      expect(row, isNotNull);
      expect(row!['workout_name'], 'From snapshot');
    });

    test('a plain rest day (no template_id) is unaffected by the filter',
        () async {
      const date = '2026-12-12';
      await SyncService.instance.restoreWorkoutPlanForTest(
        kTestUserId,
        preFetched: [planJsonBundle(date)],
        preFetchedDeletedTemplateIds: {cloudId},
      );

      final row = scheduleRow(date);
      expect(row, isNotNull);
      expect(row!['workout_name'], 'Rest');
    });
  });

  group('isGhostScheduleEntry — pure predicate', () {
    test('no template_id → false', () {
      expect(isGhostScheduleEntry({'workout_name': 'Rest'}, {cloudId}),
          isFalse);
    });

    test('legacy (non tmpl_<uuid>) key → false (cannot resolve a cloud id)',
        () {
      expect(
          isGhostScheduleEntry(
              {'template_id': 'tmpl_1234567890'}, {cloudId}),
          isFalse);
    });

    test('template_id present, cloud id NOT in the deleted set → false', () {
      expect(isGhostScheduleEntry({'template_id': hiveKey}, const {}),
          isFalse);
    });

    test('template_id present, cloud id IS in the deleted set → true', () {
      expect(isGhostScheduleEntry({'template_id': hiveKey}, {cloudId}),
          isTrue);
    });
  });
}
