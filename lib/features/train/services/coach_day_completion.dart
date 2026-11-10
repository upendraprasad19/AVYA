import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/core/services/completion_prompt_store.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/workout_read_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';

import 'workout_completion_bookkeeping.dart';

/// What the coach-day completion rule decides for one date
/// (`docs/plans/coach-workout-parity-1b.md` D1).
enum CoachDayDecision {
  /// The date is after IST today: a coach `log_set` can carry any date, and a
  /// full future day must never be marked (1a would count it permanently).
  future,

  /// No `schedule_<date>` row.
  noPlan,

  /// Completed, with its `wlog_<date>` row.
  alreadyDone,

  /// Completed, but no `wlog_<date>` row (only the chat card re-marks it).
  repairDone,

  /// `moved` / `dropped`: an audit placeholder, not a live plan.
  terminal,

  /// `type == 'rest'`: nothing planned to finish.
  rest,

  /// Every planned exercise has a log (and at least one is planned).
  completeNow,

  /// A partial day (or an empty non-rest plan): the user decides by tapping.
  askToComplete,
}

/// The ONE coach-day completion rule (founder decision 2, 2026-11-10: a
/// coach-logged day is done only when every planned exercise is logged, or
/// the user taps Complete workout). Pure. Shared by the typed all-logged
/// backstop (`ToolDispatcher._maybeCompleteScheduledDay`), the chat workout
/// card (`submitWorkoutDraft`), the completion tile and Train's Complete
/// button, so the four cannot drift.
///
/// [rawRow] MUST be the stored row (`WorkoutScheduleReadService.rawScheduleRow`),
/// never the display read `getScheduleForDate`, where a terminal row reads as
/// absent and [CoachDayDecision.terminal] would collapse into `noPlan`.
///
/// Order after [CoachDayDecision.future] is the backstop's own (completed,
/// terminal, rest, all-logged). `rest` is `type == 'rest'` (the backstop's
/// rule); Train's `isRest` is wider, and its button also requires `!isRest`.
/// A `paused` / `skipped` / `travel` row can complete, as through the
/// backstop and Active Workout.
CoachDayDecision decideCoachDay({
  required Map? rawRow,
  required int loggedCount,
  required bool hasWlog,
  required String dateStr,
  required String istToday,
}) {
  if (dateStr.compareTo(istToday) > 0) return CoachDayDecision.future;
  if (rawRow == null) return CoachDayDecision.noPlan;
  if (rawRow['status'] == 'completed') {
    return hasWlog ? CoachDayDecision.alreadyDone : CoachDayDecision.repairDone;
  }
  if (WorkoutScheduleReadService.isTerminalScheduleRow(
    rawRow['status'] as String?,
  )) {
    return CoachDayDecision.terminal;
  }
  if (rawRow['type'] == 'rest') return CoachDayDecision.rest;
  final plannedCount = plannedExercisesOf(rawRow).length;
  if (plannedCount > 0 && loggedCount >= plannedCount) {
    return CoachDayDecision.completeNow;
  }
  return CoachDayDecision.askToComplete;
}

/// The planned exercises of a schedule row (`exercises[]`, maps only).
List<Map> plannedExercisesOf(Map row) =>
    ((row['exercises'] as List?) ?? const []).whereType<Map>().toList();

/// How many of [row]'s planned exercises have an exercise log for [date].
/// Swap-tolerant: a swapped exercise counts if EITHER its current
/// `exercise_name` OR its `swapped_from` name has a log. Uses the canonical
/// `WorkoutWriteService.exlogKey` (the key `logExercise` writes under), so it
/// reads exactly what a coach log or the chat card wrote. (Moved from
/// `ToolDispatcher._exerciseLogged`; the snapshot builder's copy reads it too.)
int loggedPlannedExerciseCount(DateTime date, Map row) {
  final box = HiveService.instance.workoutBox;
  bool hasLog(String? name) {
    if (name == null || name.trim().isEmpty) return false;
    return box.get(WorkoutWriteService.exlogKey(date, name)) != null;
  }

  return plannedExercisesOf(row)
      .where(
        (ex) =>
            hasLog(ex['exercise_name'] as String?) ||
            hasLog(ex['swapped_from'] as String?),
      )
      .length;
}

/// The plan day's name for a mark: the row's `workout_name` unless it is
/// missing or a placeholder, else [fallback].
String planWorkoutName(Map? row, {required String fallback}) {
  final name = (row?['workout_name'] as String?)?.trim() ?? '';
  if (name.isEmpty || kPlaceholderWorkoutNames.contains(name.toLowerCase())) {
    return fallback;
  }
  return name;
}

/// A UTC-midnight instant that round-trips through `istDateStr` to the SAME
/// `yyyy-MM-dd` on any host timezone (the Test #11.1 double-shift trap).
DateTime? utcDateFromIstDateStr(String dateStr) {
  final parts = dateStr.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime.utc(y, m, d);
}

/// What one Complete tap did ([CoachDayCompletion.completeOnTap]).
enum CoachTapResult {
  completed,
  alreadyDone,
  refusedNotToday,
  refusedNotCountable,
  refusedNoLogs,
  failed,
}

extension CoachTapResultX on CoachTapResult {
  bool get isSuccess =>
      this == CoachTapResult.completed || this == CoachTapResult.alreadyDone;

