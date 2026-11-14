// Unit 2C-a (OI-475 L2 / L3, founder d35, d39, d40, d41, d43, d46; plan docs/plans/2026-11-14-generator-step2c-balanced-week.md
// v6, section 2A): the balanced build_muscle week at 60+ minutes.
//
//  - S1: 3-day Upper / Lower / Full Body, 4-day Upper A / Lower A / Upper B / Lower B, 5-day Push / Pull / Legs / Upper /
//    Lower + Core, each day with a B list; the later day of a type soft-avoids the earlier one's picks (`sameType`), the
//    3-day Full Body soft-avoids every earlier day's (`all`, d46). Below 60 minutes, other goals, the 6-day split and a
//    beginner's 3 / 4-day Full Body keep today's lists.
//  - S2: in those plans a quad-first row credits Quads, not Glutes (the 6-day rule of OI-454, widened).
//  - S5: one kill switch, `disable_balanced_week`, read by each reader.
//  - The repeat-phase pins refuse rows of the other split family and rows past the new plan's day count.
//
// Every expected value is restated here (lists from the plan, the predicate and the credit in this file's own words);
// no oracle calls `balancedWeekApplies` or `quadPrimaryCreditsGlutes`.
@Timeout(Duration(minutes: 8))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/exercise_selector.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/split_resolver.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/volume_filter.dart';

typedef _Day = (String, String, EarlierDayAvoid, List<String>, List<String>);

