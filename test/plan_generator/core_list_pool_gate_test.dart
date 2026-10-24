// Batch B1 Task 4 — the ON-world gate for the core-list pool.
//
// Flag ON, the 998 golden personas, the REAL generateV4, provenance from
// CoreListSelector.debugTrace (written by production, read here). Hard counts
// below must be 0 over those 998 personas — and only those; the multi-injury
// sweep in the report is reported, not gated. The one carve-out: a retired row
// the thin-day top-up (OI-401, plan R9) adds for an injured user is recorded
// evidence, pinned in _r9TopUpRetired; B1's own picks and any skill row stay hard.
//
// Report (also runs the OFF comparison and the multi-injury sweep):
//   WRITE_CORE_LIST_REPORT=1 TZ=Asia/Kolkata flutter test test/plan_generator/core_list_pool_gate_test.dart
// → test/plan_generator/core_list_pool_report.md
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
import 'package:icanbefitter/core/utils/equipment_vocab.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/core_list_selector.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/equipment_capability.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';

import '../helpers/generator_golden_personas.dart';

const _reportPath = 'test/plan_generator/core_list_pool_report.md';
const _rank = {'beginner': 0, 'intermediate': 1, 'advanced': 2};
const _implementPatterns = {
  'elbow_flexion', 'elbow_extension', 'shoulder_isolation', 'horizontal_pull',
  'vertical_pull',
};
const _suitableDisagreeIds = {'E010', 'E020', 'E045', 'E134', 'E255'};

List<String> _strs(Object? v) =>
    v is List ? [for (final e in v) e.toString()] : const <String>[];

bool _retired(Map<String, dynamic> r) =>
    _strs(r['core_levels']).isEmpty && r['variant_family'] == null;

bool _skill(Map<String, dynamic> r) =>
    r['discipline'] == 'calisthenics_skill' || r['discipline'] == 'olympic';

/// Every main-lift id the phase actually serves, both variants, every week.
Iterable<String> builtIds(Phase p) => [
      for (final w in p.weekPlans)
        for (final d in w.workoutDays)
          for (final e in d.exercises) e.exerciseId
    ];

/// Rows B1 calls retired that the thin-day top-up (OI-401) adds for an injured
/// user, measured on the 998 golden personas (2026-10-24): the top-up reads the
/// OFF-path candidates, not the core list (plan R9). Whether a top-up under B1
/// should be core-list-only is the `enable_core_list_pool` flip review's
/// question (`docs/ship_dark_pending_review.yaml`). The set is a ratchet: a NEW
/// retired id appearing here fails the gate and wants a decision.
const _r9TopUpRetired = {'E234', 'E261', 'E271'};

/// Splits the built ids that are retired or skill rows into the hard failures
/// and the R9 evidence. [without] is the same persona's built ids with the
/// top-up kill-switch set: an id that is ALSO built without the top-up is B1's
/// own pick (or a leak) and stays hard; an id built ONLY with it ON is a top-up
/// addition, and only a RETIRED one is evidence, a skill/olympic row never is.
({List<String> hard, List<String> evidence}) classifyBuilt({
  required Iterable<String> built,
  required Set<String> without,
  required bool Function(String id) isRetired,
  required bool Function(String id) isSkill,
}) {
  final hard = <String>[], evidence = <String>[];
  for (final id in built) {
    if (!isRetired(id) && !isSkill(id)) continue;
    if (!without.contains(id) && !isSkill(id)) {
      evidence.add(id);
    } else {
      hard.add(id);
    }
  }
  return (hard: hard, evidence: evidence);
}

class _Persona {
  final String kind, tier, level;
  final int phase;
  final String? injury;
  final List<String> exclusions, owned;
  _Persona(String key)
      : kind = key.split('|')[0],
        tier = _field(key, 'tier'),
        level = _field(key, 'level'),
        phase = int.parse(key.split('|').last.substring(1)),
        injury = key.startsWith('injury|') ? key.split('|')[1] : null,
        exclusions =
            key.startsWith('exclusion|') ? [key.split('|')[1]] : const [],
        owned = key.startsWith('owned|')
            ? goldenOwnedEquipment['${_field(key, 'tier')}|${_field(key, 'level')}']!
            : const [];
  static String _field(String key, String f) {
    final p = key.split('|');
    final shifted = p[0] == 'injury' || p[0] == 'exclusion';
    if (f == 'tier') return shifted ? p[2] : p[1];
    return p[p.length - 2];
  }

