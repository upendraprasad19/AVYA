@Timeout(Duration(minutes: 120))
library;

// Unit 1B-F, Ruling 5 (docs/plans/2026-11-10-generator-1bf-flip.md, Task 4): the focus grid, the only whole-grid check
// of the allocator's guard (e) (a hold crediting a focus group gives way only to a slot that brings a major group).
// Skipped unless FOCUS_GRID_OUT names a directory (CI never runs it); Task 5 runs it on the final tree and compares the
// dump with prototype H3's byte for byte (the closure records both sha256).
//
//   FOCUS_GRID_OUT=/abs/dir TZ=Asia/Kolkata flutter test test/plan_generator/focus_grid_dump_test.dart
//
// Five focus sets x 4 goals x 3-6 days x 3 levels x 4 tiers x {30, 45} minutes x phases 1-3 = 5,760 uninjured plans, one
// line per day of every week: focus|goal|days|level|tier|minutes|phase|w<week>|<day index>|<day name>|name:sets;...

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';

import '../helpers/injury_floor_sweep_lib.dart';

const kFocusGridSets = ['core', 'chest', 'glutes,quads,hamstrings,calves', 'chest,shoulders,triceps,biceps', 'biceps'];

void main() {
  SweepHarness.install();
  final outDir = Platform.environment['FOCUS_GRID_OUT'];
  test('focus grid dump (5,760 plans)', () {
    final out = File('$outDir/focus_grid_dump.txt').openSync(mode: FileMode.write);
    var plans = 0;
    for (final focus in kFocusGridSets) {
      for (final goal in kSweepGoals) {
        for (final days in const [3, 4, 5, 6]) {
          for (final level in kSweepLevels) {
            for (final tier in kSweepTiers) {
              for (final minutes in const [30, 45]) {
                for (final phase in const [1, 2, 3]) {
                  final p = PlanGenerator.instance.generateV4(goal: goal, equipment: tier, daysPerWeek: days, phase: phase,
                      experienceLevel: level, injuries: const [], bodyFocus: focus.split(','), sessionDuration: minutes,
                      previousWeights: const {});
                  plans++;
                  for (var w = 0; w < p.weekPlans.length; w++) {
                    final ds = p.weekPlans[w].workoutDays;
                    for (var i = 0; i < ds.length; i++) {
                      out.writeStringSync('$focus|$goal|$days|$level|$tier|$minutes|$phase|w${w + 1}|$i|${ds[i].name}|'
                          '${ds[i].exercises.map((e) => '${e.exerciseName}:${e.sets}').join(';')}\n');
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    out.closeSync();
    expect(plans, 5760);
  }, skip: outDir == null ? 'set FOCUS_GRID_OUT to run the focus grid dump' : false);
}
