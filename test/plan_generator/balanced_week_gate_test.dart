// Unit 2C-a (OI-475 L2 / L3; plan docs/plans/2026-11-14-generator-step2c-balanced-week.md v6, sections 4A and 5A): the
// whole-engine gate for the balanced build_muscle week. The real PlanGenerator.instance.generateV4 runs the audit grid's
// build_muscle part at 60 and 90 minutes (3 / 4 / 5 / 6 days x 3 levels x 4 tiers x phases 1-3: 288 plans, no injuries,
// no history), the counts the plan measured on the 2,304-plan audit (section 4A.2) are pinned, and the same grid with the
// kill switch `disable_balanced_week` set must equal the tree before 2C (HEAD c6b1ee48's generator) byte for byte.
//
//  1. Quads plan-weeks under the weekly band bottom (weeks 1-3; an exercise counts when its library row's primary
//     muscles map to Quads), per (days, level, minutes): EXACTLY section 4A.2's table.
//  2. No build_muscle 4 / 5-day plan has week 2 equal to week 1 (every day's names in order), except the 4-day
//     beginner's Full Body plans in phases 1-2 (16, as before 2C).
//  3. Repeated names in week 1 (non-beginner; a name used on n days counts n - 1), per day count: at or under 4A.2's
//     0 / 48 / 102 for 3 / 4 / 5 days (a better split may lower them; a lost avoid raises them).
//  4. OFF (the switch set): the digest of every plan's phase map equals the pre-2C tree's. The 1,010-persona golden
//     (`balanced_week_kill_switch_golden_test.dart`) holds no 90-minute plan, so this grid is the OFF proof at 90.
//
// Mutations run against it (diagnose c7e5a1), each red: the 60-minute bound `>=` -> `>`, VolumeFilter dropping
// `avoidEarlier`, `all` read as `sameType`, the predicate ignoring the switch, the flag getter always ON. A swap of two arm
// slots in Upper A stays green here (no Quads or repeat change); the behavioral test's list pins catch it.
@Timeout(Duration(minutes: 20))
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

import '../../scripts/migration_ledger_hash_lib.dart' show sha256Hex;

const _levels = ['beginner', 'intermediate', 'advanced'];
const _tiers = ['bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym'];

/// Section 4A.2: Quads plan-weeks under the bottom (of 36 per cell), keyed `days|level|minutes`.
const _quadsUnder = <String, int>{
  '3|beginner|60': 12, '3|intermediate|60': 36, '3|advanced|60': 36,
  '4|beginner|60': 2, '4|intermediate|60': 6, '4|advanced|60': 36,
  '5|beginner|60': 12, '5|intermediate|60': 36, '5|advanced|60': 36,
  '6|beginner|60': 12, '6|intermediate|60': 36, '6|advanced|60': 36,
  '3|beginner|90': 2, '3|intermediate|90': 4, '3|advanced|90': 36,
  '4|beginner|90': 0, '4|intermediate|90': 0, '4|advanced|90': 0,
  '5|beginner|90': 2, '5|intermediate|90': 4, '5|advanced|90': 36,
  '6|beginner|90': 0, '6|intermediate|90': 0, '6|advanced|90': 36,
};

/// Section 4A.2: week-1 repeated names (non-beginner, 60 and 90 minutes), per day count.
const _repeatsAtMost = <int, int>{3: 0, 4: 48, 5: 102};