/// The balanced lists (plan section 2A), slot by slot as `target/subFocus/pattern/type/priority`, A then B.
const Map<int, List<_Day>> _balanced = {
  3: [
    (
      'Upper',
      'upper',
      EarlierDayAvoid.none,
      [
        'Mid Chest//horizontal_push/compound/1',
        'Lats/width/vertical_pull/compound/1',
        'Biceps//elbow_flexion/isolation/2',
        'Triceps//elbow_extension/isolation/2',
        'Shoulders//vertical_push/compound/2',
        'Lateral Delts//shoulder_isolation/isolation/3',
        'Mid Back//horizontal_pull/compound/3',
        'Rear Delts//shoulder_isolation/isolation/4',
      ],
      [
        'Upper Chest//horizontal_push/compound/1',
        'Mid Back/thickness/horizontal_pull/compound/1',
        'Biceps/long_head/elbow_flexion/isolation/2',
        'Triceps/long_head/elbow_extension/isolation/2',
        'Lateral Delts//shoulder_isolation/isolation/2',
        'Shoulders//vertical_push/compound/3',
        'Lats//vertical_pull/compound/3',
        'Rear Delts/cable/shoulder_isolation/isolation/4',
      ],
    ),
    (
      'Lower',
      'legs',
      EarlierDayAvoid.none,
      [
        'Quads//knee_dominant/compound/1',
        'Hamstrings//hip_dominant/compound/1',
        'Core//core/isolation/2',
        'Quads/isolation/knee_dominant/isolation/2',
        'Calves//knee_dominant/isolation/2',
        'Hamstrings//knee_dominant/isolation/3',
        'Glutes//hip_isolation/isolation/3',
        'Hip//hip_isolation/isolation/4',
      ],
      [
        'Quads//knee_dominant/compound/1',
        'Glutes//hip_dominant/compound/1',
        'Core/obliques/core/isolation/2',
        'Hamstrings//knee_dominant/isolation/2',
        'Calves//knee_dominant/isolation/2',
        'Quads/isolation/knee_dominant/isolation/3',
        'Hamstrings//hip_dominant/compound/3',
        'Hip//hip_isolation/isolation/4',
      ],
    ),
    (
      'Full Body',
      'full_body',
      EarlierDayAvoid.all,
      [
        'Quads//knee_dominant/compound/1',
        'Mid Chest//horizontal_push/compound/1',
        'Lats/width/vertical_pull/compound/1',
        'Core//core/isolation/2',
        'Hamstrings//hip_dominant/compound/2',
        'Shoulders//vertical_push/compound/2',
        'Biceps//elbow_flexion/isolation/3',
        'Triceps//elbow_extension/isolation/3',
      ],
      [
        'Hamstrings//hip_dominant/compound/1',
        'Upper Chest//horizontal_push/compound/1',
        'Mid Back//horizontal_pull/compound/1',
        'Core/obliques/core/isolation/2',
        'Quads//knee_dominant/compound/2',
        'Lateral Delts//shoulder_isolation/isolation/2',
        'Triceps/long_head/elbow_extension/isolation/3',
        'Biceps/long_head/elbow_flexion/isolation/3',
      ],
    ),
  ],
  4: [
    (
      'Upper A',
      'upper',
      EarlierDayAvoid.none,
      [
        'Mid Chest//horizontal_push/compound/1',
        'Lats/width/vertical_pull/compound/1',
        'Biceps//elbow_flexion/isolation/2',
        'Triceps//elbow_extension/isolation/2',
        'Shoulders//vertical_push/compound/2',
        'Lateral Delts//shoulder_isolation/isolation/3',
        'Mid Back//horizontal_pull/compound/3',
        'Rear Delts//shoulder_isolation/isolation/4',
      ],
      [
        'Upper Chest//horizontal_push/compound/1',
        'Mid Back/thickness/horizontal_pull/compound/1',
        'Biceps/long_head/elbow_flexion/isolation/2',
        'Triceps/long_head/elbow_extension/isolation/2',
        'Lateral Delts//shoulder_isolation/isolation/2',
        'Shoulders//vertical_push/compound/3',
        'Lats//vertical_pull/compound/3',
        'Rear Delts/cable/shoulder_isolation/isolation/4',
      ],
    ),
    (
      'Lower A',
      'legs',
      EarlierDayAvoid.none,
      [
        'Quads//knee_dominant/compound/1',
        'Hamstrings//hip_dominant/compound/1',
        'Quads/isolation/knee_dominant/isolation/2',
        'Calves//knee_dominant/isolation/2',
        'Core//core/isolation/2',
        'Hamstrings//knee_dominant/isolation/3',
        'Glutes//hip_isolation/isolation/3',
        'Hip//hip_isolation/isolation/4',
      ],
      [
        'Quads//knee_dominant/compound/1',
        'Glutes//hip_dominant/compound/1',
        'Hamstrings//knee_dominant/isolation/2',
        'Calves//knee_dominant/isolation/2',
        'Core/obliques/core/isolation/2',
        'Quads/isolation/knee_dominant/isolation/3',
        'Hamstrings//hip_dominant/compound/3',
        'Hip//hip_isolation/isolation/4',
      ],
    ),
    (
      'Upper B',
      'upper',
      EarlierDayAvoid.sameType,
      [
        'Lats//horizontal_pull/compound/1',
        'Upper Chest//horizontal_push/compound/1',
        'Triceps/long_head/elbow_extension/isolation/2',
        'Biceps/long_head/elbow_flexion/isolation/2',
        'Lateral Delts//shoulder_isolation/isolation/2',
        'Lats//vertical_pull/compound/3',
        'Shoulders//vertical_push/compound/3',
        'Rear Delts/cable/shoulder_isolation/isolation/4',
      ],
      [
        'Shoulders//vertical_push/compound/1',
        'Lats/width/vertical_pull/compound/1',
        'Biceps//elbow_flexion/isolation/2',
        'Triceps//elbow_extension/isolation/2',
        'Mid Chest//horizontal_push/compound/2',
        'Lateral Delts//shoulder_isolation/isolation/3',
        'Mid Back//horizontal_pull/compound/3',
        'Rear Delts//shoulder_isolation/isolation/4',
      ],
    ),
    (
      'Lower B',
      'legs',
      EarlierDayAvoid.sameType,
      [
        'Hamstrings//hip_dominant/compound/1',
        'Quads//knee_dominant/compound/1',
        'Glutes//hip_dominant/compound/2',
        'Calves//knee_dominant/isolation/2',
        'Core/obliques/core/isolation/2',
        'Quads/isolation/knee_dominant/isolation/3',
        'Hamstrings//knee_dominant/isolation/3',
        'Glutes//hip_isolation/isolation/4',
      ],
      [
        'Glutes//hip_dominant/compound/1',
        'Quads//knee_dominant/compound/1',
        'Hamstrings//knee_dominant/isolation/2',
        'Calves//knee_dominant/isolation/2',
        'Core//core/isolation/2',
        'Quads/isolation/knee_dominant/isolation/3',
        'Hamstrings//hip_dominant/compound/3',
        'Glutes//hip_isolation/isolation/4',
      ],
    ),
  ],
  5: [
    (
      'Push',
      'push',
      EarlierDayAvoid.none,
      [
        'Mid Chest//horizontal_push/compound/1',
        'Upper Chest//horizontal_push/compound/1',
        'Shoulders//vertical_push/compound/2',
        'Lateral Delts//shoulder_isolation/isolation/2',
        'Triceps//elbow_extension/isolation/3',
        'Triceps/long_head/elbow_extension/isolation/3',
        'Lower Chest//horizontal_push/isolation/4',
        'Rear Delts//shoulder_isolation/isolation/4',
      ],
      [
        'Mid Chest//horizontal_push/compound/1',
        'Upper Chest//horizontal_push/compound/1',
        'Shoulders//vertical_push/compound/2',
        'Lateral Delts//shoulder_isolation/isolation/2',
        'Triceps//elbow_extension/isolation/3',
        'Triceps/long_head/elbow_extension/isolation/3',
        'Lower Chest//horizontal_push/isolation/4',
        'Rear Delts//shoulder_isolation/isolation/4',
      ],
    ),
    (
      'Pull',
      'pull',
      EarlierDayAvoid.none,
      [
        'Lats/width/vertical_pull/compound/1',
        'Mid Back/thickness/horizontal_pull/compound/1',
        'Lats//vertical_pull/compound/2',
        'Rear Delts//shoulder_isolation/isolation/2',
        'Biceps//elbow_flexion/isolation/3',
        'Biceps/long_head/elbow_flexion/isolation/3',
        'Mid Back//horizontal_pull/compound/4',
        'Rear Delts/cable/shoulder_isolation/isolation/4',
      ],
      [
        'Lats/width/vertical_pull/compound/1',
        'Mid Back/thickness/horizontal_pull/compound/1',
        'Lats//vertical_pull/compound/2',
        'Rear Delts//shoulder_isolation/isolation/2',
        'Biceps//elbow_flexion/isolation/3',
        'Biceps/long_head/elbow_flexion/isolation/3',
        'Mid Back//horizontal_pull/compound/4',
        'Rear Delts/cable/shoulder_isolation/isolation/4',
      ],
    ),
    (
      'Legs',
      'legs',
      EarlierDayAvoid.none,
      [
        'Quads//knee_dominant/compound/1',
        'Hamstrings//hip_dominant/compound/1',
        'Quads/isolation/knee_dominant/isolation/2',
        'Glutes//hip_isolation/isolation/2',
        'Calves//knee_dominant/isolation/3',
        'Core//core/isolation/3',
        'Hamstrings//knee_dominant/isolation/4',
        'Hip//hip_isolation/isolation/4',
      ],
      [
        'Quads//knee_dominant/compound/1',
        'Hamstrings//hip_dominant/compound/1',
        'Quads/isolation/knee_dominant/isolation/2',
        'Glutes//hip_isolation/isolation/2',
        'Calves//knee_dominant/isolation/3',
        'Core//core/isolation/3',
        'Hamstrings//knee_dominant/isolation/4',
        'Hip//hip_isolation/isolation/4',
      ],
    ),
    (
      'Upper',
      'upper',
      EarlierDayAvoid.none,
      [
        'Mid Chest//horizontal_push/compound/1',
        'Lats//horizontal_pull/compound/1',
        'Shoulders//vertical_push/compound/2',
        'Lateral Delts//shoulder_isolation/isolation/2',
        'Biceps//elbow_flexion/isolation/2',
        'Triceps//elbow_extension/isolation/3',
        'Lats//horizontal_pull/compound/3',
        'Biceps/long_head/elbow_flexion/isolation/4',
        'Triceps/long_head/elbow_extension/isolation/4',
      ],
      [
        'Mid Chest//horizontal_push/compound/1',
        'Lats//horizontal_pull/compound/1',
        'Shoulders//vertical_push/compound/2',
        'Lateral Delts//shoulder_isolation/isolation/2',
        'Biceps//elbow_flexion/isolation/2',
        'Triceps//elbow_extension/isolation/3',
        'Lats//horizontal_pull/compound/3',
        'Biceps/long_head/elbow_flexion/isolation/4',
        'Triceps/long_head/elbow_extension/isolation/4',
      ],
    ),
    (
      'Lower + Core',
      'legs',
      EarlierDayAvoid.sameType,
      [
        'Quads//knee_dominant/compound/1',
        'Glutes//hip_dominant/compound/1',
        'Core//core/isolation/2',
        'Core/obliques/core/isolation/2',
        'Calves//knee_dominant/isolation/3',
        'Hamstrings//hip_dominant/compound/3',
        'Glutes//hip_isolation/isolation/4',
        'Hip//hip_isolation/isolation/4',
      ],
      [
        'Quads//knee_dominant/compound/1',
        'Glutes//hip_dominant/compound/1',
        'Core//core/isolation/2',
        'Core/obliques/core/isolation/2',
        'Calves//knee_dominant/isolation/3',
        'Hamstrings//hip_dominant/compound/3',
        'Glutes//hip_isolation/isolation/4',
        'Hip//hip_isolation/isolation/4',
      ],
    ),
  ],
};

