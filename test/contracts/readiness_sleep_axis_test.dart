// Founder-locked sleep→axis thresholds (2026-09-01). Both boundary values
// fall in the MIDDLE band — that is the whole point of these tests, because
// an off-by-one at a threshold is silent.
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/readiness.dart';

void main() {
  group('sleepAxisFromHours — founder-locked thresholds', () {
    test('above 6.5h → 0 (Solid)', () {
      expect(sleepAxisFromHours(8.0), 0);
      expect(sleepAxisFromHours(6.6), 0);
    });

    test('exactly 6.5h → 1 (Okay) — upper boundary is MIDDLE', () {
      expect(sleepAxisFromHours(6.5), 1);
    });

    test('mid band → 1 (Okay)', () {
      expect(sleepAxisFromHours(5.5), 1);
    });

    test('exactly 4.5h → 1 (Okay) — lower boundary is MIDDLE', () {
      expect(sleepAxisFromHours(4.5), 1);
    });

    test('below 4.5h → 2 (Rough)', () {
      expect(sleepAxisFromHours(4.4), 2);
      expect(sleepAxisFromHours(0.5), 2);
    });

    test('feeds readinessLevelFor unchanged — 3 worst axes → red', () {
      expect(
        readinessLevelFor(
            sleep: sleepAxisFromHours(3.0), soreness: 2, energy: 2),
        ReadinessLevel.red,
      );
    });

    test('good sleep prevents red even with 2 bad axes', () {
      expect(
        readinessLevelFor(
            sleep: sleepAxisFromHours(8.0), soreness: 2, energy: 2),
        ReadinessLevel.yellow,
      );
    });
  });
}
