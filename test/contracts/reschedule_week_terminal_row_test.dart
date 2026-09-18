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
import 'package:icanbefitter/core/services/workout_read_service.dart';
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

  group('C2 review round 1 — move index maintenance + collision + wlog re-stamp (e8f4a3)', () {
    // FINDING 1 (HIGH): moveExerciseLogs re-keyed rows with raw box.put but
    // never touched exercise_log_index_<date>. The canonical read
    // exerciseLogsForIstDate is INDEX-FIRST and early-returns on a resolvable
    // non-empty destination index — so on a destination date that ALREADY had
    // logs, the moved rows were invisible, and the source date's index kept
    // dangling keys.
    test(
      'move onto a date that already has logs: canonical read returns BOTH '
      'rows; source index drops the moved key; wlog re-stamped',
      () async {
        final box = HiveService.instance.workoutBox;
        await box.put('schedule_$fromDate', {
          'date': fromDate,
          'workout_name': 'Push A',
          'status': 'planned',
          'type': 'custom_template',
          'exercises': [
            {'exercise_name': 'Bench Press'},
          ],
        });

        // Destination date ALREADY has a log (what logExercise produces:
        // exlog row + its exercise_log_index_<date> entry).
        final destKey = WorkoutWriteService.exlogKey(
            today.add(const Duration(days: 1)), 'Squat');
        await box.put(destKey, {
          'date': toDate,
          'exercise_name': 'Squat',
          'workout_log_id': 'wlog_$toDate',
          'sets': [
            {'weight_kg': 100.0, 'reps': 5},
          ],
          'set_number': 1,
        });
        await box.put('exercise_log_index_$toDate', [destKey]);

        // Source date partial log + index entry.
        final oldKey = WorkoutWriteService.exlogKey(today, 'Bench Press');
        final newKey = WorkoutWriteService.exlogKey(
            today.add(const Duration(days: 1)), 'Bench Press');
        await box.put(oldKey, {
          'date': fromDate,
          'exercise_name': 'Bench Press',
          'workout_log_id': 'wlog_$fromDate',
          'sets': [
            {'weight_kg': 60.0, 'reps': 8},
          ],
          'set_number': 1,
        });
        await box.put('exercise_log_index_$fromDate', [oldKey]);

        RescheduleWeekPlanner.instance.cache('mv_idx_1', [
          RescheduleMove(
            fromDate: fromDate,
            toDate: toDate,
            action: RescheduleAction.move,
            workoutName: 'Push A',
          ),
        ]);

        final result = await dispatch('mv_idx_1');
        expect(result.success, isTrue);

        // (a) Canonical read sees BOTH rows on the destination date —
        // pre-fix the destination index (non-empty) early-returned with
        // only Squat and the moved Bench Press was invisible.
        final read = WorkoutReadService.instance.exerciseLogsForIstDate(toDate);
        final names = read.map((r) => r['exercise_name']).toSet();
        expect(names, containsAll(<String>['Squat', 'Bench Press']),
            reason: 'the moved row must be visible through the canonical '
                'INDEX-FIRST read even when the destination date already '
                'had logs');

        // (b) Destination index lists the new key; source index dropped
        // the moved key (no dangling entry).
        final toIndex =
            (box.get('exercise_log_index_$toDate') as List?)?.cast<String>();
        final fromIndex =
            (box.get('exercise_log_index_$fromDate') as List?)?.cast<String>();
        expect(toIndex, contains(newKey));
        expect(fromIndex ?? const <String>[], isNot(contains(oldKey)),
            reason: 'the source date index must not keep the moved key');

        // (c) FINDING 4 — workout_log_id re-stamped to the destination's
        // canonical wlog key (receipt scopes by workoutLogId; carrying the
        // source's wlog_<fromDate> excluded the moved rows).
        final moved = box.get(newKey) as Map?;
        expect(moved, isNotNull);
        expect(moved!['workout_log_id'], 'wlog_$toDate');
      },
    );

    // FINDING 3 (MED): the raw box.put(exlogKey(toDate, name), row)
    // OVERWROTE an existing destination log for the same exercise name.
    // Fix: merge — append the moved row's sets[] to the existing row's
    // sets, keep the existing row's workout_log_id, and recompute the
    // simple set-derived aggregates so the row stays self-consistent
    // (logExercise's own contract: set_number/reps_completed/weight_kg/
    // volume_kg all derive from sets[] — leaving stale ones would be the
    // exact writer/reader drift class this fix exists to kill).
    test(
      'move collision: same-exercise destination log MERGES sets, keeps its '
      'own workout_log_id',
      () async {
        final box = HiveService.instance.workoutBox;
        await box.put('schedule_$fromDate', {
          'date': fromDate,
          'workout_name': 'Push A',
          'status': 'planned',
          'type': 'custom_template',
          'exercises': [
            {'exercise_name': 'Bench Press'},
          ],
        });

        final destKey = WorkoutWriteService.exlogKey(
            today.add(const Duration(days: 1)), 'Bench Press');
        final oldKey = WorkoutWriteService.exlogKey(today, 'Bench Press');
        await box.put(destKey, {
          'date': toDate,
          'exercise_name': 'Bench Press',
          'workout_log_id': 'wlog_dest_session',
          'sets': [
            {'weight_kg': 80.0, 'reps': 6},
          ],
          'set_number': 1,
          'reps_completed': 6,
          'weight_kg': 80.0,
          'volume_kg': 480.0,
        });
        await box.put('exercise_log_index_$toDate', [destKey]);
        await box.put(oldKey, {
          'date': fromDate,
          'exercise_name': 'Bench Press',
          'workout_log_id': 'wlog_$fromDate',
          'sets': [
            {'weight_kg': 60.0, 'reps': 8},
            {'weight_kg': 62.5, 'reps': 6},
          ],
          'set_number': 2,
          'reps_completed': 14,
          'weight_kg': 62.5,
          'volume_kg': 855.0,
        });
        await box.put('exercise_log_index_$fromDate', [oldKey]);

        RescheduleWeekPlanner.instance.cache('mv_col_1', [
          RescheduleMove(
            fromDate: fromDate,
            toDate: toDate,
            action: RescheduleAction.move,
            workoutName: 'Push A',
          ),
        ]);

        final result = await dispatch('mv_col_1');
        expect(result.success, isTrue);

        final merged = box.get(destKey) as Map?;
        expect(merged, isNotNull);
        final sets = (merged!['sets'] as List).cast<Map>();
        expect(sets.length, 3,
            reason: 'pre-fix the moved row OVERWROTE the destination log — '
                'its 1 set replaced the destination\'s existing set');
        expect(merged['set_number'], 3);
        expect(merged['reps_completed'], 20); // 6 + 8 + 6
        expect(merged['weight_kg'], 80.0);
        expect(merged['volume_kg'], 480.0 + 480.0 + 375.0);
        expect(merged['workout_log_id'], 'wlog_dest_session',
            reason: 'the existing destination row owns the day\'s session — '
                'the merge must NOT adopt the moved row\'s source wlog id');
        expect(box.get(oldKey), isNull, reason: 'source row still consumed');
        // Canonical read still resolves through the index.
        final read = WorkoutReadService.instance.exerciseLogsForIstDate(toDate);
        expect(read.map((r) => r['exercise_name']), contains('Bench Press'));
      },
    );
  });

  group('C2 review round 2 — restore-shaped merge preserves aggregates (e8f4a3 B1)', () {
    // FINDING B1 (MED): the round-1 collision merge recomputed the four
    // aggregates from `existingSets + movedSets`. But the restore writer
    // (sync_workout.dart _restoreExerciseLogs) emits exlog rows with
    // TOP-LEVEL aggregates and NO `sets[]` when the workout_log_sets join
    // is empty. Colliding a move into such a row recomputed DOWNWARD
    // (set_number 3→1, reps 30→8 …) — silent data loss on real user rows.
    // Fix: preserve-don't-shrink — a side with no `sets[]` contributes its
    // own top-level aggregates.
    test(
      'move collision into a RESTORE-SHAPED destination row GROWS the '
      'aggregates (existing 3 sets kept + moved 1 set added)',
      () async {
        final box = HiveService.instance.workoutBox;
        await box.put('schedule_$fromDate', {
          'date': fromDate,
          'workout_name': 'Push A',
          'status': 'planned',
          'type': 'custom_template',
          'exercises': [
            {'exercise_name': 'Bench Press'},
          ],
        });

        final destKey = WorkoutWriteService.exlogKey(
            today.add(const Duration(days: 1)), 'Bench Press');
        final oldKey = WorkoutWriteService.exlogKey(today, 'Bench Press');
        // Restore-shaped destination: top-level aggregates, NO `sets[]` —
        // exactly the row shape sync_workout.dart writes when the
        // workout_log_sets join is empty.
        await box.put(destKey, {
          'date': toDate,
          'exercise_name': 'Bench Press',
          'workout_log_id': 'wlog_$toDate',
          'set_number': 3,
          'reps_completed': 30,
          'weight_kg': 80.0,
          'volume_kg': 720.0,
        });
        await box.put('exercise_log_index_$toDate', [destKey]);
        // Moved row from the local writer: sets[] present.
        await box.put(oldKey, {
          'date': fromDate,
          'exercise_name': 'Bench Press',
          'workout_log_id': 'wlog_$fromDate',
          'sets': [
            {'weight_kg': 60.0, 'reps': 8},
          ],
          'set_number': 1,
          'reps_completed': 8,
          'weight_kg': 60.0,
          'volume_kg': 480.0,
        });
        await box.put('exercise_log_index_$fromDate', [oldKey]);

        RescheduleWeekPlanner.instance.cache('mv_col_2', [
          RescheduleMove(
            fromDate: fromDate,
            toDate: toDate,
            action: RescheduleAction.move,
            workoutName: 'Push A',
          ),
        ]);

        final result = await dispatch('mv_col_2');
        expect(result.success, isTrue);

        final merged = box.get(destKey) as Map?;
        expect(merged, isNotNull);
        // Pre-fix the unconditional recompute from mergedSets shrank every
        // aggregate to the moved row's single set (set_number 1, reps 8,
        // volume 480) — the restore-shaped 3 sets / 30 reps / 720 volume
        // were silently dropped.
        expect(merged!['set_number'], 4,
            reason: 'existing restore aggregate 3 + moved 1 set = 4 — the '
                'merge must never shrink below the pre-move totals');
        expect(merged['reps_completed'], 38, reason: '30 existing + 8 moved');
        expect(merged['weight_kg'], 80.0, reason: 'max(80 existing, 60 moved)');
        expect(merged['volume_kg'], 720.0 + 480.0);
        expect((merged['sets'] as List).length, 1,
            reason: 'only the moved side carries per-set detail — the '
                'restore-shaped side had none to contribute');
        expect(merged['workout_log_id'], 'wlog_$toDate',
            reason: 'the destination row still owns the session');
        expect(box.get(oldKey), isNull, reason: 'source row still consumed');
      },
    );
  });

  group('C2 review round 1 — destination terminal guard + stale prompt (e8f4a3)', () {
    // FINDING 6 (LOW): the destination guard refused completed/paused but
    // not terminal rows — moving onto a day that was itself moved/dropped
    // elsewhere clobbered the terminal stamp.
    test('move onto a TERMINAL destination is refused', () async {
      await HiveService.instance.workoutBox.put('schedule_$fromDate', {
        'date': fromDate,
        'workout_name': 'Push A',
        'status': 'planned',
        'type': 'custom_template',
        'exercises': [],
      });
      await HiveService.instance.workoutBox.put('schedule_$toDate', {
        'date': toDate,
        'workout_name': 'Legs B',
        'status': 'moved',
        'type': 'custom_template',
        'moved_to': istDateStr(today.add(const Duration(days: 2))),
        'exercises': [],
      });

      RescheduleWeekPlanner.instance.cache('mv_term_1', [
        RescheduleMove(
          fromDate: fromDate,
          toDate: toDate,
          action: RescheduleAction.move,
          workoutName: 'Push A',
        ),
      ]);

      final result = await dispatch('mv_term_1');
      expect(result.success, isFalse,
          reason: 'moving onto a day that was rescheduled elsewhere must be '
              'refused — pre-fix only completed/paused were guarded');
      expect(result.errorMessage, contains('destination was rescheduled'));
      final dest = scheduleRow(toDate);
      expect(dest!['status'], 'moved',
          reason: 'the terminal destination must be untouched');
      expect(scheduleRow(fromDate)!['status'], 'planned',
          reason: 'the source must stay planned when the move is refused');
    });

    // FINDING 7 (LOW): move/drop never resolved the partial day's
    // completion_prompt_<fromDate> card — a stale two-button tile kept
    // rendering for a day that no longer exists as planned.
    test('move resolves the source day completion_prompt card', () async {
      await HiveService.instance.workoutBox.put('schedule_$fromDate', {
        'date': fromDate,
        'workout_name': 'Push A',
        'status': 'planned',
        'type': 'custom_template',
        'exercises': [],
      });
      await HiveService.instance.coachBox.put('completion_prompt_$fromDate', {
        'kind': 'completion_prompt',
        'date': fromDate,
        'planned_count': 4,
        'logged_count': 1,
        'created_at': DateTime.now().toIso8601String(),
        'resolved_at': null,
      });

      RescheduleWeekPlanner.instance.cache('mv_prompt_1', [
        RescheduleMove(
          fromDate: fromDate,
          toDate: toDate,
          action: RescheduleAction.move,
          workoutName: 'Push A',
        ),
      ]);

      final result = await dispatch('mv_prompt_1');
      expect(result.success, isTrue);
      final prompt =
          HiveService.instance.coachBox.get('completion_prompt_$fromDate')
              as Map?;
      expect(prompt, isNotNull);
      expect(prompt!['resolved_at'], isNotNull,
          reason: 'a moved day must resolve its stale completion-prompt '
              'card (same semantics as the auto-complete backstop)');
    });

    test('drop resolves the source day completion_prompt card', () async {
      await HiveService.instance.workoutBox.put('schedule_$fromDate', {
        'date': fromDate,
        'workout_name': 'Legs B',
        'status': 'planned',
        'type': 'custom_template',
        'exercises': [],
      });
      await HiveService.instance.coachBox.put('completion_prompt_$fromDate', {
        'kind': 'completion_prompt',
        'date': fromDate,
        'planned_count': 4,
        'logged_count': 1,
        'created_at': DateTime.now().toIso8601String(),
        'resolved_at': null,
      });

      RescheduleWeekPlanner.instance.cache('dr_prompt_1', [
        RescheduleMove(
          fromDate: fromDate,
          action: RescheduleAction.drop,
          workoutName: 'Legs B',
        ),
      ]);

      final result = await dispatch('dr_prompt_1');
      expect(result.success, isTrue);
      final prompt =
          HiveService.instance.coachBox.get('completion_prompt_$fromDate')
              as Map?;
      expect(prompt!['resolved_at'], isNotNull,
          reason: 'a dropped day must resolve its stale completion-prompt '
              'card');
    });
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
