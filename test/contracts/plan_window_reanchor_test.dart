// BEHAVIORAL TEST — plan_window_reanchor (free-tier-hold durability #1)
//
// Concept:  plan_window_reanchor / restore_completeness — the monotonic,
//           phase-gated re-anchor shared by `_restoreWorkoutPlan` +
//           `PlanIntegrityReconciler.reconcile` (both wire its output into
//           MigratedKey).
// Writer:   lib/core/services/plan_window_reanchor.dart (PlanWindowReanchor.resolve)
//
// Each assertion FAILS if the re-anchor regresses to:
//   - unconditional cloud-verbatim (the P0-1 hold collapse), OR
//   - a blind max() (wrong across a phase advance — an old hold-extended end
//     would outlive a freshly-advanced 4-week phase).

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/plan_window_reanchor.dart';

void main() {
  group('PlanWindowReanchor.resolve', () {
    test('fresh install (null local) → cloud verbatim', () {
      final r = PlanWindowReanchor.resolve(
        localStart: null,
        localEnd: null,
        cloudStart: '2026-06-01T00:00:00.000',
        cloudEnd: '2026-06-28T00:00:00.000',
      );
      expect(r.planStart, '2026-06-01T00:00:00.000');
      expect(r.planEnd, '2026-06-28T00:00:00.000');
    });

    test(
        'phase advance (cloud plan_start differs) → cloud verbatim, even when '
        'the local plan_end is later', () {
      // Local had a hold-extended end in the OLD phase; cloud is a NEW phase
      // (different start). The new 4-week phase must NOT inherit the old
      // extension — a blind max() would wrongly keep the larger local end.
      final r = PlanWindowReanchor.resolve(
        localStart: '2026-06-01T00:00:00.000',
        localEnd: '2026-08-30T00:00:00.000', // stale, far-out hold extension
        cloudStart: '2026-06-29T00:00:00.000', // advanced phase
        cloudEnd: '2026-07-26T00:00:00.000',
      );
      expect(r.planStart, '2026-06-29T00:00:00.000');
      expect(r.planEnd, '2026-07-26T00:00:00.000',
          reason: 'a phase advance takes cloud verbatim');
    });

    test(
        'same phase, local end LATER (a hold) → keep local end (survives a '
        'stale cloud snapshot)', () {
      final r = PlanWindowReanchor.resolve(
        localStart: '2026-06-01T00:00:00.000',
        localEnd: '2026-07-12T00:00:00.000', // extended by a hold
        cloudStart: '2026-06-01T00:00:00.000', // SAME phase
        cloudEnd: '2026-06-28T00:00:00.000', // stale pre-hold end
      );
      expect(r.planStart, '2026-06-01T00:00:00.000');
      expect(r.planEnd, '2026-07-12T00:00:00.000',
          reason:
              'the hold extension MUST survive — the P0-1 collapse is exactly '
              'cloud-verbatim reverting this');
    });

    test('same phase, cloud end LATER → keep cloud end (monotonic-up, other '
        'direction)', () {
      final r = PlanWindowReanchor.resolve(
        localStart: '2026-06-01T00:00:00.000',
        localEnd: '2026-06-28T00:00:00.000',
        cloudStart: '2026-06-01T00:00:00.000',
        cloudEnd: '2026-07-12T00:00:00.000',
      );
      expect(r.planEnd, '2026-07-12T00:00:00.000');
    });

    test('same-phase test is date-only (a differing time/format is still the '
        'same phase)', () {
      final r = PlanWindowReanchor.resolve(
        localStart: '2026-06-01T00:00:00.000',
        localEnd: '2026-07-12T00:00:00.000',
        cloudStart: '2026-06-01', // date-only string, same calendar day
        cloudEnd: '2026-06-28',
      );
      expect(r.planEnd, '2026-07-12T00:00:00.000',
          reason: 'same day despite differing format → same phase → keep later');
    });
  });
}
