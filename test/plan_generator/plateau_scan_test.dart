// Batch 12-A (W3.5 plateau escalation) — PURE flatness-predicate unit test.
//
// `PlateauScan.isFlat` is the one genuinely Hive-free piece of the detector (the
// numeric "no meaningful progress" test); it is pinned here in isolation. The
// Hive-driven gates (window / span / ≥3-session / compound-only / fatigue /
// group-aggregation / no-double-bump / byte-identical) are pinned behaviorally in
// `test/contracts/plateau_escalation_behavioral_test.dart`.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plateau_scan.dart';

void main() {
  group('PlateauScan.isFlat — flatness threshold ((max−min)/max ≤ 5%)', () {
    test('perfectly flat → flat', () {
      expect(PlateauScan.isFlat([100, 100, 100]), isTrue);
    });

    test('within 5% range → flat', () {
      expect(PlateauScan.isFlat([100, 102, 101]), isTrue); // 2% range
      expect(PlateauScan.isFlat([100, 100, 105]), isTrue); // 5/105 ≈ 4.8% ≤ 5%
    });

    test('just over 5% range → NOT flat (progressing)', () {
      expect(PlateauScan.isFlat([100, 100, 106]), isFalse); // 6/106 ≈ 5.7%
      expect(PlateauScan.isFlat([100, 105, 110]), isFalse); // 10/110 ≈ 9%
    });

    test('a mid-window dip breaks flatness (range-based, order-independent)', () {
      expect(PlateauScan.isFlat([100, 90, 100]), isFalse); // 10/100 = 10%
    });

    test('a slight decline within 5% is still a plateau (the declining∧flat case)',
        () {
      // e1RM [100,100,100,98]: 2% range → flat here, yet latest<prior (declining)
      // for titration → the safety composition (net −1) is pinned behaviorally.
      expect(PlateauScan.isFlat([100, 100, 100, 98]), isTrue);
    });

    test('empty / non-positive → NOT flat (safe default)', () {
      expect(PlateauScan.isFlat(const []), isFalse);
      expect(PlateauScan.isFlat([0, 0, 0]), isFalse);
    });
  });
}
