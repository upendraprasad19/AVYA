// BEHAVIORAL CONTRACT TEST — day_of_week_completion (OI-390, diagnose dow-skip-rate).
//
// Writer WorkoutRepository.getDayOfWeekCompletionStats / getWorkoutAdherence
// (one walk, _eligibleDaysBack, through classifyScheduleDay) → reader
// PatternDetector._dayOfWeekPattern → snapshot coach_notices.
//
// The bug: a weekday with nothing scheduled read as 0% done, so the coach told a
// user "Skips Sunday workouts 100% of the time" for a rest day (recurrence of
// Bug C, APK Test #3, and OBS-3, APK Test #4 — both fixed prompt-side as
// "fabrication"; the writer was this method).
//
// Clock: UTC-flagged Fri 23 Oct 2026 00:30 IST. The 56-day walk covers
// 2026-08-28..10-22; the 90-day walk 07-25..10-22. Keys are literal strings and
// anchors UTC instants or verbatim strings, so every case is zone-independent.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/core/utils/schedule_day_eligibility.dart';
import 'package:icanbefitter/features/ai_coach/services/pattern_detector.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';

const _done = {'type': 'workout', 'status': 'completed'};
const _miss = {'type': 'workout', 'status': 'planned'};
const _rest = {'type': 'rest', 'status': 'rest'};

/// `YYYY-MM-DD` of [d] days after [from] (UTC calendar arithmetic).
String _add(String from, int d) {
  final t = DateTime.parse('${from}T00:00:00Z').add(Duration(days: d));
  return t.toIso8601String().substring(0, 10);
}

/// Monday of week [w] (0-based) of the 8 full IST weeks in the 56-day window.
String _monday(int w) => _add('2026-08-31', 7 * w);

