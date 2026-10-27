// B2 Task 7 (docs/plans/2026-10-22-session-set-budget.md): the ON-world gate.
//
// The REAL `PlanGenerator.generateV4` with `enable_session_set_budget` ON, over
// 4 goals x 4 tiers x days {3,4,5,6} x 3 levels x phases {1,4,5} x minutes
// {30,60,90} = 1,728 runs, plus 48 runs with no minutes at all (build_muscle,
// phase 1: the 60-minute default), plus a focus grid. `enable_core_list_pool` is
// ON for the build_muscle subset.
//
// Hard zeros (every one is asserted; a non-empty list prints the first offenders):
//  - time:        a day (any of the 4 weeks) whose INDEPENDENT minutes, with its
//                 warm-up and cool-down, exceed the user's minutes + 2;
//  - precondition (M6): 2 x (days whose lead lift, as the allocator ranks it,
//                 credits a group) <= that group's weekly top. This checks
//                 bookkeeping, not the model's truth;
//  - caps:        a group over its session cap or its weekly top, in any week;
//  - lighter phase: a phase-4 weekly total over the band bottom;
//  - empty days:  a day with no exercises;
//  - forced:      `capForcedFirst` above 0;
//  - lead lift:   a day's lead lift holding < 2 sets while >= 5 minutes are unused;
//  - lost lifts:  a day (any of the 4 weeks) that ends with no budgeted exercise, and
//                 a day the allocator saw with budgeted exercises that ends with none;
//  - allocator ran: `SessionSetAllocator.debugLastStats` is reset before each run and
//                 must hold the variant(s) afterwards, so no allocator-derived zero
//                 can pass on a previous run's numbers or on nothing at all;
//  - display:     `SessionBudget.estimateDaySecondsFromPlanDay`, fed the stored shape
//                 of the final plan's day (`WorkoutDay.toMap()`), equals the oracle's
//                 seconds, so what Train and Home show is what the gate priced.
//
// The oracle below shares NOTHING with `SessionBudget`: its constants, its
// archetype rule, its muscle-group mapper and its band tables are restated here
// from the plan (Q4 section 4.2, Rulings 4 and 12), so a drift in either side
// reddens the gate. It prices the final plan's sets at each exercise's own
// `restSeconds` as the plan carries it. It restates only what the generator can
// reach: a generated plan has no cardio / distance row and no timed row prescribed
// in minutes (B-pass R3 P2-1 prices those in the engine and the display, and the
// behavioural tests pin them), so its B rule is the flat 40 s a set.
//
// `WRITE_SESSION_BUDGET_REPORT=1` also writes `session_set_budget_report.md`.
@Timeout(Duration(minutes: 12))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_set_allocator.dart';

const _flag = 'enable_session_set_budget';
const _goals = ['build_muscle', 'lose_fat', 'strength', 'general_fitness'];
const _tiers = ['bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym'];
const _dayCounts = [3, 4, 5, 6];
const _levels = ['beginner', 'intermediate', 'advanced'];
const _phases = [1, 4, 5];
const _minutesGrid = [30, 60, 90];

// ── The oracle: restated, not imported ───────────────────────────────────────

const _work = {'H': 23, 'M': 35, 'I': 47, 'B': 40};
const _setup = {'H': 120, 'M': 90, 'I': 45, 'B': 30};

double _exSecs(String archetype, int sets, int rest) =>
    sets <= 0 ? 0 : 1.2 * (_setup[archetype]! + sets * _work[archetype]! + (sets - 1) * rest);

int? _lowerBound(Object? repRange) {
  final m = RegExp(r'^\s*(\d+)\s*-\s*(\d+)\s*$').firstMatch('$repRange');
  if (m == null) return null;
  final lo = int.parse(m.group(1)!), hi = int.parse(m.group(2)!);
  return (lo > 0 && hi > 0 && lo <= hi) ? lo : null;
}

String _archetype(Map<String, dynamic> row) {
  final lt = '${row['logging_type'] ?? 'weight_reps'}';
  if (lt == 'timed' || lt == 'cardio' || lt == 'distance') return 'B';
  final types = {
    for (final t in (row['exercise_type'] as List? ?? const ['compound'])) '$t'.trim().toLowerCase()
  };
  final lo = _lowerBound(row['rep_range']);
  if (types.contains('compound')) return (lo != null && lo <= 6) ? 'H' : 'M';
  if (types.contains('isolation')) return 'I';
  if (types.contains('calisthenics')) return (lo != null && lo <= 10) ? 'M' : 'B';
  return 'B';
}

