@Timeout(Duration(minutes: 5))
library;

// L1a-2 unit U2 (plan docs/plans/coach-history-correctness-client.md): the
// exercise-log RESTORE takes one live summary per (workout_log_id,
// exercise_id) by highest set count, joins per-set rows by rank, dates the
// restored log by the day encoded in `workout_log_id` (never by the write
// time `completed_at`), and does not resurrect a delete still queued for the
// cloud. Related bugs: e6a2d4, oi83.
//
// These run the REAL SyncService through the public seam
// `restoreExerciseLogsForSyncDomain()` against a stub that really filters and
// pages (`SyncStubServer.pagedTables`).

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/pending_exlog_deletes.dart';
import 'package:icanbefitter/core/services/sync/exlog_restore_rules.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';

import '../helpers/hive_test_setup.dart';
import 'sync_domain_skip_harness.dart';

const _killSwitch = 'disable_exlog_restore_dedupe';

String _id(int k) =>
    '00000000-0000-4000-8000-${k.toRadixString(16).padLeft(12, '0')}';

String _p(int n) => n.toString().padLeft(2, '0');
String _ymd(DateTime d) => '${d.year}-${_p(d.month)}-${_p(d.day)}';

/// The IST midnight of [ymd] as an instant, built the way the restore builds it.
DateTime _istMidnight(String ymd) => DateTime.utc(
      int.parse(ymd.substring(0, 4)),
      int.parse(ymd.substring(5, 7)),
      int.parse(ymd.substring(8, 10)),
    ).subtract(const Duration(hours: 5, minutes: 30));

Map<String, dynamic> _summary({
  required int n,
  required String day,
  String name = 'Bench Press',
  int sets = 3,
  String? completedAt,
  String? deletedAt,
  double weight = 60,
  int reps = 24,
}) =>
    {
      'id': _id(n),
      'user_id': kTestUserId,
      'workout_log_id': SyncService.workoutLogIdForDate(day),
      'exercise_id': name,
      'exercise_name': name,
      'set_number': sets,
      'weight_kg': weight,
      'reps': reps,
      'logging_type': 'weight_reps',
      'is_pr': false,
      'completed_at': completedAt ?? '${day}T10:00:00+00:00',
      'created_at': completedAt ?? '${day}T10:00:00+00:00',
      'deleted_at': deletedAt,
    };

Map<String, dynamic> _setRow({
  required int n,
  required String day,
  required int setNumber,
  String name = 'Bench Press',
}) =>
    {
      'id': _id(1000 + n),
      'user_id': kTestUserId,
      'workout_log_id': SyncService.workoutLogIdForDate(day),
      'exercise_id': name,
      'set_number': setNumber,
      'weight_kg': 60.0,
      'reps': 8,
      'completed_at': '${day}T10:00:00+00:00',
      'created_at': '${day}T10:00:00+00:00',
    };