  /// The one line the tile and Train show for this result (approved copy).
  String get message {
    switch (this) {
      case CoachTapResult.completed:
      case CoachTapResult.alreadyDone:
        return WardroomCopy.coachTapCompleted;
      case CoachTapResult.refusedNoLogs:
        return WardroomCopy.coachTapNoLogs;
      case CoachTapResult.refusedNotToday:
      case CoachTapResult.refusedNotCountable:
        return WardroomCopy.coachWorkoutDayNotMarked;
      case CoachTapResult.failed:
        return WardroomCopy.coachTapFailed;
    }
  }
}

/// Coach workout parity 1b (OI-490): the ONE tap-to-complete path, used by the
/// coach completion tile ([CompletionDoor.coachTap]) and Train's COMPLETE
/// WORKOUT button ([CompletionDoor.trainTap]).
class CoachDayCompletion {
  CoachDayCompletion._();
  static final CoachDayCompletion instance = CoachDayCompletion._();

  /// Read-only: whether a Complete tap on [date] would complete it now —
  /// [date] is IST today, the rule says `completeNow` or `askToComplete`
  /// (a `completeNow` day whose mark never ran stays completable), and the
  /// day holds at least one exercise log. Train shows its COMPLETE WORKOUT
  /// button only when this is true, so the button and [completeOnTap] can
  /// never disagree.
  bool canCompleteOnTap(String date) {
    if (date != istTodayStr()) return false;
    final d = utcDateFromIstDateStr(date);
    if (d == null) return false;
    final row = WorkoutScheduleReadService.instance.rawScheduleRow(d);
    final decision = decideCoachDay(
      rawRow: row,
      loggedCount: row == null ? 0 : loggedPlannedExerciseCount(d, row),
      hasWlog:
          HiveService.instance.workoutBox.get(WorkoutWriteService.wlogKey(d))
              is Map,
      dateStr: date,
      istToday: istTodayStr(),
    );
    return (decision == CoachDayDecision.completeNow ||
            decision == CoachDayDecision.askToComplete) &&
        WorkoutReadService.instance.hasExerciseLogsFor(date);
  }

  /// Completes [date] (`yyyy-MM-dd`, IST) on the user's explicit tap.
  ///
  /// Refuses (no write; the prompt is resolved) a date that is not IST today
  /// (decision F: a past partial day stays not done; a future day is not done
  /// yet), a day with no row, a rest day, a moved/dropped day, and a day with
  /// no exercise log at all (ANY log: the tap is an explicit "I'm done", and
  /// the coach's names can differ from the plan's). An already-completed day
  /// is a success with no write. Otherwise `markCompleted` + the shared
  /// after-completion step, with the Hive owner captured first.
  ///
  /// The status read runs outside `markCompleted`'s per-date lock; a race can
  /// only re-stamp `wlog_` metadata, never the count (`newlyCompleted` is
  /// decided under the lock).
  Future<CoachTapResult> completeOnTap({
    required String date,
    required CompletionDoor door,
  }) async {
    final owner = HiveUserSession.currentOwnerFullId;
    final prompts = CompletionPromptStore.instance;
    try {
      final completeDate = utcDateFromIstDateStr(date);
      if (completeDate == null) return CoachTapResult.failed;
      if (date != istTodayStr()) {
        await prompts.resolve(date);
        return CoachTapResult.refusedNotToday;
      }
      final row = WorkoutScheduleReadService.instance.rawScheduleRow(
        completeDate,
      );
      final decision = decideCoachDay(
        rawRow: row,
        loggedCount: row == null
            ? 0
            : loggedPlannedExerciseCount(completeDate, row),
        hasWlog:
            HiveService.instance.workoutBox.get(
                  WorkoutWriteService.wlogKey(completeDate),
                )
                is Map,
        dateStr: date,
        istToday: istTodayStr(),
      );
      switch (decision) {
        case CoachDayDecision.alreadyDone:
        case CoachDayDecision.repairDone:
          await prompts.resolve(date);
          return CoachTapResult.alreadyDone;
        case CoachDayDecision.future:
          await prompts.resolve(date);
          return CoachTapResult.refusedNotToday;
        case CoachDayDecision.noPlan:
        case CoachDayDecision.rest:
        case CoachDayDecision.terminal:
          await prompts.resolve(date);
          return CoachTapResult.refusedNotCountable;
        case CoachDayDecision.completeNow:
        case CoachDayDecision.askToComplete:
          break;
      }
      if (!WorkoutReadService.instance.hasExerciseLogsFor(date)) {
        return CoachTapResult.refusedNoLogs;
      }
      final mark = await WorkoutWriteService.instance.markCompleted(
        date: completeDate,
        // The plan day's name as stored, exactly as the tap always passed it
        // (`?? 'Workout'`, a placeholder the OI-284 heal never copies).
        workoutName: (row?['workout_name'] as String?) ?? 'Workout',
        durationSec: 0,
        completedVia: door == CompletionDoor.trainTap ? 'train_tap' : 'tap',
      );
      if (!mark.success) return CoachTapResult.failed;
      await WorkoutCompletionBookkeeping.instance.afterCompletion(
        workoutDate: completeDate,
        newlyCompleted: mark.newlyCompleted,
        expectedOwner: owner,
        mintProgressIfMissing: false,
        door: door,
      );
      // The prompt is resolved inside afterCompletion (owner-checked).
      return CoachTapResult.completed;
    } catch (e, st) {
      debugPrint('[CoachDayCompletion] completeOnTap failed: $e');
      unawaited(
        ErrorTelemetry.recordNonFatal(
          e,
          st,
          reason: 'coach_day_complete_on_tap',
        ),
      );
      return CoachTapResult.failed;
    }
  }
}
