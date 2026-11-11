// Generator step 1A, Task 1: the audit's verdict rules on fixtures. Parity with
// the session script it replaces was measured on both 2,304-plan dumps
// (2026-11-08): 0 verdict and 0 issue differences, and the section 1 numbers
// 1,466 / 58, 1,700 / 1,505, 36 of 56 / 56 of 56, 84 / 309, 4 / 310 (445 days),
// 0 / 1,273 (573 leads).
library;

import 'package:flutter_test/flutter_test.dart';

import 'plan_audit_lib.dart';

Map<String, dynamic> _ex(String name,
        {List<String> pattern = const ['knee_dominant'],
        List<String> needed = const ['bodyweight'],
        List<String> type = const ['compound'],
        List<String> muscles = const ['Quads'],
        String difficulty = 'intermediate',
        bool jump = false}) =>
    {
      'name': name,
      'movement_pattern': pattern,
      'equipment_needed': needed,
      'exercise_type': type,
      'primary_muscles': muscles,
      'suitable_for': ['Beginner', 'Intermediate', 'Advanced'],
      'difficulty_level': difficulty,
      'high_impact': jump,
      'is_active': true,
    };

final _lib = {
  for (final r in [
    _ex('Goblet Squat', needed: ['dumbbells']),
    _ex('Bodyweight Squat'),
    _ex('Jump Squat', jump: true),
    _ex('Self-Resisted Curl',
        pattern: ['elbow_flexion'], type: ['isolation'], muscles: ['Biceps']),
    _ex('Dumbbell Curl',
        pattern: ['elbow_flexion'], needed: ['dumbbells'], type: ['isolation'],
        muscles: ['Biceps']),
    _ex('Pike Push Up', pattern: ['vertical_push'], muscles: ['Front Deltoid']),
    _ex('Skater Squat', type: ['calisthenics']),
    _ex('Barbell Overhead Press',
        pattern: ['vertical_push'], needed: ['barbell'], muscles: ['Front Deltoid']),
    _ex('Lateral Raise',
        pattern: ['shoulder_isolation'], needed: ['dumbbells'], type: ['isolation'],
        muscles: ['Side Deltoid']),
  ])
    r['name'] as String: r
};

const _full = {
  'Chest': 12, 'Back': 12, 'Shoulders': 12, 'Quads': 12, 'Hamstrings': 12, 'Glutes': 12,
};

Map<String, dynamic> _plan(
  List<List<List<Object>>> week1Days, {
  String key = 'build_muscle|4|intermediate|home_dumbbells|60|1',
  String el = 'intermediate',
  Map<String, int> vol = _full,
  List<String> dayNames = const [],
  int? minutes,
  int deloadSets = 1,
}) {
  Map<String, dynamic> week(List<List<List<Object>>> ds, Map<String, int> v) => {
        'd': [
          for (var i = 0; i < ds.length; i++)
            {
              'n': i < dayNames.length ? dayNames[i] : 'Day ${i + 1}',
              'x': ds[i],
              'min': minutes,
            }
        ],
        'v': v,
      };
  return {
    'k': key,
    'el': el,
    'b': [10, 20],
    'w': [
      week(week1Days, vol),
      week(week1Days, vol),
      week(week1Days, vol),
      week([
        [
          ['Goblet Squat', deloadSets]
        ]
      ], vol),
    ],
  };
}

