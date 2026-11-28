// BEHAVIORAL TEST — past-phase DISPLAY bucketing by date runs (OI-348 B3/B7)
//
// Concept:  past_phase_display_buckets
// Writer:   schedule_* rows (every generator stamps `phase` at write time; the
//           L1 merge, PlanIntegrityReconciler.mergeScheduleEntry, keeps a local
//           rest row wholesale, so a REST row can carry a stale stamp)
// Reader:   WorkoutScheduleReadService.bucketPastRowsForDisplay →
//           pastPhaseBlocksForDisplay / phaseForDate → week_selector past groups
//
// The founder's walk (A5 part 1, 2026-11-22): a past week sheet listed only
// Sun + Mon. Reproduced from the account's live plan_json rows (FIXTURE below,
// read 2026-11-23): four Sunday rest rows stamped 1 inside a phase-3 month made
// the stamp-number grouping build a "Phase I" out of five scattered days.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/features/train/widgets/week_selector.dart'
    show pastPhaseGroupsForTest, pastPhaseWeekCount, pastPhaseWeekOf;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

typedef Row = (DateTime, Map<String, dynamic>);

/// The walk account's past rows (`date:phase:<status><type>`, `-` = no stamp),
/// verbatim from `user_progress.plan_json.schedules` (dates before plan_start
/// 2026-11-09). Status: p planned, c completed, r rest. Type: w workout,
/// r rest, c custom_template, l logged.
const _fixture = '''
2026-04-27:2:pw 2026-04-28:2:pw 2026-04-29:2:pw 2026-04-30:2:pw 2026-05-01:2:pw
2026-05-02:2:cc 2026-05-03:2:rr 2026-05-04:2:cc 2026-05-05:2:cw 2026-05-06:2:cc
2026-05-07:2:cc 2026-05-08:2:pw 2026-05-09:2:cc 2026-05-10:2:rr 2026-05-11:2:cc
2026-05-12:2:cw 2026-05-13:2:pw 2026-05-14:2:cc 2026-05-15:2:cc 2026-05-16:2:cw
2026-05-17:2:rr 2026-05-18:2:cc 2026-05-19:2:cw 2026-05-20:2:cc 2026-05-21:2:cc
2026-05-22:2:pw 2026-05-23:2:pw 2026-05-24:2:rr 2026-05-25:-:pw 2026-05-26:-:pw
2026-05-27:-:pw 2026-05-28:-:pw 2026-05-29:-:pw 2026-05-30:-:pw 2026-05-31:-:rr
2026-06-01:3:pw 2026-06-02:-:cc 2026-06-03:3:pw 2026-06-04:3:pw 2026-06-05:-:cc
2026-06-06:-:cc 2026-06-07:-:rr 2026-06-08:3:pw 2026-06-09:3:pw 2026-06-10:3:pw
2026-06-11:3:pw 2026-06-12:3:pw 2026-06-13:3:pw 2026-06-14:-:rr 2026-06-15:3:pw
2026-06-16:3:pw 2026-06-17:3:pw 2026-06-18:3:pw 2026-06-19:3:pw 2026-06-20:3:pw
2026-06-21:-:rr 2026-06-22:3:pw 2026-06-23:3:pw 2026-06-24:3:pw 2026-06-25:3:pw
2026-06-26:3:pw 2026-06-27:3:pw 2026-06-28:-:rr 2026-06-29:3:pw 2026-06-30:3:pw
2026-07-01:3:pw 2026-07-02:3:pw 2026-07-03:3:pw 2026-07-04:3:pw 2026-07-05:-:rr
2026-07-17:-:pw 2026-07-18:-:pw 2026-07-19:-:pw 2026-07-20:-:pw 2026-07-21:-:pw
2026-07-22:-:pw 2026-07-23:-:rr 2026-08-19:-:pc 2026-08-20:-:pl 2026-08-21:-:pc
2026-08-22:-:pc 2026-08-23:2:pw 2026-08-24:2:pw 2026-08-25:2:rr 2026-09-14:3:cw
2026-09-15:3:cw 2026-09-16:3:cw 2026-09-17:3:cw 2026-09-18:3:cw 2026-09-19:3:cw
2026-09-20:1:rr 2026-09-21:3:cw 2026-09-22:3:cw 2026-09-23:3:cw 2026-09-24:-:cc
2026-09-25:3:pw 2026-09-26:-:cc 2026-09-27:1:rr 2026-09-28:-:cc 2026-09-29:3:cw
2026-09-30:3:cw 2026-10-01:3:cw 2026-10-02:3:cw 2026-10-03:3:pw 2026-10-04:1:rr
2026-10-05:3:pw 2026-10-06:3:pw 2026-10-07:3:cw 2026-10-08:3:pw 2026-10-09:3:cw
2026-10-10:3:pw 2026-10-11:1:rr 2026-10-12:4:pw 2026-10-13:4:pw 2026-10-14:4:pw
2026-10-15:4:pw 2026-10-16:4:pw 2026-10-17:4:pw 2026-10-18:4:rr 2026-10-19:4:pw
2026-10-20:4:pw 2026-10-21:4:cw 2026-10-22:4:pw 2026-10-23:4:pw 2026-10-24:4:pw
2026-10-25:4:rr 2026-10-26:4:pw 2026-10-27:4:pw 2026-10-28:4:pw 2026-10-29:4:pw
2026-10-30:4:pw 2026-10-31:4:pw 2026-11-01:4:rr 2026-11-02:4:pw 2026-11-03:4:cw
2026-11-04:4:cw 2026-11-05:4:pw 2026-11-06:4:pw 2026-11-07:4:pw 2026-11-08:4:rr
''';

