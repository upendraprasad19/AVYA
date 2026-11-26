// Pure pieces behind the Train past-week view (docs/plans/train-past-week-in-place.md D2/D3/D5):
// date mapping, range label, name/count precedence, wlog-name reader. No Hive, no Riverpod.
//
// Run: TZ=Asia/Kolkata flutter test test/contracts/past_week_days_pure_test.dart
//      TZ=Etc/GMT-8     flutter test test/contracts/past_week_days_pure_test.dart   (device east of IST)

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/workout_read_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/train/services/past_week_days.dart';

Map<String, dynamic> _row({
  String type = 'workout',
  String status = 'planned',
  Object? name,
  Object? exercises = const <Map<String, dynamic>>[],
}) =>
    {
      'type': type,
      'status': status,
      if (name != null) 'workout_name': name,
      'exercises': exercises,
    };

void main() {
  group('pastWeekDateTime', () {
    test('is UTC noon, so istDateStr gives the SAME date on every device', () {
      final d = pastWeekDateTime('2026-10-12');
      expect(d.isUtc, isTrue);
      expect(d.hour, 12);
      expect(istDateStr(d), '2026-10-12');
      // A local-midnight parse reads the previous IST day on a device east of IST (TZ=Etc/GMT-8).
      expect(istDateStr(pastWeekDateTime('2026-01-01')), '2026-01-01');
      expect(istDateStr(pastWeekDateTime('2026-12-31')), '2026-12-31');
    });
    test('a malformed string throws (the provider skips and reports the row)', () {
      expect(() => pastWeekDateTime('nope'), throwsFormatException);
    });
    test('the range label never throws in a widget build: a malformed start shows its raw text', () {
      expect(pastWeekRangeLabel('20261012', 1), '20261012');
    });
  });

  group('pastWeekRangeLabel', () {
    test('within a month and across one, week by week from the first row (not a Monday)', () {
      expect(pastWeekRangeLabel('2026-10-12', 1), 'Oct 12–18');
      expect(pastWeekRangeLabel('2026-10-12', 2), 'Oct 19–25');
      expect(pastWeekRangeLabel('2026-10-12', 3), 'Oct 26–Nov 1');
      // A Wednesday start.
      expect(pastWeekRangeLabel('2026-10-14', 1), 'Oct 14–20');
      expect(pastWeekRangeLabel('2026-10-14', 4), 'Nov 4–10');
    });
    test('crosses a year and a leap day', () {
      expect(pastWeekRangeLabel('2026-12-28', 1), 'Dec 28–Jan 3');
      expect(pastWeekRangeLabel('2028-02-24', 1), 'Feb 24\u2013Mar 1');
    });
    test('a week past the group start still counts 7-day steps', () {
      expect(pastWeekRangeLabel('2026-03-23', 2), 'Mar 30–Apr 5');
      expect(pastWeekRangeLabel('2026-10-26', 2), 'Nov 2–8');
    });
  });

  group('pastDayView name precedence', () {
    test('COMPLETED: wlog name, then the row name, then the generic', () {
      expect(pastDayView(_row(status: 'completed', name: 'Row Name'), wlogName: 'Log Name')
          .row['workout_name'], 'Log Name');
      expect(pastDayView(_row(status: 'completed', name: 'Row Name')).row['workout_name'],
          'Row Name');
      expect(pastDayView(_row(status: 'completed')).row['workout_name'], 'Workout');
    });
    test('NOT done: the row name, then the wlog name, then the generic', () {
      expect(pastDayView(_row(name: 'Row Name'), wlogName: 'Log Name').row['workout_name'],
          'Row Name');
      expect(pastDayView(_row(), wlogName: 'Log Name').row['workout_name'], 'Log Name');
      expect(pastDayView(_row()).row['workout_name'], 'Workout');
      expect(pastDayView(_row(type: 'rest', status: 'rest')).row['workout_name'], 'Rest Day');
    });
    test('a stored "Chat Workout" title is still shown (as the current list shows it), never hidden', () {
      expect(pastDayView(_row(status: 'completed', name: 'Chat Workout'), wlogName: 'Chat Workout')
          .row['workout_name'], 'Chat Workout');
      expect(pastDayView(_row(name: 'Chat Workout')).row['workout_name'], 'Chat Workout');
      // The bare word stays the generic (the same text either way), and a real name still beats a placeholder.
      expect(pastDayView(_row(type: 'rest', status: 'rest', name: 'Workout')).row['workout_name'],
          'Rest Day');
      expect(pastDayView(_row(status: 'completed', name: 'Chat Workout'), wlogName: 'Leg Day')
          .row['workout_name'], 'Leg Day');
    });
    test('a placeholder, blank or non-string name counts as none (trim + lower-case)', () {
      for (final n in ['Workout', ' workout ', 'Chat Workout', 'CHAT WORKOUT', '  ', '']) {
        expect(pastDayView(_row(status: 'completed', name: n), wlogName: 'Real').row['workout_name'],
            'Real', reason: 'row name "$n"');
        expect(pastDayView(_row(name: 'Real'), wlogName: n).row['workout_name'], 'Real',
            reason: 'wlog name "$n"');
      }
      expect(pastDayView(_row(name: 7)).row['workout_name'], 'Workout');
    });
    test('the stored row is never mutated', () {
      final src = _row(name: 'A');
      pastDayView(src, wlogName: 'B');
      expect(src['workout_name'], 'A');
    });
  });

  group('pastDayView count', () {
    test('only when the row stores NO exercises', () {
      expect(pastDayView(_row(), loggedCount: 5).loggedCount, 5);
      expect(pastDayView(_row(exercises: null), loggedCount: 5).loggedCount, 5);
      expect(pastDayView(_row(exercises: [{'exercise_name': 'Squat'}]), loggedCount: 5).loggedCount,
          isNull);
    });
  });

  group('pastDayWantsLogName', () {
    test('a completed row or one with no usable name', () {
      expect(pastDayWantsLogName(_row(status: 'completed', name: 'X')), isTrue);
      expect(pastDayWantsLogName(_row()), isTrue);
      expect(pastDayWantsLogName(_row(name: 'Workout')), isTrue);
      expect(pastDayWantsLogName(_row(name: 'Leg Day')), isFalse);
    });
  });

  group('WorkoutReadService.workoutLogName', () {
    test('a non-blank name from a map; null for absent / non-map / blank', () {
      expect(WorkoutReadService.workoutLogName({'workout_name': 'Push Day'}), 'Push Day');
      expect(WorkoutReadService.workoutLogName({'workout_name': '  '}), isNull);
      expect(WorkoutReadService.workoutLogName({'workout_name': 3}), isNull);
      expect(WorkoutReadService.workoutLogName({}), isNull);
      expect(WorkoutReadService.workoutLogName('x'), isNull);
      expect(WorkoutReadService.workoutLogName(null), isNull);
    });
  });
}
