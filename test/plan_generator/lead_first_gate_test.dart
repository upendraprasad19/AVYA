// Unit 2A (docs/plans/2026-11-12-generator-step2-allocator.md, OI-486, founder d26-d29): the whole-engine assertion for
// the lead-first allocator. Every one of the 1,010 golden personas runs the REAL PlanGenerator.instance.generateV4 with
// the rule ON (the default) and with the kill switch set, and:
//
//  1. in every week and day of the ON plan, no budgeted row other than the day's lead holds the lead's sets + 2 or more.
//     The lead is `SequencingEngine.openerOf` over the day's BUDGETED rows (a hold is never the lead nor a row
//     compared). No exception: a day a hold opens is checked like any other (the personas carry no body focus, so no
//     row is exempt). A restated budgeted test, independent of the allocator: a library row, not a custom, not logged
//     timed / cardio / distance (`SessionBudget.isBudgeted`'s rule);
//  2. the day's first exercise equals the OFF plan's whenever the OFF plan's first exercise is still in the ON day
//     (the sequencer is unchanged, so 2A never reorders a day's opener);
//  3. the worlds the allocator kept (`AllocationStats.leadWorld`, variants A and B) are pinned EXACTLY, so a wrong
//     world choice reddens here even where the plan output happens to agree.
//
// It fails on a wrong build; the 2,304-plan audit's numbers are a measurement (plan section 3).
@Timeout(Duration(minutes: 15))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/sequencing_engine.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_set_allocator.dart';

import '../helpers/generator_golden_personas.dart';

/// The worlds kept over the 1,010 golden personas (measured on the 2A tree, 2026-11-13): no variant falls back to main
/// (A: 1,010 plans; B: the 770 that are not 6-day). Re-measured on the Unit 2C-a tree (2026-11-14): A:lead 944 -> 959,
/// A:capped 66 -> 51. The 15 personas that move (traced, capped -> lead) are build_muscle 4 / 5-day at the default 60
/// minutes; 7 of them are 4-day beginner Full Body plans, whose lists 2C-a does not change, so the credit rule (a
/// quad-first row no longer spends the Glutes cap) is what lets their uncapped lead world hold. B is unchanged.
const _worldCounts = <String, int>{'A:lead': 959, 'A:capped': 51, 'B:lead': 768, 'B:capped': 2};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;
  late Set<String> libraryNames;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('lead_first_gate');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    final exBox = await Hive.openBox(HiveService.exerciseBoxName);
    final rows = jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List;
    for (final r in rows.whereType<Map>()) {
      await exBox.put((r['id'] ?? r['name']).toString(), Map<String, dynamic>.from(r));
    }
    libraryNames = {for (final r in rows.whereType<Map>()) '${r['name']}'.toLowerCase()};
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
  });

  tearDownAll(() async {
    await HiveService.instance.configBox.delete('disable_lead_first');
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  bool budgeted(PlannedExercise e) =>
      e.customOrigin == null &&
      !const {'timed', 'cardio', 'distance'}.contains(e.loggingType) &&
      libraryNames.contains(e.exerciseName.toLowerCase());

  test('1,010 golden personas: no row at the lead + 2, the opener unchanged, the kept worlds pinned', () async {
    final personas = generatorGoldenPersonas();
    expect(personas, hasLength(1010));
    final config = HiveService.instance.configBox;

    await config.put('disable_lead_first', true);
    final offFirst = <String, List<List<String>>>{};
    for (final p in personas) {
      offFirst[p.key] = [
        for (final w in p.run().weekPlans)
          for (final d in w.workoutDays) [for (final e in d.exercises) e.exerciseName],
      ];
    }
    await config.delete('disable_lead_first');

    final overLead = <String>[];
    final openerMoved = <String>[];
    final worlds = <String, int>{};
    var daysChecked = 0;
    var holdOpened = 0;
    for (final p in personas) {
      SessionSetAllocator.debugLastStats = null;
      final plan = p.run();
      for (final e in SessionSetAllocator.debugLastStats!.entries) {
        final k = '${e.key}:${e.value.leadWorld}';
        worlds[k] = (worlds[k] ?? 0) + 1;
      }
      final off = offFirst[p.key]!;
      var i = 0;
      for (var w = 0; w < plan.weekPlans.length; w++) {
        for (final d in plan.weekPlans[w].workoutDays) {
          final names = [for (final e in d.exercises) e.exerciseName];
          final offNames = off[i++];
          if (offNames.isNotEmpty && names.contains(offNames.first) && names.first != offNames.first) {
            openerMoved.add('${p.key} week ${w + 1} ${d.name}: ${offNames.first} -> ${names.first}');
          }
          final rows = d.exercises.where(budgeted).toList();
          if (rows.isEmpty) continue;
          daysChecked++;
          if (!budgeted(d.exercises.first)) holdOpened++;
          final lead = SequencingEngine.openerOf(rows)!;
          for (final r in rows) {
            if (!identical(r, lead) && r.sets >= lead.sets + 2) {
              overLead.add('${p.key} week ${w + 1} ${d.name}: ${r.exerciseName} ${r.sets} vs lead ${lead.exerciseName} ${lead.sets}');
            }
          }
        }
      }
      expect(i, off.length, reason: '${p.key}: the ON and OFF plans hold the same days');
    }
    // ignore: avoid_print
    print('lead-first gate: $daysChecked day-weeks checked, $holdOpened opened by a not-budgeted row; worlds $worlds');
    // Measured 2026-11-13: 18,080 day-weeks with a budgeted row, 718 of them opened by a not-budgeted row.
    expect(daysChecked, greaterThan(15000), reason: 'the gate must read the personas\' days');
    expect(holdOpened, greaterThan(0), reason: 'hold-opened days are in the set the gate reads');
    expect(overLead, isEmpty, reason: '${overLead.length} rows at the lead + 2; first: ${overLead.take(5)}');
    expect(openerMoved, isEmpty, reason: '${openerMoved.length} openers moved; first: ${openerMoved.take(5)}');
    expect(worlds, _worldCounts);
  });
}
