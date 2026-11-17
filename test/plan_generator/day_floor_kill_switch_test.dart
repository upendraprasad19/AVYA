@Timeout(Duration(minutes: 20))
library;

// Unit 2B (docs/plans/2026-11-13-generator-step2b-day-floor.md §2 F5, OI-452): the kill switch `disable_day_floor`
// restores the pre-2B allocation verbatim, in both Unit 2A paths. The uninjured golden (1,010 personas) is unchanged by
// the floor, so the proofs use INJURED personas, where the floor acts:
//  - the floor-off plans of the day-floor gate (`day_floor_gate_*_test.dart`, every persona of `pairs_p1`, `pairs_p4`
//    and `rep30`): the gate checks their digest against `digest|<block>|<tier>`. They equalled main 8a2e1c5a until the
//    3A / 3C switches were deleted (generator-killswitch-3a3c); since then they are the floor-off world recorded on
//    421cd2d2 with goal training and the unreserved finisher (plan §1, the two-tree oracle);
//  - this test: a sample where the floor acts (basic_gym pairs at 5 days, the 6-day 30-minute repeat) in all four
//    combinations of `disable_lead_first` and `disable_day_floor`, recorded on 421cd2d2 (RECORD_DAY_FLOOR_HASHES=main
//    for the floor-off keys, =on for the floor-on keys).
// The fixture and this test are deleted in the commit that deletes the switch (OI-506).
//
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/cardio_finisher.dart';

import '../helpers/day_floor_personas.dart';
import '../helpers/injury_floor_sweep_lib.dart';

/// The sample: personas of the gate where the floor acts (the probe put the pairs' thin days on 5-day plans): basic_gym
/// pairs at 5 days (15 pairs x 4 goals x 3 levels) and the 30-minute pinned repeat at 6 days (the 6-day path, B = A).
List<DayFloorPersona> _sample() => [
      for (final p in dayFloorPersonas('pairs_p1', 'basic_gym'))
        if (p.days == 5) p,
      for (final p in dayFloorPersonas('rep30', 'basic_gym'))
        if (p.days == 6) p,
    ];

void main() {
  final h = SweepHarness.install();

  void setFlags({required bool floor, required bool leadFirst}) {
    final box = HiveService.instance.configBox;
    if (floor) {
      box.delete('disable_day_floor');
    } else {
      box.put('disable_day_floor', true);
    }
    if (leadFirst) {
      box.delete('disable_lead_first');
    } else {
      box.put('disable_lead_first', true);
    }
    // Unit 2C-a: the four combinations are pinned to main 8a2e1c5a (before 2C); the 2C switch is set for all of them.
    box.put('disable_balanced_week', true);
    // The 3A / 3C switches are deleted (generator-killswitch-3a3c): the combinations run with goal training, and with
    // the finisher built but its time not reserved (`CardioFinisher.debugReserve`), the world the 3C key gave.
    CardioFinisher.debugReserve = false;
  }

  void clearFlags() {
    setFlags(floor: true, leadFirst: true);
    HiveService.instance.configBox.delete('disable_balanced_week');
    CardioFinisher.debugReserve = true;
  }

  /// key -> (floor on?, lead-first on?, persona)
  Map<String, (bool, bool, DayFloorPersona)> combos() => {
        for (final p in _sample())
          for (final lf in [true, false])
            for (final fl in [true, false]) 'combo|lf_${lf ? 'on' : 'off'}|fl_${fl ? 'on' : 'off'}|${p.label}': (fl, lf, p),
      };

  String comboHash((bool, bool, DayFloorPersona) k) {
    final (fl, lf, p) = k;
    try {
      setFlags(floor: fl, leadFirst: lf);
      final pins = p.pinned ? dayFloorPins(h, p) : null;
      return dayFloorPlanHash(h.gen(
          tier: p.tier,
          goal: p.goal,
          level: p.level,
          days: p.days,
          phase: p.phase,
          injuries: p.injuries,
          pins: pins,
          minutes: p.minutes));
    } finally {
      clearFlags();
    }
  }

  test('the four combinations of disable_lead_first x disable_day_floor on an injured sample are pinned', () {
    final all = combos();
    final record = Platform.environment['RECORD_DAY_FLOOR_HASHES'];
    if (record == 'main' || record == 'on') {
      // main: every floor-off combination key; on: the floor-on combination keys. Both were re-recorded on 421cd2d2
      // (generator-killswitch-3a3c, plan §1); the gate's floor-off digests were recorded there too, by a temporary
      // path in `day_floor_gate_lib.dart` (commit c16ce1ea).
      final entries = <String, Object>{
        for (final e in all.entries)
          if (e.value.$1 == (record == 'on')) e.key: comboHash(e.value),
      };
      writeDayFloorFixtureEntries(entries);
      // ignore: avoid_print
      print('recorded ${entries.length} entries ($record)');
      return;
    }
    final fixture = jsonDecode(File(dayFloorFixturePath).readAsStringSync()) as Map<String, dynamic>;
    expect({for (final k in fixture.keys) if (k.startsWith('combo|')) k}, all.keys.toSet());
    final diffs = <String>[];
    for (final e in all.entries) {
      if (fixture[e.key] != comboHash(e.value)) diffs.add(e.key);
    }
    expect(diffs, isEmpty, reason: '${diffs.length} keys differ; first 10: ${diffs.take(10).join(', ')}');
    // A FIXTURE-content guard, not the live check (B-pass seat 2, finding 2-3): the sample must hold days the floor
    // changes, or the floor-on keys pin nothing. The live check is `diffs` above: a switch ignored in either 2A path
    // turns the main-recorded floor-off keys red there.
    var changed = 0;
    for (final k in all.keys.where((k) => k.contains('|fl_on|'))) {
      if (fixture[k] != fixture[k.replaceFirst('|fl_on|', '|fl_off|')]) changed++;
    }
    // ignore: avoid_print
    print('combination keys the floor changes: $changed of ${all.length ~/ 2}');
    // Measured 2026-11-13: 18 (9 with lead-first on, 9 off; 2 of them 6-day). The first sample (3 pairs, 3 and 6 days)
    // changed 0, which is why the sample sits where the floor acts. Re-measured on 421cd2d2 with goal training and the
    // unreserved finisher (generator-killswitch-3a3c): 28 (14 with lead-first on, 14 off; 12 of them 6-day). The
    // growth is in the 6-day 30-minute repeat (2 -> 12); the cause was not isolated.
    expect(changed, 28);
  });
}
