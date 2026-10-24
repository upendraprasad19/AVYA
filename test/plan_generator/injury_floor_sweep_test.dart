@Timeout(Duration(minutes: 10))
library;

// Injury re-check sweep — docs/plans/2026-10-23-library-injury-recheck.md.
//
// The REAL PlanGenerator.instance.generateV4, flag OFF (the path users get),
// over every injury x equipment tier x goal x level x days, in five separate
// tests so each has its own timeout and wall time. All four day counts the
// product offers (3, 4, 5, 6) are swept (B-pass F3: 4 and 6 were missing):
//   singles — the 9 injuries one at a time: 3 and 5 days at phases 1 and 3,
//             then 4 and 6 days at phase 1;
//   pairs   — all 15 pairs of knee/shoulder/lower_back/wrist/elbow/hip (the six
//             injuries with the most v14 tags), phase 1: 3 and 5 days, then 4
//             and 6 days;
//   repeat  — phase 1 generated uninjured, then phase 2 with the injury and that
//             plan's names pinned, at 3, 4, 5 and 6 days (the repeat-phase path,
//             where a now-unsafe pin is dropped with no refill,
//             exercise_selector.dart buildPinnedDays).
//
// GATED in every block: no unsafe main pick, no unsafe warm-up / cool-down
// pick, no pick whose name is not a library row (such a pick would be skipped
// silently by the tag lookup, so `unsafe == 0` could hide it), no main pick the
// run's equipment tier cannot perform (`unperformable`, EquipmentCapability, read
// from the library row) and no exercise twice in one day (`duplicates`). GATED in
// every block: no empty day and no one-exercise day, and the scan saw days and
// picks at all (B-pass F2: a run that generated nothing would otherwise pass every
// zero above). GATED in singles (both) and repeat: no day under 3 exercises
// ("thin"). The thin-day top-up (OI-401, docs/plans/2026-10-24-thin-day-topup.md)
// is what takes the empty, one-exercise and thin counts to 0; before it, two
// injuries at once left up to 6 days empty and the founder accepted that for one
// batch (plan Ruling E5 of the injury re-check, 2026-10-23).
// RATCHETED in the two pairs blocks: thin days may not exceed kPairsThinBaseline
// and kPairs46ThinBaseline, and every thin day must belong to ONE persona,
// shoulder + lower_back (bodyweight, beginner, 5- and 6-day plans), whose day
// VolumeFilter trims to 4 slots before the selector runs; the top-up leaves
// `Plank, Dead Bug` there (OI-408).
// Out of scope: the cardio finisher (WorkoutDay.finisher). It takes no injuries
// and no screen shows it (OI-396).
//
// The tag lookup reads assets/data/exercise_library.json, the same file the
// generator is seeded from.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/utils/equipment_vocab.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/equipment_capability.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';

import '../helpers/generator_golden_personas.dart' show namesByDay;

const _injuries = [
  'ankle', 'elbow', 'hamstring', 'hip', 'knee',
  'lower_back', 'neck', 'shoulder', 'wrist',
];
const _pairInjuries = ['knee', 'shoulder', 'lower_back', 'wrist', 'elbow', 'hip'];
const _tiers = ['bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym'];
const _goals = ['build_muscle', 'lose_fat', 'strength', 'general_fitness'];
const _levels = ['beginner', 'intermediate', 'advanced'];

/// Thin days (1 or 2 exercises) left in the 3/5-day pairs block after the top-up.
/// SCAN days: one day in week 1 or week 2, and the 6-day plans repeat variant A in
/// both scanned weeks (`useB` is false there), so 2 scan days is one plan day seen
/// twice. All of them are shoulder + lower_back, bodyweight, beginner (the 5-day
/// build_muscle plan): OI-408.
const kPairsThinBaseline = 2;

/// The same ratchet for the 4/6-day pairs block: 6 scan days, the 6-day lose_fat,
/// strength and general_fitness plans for the same persona (OI-408).
const kPairs46ThinBaseline = 6;

/// The one persona allowed to be thin after the top-up (the `thinBy` key).
const kResidualThinKey = 'shoulder+lower_back|shoulder+lower_back';

