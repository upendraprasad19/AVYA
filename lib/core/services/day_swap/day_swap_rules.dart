// lib/core/services/day_swap/day_swap_rules.dart
//
// The day-swap rules (spec §5.2, §5.4, §5.6). PURE: plain maps and IST
// `YYYY-MM-DD` strings in, decisions out. No Hive, no clock, no I/O — the
// engine (SwapService.swapDays) reads live state inside the write lock and
// passes it in, so every rule is testable without a device.

import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';

import '../workout_write_service.dart' show ScheduledDaySwapWrite;
import 'day_swap_result.dart';

class DaySwapRules {
  DaySwapRules._();

  /// Keys that stay with the DATE (spec §5.4 "identity").
  static const Set<String> identityKeys = {
    'date',
    'day_of_week',
    'week',
    'phase',
    'week_character',
    'is_hold',
    'hold_ordinal',
    'reason',
  };

  /// Swap markers: rebuilt on every swap, never copied with content.
  /// `rescued_into` (OI-348 P3) marks a past day whose missed workout was
  /// rescued into [rescuedIntoKey]'s date; it belongs to that past date only.
  static const Set<String> markerKeys = {
    'is_swapped',
    'original_date',
    'arranged_at_ms',
    rescuedIntoKey,
  };

  /// Row key written on the PAST date of a missed-day rescue: the IST date the
  /// workout moved to. The freeze refund keys on it (never on the row shape).
  static const String rescuedIntoKey = 'rescued_into';

  /// Write stamps: `swapScheduledDays` re-stamps them.
  static const Set<String> writeStampKeys = {'source', 'updated_at_ms'};

  /// The only statuses a movable day may have (spec §5.2 rule 3).
  static const Set<String> movableStatuses = {'planned', 'rest'};

