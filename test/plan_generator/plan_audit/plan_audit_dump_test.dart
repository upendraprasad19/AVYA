// Generator step 1A, Task 1: the 2,304-plan suitability audit (the founder's
// "re-run the full review after each step"). Skipped unless PLAN_AUDIT_OUT names
// a directory, so CI never runs it:
//
//   PLAN_AUDIT_OUT=/abs/dir TZ=Asia/Kolkata flutter test \
//     test/plan_generator/plan_audit/plan_audit_dump_test.dart
//
// Grid: 4 goals x 3/4/5/6 days x 3 levels x 4 tiers x 30/45/60/90 min x phases
// 1-3; no injuries, no history. Focus: none, unless PLAN_AUDIT_FOCUS names a
// `physique_focus` token (`glutes_legs` | `chest_shoulders_arms`; t108, 2026-11-12):
// the grid then passes that token's muscles as `bodyFocus`, which is what
// TrainingHistoryAnalyzer.resolveBodyFocus returns for a profile holding it (no
// history, so weakMuscles() never applies). Keys are unchanged, so a focus run
// compares with the no-focus run key by key. Runs the real generateV4 once (one world
// since Unit 1B-F deleted the `enable_core_list_pool` flag and the cascade) and
// writes into PLAN_AUDIT_OUT:
//   plan_dump.jsonl   one line per plan (the shape plan_audit_lib reads; the last
//                     line is {"exercises": ...})
//   audit.json        per-plan verdict + issues
//   section1.md       the plan's section 1 table
// A before/after comparison runs this test on each tree into its own directory.
@Timeout(Duration(minutes: 120))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/constants/fitness_goals.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/budget_muscle_groups.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/split_resolver.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/training_history_analyzer.dart';