class _Tally {
  int runs = 0, days = 0, picks = 0, empty = 0, thin = 0, unsafeMain = 0, unsafeWarm = 0;
  int unresolvedMain = 0, unresolvedWarm = 0, unperformable = 0, duplicates = 0;
  final sizes = <int, int>{};
  final thinBy = <String, int>{};
  final oneExercise = <String>[];
  final emptyDays = <String>[];
  final unsafe = <String>{};
  final unresolved = <String>{};
  final cannotPerform = <String>{};
  final duplicated = <String>{};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;
  final tagsByName = <String, Set<String>>{};
  final needsByName = <String, Object?>{};

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('injury_floor_sweep');
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
      final m = Map<String, dynamic>.from(r);
      await exBox.put((m['id'] ?? m['name']).toString(), m);
      final ic = m['injury_contraindications'];
      tagsByName[(m['name'] as String).toLowerCase()] = {
        if (ic is List) ...ic.map((t) => t.toString().toLowerCase()),
      };
      needsByName[(m['name'] as String).toLowerCase()] = m['equipment_needed'];
    }
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
  });

  tearDownAll(() async {
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Phase gen({
    required String tier,
    required String goal,
    required String level,
    required int days,
    required int phase,
    required List<String> injuries,
    Map<int, ({List<String> a, List<String> b})>? pins,
  }) =>
      PlanGenerator.instance.generateV4(
        goal: goal,
        equipment: tier,
        daysPerWeek: days,
        phase: phase,
        experienceLevel: level,
        injuries: injuries,
        equipmentExclusions: const [],
        previousWeights: const {},
        pinnedExercisesByDay: pins,
      );

  void scan(_Tally t, Phase p, List<String> injuries, String label) {
    t.runs++;
    // The label is `<injuries>|<tier>|...`; the capability set is what the
    // generator itself resolves for that tier with no owned items and no exclusions.
    final capability =
        EquipmentVocab.effectiveItems(label.split('|')[1], null, null);
    for (final wk in p.weekPlans.take(2)) {
      for (final day in wk.workoutDays) {
        t.days++;
        final dayNames = [for (final e in day.exercises) e.exerciseName];
        if (dayNames.toSet().length != dayNames.length) {
          t.duplicates++;
          t.duplicated.add('$label|${day.focus}: ${dayNames.join(', ')}');
        }
        for (final e in day.exercises) {
          final needs = needsByName[e.exerciseName.toLowerCase()];
          if (needs != null && !EquipmentCapability.canPerform(needs, capability)) {
            t.unperformable++;
            t.cannotPerform.add('$label: ${e.exerciseName} needs $needs');
          }
        }
        final n = day.exercises.length;
        t.sizes[n] = (t.sizes[n] ?? 0) + 1;
        if (n == 0) {
          t.empty++;
          t.emptyDays.add('$label|${day.focus}');
        } else if (n < 3) {
          t.thin++;
          final k = '${injuries.join('+')}|${label.split('|')[0]}';
          t.thinBy[k] = (t.thinBy[k] ?? 0) + 1;
          if (n == 1) {
            t.oneExercise.add('$label|${day.focus}: '
                '${day.exercises.map((e) => e.exerciseName).join(', ')}');
          }
        }
        void check(Iterable<PlannedExercise> list, bool main) {
          for (final e in list) {
            t.picks++;
            final tags = tagsByName[e.exerciseName.toLowerCase()];
            if (tags == null) {
              if (main) {
                t.unresolvedMain++;
              } else {
                t.unresolvedWarm++;
              }
              t.unresolved.add('${main ? 'main' : 'warm/cool'}: ${e.exerciseName}');
            } else if (injuries.any(tags.contains)) {
              if (main) {
                t.unsafeMain++;
              } else {
                t.unsafeWarm++;
              }
              t.unsafe.add('${injuries.join('+')}: ${e.exerciseName}');
            }
          }
        }

        check(day.exercises, true);
        check([...day.warmup, ...day.cooldown], false);
      }
    }
  }

  void report(String block, _Tally t, Stopwatch sw) {
    final sizes = (t.sizes.keys.toList()..sort()).map((k) => '$k:${t.sizes[k]}').join(' ');
    // ignore: avoid_print
    print('[$block] ${sw.elapsed} runs ${t.runs} days ${t.days} empty ${t.empty} '
        'thin(<3) ${t.thin} one-exercise ${t.oneExercise.length} '
        'unsafe-main ${t.unsafeMain} unsafe-warm/cool ${t.unsafeWarm} '
        'unresolved-main ${t.unresolvedMain} unresolved-warm/cool ${t.unresolvedWarm} '
        'unperformable ${t.unperformable} duplicates ${t.duplicates}\n'
        '[$block] sizes $sizes\n'
        '[$block] thin by ${t.thinBy}\n'
        '[$block] unsafe ${(t.unsafe.toList()..sort())}\n'
        '[$block] unresolved ${(t.unresolved.toList()..sort())}\n'
        '[$block] unperformable ${(t.cannotPerform.toList()..sort())}\n'
        '[$block] duplicates ${(t.duplicated.toList()..sort())}\n'
        '[$block] EMPTY DAYS ${(t.emptyDays..sort())}\n'
        '[$block] ONE-EXERCISE DAYS\n${(t.oneExercise..sort()).take(60).join('\n')}');
  }

  void expectSafe(_Tally t) {
    // Non-vacuity: 3-day plans are the shortest (2 weeks x 3 days = 6 days a run).
    expect(t.days, greaterThanOrEqualTo(t.runs * 6),
        reason: 'the scan saw too few days; every zero below would pass on an empty scan');
    expect(t.picks, greaterThan(0), reason: 'the scan saw no exercise at all');
    expect(t.unsafeMain, 0, reason: 'unsafe main picks: ${t.unsafe}');
    expect(t.unsafeWarm, 0, reason: 'unsafe warm-up / cool-down picks: ${t.unsafe}');
    expect(t.unresolvedMain, 0, reason: 'main picks that are not library rows: ${t.unresolved}');
    expect(t.unresolvedWarm, 0,
        reason: 'warm-up / cool-down picks that are not library rows: ${t.unresolved}');
    expect(t.unperformable, 0,
        reason: 'main picks the run\'s equipment tier cannot perform: ${t.cannotPerform}');
    expect(t.duplicates, 0, reason: 'a name twice in one day: ${t.duplicated}');
    expect(t.empty, 0, reason: 'a day with no exercise at all: ${t.emptyDays}');
    expect(t.oneExercise, isEmpty,
        reason: 'a one-exercise day: ${t.oneExercise.take(10).toList()}');
  }

  /// Singles and repeat: the top-up leaves no day under 3 exercises.
  void expectNoThin(_Tally t) {
    expect(t.thin, 0, reason: 'days under 3 exercises: ${t.thinBy}');
  }

  /// Pairs: thin days may not exceed [baseline], and all belong to the one persona
  /// OI-408 owns. A persona that appears here that is not in that set is a new
  /// finding, not a baseline.
  void expectOnlyResidualThin(_Tally t, int baseline) {
    expect(t.thin, lessThanOrEqualTo(baseline),
        reason: 'more thin days than the baseline: ${t.thinBy}');
    expect(t.thinBy.keys.toSet().difference({kResidualThinKey}), isEmpty,
        reason: 'thin days outside the OI-408 persona: ${t.thinBy}');
  }

  void runSingles(_Tally t, List<int> days, List<int> phases) {
    for (final injury in _injuries) {
      for (final tier in _tiers) {
        for (final goal in _goals) {
          for (final level in _levels) {
            for (final d in days) {
              for (final phase in phases) {
                scan(
                  t,
                  gen(tier: tier, goal: goal, level: level, days: d, phase: phase,
                      injuries: [injury]),
                  [injury],
                  '$injury|$tier|$goal|$level|${d}d|p$phase',
                );
              }
            }
          }
        }
      }
    }
  }

  void runPairs(_Tally t, List<int> days) {
    for (var i = 0; i < _pairInjuries.length; i++) {
      for (var j = i + 1; j < _pairInjuries.length; j++) {
        final pair = [_pairInjuries[i], _pairInjuries[j]];
        for (final tier in _tiers) {
          for (final goal in _goals) {
            for (final level in _levels) {
              for (final d in days) {
                scan(
                  t,
                  gen(tier: tier, goal: goal, level: level, days: d, phase: 1,
                      injuries: pair),
                  pair,
                  '${pair.join('+')}|$tier|$goal|$level|${d}d|p1',
                );
              }
            }
          }
        }
      }
    }
  }

  void runRepeat(_Tally t, List<int> days) {
    for (final injury in _injuries) {
      for (final tier in _tiers) {
        for (final goal in _goals) {
          for (final level in _levels) {
            for (final d in days) {
              final first = gen(
                  tier: tier, goal: goal, level: level, days: d, phase: 1,
                  injuries: const []);
              final pins = namesByDay(first);
              scan(
                t,
                gen(tier: tier, goal: goal, level: level, days: d, phase: 2,
                    injuries: [injury], pins: pins),
                [injury],
                '$injury|$tier|$goal|$level|${d}d|p2-pinned',
              );
            }
          }
        }
      }
    }
  }

  test('singles: 9 injuries x tiers x goals x levels x 3/5 days x phases 1,3', () {
    final sw = Stopwatch()..start();
    final t = _Tally();
    runSingles(t, const [3, 5], const [1, 3]);
    report('singles', t, sw);
    expect(t.runs, 1728);
    expectSafe(t);
    expectNoThin(t);
  });

  test('singles 4/6 days: 9 injuries x tiers x goals x levels x 4/6 days x phase 1', () {
    final sw = Stopwatch()..start();
    final t = _Tally();
    runSingles(t, const [4, 6], const [1]);
    report('singles46', t, sw);
    expect(t.runs, 864);
    expectSafe(t);
    expectNoThin(t);
  });

  test('pairs: all 15 pairs of knee/shoulder/lower_back/wrist/elbow/hip, 3/5 days, phase 1', () {
    final sw = Stopwatch()..start();
    final t = _Tally();
    runPairs(t, const [3, 5]);
    report('pairs', t, sw);
    expect(t.runs, 1440);
    expectSafe(t);
    expectOnlyResidualThin(t, kPairsThinBaseline);
  });

  test('pairs 4/6 days: all 15 pairs of knee/shoulder/lower_back/wrist/elbow/hip, phase 1', () {
    final sw = Stopwatch()..start();
    final t = _Tally();
    runPairs(t, const [4, 6]);
    report('pairs46', t, sw);
    expect(t.runs, 1440);
    expectSafe(t);
    expectOnlyResidualThin(t, kPairs46ThinBaseline);
  });

  test('repeat: phase 1 uninjured, then phase 2 with the injury and those pins, 3/4/5/6 days', () {
    final sw = Stopwatch()..start();
    final t = _Tally();
    runRepeat(t, const [3, 4, 5, 6]);
    report('repeat', t, sw);
    expect(t.runs, 1728);
    expectSafe(t);
    expectNoThin(t);
  });
}