void main() {
  final auditor = PlanAuditor(_lib);
  List<String> codes(PlanAuditResult r) => [for (final i in r.issues) i.code];

  test('a clean plan is suitable', () {
    final r = auditor.audit(_plan([
      [['Goblet Squat', 3], ['Dumbbell Curl', 3]],
    ]));
    expect(r.issues, isEmpty);
    expect(r.verdict, 'suitable');
  });

  test('improvised: a household substitute when a loaded row fits (major); '
      'not flagged for a bodyweight user', () {
    final r = auditor.audit(_plan([
      [['Goblet Squat', 3], ['Self-Resisted Curl', 3]],
    ]));
    expect(codes(r), contains('improvised'));
    expect(r.verdict, 'not_suitable');
    final bw = auditor.audit(_plan([
      [['Goblet Squat', 3], ['Self-Resisted Curl', 3]],
    ], key: 'build_muscle|4|intermediate|bodyweight|60|1'));
    expect(codes(bw), isNot(contains('improvised')));
  });

  test('unloaded: an unloaded squat beside a loaded alternative (moderate)', () {
    final r = auditor.audit(_plan([
      [['Bodyweight Squat', 3], ['Dumbbell Curl', 3]],
    ]));
    expect(codes(r), ['unloaded']);
    expect(r.verdict, 'needs_work');
  });

  test('zero_muscle in weeks 1-3 only; week 4 is the deload', () {
    final r = auditor.audit(_plan([
      [['Goblet Squat', 3]],
    ], vol: {..._full, 'Hamstrings': 0}));
    expect(r.issues.where((i) => i.code == 'zero_muscle'), hasLength(3));
  });

  // Unit 1B-F (OI-485 (3)): iso_first reads the BUILT type, x[7], when the dump carries it. Both directions: a row the
  // library calls `calisthenics` built as `compound` is a compound opener (the 12 strength Squat Days that opened
  // with E143 Skater Squat), and a library compound built as `isolation` is not.
  List<Object> built(String name, int sets, String type) => [name, sets, '10', 60, 0, 0, <String>[], type];
  test('iso_first: a library non-compound built as compound is a compound opener', () {
    final r = auditor.audit(_plan([
      [built('Skater Squat', 3, 'compound'), built('Goblet Squat', 3, 'compound')],
    ]));
    expect(r.isoFirstDays, 0);
    final lib = auditor.audit(_plan([
      [['Skater Squat', 3], ['Goblet Squat', 3]],
    ]));
    expect(lib.isoFirstDays, 1, reason: 'non-vacuity: without x[7] the library type flags the day');
  });
  test('iso_first: a library compound built as isolation opens the day as an isolation', () {
    final r = auditor.audit(_plan([
      [built('Goblet Squat', 3, 'isolation'), built('Bodyweight Squat', 3, 'compound')],
    ]));
    expect(r.isoFirstDays, 1);
  });
  test('iso_first: only a built `compound` counts as compound (a third type, e.g. calisthenics, does not)', () {
    final r = auditor.audit(_plan([
      [built('Goblet Squat', 3, 'calisthenics'), built('Bodyweight Squat', 3, 'compound')],
    ]));
    expect(r.isoFirstDays, 1);
  });

  test('iso_first and lead_starved count on week 1', () {
    final r = auditor.audit(_plan([
      [['Dumbbell Curl', 3], ['Goblet Squat', 3]],
      [['Goblet Squat', 2], ['Lateral Raise', 4]],
    ]));
    expect(r.isoFirstDays, 1);
    expect(codes(r), containsAll(['iso_first', 'lead_starved']));
  });

  test('jump rows in week 1, and as the lead', () {
    final r = auditor.audit(_plan([
      [['Jump Squat', 3], ['Goblet Squat', 3]],
      [['Goblet Squat', 3], ['Jump Squat', 3]],
    ]));
    expect(r.jumpRowsWeek1, 2);
    expect(r.jumpLeadsWeek1, 1);
  });

  test('OHP Day with Pike Push Up counts for Strength 4-day gym plans only', () {
    final days = [
      [['Pike Push Up', 3], ['Lateral Raise', 3]],
    ];
    final gym = auditor.audit(_plan(days,
        key: 'strength|4|intermediate|basic_gym|60|1', dayNames: ['OHP Day']));
    expect((gym.ohpDays, gym.ohpPikeDays), (1, 1));
    final home = auditor.audit(_plan(days,
        key: 'strength|4|intermediate|home_dumbbells|60|1', dayNames: ['OHP Day']));
    expect((home.ohpDays, home.ohpPikeDays), (0, 0));
    final press = auditor.audit(_plan([
      [['Barbell Overhead Press', 3]],
    ], key: 'strength|4|intermediate|full_gym|60|1', dayNames: ['OHP Day']));
    expect((press.ohpDays, press.ohpPikeDays), (1, 0));
  });

  test('over_time: +6..10 min moderate, more than +10 major', () {
    final mod = auditor.audit(_plan([
      [['Goblet Squat', 3]],
    ], minutes: 67));
    expect(mod.issues.where((i) => i.code == 'over_time').map((i) => i.severity).toSet(),
        {'moderate'});
    final maj = auditor.audit(_plan([
      [['Goblet Squat', 3]],
    ], minutes: 71));
    expect(maj.verdict, 'not_suitable');
  });

  test('no_deload when week 4 is not lighter than week 3', () {
    final r = auditor.audit(_plan([
      [['Goblet Squat', 3]],
    ], deloadSets: 3));
    expect(codes(r), ['no_deload']);
  });

  test('summary counts plans per code, and the table renders one column per summary', () {
    final a = auditor.audit(_plan([
      [['Bodyweight Squat', 3]],
    ]));
    final b = auditor.audit(_plan([
      [['Goblet Squat', 3]],
    ]));
    final s = AuditSummary.of([a, b]);
    expect(s.plans, 2);
    expect(s.code('unloaded'), 1);
    expect(s.verdicts, {'needs_work': 1, 'suitable': 1});
    expect(sectionOneTable([('this tree', s)]),
        contains('| plans with an unloaded pick where a loaded row fits | 1 |\n'));
    final t = sectionOneTable([('before', s), ('after', s)]);
    expect(t, contains('| measure | before | after |\n|---|---|---|'));
    expect(t, contains('| plans with an unloaded pick where a loaded row fits | 1 | 1 |'));
  });
}
