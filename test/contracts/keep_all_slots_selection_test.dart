// B2 Task 5 (docs/plans/2026-10-22-session-set-budget.md): the production-path
// check of the EXTRA slots. The volume filter keeps EVERY split slot (flipped
// ON 2026-11-02), so the selector has to fill slots beyond the old fixed
// `targetCount` (a table deleted with the flip, copied below as `_oldTargetCount`). They sit at the END of each day's priority order. This
// test fills them on both selection paths and counts the ones that do not resolve
// to a real exercise.
//
// The REAL `ExerciseSelector.pickV4` (the core-list pool) with B1's
// `CoreListSelector.debugTrace` attached. A slot "fails" when its source is `drop`.
// Unit 1B-F deleted the cascade, its mirror (`CascadeTracer`) and this test's OFF
// half with them.
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

/// The deleted `VolumeFilter.targetCount` table (flip 2026-11-02), kept HERE only
/// to name which slots are "extra": the ones the old fixed-count day never filled.
/// The selector must still resolve them to real exercises now that every slot is
/// kept, so this test still counts failures over exactly those slots.
int _oldTargetCount(String experience, int daysPerWeek) {
  if (experience == 'beginner') {
    if (daysPerWeek <= 3) return 6;
    if (daysPerWeek == 4) return 5;
    return 4;
  }
  if (experience == 'intermediate') {
    if (daysPerWeek <= 3) return 8;
    if (daysPerWeek == 4) return 7;
    return 6;
  }
  if (daysPerWeek <= 3) return 10;
  if (daysPerWeek == 4) return 9;
  return 8;
}

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

  test('extra slots on the core-list path (reported per tier)', () {
    final on = {for (final t in _tiers) t: _Count()};
    var onCombos = 0;

    for (final goal in _goals) {
      for (final tier in _tiers) {
        for (final days in _days) {
          for (final level in _levels) {
            final split = SplitResolver.selectV4(goal, days, experienceLevel: level);
            final all =
                VolumeFilter.filterDays(split, weekCharacter: 'baseline');
            final target = _oldTargetCount(level, days);

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
    for (final path in [('core-list', on)]) {
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
      expect(on[t]!.extra, greaterThan(300), reason: 'ON extras at $t');
    }

    // The ratchet, measured 2026-10-25 over the shipped library: the core-list pool
    // drops its thinnest slot types. A dropped slot
    // shortens that day's list; the allocator sizes whatever the selector returned.
    // A count above its ceiling, or a new slot type in the gym tiers, wants a look.
    // Re-measured 2026-11-11 (Unit 1B-F, the flipped tree): 19 / 6 / 0 / 0, down from the
    // 123 / 69 / 36 / 34 recorded on 2026-10-25 (the core lists have grown since); tightened.
    const onCeiling = {'bodyweight': 19, 'home_dumbbells': 6, 'basic_gym': 0, 'full_gym': 0};
    for (final t in _tiers) {
      expect(on[t]!.failed, lessThanOrEqualTo(onCeiling[t]!), reason: 'ON $t');
    }
    const gymDropTypes = {'drop Hip/hip_isolation', 'drop Lateral Delts/shoulder_isolation'};
    for (final t in ['basic_gym', 'full_gym']) {
      expect(gymDropTypes.containsAll(on[t]!.failedAt.keys), isTrue,
          reason: 'ON $t drops a new slot type: ${on[t]!.failedAt}');
    }
  });
}
