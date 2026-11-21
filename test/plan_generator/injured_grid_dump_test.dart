@Timeout(Duration(minutes: 300))
library;

// Unit 1B-F, Ruling 3 (docs/plans/2026-11-10-generator-1bf-flip.md, Task 4): the full measurement behind the CI hard
// test (test/plan_generator/r6_removed_runs_*_test.dart). Skipped unless INJURED_GRID_OUT names a directory (CI never runs
// it; about 3 hours). Task 5 runs it on the final tree; the closure records its table against the live baseline.
//
//   INJURED_GRID_OUT=/abs/dir TZ=Asia/Kolkata flutter test test/plan_generator/injured_grid_dump_test.dart
//
// The 19,584-run domain (the 15 pairs of the floor sweep's six injuries x 4 tiers x 4 goals x 3 levels x 3-6 days x
// phases 1-3 and the pinned repeat; every triple of the six on bodyweight; every pair of the 9 injuries x
// exclude-everything on bodyweight) plus the 26,928-run extension (the triples on home_dumbbells / basic_gym /
// full_gym; every pair holding ankle, neck or hamstring on those three tiers; every quad of the six on all 4 tiers; all
// 9 injuries on all 4 tiers): 46,512 runs, one line per day of weeks 1-2:
// block|tier|goal|level|days|phase|injuries|w<week>|<day index>|<day name>|<n>|name;...

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/equipment_vocab.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';

import '../helpers/generator_golden_personas.dart' show namesByDay;
import '../helpers/injury_floor_sweep_lib.dart';

List<List<String>> _combos(List<String> xs, int k) {
  if (k == 0) return [<String>[]];
  final out = <List<String>>[];
  for (var i = 0; i <= xs.length - k; i++) {
    for (final rest in _combos(xs.sublist(i + 1), k - 1)) {
      out.add([xs[i], ...rest]);
    }
  }
  return out;
}

void main() {
  final h = SweepHarness.install();
  final outDir = Platform.environment['INJURED_GRID_OUT'];
  test('injured grid dump (46,512 runs)', () {
    final out = File('$outDir/injured_grid_dump.txt').openSync(mode: FileMode.write);
    var runs = 0;
    void dump(String block, String tier, String goal, String level, int days, int phase, List<String> inj,
        {Map<int, ({List<String> a, List<String> b})>? pins, List<String> exclusions = const []}) {
      final Phase p = h.gen(tier: tier, goal: goal, level: level, days: days, phase: phase, injuries: inj, pins: pins,
          exclusions: exclusions);
      runs++;
      for (var w = 0; w < 2 && w < p.weekPlans.length; w++) {
        final ds = p.weekPlans[w].workoutDays;
        for (var i = 0; i < ds.length; i++) {
          out.writeStringSync('$block|$tier|$goal|$level|$days|$phase|${inj.join('+')}|w${w + 1}|$i|${ds[i].name}|'
              '${ds[i].exercises.length}|${ds[i].exercises.map((e) => e.exerciseName).join(';')}\n');
        }
      }
    }

    const p6 = kSweepPairInjuries;
    const p9 = kSweepInjuries;
    final pairs = _combos(p6, 2), triples = _combos(p6, 3), quads = _combos(p6, 4);
    final pairs9 = _combos(p9, 2);
    final pairsAnh = [for (final pr in pairs9) if (!(p6.contains(pr[0]) && p6.contains(pr[1]))) pr];
    final excludeAll = EquipmentVocab.tierItems['bodyweight']!;
    for (final goal in kSweepGoals) {
      for (final level in kSweepLevels) {
        for (final days in const [3, 4, 5, 6]) {
          for (final tier in kSweepTiers) {
            final pins = namesByDay(h.gen(tier: tier, goal: goal, level: level, days: days, phase: 1, injuries: const []));
            for (final pr in pairs) {
              for (final phase in const [1, 2, 3]) {
                dump('pairs', tier, goal, level, days, phase, pr);
              }
              dump('pairs_repeat', tier, goal, level, days, 2, pr, pins: pins);
            }
          }
          for (final phase in const [1, 2, 3]) {
            for (final tr in triples) {
              dump('triples', 'bodyweight', goal, level, days, phase, tr);
            }
            for (final pr in pairs9) {
              dump('pairs9_exclall', 'bodyweight', goal, level, days, phase, pr, exclusions: excludeAll);
            }
            for (final tier in const ['home_dumbbells', 'basic_gym', 'full_gym']) {
              for (final tr in triples) {
                dump('triples_eq', tier, goal, level, days, phase, tr);
              }
              for (final pr in pairsAnh) {
                dump('pairs_anh_eq', tier, goal, level, days, phase, pr);
              }
            }
            for (final tier in kSweepTiers) {
              for (final q in quads) {
                dump('quads_all', tier, goal, level, days, phase, q);
              }
              dump('all9_all', tier, goal, level, days, phase, p9.toList());
            }
          }
        }
      }
    }
    out.closeSync();
    expect(runs, 46512);
  }, skip: outDir == null ? 'set INJURED_GRID_OUT to run the injured grid dump' : false);
}