/// Today's build_muscle day names (intermediate), which serve below 60 minutes and with the switch set.
const Map<int, List<String>> _todayNames = {
  3: ['Push + Core', 'Pull + Core', 'Legs'],
  4: ['Push', 'Pull', 'Legs', 'Upper'],
  5: ['Chest', 'Back', 'Shoulders + Arms', 'Legs', 'Upper + Core'],
};

String _slot(MuscleSlot x) =>
    '${x.targetMuscle}/${x.subFocus ?? ''}/${x.movementPattern}/${x.exerciseType}/${x.priority}';

List<String> _names(List<MuscleSlotDay> days) => [for (final d in days) d.name];

/// The rule, restated: build_muscle, 3 to 5 days, 60+ resolved minutes, the switch not set.
bool _balancedRule(String goal, int days, int? minutes, bool switchOn) =>
    goal == 'build_muscle' && days >= 3 && days <= 5 && minutes != null && minutes >= 60 && switchOn;

/// The credit, restated: a quad-first row credits Glutes except in a balanced week and in the 6-day build_muscle split
/// while its Legs B quad slot is on.
bool _creditRule(String goal, int days, int? minutes, bool quadLegsB, bool switchOn) =>
    !(_balancedRule(goal, days, minutes, switchOn) || (goal == 'build_muscle' && days == 6 && quadLegsB));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;
  late List<Map<String, dynamic>> library;

  Future<void> seed(List<Map<String, dynamic>> rows) async {
    final box = Hive.box(HiveService.exerciseBoxName);
    await box.clear();
    for (final r in rows) {
      await box.put((r['id'] ?? r['name']).toString(), r);
    }
  }

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('balanced_week_behavioral');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    await Hive.openBox(HiveService.exerciseBoxName);
    library = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
  });

  tearDown(() async {
    await HiveService.instance.configBox.delete('disable_balanced_week');
  });

  tearDownAll(() async {
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('S1: the lists', () {
    for (final days in [3, 4, 5]) {
      for (final minutes in [60, 90]) {
        test('build_muscle ${days}d at $minutes: every day, its avoid and both lists, in order', () {
          final got = SplitResolver.selectV4('build_muscle', days, sessionMinutes: minutes, balancedWeek: true);
          final want = _balanced[days]!;
          expect(_names(got), [for (final d in want) d.$1]);
          for (var i = 0; i < want.length; i++) {
            final (name, type, avoid, a, b) = want[i];
            expect(got[i].dayType, type, reason: name);
            expect(got[i].avoidEarlier, avoid, reason: name);
            expect([for (final s in got[i].slotsA) _slot(s)], a, reason: '$name A');
            expect(got[i].slotsB, isNotNull, reason: '$name has a B list');
            expect([for (final s in got[i].slotsB!) _slot(s)], b, reason: '$name B');
          }
        });
      }
      for (final minutes in [null, 30, 45, 59]) {
        test('build_muscle ${days}d at $minutes minutes: today\'s lists', () {
          final got = SplitResolver.selectV4('build_muscle', days, sessionMinutes: minutes, balancedWeek: true);
          expect(_names(got), _todayNames[days]);
          expect(got.every((d) => d.avoidEarlier == EarlierDayAvoid.none), isTrue);
        });
      }
    }

    test('other goals and the 6-day split at 60: the same lists as at 45', () {
      for (final goal in ['strength', 'lose_fat', 'general_fitness', 'build_muscle']) {
        for (final days in [3, 4, 5, 6]) {
          if (goal == 'build_muscle' && days != 6) continue;
          final at60 = SplitResolver.selectV4(goal, days, sessionMinutes: 60, balancedWeek: true);
          final at45 = SplitResolver.selectV4(goal, days, sessionMinutes: 45, balancedWeek: true);
          expect(
            [
              for (final d in at60) [d.name, d.avoidEarlier, ...d.slotsA.map(_slot), ...?d.slotsB?.map(_slot)],
            ],
            [
              for (final d in at45) [d.name, d.avoidEarlier, ...d.slotsA.map(_slot), ...?d.slotsB?.map(_slot)],
            ],
            reason: '$goal ${days}d',
          );
        }
      }
    });

    test('beginners: 3 / 4-day Full Body until the level lifts them (phase 3), 5-day balanced in every phase', () {
      for (final days in [3, 4]) {
        final full = SplitResolver.selectV4(
          'build_muscle',
          days,
          experienceLevel: 'beginner',
          sessionMinutes: 60,
          balancedWeek: true,
        );
        expect(full.every((d) => d.name.startsWith('Full Body ')), isTrue, reason: '${days}d: ${_names(full)}');
        expect(PlanGenerator.effectiveLevel('beginner', 3), 'intermediate');
        final lifted = SplitResolver.selectV4(
          'build_muscle',
          days,
          experienceLevel: PlanGenerator.effectiveLevel('beginner', 3),
          sessionMinutes: 60,
          balancedWeek: true,
        );
        expect(_names(lifted), [for (final d in _balanced[days]!) d.$1]);
      }
      final five = SplitResolver.selectV4(
        'build_muscle',
        5,
        experienceLevel: 'beginner',
        sessionMinutes: 60,
        balancedWeek: true,
      );
      expect(_names(five), [for (final d in _balanced[5]!) d.$1]);
    });
  });

  group('S1: the predicate', () {
    test('balancedWeekApplies: days 3 / 4 / 5 only, 60+ minutes, null false, the switch, build_muscle only', () {
      for (final goal in ['build_muscle', 'strength', 'lose_fat', 'general_fitness']) {
        for (final days in [2, 3, 4, 5, 6, 7]) {
          for (final minutes in [null, 15, 30, 45, 59, 60, 61, 90, 180]) {
            for (final on in [true, false]) {
              expect(
                SplitResolver.balancedWeekApplies(goal, days, minutes, balancedWeek: on),
                _balancedRule(goal, days, minutes, on),
                reason: '$goal ${days}d $minutes min switch ${on ? 'on' : 'off'}',
              );
            }
          }
        }
      }
    });
  });

  group('S2: the credit', () {
    test('quadPrimaryCreditsGlutes over goal x days x minutes x quadLegsB x the switch', () {
      var falses = 0;
      for (final goal in ['build_muscle', 'strength', 'lose_fat', 'general_fitness']) {
        for (final days in [3, 4, 5, 6]) {
          for (final minutes in [null, 30, 45, 59, 60, 90]) {
            for (final quadLegsB in [true, false]) {
              for (final on in [true, false]) {
                final want = _creditRule(goal, days, minutes, quadLegsB, on);
                if (!want) falses++;
                expect(
                  SplitResolver.quadPrimaryCreditsGlutes(goal, days, minutes, quadLegsB: quadLegsB, balancedWeek: on),
                  want,
                  reason: '$goal ${days}d $minutes min quadLegsB $quadLegsB switch ${on ? 'on' : 'off'}',
                );
              }
            }
          }
        }
      }
      // build_muscle 3 / 4 / 5-day at 60 and 90 with the switch on (12) plus 6-day with Legs B (6 minutes x 2 switch).
      expect(falses, 3 * 2 * 2 + 6 * 2);
    });
  });

  group('S5: the switch, per reader', () {
    test('unset: ON; set: selectV4, the credit and the pin check all read it', () async {
      expect(PlanEngineFlags.balancedWeekEnabled, isTrue);
      expect(_names(SplitResolver.selectV4('build_muscle', 4, sessionMinutes: 60)), [
        for (final d in _balanced[4]!) d.$1,
      ]);
      expect(SplitResolver.quadPrimaryCreditsGlutes('build_muscle', 4, 60, quadLegsB: true), isFalse);
      expect(
        WorkoutScheduleReadService.foreignDayNamesFor(
          planGoal: 'build_muscle',
          daysPerWeek: 4,
          effectiveExp: 'intermediate',
          minutes: 60,
        ),
        _todayNames[4]!.toSet(),
      );

      await HiveService.instance.configBox.put('disable_balanced_week', true);
      expect(PlanEngineFlags.balancedWeekEnabled, isFalse);
      expect(_names(SplitResolver.selectV4('build_muscle', 4, sessionMinutes: 60)), _todayNames[4]);
      expect(SplitResolver.quadPrimaryCreditsGlutes('build_muscle', 4, 60, quadLegsB: true), isTrue);
      expect(
        WorkoutScheduleReadService.foreignDayNamesFor(
          planGoal: 'build_muscle',
          daysPerWeek: 4,
          effectiveExp: 'intermediate',
          minutes: 60,
        ),
        {for (final d in _balanced[4]!) d.$1},
        reason: 'with the switch set, a balanced phase\'s rows are the other family',
      );
    });

    test('generateV4 reads it: 60 minutes builds the balanced days, the switch set builds today\'s', () async {
      await seed(library);
      Phase gen() => PlanGenerator.instance.generateV4(
        goal: 'build_muscle',
        equipment: 'full_gym',
        daysPerWeek: 4,
        phase: 1,
        experienceLevel: 'intermediate',
        injuries: const [],
        sessionDuration: 60,
        previousWeights: const {},
      );
      List<String> dayNames(Phase p) => [for (final d in p.weekPlans.first.workoutDays) d.name];
      expect(dayNames(gen()), [for (final d in _balanced[4]!) d.$1]);
      await HiveService.instance.configBox.put('disable_balanced_week', true);
      expect(dayNames(gen()), _todayNames[4]);
    });
  });

  group('the filter carry', () {
    test('VolumeFilter.filterDays keeps avoidEarlier on every week character', () {
      for (final avoid in EarlierDayAvoid.values) {
        for (final wc in ['baseline', 'overreach', 'peak', 'deload']) {
          final day = MuscleSlotDay(
            name: 'D',
            focus: 'f',
            dayType: 'legs',
            intensity: 'hypertrophy',
            avoidEarlier: avoid,
            slotsA: const [
              MuscleSlot(
                targetMuscle: 'Quads',
                movementPattern: 'knee_dominant',
                exerciseType: 'compound',
                priority: 1,
              ),
            ],
            slotsB: const [
              MuscleSlot(
                targetMuscle: 'Quads',
                movementPattern: 'knee_dominant',
                exerciseType: 'compound',
                priority: 1,
              ),
            ],
          );
          expect(VolumeFilter.filterDays([day], weekCharacter: wc).single.avoidEarlier, avoid, reason: '$avoid $wc');
        }
      }
    });
  });

  group('the earlier-day avoid, through VolumeFilter and pickV4', () {
    // Three knee_dominant Quads compounds, core at every level, ranked 1 / 2 / 3 by priority_tier.
    Map<String, dynamic> lunge(int i) {
      final base = library.firstWhere((r) => r['id'] == 'E042');
      return {
        ...base,
        'id': 'X00$i',
        'name': 'Test Lunge $i',
        'priority_tier': i,
        'core_levels': ['beginner', 'intermediate', 'advanced'],
      }..remove('same_movement_as');
    }

    const knee = MuscleSlot(
      targetMuscle: 'Quads',
      movementPattern: 'knee_dominant',
      exerciseType: 'compound',
      priority: 1,
    );
    MuscleSlotDay day(String name, String type, EarlierDayAvoid avoid) => MuscleSlotDay(
      name: name,
      focus: 'f',
      dayType: type,
      intensity: 'hypertrophy',
      avoidEarlier: avoid,
      slotsA: const [knee],
      slotsB: const [knee],
    );

    List<PopulatedDay> pick(List<MuscleSlotDay> days) => ExerciseSelector.pickV4(
      slotDays: VolumeFilter.filterDays(days, weekCharacter: 'baseline'),
      exerciseRepo: ExerciseRepository.instance,
      equipmentTier: 'full_gym',
      effectiveExp: 'intermediate',
      phase: 1,
      goal: 'build_muscle',
      exclusions: const {},
      capability: null,
    );
    List<String> a(PopulatedDay d) => [for (final e in d.exercisesA) e.exerciseName];
    List<String> b(PopulatedDay d) => [for (final e in d.exercisesB) e.exerciseName];

    test('sameType: the later day of a type does not repeat the earlier one\'s picks (A and B)', () async {
      await seed([lunge(1), lunge(2), lunge(3)]);
      final out = pick([
        day('Lower A', 'legs', EarlierDayAvoid.none),
        day('Lower B', 'legs', EarlierDayAvoid.sameType),
      ]);
      expect(a(out[0]), ['Test Lunge 1']);
      expect(b(out[0]), ['Test Lunge 2'], reason: 'B soft-avoids A (today)');
      expect(a(out[1]), isNot(a(out[0])));
      expect(b(out[1]), isNot(b(out[0])));
    });

    test('sameType, variant B on its own: the later day\'s B avoids the earlier day\'s B picks', () async {
      // A is a hinge slot and B a knee slot, so B's within-day avoid of A's picks never touches the lunges: only the
      // earlier day's B names can move the later B off Test Lunge 1.
      final hinge = {
        ...library.firstWhere((r) => r['id'] == 'E045'),
        'id': 'X010',
        'name': 'Test Hinge',
        'core_levels': ['beginner', 'intermediate', 'advanced'],
      };
      await seed([hinge, lunge(1), lunge(2), lunge(3)]);
      const hingeSlot =
          MuscleSlot(targetMuscle: 'Hamstrings', movementPattern: 'hip_dominant', exerciseType: 'compound', priority: 1);
      MuscleSlotDay split(String name, EarlierDayAvoid avoid) => MuscleSlotDay(
          name: name, focus: 'f', dayType: 'legs', intensity: 'hypertrophy', avoidEarlier: avoid,
          slotsA: const [hingeSlot], slotsB: const [knee]);
      final out = pick([split('Lower A', EarlierDayAvoid.none), split('Lower B', EarlierDayAvoid.sameType)]);
      expect(b(out[0]), ['Test Lunge 1']);
      expect(b(out[1]), ['Test Lunge 2'], reason: 'the earlier day\'s B pick is soft-avoided');
      final control = pick([split('Lower A', EarlierDayAvoid.none), split('Lower B', EarlierDayAvoid.none)]);
      expect(b(control[1]), ['Test Lunge 1'], reason: 'without the avoid the later B repeats');
    });

    test('control: with no avoid, or a different day type, the later day repeats', () async {
      await seed([lunge(1), lunge(2), lunge(3)]);
      final none = pick([day('Lower A', 'legs', EarlierDayAvoid.none), day('Lower B', 'legs', EarlierDayAvoid.none)]);
      expect(a(none[1]), a(none[0]), reason: 'the avoid is what makes the difference above');
      final other = pick([
        day('Lower A', 'legs', EarlierDayAvoid.none),
        day('Upper B', 'upper', EarlierDayAvoid.sameType),
      ]);
      expect(a(other[1]), a(other[0]), reason: 'sameType reads only the same dayType');
    });

    test('all: the Full Body day avoids every earlier day\'s picks; sameType there would not', () async {
      await seed([lunge(1), lunge(2), lunge(3)]);
      final all = pick([
        day('Upper', 'upper', EarlierDayAvoid.none),
        day('Lower', 'legs', EarlierDayAvoid.none),
        day('Full Body', 'full_body', EarlierDayAvoid.all),
      ]);
      expect(a(all[0]), ['Test Lunge 1']);
      expect(a(all[1]), ['Test Lunge 1']);
      expect(a(all[2]), isNot(contains('Test Lunge 1')));
      expect(b(all[2]), isNot(anyOf(contains(b(all[0]).single), contains(b(all[1]).single))));
      final same = pick([
        day('Upper', 'upper', EarlierDayAvoid.none),
        day('Lower', 'legs', EarlierDayAvoid.none),
        day('Full Body', 'full_body', EarlierDayAvoid.sameType),
      ]);
      expect(a(same[2]), ['Test Lunge 1'], reason: 'no earlier full_body day');
    });

    test('stated (plan S1, round 3 A-11): a repeat phase\'s fresh fill sees one frame, so it has no earlier day to avoid',
        () async {
      await seed([lunge(1), lunge(2), lunge(3)]);
      final out = ExerciseSelector.buildPinnedDays(
        frames: VolumeFilter.filterDays(
            [day('Lower A', 'legs', EarlierDayAvoid.none), day('Lower B', 'legs', EarlierDayAvoid.sameType)],
            weekCharacter: 'baseline'),
        pinnedByDay: {
          0: (a: ['Test Lunge 1'], b: ['Test Lunge 2']),
        },
        exerciseRepo: ExerciseRepository.instance,
        equipmentTier: 'full_gym',
        effectiveExp: 'intermediate',
        phase: 2,
        goal: 'build_muscle',
        capability: null,
      );
      expect(a(out[0]), ['Test Lunge 1'], reason: 'the pinned day');
      expect(a(out[1]), ['Test Lunge 1'], reason: 'the fresh-filled Lower B repeats Lower A (no earlier days in its call)');
    });

    test('a soft avoid: a pool of one repeats', () async {
      await seed([lunge(1)]);
      final out = pick([
        day('Lower A', 'legs', EarlierDayAvoid.none),
        day('Lower B', 'legs', EarlierDayAvoid.sameType),
      ]);
      expect(a(out[1]), ['Test Lunge 1']);
    });
  });

  group('the repeat-pin row checks', () {
    const stored = {
      'plan_goal': 'build_muscle',
      'equipment': 'full_gym',
      'days_per_week': 4,
      'effective_exp': 'intermediate',
    };
    Map<String, dynamic> row(int idx, String name, [String type = 'workout']) => {
      'type': type,
      'workout_day_index': idx,
      'workout_name': name,
      'exercises': [
        {'exercise_name': 'Ex $idx'},
      ],
    };
    List<Map<String, dynamic>> week(List<String> names) => [for (var i = 0; i < names.length; i++) row(i, names[i])];
    Map<int, ({List<String> a, List<String> b})>? pins(
      List<Map<String, dynamic>> w1,
      List<Map<String, dynamic>> w2,
      Set<String> foreign,
    ) => WorkoutScheduleReadService.repeatPinsFrom(
      stored: stored,
      week1: w1,
      week2: w2,
      currentPlanGoal: 'build_muscle',
      equipment: 'full_gym',
      daysPerWeek: 4,
      newPhaseEffectiveExp: 'intermediate',
      foreignDayNames: foreign,
    );
    final balancedNames = ['Upper A', 'Lower A', 'Upper B', 'Lower B'];
    final foreign = _todayNames[4]!.toSet();

    test('rows of the new family pin; one row of the other family refuses (either week)', () {
      expect(pins(week(balancedNames), week(balancedNames), foreign)?.keys, [0, 1, 2, 3]);
      final mixed = week(balancedNames)..[1] = row(1, 'Pull');
      expect(pins(mixed, week(balancedNames), foreign), isNull);
      expect(pins(week(balancedNames), mixed, foreign), isNull);
    });

    test('a renamed row (a log title) matches neither family and is not refused; a non-workout row is ignored', () {
      final renamed = week(balancedNames)..[2] = row(2, 'Morning session');
      expect(pins(renamed, week(balancedNames), foreign), isNotNull);
      final rest = [...week(balancedNames), row(1, 'Push', 'rest')];
      expect(pins(rest, week(balancedNames), foreign), isNotNull);
    });

    test('a day index past the new plan\'s days refuses; the last index pins', () {
      final past = [...week(balancedNames), row(4, 'Upper A')];
      expect(pins(past, week(balancedNames), foreign), isNull);
      expect(pins(week(balancedNames), week(balancedNames), const {}), isNotNull);
    });

    test('with no foreign names (the parameter default) the old rows pin as before', () {
      expect(pins(week(_todayNames[4]!), week(_todayNames[4]!), const {}), isNotNull);
      expect(pins(week(_todayNames[4]!), week(_todayNames[4]!), foreign), isNull);
    });

    test('foreignDayNamesFor: the other family minus the new one', () {
      Set<String> f(String goal, int days, String exp, int minutes, {bool? on}) =>
          WorkoutScheduleReadService.foreignDayNamesFor(
            planGoal: goal,
            daysPerWeek: days,
            effectiveExp: exp,
            minutes: minutes,
            balancedWeek: on,
          );
      for (final days in [3, 4, 5]) {
        final balanced = {for (final d in _balanced[days]!) d.$1};
        final today = _todayNames[days]!.toSet();
        expect(f('build_muscle', days, 'intermediate', 60), today.difference(balanced), reason: '${days}d at 60');
        expect(f('build_muscle', days, 'intermediate', 45), balanced.difference(today), reason: '${days}d at 45');
        expect(
          f('build_muscle', days, 'intermediate', 60, on: false),
          balanced.difference(today),
          reason: '${days}d off',
        );
      }
      expect(
        f('build_muscle', 5, 'intermediate', 60),
        {'Chest', 'Back', 'Shoulders + Arms', 'Upper + Core'},
        reason: 'Legs is in both 5-day families; every old week also holds Chest, so it still refuses',
      );
      expect(f('build_muscle', 6, 'intermediate', 60), isEmpty);
      expect(f('build_muscle', 3, 'beginner', 60), isEmpty, reason: 'Full Body in both');
      expect(f('strength', 3, 'intermediate', 60), isEmpty);
      expect(f('lose_fat', 4, 'intermediate', 90), isEmpty);
    });
  });

  group('the pin builder passes the new phase\'s minutes (buildRepeatPinsForAdvance, real Hive rows)', () {
    // A just-finished 4-day phase whose rows are named for today's `Push` day (the < 60-minute family), weeks 1 and 2.
    setUp(() async {
      final wb = HiveService.instance.workoutBox;
      await wb.clear();
      await HiveService.instance.userBox.delete('profile');
      await MigratedKey.write('plan_start_date', '2026-09-14');
      await MigratedKey.write('last_phase_profile', {
        'plan_goal': 'build_muscle',
        'equipment': 'full_gym',
        'days_per_week': 4,
        'effective_exp': 'intermediate',
      });
      for (final (date, name) in [('2026-09-14', 'Cable Fly'), ('2026-09-21', 'Skull Crusher')]) {
        await wb.put('schedule_$date', {
          'type': 'workout',
          'status': 'planned',
          'workout_day_index': 0,
          'workout_name': 'Push',
          'exercises': [
            {'exercise_name': name, 'sets': 3},
          ],
        });
      }
    });
    tearDown(() async {
      await HiveService.instance.workoutBox.clear();
      await HiveService.instance.userBox.delete('profile');
    });

    Map<int, ({List<String> a, List<String> b})>? pins({int? minutes}) =>
        WorkoutScheduleReadService.instance.buildRepeatPinsForAdvance(
          goal: 'build_muscle',
          equipment: 'full_gym',
          daysPerWeek: 4,
          experienceLevel: 'intermediate',
          newPhase: 2,
          sessionDuration: minutes,
        );

    test('the argument: 45 minutes pins the Push rows, 60 refuses them (the balanced family)', () {
      expect(pins(minutes: 45)?[0]?.a, ['Cable Fly']);
      expect(pins(minutes: 60), isNull);
    });

    test('no argument: the profile\'s minutes decide, as the generate after it resolves them', () async {
      await HiveService.instance.userBox.put('profile', {'session_duration_minutes': 45});
      expect(pins()?[0]?.a, ['Cable Fly']);
      await HiveService.instance.userBox.put('profile', {'session_duration_minutes': 90});
      expect(pins(), isNull);
      await HiveService.instance.userBox.delete('profile');
      expect(pins(), isNull, reason: 'an empty profile resolves to 60');
    });

    test('the switch set: the Push rows pin at 60 (today\'s family is the new one)', () async {
      await HiveService.instance.configBox.put('disable_balanced_week', true);
      expect(pins(minutes: 60)?[0]?.a, ['Cable Fly']);
    });
  });

}
