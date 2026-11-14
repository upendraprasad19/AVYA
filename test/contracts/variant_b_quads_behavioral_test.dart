// Generator Unit 1B-Q (OI-475 L1, founder decision d13, plan docs/plans/2026-11-10-generator-1bq-variant-b-quads.md):
// the B leg day of the 3, 4 and 5-day splits carries a Quads / knee_dominant / compound slot at priority 1, second
// after the Hamstrings hinge, so week 2 (variant B) holds quad work with the core-list pool too; its Glutes
// isolation slot sits behind the Calves slot (4-day: and Core) so Calves and Core keep their B-week sets.
//
// Before: B was the posterior variant with the Quads compound at priority 3 in sixth place (3-day) or no Quads
// compound at all (4 and 5-day), so the allocator never seated quad work at 30 to 60 minutes. The live picker hid it
// by putting a quad-crediting row into a non-quad slot; the core-list pool (Unit 1B-F) picks each slot's own row and
// showed 184 plans of the 2,304-plan audit with no Quads in week 2 that their live twin had. Unit 1B-F deleted the live
// (cascade) world and its tests here; the core-list tests below discriminate, with the shape tests.
//
// The set counts below read the BUILT plan with a restated reader (the library row's primary_muscles), never the
// allocator's ledger or BudgetMuscleGroups.
@Timeout(Duration(minutes: 8))
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
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/split_resolver.dart';

/// The splits whose B leg day this unit changed, with the B slot count (unchanged by the unit).
const _changed = <(String, int), int>{
  ('build_muscle', 3): 10,
  ('strength', 3): 10,
  ('build_muscle', 4): 9,
  ('build_muscle', 5): 8,
};

typedef _S = (String, String, String, int);

/// The pre-1B-Q B leg day lists, restated slot by slot (target, pattern, type, priority) from main cc8286ad, for the
/// kill-switch `disable_variant_b_quad`. The 3-day list serves build_muscle and strength.
const List<_S> _old3 = [
  ('Hamstrings', 'hip_dominant', 'compound', 1), ('Glutes', 'hip_dominant', 'compound', 1),
  ('Glutes', 'hip_isolation', 'isolation', 2), ('Hamstrings', 'knee_dominant', 'isolation', 2),
  ('Calves', 'knee_dominant', 'isolation', 3), ('Quads', 'knee_dominant', 'compound', 3),
  ('Quads', 'knee_dominant', 'isolation', 4), ('Hip', 'hip_isolation', 'isolation', 4),
  ('Core', 'core', 'isolation', 5), ('Calves', 'knee_dominant', 'isolation', 5),
];
const List<_S> _old4 = [
  ('Hamstrings', 'hip_dominant', 'compound', 1), ('Glutes', 'hip_dominant', 'compound', 1),
  ('Glutes', 'hip_isolation', 'isolation', 2), ('Hamstrings', 'knee_dominant', 'isolation', 2),
  ('Calves', 'knee_dominant', 'isolation', 3), ('Core', 'core', 'isolation', 3),
  ('Quads', 'knee_dominant', 'isolation', 4), ('Hip', 'hip_isolation', 'isolation', 4),
  ('Calves', 'knee_dominant', 'isolation', 5),
];
const List<_S> _old5 = [
  ('Hamstrings', 'hip_dominant', 'compound', 1), ('Glutes', 'hip_dominant', 'compound', 1),
  ('Glutes', 'hip_isolation', 'isolation', 2), ('Hamstrings', 'knee_dominant', 'isolation', 2),
  ('Calves', 'knee_dominant', 'isolation', 3), ('Quads', 'knee_dominant', 'isolation', 3),
  ('Hip', 'hip_isolation', 'isolation', 4), ('Core', 'core', 'isolation', 4),
];
const _oldB = <(String, int), List<_S>>{
  ('build_muscle', 3): _old3,
  ('strength', 3): _old3,
  ('build_muscle', 4): _old4,
  ('build_muscle', 5): _old5,
};

