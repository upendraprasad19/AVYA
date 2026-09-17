// C2 (ai-coach-ux-tool-integrity spec 2026-09-18) — reschedule_week must
// write TERMINAL source rows, not raw deletes.
//
// THE BUG (pre-fix): _executeRescheduleWeek's move path wrote the destination
// via WorkoutWriteService.upsertScheduled then RAW-DELETED the source
// schedule_<fromDate>; the drop path raw-deleted too. A raw delete:
//   (a) punches a HOLE in the streak walk-back (the walker breaks
//       unconditionally on a null row — freeze-proof; diagnose c1a9d4/C1
//       registered 'moved'/'dropped' as invisible statuses but nothing WROTE
//       them), and
//   (b) never reaches cloud — a restore resurrects the workout on BOTH dates.
//
// THE FIX: the source row is re-stamped in place via upsertScheduled —
//   move: status='moved' + moved_to + moved_via='ai_coach' + moved_at
//   drop: status='dropped' + dropped_via='ai_coach' + dropped_at
// and partial exlog_<fromDate>_* rows are re-keyed onto the destination date
// via the canonical WorkoutWriteService.exlogKey (UUID-v5 hash, H-16 — NOT
// the dead name.hashCode scheme the plan sketch quoted).
//
// Each test below FAILS against the pre-fix raw-delete behavior.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';
import 'package:icanbefitter/features/ai_coach/services/reschedule_week_planner.dart';
import 'package:icanbefitter/features/ai_coach/services/tool_dispatcher.dart';

import '../helpers/hive_test_setup.dart';

