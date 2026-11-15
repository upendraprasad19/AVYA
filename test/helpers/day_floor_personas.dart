// Unit 2B (OI-452): the personas of the day-floor gate and of its kill-switch fixture, in one fixed order, and the
// plan hash. Deliberately free of any Unit 2B symbol (no `floorSeats`, no oracle), so the SAME file compiles against
// main 8a2e1c5a and records the floor-off digests there (`day_floor_gate_lib.dart`, `day_floor_kill_switch_test.dart`).
import 'dart:convert';
import 'dart:io';

import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';

import '../../scripts/migration_ledger_hash_lib.dart' show sha256Hex;
import 'generator_golden_personas.dart' show namesByDay;
import 'injury_floor_sweep_lib.dart';

const dayFloorFixturePath = 'test/fixtures/day_floor_off_hashes.json';

/// One gate persona. [pinned]: a repeat whose pins are the uninjured phase-1 plan of the same goal, level, day count,
/// tier and [minutes] (`dayFloorPins`).
typedef DayFloorPersona = ({
  String label,
  String tier,
  String goal,
  String level,
  int days,
  int phase,
  List<String> injuries,
  int? minutes,
  bool pinned,
});

/// The blocks: `pairs_p1` and `pairs_p4` (15 pairs x 4 goals x 3 levels x 3-6 days, 60 minutes, phase 1 / 4) and
/// `rep30` (the pinned phase-2 repeat over the 15 pairs at 30 minutes, beginner, 3-6 days).
const dayFloorBlocks = ['pairs_p1', 'pairs_p4', 'rep30'];

List<DayFloorPersona> dayFloorPersonas(String block, String tier) {
  final out = <DayFloorPersona>[];
  final pairs = [
    for (var i = 0; i < kSweepPairInjuries.length; i++)
      for (var j = i + 1; j < kSweepPairInjuries.length; j++) [kSweepPairInjuries[i], kSweepPairInjuries[j]],
  ];
  if (block == 'rep30') {
    for (final goal in kSweepGoals) {
      for (final d in const [3, 4, 5, 6]) {
        for (final pair in pairs) {
          out.add((
            label: '${pair.join('+')}|$tier|$goal|beginner|${d}d|p2-pinned|30min',
            tier: tier,
            goal: goal,
            level: 'beginner',
            days: d,
            phase: 2,
            injuries: pair,
            minutes: 30,
            pinned: true,
          ));
        }
      }
    }
    return out;
  }
  final phase = block == 'pairs_p4' ? 4 : 1;
  for (final pair in pairs) {
    for (final goal in kSweepGoals) {
      for (final level in kSweepLevels) {
        for (final d in const [3, 4, 5, 6]) {
          out.add((
            label: '${pair.join('+')}|$tier|$goal|$level|${d}d|p$phase',
            tier: tier,
            goal: goal,
            level: level,
            days: d,
            phase: phase,
            injuries: pair,
            minutes: null,
            pinned: false,
          ));
        }
      }
    }
  }
  return out;
}

/// The pins of a pinned persona: the uninjured phase-1 plan at its minutes (generated in whatever world is set).
Map<int, ({List<String> a, List<String> b})> dayFloorPins(SweepHarness h, DayFloorPersona p) => namesByDay(h.gen(
    tier: p.tier, goal: p.goal, level: p.level, days: p.days, phase: 1, injuries: const [], minutes: p.minutes));

String dayFloorPlanHash(Phase p) => sha256Hex(utf8.encode(jsonEncode(p.toMap())));

String dayFloorDigest(List<String> hashes) => sha256Hex(utf8.encode(hashes.join('\n')));

void _write(File file, Map<String, dynamic> m) {
  m['_meta'] = 'Unit 2B kill-switch fixture (plan docs/plans/2026-11-13-generator-step2b-day-floor.md §2 F5): '
      'digest|<block>|<tier> = sha256 over the newline-joined sha256 of every floor-OFF plan of the day-floor gate '
      '(recorded on main 8a2e1c5a); combo|... = one combination of disable_lead_first x disable_day_floor on a sample '
      '(floor-off keys recorded on main 8a2e1c5a, floor-on keys on the 2B tree). See day_floor_gate_lib.dart and '
      'day_floor_kill_switch_test.dart.';
  final sorted = {for (final k in m.keys.toList()..sort()) k: m[k]};
  file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(sorted)}\n');
}

/// Merges [entries] into the fixture (the recording path of `day_floor_kill_switch_test.dart`), sorted, with `_meta`.
void writeDayFloorFixtureEntries(Map<String, Object> entries) {
  final file = File(dayFloorFixturePath);
  final existing = file.existsSync()
      ? Map<String, dynamic>.from(jsonDecode(file.readAsStringSync()) as Map)
      : <String, dynamic>{};
  existing.addAll(entries);
  _write(file, existing);
}
