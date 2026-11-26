// OI-348-style batch `train-history-sheet-style` (plan docs/plans/train-past-week-in-place.md,
// D1): the Train day-object builder is extracted from `currentPlanProvider` into
// `workoutDayDataFromScheduleRow` so the PAST-week list builds its rows through the SAME code.
//
// GOLDEN values: the `_golden` list below was captured from the UNMODIFIED provider (before the
// extraction), then frozen. The extraction must keep every line. A shared function compared with
// itself would prove nothing, which is why the expectations are literals.
//
// Run: TZ=Asia/Kolkata flutter test test/contracts/workout_day_data_from_row_test.dart

@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';

import '../helpers/hive_test_setup.dart';

Directory? _dir;

/// One line per day: every field the builder fills, in a fixed order.
String describeDay(WorkoutDayData d) {
  String ex(ExerciseData e) =>
      '${e.name}|${e.sets}|${e.reps}|${e.rest}|${e.loggingType}|${e.category}|${e.detailText}';
  return [
    'n=${d.dayNumber}',
    'name=${d.name}',
    'sub=${d.subtitle}',
    'label=${d.dateLabel}',
    'date=${d.date == null ? null : d.date!.toIso8601String()}',
    'rest=${d.isRest}',
    'done=${d.isDone}',
    'ex=[${d.exercises.map(ex).join(';')}]',
    'warm=[${d.warmup.map(ex).join(';')}]',
    'cool=[${d.cooldown.map(ex).join(';')}]',
    'fin=[${d.finisher.map(ex).join(';')}]',
    'finSec=${d.finisherSeconds}',
    'budget=${d.budgetMinutes}',
    'mode=${d.weekMode}',
    'count=${d.exerciseCount}',
  ].join(' ');
}

/// A fixed Monday far enough back that every row is "past"; the builder never reads the clock.
const _start = '2026-11-02';

Future<void> _seed() async {
  final wb = HiveService.instance.workoutBox;
  await wb.clear();
  await HiveService.instance.userBox.put('plan_start_date', _start);
  await wb.put('current_plan', {'focus': 'Golden focus', 'name': 'Foundation'});
  Map<String, dynamic> row(
    int i, {
    required String type,
    required String status,
    String? name,
    String focus = 'Push',
    List<Map<String, dynamic>> exercises = const [],
    List<Map<String, dynamic>> warmup = const [],
    List<Map<String, dynamic>> cooldown = const [],
    List<Map<String, dynamic>>? finisher,
    Map<String, dynamic> extra = const {},
  }) {
    final day = DateTime.utc(2026, 11, 2 + i);
    final ds =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    return {
      'date': ds,
      'week': 1,
      'day_of_week': i,
      'type': type,
      'status': status,
      if (name != null) 'workout_name': name,
      'workout_focus': focus,
      'exercises': exercises,
      'warmup': warmup,
      'cooldown': cooldown,
      if (finisher != null) 'finisher': finisher,
      ...extra,
    };
  }

  final rows = <Map<String, dynamic>>[
    row(0,
        type: 'workout',
        status: 'planned',
        name: 'Push',
        exercises: [
          {'exercise_name': 'Bench Press', 'sets': 3, 'reps': '8', 'rest_seconds': 90},
          {'exercise_name': 'Overhead Press', 'sets': 3, 'reps': '10', 'rest_seconds': 60},
        ],
        warmup: [
          {'exercise_name': 'Arm Circles', 'sets': 1, 'reps': '10'},
        ],
        cooldown: [
          {'exercise_name': 'Chest Stretch', 'sets': 1, 'reps': '30s'},
        ],
        finisher: [
          {
            'exercise_name': 'Stationary Bike Sprints',
            'sets': 8,
            'reps': '30s fast / 30s slow',
            'rest_seconds': 0,
            'logging_type': 'timed',
          },
        ],
        extra: {'week_character': 'baseline'}),
    row(1,
        type: 'workout',
        status: 'completed',
        name: 'Pull',
        focus: 'Pull',
        exercises: [
          {'exercise_name': 'Pull Up', 'sets': 4, 'reps': '6', 'rest_seconds': 90},
        ],
        extra: {'completed_at': '2026-11-03T10:00:00.000', 'week_character': 'baseline'}),
    row(2, type: 'rest', status: 'rest', name: 'Rest Day', focus: ''),
    row(3,
        type: 'workout',
        status: 'planned',
        name: 'Legs',
        focus: 'Legs',
        exercises: [
          {'exercise_name': 'Back Squat', 'sets': 5, 'reps': '5', 'rest_seconds': 120},
        ],
        extra: {'is_hold': true, 'hold_ordinal': 1, 'week_character': 'peak'}),
    row(4, type: 'workout', status: 'planned', focus: 'Core'),
    row(5,
        type: 'logged',
        status: 'completed',
        name: 'Leftover Legs',
        focus: 'Legs',
        extra: {'completed_at': '2026-11-07T10:00:00.000'}),
    row(6, type: 'rest', status: 'rest', name: 'Rest Day', focus: ''),
  ];
  for (final r in rows) {
    await wb.put('schedule_${r['date']}', r);
  }
}