Set<String> _groups(Iterable<Object?> muscles) {
  final out = <String>{};
  for (final raw in muscles) {
    final t = '$raw'.toLowerCase().replaceAll(RegExp(r'\(.*?\)'), '').trim();
    if (t.isEmpty) continue;
    if (t.contains('lower back') || t.contains('erector') || t.contains('spinal')) continue;
    if (t.contains('chest') || t.contains('pec')) out.add('Chest');
    if (RegExp(r'(^|[^a-z])lats?($|[^a-z])').hasMatch(t) ||
        t.contains('back') ||
        t.contains('trap') ||
        t.contains('rhomboid')) {
      out.add('Back');
    }
    if (t.contains('delt') || t.contains('shoulder')) out.add('Shoulders');
    if (t.contains('bicep') || t.contains('brachialis')) out.add('Biceps');
    if (t.contains('tricep')) out.add('Triceps');
    if (t.contains('quad')) out.add('Quads');
    if (t.contains('hamstring')) out.add('Hamstrings');
    if (t.contains('glute')) out.add('Glutes');
    if (t.contains('abs') || t.contains('oblique') || t.contains('core') || t.contains('transverse')) {
      out.add('Core');
    }
    if (t.contains('calf') || t.contains('calves') || t.contains('gastrocnemius') || t.contains('soleus')) {
      out.add('Calves');
    }
  }
  return out;
}

// goal -> level -> (bottom, top, cap)
const _table = {
  'build_muscle': {
    'beginner': (10, 12, 6),
    'intermediate': (12, 16, 8),
    'advanced': (14, 20, 10),
  },
  'strength': {
    'beginner': (10, 12, 6),
    'intermediate': (10, 14, 8),
    'advanced': (12, 16, 10),
  },
  'lose_fat': {
    'beginner': (10, 12, 6),
    'intermediate': (10, 14, 8),
    'advanced': (12, 16, 8),
  },
  'general_fitness': {
    'beginner': (10, 10, 6),
    'intermediate': (10, 12, 8),
    'advanced': (12, 14, 8),
  },
};

// ── One persona ──────────────────────────────────────────────────────────────

class _P {
  _P(this.goal, this.tier, this.days, this.level, this.phase, this.minutes,
      {this.focus = const [], this.injuries = const []});
  final String goal, tier, level;
  final int days, phase;
  final int? minutes;
  final List<String> focus;
  final List<String> injuries;

  /// `recompose` plans as build_muscle (the generator's own mapping).
  String get planGoal => goal == 'recompose' ? 'build_muscle' : goal;
  int get effMinutes => minutes ?? 60;
  bool get lighter => phase % 4 == 0;
  String get effLevel => PlanGenerator.effectiveLevel(level, phase);
  Set<String> get focusGroups => _groups(focus);
  String get label => '$goal|$tier|${days}d|$level|p$phase|${minutes ?? 'null'}min'
      '${focus.isEmpty ? '' : '|focus ${focus.join('+')}'}'
      '${injuries.isEmpty ? '' : '|injured ${injuries.join('+')}'}';
  int get bottom => _table[planGoal]![effLevel]!.$1;
  int top(String g) => lighter ? bottom : (focusGroups.contains(g) ? 25 : _table[planGoal]![effLevel]!.$2);
  int cap(String g) =>
      (!lighter && focusGroups.contains(g)) ? 12 : _table[planGoal]![effLevel]!.$3;
}

/// What the report keeps from one run.
class _Agg {
  int runs = 0;
  final cell = <String, List<List<num>>>{}; // 'minutes|days|level' -> [[exCount, sets, minutes]]
  final unused = <int, List<double>>{}; // minutes -> unused minutes per day
  final belowFloor = <String, int>{}; // 'label' and 'Group:label'
  int timeForced = 0;
  final timeForcedOver = <double>[]; // minutes over the user's minutes, forced lead lifts only
  final timeForcedOverWhere = <String>[];
  int days = 0; // every day of weeks 1-4 of every run
  int daysOverMinutes = 0; // days longer than the user's own minutes, by any amount
  double worstOverMinutes = 0; // the largest such overage, in minutes
  final overs = <double>[]; // every such overage, in minutes
  int leadDays = 0; // allocator days with a budgeted exercise (lead lifts)
  int leadAbsent = 0; // ...whose lead lift was not kept (a cheaper lift filled the day)
  int displayChecked = 0; // days compared with the display estimate
  final focusWeekly = <String, List<int>>{}; // 'days' -> weekly Chest sets, week 1
  final founder = <String, String>{}; // 'none' / 'Chest' -> markdown
}