/// The date of ISO weekday [iso] (1 = Monday) in week [w].
String _day(int w, int iso) => _add(_monday(w), iso - 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_dow_skip_rate');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    resetTestClock();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    for (final name in [
      HiveService.configBoxName,
      HiveService.migrationBoxName,
      'userBox_aaaaaaaa',
      'workoutBox_aaaaaaaa',
      'nutritionBox_aaaaaaaa',
      'healthBox_aaaaaaaa',
      'coachBox_aaaaaaaa',
    ]) {
      if (Hive.isBoxOpen(name)) await Hive.box(name).close();
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
    setTestClockTo(DateTime.utc(2026, 10, 22, 19, 0)); // Fri 23 Oct 00:30 IST
  });

  tearDown(() async {
    resetTestClock();
    await HiveUserSession.closeAll();
  });

  Future<void> seed(Map<String, Map> rows) async {
    final box = HiveService.instance.workoutBox;
    for (final e in rows.entries) {
      await box.put('schedule_${e.key}', Map<String, dynamic>.from(e.value));
    }
  }

  /// Every day of the 8 full weeks: [plan] weekdays get `rowFor(w, iso)`
  /// (default completed), the rest a rest row.
  Map<String, Map> weeks(Set<int> plan, {Map Function(int w, int iso)? rowFor}) {
    final rows = <String, Map>{};
    for (var w = 0; w < 8; w++) {
      for (var iso = 1; iso <= 7; iso++) {
        rows[_day(w, iso)] =
            plan.contains(iso) ? (rowFor?.call(w, iso) ?? _done) : _rest;
      }
    }
    return rows;
  }

  List<CoachingInsight> dow() => PatternDetector.instance
      .analyze()
      .where((i) => i.patternId == 'day_of_week_pattern')
      .toList();

  DayOfWeekStats stats() =>
      WorkoutRepository.instance.getDayOfWeekCompletionStats(weeks: 8);

  // T3: Mon/Wed/Fri; Mondays of weeks 0-4 missed with Wed + Fri done.
  Map<String, Map> t3() =>
      weeks({1, 3, 5}, rowFor: (w, iso) => iso == 1 && w < 5 ? _miss : _done);

  test('T1 Mon-Sat done, Sunday rest: no Sunday key, no insight', () async {
    await seed(weeks({1, 2, 3, 4, 5, 6}));
    expect(stats().byIsoWeekday.containsKey(7), isFalse);
    expect(stats().byIsoWeekday.keys.toSet(), {1, 2, 3, 4, 5, 6});
    expect(dow(), isEmpty);
  });

  test('T2 Mon/Wed/Fri done, others rest or absent: keys {1,3,5}, no insight',
      () async {
    final rows = weeks({1, 3, 5});
    rows.removeWhere((k, v) => v == _rest && k.compareTo('2026-10-01') > 0);
    await seed(rows);
    expect(stats().byIsoWeekday.keys.toSet(), {1, 3, 5});
    expect(dow(), isEmpty);
  });

  test('T3 five isolated Monday misses fire the exact notice', () async {
    await seed(t3());
    final got = dow();
    expect(got, hasLength(1));
    expect(got.single.coachNotice,
        'Missed 5 of 8 scheduled Monday workouts since 2026-08-31.');
  });

  test('T3b the walk covers 2026-08-28..2026-10-22', () async {
    await seed({...t3(), '2026-08-28': _done, '2026-10-22': _done});
    final days = stats().days;
    expect(days.first.istDate, '2026-08-28');
    expect(days.last.istDate, '2026-10-22');
  });

  test('T3c istWeekMondayOf', () {
    expect(istWeekMondayOf('2026-10-19'), '2026-10-19');
    expect(istWeekMondayOf('2026-10-25'), '2026-10-19');
    expect(istWeekMondayOf('2026-01-01'), '2025-12-29');
    expect(istWeekMondayOf('bad'), isNull);
  });

  test('T3d tie on isolated misses: the lower rate wins over Mon→Sun order',
      () async {
    // Mon-Fri plan. Week 5 (index 5) fully missed (no isolated misses there).
    // Monday: weeks 0-2 rest, 3 and 4 isolated misses, 5 missed, 6-7 done
    //   → eligible 5, completed 2 (0.4), 2 isolated.
    // Wednesday: weeks 0-3 rest, 4 and 6 isolated misses, 5 missed, 7 done
    //   → eligible 4, completed 1 (0.25), 2 isolated.
    await seed(weeks({1, 2, 3, 4, 5}, rowFor: (w, iso) {
      if (w == 5) return _miss;
      if (iso == 1) return w < 3 ? _rest : (w < 5 ? _miss : _done);
      if (iso == 3) return w < 4 ? _rest : (w == 7 ? _done : _miss);
      return _done;
    }));
    final s = stats().byIsoWeekday;
    expect(s[1]!.eligible, 5);
    expect(s[1]!.completed, 2);
    expect(s[3]!.eligible, 4);
    expect(s[3]!.completed, 1);
    expect(dow().single.coachNotice,
        'Missed 3 of 4 scheduled Wednesday workouts since 2026-09-30.');
  });

  test('T3e a miss with only ONE other eligible day that week is not isolated',
      () async {
    await seed(
        weeks({1, 3}, rowFor: (w, iso) => iso == 1 && w < 5 ? _miss : _done));
    expect(dow(), isEmpty);
  });

  // B-pass 3e9c037a4702 F1: a week is judged on its WALKED days only, so the
  // current week (Monday to yesterday) can hide a miss until its other days
  // are walked. Mondays: weeks 0-4 missed with Wednesday also missed (not
  // isolated), week 5 isolated, week 6 done, week 7 (10-19) missed.
  Map<String, Map> t3f() => weeks({1, 3, 5}, rowFor: (w, iso) {
        if (iso == 1) return w == 6 ? _done : _miss;
        if (iso == 3) return w < 5 ? _miss : _done;
        return _done;
      });

  test('T3f a current-week miss with one walked other day is not isolated',
      () async {
    await seed(t3f()); // today Fri 10-23 is not walked: week 7 has only Wed
    expect(stats().byIsoWeekday[1]!.eligible, 8);
    expect(dow(), isEmpty);
  });

  test('T3f mirror: once Friday is walked, the same miss is isolated',
      () async {
    setTestClockTo(DateTime.utc(2026, 10, 23, 19, 0)); // Sat 24 Oct 00:30 IST
    await seed(t3f());
    expect(dow().single.coachNotice,
        'Missed 7 of 8 scheduled Monday workouts since 2026-08-31.');
  });

  test('T4 today is never walked; a walked day with no row is not counted',
      () async {
    setTestClockTo(DateTime.utc(2026, 10, 26, 4, 30)); // Mon 26 Oct 10:00 IST
    final rows = t3()..remove('2026-08-31');
    rows['2026-10-26'] = _miss; // today, a planned Monday
    await seed(rows);
    expect(stats().byIsoWeekday[1]!.eligible, 7);
  });

  test('T5 travel / paused / moved Mondays are not misses', () async {
    final statuses = ['travel', 'travel', 'paused', 'moved'];
    await seed(weeks({1, 3, 5}, rowFor: (w, iso) {
      if (iso != 1) return _done;
      if (w < 4) return {'type': 'workout', 'status': statuses[w]};
      return w < 6 ? _miss : _done;
    }));
    final m = stats().byIsoWeekday[1]!;
    expect((m.eligible, m.completed), (4, 2));
    expect(dow(), isEmpty);
  });

  test('T6 6-day plan, every day missed for 8 weeks: no insight', () async {
    await seed(weeks({1, 2, 3, 4, 5, 6}, rowFor: (_, _) => _miss));
    expect(dow(), isEmpty);
  });

  // upendra's live scheduled_workouts (read-only SELECT, 2026-10-23), mapped as
  // the restore maps them: status rest → a rest row; a template row →
  // custom_template; else workout. 08-19..08-24 are planned rows of an
  // abandoned first plan (no anchor here: the fixture has no profile).
  Map<String, Map> upendra() {
    const live = {
      '2026-08-19': ('planned', true), '2026-08-20': ('planned', false),
      '2026-08-21': ('planned', true), '2026-08-22': ('planned', true),
      '2026-08-23': ('planned', false), '2026-08-24': ('planned', false),
      '2026-08-25': ('rest', false),
      '2026-09-14': ('completed', false), '2026-09-15': ('completed', false),
      '2026-09-16': ('completed', false), '2026-09-17': ('completed', false),
      '2026-09-18': ('completed', false), '2026-09-19': ('completed', false),
      '2026-09-20': ('rest', false),
      '2026-09-21': ('completed', false), '2026-09-22': ('completed', false),
      '2026-09-23': ('completed', false), '2026-09-24': ('completed', true),
      '2026-09-25': ('planned', false), '2026-09-26': ('completed', true),
      '2026-09-27': ('rest', false),
      '2026-09-28': ('completed', true), '2026-09-29': ('completed', false),
      '2026-09-30': ('completed', false), '2026-10-01': ('completed', false),
      '2026-10-02': ('completed', false), '2026-10-03': ('planned', false),
      '2026-10-04': ('rest', false),
      '2026-10-05': ('planned', false), '2026-10-06': ('planned', false),
      '2026-10-07': ('completed', false), '2026-10-08': ('planned', false),
      '2026-10-09': ('completed', false), '2026-10-10': ('planned', false),
      '2026-10-11': ('rest', false),
      '2026-10-12': ('planned', false), '2026-10-13': ('planned', false),
      '2026-10-14': ('planned', false), '2026-10-15': ('planned', false),
      '2026-10-16': ('planned', false), '2026-10-17': ('planned', false),
      '2026-10-18': ('rest', false),
      '2026-10-19': ('planned', false), '2026-10-20': ('planned', false),
      '2026-10-21': ('completed', false), '2026-10-22': ('planned', false),
      '2026-10-23': ('planned', false),
    };
    return {
      for (final e in live.entries)
        e.key: e.value.$1 == 'rest'
            ? _rest
            : {
                'type': e.value.$2 ? 'custom_template' : 'workout',
                'status': e.value.$1,
              },
    };
  }

  test('T7 upendra: counts as in the plan §0, no weekday named', () async {
    await seed(upendra());
    final s = stats().byIsoWeekday;
    expect(s.containsKey(7), isFalse);
    expect({for (final e in s.entries) e.key: (e.value.eligible, e.value.completed)},
        {1: (6, 3), 2: (6, 3), 3: (6, 5), 4: (6, 3), 5: (5, 3), 6: (5, 2)});
    expect(dow(), isEmpty);
  });

  test('T8 a missed custom_template Monday counts like a workout', () async {
    final rows = t3();
    rows['2026-08-31'] = {'type': 'custom_template', 'status': 'planned'};
    await seed(rows);
    expect(dow().single.coachNotice,
        'Missed 5 of 8 scheduled Monday workouts since 2026-08-31.');
  });

  test('T9 logged + completed counts as completed; never a miss', () async {
    const logged = {'type': 'logged', 'status': 'completed'};
    final rows = weeks({1, 3, 5});
    rows[_day(7, 1)] = logged; // a late-restored Monday completion
    for (var w = 0; w < 3; w++) {
      rows[_day(w, 7)] = logged; // unplanned Sunday sessions
    }
    await seed(rows);
    final s = stats().byIsoWeekday;
    expect((s[7]!.eligible, s[7]!.completed), (3, 3));
    expect((s[1]!.eligible, s[1]!.completed), (8, 8));
    expect(dow(), isEmpty);
  });

  test('T10 onboarding anchor: its IST date counts, the day before does not',
      () async {
    await HiveService.instance.userBox
        .put('profile', {'onboarding_completed_at': '2026-09-13T20:00:00Z'});
    await seed({'2026-09-13': _miss, '2026-09-14': _miss});
    final dates = stats().days.map((d) => d.istDate).toList();
    expect(dates, contains('2026-09-14'));
    expect(dates, isNot(contains('2026-09-13')));
  });

  test('T10b wlog_ anchor: its date string verbatim', () async {
    await HiveService.instance.workoutBox
        .put('wlog_first', {'date': '2026-09-14'});
    await seed({'2026-09-13': _miss, '2026-09-14': _miss});
    final dates = stats().days.map((d) => d.istDate).toList();
    expect(dates, contains('2026-09-14'));
    expect(dates, isNot(contains('2026-09-13')));
  });

  test('T11 no Monday in the last 14 walked days: no insight', () async {
    await seed(weeks({1, 3, 5}, rowFor: (w, iso) {
      if (iso != 1) return _done;
      return w < 4 ? _miss : _rest;
    }));
    expect(dow(), isEmpty);
  });

  test('T12 classifyScheduleDay table', () {
    const ex = ScheduleDayKind.excluded;
    const pe = ScheduleDayKind.pending;
    const co = ScheduleDayKind.completed;
    final table = <Map?, ScheduleDayKind>{
      null: ex,
      {'type': 'rest', 'status': 'planned'}: ex,
      {'type': 'off', 'status': 'planned'}: ex,
      {'type': 'workout', 'status': 'rest'}: ex,
      {'type': 'workout', 'status': 'travel'}: ex,
      {'type': 'workout', 'status': 'paused'}: ex,
      {'type': 'workout', 'status': 'moved'}: ex,
      {'type': 'workout', 'status': 'dropped'}: ex,
      {'type': 'workout', 'status': 'planned', 'reason': 'pre_onboarding'}: ex,
      {'type': 'workout', 'status': 'completed'}: co,
      {'type': 'custom_template', 'status': 'completed'}: co,
      {'type': 'logged', 'status': 'completed'}: co,
      {'type': 'mystery', 'status': 'completed'}: co,
      {'type': 'logged', 'status': 'planned'}: ex,
      {'type': 'workout', 'status': 'planned'}: pe,
      {'type': 'custom_template', 'status': 'planned'}: pe,
      {'type': 'workout'}: pe,
    };
    for (final e in table.entries) {
      expect(classifyScheduleDay(e.key), e.value, reason: '${e.key}');
    }
  });

  test('T14 getWorkoutAdherence(90) on upendra: today (planned) not counted',
      () async {
    await seed(upendra());
    expect(WorkoutRepository.instance.getWorkoutAdherence(days: 90),
        {'planned': 40, 'completed': 19, 'missed': 21, 'rate_percent': 47});
  });

  test('T14b nothing eligible: rate_percent is omitted, not 0', () async {
    await HiveService.instance.userBox
        .put('profile', {'onboarding_completed_at': '2026-10-22T19:00:00Z'});
    await seed({...t3(), '2026-10-23': _miss}); // today, not yet done
    final anchored = WorkoutRepository.instance.getWorkoutAdherence(days: 90);
    expect(anchored['planned'], 0);
    expect(anchored.containsKey('rate_percent'), isFalse);

    await HiveService.instance.userBox.delete('profile');
    await seed(weeks({1, 2, 3, 4, 5, 6, 7},
        rowFor: (_, _) => {'type': 'workout', 'status': 'travel'}));
    final travel = WorkoutRepository.instance.getWorkoutAdherence(days: 56);
    expect(travel['planned'], 0);
    expect(travel.containsKey('rate_percent'), isFalse);
  });

  test('T14c today counts once completed, not while planned', () async {
    await seed({'2026-10-23': _done, '2026-10-22': _miss});
    expect(WorkoutRepository.instance.getWorkoutAdherence(days: 7),
        {'planned': 2, 'completed': 1, 'missed': 1, 'rate_percent': 50});
    await seed({'2026-10-23': _miss});
    expect(WorkoutRepository.instance.getWorkoutAdherence(days: 7),
        {'planned': 1, 'completed': 0, 'missed': 1, 'rate_percent': 0});
  });

  test('T16 only 2 eligible Mondays (both isolated misses): no insight',
      () async {
    await seed(weeks({1, 3, 5}, rowFor: (w, iso) {
      if (iso != 1) return _done;
      // 10-05 and 10-12 (inside the last 14 walked days): both isolated, so
      // only condition 1 (eligible >= 3) holds the insight back.
      return w == 5 || w == 6 ? _miss : _rest;
    }));
    expect(stats().byIsoWeekday[1]!.eligible, 2);
    expect(dow(), isEmpty);
  });
}
