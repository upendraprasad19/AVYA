// B2 Task 6 (docs/plans/2026-10-22-session-set-budget.md): `generateV4` wiring.
//
// The REAL PlanGenerator over the shipped library. Flag OFF is the generator
// golden, byte for byte, and reads no profile minutes. Flag ON sizes each session
// by the user's minutes: the volume filter keeps every split slot, the allocator
// sizes the days, and `apply`, titration and the warm-up take the same context.
//
// The time oracle below is test-local and independent of the allocator: it prices
// each exercise the plan finally carries with the Q4 constants, at the rest the
// plan carries, from the library row's own type and rep range.
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/budget_muscle_groups.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/training_history_analyzer.dart';

import '../../scripts/migration_ledger_hash_lib.dart' show sha256Hex;
import '../helpers/generator_golden_personas.dart';

const _fixturePath = 'test/fixtures/generator_golden_hashes.json';
const _flag = 'enable_session_set_budget';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;
  late Map<String, Map<String, dynamic>> byName;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('session_budget_wiring');
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

  tearDown(() async {
    await HiveService.instance.configBox.delete(_flag);
    await HiveService.instance.configBox.delete('disable_thin_day_topup');
    await HiveService.instance.userBox.delete('profile');
  });

  Future<void> flagOn() => HiveService.instance.configBox.put(_flag, true);

  Phase gen({
    String tier = 'full_gym',
    String goal = 'build_muscle',
    int days = 4,
    String level = 'intermediate',
    int phase = 1,
    int? sessionDuration,
    List<String> injuries = const [],
    List<String> bodyFocus = const [],
    Map<int, ({List<String> a, List<String> b})>? pins,
  }) =>
      PlanGenerator.instance.generateV4(
        goal: goal,
        equipment: tier,
        daysPerWeek: days,
        phase: phase,
        experienceLevel: level,
        injuries: injuries,
        bodyFocus: bodyFocus,
        sessionDuration: sessionDuration,
        previousWeights: const {},
        pinnedExercisesByDay: pins,
      );

  /// Modelled seconds of a day's main exercises, priced independently.
  double mainSeconds(WorkoutDay d) {
    var total = 0.0;
    for (final e in d.exercises) {
      final row = byName[e.exerciseName.toLowerCase()];
      total += SessionBudget.exerciseSeconds(
        archetype: row == null ? 'B' : SessionBudget.archetypeOfRow(row),
        sets: e.sets,
        restSeconds: e.restSeconds,
      );
    }
    return total;
  }

  Iterable<WorkoutDay> allDays(Phase p) =>
      [for (final w in p.weekPlans) ...w.workoutDays];

  double budgetSeconds(int minutes) => (minutes - SessionBudget.warmCoolMinutes(minutes)) * 60;

  /// Hard sets per budget group across one week of [p].
  Map<String, int> weeklyTotals(Phase p, int week) {
    final per = <String, int>{};
    for (final d in p.weekPlans[week].workoutDays) {
      for (final e in d.exercises) {
        final row = byName[e.exerciseName.toLowerCase()];
        if (row == null) continue;
        for (final g in BudgetMuscleGroups.of([
          for (final m in (row['primary_muscles'] as List)) '$m',
        ])) {
          per[g] = (per[g] ?? 0) + e.sets;
        }
      }
    }
    return per;
  }

  /// The most hard sets any one budget group gets in a single week-1 session.
  int maxGroupSession(Phase p) {
    var best = 0;
    for (final d in p.weekPlans.first.workoutDays) {
      final per = <String, int>{};
      for (final e in d.exercises) {
        final row = byName[e.exerciseName.toLowerCase()];
        if (row == null) continue;
        for (final g in BudgetMuscleGroups.of([
          for (final m in (row['primary_muscles'] as List)) '$m',
        ])) {
          per[g] = (per[g] ?? 0) + e.sets;
        }
      }
      for (final v in per.values) {
        if (v > best) best = v;
      }
    }
    return best;
  }

  group('flag OFF', () {
    test('four golden personas are byte-identical and no profile minutes are read', () {
      final fixture = jsonDecode(File(_fixturePath).readAsStringSync()) as Map<String, dynamic>;
      final keys = [
        'grid|full_gym|build_muscle|6d|beginner|p1',
        'grid|bodyweight|lose_fat|3d|intermediate|p2',
        'grid|basic_gym|strength|4d|advanced|p3',
        'grid|home_dumbbells|general_fitness|5d|intermediate|p5',
      ];
      final personas = generatorGoldenPersonas();
      final reads = TrainingHistoryAnalyzer.debugReadCount;
      for (final k in keys) {
        final p = personas.firstWhere((x) => x.key == k);
        final hash = sha256Hex(utf8.encode(jsonEncode(p.run().toMap())));
        expect(hash, fixture[k], reason: k);
      }
      expect(TrainingHistoryAnalyzer.debugReadCount, reads);
    });
  });

  group('flag ON', () {
    test('every split slot is kept: a beginner 6-day plan holds more than the 4 exercises OFF gives', () async {
      final off = gen(days: 6, level: 'beginner');
      expect(off.weekPlans.first.workoutDays.map((d) => d.exercises.length), everyElement(4));
      await flagOn();
      final on = gen(days: 6, level: 'beginner', sessionDuration: 90);
      expect(on.weekPlans.first.workoutDays.map((d) => d.exercises.length).reduce((a, b) => a > b ? a : b),
          greaterThan(4));
    });

    test('the profile minutes size the sessions when the caller passes none', () async {
      await HiveService.instance.userBox.put('profile', {'session_duration_minutes': 30});
      final off = gen();
      expect(allDays(off).map(mainSeconds).reduce((a, b) => a > b ? a : b),
          greaterThan(budgetSeconds(30)),
          reason: 'fixture: OFF overspends a 30-minute session');
      await flagOn();
      final on = gen();
      for (final d in allDays(on)) {
        expect(mainSeconds(d), lessThanOrEqualTo(budgetSeconds(30) + 1e-6));
      }
    });

    test('a caller-supplied duration beats the profile', () async {
      await HiveService.instance.userBox.put('profile', {'session_duration_minutes': 30});
      await flagOn();
      final on = gen(sessionDuration: 90);
      final longest = allDays(on).map(mainSeconds).reduce((a, b) => a > b ? a : b);
      expect(longest, greaterThan(budgetSeconds(30)));
      expect(longest, lessThanOrEqualTo(budgetSeconds(90) + 1e-6));
    });

    test('with no minutes anywhere the session is budgeted at 60', () async {
      await flagOn();
      final on = gen();
      final longest = allDays(on).map(mainSeconds).reduce((a, b) => a > b ? a : b);
      expect(longest, lessThanOrEqualTo(budgetSeconds(60) + 1e-6));
      expect(longest, greaterThan(budgetSeconds(30)));
    });

    test('phase 4 is a lighter phase: no group is above the band bottom, where phase 3 is', () async {
      await flagOn();
      // An advanced build_muscle user: band 14-20. Phase 3 may go to the top; phase 4
      // (a deload-archetype phase) holds every group to the bottom, 14.
      final heavy = gen(days: 6, level: 'advanced', phase: 3, sessionDuration: 90);
      final light = gen(days: 6, level: 'advanced', phase: 4, sessionDuration: 90);
      int most(Map<String, int> m) => m.values.reduce((a, b) => a > b ? a : b);
      expect(most(weeklyTotals(heavy, 0)), greaterThan(14), reason: 'fixture: phase 3 goes above 14');
      expect(most(weeklyTotals(light, 0)), lessThanOrEqualTo(14));
    });

    test('a body focus is the focus group: Chest goes past the ordinary top of 16', () async {
      await flagOn();
      final plain = gen(days: 5, sessionDuration: 90);
      final focused = gen(days: 5, sessionDuration: 90, bodyFocus: const ['chest']);
      expect(weeklyTotals(plain, 0)['Chest'] ?? 0, lessThanOrEqualTo(16));
      expect(weeklyTotals(focused, 0)['Chest']!, greaterThan(16));
      expect(weeklyTotals(focused, 0)['Chest']!, lessThanOrEqualTo(25));
    });

    test('the warm-up lead-in and the cool-down walk scale with the minutes', () async {
      final off = gen();
      expect(off.weekPlans.first.workoutDays.first.warmup.first.reps, '300s');
      await flagOn();
      final on30 = gen(sessionDuration: 30);
      final day = on30.weekPlans.first.workoutDays.first;
      expect(day.warmup.first.reps, '60s');
      expect(day.cooldown.first.reps, '60s');
      final on90 = gen(sessionDuration: 90);
      expect(on90.weekPlans.first.workoutDays.first.warmup.first.reps, '300s');
    });

    test('the volume-titration and plateau pass receives the same budget (source seam)', () {
      // A source check proves PRESENCE only. The behaviour of a budgeted
      // `applyToWeeks` is pinned in session_set_budget_consumers_test.dart.
      final src = File('lib/shared/repositories/plan_engine/plan_generator.dart')
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join(String.fromCharCode(10));
      expect(src, contains('VolumeTitration.applyToWeeks(weekPlans, deltas, budget: budget)'));
    });

    test('the level is the EFFECTIVE level: a beginner at phase 5 is budgeted as advanced', () async {
      await flagOn();
      // Session caps by level (build_muscle): beginner 6, advanced 10.
      final first = gen(days: 3, level: 'beginner', phase: 1, sessionDuration: 90);
      final later = gen(days: 3, level: 'beginner', phase: 5, sessionDuration: 90);
      expect(maxGroupSession(first), lessThanOrEqualTo(6));
      expect(maxGroupSession(later), greaterThan(6));
      expect(maxGroupSession(later), lessThanOrEqualTo(10));
    });

    test('repeat pins: library pins are budgeted, a custom pin keeps its sets', () async {
      const customKey = 'custom_exercise_golden-band-row';
      await HiveService.instance.customBox.put(customKey, {
        'type': 'exercise',
        'name': customPinName,
        'equipment_needed': <String>[],
        'primary_muscles': ['Lats'],
        'movement_pattern': ['horizontal_pull'],
        'logging_type': 'weight_reps',
      });
      try {
        final prior = namesByDay(gen());
        final day0 = prior[0]!;
        prior[0] = (a: [...day0.a, customPinName], b: day0.b);
        final pinnedLibrary = day0.a.length;

        final off = gen(phase: 2, pins: prior);
        final offCustom = off.weekPlans[0].workoutDays[0].exercises
            .firstWhere((e) => e.exerciseName == customPinName);
        expect(offCustom.sets, 4, reason: 'fixture: OFF re-sizes the custom to the base 4');

        await flagOn();
        final on = gen(phase: 2, pins: prior, sessionDuration: 30);
        final onDay = on.weekPlans[0].workoutDays[0].exercises;
        final onCustom = onDay.firstWhere((e) => e.exerciseName == customPinName);
        expect(onCustom.sets, 3); // its own, untouched
        expect(onCustom.customOrigin, 'repeat_pin');
        final library = onDay.where((e) => e.exerciseName != customPinName).length;
        expect(library, lessThan(pinnedLibrary), reason: '30 minutes trims the library pins');
        expect(library, greaterThanOrEqualTo(1));
      } finally {
        await HiveService.instance.customBox.delete(customKey);
      }
    });

    test('a thin day of an injured user: the top-up fills it before the allocator, which budgets the add', () async {
      await flagOn();
      final config = HiveService.instance.configBox;
      // Built with the top-up's kill-switch set, then without it. 30 minutes, a
      // beginner on a bodyweight tier with a wrist and a shoulder injury.
      List<String> day0(Phase p) =>
          [for (final e in p.weekPlans.first.workoutDays[0].exercises) e.exerciseName];
      await config.put('disable_thin_day_topup', true);
      final thin = gen(
          tier: 'bodyweight',
          level: 'beginner',
          days: 5,
          injuries: ['wrist', 'shoulder'],
          sessionDuration: 30);
      expect(thin.weekPlans.first.workoutDays.every((d) => d.exercises.isNotEmpty), isTrue);
      expect(day0(thin).length, 2, reason: 'fixture: the thin day, without the top-up');

      await config.delete('disable_thin_day_topup');
      final filled = gen(
          tier: 'bodyweight',
          level: 'beginner',
          days: 5,
          injuries: ['wrist', 'shoulder'],
          sessionDuration: 30);
      expect(day0(filled).length, 3);
      expect(day0(filled).toSet().containsAll(day0(thin)), isTrue);
      // The add is budgeted like any generated exercise: the day still fits 30 minutes.
      for (final w in filled.weekPlans) {
        expect(mainSeconds(w.workoutDays[0]), lessThanOrEqualTo(budgetSeconds(30) + 1e-6));
      }
    });
  });
}
