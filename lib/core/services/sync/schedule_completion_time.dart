// lib/core/services/sync/schedule_completion_time.dart
//
// The one resolver for the TRUE completion time of a `schedule_<date>` Hive
// row (day-swapper + sync-load plan, spec §1.6 / §5.12; Task 14).
//
// markCompleted (workout_write_service.dart:502, :511) stamps the SCHEDULE
// row with `completed_at_ms` ONLY -- never the ISO `completed_at` (that field
// is written on the separate `wlog_<date>` row, workout_write_service.dart:540).
// Every reader of the schedule row's completion time that fell back to a raw
// `entry['completed_at']` read with a DateTime.now() default was therefore
// falling back on EVERY pass, because the schedule row never carries that
// field (recurrence of 5a36ad). This resolver is the one place that knows
// the real order: the legacy ISO field first (some rows still carry it, e.g. after a cloud
// restore merge), then the ms field markCompleted actually writes, then
// nothing -- NEVER DateTime.now().
//
// `updated_at_ms` is deliberately never read here: it is the row's
// last-WRITE time (often plan generation, via upsertScheduled), not its
// completion time (spec §1.6's correction to the 5a36ad resolver's own field
// order -- that resolver checks updated_at_ms before completed_at_ms and
// cannot be reused as-is for this purpose).
//
// A standalone library (not a `part`): every `sync/sync_*.dart` file in this
// codebase opens with `part of '../sync_service.dart';` and therefore cannot
// declare its own imports (a part file's imports are exactly the enclosing
// library's) -- so the only way for sync_workout.dart's part-file code to
// reach this class is for sync_service.dart itself to import it, which
// requires this to be a real library. It also makes the resolver directly
// unit-testable, unlike the private `_resolveCompletedAt` extension method it
// sits beside (test/sync/completed_at_preservation_test.dart's own header:
// "private, and the production singleton can't be DI'd from a unit test").
library;

/// The true completion time of a `schedule_<date>` row. Returns null when the
/// row is not completed, or is completed but carries no completion time at
/// all -- NEVER `DateTime.now()`.
///
/// Resolution order: the legacy ISO `completed_at` field, then a value
/// derived from `completed_at_ms` (the field `markCompleted` actually
/// writes). Never `updated_at_ms`. Callers that also want the spec's third
/// fallback step (the matching `wlog_<date>`'s `completed_at`) read that row
/// themselves and chain it with `??` -- it is a different Hive key entirely,
/// not a field of the row this class resolves.
class ScheduleCompletionTime {
  ScheduleCompletionTime._();

  static String? scheduledCompletedAtIso(Map<String, dynamic> row) {
    if (row['status'] != 'completed') return null;
    final iso = row['completed_at'];
    if (iso is String && iso.isNotEmpty) return iso;
    final ms = row['completed_at_ms'];
    if (ms is num && ms > 0) {
      return DateTime.fromMillisecondsSinceEpoch(ms.toInt(), isUtc: false)
          .toUtc()
          .toIso8601String();
    }
    return null;
  }

  /// The same resolution, as epoch milliseconds. Reads `completed_at_ms`
  /// directly when present (the common, fast path written by `markCompleted`);
  /// otherwise parses the legacy ISO field. Returns null on the same
  /// conditions as [scheduledCompletedAtIso].
  static int? scheduledCompletedAtMs(Map<String, dynamic> row) {
    if (row['status'] != 'completed') return null;
    final ms = row['completed_at_ms'];
    if (ms is num && ms > 0) return ms.toInt();
    final iso = row['completed_at'];
    if (iso is String && iso.isNotEmpty) {
      final parsed = DateTime.tryParse(iso);
      if (parsed != null) return parsed.toUtc().millisecondsSinceEpoch;
    }
    return null;
  }
}