/// CAPTURED from the unmodified `currentPlanProvider` (see the header). Do not regenerate to make a
/// failure go away: a diff here is a behaviour change of the Train week list.
const List<String> _golden = <String>[
  'n=1 name=PUSH sub=Push · 2 exercises label=Mon, Nov 2 date=2026-11-02T00:00:00.000 rest=false done=false ex=[Bench Press|3|8|90s|weight_reps|null|null;Overhead Press|3|10|60s|weight_reps|null|null] warm=[Arm Circles|1|10|60s|weight_reps|null|null] cool=[Chest Stretch|1|30s|60s|weight_reps|null|null] fin=[Stationary Bike Sprints|8|30s fast / 30s slow|0s|timed|finisher|8 rounds · 30s fast / 30s slow] finSec=0 budget=17 mode=Baseline count=2',
  'n=2 name=PULL sub=Pull · 1 exercises label=Tue, Nov 3 date=2026-11-03T00:00:00.000 rest=false done=true ex=[Pull Up|4|6|90s|weight_reps|null|null] warm=[] cool=[] fin=[] finSec=0 budget=10 mode=Baseline count=1',
  'n=3 name=REST DAY sub=Recovery & mobility label=Wed, Nov 4 date=2026-11-04T00:00:00.000 rest=true done=false ex=[] warm=[] cool=[] fin=[] finSec=0 budget=null mode=null count=0',
  'n=4 name=LEGS sub=Legs · 1 exercises label=Thu, Nov 5 date=2026-11-05T00:00:00.000 rest=false done=false ex=[Back Squat|5|5|120s|weight_reps|null|null] warm=[] cool=[] fin=[] finSec=0 budget=15 mode=Peak count=1',
  'n=5 name=REST DAY sub=Core · 0 exercises label=Fri, Nov 6 date=2026-11-06T00:00:00.000 rest=false done=false ex=[] warm=[] cool=[] fin=[] finSec=0 budget=null mode=null count=0',
  'n=6 name=LEFTOVER LEGS sub=Recovery & mobility label=Sat, Nov 7 date=2026-11-07T00:00:00.000 rest=true done=true ex=[] warm=[] cool=[] fin=[] finSec=0 budget=null mode=null count=0',
  'n=7 name=REST DAY sub=Recovery & mobility label=Sun, Nov 8 date=2026-11-08T00:00:00.000 rest=true done=false ex=[] warm=[] cool=[] fin=[] finSec=0 budget=null mode=null count=0',
];

void main() {
  tearDownAll(() async {
    if (_dir != null) await tearDownHiveForTests(_dir!);
  });

  Future<List<WorkoutDayData>> currentWeek1(WidgetTester tester) async {
    _dir ??= await tester.runAsync(setUpHiveForTests);
    await tester.runAsync(_seed);
    final c = ProviderContainer(overrides: [
      authUserIdTokenProvider.overrideWithValue('u'),
    ]);
    addTearDown(c.dispose);
    return c.read(currentPlanProvider).getWeek(1);
  }

  testWidgets('GOLDEN: the current-phase week-1 day objects', (tester) async {
    final days = await currentWeek1(tester);
    final got = days.map(describeDay).toList();
    expect(got, _golden);
  });
}
