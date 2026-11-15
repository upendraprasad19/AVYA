// Unit 2D (OI-453, plan docs/plans/2026-11-15-generator-step2d-repeat-minutes.md §3): the whole-engine gate for a
// repeat phase at more minutes. Phase 1 is generated at m1; its weeks 1-2 become schedule rows; the real
// `WorkoutScheduleReadService.repeatPinsFrom` turns them into pins (so a repeat production sends FRESH, e.g. a
// build_muscle 3-5-day plan crossing 60 minutes, is counted as fresh and never measured); the phase-2 repeat is then
// generated at m2 with the flag off and on.
//
// Asserted per measured persona: every row of the flag-off repeat is in the flag-on repeat on the same day of every
// week with the same sets and reps (the pins and their week-1 / week-2 sets survive); every extra row is a library
// isolation, appears once in its day, and the same extras sit in weeks 1 and 3 (variant A) and in weeks 2 and 4
// (variant B); no week-1 day holds more than the level's exercise count; a day's main-work seconds with the extras stay
// within the plain day budget (the session minus warm-up and cool-down) whenever the flag-off day was within it.

import 'package:icanbefitter/core/constants/fitness_goals.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_generator.dart';

import 'injury_floor_sweep_lib.dart';

const kRepeatMinutePairs = [(30, 45), (30, 60), (45, 60), (60, 90)];
const kRepeatDays = [3, 4, 5, 6];

/// Per (pair, tier): personas, fresh (no pins), measured, gained (any extra row), extra rows and extra sets (week 1 +
/// week 2), extra seconds (week 1, whole seconds).
class RepeatMinutesTally {
  int personas = 0, fresh = 0, measured = 0, gained = 0, rows = 0, sets = 0, seconds = 0;
  final failures = <String>[];
  (int, int, int, int, int, int, int) get tuple => (personas, fresh, measured, gained, rows, sets, seconds);
}

List<Map<String, dynamic>> _rowsOf(WeekPlan w) => [
      for (var i = 0; i < w.workoutDays.length; i++)
        {
          'type': 'workout',
          'workout_day_index': i,
          'workout_name': w.workoutDays[i].name,
          'exercises': [
            for (final e in w.workoutDays[i].exercises) {'exercise_name': e.exerciseName},
          ],
        },
    ];

String _k(PlannedExercise e) => '${e.exerciseName}|${e.sets}|${e.reps}';

double _mainSeconds(WorkoutDay d) => SessionBudget.estimateDaySecondsFromPlanDay({
      'exercises': [
        for (final e in d.exercises)
          {
            'exercise_name': e.exerciseName,
            'exercise_type': e.exerciseType,
            'rep_range': e.repRange,
            'logging_type': e.loggingType,
            'sets': e.sets,
            'reps': e.reps,
            'rest_seconds': e.restSeconds,
          },
      ],
    }, const {}, rowsByName: const {});

RepeatMinutesTally runRepeatMinutes(SweepHarness h, (int, int) pair, String tier) {
  final (m1, m2) = pair;
  final t = RepeatMinutesTally();
  for (final goal in kSweepGoals) {
    for (final level in kSweepLevels) {
      for (final days in kRepeatDays) {
        t.personas++;
        final label = '$goal|$level|$days|$tier|$m1->$m2';
        final p1 = h.gen(tier: tier, goal: goal, level: level, days: days, phase: 1, injuries: const [], minutes: m1);
        final planGoal = FitnessGoals.of(goal).planGoal;
        final exp2 = PlanGenerator.effectiveLevel(level, 2);
        final pins = WorkoutScheduleReadService.repeatPinsFrom(
          stored: {
            'plan_goal': planGoal,
            'equipment': tier,
            'days_per_week': days,
            'effective_exp': PlanGenerator.effectiveLevel(level, 1),
            'session_minutes': m1,
          },
          week1: _rowsOf(p1.weekPlans[0]),
          week2: _rowsOf(p1.weekPlans[1]),
          currentPlanGoal: planGoal,
          equipment: tier,
          daysPerWeek: days,
          newPhaseEffectiveExp: exp2,
          foreignDayNames: WorkoutScheduleReadService.foreignDayNamesFor(
              planGoal: planGoal, daysPerWeek: days, effectiveExp: exp2, minutes: m2),
        );
        if (pins == null) {
          t.fresh++;
          continue;
        }
        t.measured++;
        Phase gen(bool rose) => h.gen(
            tier: tier,
            goal: goal,
            level: level,
            days: days,
            phase: 2,
            injuries: const [],
            minutes: m2,
            pins: pins,
            repeatMinutesRose: rose);
        final off = gen(false);
        final on = gen(true);
        final levelMax = SessionBudget.countMax(exp2) < SessionBudget.hardMax
            ? SessionBudget.countMax(exp2)
            : SessionBudget.hardMax;
        final budget = (m2 - SessionBudget.warmCoolMinutes(m2)) * 60.0;
        var any = false;
        final extrasByWeek = <int, List<List<String>>>{};
        for (var w = 0; w < off.weekPlans.length; w++) {
          final dOff = off.weekPlans[w].workoutDays;
          final dOn = on.weekPlans[w].workoutDays;
          if (dOff.length != dOn.length) {
            t.failures.add('$label w$w: day count ${dOff.length} vs ${dOn.length}');
            continue;
          }
          extrasByWeek[w] = [];
          for (var d = 0; d < dOff.length; d++) {
            final offKeys = [for (final e in dOff[d].exercises) _k(e)];
            final onKeys = [for (final e in dOn[d].exercises) _k(e)];
            final rest = [...onKeys];
            for (final k in offKeys) {
              if (!rest.remove(k)) t.failures.add('$label w$w d$d: lost or changed $k');
            }
            final names = [for (final e in dOn[d].exercises) e.exerciseName.toLowerCase()];
            if (names.toSet().length != names.length) t.failures.add('$label w$w d$d: duplicate $names');
            final extras = [
              for (final e in dOn[d].exercises)
                if (rest.contains(_k(e))) e,
            ];
            extrasByWeek[w]!.add([for (final e in extras) e.exerciseName]..sort());
            for (final e in extras) {
              if (e.exerciseType != 'isolation' || e.customOrigin != null) {
                t.failures.add('$label w$w d$d: extra ${e.exerciseName} is not a library isolation');
              }
            }
            if (extras.isEmpty) continue;
            any = true;
            if (w <= 1) {
              t.rows += extras.length;
              for (final e in extras) {
                t.sets += e.sets;
              }
            }
            if (w == 0) {
              if (dOn[d].exercises.length > levelMax) {
                t.failures.add('$label d$d: ${dOn[d].exercises.length} rows > $levelMax');
              }
              final sOff = _mainSeconds(dOff[d]);
              final sOn = _mainSeconds(dOn[d]);
              t.seconds += (sOn - sOff).round();
              if (sOff <= budget + 1e-6 && sOn > budget + 1e-6) {
                t.failures.add('$label d$d: ${sOn.round()} s > plain budget ${budget.round()} s');
              }
            }
          }
        }
        if (extrasByWeek.length == 4) {
          if ('${extrasByWeek[0]}' != '${extrasByWeek[2]}') {
            t.failures.add('$label: week 1 extras ${extrasByWeek[0]} != week 3 ${extrasByWeek[2]}');
          }
          if ('${extrasByWeek[1]}' != '${extrasByWeek[3]}') {
            t.failures.add('$label: week 2 extras ${extrasByWeek[1]} != week 4 ${extrasByWeek[3]}');
          }
        }
        if (any) t.gained++;
      }
    }
  }
  return t;
}