import 'plan_audit_lib.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  final outDir = Platform.environment['PLAN_AUDIT_OUT'];
  final focusToken = Platform.environment['PLAN_AUDIT_FOCUS'];
  final bodyFocus = TrainingHistoryAnalyzer.physiqueFocusToBodyFocus(focusToken);
  late Directory tempDir;
  late List<Map<String, dynamic>> rows;
  late Map<String, Map<String, dynamic>> byName, byId, byExactName;

  setUpAll(() async {
    if (outDir == null) return;
    tempDir = await Directory.systemTemp.createTemp('plan_audit');
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
    rows = (jsonDecode(
      File('assets/data/exercise_library.json').readAsStringSync(),
    ) as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    for (final r in rows) {
      await exBox.put((r['id'] ?? r['name']).toString(), r);
    }
    byName = {for (final r in rows) (r['name'] as String).toLowerCase(): r};
    byExactName = {for (final r in rows) r['name'] as String: r};
    byId = {for (final r in rows) (r['id'] ?? r['name']).toString(): r};
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
  });

  tearDownAll(() async {
    if (outDir == null) return;
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Map<String, dynamic> dumpOne(String goal, int days, String level, String tier,
      int minutes, int phase, Map<String, Map<String, dynamic>> exercises) {
    final plan = PlanGenerator.instance.generateV4(
      goal: goal,
      equipment: tier,
      daysPerWeek: days,
      phase: phase,
      experienceLevel: level,
      injuries: const [],
      bodyFocus: bodyFocus,
      sessionDuration: minutes,
      previousWeights: const {},
    );
    final planGoal = FitnessGoals.of(goal).planGoal;
    final effLevel = PlanGenerator.effectiveLevel(level, phase);
    // The audit's credit is the generator's own (Unit 2C-a, plan round 3 A-2: one rule for both sides of a comparison).
    final quadGlutes = SplitResolver.quadPrimaryCreditsGlutes(planGoal, days, minutes,
        quadLegsB: PlanEngineFlags.quadLegsBEnabled);
    final band = SessionBudget.weeklyBand(planGoal, effLevel);
    final weeks = <Map<String, dynamic>>[];
    for (final w in plan.weekPlans) {
      final dayList = <Map<String, dynamic>>[];
      final vol = <String, int>{};
      for (final d in w.workoutDays) {
        final exList = <List<Object?>>[];
        for (final e in d.exercises) {
          final row = byName[e.exerciseName.toLowerCase()];
          final tokens = [
            for (final m in (row?['primary_muscles'] as List? ??
                e.primaryMuscles ??
                const []))
              '$m'
          ];
          exercises.putIfAbsent(e.exerciseName, () => {
                'm': tokens,
                'lt': e.loggingType,
                'eq': row?['equipment_needed'] ?? e.equipmentNeeded ?? const [],
                't': e.exerciseType ?? row?['exercise_type'],
              });
          final groups = BudgetMuscleGroups.creditedOf(tokens,
              quadPrimaryCreditsGlutes: quadGlutes);
          for (final g in groups) {
            vol[g] = (vol[g] ?? 0) + e.sets;
          }
          // x[7], Unit 1B-F (OI-485 (3)): the BUILT type (after the picker's typeOverride), which SequencingEngine
          // orders by; the per-name header map above keeps one type per name.
          exList.add([e.exerciseName, e.sets, e.reps, e.restSeconds,
              e.durationSeconds, e.supersetGroup, groups.toList(), e.exerciseType]);
        }
        int? mins;
        try {
          mins = SessionBudget.estimateDayMinutesFromPlanDay(d.toMap(), byId,
              rowsByName: byName);
        } catch (_) {}
        dayList.add({'n': d.name, 'f': d.focus, 'x': exList, 'min': mins});
      }
      weeks.add({'c': w.weekCharacter, 'd': dayList, 'v': vol});
    }
    return {
      'k': '$goal|$days|$level|$tier|$minutes|$phase',
      'pn': plan.name,
      'pg': planGoal,
      'el': effLevel,
      'b': [band.bottom, band.top],
      // t108: the focus groups the budget raised to SessionBudget.focusWeeklyTop (written only with a focus, so a
      // no-focus dump stays byte-identical to earlier runs).
      if (bodyFocus.isNotEmpty) 'fg': (BudgetMuscleGroups.of(bodyFocus).toList()..sort()),
      'w': weeks,
    };
  }

  Future<AuditSummary> run() async {
    final auditor = PlanAuditor(byExactName);
    final dump = File('$outDir/plan_dump.jsonl').openSync(mode: FileMode.write);
    final exercises = <String, Map<String, dynamic>>{};
    final results = <PlanAuditResult>[];
    for (final goal in const ['build_muscle', 'lose_fat', 'general_fitness', 'strength']) {
      for (final days in const [3, 4, 5, 6]) {
        for (final level in const ['beginner', 'intermediate', 'advanced']) {
          for (final tier in const ['bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym']) {
            for (final minutes in const [30, 45, 60, 90]) {
              for (final phase in const [1, 2, 3]) {
                final p = dumpOne(goal, days, level, tier, minutes, phase, exercises);
                dump.writeStringSync('${jsonEncode(p)}\n');
                results.add(auditor.audit(p));
              }
            }
          }
        }
      }
    }
    dump.writeStringSync('${jsonEncode({'exercises': exercises})}\n');
    dump.closeSync();
    File('$outDir/audit.json').writeAsStringSync(jsonEncode({
      for (final r in results)
        r.key: {
          'v': r.verdict,
          'i': [for (final i in r.issues) [i.severity, i.code, i.text]],
        }
    }));
    return AuditSummary.of(results);
  }

  test('2,304-plan audit', () async {
    // A token that maps to no muscles would silently run the no-focus grid under a focus label.
    if (focusToken != null) expect(bodyFocus, isNotEmpty, reason: 'PLAN_AUDIT_FOCUS=$focusToken maps to no muscles');
    final s = await run();
    expect(s.plans, 2304);
    File('$outDir/section1.md').writeAsStringSync(
        '# Plan audit (2,304 plans, no injuries, no history, focus ${focusToken ?? 'none'})\n\n'
        '${sectionOneTable([('this tree', s)])}\n\n'
        'Codes: ${s.codes}\n');
  }, skip: outDir == null ? 'set PLAN_AUDIT_OUT to run the plan audit' : false);
}
