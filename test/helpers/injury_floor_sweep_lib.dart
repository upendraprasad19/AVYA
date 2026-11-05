// Shared harness of the injury floor sweep (docs/plans/2026-10-23-library-injury-recheck.md; split into five block files
// by Batch C1, docs/plans/2026-10-25-library-batch-c-new-rows.md Task 5.3).
//
// WHY SPLIT. On the 914-row library the whole sweep took 32 minutes solo (754 s on the 285-row base): singles 6:45,
// singles 4/6 days 3:33, pairs 7:06, pairs 4/6 days 8:34, repeat 5:52. One file per block, and inside it one TEST PER
// EQUIPMENT TIER, keeps every test near two minutes (the per-test @Timeout applies per test, and CI shards hand out WHOLE
// files). Nothing was removed from the sweep: every injury x tier x goal x level x day-count x phase run still happens, with
// the same gates (the tier loop moved out of the run functions into the tests, so the ORDER of the runs differs, the set does
// not). A tier dropped from [kSweepTiers], or a block file that dropped its own tier loop, would silently lose a quarter of the
// runs: injury_sweep_b_singles_test.dart pins the lists and reads all five files for the loop and the call.
//
// The REAL PlanGenerator.instance.generateV4, flag OFF (the path users get). The tag lookup reads
// assets/data/exercise_library.json, the same file the generator is seeded from.
//
// GATED in every block: no unsafe main pick, no unsafe warm-up / cool-down pick, no pick whose name is not a library row
// (such a pick would be skipped silently by the tag lookup, so `unsafe == 0` could hide it), no main pick the run's
// equipment tier cannot perform (`unperformable`, EquipmentCapability, read from the library row) and no exercise twice in
// one day (`duplicates`); no empty day and no one-exercise day; every scanned plan week has the day count the run asked
// for (a day that never appears is neither empty nor thin); and the scan saw days and picks at all. GATED in singles
// (both), pairs (both) and repeat: no day under 3 exercises ("thin"; the thin-day top-up, OI-401, takes it to 0, and the 629
// rows of Batch C1 took the last two pairs personas, OI-408, to 0 as well). Out of scope: the cardio finisher (WorkoutDay.finisher). It takes no injuries and no screen shows it (OI-396).

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

import 'generator_golden_personas.dart' show namesByDay;

const kSweepInjuries = [
  'ankle', 'elbow', 'hamstring', 'hip', 'knee',
  'lower_back', 'neck', 'shoulder', 'wrist',
];
const kSweepPairInjuries = ['knee', 'shoulder', 'lower_back', 'wrist', 'elbow', 'hip'];
const kSweepTiers = ['bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym'];
const kSweepGoals = ['build_muscle', 'lose_fat', 'strength', 'general_fitness'];
const kSweepLevels = ['beginner', 'intermediate', 'advanced'];

class SweepTally {
  int runs = 0, days = 0, picks = 0, empty = 0, thin = 0, unsafeMain = 0, unsafeWarm = 0;
  int unresolvedMain = 0, unresolvedWarm = 0, unperformable = 0, duplicates = 0, wrongDayCount = 0;
  final sizes = <int, int>{};
  final thinBy = <String, int>{};
  String block = '';
  final oneExercise = <String>[];
  final emptyDays = <String>[];
  final unsafe = <String>{};
  final unresolved = <String>{};
  final cannotPerform = <String>{};
  final duplicated = <String>{};
  final wrongDays = <String>{};
}

/// Seeds the library into Hive once per test file and runs the sweep blocks. Call [install] from `main()`.
class SweepHarness {
  SweepHarness._();

  static const _testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory _tempDir;
  final tagsByName = <String, Set<String>>{};
  final needsByName = <String, Object?>{};

  static SweepHarness install() {
    TestWidgetsFlutterBinding.ensureInitialized();
    final h = SweepHarness._();
    setUpAll(h._setUp);
    tearDownAll(h._tearDown);
    return h;
  }