List<_S> _shape(List<MuscleSlot> l) =>
    [for (final x in l) (x.targetMuscle, x.movementPattern, x.exerciseType, x.priority)];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;
  late Map<String, Map<String, dynamic>> byName;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('variant_b_quads');
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
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  List<String> primary(String name) =>
      [for (final m in (byName[name.toLowerCase()]?['primary_muscles'] as List? ?? const [])) '$m'];

  /// Sets in [week] (0-based) on exercises whose library row lists Quads as a primary muscle. Exact spelling only
  /// (`Quads (eccentric)` is not counted), so it is stricter than [setsOf].
  int quadSets(Phase p, int week) {
    var n = 0;
    for (final d in p.weekPlans[week].workoutDays) {
      for (final e in d.exercises) {
        if (primary(e.exerciseName).contains('Quads')) n += e.sets;
      }
    }
    return n;
  }

  /// Sets in [week] (0-based) on exercises whose library row lists Hamstrings as a primary muscle.
  int hamSets(Phase p, int week) {
    var n = 0;
    for (final d in p.weekPlans[week].workoutDays) {
      for (final e in d.exercises) {
        if (primary(e.exerciseName).contains('Hamstrings')) n += e.sets;
      }
    }
    return n;
  }

  /// Sets in [week] (0-based) on exercises whose library row lists any of [muscles] as primary: case-insensitive,
  /// the bare name or the name with a qualifier (the library spells `Calves (Gastrocnemius)`).
  int setsOf(Phase p, int week, Set<String> muscles) {
    bool hit(String m) {
      final l = m.toLowerCase();
      return muscles.any((t) => l == t || l.startsWith('$t ('));
    }

    var n = 0;
    for (final d in p.weekPlans[week].workoutDays) {
      for (final e in d.exercises) {
        if (primary(e.exerciseName).any(hit)) n += e.sets;
      }
    }
    return n;
  }

  Phase gen(String goal, String tier, int days, int minutes, {String level = 'intermediate', int phase = 1}) =>
      PlanGenerator.instance.generateV4(
        goal: goal,
        equipment: tier,
        daysPerWeek: days,
        phase: phase,
        experienceLevel: level,
        injuries: const [],
        sessionDuration: minutes,
        previousWeights: const {},
      );

  group('the split', () {
    for (final e in _changed.entries) {
      final (goal, days) = e.key;
      test('$goal ${days}d: the B leg day leads with the hinge, then a priority-1 Quads compound', () {
        final legs = SplitResolver.selectV4(goal, days).where((d) => d.dayType == 'legs' && d.slotsB != null).toList();
        expect(legs, hasLength(1), reason: 'one Legs day with a B variant');
        final b = legs.single.slotsB!;
        expect(b, hasLength(e.value), reason: 'the unit moves a slot; it adds none');
        expect([b[0].targetMuscle, b[0].movementPattern, b[0].exerciseType], ['Hamstrings', 'hip_dominant', 'compound'],
            reason: 'B keeps its posterior lead');
        expect([b[1].targetMuscle, b[1].movementPattern, b[1].exerciseType, b[1].priority],
            ['Quads', 'knee_dominant', 'compound', 1]);
        expect(b.where((s) => s.targetMuscle == 'Quads' && s.exerciseType == 'compound'), hasLength(1),
            reason: 'exactly one Quads compound on B');
        // Round 2 (2026-11-10): the Glutes isolation slot sits BEHIND the Calves slot (and, on the 4-day, the Core
        // slot). Directly after the hinges it pushed Calves / Core past the count band: 51 live plans lost all week-2
        // Calves and 12 all week-2 Core. Both hinge rows still credit Glutes.
        int at(bool Function(MuscleSlot) f) => b.indexWhere(f);
        final glutesIso = at((s) => s.targetMuscle == 'Glutes' && s.movementPattern == 'hip_isolation');
        final calves = at((s) => s.targetMuscle == 'Calves' && s.subFocus == null);
        final core = at((s) => s.targetMuscle == 'Core');
        expect(glutesIso, greaterThan(-1));
        expect(calves, inInclusiveRange(0, glutesIso - 1), reason: 'Calves before the Glutes isolation slot');
        if (days == 4) expect(core, inInclusiveRange(0, glutesIso - 1), reason: 'Core before the Glutes isolation slot');
        expect(b[2].targetMuscle == 'Glutes' && b[2].movementPattern == 'hip_dominant', isTrue,
            reason: 'the Glutes hinge stays third');
      });
    }

    for (final e in _oldB.entries) {
      final (goal, days) = e.key;
      test('$goal ${days}d: kill-switch OFF (variantBQuad: false) restores the pre-1B-Q B list exactly; A unchanged', () {
        List<MuscleSlotDay> legs(bool on) => SplitResolver.selectV4(goal, days, variantBQuad: on)
            .where((d) => d.dayType == 'legs' && d.slotsB != null)
            .toList();
        expect(_shape(legs(false).single.slotsB!), e.value);
        expect(_shape(legs(false).single.slotsA), _shape(legs(true).single.slotsA), reason: 'A is not touched');
        expect(_shape(legs(true).single.slotsB!), isNot(e.value));
      });
    }

    test('the 6-day split is not touched by this unit (OI-454 owns its Legs B)', () {
      final legsB = SplitResolver.selectV4('build_muscle', 6).firstWhere((d) => d.name == 'Legs B');
      expect(legsB.slotsB, isNull);
    });
  });

  group('kill switch disable_variant_b_quad (platform tier, default ON)', () {
    tearDown(() async => HiveService.instance.configBox.delete('disable_variant_b_quad'));

    test('unset: ON; set true: selectV4 and generateV4 build the pre-1B-Q B leg day', () async {
      expect(PlanEngineFlags.variantBQuadEnabled, isTrue);
      await HiveService.instance.configBox.put('disable_variant_b_quad', true);
      expect(PlanEngineFlags.variantBQuadEnabled, isFalse);
      final legs = SplitResolver.selectV4('build_muscle', 4).firstWhere((d) => d.dayType == 'legs');
      expect(_shape(legs.slotsB!), _old4, reason: 'selectV4 reads the flag when no override is passed');
      // Unit 2C-a: 45 minutes, where today's 4-day list (and the B leg day this switch governs) still serves; at 60+ the
      // balanced week has no `Legs` day.
      String legsB() => jsonEncode(gen('build_muscle', 'full_gym', 4, 45)
          .weekPlans[1]
          .workoutDays
          .firstWhere((d) => d.name == 'Legs')
          .exercises
          .map((e) => e.exerciseName)
          .toList());
      final off = legsB();
      await HiveService.instance.configBox.delete('disable_variant_b_quad');
      expect(off, isNot(legsB()), reason: 'generateV4 honours the switch (the 998-persona golden with the switch set '
          'equals main cc8286ad byte for byte: diagnose cf970c)');
    });
  });

  group('core-list pool ON', () {

    for (final days in [3, 4, 5]) {
      for (final tier in ['bodyweight', 'full_gym']) {
        // Unit 2C-a: 30 and 45 minutes run today's lists (the 1B-Q B leg day); 60 runs the balanced week, which must
        // keep quad and hamstring work in weeks 2 and 4 too (it has no `Legs` day at 3 and 4 days).
        for (final minutes in [30, 45, 60]) {
          test('build_muscle ${days}d $tier $minutes min: week 2 (variant B) holds quad sets', () {
            final p = gen('build_muscle', tier, days, minutes);
            expect(quadSets(p, 1), greaterThan(0), reason: 'week 2 lost all quad work');
            expect(p.weekPlans[3].weekCharacter, 'deload');
            expect(quadSets(p, 3), greaterThan(0), reason: 'week 4 (deload, variant B) lost all quad work');
            expect(hamSets(p, 1), greaterThan(0), reason: 'week 2 lost all hamstring work');
            if (minutes < 60) {
              final legs2 = p.weekPlans[1].workoutDays.firstWhere((d) => d.name == 'Legs');
              expect(legs2.exercises.any((e) => primary(e.exerciseName).firstOrNull == 'Hamstrings'), isTrue,
                  reason: 'B keeps a hamstring-first row (the posterior mirror)');
            }
          });
        }
      }
    }

    // The eight audit personas (goal|days|level|tier|minutes|phase) that measured the order: with the Quads compound
    // THIRD (after both hinges) the core-list pool left week 2 without quads, because the Glutes session cap refused
    // the quad row after the hinge and the bridge. Second is what holds them.
    for (final k in const [
      'build_muscle|3|advanced|bodyweight|30|2',
      'build_muscle|3|advanced|bodyweight|30|3',
      'build_muscle|4|advanced|bodyweight|30|2',
      'build_muscle|4|advanced|bodyweight|30|3',
      'build_muscle|5|advanced|bodyweight|30|2',
      'build_muscle|5|advanced|bodyweight|30|3',
      'strength|3|advanced|bodyweight|30|1',
      'strength|3|advanced|home_dumbbells|30|1',
    ]) {
      test('$k: week 2 holds quad sets', () {
        final f = k.split('|');
        final p = gen(f[0], f[3], int.parse(f[1]), int.parse(f[4]), level: f[2], phase: int.parse(f[5]));
        expect(quadSets(p, 1), greaterThan(0));
      });
    }

    // Round 2: personas that measured week 2 AND week 4 with no Calves / no Core set when the Glutes isolation slot
    // sat fourth (audit, live and pool ON). Each must hold that muscle in both B weeks. These guard the Glutes slot's
    // position; they do not detect a no-op on the deleted live world (6 of the 7 already held the muscle there).
    for (final (k, muscles) in const [
      ('strength|3|intermediate|basic_gym|45|1', {'calves'}),
      ('strength|3|intermediate|bodyweight|60|2', {'calves'}),
      ('build_muscle|3|intermediate|full_gym|60|1', {'calves'}),
      ('build_muscle|3|advanced|bodyweight|45|2', {'calves'}),
      ('build_muscle|5|advanced|bodyweight|45|2', {'calves'}),
      ('build_muscle|4|intermediate|basic_gym|60|1', {'core', 'abs', 'obliques'}),
      ('build_muscle|4|intermediate|full_gym|45|2', {'core', 'abs', 'obliques'}),
    ]) {
      test('$k: weeks 2 and 4 hold ${muscles.first} sets', () {
        final f = k.split('|');
        final p = gen(f[0], f[3], int.parse(f[1]), int.parse(f[4]), level: f[2], phase: int.parse(f[5]));
        expect(setsOf(p, 1, muscles), greaterThan(0), reason: 'week 2: ${[for (final d in p.weekPlans[1].workoutDays) '${d.name}: ${d.exercises.map((e) => '${e.exerciseName} ${e.sets}').join(', ')}']}');
        expect(setsOf(p, 3, muscles), greaterThan(0), reason: 'week 4');
      });
    }

    test('strength 3d full_gym 60 min: week 2 holds quad sets', () {
      expect(quadSets(gen('strength', 'full_gym', 3, 60), 1), greaterThan(0));
    });
  });
}