/// The OFF grid's digest on the tree before 2C (HEAD c6b1ee48, the switch key unread there), recorded 2026-11-14.
const _offDigest = '8d2554d169175c89fe0c2ebcf5d4cfca7a5717b3c8ed28bea8af9461efa98c7e';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;
  late Map<String, Map<String, dynamic>> byName;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('balanced_week_gate');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    final exBox = await Hive.openBox(HiveService.exerciseBoxName);
    final rows = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List)
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
    await HiveService.instance.configBox.delete('disable_balanced_week');
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Phase gen(int days, String level, String tier, int minutes, int phase) => PlanGenerator.instance.generateV4(
        goal: 'build_muscle',
        equipment: tier,
        daysPerWeek: days,
        phase: phase,
        experienceLevel: level,
        injuries: const [],
        sessionDuration: minutes,
        previousWeights: const {},
      );

  Iterable<(int, String, String, int, int)> grid() sync* {
    for (final days in [3, 4, 5, 6]) {
      for (final level in _levels) {
        for (final tier in _tiers) {
          for (final minutes in [60, 90]) {
            for (final phase in [1, 2, 3]) {
              yield (days, level, tier, minutes, phase);
            }
          }
        }
      }
    }
  }

  bool quadRow(String name) => BudgetMuscleGroups.of([
        for (final m in (byName[name.toLowerCase()]?['primary_muscles'] as List? ?? const [])) '$m',
      ]).contains('Quads');

  List<List<String>> weekNames(WeekPlan w) => [
        for (final d in w.workoutDays) [for (final e in d.exercises) e.exerciseName],
      ];

  test('ON: the Quads residue, week 2 never week 1, repeats bounded (288 build_muscle plans at 60 / 90)', () async {
    await HiveService.instance.configBox.delete('disable_balanced_week');
    final quads = <String, int>{for (final k in _quadsUnder.keys) k: 0};
    final weekTwoSame = <String>[];
    final repeats = <int, int>{3: 0, 4: 0, 5: 0, 6: 0};
    for (final (days, level, tier, minutes, phase) in grid()) {
      final plan = gen(days, level, tier, minutes, phase);
      final bottom = SessionBudget.weeklyBand('build_muscle', PlanGenerator.effectiveLevel(level, phase)).bottom;
      for (var w = 0; w < 3; w++) {
        var q = 0;
        for (final d in plan.weekPlans[w].workoutDays) {
          for (final e in d.exercises) {
            if (quadRow(e.exerciseName)) q += e.sets;
          }
        }
        if (q < bottom) quads['$days|$level|$minutes'] = quads['$days|$level|$minutes']! + 1;
      }
      final key = '$days|$level|$tier|$minutes|$phase';
      if ((days == 4 || days == 5) &&
          jsonEncode(weekNames(plan.weekPlans[0])) == jsonEncode(weekNames(plan.weekPlans[1]))) {
        weekTwoSame.add(key);
      }
      if (level != 'beginner') {
        final counts = <String, int>{};
        for (final d in plan.weekPlans[0].workoutDays) {
          for (final e in d.exercises) {
            counts[e.exerciseName] = (counts[e.exerciseName] ?? 0) + 1;
          }
        }
        repeats[days] = repeats[days]! + counts.values.fold(0, (s, c) => s + c - 1);
      }
    }
    // ignore: avoid_print
    print('balanced week gate: quads $quads; week 2 == week 1 ${weekTwoSame.length}; repeats $repeats');
    expect(quads, _quadsUnder);
    expect(weekTwoSame.toSet(), {
      for (final tier in _tiers)
        for (final minutes in [60, 90])
          for (final phase in [1, 2]) '4|beginner|$tier|$minutes|$phase',
    });
    for (final e in _repeatsAtMost.entries) {
      expect(repeats[e.key], lessThanOrEqualTo(e.value), reason: '${e.key}-day week-1 repeats');
    }
  });

  test('OFF: the switch set reproduces the pre-2C tree byte for byte', () async {
    await HiveService.instance.configBox.put('disable_balanced_week', true);
    try {
      final lines = <String>[];
      for (final (days, level, tier, minutes, phase) in grid()) {
        final plan = gen(days, level, tier, minutes, phase);
        lines.add('$days|$level|$tier|$minutes|$phase:${sha256Hex(utf8.encode(jsonEncode(plan.toMap())))}');
      }
      final digest = sha256Hex(utf8.encode(lines.join('\n')));
      // ignore: avoid_print
      print('balanced week gate OFF digest: $digest');
      expect(digest, _offDigest);
    } finally {
      await HiveService.instance.configBox.delete('disable_balanced_week');
    }
  });
}
