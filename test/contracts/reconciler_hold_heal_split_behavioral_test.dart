// BEHAVIORAL TEST — the reconciler's trigger is split from its write
// (FOB-7(b) / OI-60)
//
// Concept:  plan_integrity_reconcile_triggers
// Writer:   lib/core/services/plan_integrity_reconciler.dart reconcile()
//           — merges `schedule_*` rows AND (separately) writes
//             plan_start_date / plan_end_date
// Reader:   PlanIntegrityReconciler.computeTriggers() — the single point that
//           decides which of those two the current symptom authorises
//
// THE RULE UNDER TEST: a hold week that lost its exercises must be HEALED, and
// healing it must NOT move the plan window.
//
// WHY A RECORD AND NOT A BOOL: the entire fix is the distinction between "fetch
// and merge" and "move the window". A single bool return would force the caller
// to re-derive the second decision, which is the recurring failure this repo
// files under guard-without-its-mirror — three passes fixed a guard correctly
// and the caller kept throwing the binding away. So computeTriggers returns
// both verdicts and these tests assert both.
//
// ⚠ THE REFUTED DESIGN, recorded so it is not re-proposed: widening the 1..4
// scan. docs/audit/oi60-streak-identity.closure.yaml, P0-11 concern d7f3a9 —
// that scan IS the re-anchor trigger, so widening it buys no healing and only
// makes plan_start/plan_end move more often. The test
// 'a hold-only symptom must NOT authorise the re-anchor' is what fails if
// someone re-implements it that way.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/plan_integrity_reconciler.dart';

/// A planned workout day that still has its exercises — healthy.
Map<String, dynamic> healthy(String date) => {
      'type': 'workout',
      'date': date,
      'status': 'planned',
      'exercises': const [
        {'name': 'Squat', 'sets': 3, 'reps': 5},
      ],
    };

/// A planned workout day whose exercises were dropped — the restore-skip
/// symptom this reconciler exists to cure.
Map<String, dynamic> stripped(String date) => {
      'type': 'workout',
      'date': date,
      'status': 'planned',
      'exercises': const <Map<String, dynamic>>[],
    };

void main() {
  group('FOB-7(b) — hold weeks trigger the heal without moving the window', () {
    test('a hold-only symptom DOES authorise the fetch + merge', () {
      final t = PlanIntegrityReconciler.computeTriggers(
        windowRows: [healthy('2026-06-01'), healthy('2026-06-02')],
        holdRows: [stripped('2026-06-29')],
      );
      expect(t.shouldFetch, isTrue,
          reason: 'a hold week with dropped exercises must heal — before this '
              'it was invisible to the 1..4 scan and never healed at all');
    });

    test('a hold-only symptom must NOT authorise the re-anchor', () {
      // THE test. If someone "fixes" this by widening the 1..4 scan instead of
      // splitting the predicates, mayReanchor becomes true here and this fails.
      final t = PlanIntegrityReconciler.computeTriggers(
        windowRows: [healthy('2026-06-01'), healthy('2026-06-02')],
        holdRows: [stripped('2026-06-29')],
      );
      expect(t.mayReanchor, isFalse,
          reason: 'plan_start/plan_end must not move on a hold-only symptom');
    });

    test('the weeks-1-4 symptom still authorises BOTH, exactly as before', () {
      final t = PlanIntegrityReconciler.computeTriggers(
        windowRows: [stripped('2026-06-01')],
        holdRows: const [],
      );
      expect(t.shouldFetch, isTrue);
      expect(t.mayReanchor, isTrue,
          reason: 'the original behaviour is unchanged for the original symptom');
    });

    test('both symptoms present: fetch and re-anchor, unchanged', () {
      final t = PlanIntegrityReconciler.computeTriggers(
        windowRows: [stripped('2026-06-01')],
        holdRows: [stripped('2026-06-29')],
      );
      expect(t.shouldFetch, isTrue);
      expect(t.mayReanchor, isTrue);
    });

    test('healthy everywhere: no fetch, no re-anchor (the no-op case)', () {
      final t = PlanIntegrityReconciler.computeTriggers(
        windowRows: [healthy('2026-06-01')],
        holdRows: [healthy('2026-06-29')],
      );
      expect(t.shouldFetch, isFalse);
      expect(t.mayReanchor, isFalse);
    });

    test('flag OFF is byte-identical: activeHoldWeeks() yields no hold rows', () {
      // With `enable_hold_weeks` OFF the production caller passes an EMPTY
      // holdRows (activeHoldWeeks() returns const []). Pinning that here means
      // the ship-dark property is asserted at the decision layer, not just
      // assumed from the seam's documentation.
      final off = PlanIntegrityReconciler.computeTriggers(
        windowRows: [healthy('2026-06-01')],
        holdRows: const [],
      );
      expect(off.shouldFetch, isFalse);
      expect(off.mayReanchor, isFalse);

      final offBroken = PlanIntegrityReconciler.computeTriggers(
        windowRows: [stripped('2026-06-01')],
        holdRows: const [],
      );
      expect(offBroken.shouldFetch, isTrue);
      expect(offBroken.mayReanchor, isTrue);
    });

    test('a COMPLETED hold day is not a symptom', () {
      // needsHeal ignores completed days; a hold week the user actually trained
      // must not drag the whole reconciler awake on every boot.
      final t = PlanIntegrityReconciler.computeTriggers(
        windowRows: [healthy('2026-06-01')],
        holdRows: [
          {
            'type': 'workout',
            'date': '2026-06-29',
            'status': 'completed',
            'exercises': const <Map<String, dynamic>>[],
          },
        ],
      );
      expect(t.shouldFetch, isFalse);
      expect(t.mayReanchor, isFalse);
    });

    test('a REST day in a hold week is not a symptom', () {
      final t = PlanIntegrityReconciler.computeTriggers(
        windowRows: [healthy('2026-06-01')],
        holdRows: [
          {
            'type': 'rest',
            'date': '2026-06-29',
            'status': 'planned',
            'exercises': const <Map<String, dynamic>>[],
          },
        ],
      );
      expect(t.shouldFetch, isFalse);
      expect(t.mayReanchor, isFalse);
    });
  });
}
