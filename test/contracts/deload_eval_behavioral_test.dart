// ⑥ 7-B-2 (W2.4): triggered-deload EVAL + un-deload — production behavioral
// test (platform behavioral_test_path, §4.4 rule 21). Drives the REAL
// `DeloadEvaluator.maybeEvaluate()` against seeded Hive state — schedule rows,
// the `current_plan` blob, `exlog_*` history, and `readiness_*` check-ins — and
// asserts the SAFE-polarity contract:
//
//   shouldLift = notBackstop && notDeloadPhase && readinessGood && e1rmNoFatigue
//
// Every clause requires POSITIVE evidence; any false/unknown/missing → KEEP the
// deload. Proves: (1) flag-OFF (either flag) → byte-identical no-op; (2) all
// clauses true → LIFT (rows + blob → working, sets←working_sets, char 'working');
// (3) each polarity KEEP (empty/sparse readiness, zero-compound, declining e1RM
// via the MAX-Epley pin, unseeded backstop, intended deload phase); (4) the
// restore-race (no signals) keeps AND does NOT lock the flag; (5) idempotency +
// marker seeding on a firm keep; (6) the today-or-future + status/swap row gates.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/deload_evaluator.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;
  late String compoundName;

  // Fixed "today" — first day of week 4 of a phase that started 21 days earlier.
  final fixedToday = DateTime(2026, 6, 1, 12);
  final planStart = DateTime(2026, 6, 1).subtract(const Duration(days: 21));

  String dk(DateTime d) => istDateStr(d);

  late final Box wb; // workoutBox — assigned in setUpAll after opening.
  late final Box hb; // healthBox
  late final Box cb; // configBox

  Map<String, dynamic> stashedEx({
    int sets = 2,
    String reps = '8',
    int? workingSets = 4,
    String workingReps = '10',
    String name = 'Barbell Bench Press',
  }) =>
      {
        'exercise_id': 'e1',
        'exercise_name': name,
        'logging_type': 'weight_reps',
        'sets': sets,
        'reps': reps,
        'rest_seconds': 90,
        'weight_cue': 'Light week — same weight, fewer sets.',
        'intensity_profile': 'hypertrophy',
        'variant': 'A',
        if (workingSets != null) 'working_sets': workingSets,
        if (workingSets != null) 'working_reps': workingReps,
      };

  Map<String, dynamic> workoutRow(DateTime date, int phase, int dow,
          {String status = 'planned',
          bool isSwapped = false,
          String? shortenedVia,
          List<Map<String, dynamic>>? exercises}) =>
      {
        'date': dk(date),
        'phase': phase,
        'week': 4,
        'day_of_week': dow,
        'type': 'workout',
        'workout_day_index': dow,
        'workout_name': 'Push',
        'workout_focus': 'Chest',
        'exercises': exercises ?? [stashedEx()],
        'week_character': 'deload',
        'status': status,
        'completed_at': null,
        'is_swapped': isSwapped,
        'shortened_via': ?shortenedVia,
        'original_date': null,
      };

  // Seed a week-4 deload plan: schedule rows (workout on days 0 & 2, rest else)
  // + the current_plan blob. `phase` stamps every row + the blob.
  Future<void> seedWk4({required int phase}) async {
    await cb.put('plan_start_date', planStart.toIso8601String());
    await cb.put('plan_end_date',
        planStart.add(const Duration(days: 27)).toIso8601String());
    final wk4Start = planStart.add(const Duration(days: 21));
    for (int i = 0; i < 7; i++) {
      final date = wk4Start.add(Duration(days: i));
      final isWorkout = i == 0 || i == 2;
      final row = isWorkout
          ? workoutRow(date, phase, i)
          : {
              'date': dk(date),
              'phase': phase,
              'week': 4,
              'day_of_week': i,
              'type': 'rest',
              'workout_name': 'Rest Day',
              'workout_focus': 'Recovery',
              'exercises': <Map<String, dynamic>>[],
              'week_character': 'deload',
              'status': 'rest',
              'completed_at': null,
              'is_swapped': false,
              'original_date': null,
            };
      await wb.put('schedule_${dk(date)}', row);
    }
    await wb.put('current_plan', {
      'phase': phase,
      'name': 'Foundation',
      'focus': '',
      'weeks': '1-4',
      'daily_calories': 2000,
      'protein_grams': 150,
      'workouts': <Map<String, dynamic>>[],
      'week_plans': [
        {
          'week_number': 1,
          'week_in_phase': 1,
          'overload_notes': '',
          'week_character': 'baseline',
          'workout_days': <Map<String, dynamic>>[],
        },
        {
          'week_number': 2,
          'week_in_phase': 2,
          'overload_notes': '',
          'week_character': 'overreach',
          'workout_days': <Map<String, dynamic>>[],
        },
        {
          'week_number': 3,
          'week_in_phase': 3,
          'overload_notes': '',
          'week_character': 'peak',
          'workout_days': <Map<String, dynamic>>[],
        },
        {
          'week_number': 4,
          'week_in_phase': 4,
          'overload_notes': 'Strategic recovery',
          'week_character': 'deload',
          'workout_days': [
            {
              'day_number': 1,
              'name': 'Push',
              'focus': '',
              'exercises': [stashedEx()],
            },
          ],
        },
      ],
    });
  }

  // ≥3 green check-ins in the trailing window → readinessGood TRUE.
  Future<void> seedGoodReadiness({int n = 4}) async {
    for (int i = 1; i <= n; i++) {
      final d = fixedToday.subtract(Duration(days: i));
      await hb.put('readiness_${dk(d)}',
          {'date': dk(d), 'sleep': 0, 'soreness': 0, 'energy': 0, 'level': 'green'});
    }
  }

  // A compound with 2 dated sessions, latest e1RM >= prior → e1rmNoFatigue TRUE.
  Future<void> seedNonDecliningCompound() async {
    final d1 = fixedToday.subtract(const Duration(days: 6));
    final d2 = fixedToday.subtract(const Duration(days: 2));
    await wb.put('exlog_${dk(d1)}_c', {
      'exercise_name': compoundName,
      'date': dk(d1),
      'logging_type': 'weight_reps',
      'sets': [
        {'weight_kg': 90, 'reps_completed': 5}
      ],
      'weight_kg': 90,
      'reps_completed': 5,
    });
    await wb.put('exlog_${dk(d2)}_c', {
      'exercise_name': compoundName,
      'date': dk(d2),
      'logging_type': 'weight_reps',
      'sets': [
        {'weight_kg': 95, 'reps_completed': 5}
      ],
      'weight_kg': 95,
      'reps_completed': 5,
    });
  }

  Future<void> enableFlags({bool deload = true, bool readiness = true}) async {
    if (deload) await cb.put('enable_triggered_deload', true);
    if (readiness) await cb.put('enable_readiness', true);
  }

  // Read the first wk4 workout row back (day 0 = today).
  Map? liftedWorkoutRow() {
    final wk4Start = planStart.add(const Duration(days: 21));
    return wb.get('schedule_${dk(wk4Start)}') as Map?;
  }

  Map deloadBlobWeek() {
    final plan = wb.get('current_plan') as Map;
    return (plan['week_plans'] as List)[3] as Map;
  }

  // First-exercise field of a row/day (typed casts avoid avoid_dynamic_calls).
  Object? ex0(Map row, String field) =>
      ((row['exercises'] as List)[0] as Map)[field];

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('deload_eval');
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
    final rows = jsonDecode(
      File('assets/data/exercise_library.json').readAsStringSync(),
    ) as List;
    for (final r in rows.whereType<Map>()) {
      final id = (r['id'] ?? r['name']).toString();
      await exBox.put(id, Map<String, dynamic>.from(r));
    }
    // Discover a real compound exercise name (exact `exercise_type == 'compound'`).
    compoundName = '';
    for (final v in exBox.values) {
      if (v is! Map) continue;
      final t = v['exercise_type'];
      final isC = t is List
          ? t.any((e) => e.toString().toLowerCase() == 'compound')
          : (t as String?)?.toLowerCase() == 'compound';
      if (isC) {
        compoundName = (v['name'] as String?) ?? '';
        if (compoundName.isNotEmpty) break;
      }
    }
    expect(compoundName, isNotEmpty,
        reason: 'library must contain ≥1 compound for the e1RM scan test');
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
    // Resolve the guarded per-user boxes (workoutBox_<hash> / healthBox_<hash>)
    // + the shared configBox — the same references the eval reads/writes.
    wb = HiveService.instance.workoutBox;
    hb = HiveService.instance.healthBox;
    cb = HiveService.instance.configBox;
    setTestClockTo(fixedToday);
  });

  tearDownAll(() async {
    resetTestClock();
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await wb.clear();
    await hb.clear();
    await cb.clear();
  });

  group('flag-off → byte-identical no-op', () {
    test('triggered_deload OFF → wk4 stays deload', () async {
      await seedWk4(phase: 2);
      await wb.put('last_actual_deload_phase', 1);
      await seedGoodReadiness();
      await seedNonDecliningCompound();
      await enableFlags(deload: false, readiness: true);

      await DeloadEvaluator.instance.maybeEvaluate();

      expect(liftedWorkoutRow()!['week_character'], 'deload');
      expect(ex0(liftedWorkoutRow()!, 'sets'), 2);
      expect(deloadBlobWeek()['week_character'], 'deload');
    });

    test('readiness OFF → wk4 stays deload', () async {
      await seedWk4(phase: 2);
      await wb.put('last_actual_deload_phase', 1);
      await seedGoodReadiness();
      await seedNonDecliningCompound();
      await enableFlags(deload: true, readiness: false);

      await DeloadEvaluator.instance.maybeEvaluate();

      expect(liftedWorkoutRow()!['week_character'], 'deload');
      expect(ex0(liftedWorkoutRow()!, 'sets'), 2);
    });
  });

  group('all clauses positive → LIFT', () {
    test('phase 2, recent marker, good readiness, non-declining compound', () async {
      await seedWk4(phase: 2);
      await wb.put('last_actual_deload_phase', 1); // notBackstop TRUE
      await seedGoodReadiness();
      await seedNonDecliningCompound();
      await enableFlags();

      await DeloadEvaluator.instance.maybeEvaluate();

      final row = liftedWorkoutRow()!;
      expect(row['week_character'], 'working');
      expect(ex0(row, 'sets'), 4); // working_sets
      expect(ex0(row, 'reps'), '10'); // working_reps
      expect(ex0(row, 'weight_cue'),
          'Working week — full sets and reps');
      // blob dual-write
      final blobWeek = deloadBlobWeek();
      expect(blobWeek['week_character'], 'working');
      final blobDay = (blobWeek['workout_days'] as List)[0] as Map;
      expect(ex0(blobDay, 'sets'), 4);
      // lifted → NO deload taken → marker unchanged (still 1); flag set.
      expect(wb.get('last_actual_deload_phase'), 1);
      expect(wb.get('deload_evaluated_for_phase_2'), true);
    });
  });

  group('polarity KEEPs (any clause false → keep the deload)', () {
    test('empty readiness → keep', () async {
      await seedWk4(phase: 2);
      await wb.put('last_actual_deload_phase', 1);
      await seedNonDecliningCompound();
      // no readiness at all
      await enableFlags();
      await DeloadEvaluator.instance.maybeEvaluate();
      expect(liftedWorkoutRow()!['week_character'], 'deload');
    });

    test('sparse readiness (< 3 entries) → keep', () async {
      await seedWk4(phase: 2);
      await wb.put('last_actual_deload_phase', 1);
      await seedGoodReadiness(n: 2); // only 2 → insufficient
      await seedNonDecliningCompound();
      await enableFlags();
      await DeloadEvaluator.instance.maybeEvaluate();
      expect(liftedWorkoutRow()!['week_character'], 'deload');
    });

    test('zero compounds logged → keep', () async {
      await seedWk4(phase: 2);
      await wb.put('last_actual_deload_phase', 1);
      await seedGoodReadiness();
      // no exlog at all
      await enableFlags();
      await DeloadEvaluator.instance.maybeEvaluate();
      expect(liftedWorkoutRow()!['week_character'], 'deload');
    });

    test('declining e1RM (max-Epley pin: high-rep set out-e1RMs heaviest) → keep',
        () async {
      await seedWk4(phase: 2);
      await wb.put('last_actual_deload_phase', 1);
      await seedGoodReadiness();
      // PRIOR session: heaviest-weight set 100×3 (e1RM 110) BUT a high-rep set
      // 80×12 (e1RM 112) is the real max. LATEST: 101×3 (e1RM 111.1). By
      // heaviest-by-WEIGHT: prior 110 < latest 111.1 → "no decline" (WRONG). By
      // MAX-Epley: prior 112 > latest 111.1 → DECLINE → keep (correct).
      final dPrior = fixedToday.subtract(const Duration(days: 6));
      final dLatest = fixedToday.subtract(const Duration(days: 2));
      await wb.put('exlog_${dk(dPrior)}_c', {
        'exercise_name': compoundName,
        'date': dk(dPrior),
        'logging_type': 'weight_reps',
        'sets': [
          {'weight_kg': 100, 'reps_completed': 3},
          {'weight_kg': 80, 'reps_completed': 12},
        ],
      });
      await wb.put('exlog_${dk(dLatest)}_c', {
        'exercise_name': compoundName,
        'date': dk(dLatest),
        'logging_type': 'weight_reps',
        'sets': [
          {'weight_kg': 101, 'reps_completed': 3},
        ],
      });
      await enableFlags();
      await DeloadEvaluator.instance.maybeEvaluate();
      expect(liftedWorkoutRow()!['week_character'], 'deload',
          reason: 'max-Epley must detect the high-rep-set decline');
    });

    test('unseeded backstop (no marker) → keep', () async {
      await seedWk4(phase: 2);
      // NO last_actual_deload_phase marker
      await seedGoodReadiness();
      await seedNonDecliningCompound();
      await enableFlags();
      await DeloadEvaluator.instance.maybeEvaluate();
      expect(liftedWorkoutRow()!['week_character'], 'deload');
      // firm keep (backstop forced) → marker seeded to the current phase + flag.
      expect(wb.get('last_actual_deload_phase'), 2);
      expect(wb.get('deload_evaluated_for_phase_2'), true);
    });

    test('intended deload phase (phase 4) → keep even with all signals good',
        () async {
      await seedWk4(phase: 4);
      await wb.put('last_actual_deload_phase', 3); // notBackstop would be TRUE
      await seedGoodReadiness();
      await seedNonDecliningCompound();
      await enableFlags();
      await DeloadEvaluator.instance.maybeEvaluate();
      expect(liftedWorkoutRow()!['week_character'], 'deload');
    });

    test('COACH-2: any coach-regen wk4 row (generated_via) → whole eval skipped',
        () async {
      await seedWk4(phase: 2);
      await wb.put('last_actual_deload_phase', 1);
      await seedGoodReadiness();
      await seedNonDecliningCompound();
      // Stamp the day-0 row as coach-generated — guard 5 must skip the WHOLE
      // eval (coach weeks have their own numbering + never-persisted base).
      final wk4Start = planStart.add(const Duration(days: 21));
      await wb.put('schedule_${dk(wk4Start)}', {
        ...workoutRow(wk4Start, 2, 0),
        'generated_via': 'ai_coach_regenerate',
      });
      await enableFlags();

      await DeloadEvaluator.instance.maybeEvaluate();

      // Even the non-coach day-2 row stays deload (whole eval skipped).
      expect(liftedWorkoutRow()!['week_character'], 'deload');
      final day2 = wb.get('schedule_${dk(wk4Start.add(const Duration(days: 2)))}')
          as Map;
      expect(day2['week_character'], 'deload');
    });

    test('stale e1RM only (> 35d old) → not current evidence → keep', () async {
      await seedWk4(phase: 2);
      await wb.put('last_actual_deload_phase', 1);
      await seedGoodReadiness();
      // 2 compound sessions, BOTH older than the 35-day recency bound → excluded
      // → hasCompoundEvidence false → e1rmNoFatigue false → keep.
      final d1 = fixedToday.subtract(const Duration(days: 45));
      final d2 = fixedToday.subtract(const Duration(days: 40));
      await wb.put('exlog_${dk(d1)}_c', {
        'exercise_name': compoundName,
        'date': dk(d1),
        'logging_type': 'weight_reps',
        'sets': [
          {'weight_kg': 90, 'reps_completed': 5}
        ],
      });
      await wb.put('exlog_${dk(d2)}_c', {
        'exercise_name': compoundName,
        'date': dk(d2),
        'logging_type': 'weight_reps',
        'sets': [
          {'weight_kg': 95, 'reps_completed': 5}
        ],
      });
      await enableFlags();

      await DeloadEvaluator.instance.maybeEvaluate();
      expect(liftedWorkoutRow()!['week_character'], 'deload');
    });
  });

  group('idempotency + restore-race', () {
    test('firm keep sets flag; second call is a no-op', () async {
      await seedWk4(phase: 2);
      await seedGoodReadiness(); // present → firm keep on the backstop
      await seedNonDecliningCompound();
      await enableFlags();

      await DeloadEvaluator.instance.maybeEvaluate();
      expect(wb.get('deload_evaluated_for_phase_2'), true);

      // Flip readiness/marker so a re-eval WOULD lift — but the flag blocks it.
      await wb.put('last_actual_deload_phase', 1);
      await DeloadEvaluator.instance.maybeEvaluate();
      expect(liftedWorkoutRow()!['week_character'], 'deload');
    });

    test('restore race (no readiness AND no compound) → keep AND flag NOT set',
        () async {
      await seedWk4(phase: 2);
      await wb.put('last_actual_deload_phase', 1); // backstop permits
      // NO readiness, NO exlog → pure insufficient-data keep.
      await enableFlags();

      await DeloadEvaluator.instance.maybeEvaluate();
      expect(liftedWorkoutRow()!['week_character'], 'deload');
      // NOT locked → re-evaluable once restore lands.
      expect(wb.get('deload_evaluated_for_phase_2'), isNull);
      expect(wb.get('last_actual_deload_phase'), 1); // marker NOT bumped
    });
  });

  group('row gates', () {
    test('a completed wk4 row is NOT rewritten on a lift', () async {
      await seedWk4(phase: 2);
      await wb.put('last_actual_deload_phase', 1);
      await seedGoodReadiness();
      await seedNonDecliningCompound();
      // Mark the day-0 workout row completed.
      final wk4Start = planStart.add(const Duration(days: 21));
      final r = Map<String, dynamic>.from(
          wb.get('schedule_${dk(wk4Start)}') as Map);
      r['status'] = 'completed';
      await wb.put('schedule_${dk(wk4Start)}', r);
      await enableFlags();

      await DeloadEvaluator.instance.maybeEvaluate();

      // day 0 completed → untouched; day 2 (planned, future) → lifted.
      expect(ex0(liftedWorkoutRow()!, 'sets'), 2);
      expect(liftedWorkoutRow()!['week_character'], 'deload');
      final day2 = wb.get('schedule_${dk(wk4Start.add(const Duration(days: 2)))}')
          as Map;
      expect(ex0(day2, 'sets'), 4);
      expect(day2['week_character'], 'working');
    });

    test('is_swapped + shortened rows are NOT rewritten', () async {
      await seedWk4(phase: 2);
      await wb.put('last_actual_deload_phase', 1);
      await seedGoodReadiness();
      await seedNonDecliningCompound();
      final wk4Start = planStart.add(const Duration(days: 21));
      // day 0 → is_swapped; day 2 → shortened.
      await wb.put('schedule_${dk(wk4Start)}',
          workoutRow(wk4Start, 2, 0, isSwapped: true));
      await wb.put('schedule_${dk(wk4Start.add(const Duration(days: 2)))}',
          workoutRow(wk4Start.add(const Duration(days: 2)), 2, 2,
              shortenedVia: 'ai_coach'));
      await enableFlags();

      await DeloadEvaluator.instance.maybeEvaluate();

      expect(ex0(liftedWorkoutRow()!, 'sets'), 2);
      final day2 = wb.get('schedule_${dk(wk4Start.add(const Duration(days: 2)))}')
          as Map;
      expect(ex0(day2, 'sets'), 2);
    });

    test('per-exercise: a swapped-in exercise (no stash) is left untouched',
        () async {
      await seedWk4(phase: 2);
      await wb.put('last_actual_deload_phase', 1);
      await seedGoodReadiness();
      await seedNonDecliningCompound();
      // day-0 row: exercise[0] carries the stash; exercise[1] is an exercise-
      // level swap-in with NO working_sets (is_swapped is DAY-level, so this row
      // stays 'planned' + eligible — the per-exercise guard must protect ex[1]).
      final wk4Start = planStart.add(const Duration(days: 21));
      await wb.put('schedule_${dk(wk4Start)}', {
        ...workoutRow(wk4Start, 2, 0),
        'exercises': [
          stashedEx(),
          stashedEx(workingSets: null, name: 'Swapped In', sets: 3, reps: '12'),
        ],
      });
      await enableFlags();

      await DeloadEvaluator.instance.maybeEvaluate();

      final exs = liftedWorkoutRow()!['exercises'] as List;
      expect((exs[0] as Map)['sets'], 4); // stashed → lifted
      expect((exs[1] as Map)['sets'], 3); // no stash → untouched
      expect((exs[1] as Map)['reps'], '12');
      expect(liftedWorkoutRow()!['week_character'], 'working');
    });
  });
}
