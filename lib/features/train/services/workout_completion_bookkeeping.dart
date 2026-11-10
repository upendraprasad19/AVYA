import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/badge_service.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/rank_service.dart';
import 'package:icanbefitter/core/services/sync_flags.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_read_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../providers/train_provider.dart'
    show resolveStreakWeekState, weeklyStreakAfterCompletion, lastCountedWeekKeyFrom;
import '../repositories/workout_repository.dart';

/// Which completion door called [WorkoutCompletionBookkeeping.afterCompletion].
/// Telemetry and the test recorder only; every door runs the same steps.
enum CompletionDoor { activeWorkout, chatCard, coachAuto, coachTap }

/// One recorded call (test seam).
@immutable
class CompletionBookkeepingCall {
  final CompletionDoor door;
  final String dateStr;
  final bool newlyCompleted;
  const CompletionBookkeepingCall(this.door, this.dateStr, this.newlyCompleted);
}

/// Coach workout parity 1a (OI-379; plan `docs/plans/coach-workout-parity-1a.md`
/// rev 4): the ONE after-completion step every completion door calls once
/// `WorkoutWriteService.markCompleted` succeeded — Active Workout
/// (`_persistCompletion`), the chat workout card (`submitWorkoutDraft`), the
/// typed all-logged backstop (`_maybeCompleteScheduledDay`) and the
/// completion-prompt tap (`completeWorkoutFromPrompt`).
///
/// Before this, only Active Workout did any of it (ADR-0012 assumed
/// `markCompleted` "feeds streak / rank"; it never did).
///
/// Every value raised here is monotonic and cannot be walked back (restore
/// merges progress max-wins, the push RPC takes GREATEST, rank never demotes),
/// so the count is decided once per day (`newlyCompleted`, under the
/// per-date lock) and healed to the number of completed DAYS on record.
/// Each step has its own try/catch, so one failing never skips a later one.
class WorkoutCompletionBookkeeping {
  WorkoutCompletionBookkeeping._();
  static final WorkoutCompletionBookkeeping instance =
      WorkoutCompletionBookkeeping._();

  /// Records every call (door, IST day, newlyCompleted). Production never sets it.
  @visibleForTesting
  static void Function(CompletionBookkeepingCall call)? debugOnCall;

  /// Throws inside the named step ('count', 'reckon', 'weekly', 'progress',
  /// 'streak_row', 'badges_rank') to prove the steps are independent.
  @visibleForTesting
  static String? debugThrowAtStep;

  /// Replaces the completed-day count (to observe `newlyCompleted` alone).
  @visibleForTesting
  static int Function()? debugCompletedDayCount;

  @visibleForTesting
  static void debugReset() {
    debugOnCall = null;
    debugThrowAtStep = null;
    debugCompletedDayCount = null;
  }

  static void _fault(String step) {
    if (debugThrowAtStep == step) throw StateError('debug fault at $step');
  }