  /// `YYYY-MM-DD` → UTC midnight of that calendar date. `istDateStr` of the
  /// result is the same day on every host timezone (Global Constraints).
  static DateTime utcDate(String istDate) {
    final p = istDate.split('-');
    return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  static String format(DateTime utcDate) =>
      '${utcDate.year.toString().padLeft(4, '0')}-'
      '${utcDate.month.toString().padLeft(2, '0')}-'
      '${utcDate.day.toString().padLeft(2, '0')}';

  static String addDays(String istDate, int days) =>
      format(utcDate(istDate).add(Duration(days: days)));

  /// IST Monday of the Mon–Sun week containing [istDate]. String maths on
  /// UTC dates, so no timezone can shift it (unlike `istDateStr` of the
  /// naive-IST `mondayOfIst`, which double-shifts east of IST).
  static String mondayOf(String istDate) {
    final d = utcDate(istDate);
    return format(d.subtract(Duration(days: d.weekday - 1)));
  }

  /// Monday..Sunday of the week containing [istDate].
  static List<String> weekDates(String istDate) {
    final monday = mondayOf(istDate);
    return [for (var i = 0; i < 7; i++) addDays(monday, i)];
  }

  /// Refusal for the PAIR, before any row is read.
  static DaySwapRefusal? pairRefusal(String dateA, String dateB) {
    if (dateA == dateB) return DaySwapRefusal.sameDay;
    if (mondayOf(dateA) != mondayOf(dateB)) {
      return DaySwapRefusal.differentWeek;
    }
    return null;
  }

  /// Why [date] cannot move, or null when it can (spec §5.2). Precedence:
  /// completed → paused → past → started → travel → rescheduled → skipped →
  /// noRow (plan Task 10).
  static DaySwapRefusal? lockOf({
    required String date,
    required Map<String, dynamic>? row,
    required String today,
    required bool hasLoggedSets,
    required String? inProgressDate,
  }) {
    final status = row?['status'];
    if (status == 'completed') return DaySwapRefusal.completed;
    if (status == 'paused') return DaySwapRefusal.paused;
    if (date.compareTo(today) < 0) return DaySwapRefusal.past;
    if (hasLoggedSets || inProgressDate == date) return DaySwapRefusal.started;
    if (status == 'travel') return DaySwapRefusal.travel;
    if (status == 'moved' || status == 'dropped') {
      return DaySwapRefusal.rescheduled;
    }
    if (status == 'skipped') return DaySwapRefusal.skipped;
    if (row == null || !movableStatuses.contains(status)) {
      return DaySwapRefusal.noRow;
    }
    return null;
  }

  // ── Missed-day rescue (OI-348 P3, docs/plans/oi348-landing3d.md) ──
  //
  // A past day may swap ONLY with TODAY, only when today is a true rest day,
  // only inside the same Mon–Sun week (the pair rule is [pairRefusal]'s). A
  // past day is rescuable ("missed") when its row is a planned training day
  // with no logs and no session in progress. Everything else about a past day
  // is locked exactly as [lockOf] locks it.

  /// Today can host a rescue: a TRUE rest row (`type` AND `status` rest). A
  /// rest hybrid ([isRestHybrid]) is not a host: landed on the past date it
  /// would read as a missed workout to the streak walk (which skips by type).
  static bool isRescueHost(Map<String, dynamic>? row) =>
      row != null && row['type'] == 'rest' && row['status'] == 'rest';

  /// A past planned training day with no logs and no live session.
  static bool isMissed({
    required String date,
    required Map<String, dynamic>? row,
    required String today,
    required bool hasLogs,
    required String? inProgressDate,
  }) =>
      date.compareTo(today) < 0 &&
      row != null &&
      row['status'] == 'planned' &&
      !isRest(row) &&
      !hasLogs &&
      inProgressDate != date;

  /// The lock of a PAST [date] in a week whose today hosts a rescue. Same
  /// labels as [lockOf] for completed / paused; a missed day is movable; any
  /// other past day stays `past`.
  static DaySwapRefusal? rescueLockOf({
    required String date,
    required Map<String, dynamic>? row,
    required String today,
    required bool hasLogs,
    required String? inProgressDate,
  }) {
    final status = row?['status'];
    if (status == 'completed') return DaySwapRefusal.completed;
    if (status == 'paused') return DaySwapRefusal.paused;
    if (isMissed(
        date: date,
        row: row,
        today: today,
        hasLogs: hasLogs,
        inProgressDate: inProgressDate)) {
      return null;
    }
    return DaySwapRefusal.past;
  }

  /// The pair rule of a rescue: when either date is before [today], the
  /// other must BE today. Refused as `past` on the past date (the earlier
  /// one when both are past). Shared by the engine, the picker and the drag
  /// target so none of them can disagree.
  static DaySwapRefused? pairLock(String dateA, String dateB, String today) {
    final aPast = dateA.compareTo(today) < 0;
    final bPast = dateB.compareTo(today) < 0;
    if (!aPast && !bPast) return null;
    if (aPast && dateB == today) return null;
    if (bPast && dateA == today) return null;
    final lockedDate = aPast && bPast
        ? (dateA.compareTo(dateB) <= 0 ? dateA : dateB)
        : (aPast ? dateA : dateB);
    return DaySwapRefused(reason: DaySwapRefusal.past, date: lockedDate);
  }

  /// "⇄ MOVED": swapped content that is not completed (spec §6.1).
  static bool isMoved(Map<String, dynamic>? row) =>
      row != null && row['is_swapped'] == true && row['status'] != 'completed';

  /// Rest = a row of type `rest` (spec §5.6), OR a legacy rest hybrid
  /// ([isRestHybrid]). A missing row is not rest. Hermes h4F3 (diagnose
  /// c2d8e5): the hybrid shape is what the one-time repair migrator fixes,
  /// but a hybrid restored AFTER that migrator ran is only normalized on the
  /// next restore/reconcile — until then `type == 'rest'` alone counted it
  /// as a workout day and understated the 3+-rest-day-run warning.
  static bool isRest(Map<String, dynamic>? row) =>
      row != null && (row['type'] == 'rest' || isRestHybrid(row));

  /// The ONE hybrid predicate (spec §1.3/§1.4, plan D5): `status: rest`, a
  /// workout type, and no exercises. Shared by [isRest], the restore merge
  /// normalizer and the one-time `ScheduleHybridRepairMigrator` (through
  /// `PlanIntegrityReconciler.isRestHybrid`, which delegates here) so none
  /// of them can disagree about what a hybrid is. A hybrid WITH exercises is
  /// not one of these (ambiguous; left alone by all).
  static bool isRestHybrid(Map<String, dynamic> row) {
    final isWorkoutType =
        !PlanEngineFlags.isRestDayConsideringLogged(row['type']);
    final ex = row['exercises'];
    final hasExercises = ex is List && ex.isNotEmpty;
    return row['status'] == 'rest' && isWorkoutType && !hasExercises;
  }

  static Map<String, dynamic> contentOf(Map<String, dynamic> row) => {
        for (final e in row.entries)
          if (!identityKeys.contains(e.key) &&
              !markerKeys.contains(e.key) &&
              !writeStampKeys.contains(e.key))
            e.key: e.value,
      };

  static Map<String, dynamic> identityOf(Map<String, dynamic> row) => {
        for (final e in row.entries)
          if (identityKeys.contains(e.key)) e.key: e.value,
      };

  /// Where the content of [row] first came from: its `original_date` when
  /// it is already swapped content, else [fromDate] (spec §5.4).
  static String originOf(Map<String, dynamic> row, String fromDate) {
    final o = row['original_date'];
    if (row['is_swapped'] == true && o is String && o.isNotEmpty) return o;
    return fromDate;
  }

  /// [contentRow]'s content placed on [identityRow]'s identity at [toDate],
  /// with the swap markers. Content landing back on its origin loses both
  /// markers (the MOVED tag disappears after a swap-back).
  static Map<String, dynamic> landed({
    required Map<String, dynamic> contentRow,
    required String fromDate,
    required Map<String, dynamic> identityRow,
    required String toDate,
    required int? arrangedAtMs,
  }) {
    final origin = originOf(contentRow, fromDate);
    final out = <String, dynamic>{
      ...contentOf(contentRow),
      ...identityOf(identityRow),
      'date': toDate,
    };
    if (origin != toDate) {
      out['is_swapped'] = true;
      out['original_date'] = origin;
    }
    if (arrangedAtMs != null) out['arranged_at_ms'] = arrangedAtMs;
    return out;
  }

  /// A `displaced_<date>` backup follows its template to [toDate], re-dated
  /// onto the new date's identity (spec §5.4 template bookkeeping), so
  /// removing the template later restores the displaced workout there.
  static Map<String, dynamic>? travelBackup({
    required Map<String, dynamic>? backup,
    required String fromDate,
    required Map<String, dynamic> identityRow,
    required String toDate,
  }) {
    if (backup == null) return null;
    return landed(
      contentRow: backup,
      fromDate: fromDate,
      identityRow: identityRow,
      toDate: toDate,
      arrangedAtMs: null,
    );
  }

  /// The four keys a swap writes (spec §5.4). `arranged_at_ms` is the same
  /// [nowMs] on both rows and is never removed (spec §5.7).
  static ScheduledDaySwapWrite buildSwap({
    required String dateA,
    required String dateB,
    required Map<String, dynamic> rowA,
    required Map<String, dynamic> rowB,
    required Map<String, dynamic>? displacedA,
    required Map<String, dynamic>? displacedB,
    required int nowMs,
  }) =>
      (
        rowA: landed(
            contentRow: rowB,
            fromDate: dateB,
            identityRow: rowA,
            toDate: dateA,
            arrangedAtMs: nowMs),
        rowB: landed(
            contentRow: rowA,
            fromDate: dateA,
            identityRow: rowB,
            toDate: dateB,
            arrangedAtMs: nowMs),
        displacedA: travelBackup(
            backup: displacedB,
            fromDate: dateB,
            identityRow: rowA,
            toDate: dateA),
        displacedB: travelBackup(
            backup: displacedA,
            fromDate: dateA,
            identityRow: rowB,
            toDate: dateB),
      );

  /// Warn only when the swap CREATES or EXTENDS a run of ≥ 3 rest days
  /// inside the week (spec §5.6). [rows] are the rows BEFORE the swap.
  static RestRunWarning? restRunWarning({
    required List<String> weekDates,
    required Map<String, Map<String, dynamic>?> rows,
    required String dateA,
    required String dateB,
  }) {
    bool before(String d) => isRest(rows[d]);
    bool after(String d) {
      if (d == dateA) return isRest(rows[dateB]);
      if (d == dateB) return isRest(rows[dateA]);
      return before(d);
    }

    final beforeSet = _runs(weekDates, before).expand((r) => r).toSet();
    final flagged = <String>{
      for (final run in _runs(weekDates, after))
        if (run.any((d) => !beforeSet.contains(d))) ...run,
    }.toList()
      ..sort();
    return flagged.isEmpty ? null : RestRunWarning(runDates: flagged);
  }

  static List<List<String>> _runs(
      List<String> dates, bool Function(String) isRestDay) {
    final runs = <List<String>>[];
    var current = <String>[];
    for (final d in dates) {
      if (isRestDay(d)) {
        current.add(d);
        continue;
      }
      if (current.length >= 3) runs.add(current);
      current = <String>[];
    }
    if (current.length >= 3) runs.add(current);
    return runs;
  }
}