  Future<void> _setUp() async {
    _tempDir = await Directory.systemTemp.createTemp('injury_floor_sweep');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => _tempDir.path,
    );
    Hive.init(_tempDir.path);
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
    await HiveUserSession.openForUser(_testUser);
  }

  Future<void> _tearDown() async {
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    try {
      if (_tempDir.existsSync()) _tempDir.deleteSync(recursive: true);
    } catch (_) {}
  }

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

  /// [dayCount] is the training days a week the run asked for: a plan week that has more or fewer days than that is
  /// counted, so a day that never appears (neither empty nor thin, because it is not there) cannot hide.
  void scan(SweepTally t, Phase p, List<String> injuries, String label, int dayCount) {
    t.runs++;
    // The label is `<injuries>|<tier>|...`; the capability set is what the
    // generator itself resolves for that tier with no owned items and no exclusions.
    final capability =
        EquipmentVocab.effectiveItems(label.split('|')[1], null, null);
    for (final wk in p.weekPlans.take(2)) {
      if (wk.workoutDays.length != dayCount) {
        t.wrongDayCount++;
        t.wrongDays.add('$label: ${wk.workoutDays.length} days, asked for $dayCount');
      }
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

  void report(String block, SweepTally t, Stopwatch sw) {
    t.block = block;
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

  void expectSafe(SweepTally t) {
    // Non-vacuity: 3-day plans are the shortest (2 weeks x 3 days = 6 days a run).
    expect(t.days, greaterThanOrEqualTo(t.runs * 6),
        reason: 'the scan saw too few days; every zero below would pass on an empty scan');
    expect(t.picks, greaterThan(0), reason: 'the scan saw no exercise at all');
    expect(t.wrongDayCount, 0, reason: 'plan weeks whose day count is not the one asked for: ${t.wrongDays.take(10).toList()}');
    expect(t.unsafeMain, 0, reason: 'unsafe main picks: ${t.unsafe}');
    expect(t.unsafeWarm, 0, reason: 'unsafe warm-up / cool-down picks: ${t.unsafe}');
    expect(t.unresolvedMain, 0, reason: 'main picks that are not library rows: ${t.unresolved}');
    expect(t.unresolvedWarm, 0,
        reason: 'warm-up / cool-down picks that are not library rows: ${t.unresolved}');
    expect(t.unperformable, 0,
        reason: 'main picks the run\'s equipment tier cannot perform: ${t.cannotPerform}');
    expect(t.duplicates, 0, reason: 'a name twice in one day: ${t.duplicated}');
    expect(t.empty, 0, reason: 'a day with no exercise at all: ${t.emptyDays}');
  }

  /// Measured ceilings of the days the session set budget leaves thin, per block (the block name `report` is given): the
  /// pair is (days under 3 exercises, days with exactly 1). Before the budget flipped (2026-11-02) both were hard zeros
  /// because the thin-day top-up (OI-408) ran into a trim that only cut the tail of a full day. The budget sizes a day by
  /// the user's minutes and by a WEEKLY band per muscle group, so a 6-day beginner week whose bands are spent drops the
  /// last accessories of a day and an injured pool is thin to begin with. Measured on the 914-row library in
  /// `docs/audit/set-budget-flip.closure.yaml` (SBF-THIN-DAYS), a founder call: keep the weekly band hard (today), or let
  /// a day under 2 exercises exceed it by a few sets. No block has an EMPTY day (the allocator's guard, a hard zero in
  /// [expectSafe]); a ceiling moves DOWN freely; a rise needs a recorded decision (see below).
  /// OI-456 piece B (count band: every day SEATS its exercises at 2 sets first, floor 4/5 by minutes) re-measured all 20
  /// blocks: 14 of 20 fell to 0 thin days and 0 one-exercise days (seating at 2 sets leaves room for the 3rd and 4th
  /// exercise that the 3-set seat used to starve); the six `pairs` / `pairs46` blocks of home_dumbbells, basic_gym and
  /// full_gym keep a small residue, every day of it a shoulder+elbow pair (small injured pool; measured 2026-11-04):
  /// pairs 10 / 22 / 14 and pairs46 12 / 8 / 4, down from 76 / 126 / 106 and 120 / 143 / 125. No empty day anywhere.
  /// Batch C2a (OI-460, library v18, 864 rows), merged onto the count band, re-measured all 20 blocks: one rose, `repeat bodyweight` 0 -> 4 thin days (2 elbow 5d, 2 lower_back 4d: the phase-1 plan now pins different rows and a repeat phase drops an unsafe pin with no refill; 0 one-exercise days, 0 empty days), a recorded decision in the C2a diagnose-doc (c2a7f1). The other 19 blocks held.
  /// OI-456 piece A (rest by exercise type, 3 base sets every day) re-measured all 20 blocks: 18 fell, 1 equal, 1 rose
  /// (one-exercise days never rose); the one that rose is `pairs bodyweight` thin days 30 -> 32 (knee+elbow 10,
  /// lower_back+elbow 4, wrist+elbow 8, elbow+hip 10), a recorded decision in the OI-456 diagnose-doc. MEASURED cause
  /// (probe, 2026-11-04): the 3 base sets, not the rest. Old 4/3/2 base sets with the new rests gives 30; the new 3 base
  /// sets with the old intensity-keyed rests gives 32. So a former 2-set endurance day now starts at 3 and a small
  /// injured pool spends its weekly band sooner.
  static const Map<String, (int thin, int one)> kThinCeilings = {
    'pairs bodyweight': (0, 0),
    'pairs home_dumbbells': (10, 0),
    'pairs basic_gym': (22, 0),
    'pairs full_gym': (14, 0),
    'pairs46 bodyweight': (0, 0),
    'pairs46 home_dumbbells': (12, 0),
    'pairs46 basic_gym': (8, 0),
    'pairs46 full_gym': (4, 0),
    'repeat bodyweight': (4, 0),
    'repeat home_dumbbells': (0, 0),
    'repeat basic_gym': (0, 0),
    'repeat full_gym': (0, 0),
    'singles bodyweight': (0, 0),
    'singles home_dumbbells': (0, 0),
    'singles basic_gym': (0, 0),
    'singles full_gym': (0, 0),
    'singles46 bodyweight': (0, 0),
    'singles46 home_dumbbells': (0, 0),
    'singles46 basic_gym': (0, 0),
    'singles46 full_gym': (0, 0),
  };

  /// Every block: thin days (under 3 exercises) and one-exercise days match the measured
  /// count EXACTLY. Above the count is a regression; BELOW it means the ceiling is stale and
  /// must be lowered here (a ratchet only works when a better number also fails).
  void expectNoThin(SweepTally t) {
    final c = kThinCeilings[t.block];
    expect(c, isNotNull, reason: 'no thin-day ceiling recorded for the block "${t.block}"');
    expect(t.thin, lessThanOrEqualTo(c!.$1), reason: 'days under 3 exercises: ${t.thinBy}');
    expect(t.oneExercise.length, lessThanOrEqualTo(c.$2),
        reason: 'a one-exercise day: ${t.oneExercise.take(10).toList()}');
    expect(t.thin, c.$1,
        reason: 'block "${t.block}": thin days fell below the recorded ceiling; lower kThinCeilings to ${t.thin}');
    expect(t.oneExercise.length, c.$2,
        reason: 'block "${t.block}": one-exercise days fell below the recorded ceiling; lower kThinCeilings to ${t.oneExercise.length}');
  }

  SweepTally runSingles(String tier, List<int> days, List<int> phases) {
    final t = SweepTally();
    for (final injury in kSweepInjuries) {
      for (final goal in kSweepGoals) {
        for (final level in kSweepLevels) {
          for (final d in days) {
            for (final phase in phases) {
              scan(
                t,
                gen(tier: tier, goal: goal, level: level, days: d, phase: phase, injuries: [injury]),
                [injury],
                '$injury|$tier|$goal|$level|${d}d|p$phase',
                d,
              );
            }
          }
        }
      }
    }
    return t;
  }

  SweepTally runPairs(String tier, List<int> days) {
    final t = SweepTally();
    for (var i = 0; i < kSweepPairInjuries.length; i++) {
      for (var j = i + 1; j < kSweepPairInjuries.length; j++) {
        final pair = [kSweepPairInjuries[i], kSweepPairInjuries[j]];
        for (final goal in kSweepGoals) {
          for (final level in kSweepLevels) {
            for (final d in days) {
              scan(
                t,
                gen(tier: tier, goal: goal, level: level, days: d, phase: 1, injuries: pair),
                pair,
                '${pair.join('+')}|$tier|$goal|$level|${d}d|p1',
                d,
              );
            }
          }
        }
      }
    }
    return t;
  }

  SweepTally runRepeat(String tier, List<int> days) {
    final t = SweepTally();
    for (final injury in kSweepInjuries) {
      for (final goal in kSweepGoals) {
        for (final level in kSweepLevels) {
          for (final d in days) {
            final first = gen(tier: tier, goal: goal, level: level, days: d, phase: 1, injuries: const []);
            final pins = namesByDay(first);
            scan(
              t,
              gen(tier: tier, goal: goal, level: level, days: d, phase: 2, injuries: [injury], pins: pins),
              [injury],
              '$injury|$tier|$goal|$level|${d}d|p2-pinned',
              d,
            );
          }
        }
      }
    }
    return t;
  }
}
