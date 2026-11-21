// OI-390 U6 / T17 — SimulationService.simSkipsDay, the dev sim's skip seam.
// A non-empty skip set decides alone (the break window is ignored); an empty
// set keeps the original `inBreakWindow || roll >= adherence` rule.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/dev/simulation_service.dart';

bool _skips(int iso, Set<int> set, {bool brk = false, double roll = 0.5}) =>
    SimulationService.simSkipsDay(
      isoWeekday: iso,
      skipIsoWeekdays: set,
      inBreakWindow: brk,
      roll: roll,
      adherence: 0.85,
    );

void main() {
  test('in the set → skip, whatever the roll or break window', () {
    expect(_skips(1, {1}, roll: 0.0), isTrue);
    expect(_skips(1, {1}, brk: true), isTrue);
  });

  test('not in a non-empty set → complete, even in the break window', () {
    expect(_skips(3, {1}, brk: true, roll: 0.99), isFalse);
  });

  test('empty set → the original rule', () {
    expect(_skips(1, {}, roll: 0.5), isFalse);
    expect(_skips(1, {}, roll: 0.9), isTrue);
    expect(_skips(1, {}, brk: true, roll: 0.0), isTrue);
  });
}