/// Exposes a real Riverpod [Ref] to the test so we can drive
/// `ToolDispatcher.execute(ref, intent)` — the REAL dispatch path.
final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
    // Keep the dispatch hermetic: execute()'s fire-and-forget
    // syncWorkoutData()/pushSnapshot() short-circuit under this flag.
    SyncService.pausedForSimulation = true;
  });

  tearDown(() async {
    SyncService.pausedForSimulation = false;
    await tearDownHiveForTests(tempDir);
  });

  final today = nowWall();
  final fromDate = istDateStr(today);
  final toDate = istDateStr(today.add(const Duration(days: 1)));

  ToolIntent buildRescheduleIntent(String id) => ToolIntent(
        id: id,
        type: 'reschedule_week',
        payload: const <String, dynamic>{},
        confirmationClass: ConfirmationClass.destructive,
        previewSummary: 'Move Push A',
        createdAt: DateTime.now(),
      );

  Future<ToolExecutionResult> dispatch(String intentId) {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ref = container.read(_refProvider);
    return ToolDispatcher.instance.execute(
      ref,
      buildRescheduleIntent(intentId),
    );
  }

  Map? scheduleRow(String dateStr) =>
      HiveService.instance.workoutBox.get('schedule_$dateStr') as Map?;

  group('C2 — reschedule_week terminal rows replace raw deletes', () {
    test(
      'move path: source row STAYS as a moved terminal row (not deleted)',
      () async {
        await HiveService.instance.workoutBox.put('schedule_$fromDate', {
          'date': fromDate,
          'workout_name': 'Push A',
          'status': 'planned',
          'type': 'custom_template',
          'exercises': [
            {'exercise_name': 'Bench Press'},
          ],
        });

        RescheduleWeekPlanner.instance.cache('mv_int_1', [
          RescheduleMove(
            fromDate: fromDate,
            toDate: toDate,
            action: RescheduleAction.move,
            workoutName: 'Push A',
          ),
        ]);

        final result = await dispatch('mv_int_1');
        expect(result.success, isTrue, reason: 'dispatch must succeed');

        // (a) source row still EXISTS with the terminal 'moved' stamp.
        final src = scheduleRow(fromDate);
        expect(src, isNotNull,
            reason: 'pre-fix the source row was raw-deleted — a hole in the '
                'streak walk. Post-fix it must remain as a terminal row.');
        expect(src!['status'], 'moved');
        expect(src['moved_to'], toDate);
        expect(src['moved_via'], 'ai_coach');
        expect(src['moved_at'], isNotNull);

        // (b) destination row is planned on the new date.
        final dest = scheduleRow(toDate);
        expect(dest, isNotNull);
        expect(dest!['status'], 'planned');
        expect(dest['date'], toDate);
        expect(dest['workout_name'], 'Push A');
      },
    );

    test(
      'move path: partial exlog_<from> row re-keys onto the destination date',
      () async {
        await HiveService.instance.workoutBox.put('schedule_$fromDate', {
          'date': fromDate,
          'workout_name': 'Push A',
          'status': 'planned',
          'type': 'custom_template',
          'exercises': [
            {'exercise_name': 'Bench Press'},
          ],
        });
        final oldKey = WorkoutWriteService.exlogKey(today, 'Bench Press');
        final newKey =
            WorkoutWriteService.exlogKey(today.add(const Duration(days: 1)),
                'Bench Press');
        await HiveService.instance.workoutBox.put(oldKey, {
          'date': fromDate,
          'exercise_name': 'Bench Press',
          'sets': [
            {'weight_kg': 60.0, 'reps': 8},
          ],
        });

        RescheduleWeekPlanner.instance.cache('mv_int_2', [
          RescheduleMove(
            fromDate: fromDate,
            toDate: toDate,
            action: RescheduleAction.move,
            workoutName: 'Push A',
          ),
        ]);

        final result = await dispatch('mv_int_2');
        expect(result.success, isTrue);

        final moved = HiveService.instance.workoutBox.get(newKey) as Map?;
        expect(moved, isNotNull,
            reason: 'the partial log must travel with the day');
        expect(moved!['date'], toDate);
        expect(moved['exercise_name'], 'Bench Press');
        expect(HiveService.instance.workoutBox.get(oldKey), isNull,
            reason: 'the old-date key must be gone after the re-key');
      },
    );

    test(
      'drop path: source row STAYS as a dropped terminal row (not deleted)',
      () async {
        await HiveService.instance.workoutBox.put('schedule_$fromDate', {
          'date': fromDate,
          'workout_name': 'Legs B',
          'status': 'planned',
          'type': 'custom_template',
          'exercises': [
            {'exercise_name': 'Squat'},
          ],
        });

        RescheduleWeekPlanner.instance.cache('dr_int_1', [
          RescheduleMove(
            fromDate: fromDate,
            action: RescheduleAction.drop,
            workoutName: 'Legs B',
          ),
        ]);

        final result = await dispatch('dr_int_1');
        expect(result.success, isTrue, reason: 'dispatch must succeed');

        final src = scheduleRow(fromDate);
        expect(src, isNotNull,
            reason: 'pre-fix the source row was raw-deleted. Post-fix it must '
                'remain as a terminal dropped row.');
        expect(src!['status'], 'dropped');
        expect(src['dropped_via'], 'ai_coach');
        expect(src['dropped_at'], isNotNull);
      },
    );

    test(
      'no-op self-move guard: fromDate == toDate never writes a moved row',
      () async {
        await HiveService.instance.workoutBox.put('schedule_$fromDate', {
          'date': fromDate,
          'workout_name': 'Push A',
          'status': 'planned',
          'type': 'custom_template',
          'exercises': [],
        });

        RescheduleWeekPlanner.instance.cache('mv_same_1', [
          RescheduleMove(
            fromDate: fromDate,
            toDate: fromDate,
            action: RescheduleAction.move,
            workoutName: 'Push A',
          ),
        ]);

        final result = await dispatch('mv_same_1');
        expect(result.success, isTrue);

        final row = scheduleRow(fromDate);
        expect(row, isNotNull);
        expect(row!['status'], 'planned',
            reason: 'a same-date move must not stamp the terminal moved '
                'status over a live plan (fromDate != toDate guard)');
      },
    );
  });

  group('C2 review — planner never re-plans terminal rows (e8f4a3)', () {
    // Issue 2: RescheduleWeekPlanner's protection checks only skipped
    // completed/paused, so a SECOND reschedule in the same week re-planned
    // (moved/dropped) the terminal rows C2 had just written. Terminal rows
    // are audit placeholders — the workout lives elsewhere now (or was
    // dropped). MUTATION PROOF: removing the isInvisibleToStreak skip in
    // RescheduleWeekPlanner.plan reddens both tests below.
    test(
      'a moved row is skipped entirely; a planned row still plans normally',
      () async {
        final monday = DateTime(today.year, today.month, today.day)
            .subtract(Duration(days: (today.weekday - 1) % 7));
        final mondayStr = istDateStr(monday);
        final wednesday = monday.add(const Duration(days: 2));
        final wednesdayStr = istDateStr(wednesday);
        final friday = monday.add(const Duration(days: 4));

        await HiveService.instance.workoutBox.put('schedule_$mondayStr', {
          'date': mondayStr,
          'week': 1,
          'day_of_week': 0,
          'workout_name': 'Push A',
          'status': 'moved',
          'type': 'custom_template',
          'moved_to': wednesdayStr,
          'moved_via': 'ai_coach',
          'moved_at': DateTime.now().toIso8601String(),
          'exercises': [
            {'exercise_name': 'Bench Press'},
          ],
        });
        await HiveService.instance.workoutBox.put('schedule_$wednesdayStr', {
          'date': wednesdayStr,
          'week': 1,
          'day_of_week': 2,
          'workout_name': 'Pull B',
          'status': 'planned',
          'type': 'custom_template',
          'exercises': [
            {'exercise_name': 'Row'},
          ],
        });

        final moves = await RescheduleWeekPlanner.instance.plan(
          daysAvailable: [3, 5], // Wed + Fri (weekday numbers, Mon=1)
          weekStart: mondayStr,
        );

        expect(
          moves.where((m) => m.fromDate == mondayStr),
          isEmpty,
          reason: 'the terminal moved row must not appear in the plan at all '
              '— pre-fix it was re-planned (moved onto the free available '
              'day) on a second reschedule of the same week.',
        );
        expect(
          moves.any((m) => m.action == RescheduleAction.drop),
          isFalse,
          reason: 'a terminal row must never be dropped by the planner.',
        );
        expect(
          moves.any((m) =>
              m.fromDate == wednesdayStr && m.action == RescheduleAction.keep),
          isTrue,
          reason: 'the live planned row on an available day must still be '
              'kept — the skip is scoped to terminal rows only.',
        );
        // The moved row must not occupy the free Friday slot either.
        expect(
          moves.any((m) => m.toDate == istDateStr(friday)),
          isFalse,
          reason: 'the planner must not relocate anything onto a day because '
              'a terminal row pretended to be a live workout.',
        );
      },
    );

    test('a dropped row is skipped entirely', () async {
      final monday = DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: (today.weekday - 1) % 7));
      final mondayStr = istDateStr(monday);

      await HiveService.instance.workoutBox.put('schedule_$mondayStr', {
        'date': mondayStr,
        'week': 1,
        'day_of_week': 0,
        'workout_name': 'Legs B',
        'status': 'dropped',
        'type': 'custom_template',
        'dropped_via': 'ai_coach',
        'dropped_at': DateTime.now().toIso8601String(),
        'exercises': [
          {'exercise_name': 'Squat'},
        ],
      });

      final moves = await RescheduleWeekPlanner.instance.plan(
        daysAvailable: [2],
        weekStart: mondayStr,
      );

      expect(moves.where((m) => m.fromDate == mondayStr), isEmpty,
          reason: 'a terminal dropped row must never be re-planned (pre-fix '
              'it was moved to the available day or dropped again).');
    });
  });
}