  /// [workoutDate]: the exact DateTime the door gave `markCompleted`; the
  /// steps work on its IST day. [expectedOwner]: the Hive owner captured as the
  /// FIRST statement of the door, before any await. [mintProgressIfMissing]:
  /// true only for Active Workout (today's behaviour); a coach door never mints
  /// a default progress map.
  Future<void> afterCompletion({
    required DateTime workoutDate,
    required bool newlyCompleted,
    required String? expectedOwner,
    required bool mintProgressIfMissing,
    required CompletionDoor door,
  }) async {
    final dateStr = istDateStr(workoutDate);
    debugOnCall?.call(CompletionBookkeepingCall(door, dateStr, newlyCompleted));

    // 0. Guards.
    if (HiveUserSession.currentOwnerFullId != expectedOwner) {
      unawaited(ErrorTelemetry.logEvent('completion_bookkeeping_owner_changed',
          message: 'door=${door.name}'));
      return;
    }
    final users = UserRepository.instance;
    if (users.getProgress() == null && !mintProgressIfMissing) {
      unawaited(ErrorTelemetry.logEvent('completion_bookkeeping_no_progress',
          message: 'door=${door.name}'));
      return;
    }

    // The IST day as a UTC-midnight DateTime: the week helpers read only its
    // year/month/day, and istDateStr(UTC midnight) is that same day on every
    // device.
    final day = DateTime.utc(int.parse(dateStr.substring(0, 4)),
        int.parse(dateStr.substring(5, 7)), int.parse(dateStr.substring(8, 10)));

    // 1. COUNT FIRST, alone: +1 for a first completion, healed up to the
    //    completed days on record (never down). Read and write with no await
    //    between (updateProgress re-reads synchronously before its first await).
    try {
      _fault('count');
      final stored =
          (users.getProgress()?['total_workouts_done'] as num?)?.toInt() ?? 0;
      final days = debugCompletedDayCount?.call() ??
          WorkoutReadService.instance.completedWorkoutDayCount();
      final next = math.max(stored + (newlyCompleted ? 1 : 0), days);
      if (next != stored || users.getProgress() == null) {
        await users.updateProgress({'total_workouts_done': next});
      }
    } catch (e, st) {
      _report(e, st, 'count', door);
    }

    // 1b. Streak fields only once this user's restore has settled: a partial
    //     schedule would write a low daily streak (not monotonic) or a weekly
    //     credit computed from too few rows (permanent). The next completion
    //     after the restore settles does the rest. The SAME gate as
    //     reckonStreakDecayAndPersist, kill switch included
    //     (disable_streak_reckon_user_gate falls back to the restore tick), so
    //     the switch never leaves completions unable to update a streak.
    final restoreSettled = SyncFlags.streakReckonUserGateEnabled
        ? SyncService.instance.restoreSettledForCurrentUser
        : SyncService.instance.restoreCompletedTick.value > 0;
    if (!restoreSettled) {
      unawaited(ErrorTelemetry.logEvent(
          'completion_bookkeeping_restore_unsettled',
          message: 'door=${door.name}'));
      return;
    }

    // 2. Daily streak (the reckon persists freeze debits itself).
    int? streakDays;
    try {
      _fault('reckon');
      streakDays = WorkoutRepository.instance.reckonStreakDecayAndPersist();
    } catch (e, st) {
      _report(e, st, 'reckon', door);
    }

    // 3. Weekly streak. The hold ordinal is the same flag-gated value
    //    holdStatusProvider exposes (`isHolding ? todayHoldOrdinal : null`):
    //    activeHoldOrdinalFor(nowWall()); resolveStreakWeekState re-derives the
    //    ordinal from the day itself.
    ({
      int streakWeekId,
      int weekKey,
      bool weekIsCurrent,
      DateTime? weekStartDate,
      int planned,
      int completedCount
    })? streakWeek;
    ({int weeks, int marker})? weekly;
    try {
      _fault('weekly');
      // ignore: deprecated_member_use — ref-free door; singleton until full provider migration
      final readSvc = WorkoutScheduleReadService.instance;
      streakWeek = resolveStreakWeekState(
        readSvc: readSvc,
        planStart: WorkoutScheduleService.instance.getPlanStartDate(),
        holdOrdinal: readSvc.activeHoldOrdinalFor(nowWall()),
        workoutDate: day,
      );
      final progress = users.getProgress() ?? const <String, dynamic>{};
      weekly = weeklyStreakAfterCompletion(
        streakWeeks: (progress['current_streak_weeks'] as num?)?.toInt() ?? 0,
        lastCountedWeekKey:
            lastCountedWeekKeyFrom(progress['last_counted_week_key']),
        weekKey: streakWeek.weekKey,
        weekIsCurrent: streakWeek.weekIsCurrent,
        planned: streakWeek.planned,
        completedCount: streakWeek.completedCount,
      );
    } catch (e, st) {
      _report(e, st, 'weekly', door);
    }

    // 3a. Step 1 awaited: re-check the owner before the remaining writes.
    if (HiveUserSession.currentOwnerFullId != expectedOwner) {
      unawaited(ErrorTelemetry.logEvent('completion_bookkeeping_owner_changed',
          message: 'door=${door.name} step=progress'));
      return;
    }

    // 4. One progress write. last_workout_date only ever moves later, so a
    //    backdated coach log never pulls it back: the ONE date rule,
    //    laterIsoDate (stored = local, this day = incoming), the same rule the
    //    restore merge uses (SoT progress_last_workout_date, constraint 1).
    try {
      _fault('progress');
      final date = laterIsoDate(
          users.getProgress()?['last_workout_date'], dateStr,
          istToday: istTodayStr());
      await users.updateProgress({
        'current_streak_days': ?streakDays,
        'last_workout_date': ?date.value,
        if (weekly != null) 'current_streak_weeks': weekly.weeks,
        // Slice D: the calendar week LAST COUNTED, moved only when the counter
        // moves (weeklyStreakAfterCompletion).
        if (weekly != null) 'last_counted_week_key': weekly.marker,
      });
    } catch (e, st) {
      _report(e, st, 'progress', door);
    }

    // 5. Per-week streak row for the Supabase streaks table.
    try {
      _fault('streak_row');
      final weekStartDate = streakWeek?.weekStartDate;
      final planned = streakWeek?.planned ?? 0;
      if (streakWeek != null && weekStartDate != null && planned > 0) {
        final weekStartStr = istDateStr(weekStartDate);
        final streakId = 'streak_$weekStartStr';
        final healthBox = HiveService.instance.healthBox;
        final existing = (healthBox.get('streaks') as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            <Map<String, dynamic>>[];
        final idx = existing.indexWhere((s) => s['local_id'] == streakId);
        final row = <String, dynamic>{
          'local_id': streakId,
          'week_start': weekStartStr,
          'workouts_planned': planned,
          'workouts_completed': streakWeek.completedCount,
          'is_streak_maintained':
              streakWeek.completedCount >= (planned * 0.8).ceil(),
        };
        if (idx >= 0) {
          existing[idx] = row;
        } else {
          existing.add(row);
        }
        await healthBox.put('streaks', existing);
      }
    } catch (e, st) {
      _report(e, st, 'streak_row', door);
    }

    // 6. Badges (synchronous) and the rank check (monotonic, fire-and-forget).
    try {
      _fault('badges_rank');
      BadgeService.instance.checkAll();
      unawaited(RankService.instance.evaluateAndPromote());
    } catch (e, st) {
      _report(e, st, 'badges_rank', door);
    }
  }

  static void _report(Object e, StackTrace st, String step, CompletionDoor door) {
    debugPrint('[WorkoutCompletionBookkeeping] $step failed: $e');
    unawaited(ErrorTelemetry.recordNonFatal(e, st,
        reason: 'workout_completion_bookkeeping',
        extra: {'step': step, 'door': door.name}));
  }
}
