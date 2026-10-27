// B2 Task 5 (docs/plans/2026-10-22-session-set-budget.md): the production-path
// check of the EXTRA slots. Under the session set budget the volume filter keeps
// EVERY split slot (`keepAllSlots`), so the selector now has to fill slots beyond
// today's `targetCount`. They sit at the END of each day's priority order. This
// test fills them on both selection paths and counts the ones that do not resolve
// to a real exercise.
//
//  - OFF selection: the pure-Dart mirror of the cascade (`CascadeTracer`) over the
//    keep-all frames. A slot "fails" when it resolves at attempt 5 (the hardcoded
//    bodyweight pool) or not at all.
//  - ON selection: the REAL `ExerciseSelector.pickV4` with `enable_core_list_pool`
//    on and B1's `CoreListSelector.debugTrace` attached. A slot "fails" when its
//    source is `drop`.
//
// Every (goal x tier x days x level) at phase 1 (the foundational-only phase, the
// hardest for the pools): 4 x 4 x 4 x 3 = 192 combinations.
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/core_list_selector.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/exercise_selector.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/split_resolver.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/training_history_analyzer.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/volume_filter.dart';

import '../plan_generator/v4_diagnostic/cascade_tracer.dart';

const _goals = ['build_muscle', 'lose_fat', 'strength', 'general_fitness'];
const _tiers = ['bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym'];
const _levels = ['beginner', 'intermediate', 'advanced'];
const _days = [3, 4, 5, 6];

class _Count {
  int extra = 0;
  int failed = 0;
  final failedAt = <String, int>{};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;
  late List<Map<String, dynamic>> library;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('keep_all_slots');
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
    library = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    for (final r in library) {
      await exBox.put(r['id'] as String, r);
    }
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
    await HiveService.instance.configBox.put('enable_core_list_pool', true);
  });

  tearDownAll(() async {
    CoreListSelector.debugTrace = null;
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('extra slots on both selection paths (reported per tier)', () {
    final off = {for (final t in _tiers) t: _Count()};
    final on = {for (final t in _tiers) t: _Count()};
    var onCombos = 0;

    for (final goal in _goals) {
      for (final tier in _tiers) {
        for (final days in _days) {
          for (final level in _levels) {
            final split = SplitResolver.selectV4(goal, days, experienceLevel: level);
            final all = VolumeFilter.filterDays(split,
                experience: level, weekCharacter: 'baseline', keepAllSlots: true);
            final target = VolumeFilter.targetCount(level, days);

            // ── OFF: the cascade mirror, variant A, slots in priority order ──
            final picked = <String>{};
            for (final day in all) {
              for (var i = 0; i < day.slotsA.length; i++) {
                final trace = CascadeTracer.trace(
                  library,
                  slot: day.slotsA[i],
                  equipmentTier: tier,
                  effectiveExp: level,
                  phase: 1,
                  injuries: const [],
                  pickedNames: picked,
                  capability: TrainingHistoryAnalyzer.resolveCapability(
                      tier: tier, exclusions: const {}, flagEnabled: true),
                );
                final pick = trace.finalPick;
                if (pick != null) picked.add(pick.name);
                if (i < target) continue;
                final c = off[tier]!;
                c.extra++;
                final source = pick?.source;
                final good = source != null &&
                    source != CascadePickSource.universalPool &&
                    source != CascadePickSource.universalPoolPlaceholder &&
                    source != CascadePickSource.safelyOmitted;
                if (!good) {
                  c.failed++;
                  final k = '${source?.name ?? 'none'} ${day.slotsA[i].targetMuscle}/${day.slotsA[i].movementPattern}';
                  c.failedAt[k] = (c.failedAt[k] ?? 0) + 1;
                }
              }
            }

            // ── ON: the real selector, core-list pool, B1's trace attached ──
            final extras = Set<MuscleSlot>.identity();
            for (final day in all) {
              extras.addAll(day.slotsA.skip(target));
              extras.addAll((day.slotsB ?? const <MuscleSlot>[]).skip(target));
            }
            final trace = CoreListTrace();
            CoreListSelector.debugTrace = trace;
            try {
              ExerciseSelector.pickV4(
                slotDays: all,
                exerciseRepo: ExerciseRepository.instance,
                equipmentTier: tier,
                effectiveExp: level,
                phase: 1,
                goal: goal,
                applyInjurySubstitutePreference: true,
                capability: TrainingHistoryAnalyzer.resolveCapability(
                    tier: tier, exclusions: const {}, flagEnabled: true),
              );
            } finally {
              CoreListSelector.debugTrace = null;
            }
            onCombos++;
            for (final s in trace.slots) {
              if (!extras.contains(s.slot)) continue;
              final c = on[tier]!;
              c.extra++;
              if (s.source == 'drop') {
                c.failed++;
                final k = 'drop ${s.slot.targetMuscle}/${s.slot.movementPattern}';
                c.failedAt[k] = (c.failedAt[k] ?? 0) + 1;
              }
            }
          }
        }
      }
    }

    final buf = StringBuffer('\nKEEP-ALL-SLOTS extra-slot report ($onCombos combos, phase 1)\n');
    for (final path in [('OFF mirror', off), ('ON core-list', on)]) {
      buf.writeln('${path.$1}:');
      for (final t in _tiers) {
        final c = path.$2[t]!;
        buf.writeln('  $t: extra=${c.extra} failed=${c.failed} ${c.failedAt}');
      }
    }
    // ignore: avoid_print
    print(buf);

    expect(onCombos, 192);
    // Not vacuous: keep-all really produced slots beyond targetCount on both paths.
    for (final t in _tiers) {
      expect(off[t]!.extra, greaterThan(300), reason: 'OFF extras at $t');
      expect(on[t]!.extra, greaterThan(300), reason: 'ON extras at $t');
    }

    // Plan P2-9: an extra slot that falls to the hardcoded bodyweight pool (or to
    // nothing) on a GYM tier is a finding. There are none.
    expect(off['basic_gym']!.failed, 0, reason: '${off['basic_gym']!.failedAt}');
    expect(off['full_gym']!.failed, 0, reason: '${off['full_gym']!.failedAt}');

    // The ratchet, measured 2026-10-25 over the shipped library. The bodyweight and
    // home tiers have thin chest pools at phase 1, so a few extra Lower/Mid Chest
    // slots resolve to a bodyweight pool exercise (a real exercise, not a gap) or to
    // nothing; the core-list pool drops its thinnest slot types. A dropped slot
    // shortens that day's list; the allocator sizes whatever the selector returned.
    // A count above its ceiling, or a new slot type in the gym tiers, wants a look.
    const offCeiling = {'bodyweight': 10, 'home_dumbbells': 6, 'basic_gym': 0, 'full_gym': 0};
    const onCeiling = {'bodyweight': 123, 'home_dumbbells': 69, 'basic_gym': 36, 'full_gym': 34};
    for (final t in _tiers) {
      expect(off[t]!.failed, lessThanOrEqualTo(offCeiling[t]!), reason: 'OFF $t');
      expect(on[t]!.failed, lessThanOrEqualTo(onCeiling[t]!), reason: 'ON $t');
    }
    const gymDropTypes = {'drop Hip/hip_isolation', 'drop Lateral Delts/shoulder_isolation'};
    for (final t in ['basic_gym', 'full_gym']) {
      expect(gymDropTypes.containsAll(on[t]!.failedAt.keys), isTrue,
          reason: 'ON $t drops a new slot type: ${on[t]!.failedAt}');
    }
  });
}