final _agg = _Agg();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;
  late Map<String, Map<String, dynamic>> byName;
  late Map<String, Map<String, dynamic>> rowsById;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('session_budget_gate');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    final exBox = await Hive.openBox(HiveService.exerciseBoxName);
    final rows = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync())
            as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    for (final r in rows) {
      await exBox.put((r['id'] ?? r['name']).toString(), r);
    }
    byName = {for (final r in rows) (r['name'] as String).toLowerCase(): r};
    rowsById = {for (final r in rows) r['id'] as String: r};
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
    await HiveService.instance.configBox.put(_flag, true);
  });

  tearDownAll(() async {
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  bool budgeted(PlannedExercise e) =>
      e.customOrigin == null &&
      !const {'timed', 'cardio', 'distance'}.contains(e.loggingType) &&
      byName.containsKey(e.exerciseName.toLowerCase());

  double exSeconds(PlannedExercise e) {
    final row = byName[e.exerciseName.toLowerCase()];
    final arch = row == null ? 'B' : _archetype(row);
    return _exSecs(arch, e.sets, e.restSeconds);
  }

  double itemSeconds(PlannedExercise e) {
    if (e.loggingType == 'timed') {
      final d = RegExp(r'\d+').firstMatch(e.reps)?.group(0);
      return d == null ? 30.0 : double.parse(d);
    }
    return _exSecs('B', e.sets, e.restSeconds);
  }

  double daySeconds(WorkoutDay d) =>
      d.exercises.fold(0.0, (a, e) => a + exSeconds(e)) +
      d.warmup.fold(0.0, (a, e) => a + itemSeconds(e)) +
      d.cooldown.fold(0.0, (a, e) => a + itemSeconds(e));

  Map<String, int> sessionGroups(WorkoutDay d) {
    final per = <String, int>{};
    for (final e in d.exercises.where(budgeted)) {
      for (final g in _groups(byName[e.exerciseName.toLowerCase()]!['primary_muscles'] as List)) {
        per[g] = (per[g] ?? 0) + e.sets;
      }
    }
    return per;
  }

  double median(List<num> v) {
    if (v.isEmpty) return 0;
    final s = [...v]..sort();
    final m = s.length ~/ 2;
    return s.length.isOdd ? s[m].toDouble() : (s[m - 1] + s[m]) / 2;
  }

  Phase gen(_P p) => PlanGenerator.instance.generateV4(
        goal: p.goal,
        equipment: p.tier,
        daysPerWeek: p.days,
        phase: p.phase,
        experienceLevel: p.level,
        injuries: p.injuries,
        bodyFocus: p.focus,
        sessionDuration: p.minutes,
        previousWeights: const {},
      );

  /// Runs [p], checks every hard zero, and returns the plan. Failures append to
  /// [bad] keyed by the zero's name.
  Phase check(_P p, Map<String, List<String>> bad) {
    void fail(String zero, String why) => (bad[zero] ??= []).add('${p.label}: $why');
    // Reset, so a stat read below is THIS run's or absent, never a previous run's.
    SessionSetAllocator.debugLastStats = null;
    final plan = gen(p);
    final stats = SessionSetAllocator.debugLastStats;
    _agg.runs++;
    final limitMin = p.effMinutes + 2;
    final wantVariants = p.days == 6 ? const ['A'] : const ['A', 'B'];
    for (final v in wantVariants) {
      if (stats == null || !stats.containsKey(v)) fail('allocator ran', 'no stats for variant $v');
    }

    for (var w = 0; w < plan.weekPlans.length; w++) {
      final weekGroups = <String, int>{};
      // Weeks 2 and 4 show the B list of a day (the 6-day plan has one list).
      final variant = (w == 1 || w == 3) && p.days != 6 ? 'B' : 'A';
      final forcedDays = stats?[variant]?.forcedDays ?? const <int>[];
      final days = plan.weekPlans[w].workoutDays;
      for (var di = 0; di < days.length; di++) {
        final d = days[di];
        if (d.exercises.isEmpty) fail('empty days', 'week ${w + 1} ${d.name}');
        // Oracle-side: no day may end without a budgeted lift, whatever the allocator says.
        if (d.exercises.isNotEmpty && !d.exercises.any(budgeted)) {
          fail('lost lifts', 'week ${w + 1} ${d.name} carries no budgeted exercise');
        }
        final mins = daySeconds(d) / 60;
        _agg.days++;
        if (mins > p.effMinutes + 0.05) {
          _agg.daysOverMinutes++;
          _agg.overs.add(mins - p.effMinutes);
          if (mins - p.effMinutes > _agg.worstOverMinutes) _agg.worstOverMinutes = mins - p.effMinutes;
        }
        // The display prices the STORED day (`toMap()`), and must say what the oracle did.
        final shown = SessionBudget.estimateDaySecondsFromPlanDay(d.toMap(), rowsById);
        _agg.displayChecked++;
        if ((shown - daySeconds(d)).abs() > 1e-6) {
          fail('display', 'week ${w + 1} ${d.name} display ${shown.toStringAsFixed(1)} s, oracle '
              '${daySeconds(d).toStringAsFixed(1)} s');
        }
        if (mins > limitMin) {
          // The ONE overage allowed: the day's lead lift, put on by the empty-day
          // guard although the not-budgeted rows (timed, cardio, distance: they keep
          // their sets, Ruling 8) had already spent the day's time. It is exempt only
          // when the allocator says it forced this very day AND the day, without
          // that lift, is back inside the limit. Anything else over the limit fails.
          final lead = d.exercises.where(budgeted).firstOrNull;
          final explained = lead != null &&
              forcedDays.contains(di) &&
              mins - exSeconds(lead) / 60 <= limitMin;
          if (explained) {
            _agg.timeForcedOver.add(mins - p.effMinutes); // minutes over the user's own minutes
            _agg.timeForcedOverWhere.add(p.label);
          } else {
            fail('time', 'week ${w + 1} ${d.name} ${mins.toStringAsFixed(1)} min > $limitMin');
          }
        }
        final per = sessionGroups(d);
        per.forEach((g, n) {
          weekGroups[g] = (weekGroups[g] ?? 0) + n;
          if (n > p.cap(g)) fail('caps', 'week ${w + 1} ${d.name} $g $n > session cap ${p.cap(g)}');
        });
      }
      weekGroups.forEach((g, n) {
        if (n > p.top(g)) {
          fail(p.lighter ? 'lighter phase' : 'caps',
              'week ${w + 1} $g $n > weekly ${p.lighter ? 'band bottom' : 'top'} ${p.top(g)}');
        }
      });
    }

    // M6 precondition, per allocated variant: the lead lift is the allocator's rank 0
    // (the split's first slot of the day), which the final plan's own order need not
    // keep (sequencing runs later), so the groups come from the allocator's own
    // `firstLifts`, not from the first exercise of the finished day.
    (stats ?? const <String, AllocationStats>{}).forEach((variant, s) {
      final lead = <String, int>{};
      for (final f in s.firstLifts) {
        for (final g in f.groups) {
          lead[g] = (lead[g] ?? 0) + 1;
        }
      }
      lead.forEach((g, n) {
        if (2 * n > p.top(g)) {
          fail('precondition', '$variant: $g leads $n days, 2 x $n > weekly top ${p.top(g)}');
        }
      });
    });

    // Lost lifts: a day the allocator saw with budgeted exercises must still carry
    // one in the final plan (the empty-day guard's job). Variant A is week 1, B is
    // week 2; a 6-day plan has A only.
    (stats ?? const <String, AllocationStats>{}).forEach((variant, s) {
      final w = variant == 'A' ? 0 : 1;
      if (w >= plan.weekPlans.length) return;
      final days = plan.weekPlans[w].workoutDays;
      for (final f in s.firstLifts) {
        if (f.day < days.length && !days[f.day].exercises.any(budgeted)) {
          fail('lost lifts', '$variant day ${f.day} ${days[f.day].name} had budgeted exercises, the plan carries none');
        }
      }
    });

    for (final s in (stats ?? const <String, AllocationStats>{}).values) {
      if (s.capForcedFirst > 0) fail('forced', 'capForcedFirst ${s.capForcedFirst}');
      _agg.timeForced += s.timeForcedFirst;
      s.belowFloor.forEach((g, label) {
        _agg.belowFloor[label] = (_agg.belowFloor[label] ?? 0) + 1;
        _agg.belowFloor['$g:$label'] = (_agg.belowFloor['$g:$label'] ?? 0) + 1;
      });
      for (final f in s.firstLifts) {
        _agg.leadDays++;
        if (f.sets == 0) _agg.leadAbsent++;
        if (f.sets < 2 && f.secondsLeft >= 300) {
          fail('lead lift', 'day ${f.day} lead lift ${f.sets} set(s), ${(f.secondsLeft / 60).toStringAsFixed(1)} min unused');
        }
      }
    }

    if (p.phase == 1 && p.minutes != null && p.focus.isEmpty) {
      final key = '${p.minutes}|${p.days}|${p.level}';
      for (final d in plan.weekPlans.first.workoutDays) {
        (_agg.cell[key] ??= []).add([
          d.exercises.length,
          d.exercises.fold(0, (a, e) => a + e.sets),
          daySeconds(d) / 60,
        ]);
        (_agg.unused[p.minutes!] ??= []).add(p.minutes! - daySeconds(d) / 60);
      }
    }
    return plan;
  }

  void expectNoZeros(Map<String, List<String>> bad, int runs, int expected) {
    expect(runs, expected, reason: 'the grid is not what the plan says');
    final buf = StringBuffer();
    bad.forEach((zero, list) {
      buf.writeln('$zero: ${list.length} offender(s)');
      for (final x in list.take(8)) {
        buf.writeln('   $x');
      }
    });
    expect(bad, isEmpty, reason: '\n$buf');
  }

  for (final tier in _tiers) {
    test('hard zeros over the grid: $tier', () async {
      final bad = <String, List<String>>{};
      var runs = 0;
      for (final goal in _goals) {
        await HiveService.instance.configBox.put('enable_core_list_pool', goal == 'build_muscle');
        for (final days in _dayCounts) {
          for (final level in _levels) {
            for (final phase in _phases) {
              for (final minutes in _minutesGrid) {
                check(_P(goal, tier, days, level, phase, minutes), bad);
                runs++;
              }
            }
            if (goal == 'build_muscle') {
              check(_P(goal, tier, days, level, 1, null), bad);
              runs++;
            }
          }
        }
      }
      await HiveService.instance.configBox.delete('enable_core_list_pool');
      expectNoZeros(bad, runs, 4 * 4 * 3 * 3 * 3 + 12);
    });
  }

  test('hard zeros with a focus muscle (cap 12, top 25) and the founder case', () async {
    await HiveService.instance.configBox.put('enable_core_list_pool', true);
    final bad = <String, List<String>>{};
    var runs = 0;
    for (final days in _dayCounts) {
      for (final level in _levels) {
        for (final minutes in const [60, 90]) {
          final plan = check(_P('build_muscle', 'full_gym', days, level, 1, minutes, focus: const ['Chest']), bad);
          runs++;
          if (level == 'intermediate' && minutes == 90) {
            var chest = 0;
            for (final d in plan.weekPlans.first.workoutDays) {
              chest += sessionGroups(d)['Chest'] ?? 0;
            }
            (_agg.focusWeekly['${days}d'] ??= []).add(chest);
          }
        }
      }
    }
    // The founder case: intermediate, build_muscle, full_gym, 6 days, 90 minutes,
    // focus none, then focus Chest. Weeks 1-4 of phase 1.
    for (final focus in const [<String>[], ['Chest']]) {
      final p = _P('build_muscle', 'full_gym', 6, 'intermediate', 1, 90, focus: focus);
      final plan = check(p, bad);
      runs++;
      final md = StringBuffer();
      for (var w = 0; w < plan.weekPlans.length; w++) {
        final totals = <String, int>{};
        md.writeln('\n**Week ${w + 1}**\n');
        md.writeln('| day | exercises | sets | minutes (with warm-up and cool-down) |');
        md.writeln('|---|---|---|---|');
        for (final d in plan.weekPlans[w].workoutDays) {
          md.writeln('| ${d.name} | ${d.exercises.length} | '
              '${d.exercises.fold(0, (a, e) => a + e.sets)} | ${(daySeconds(d) / 60).toStringAsFixed(1)} |');
          sessionGroups(d).forEach((g, n) => totals[g] = (totals[g] ?? 0) + n);
        }
        final order = totals.keys.toList()..sort();
        md.writeln('\nWeekly sets: ${[for (final g in order) '$g ${totals[g]}'].join(', ')}');
      }
      _agg.founder[focus.isEmpty ? 'none' : focus.first] = md.toString();
    }
    await HiveService.instance.configBox.delete('enable_core_list_pool');
    expectNoZeros(bad, runs, 4 * 3 * 2 + 2);
  });

  test('hard zeros: the recompose goal (plans as build_muscle) and injured users', () async {
    // The grid's four goal tokens are not the app's five: onboarding also offers
    // `recompose`, which the generator plans as build_muscle but through its own
    // cardio path. And an injured user's days are thinner (top-up, exclusions).
    await HiveService.instance.configBox.put('enable_core_list_pool', true);
    final bad = <String, List<String>>{};
    var runs = 0;
    for (final tier in const ['full_gym', 'home_dumbbells']) {
      for (final days in const [3, 4, 5]) {
        for (final minutes in _minutesGrid) {
          check(_P('recompose', tier, days, 'intermediate', 1, minutes), bad);
          runs++;
        }
      }
    }
    for (final injuries in const [
      ['knee'],
      ['shoulder'],
      ['lower_back'],
    ]) {
      for (final days in const [3, 4, 6]) {
        for (final minutes in _minutesGrid) {
          check(_P('build_muscle', 'full_gym', days, 'intermediate', 1, minutes, injuries: injuries),
              bad);
          runs++;
        }
      }
    }
    await HiveService.instance.configBox.delete('enable_core_list_pool');
    expectNoZeros(bad, runs, 2 * 3 * 3 + 3 * 3 * 3);
  });

  test('report', () async {
    if (Platform.environment['WRITE_SESSION_BUDGET_REPORT'] != '1') {
      markTestSkipped('set WRITE_SESSION_BUDGET_REPORT=1 to write the report');
      return;
    }
    final b = StringBuffer()
      ..writeln('# Session set budget: ON-world report')
      ..writeln()
      ..writeln('Generated by `test/plan_generator/session_set_budget_gate_test.dart` '
          '(`WRITE_SESSION_BUDGET_REPORT=1`). ${_agg.runs} real `generateV4` runs, flag ON.')
      ..writeln()
      ..writeln('The "precondition" hard zero checks the allocator\'s bookkeeping '
          '(2 x lead-lift days <= weekly top), not the model\'s truth.')
      ..writeln()
      ..writeln('## Median day by minutes x days x level (phase 1, week 1, all goals and tiers)')
      ..writeln()
      ..writeln('| minutes | days | level | exercises | sets | minutes with warm-up and cool-down |')
      ..writeln('|---|---|---|---|---|---|');
    final keys = _agg.cell.keys.toList()
      ..sort((a, b) {
        final x = a.split('|'), y = b.split('|');
        final c1 = int.parse(x[0]).compareTo(int.parse(y[0]));
        if (c1 != 0) return c1;
        final c2 = int.parse(x[1]).compareTo(int.parse(y[1]));
        if (c2 != 0) return c2;
        return _levels.indexOf(x[2]).compareTo(_levels.indexOf(y[2]));
      });
    for (final k in keys) {
      final rows = _agg.cell[k]!;
      final parts = k.split('|');
      b.writeln('| ${parts[0]} | ${parts[1]} | ${parts[2]} | '
          '${median([for (final r in rows) r[0]]).toStringAsFixed(1)} | '
          '${median([for (final r in rows) r[1]]).toStringAsFixed(1)} | '
          '${median([for (final r in rows) r[2]]).toStringAsFixed(1)} |');
    }
    b
      ..writeln('\n## Minutes unused per day (median, p10 not shown)\n')
      ..writeln('| minutes | median unused |')
      ..writeln('|---|---|');
    for (final m in _minutesGrid) {
      b.writeln('| $m | ${median(_agg.unused[m] ?? []).toStringAsFixed(1)} |');
    }
    b
      ..writeln('\n## Groups below their weekly floor, by label (count of group-runs)\n')
      ..writeln('| label | count |')
      ..writeln('|---|---|');
    final labels = _agg.belowFloor.keys.where((k) => !k.contains(':')).toList()..sort();
    for (final k in labels) {
      b.writeln('| $k | ${_agg.belowFloor[k]} |');
    }
    b
      ..writeln('\nBy group:\n')
      ..writeln('| group:label | count |')
      ..writeln('|---|---|');
    final byGroup = _agg.belowFloor.keys.where((k) => k.contains(':')).toList()..sort();
    for (final k in byGroup) {
      b.writeln('| $k | ${_agg.belowFloor[k]} |');
    }
    b
      ..writeln('\n## Time and lead lifts (counts are DAYS of weeks 1-4 of every run, not personas)\n')
      ..writeln('- Days longer than the user\'s own minutes, by any amount: ${_agg.daysOverMinutes} of '
          '${_agg.days}, worst ${_agg.worstOverMinutes.toStringAsFixed(2)} min over. '
          'The gate\'s limit is minutes + 2.')
      ..writeln('- Of those, median ${median(_agg.overs).toStringAsFixed(2)} min over, '
          '${_agg.overs.where((o) => o > 1).length} days over by more than 1 min, '
          '${_agg.overs.where((o) => o > 2).length} by more than 2 (the exempt forced lead lifts). '
          'The stored warm-up and cool-down items vary by day type while the model reserves '
          '`warmCoolMinutes`; this is that calibration residual (Ruling 3).')
      ..writeln('- `timeForcedFirst` (days the empty-day guard filled although the time was already '
          'spent: the lead lift, or the first exercise that had weekly room): ${_agg.timeForced}')
      ..writeln('- Days over minutes + 2 that the forced lead lift explains (the gate\'s one '
          'exemption): ${_agg.timeForcedOver.length}'
          '${_agg.timeForcedOver.isEmpty ? '' : ', worst ${_agg.timeForcedOver.reduce((a, b) => a > b ? a : b).toStringAsFixed(1)} min over the user\'s minutes, e.g. ${_agg.timeForcedOverWhere.first}'}.')
      ..writeln('- Lead lift not kept (the time left fitted a cheaper lift but not 2 sets of it): '
          '${_agg.leadAbsent} of ${_agg.leadDays} allocated days (every run, both variants).')
      ..writeln('- Display agreement: ${_agg.displayChecked} stored days priced by '
          '`SessionBudget.estimateDaySecondsFromPlanDay` equal the oracle to 1e-6 s.')
      ..writeln('\n## Focus Chest, intermediate, 90 min: week-1 Chest sets by split\n')
      ..writeln('| split | Chest sets |')
      ..writeln('|---|---|');
    _agg.focusWeekly.forEach((k, v) => b.writeln('| $k | ${v.join(', ')} |'));
    b
      ..writeln('\n## The founder case: intermediate, build_muscle, full_gym, 6 days, 90 minutes\n')
      ..writeln('### Focus none')
      ..writeln(_agg.founder['none'] ?? '(not run)')
      ..writeln('\n### Focus Chest')
      ..writeln(_agg.founder['Chest'] ?? '(not run)');
    // For scale: the same persona shape with the flag OFF (a fixed exercise count),
    // priced by the same oracle. Phase 1, week 1, build_muscle, full_gym.
    await HiveService.instance.configBox.put(_flag, false);
    b
      ..writeln('\n## For scale: the flag-OFF world (build_muscle, full_gym, phase 1, week 1)\n')
      ..writeln('Median day in minutes with warm-up and cool-down, priced by the same oracle. '
          'OFF ignores the user\'s minutes.\n')
      ..writeln('| days | beginner | intermediate | advanced |')
      ..writeln('|---|---|---|---|');
    for (final days in _dayCounts) {
      final cells = <String>[];
      for (final level in _levels) {
        final plan = gen(_P('build_muscle', 'full_gym', days, level, 1, 60));
        cells.add(median([for (final d in plan.weekPlans.first.workoutDays) daySeconds(d) / 60])
            .toStringAsFixed(1));
      }
      b.writeln('| $days | ${cells.join(' | ')} |');
    }
    await HiveService.instance.configBox.put(_flag, true);
    File('test/plan_generator/session_set_budget_report.md').writeAsStringSync(b.toString());
  });
}