const _status = {'p': 'planned', 'c': 'completed', 'r': 'rest'};
const _type = {'w': 'workout', 'r': 'rest', 'c': 'custom_template', 'l': 'logged'};

Map<String, dynamic> _map(String date, int? phase, String status, String type) =>
    {
      'date': date,
      'phase': ?phase,
      'status': status,
      'type': type,
    };

List<Row> _fixtureRows() => [
      for (final tok in _fixture.split(RegExp(r'\s+')).where((t) => t.isNotEmpty))
        () {
          final parts = tok.split(':');
          final code = parts[2];
          return (
            DateTime.parse(parts[0]),
            _map(parts[0], parts[1] == '-' ? null : int.parse(parts[1]),
                _status[code[0]]!, _type[code[1]]!),
          );
        }(),
    ];

String _d(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// [n] consecutive days from [start]; [stamp] null → no stamp. A day whose
/// weekday is Sunday is a rest row, others are workouts (unless [allRest]).
List<Row> _days(DateTime start, int n,
    {int? stamp, String status = 'planned', bool allRest = false}) {
  return [
    for (var i = 0; i < n; i++)
      () {
        final day = DateTime(start.year, start.month, start.day + i);
        final rest = allRest || day.weekday == DateTime.sunday;
        return (
          day,
          _map(_d(day), stamp, rest ? 'rest' : status, rest ? 'rest' : 'workout'),
        );
      }(),
  ];
}

Row _one(DateTime day, {int? stamp, bool rest = false, String status = 'planned'}) =>
    (day, _map(_d(day), stamp, rest ? 'rest' : status, rest ? 'rest' : 'workout'));

List<(String, String)> _bounds(List<PastPhaseBlock> b) =>
    [for (final x in b) (_d(x.startDate), _d(x.endDate))];

List<List<String>> _rowDates(List<PastPhaseBlock> b) =>
    [for (final x in b) [for (final r in x.rows) r['date'] as String]];

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

void main() {
  final display = WorkoutScheduleReadService.bucketPastRowsForDisplay;
  final strictPure = WorkoutScheduleReadService.bucketPastRows;

  group('T1 · the walk account', () {
    test('five date-ordered blocks; Sep 28-Oct 4 whole; no date twice', () {
      final blocks = display(_fixtureRows());
      expect(_bounds(blocks), [
        ('2026-04-27', '2026-05-31'),
        ('2026-06-01', '2026-07-23'),
        ('2026-08-19', '2026-08-25'),
        ('2026-09-14', '2026-10-11'),
        ('2026-10-12', '2026-11-08'),
      ]);
      final sepBlock = blocks[3].rows.map((r) => r['date']).toSet();
      for (var d = 28; d <= 34; d++) {
        final day = DateTime(2026, 9, d);
        expect(sepBlock, contains(_d(day)),
            reason: 'week Sep 28-Oct 4 must list all seven days');
      }
      final all = [for (final b in blocks) ...b.rows.map((r) => r['date'])];
      expect(all.length, all.toSet().length, reason: 'no date in two blocks');
      expect(all.length, _fixtureRows().length, reason: 'no row dropped');
    });

    test('the old grouping reproduces the symptom (pins the diagnosis)', () {
      final old = strictPure(_fixtureRows());
      // Stamp 1 first (sorted by number): Sep 20, 27, 28, Oct 4, 11.
      expect(_rowDates(old).first, [
        '2026-09-20', '2026-09-27', '2026-09-28', '2026-10-04', '2026-10-11'
      ]);
    });
  });

  group('T2 · clean history equals the stamp grouping', () {
    test('1/2/3, leading unstamped run, unstamped mid-week rows', () {
      final rows = <Row>[
        ..._days(DateTime(2026, 1, 2), 3), // Fri-Sun, unstamped, leading
        ..._days(DateTime(2026, 1, 5), 28, stamp: 1),
        ..._days(DateTime(2026, 2, 2), 28, stamp: 2),
        ..._days(DateTime(2026, 3, 2), 28, stamp: 3),
      ];
      // Unstamp a completed Wednesday inside phase 2 (restored row shape).
      final i = rows.indexWhere((r) => r.$2['date'] == '2026-02-11');
      rows[i] = _one(DateTime(2026, 2, 11), status: 'completed');
      final a = display(rows);
      final b = strictPure(rows);
      expect(_bounds(a), _bounds(b));
      expect(_rowDates(a), _rowDates(b));
      for (var k = 0; k < a.length; k++) {
        for (var j = 0; j < a[k].rows.length; j++) {
          expect(identical(a[k].rows[j], b[k].rows[j]), isTrue);
        }
      }
    });
  });

  group('T3/T4 · one stamp stays one block (F-B, 7d2e6b)', () {
    test('9 weeks with a 3-week gap and unstamped completed rows', () {
      final rows = <Row>[
        ..._days(DateTime(2026, 1, 5), 28, stamp: 3),
        ..._days(DateTime(2026, 2, 23), 14, stamp: 3),
        _one(DateTime(2026, 3, 9), status: 'completed'),
      ];
      final blocks = display(rows);
      expect(blocks.length, 1);
      expect(_d(blocks.single.endDate), '2026-03-09');
    });

    test('five-week held phase is one block with 5 chips', () {
      final rows = _days(DateTime(2026, 1, 5), 35, stamp: 2);
      final blocks = display(rows);
      expect(blocks.length, 1);
      expect(pastPhaseWeekCount(blocks.single.startDate, blocks.single.endDate),
          5);
    });

    test('week of a date is CALENDAR arithmetic, not elapsed hours (DST)', () {
      // A spring-forward day is 23 h: day 7 of the group is less than 7 x 24 h
      // after the start. Simulated with a start one hour into its day.
      final start = DateTime(2026, 3, 1, 1);
      expect(pastPhaseWeekOf(start, DateTime(2026, 3, 1)), 1);
      expect(pastPhaseWeekOf(start, DateTime(2026, 3, 7, 23)), 1);
      expect(pastPhaseWeekOf(start, DateTime(2026, 3, 8)), 2);
      expect(pastPhaseWeekOf(start, DateTime(2026, 3, 29)), 5);
      expect(pastPhaseWeekCount(start, DateTime(2026, 3, 29)), 5);
      expect(pastPhaseWeekOf(start, DateTime(2026, 2, 28)), 0);
      expect(pastPhaseWeekOf(start, DateTime(2026, 2, 22)), 0);
      expect(pastPhaseWeekOf(start, DateTime(2026, 2, 21)), -1);
    });
  });

  group('T5 · restarts and non-adjacent equal stamps', () {
    test('3 ×28 then 1 ×14 → two blocks', () {
      final rows = [
        ..._days(DateTime(2026, 1, 5), 28, stamp: 3),
        ..._days(DateTime(2026, 2, 2), 14, stamp: 1),
      ];
      expect(_bounds(display(rows)),
          [('2026-01-05', '2026-02-01'), ('2026-02-02', '2026-02-15')]);
    });

    test('2, 3, 2 → three blocks (the stamp grouping merges the 2s)', () {
      final rows = [
        ..._days(DateTime(2026, 1, 5), 28, stamp: 2),
        ..._days(DateTime(2026, 2, 2), 28, stamp: 3),
        ..._days(DateTime(2026, 3, 2), 28, stamp: 2),
      ];
      expect(display(rows).length, 3);
      expect(strictPure(rows).length, 2);
    });
  });

  group('T6/T10 · noise and its mirrors', () {
    List<Row> sandwich(List<Row> middle, {int tail = 3}) => [
          ..._days(DateTime(2026, 1, 5), 13, stamp: 3), // Mon Jan 5 - Sat 17
          ...middle,
          ..._days(DateTime(2026, 1, 26), 13, stamp: tail), // Mon 26 - Sat Feb 7
        ];

    test('one stray rest row → one block', () {
      final rows = sandwich([_one(DateTime(2026, 1, 18), stamp: 4, rest: true)]);
      expect(display(rows).length, 1);
    });

    test('two consecutive noise runs → one block', () {
      final rows = sandwich([
        _one(DateTime(2026, 1, 18), stamp: 4, rest: true),
        _one(DateTime(2026, 1, 19), stamp: 4, rest: true),
        _one(DateTime(2026, 1, 20), stamp: 5, rest: true),
        _one(DateTime(2026, 1, 21), stamp: 5, rest: true),
      ]);
      expect(display(rows).length, 1);
    });

    test('a rest-only run of 3 is a block', () {
      final rows = sandwich([
        for (var d = 18; d <= 20; d++)
          _one(DateTime(2026, 1, d), stamp: 4, rest: true),
      ], tail: 5);
      expect(display(rows).length, 3);
    });

    test('a 1-row WORKOUT run is a block (not noise)', () {
      final rows = sandwich([_one(DateTime(2026, 1, 18), stamp: 4)]);
      expect(display(rows).length, 3);
    });

    test('2 rows, one workout + one rest, is a block', () {
      final rows = sandwich([
        _one(DateTime(2026, 1, 18), stamp: 4, rest: true),
        _one(DateTime(2026, 1, 19), stamp: 4),
      ]);
      expect(display(rows).length, 3);
    });

    test('every run noise → runs are blocks', () {
      final rows = [
        _one(DateTime(2026, 1, 4), stamp: 2, rest: true),
        _one(DateTime(2026, 1, 11), stamp: 2, rest: true),
        _one(DateTime(2026, 1, 18), stamp: 3, rest: true),
      ];
      expect(display(rows).length, 2);
    });
  });

  group('T7 · stray stamps never swallow unstamped rows (round 1 A P1-1)', () {
    test('a window of unstamped completed days + Sundays stamped 1', () {
      final rows = <Row>[
        ..._days(DateTime(2026, 1, 5), 28, stamp: 2), // Mon Jan 5 - Sun Feb 1
        for (final r in _days(DateTime(2026, 2, 2), 28, status: 'completed'))
          r.$1.weekday == DateTime.sunday
              ? _one(r.$1, stamp: 1, rest: true)
              : r,
      ];
      expect(_bounds(display(rows)),
          [('2026-01-05', '2026-02-01'), ('2026-02-02', '2026-03-01')]);
    });
  });

  group('T8 · the edge rule and its mirror', () {
    test('unstamped Monday before a stamped Tuesday joins the new window', () {
      final rows = <Row>[
        ..._days(DateTime(2026, 1, 5), 27, stamp: 1), // .. Sat Jan 31
        _one(DateTime(2026, 2, 1)), // unstamped Sunday, old week
        _one(DateTime(2026, 2, 2), status: 'completed'), // unstamped Monday
        ..._days(DateTime(2026, 2, 3), 20, stamp: 2),
      ];
      expect(_bounds(display(rows)),
          [('2026-01-05', '2026-02-01'), ('2026-02-02', '2026-02-22')]);
    });

    test('T8b old window ends mid-week: its own rows stay old', () {
      final rows = <Row>[
        ..._days(DateTime(2026, 1, 5), 24, stamp: 1), // .. Wed Jan 28
      ];
      // Unstamp Mon 26 and Tue 27 (restored completed, before the old last).
      rows.removeWhere((r) =>
          r.$2['date'] == '2026-01-26' || r.$2['date'] == '2026-01-27');
      rows
        ..add(_one(DateTime(2026, 1, 26), status: 'completed'))
        ..add(_one(DateTime(2026, 1, 27), status: 'completed'))
        ..add(_one(DateTime(2026, 1, 29), status: 'completed')) // Thu, after
        ..add(_one(DateTime(2026, 1, 30), status: 'completed')) // Fri, after
        ..addAll(_days(DateTime(2026, 1, 31), 15, stamp: 2)); // from Sat
      final blocks = display(rows);
      expect(_bounds(blocks),
          [('2026-01-05', '2026-01-28'), ('2026-01-29', '2026-02-14')]);
    });
  });

  group('T9 · no stamps', () {
    test('equals the legacy 28-day fallback', () {
      final rows = _days(DateTime(2026, 1, 5), 70);
      expect(_bounds(display(rows)), _bounds(strictPure(rows)));
    });
  });

  group('phaseForDateDisplay', () {
    final f = WorkoutScheduleReadService.phaseForDateDisplay;
    final starts = [
      DateTime(2026, 4, 27),
      DateTime(2026, 6, 1),
      DateTime(2026, 8, 19),
      DateTime(2026, 9, 14),
      DateTime(2026, 10, 12),
    ];
    final planStart = DateTime(2026, 11, 9);
    test('chip numbers of the last currentPhase-1 blocks', () {
      expect(f(5, planStart, DateTime(2026, 6, 10), starts), 1);
      expect(f(5, planStart, DateTime(2026, 8, 20), starts), 2);
      expect(f(5, planStart, DateTime(2026, 9, 28), starts), 3);
      expect(f(5, planStart, DateTime(2026, 11, 1), starts), 4);
      expect(f(5, planStart, DateTime(2026, 11, 20), starts), 5);
    });
    test('hidden older block and before-every-block read 1', () {
      expect(f(5, planStart, DateTime(2026, 5, 1), starts), 1);
      expect(f(5, planStart, DateTime(2026, 1, 1), starts), 1);
      expect(f(3, planStart, DateTime(2026, 9, 28), starts), 1,
          reason: 'cp 3 shows the last 2 blocks; Sep 14 is the 4th of 5');
      expect(f(3, planStart, DateTime(2026, 10, 20), starts), 2);
    });
  });

  group('Hive: readers, agreement, kill switch', () {
    late Directory tempDir;
    const uid = 'aaaaaaaa-bbbb-cccc-dddd-0000000348b3';
    final read = WorkoutScheduleReadService.instance;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      tempDir = Directory.systemTemp.createTempSync('past_runs_');
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
      Hive.init(tempDir.path);
      await Hive.openBox(HiveService.exerciseBoxName);
      await Hive.openBox(HiveService.foodBoxName);
      await Hive.openBox(HiveService.syncBoxName);
      await Hive.openBox(HiveService.configBoxName);
      await Hive.openBox(HiveService.migrationBoxName);
      HiveService.debugMarkInitializedForTests();
      GuardedBox.testBypassOwnership = true;
    });

    tearDownAll(() async {
      GuardedBox.testBypassOwnership = false;
      await HiveUserSession.closeAll();
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    setUp(() async {
      await HiveUserSession.openForUser(uid);
      final wb = HiveService.instance.workoutBox;
      for (final (_, m) in _fixtureRows()) {
        await wb.put('schedule_${m['date']}', m);
      }
      // The current window (stamp 5), so the box looks like the account.
      for (final (_, m) in _days(DateTime(2026, 11, 9), 28, stamp: 5)) {
        await wb.put('schedule_${m['date']}', m);
      }
      await MigratedKey.write(
          'plan_start_date', DateTime(2026, 11, 9).toIso8601String());
      await MigratedKey.write(
          'plan_end_date', DateTime(2026, 12, 6).toIso8601String());
      await HiveService.instance.userBox.put('progress', {'current_phase': 5});
      await HiveService.instance.configBox.delete(
          WorkoutScheduleReadService.kDisablePastPhaseDisplayRunsKey);
    });

    tearDown(() async {
      final wb = HiveService.instance.workoutBox;
      for (final k in wb.keys
          .where((k) => k.toString().startsWith('schedule_'))
          .toList()) {
        await wb.delete(k);
      }
      await HiveService.instance.configBox.delete(
          WorkoutScheduleReadService.kDisablePastPhaseDisplayRunsKey);
      await HiveUserSession.closeAll();
    });

    test('every listed row reads the number of the group that lists it', () {
      final blocks = read.pastPhaseBlocksForDisplay(5);
      final groups = pastPhaseGroupsForTest(blocks, 5, extendWeeks: true);
      expect([for (final g in groups) g.phaseNumber], [1, 2, 3, 4]);
      expect(groups.first.weekCount, 8, reason: 'Jun 1-Jul 23 spans 8 weeks');
      // B-pass: every listed row sits on exactly ONE chip, and the last chip of
      // an extended group is not empty (the chip count and the row-to-chip
      // assignment use the same calendar arithmetic).
      for (final g in groups) {
        final onChips = [for (final c in g.chips) ...c];
        expect(onChips.map(_d).toList()..sort(),
            g.dates.map(_d).toList()..sort(),
            reason: 'PHASE ${g.phaseNumber}: every row on one chip');
        if (g.weekCount > 4) {
          expect(g.chips.last, isNotEmpty,
              reason: 'PHASE ${g.phaseNumber}: W${g.weekCount} lists a row');
        }
        // A chip's ✓ is exactly "a row ON THIS CHIP is completed".
        for (var i = 0; i < g.weekCount; i++) {
          expect(g.chipTicks[i], g.chipStatuses[i].contains('completed'),
              reason: 'PHASE ${g.phaseNumber} W${i + 1} tick');
        }
      }
      final ticks = [for (final g in groups) ...g.chipTicks];
      expect(ticks, contains(true));
      expect(ticks, contains(false),
          reason: 'the fixture needs both, or an off-by-one tick passes');
      for (final g in groups) {
        for (final date in g.dates) {
          expect(read.phaseForDate(date), g.phaseNumber,
              reason: '${_d(date)} is listed under PHASE ${g.phaseNumber}');
        }
      }
      // Gap dates resolve to the PRECEDING block; the hidden Apr block reads 1
      // (it collides with Phase I by design: it is older than every shown one).
      expect(read.phaseForDate(DateTime(2026, 8, 1)), 1);
      expect(read.phaseForDate(DateTime(2026, 9, 1)), 2);
      expect(read.phaseForDate(DateTime(2026, 5, 5)), 1);
      expect(read.phaseForDate(DateTime(2026, 11, 20)), 5);
    });

    test('kill switch: today\'s blocks, 4 chips, strict-index receipts', () async {
      await HiveService.instance.configBox.put(
          WorkoutScheduleReadService.kDisablePastPhaseDisplayRunsKey, true);
      expect(read.pastPhaseDisplayRunsEnabled, isFalse);
      final strict = read.pastPhaseBlocks();
      final shown = read.pastPhaseBlocksForDisplay(5);
      expect(_bounds(shown), _bounds(strict));
      expect(_rowDates(shown), _rowDates(strict));
      final groups = pastPhaseGroupsForTest(shown, 5, extendWeeks: false);
      expect(groups.every((g) => g.weekCount == 4), isTrue);
      final starts = [for (final b in strict) b.startDate];
      for (final date in [
        DateTime(2026, 6, 10),
        DateTime(2026, 9, 28),
        DateTime(2026, 10, 20),
      ]) {
        expect(
            read.phaseForDate(date),
            WorkoutScheduleReadService.phaseForDatePure(
                5, DateTime(2026, 11, 9), date, starts));
      }
    });

    test('kill switch, recovery branch: today\'s stamp grouping', () async {
      // plan_start at the earliest row → strict is empty → recovery branch.
      await MigratedKey.write(
          'plan_start_date', DateTime(2026, 4, 27).toIso8601String());
      final all = <Row>[
        for (final k in HiveService.instance.workoutBox.keys
            .where((k) => k.toString().startsWith('schedule_')))
          () {
            final m = Map<String, dynamic>.from(
                HiveService.instance.workoutBox.get(k) as Map);
            return (DateTime.parse(m['date'] as String), m);
          }(),
      ];
      await HiveService.instance.configBox.put(
          WorkoutScheduleReadService.kDisablePastPhaseDisplayRunsKey, true);
      final old = strictPure(all);
      expect(_bounds(read.pastPhaseBlocksForDisplay(5)),
          _bounds(old.sublist(0, old.length - 1)));
      await HiveService.instance.configBox.delete(
          WorkoutScheduleReadService.kDisablePastPhaseDisplayRunsKey);
      final fixed = display(all);
      expect(_bounds(read.pastPhaseBlocksForDisplay(5)),
          _bounds(fixed.sublist(0, fixed.length - 1)));
    });

    test('T11 a current-window receipt walks no rows', () async {
      // A row whose `date` is not a String makes any block walk throw; the
      // receipt then falls back to 1. Only the short-circuit returns 5.
      final reasons = <String>[];
      ErrorTelemetry.debugOnRecordNonFatalForTests =
          (e, st, {required String reason, extra}) => reasons.add(reason);
      addTearDown(() => ErrorTelemetry.debugOnRecordNonFatalForTests = null);
      await HiveService.instance.workoutBox
          .put('schedule_2026-01-01', {'date': 42});
      expect(read.phaseForDate(DateTime(2026, 11, 20)), 5);
      expect(read.phaseForDate(DateTime(2026, 12, 6)), 5);
      expect(reasons, isEmpty);
      // Control: a past date DOES walk, so the poisoned row is reached.
      expect(read.phaseForDate(DateTime(2026, 9, 28)), 1);
      expect(reasons, ['phase_for_date_fallback']);
    });
  });
}
