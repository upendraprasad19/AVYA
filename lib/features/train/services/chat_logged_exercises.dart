// Coach workout parity 1c (OI-491): which exercises of today's Active Workout
// session the coach already logged in chat.
//
// Active Workout takes ONE name-keyed snapshot of them at START
// (`ActiveWorkoutNotifier.startWorkout`); a chat-logged exercise opens as DONE
// with the label LOGGED IN CHAT. The coach's sets live only in this snapshot,
// never in `checkedSets` / `setInputValues`, so FINISH cannot save them again.
// Plan: docs/plans/coach-workout-parity-1c.md (C1, C2).

import 'dart:math' as math;

import 'package:icanbefitter/core/services/workout_read_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/exercise_name_identity.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_set_chips.dart';

import 'coach_day_completion.dart';

/// One exercise the coach logged in chat for the session's date.
class ChatLoggedExercise {
  /// The name the row is stored under (the current name, or the plan row's
  /// `swapped_from` name when only that one was logged).
  final String loggedName;
  final String loggingType;

  /// The coach's per-set list (possibly empty for a row with no `sets[]`).
  final List<ExerciseSet> sets;

  /// How many sets the coach logged: `max(sets.length, aggregateSetCount)`.
  /// Every count (header, FINISH line, re-open rows, numbering) uses it.
  final int coachCount;

  /// The slot's planned set count at START (after the Red-day drop).
  final int plannedSets;

  const ChatLoggedExercise({
    required this.loggedName,
    required this.loggingType,
    required this.sets,
    required this.coachCount,
    required this.plannedSets,
  });
}

/// A row the coach wrote (or appended to): the sticky Hive-local marker, or a
/// row whose last writer was the coach. Cloud-restored rows carry neither
/// (residual R6), so they open as plain cards.
bool isChatLoggedRow(Map row) =>
    row['coach_logged'] == true || row['source'] == WriteSource.aiCoach.code;

/// Builds the entry for [row] (a chat row). Throws on a malformed set, so
/// the caller's per-row guard skips that exercise.
ChatLoggedExercise chatLoggedEntryFromRow(
  Map<String, dynamic> row, {
  required String loggedName,
  required String fallbackLoggingType,
  required int plannedSets,
}) {
  final sets = WorkoutReadService.perSetList(row)
      .map(ExerciseSet.fromMap)
      .toList(growable: false);
  final coachCount =
      math.max(sets.length, WorkoutReadService.aggregateSetCount(row));
  return ChatLoggedExercise(
    loggedName: loggedName,
    loggingType: (row['logging_type'] as String?) ?? fallbackLoggingType,
    sets: sets,
    coachCount: coachCount,
    plannedSets: plannedSets,
  );
}

/// The chat entry for one planned exercise, or null when it has none.
/// [ex] is a schedule-row exercise map (`exercise_name`, optional
/// `swapped_from`); [date] is the session date. Throws on a malformed row.
ChatLoggedExercise? chatLoggedEntryFor(
  DateTime date,
  Map ex, {
  required String fallbackLoggingType,
  required int plannedSets,
}) {
  final name = loggedNameForPlannedExercise(date, ex, accept: isChatLoggedRow);
  if (name == null) return null;
  final row = WorkoutReadService.exerciseLogRow(
    WorkoutWriteService.exlogKey(date, name),
  );
  if (row == null) return null;
  return chatLoggedEntryFromRow(
    row,
    loggedName: name,
    fallbackLoggingType: fallbackLoggingType,
    plannedSets: plannedSets,
  );
}

/// The chips for a chat entry's sets (none when the per-set list is empty).
/// Field mapping as `workout_receipt_card.dart` builds its receipt sets.
List<WardSetChip> chatLoggedChips(List<ExerciseSet> sets) => [
      for (final s in sets)
        WardSetChip(
          weightKg: s.weightKg > 0 ? s.weightKg : null,
          reps: s.reps > 0 ? s.reps : null,
          durationSeconds:
              (s.durationSec ?? 0) > 0 ? s.durationSec : null,
          distanceKm: (s.distanceKm ?? 0) > 0 ? s.distanceKm : null,
        ),
    ];

/// The map key of a session exercise in `ActiveWorkoutData.loggedInChat`.
String chatLoggedKey(String sessionName) => exerciseNameKey(sessionName);
