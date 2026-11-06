// Founder-locked sleep→axis thresholds (2026-09-01). Both boundary values
// fall in the MIDDLE band — that is the whole point of these tests, because
// an off-by-one at a threshold is silent.
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/health_sync_service.dart';
import 'package:icanbefitter/core/utils/readiness.dart';

void main() {
  _writeDecisionTests();
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

// ── B-pass F2: the synced-sleep WRITE decision ───────────────────────────────
// Extracted from HealthSyncService so it is testable at all: the enclosing sync
// method needs a live Health Connect plugin and cannot run in this suite. The
// SoT `sleep_logs` behavioral_test_path covers logSleep's own writers and knows
// nothing about this third path -- rule 21's documented "green about a line it
// does not run" trap -- so the decision gets its own coverage here.
void _writeDecisionTests() {
  group('shouldWriteSyncedSleep — manual entry always wins', () {
    test('no reading → do not write', () {
      expect(HealthSyncService.shouldWriteSyncedSleep(null, null), isFalse);
    });

    test('reading + no existing row → WRITE', () {
      expect(HealthSyncService.shouldWriteSyncedSleep(7.3, null), isTrue);
    });

    test('reading + an existing row → do NOT overwrite the user', () {
      expect(
        HealthSyncService.shouldWriteSyncedSleep(7.3, {'sleep_hours': 5.0}),
        isFalse,
        reason: 'a manual or AI-coach entry must never be clobbered by sync',
      );
    });

    test('zero/negative reading → do not write', () {
      expect(HealthSyncService.shouldWriteSyncedSleep(0.0, null), isFalse);
      expect(HealthSyncService.shouldWriteSyncedSleep(-1.0, null), isFalse);
    });
  });
}