void main() {
  final h = SyncHarness();
  setUp(() async {
    await h.setUp();
    h.server.pagedTables['workout_log_exercises'] = [];
    h.server.pagedTables['workout_log_sets'] = [];
  });
  tearDown(() async {
    await h.tearDown();
  });

  Future<void> restore() => SyncService.instance
      .restoreExerciseLogsForSyncDomain(since: '2020-01-01T00:00:00Z')
      .timeout(const Duration(minutes: 2));

  Map<String, dynamic>? localLog(String day, String name) {
    final raw = HiveService.instance.workoutBox
        .get(WorkoutWriteService.exlogKey(_istMidnight(day), name));
    return raw == null ? null : Map<String, dynamic>.from(raw as Map);
  }

  group('U2(a) one live summary per key, highest set count', () {
    test('the highest-count row wins when the newest row is not the last',
        () async {
      h.server.pagedTables['workout_log_exercises'] = [
        _summary(n: 1, day: '2026-09-01', sets: 3, completedAt: '2026-09-01T10:00:00+00:00'),
        // Older write time, higher count: the count decides, not the order.
        _summary(n: 2, day: '2026-09-01', sets: 5, completedAt: '2026-09-01T09:00:00+00:00'),
        _summary(n: 3, day: '2026-09-01', sets: 4, completedAt: '2026-09-01T11:00:00+00:00'),
      ];
      await restore();
      expect(localLog('2026-09-01', 'Bench Press')?['set_number'], 5);
    });

    test('a tombstoned row is never restored', () async {
      h.server.pagedTables['workout_log_exercises'] = [
        _summary(n: 1, day: '2026-09-01', sets: 9, deletedAt: '2026-09-02T00:00:00+00:00'),
        _summary(n: 2, day: '2026-09-01', sets: 3),
      ];
      await restore();
      expect(localLog('2026-09-01', 'Bench Press')?['set_number'], 3);
    });

    test('kill switch ON: the old behaviour (the newest-written row wins)',
        () async {
      await HiveService.instance.configBox.put(_killSwitch, true);
      // `_fetchAllRows` reads newest-first and the old loop kept the first row
      // it saw per key, so the NEWEST write won whatever its set count was
      // (the v9 plan said "oldest"; the code reads descending).
      h.server.pagedTables['workout_log_exercises'] = [
        _summary(n: 1, day: '2026-09-01', sets: 3, completedAt: '2026-09-01T11:00:00+00:00'),
        _summary(n: 2, day: '2026-09-01', sets: 5, completedAt: '2026-09-01T09:00:00+00:00'),
      ];
      await restore();
      expect(localLog('2026-09-01', 'Bench Press')?['set_number'], 3);
    });
  });

  group('U2(b) per-set join by rank', () {
    test('over-count 1..7 at count 4 trims to 1..4', () async {
      h.server.pagedTables['workout_log_exercises'] = [
        _summary(n: 1, day: '2026-09-01', sets: 4),
      ];
      h.server.pagedTables['workout_log_sets'] = [
        for (var s = 1; s <= 7; s++) _setRow(n: s, day: '2026-09-01', setNumber: s),
      ];
      await restore();
      final sets = (localLog('2026-09-01', 'Bench Press')?['sets'] as List)
          .map((e) => (e as Map)['set_number'])
          .toList();
      expect(sets, [1, 2, 3, 4]);
    });

    test('gapped legacy {1,2,4} at count 3 keeps set 4', () async {
      h.server.pagedTables['workout_log_exercises'] = [
        _summary(n: 1, day: '2026-09-01', sets: 3),
      ];
      h.server.pagedTables['workout_log_sets'] = [
        for (final s in [1, 2, 4]) _setRow(n: s, day: '2026-09-01', setNumber: s),
      ];
      await restore();
      final sets = (localLog('2026-09-01', 'Bench Press')?['sets'] as List)
          .map((e) => (e as Map)['set_number'])
          .toList();
      expect(sets, [1, 2, 4]);
    });

    test('kill switch ON: every per-set row is joined, as before', () async {
      await HiveService.instance.configBox.put(_killSwitch, true);
      h.server.pagedTables['workout_log_exercises'] = [
        _summary(n: 1, day: '2026-09-01', sets: 4),
      ];
      h.server.pagedTables['workout_log_sets'] = [
        for (var s = 1; s <= 7; s++) _setRow(n: s, day: '2026-09-01', setNumber: s),
      ];
      await restore();
      expect((localLog('2026-09-01', 'Bench Press')?['sets'] as List).length, 7);
    });
  });

  group('U2(c) the day comes from workout_log_id', () {
    test(
        'an edit-day completed_at restores onto the workout day: key, date, '
        'day index and the PR date all agree', () async {
      // Logged on 2026-09-01, edited (so completed_at is recent) on 2026-10-05.
      h.server.pagedTables['workout_log_exercises'] = [
        _summary(n: 1, day: '2026-09-01', sets: 3, completedAt: '2026-10-05T10:00:00+00:00'),
      ];
      await restore();

      final log = localLog('2026-09-01', 'Bench Press');
      expect(log, isNotNull, reason: 'stored under the WORKOUT day key');
      expect(log!['date'], '2026-09-01');
      expect(localLog('2026-10-05', 'Bench Press'), isNull,
          reason: 'not under the write-time day');
      final key = WorkoutWriteService.exlogKey(_istMidnight('2026-09-01'), 'Bench Press');
      final index = HiveService.instance.workoutBox
          .get('exercise_log_index_2026-09-01') as List?;
      expect(index, contains(key), reason: 'the day index holds the key');

      final prs = WorkoutRepository.instance.loadAllExercisePRs();
      final bench = prs.singleWhere((p) => p.exerciseName == 'Bench Press');
      expect(_ymd(bench.date), '2026-09-01',
          reason: 'the PR list dates a restored edited log to the workout day');
    });

    test('PRs on the same day list in a stable order by exercise name', () async {
      h.server.pagedTables['workout_log_exercises'] = [
        _summary(n: 1, day: '2026-09-01', name: 'Squat', sets: 3),
        _summary(n: 2, day: '2026-09-01', name: 'Bench Press', sets: 3),
        _summary(n: 3, day: '2026-09-01', name: 'Deadlift', sets: 3),
      ];
      await restore();
      final names = WorkoutRepository.instance
          .loadAllExercisePRs()
          .map((p) => p.exerciseName)
          .toList();
      expect(names, ['Bench Press', 'Deadlift', 'Squat']);
    });

    test('a forward-rescheduled (future-day) row restores onto its day',
        () async {
      final future = DateTime.now().toUtc().add(const Duration(days: 20));
      final day = _ymd(future);
      h.server.pagedTables['workout_log_exercises'] = [
        _summary(n: 1, day: day, sets: 3, completedAt: '${_ymd(DateTime.now().toUtc())}T10:00:00+00:00'),
      ];
      await restore();
      expect(localLog(day, 'Bench Press'), isNotNull);
    });

    test('kill switch ON: the old write-time day', () async {
      await HiveService.instance.configBox.put(_killSwitch, true);
      h.server.pagedTables['workout_log_exercises'] = [
        _summary(n: 1, day: '2026-09-01', sets: 3, completedAt: '2026-10-05T10:00:00+00:00'),
      ];
      await restore();
      expect(localLog('2026-10-05', 'Bench Press'), isNotNull);
      expect(localLog('2026-09-01', 'Bench Press'), isNull);
    });
  });

  group('U2(d) a queued delete is not resurrected', () {
    test('an entry queued for (workout_log_id, exercise_id) at any count is skipped',
        () async {
      await PendingExlogDeletes.add(
        workoutLogId: SyncService.workoutLogIdForDate('2026-09-01'),
        exerciseId: 'Bench Press',
        setNumber: 2,
      );
      h.server.pagedTables['workout_log_exercises'] = [
        _summary(n: 1, day: '2026-09-01', sets: 5),
        _summary(n: 2, day: '2026-09-01', name: 'Squat', sets: 3),
      ];
      await restore();
      expect(localLog('2026-09-01', 'Bench Press'), isNull,
          reason: 'queued delete: not written');
      expect(localLog('2026-09-01', 'Squat'), isNotNull,
          reason: 'a different exercise on the same day still restores');
    });

    test('kill switch ON: the queued delete is not consulted', () async {
      await HiveService.instance.configBox.put(_killSwitch, true);
      await PendingExlogDeletes.add(
        workoutLogId: SyncService.workoutLogIdForDate('2026-09-01'),
        exerciseId: 'Bench Press',
        setNumber: 3,
      );
      h.server.pagedTables['workout_log_exercises'] = [
        _summary(n: 1, day: '2026-09-01', sets: 3),
      ];
      await restore();
      expect(localLog('2026-09-01', 'Bench Press'), isNotNull);
    });
  });

  group('U2 heal: a row restored under the OLD rules is re-keyed, not duplicated',
      () {
    test('an edit-day-keyed restored row moves onto the workout day; one row '
        'remains and both day indexes are right', () async {
      final box = HiveService.instance.workoutBox;
      final cloudId = SyncService.workoutLogIdForDate('2026-09-01');
      // As the old restore wrote it: keyed by the day of completed_at.
      final staleKey = WorkoutWriteService.exlogKey(_istMidnight('2026-10-05'), 'Bench Press');
      await box.put(staleKey, {
        'id': staleKey,
        'type': 'exercise_log',
        'exercise_name': 'Bench Press',
        'date': '2026-10-05',
        'workout_log_id': cloudId,
        'created_at': '2026-10-05T10:00:00+00:00',
        'set_number': 3,
      });
      await box.put('exercise_log_index_2026-10-05', <String>[staleKey]);
      h.server.pagedTables['workout_log_exercises'] = [
        _summary(n: 1, day: '2026-09-01', sets: 3, completedAt: '2026-10-05T10:00:00+00:00'),
      ];
      await restore();

      final goodKey = WorkoutWriteService.exlogKey(_istMidnight('2026-09-01'), 'Bench Press');
      expect(box.get(staleKey), isNull, reason: 'the stale-day row is gone');
      final healed = Map<String, dynamic>.from(box.get(goodKey) as Map);
      expect(healed['date'], '2026-09-01');
      expect(healed['id'], goodKey);
      expect((box.get('exercise_log_index_2026-09-01') as List), contains(goodKey));
      final oldIdx = box.get('exercise_log_index_2026-10-05') as List?;
      expect(oldIdx == null || !oldIdx.contains(staleKey), isTrue);
      final exlogKeys = box.keys.whereType<String>().where((k) => k.startsWith('exlog_'));
      expect(exlogKeys, [goodKey], reason: 'exactly one local row for the exercise');
    });

    test('a LOCALLY logged row on the write day is never touched (its '
        'workout_log_id is a wlog_ id, not the cloud id)', () async {
      final box = HiveService.instance.workoutBox;
      final localKey = WorkoutWriteService.exlogKey(_istMidnight('2026-10-05'), 'Bench Press');
      await box.put(localKey, {
        'id': localKey,
        'exercise_name': 'Bench Press',
        'date': '2026-10-05',
        'workout_log_id': 'wlog_2026-10-05',
        'set_number': 2,
      });
      h.server.pagedTables['workout_log_exercises'] = [
        _summary(n: 1, day: '2026-09-01', sets: 3, completedAt: '2026-10-05T10:00:00+00:00'),
      ];
      await restore();
      expect(box.get(localKey), isNotNull, reason: 'a different log, left alone');
      expect(localLog('2026-09-01', 'Bench Press'), isNotNull,
          reason: 'the cloud row restores on its own day');
    });
  });

  group('selectLiveSummaries compares timestamps as instants', () {
    test('equal counts: the later INSTANT wins whatever the offset spelling', () {
      final rows = [
        // 12:00+05:30 = 06:30Z, earlier than 09:00Z although the text sorts later
        {'workout_log_id': 'w', 'exercise_id': 'x', 'set_number': 3, 'completed_at': '2026-10-05T12:00:00+05:30', 'id': 'a'},
        {'workout_log_id': 'w', 'exercise_id': 'x', 'set_number': 3, 'completed_at': '2026-10-05T09:00:00+00:00', 'id': 'b'},
      ];
      expect(selectLiveSummaries(rows).single['id'], 'b');
    });
  });

  group('U2(c) the IST-midnight instant', () {
    test('is 18:30 UTC of the previous day, whatever the device zone', () {
      // A local DateTime(y, m, d) is NOT this instant on a device east of IST
      // (it lands on the previous IST day); a CI pinned to IST cannot see
      // that, so the instant itself is pinned here.
      expect(ExlogWorkoutDays.istMidnight('2026-09-01'),
          DateTime.utc(2026, 8, 31, 18, 30));
      expect(ExlogWorkoutDays.istMidnight('2026-09-01').isUtc, isTrue);
    });

    test('forToday inverts workoutLogIdForDate across the horizon', () {
      final m = ExlogWorkoutDays.forToday('2026-10-09');
      expect(m[SyncService.workoutLogIdForDate('2020-01-01')], '2020-01-01');
      expect(m[SyncService.workoutLogIdForDate('2026-10-09')], '2026-10-09');
      expect(m[SyncService.workoutLogIdForDate('2027-11-13')], '2027-11-13',
          reason: 'today + 400 days resolves');
      expect(m[SyncService.workoutLogIdForDate('2027-11-14')], isNull,
          reason: 'one day past the horizon does not');
      expect(m[SyncService.workoutLogIdForDate('')], isNull,
          reason: 'the shared missing-date bucket is not a day');
    });
  });
}