  Set<String> get capability =>
      EquipmentVocab.effectiveItems(tier, owned, exclusions);
}

class _Cell {
  int core = 0, fill = 0, drop = 0, emergency = 0, bTotal = 0, bRepeat = 0;
  final dropTypes = <String, int>{};
  final onSizes = <int>[], offSizes = <int>[];
  final subTotal = <String, int>{}, subHit = <String, int>{};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  final writeReport = Platform.environment['WRITE_CORE_LIST_REPORT'] == '1';
  late Directory tempDir;
  late Map<String, Map<String, dynamic>> byId;

  final cells = <String, _Cell>{};
  final pickCounts = <String, int>{};
  final highImpact = <String, int>{}, coaching = <String, int>{};
  final disagree = <String, int>{};
  final emergencyKeys = <String>[];
  final injuredLists = <String, List<int>>{}; // injury key → drops per list
  final topUpRetired = <String>[]; // R9 evidence: persona + id the top-up added
  final topUpRetiredIds = <String>{};
  var copied = 0;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('core_list_gate');
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
    final rows = (jsonDecode(
      File('assets/data/exercise_library.json').readAsStringSync(),
    ) as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    for (final r in rows) {
      await exBox.put(r['id'] as String, r);
    }
    byId = {for (final r in rows) r['id'] as String: r};
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

  List<int> strengthSizes(Phase p) => [
        for (final w in p.weekPlans.take(2))
          for (final d in w.workoutDays) d.exercises.length
      ];

  /// Runs [p] ON and returns every hard-count violation it produced.
  Future<List<String>> check(GoldenPersona p) async {
    final persona = _Persona(p.key);
    final trace = CoreListTrace();
    CoreListSelector.debugTrace = trace;
    final phase = p.run();
    CoreListSelector.debugTrace = null;
    final bad = <String>[];
    final cap = persona.capability;
    final implement =
        CoreListSelector.needsImplementPreference(cap, persona.tier);
    final level = trace.slots.isEmpty ? persona.level : trace.slots.last.level;
    final cell = cells.putIfAbsent('${persona.tier}|$level', _Cell.new);

    for (final s in trace.slots) {
      switch (s.source) {
        case 'core':
          cell.core++;
        case 'fill':
          cell.fill++;
        case 'drop':
          cell.drop++;
          final t = '${s.slot.targetMuscle}/${s.slot.movementPattern}';
          cell.dropTypes[t] = (cell.dropTypes[t] ?? 0) + 1;
        case 'emergency':
          cell.emergency++;
      }
      if (s.slot.subFocus != null && s.pickedId != null) {
        final k = s.slot.subFocus!;
        cell.subTotal[k] = (cell.subTotal[k] ?? 0) + 1;
        if (CoreListSelector.subFocusMatches(byId[s.pickedId]!, s.slot)) {
          cell.subHit[k] = (cell.subHit[k] ?? 0) + 1;
        }
      }
      if (s.pickedId == null) continue;
      final r = byId[s.pickedId]!;
      final id = s.pickedId!;
      final where = '${p.key} $id ${s.source}';
      pickCounts[id] = (pickCounts[id] ?? 0) + 1;
      if (r['high_impact'] == true) highImpact[id] = (highImpact[id] ?? 0) + 1;
      if (r['requires_coaching'] == true) coaching[id] = (coaching[id] ?? 0) + 1;
      if (_suitableDisagreeIds.contains(id)) disagree[id] = (disagree[id] ?? 0) + 1;

      final needed = EquipmentVocab.fromProfile(r['equipment_needed']);
      if (!EquipmentCapability.canPerform(r['equipment_needed'], cap)) {
        bad.add('equipment: $where needs $needed');
      }
      final d = r['discipline'];
      if (d == 'calisthenics_skill' || d == 'olympic') bad.add('discipline: $where');
      final levels = _strs(r['core_levels']);
      if (s.source == 'core' && !levels.contains(s.level)) {
        bad.add('level: $where not core at ${s.level}');
      }
      if (s.source == 'fill' &&
          (levels.any((l) => _rank[l]! <= _rank[s.level]!) ||
              !s.families.contains(r['variant_family']) ||
              !_strs(r['suitable_for'])
                  .contains(s.level[0].toUpperCase() + s.level.substring(1)))) {
        bad.add('level: $where bad fill at ${s.level}');
      }
      if (persona.injury != null &&
          _strs(r['injury_contraindications']).contains(persona.injury)) {
        bad.add('injury: $where');
      }
      if (needed.any(persona.exclusions.contains)) bad.add('excluded: $where');
      if (implement &&
          _implementPatterns.contains(s.slot.movementPattern) &&
          s.nonImprovisedInPool > 0 &&
          needed.every(CoreListSelector.improvisedTokens.contains)) {
        bad.add('improvised: $where');
      }
      if (levels.isEmpty && r['variant_family'] == null) bad.add('retired: $where');
    }

    // Variant B repeats of A, per (day).
    for (final dayIdx in {for (final s in trace.slots) s.day}) {
      final a = {
        for (final s in trace.slots)
          if (s.day == dayIdx && s.variant == 'A' && s.pickedId != null) s.pickedId
      };
      for (final s in trace.slots) {
        if (s.day == dayIdx && s.variant == 'B' && s.pickedId != null) {
          cell.bTotal++;
          if (a.contains(s.pickedId)) cell.bRepeat++;
        }
      }
    }

    // Lists: a (day, variant) the user actually sees as picked.
    final replaced = {
      for (final e in [...trace.copied, ...trace.emergencyAnyLevel, ...trace.refilled])
        '${e.day}|${e.variant}'
    };
    final drops = <String, int>{};
    for (final s in trace.slots) {
      final k = '${s.day}|${s.variant}';
      if (s.source == 'drop' && !replaced.contains(k)) drops[k] = (drops[k] ?? 0) + 1;
    }
    if (persona.kind == 'grid' &&
        (persona.tier == 'full_gym' || persona.tier == 'basic_gym')) {
      for (final e in drops.entries) {
        if (e.value > 1) bad.add('drops: ${p.key} list ${e.key} drops ${e.value}');
      }
    }
    if (persona.injury != null) {
      injuredLists[p.key] = drops.values.toList();
    }
    for (final e in trace.refilled) {
      bad.add('refilled: ${p.key} day ${e.day} ${e.variant}');
    }
    copied += trace.copied.length;
    if (trace.emergencyAnyLevel.isNotEmpty) emergencyKeys.add(p.key);
    final sizes = strengthSizes(phase);
    if (sizes.any((n) => n == 0)) bad.add('empty day: ${p.key} $sizes');
    // The BUILT lists carry the top-up's additions, which the trace never sees.
    // Re-run only a persona that has a flagged id, with the top-up switched off,
    // to tell B1's own picks (hard) from top-up additions (R9 evidence).
    bool flagged(String id) => byId[id] != null && (_retired(byId[id]!) || _skill(byId[id]!));
    var without = <String>{};
    if (builtIds(phase).any(flagged)) {
      final config = HiveService.instance.configBox;
      await config.put('disable_thin_day_topup', true);
      try {
        without = builtIds(p.run()).toSet();
      } finally {
        await config.delete('disable_thin_day_topup');
      }
    }
    final built = classifyBuilt(
      built: builtIds(phase),
      without: without,
      isRetired: (id) => byId[id] != null && _retired(byId[id]!),
      isSkill: (id) => byId[id] != null && _skill(byId[id]!),
    );
    for (final id in built.hard) {
      bad.add('built: ${p.key} $id');
    }
    for (final id in built.evidence) {
      topUpRetired.add('${p.key} $id');
      topUpRetiredIds.add(id);
    }
    cell.onSizes.addAll(sizes);
    return bad;
  }

  final personas = generatorGoldenPersonas();
  for (final group in {for (final p in personas) p.group}) {
    test('ON hard counts are 0: $group', () async {
      final bad = <String>[];
      for (final p in personas.where((p) => p.group == group)) {
        bad.addAll(await check(p));
      }
      expect(bad, isEmpty,
          reason: '${bad.length} violations; first 10:\n${bad.take(10).join('\n')}');
    });
  }

  test('R9: the retired rows the top-up adds are exactly the recorded set', () {
    // Exact, not a subset: an empty evidence list (a broken re-run) must fail too.
    expect(topUpRetiredIds, _r9TopUpRetired,
        reason: 'a NEW retired id reached an injured user through the thin-day '
            'top-up under B1 ON (or a recorded one stopped): decide it at the '
            'enable_core_list_pool flip review, then edit _r9TopUpRetired');
    expect(topUpRetired, isNotEmpty);
  });

  group('classifyBuilt (the R9 attribution)', () {
    bool retired(String id) => id.startsWith('R');
    bool skill(String id) => id.startsWith('S');
    ({List<String> hard, List<String> evidence}) run(
            List<String> built, Set<String> without) =>
        classifyBuilt(
            built: built, without: without, isRetired: retired, isSkill: skill);

    test('a retired id built ONLY with the top-up on is evidence, not a failure', () {
      final r = run(['R1', 'K1'], {'K1'});
      expect(r.evidence, ['R1']);
      expect(r.hard, isEmpty);
    });

    test('a retired id also built WITHOUT the top-up is B1\'s own: hard', () {
      final r = run(['R1'], {'R1'});
      expect(r.hard, ['R1']);
      expect(r.evidence, isEmpty);
    });

    test('a skill id the top-up added is never evidence: hard', () {
      final r = run(['S1'], const {});
      expect(r.hard, ['S1']);
      expect(r.evidence, isEmpty);
    });

    test('a clean build yields neither', () {
      final r = run(['K1', 'K2'], const {});
      expect(r.hard, isEmpty);
      expect(r.evidence, isEmpty);
    });
  });

  test('report', () async {
    // OFF comparison: same personas, flag absent.
    final config = HiveService.instance.configBox;
    await config.delete('enable_core_list_pool');
    for (final p in personas) {
      final persona = _Persona(p.key);
      final level = PlanGenerator.effectiveLevel(persona.level, persona.phase);
      cells.putIfAbsent('${persona.tier}|$level', _Cell.new)
          .offSizes
          .addAll(strengthSizes(p.run()));
    }
    await config.put('enable_core_list_pool', true);

    // Multi-injury sweep: every tier × level × days, phases 1-2, every pair.
    const injuries = ['knee', 'shoulder', 'lower_back', 'wrist'];
    var runs = 0, sweepEmergency = 0, sweepRefilled = 0;
    final sweepRetired = <String>{};
    final sweepSkill = <String>{};
    for (final tier in goldenTiers) {
      for (final level in ['beginner', 'intermediate', 'advanced']) {
        for (final days in [3, 4, 5, 6]) {
          for (final phase in [1, 2]) {
            for (var i = 0; i < injuries.length; i++) {
              for (var j = i + 1; j < injuries.length; j++) {
                final trace = CoreListTrace();
                CoreListSelector.debugTrace = trace;
                final out = PlanGenerator.instance.generateV4(
                  goal: 'build_muscle',
                  equipment: tier,
                  daysPerWeek: days,
                  phase: phase,
                  experienceLevel: level,
                  injuries: [injuries[i], injuries[j]],
                  previousWeights: const {},
                );
                CoreListSelector.debugTrace = null;
                runs++;
                if (trace.emergencyAnyLevel.isNotEmpty) sweepEmergency++;
                if (trace.refilled.isNotEmpty) sweepRefilled++;
                // The BUILT lists, not the trace: a refilled variant runs the
                // OFF cascade (universal pool included), whose picks the
                // trace never sees (B-pass F1).
                for (final id in builtIds(out)) {
                  final r = byId[id];
                  if (r == null) continue;
                  if (_retired(r)) sweepRetired.add(id);
                  if (_skill(r)) sweepSkill.add(id);
                }
              }
            }
          }
        }
      }
    }

    String stats(List<int> xs) {
      if (xs.isEmpty) return '-';
      final s = [...xs]..sort();
      final mean = xs.reduce((a, b) => a + b) / xs.length;
      return 'p5 ${s[(s.length * 0.05).floor()]} / min ${s.first} / '
          'mean ${mean.toStringAsFixed(2)}';
    }

    final out = StringBuffer()
      ..writeln('# Core-list pool — ON-world report (Batch B1 Task 4)')
      ..writeln()
      ..writeln('Generated by `test/plan_generator/core_list_pool_gate_test.dart` '
          '(`WRITE_CORE_LIST_REPORT=1`) over the ${personas.length} golden personas, '
          'flag ON, real `generateV4`. The gate\'s hard zeros cover these personas '
          'only; the multi-injury sweep below is reported, not gated.')
      ..writeln()
      ..writeln('## Per tier × effective level')
      ..writeln()
      ..writeln('| cell | core | fill | drop | emergency | B repeats A | '
          'strength/day ON | strength/day OFF |')
      ..writeln('|---|---|---|---|---|---|---|---|');
    final keys = cells.keys.toList()..sort();
    for (final k in keys) {
      final c = cells[k]!;
      final rate = c.bTotal == 0 ? '-' : '${(100 * c.bRepeat / c.bTotal).toStringAsFixed(1)}%';
      out.writeln('| $k | ${c.core} | ${c.fill} | ${c.drop} | ${c.emergency} | '
          '$rate | ${stats(c.onSizes)} | ${stats(c.offSizes)} |');
    }
    out
      ..writeln()
      ..writeln('## Drop slot types')
      ..writeln();
    for (final k in keys) {
      final t = cells[k]!.dropTypes.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (t.isEmpty) continue;
      out.writeln('- **$k**: ${t.map((e) => '${e.key} ×${e.value}').join(', ')}');
    }
    out
      ..writeln()
      ..writeln('## Sub-focus match rate')
      ..writeln();
    final subTotal = <String, int>{}, subHit = <String, int>{};
    for (final c in cells.values) {
      c.subTotal.forEach((k, v) => subTotal[k] = (subTotal[k] ?? 0) + v);
      c.subHit.forEach((k, v) => subHit[k] = (subHit[k] ?? 0) + v);
    }
    for (final k in subTotal.keys.toList()..sort()) {
      out.writeln('- $k: ${subHit[k] ?? 0} / ${subTotal[k]}');
    }
    String top(Map<String, int> m, int n) {
      final e = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      return e
          .take(n)
          .map((x) => '${x.key} ${byId[x.key]?['name']} ×${x.value}')
          .join('; ');
    }

    final injuredMulti = injuredLists.entries
        .where((e) => e.value.any((d) => d > 1))
        .map((e) => e.key)
        .toList()
      ..sort();
    out
      ..writeln()
      ..writeln('## Reported, not gated (flip criteria)')
      ..writeln()
      ..writeln('- `emergencyAnyLevel` personas: ${emergencyKeys.length} '
          '${emergencyKeys.isEmpty ? '' : '(${emergencyKeys.join(', ')})'}')
      ..writeln('- `copied` variants: $copied')
      ..writeln('- injured personas with a list dropping 2+ slots: '
          '${injuredMulti.length} ${injuredMulti.isEmpty ? '' : '(${injuredMulti.join(', ')})'}')
      ..writeln('- multi-injury sweep ($runs runs, every pair of '
          '${injuries.join('/')}): emergencyAnyLevel in $sweepEmergency, '
          'refilled in $sweepRefilled; built lists: retired picks ${sweepRetired.isEmpty ? 'none' : sweepRetired.join(', ')}, '
          'skill/olympic picks ${sweepSkill.isEmpty ? 'none' : sweepSkill.join(', ')}')
      ..writeln('- core-vs-suitable_for disagreements picked: '
          '${disagree.isEmpty ? 'none' : top(disagree, 10)}')
      ..writeln('- high-impact picks: ${highImpact.isEmpty ? 'none' : top(highImpact, 20)}')
      ..writeln('- requires-coaching picks: ${coaching.isEmpty ? 'none' : top(coaching, 20)}')
      ..writeln()
      ..writeln('## Top 20 repeated picks')
      ..writeln()
      ..writeln(top(pickCounts, 20));
    File(_reportPath).writeAsStringSync(out.toString());
  }, skip: !writeReport);
}
