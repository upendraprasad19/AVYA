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

import 'dart:io';

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

    // ── Newer-local-phase rule (ensure-current plan A1.8b, 2026-10-16) ──
    // The device advanced to Phase IV (window Oct 12 → Nov 8) but the advance's
    // plan push never landed, so the cloud bundle is still Phase III.
    group('newer local phase (keepNewerLocalPhase)', () {
      PlanWindowReanchor run({
        String? localStart = '2026-10-12T00:00:00.000',
        String? localEnd = '2026-11-08T00:00:00.000',
        String? cloudStart = '2026-09-14T00:00:00.000',
        String? cloudEnd = '2026-10-11T00:00:00.000',
        Object? localPhase = 4,
        Object? cloudPhase = 3,
        bool keep = true,
      }) =>
          PlanWindowReanchor.resolve(
            localStart: localStart,
            localEnd: localEnd,
            cloudStart: cloudStart,
            cloudEnd: cloudEnd,
            localPlanPhase: localPhase,
            cloudPlanPhase: cloudPhase,
            keepNewerLocalPhase: keep,
          );

      test('stale cloud (earlier start, lower phase) → keep local: (null, null)',
          () {
        final r = run();
        expect(r.planStart, isNull);
        expect(r.planEnd, isNull,
            reason: 'nothing to write: the Phase IV window must survive');
      });

      test(
          'same-phase regen with a LATER local start → cloud wins (the a7d3f1 '
          'heal: login-restore regen / Train repair regen)', () {
        final r = run(localPhase: 3, cloudPhase: 3);
        expect(r.planStart, '2026-09-14T00:00:00.000');
        expect(r.planEnd, '2026-10-11T00:00:00.000');
      });

      test('local phase LOWER than cloud (Edit Profile stamps phase 1) → cloud',
          () {
        final r = run(localPhase: 1, cloudPhase: 3);
        expect(r.planStart, '2026-09-14T00:00:00.000');
      });

      test('missing / non-int phase on either side → today\'s cloud rule', () {
        for (final r in [
          run(localPhase: null),
          run(cloudPhase: null),
          run(localPhase: '4'),
          run(cloudPhase: 3.5),
        ]) {
          expect(r.planStart, '2026-09-14T00:00:00.000');
          expect(r.planEnd, '2026-10-11T00:00:00.000');
        }
      });

      test('cloud start AFTER local start (another device advanced) → cloud',
          () {
        final r = run(
          localStart: '2026-09-14T00:00:00.000',
          localEnd: '2026-10-11T00:00:00.000',
          cloudStart: '2026-10-12T00:00:00.000',
          cloudEnd: '2026-11-08T00:00:00.000',
          localPhase: 3,
          cloudPhase: 4,
        );
        expect(r.planStart, '2026-10-12T00:00:00.000');
      });

      test(
          'date-only: same calendar day, different format → same-phase branch '
          '(keeps the later end), never the newer-local branch', () {
        final r = run(
          localStart: '2026-10-12T09:30:00.000',
          cloudStart: '2026-10-12',
          cloudEnd: '2026-10-25',
          localPhase: 4,
          cloudPhase: 3,
        );
        expect(r.planStart, '2026-10-12');
        expect(r.planEnd, '2026-11-08T00:00:00.000');
      });

      test('fresh install (null local start) → cloud even with phases set', () {
        final r = run(localStart: null, localEnd: null);
        expect(r.planStart, '2026-09-14T00:00:00.000');
      });

      test('switch off (keepNewerLocalPhase false) → pre-fix cloud-verbatim',
          () {
        final r = run(keep: false);
        expect(r.planStart, '2026-09-14T00:00:00.000');
        expect(r.planEnd, '2026-10-11T00:00:00.000');
      });
    });

    group('localWindowPinned (an advance is rewriting the window)', () {
      PlanWindowReanchor run({
        String? localStart = '2026-09-14T00:00:00.000',
        bool pinned = true,
      }) =>
          PlanWindowReanchor.resolve(
            localStart: localStart,
            localEnd: '2026-10-11T00:00:00.000',
            cloudStart: '2026-10-12T00:00:00.000',
            cloudEnd: '2026-11-08T00:00:00.000',
            localPlanPhase: 3,
            cloudPlanPhase: 3,
            localWindowPinned: pinned,
          );

      test('pinned with a local window → nothing is written', () {
        final r = run();
        expect(r.planStart, isNull);
        expect(r.planEnd, isNull);
      });
      test('pinned but NO local window (fresh install) → cloud verbatim', () {
        final r = run(localStart: null);
        expect(r.planStart, '2026-10-12T00:00:00.000');
        expect(r.planEnd, '2026-11-08T00:00:00.000');
      });
      test('not pinned → the pre-existing phase-advance rule (cloud wins)', () {
        final r = run(pinned: false);
        expect(r.planStart, '2026-10-12T00:00:00.000');
      });
    });

    group('callers pass the pin (presence only; the decision is above)', () {
      for (final f in [
        'lib/core/services/sync/sync_workout.dart',
        'lib/core/services/plan_integrity_reconciler.dart',
      ]) {
        test(f, () {
          final s = File(f).readAsStringSync();
          expect(
              RegExp(r'localWindowPinned:\s*planWindowPinnedByAdvance').hasMatch(s),
              isTrue);
          // ...and each of the two window writes re-checks it.
          expect(
              RegExp(r'reStart != null &&\s*!planWindowPinnedByAdvance')
                  .hasMatch(s),
              isTrue);
          expect(
              RegExp(r'reEnd != null &&\s*!planWindowPinnedByAdvance')
                  .hasMatch(s),
              isTrue);
        });
      }
    });

    group('blobPhase', () {
      test('reads an int, an integral double, and rejects the rest', () {
        expect(PlanWindowReanchor.blobPhase({'phase': 4}), 4);
        expect(PlanWindowReanchor.blobPhase({'phase': 4.0}), 4);
        expect(PlanWindowReanchor.blobPhase({'phase': 4.5}), isNull);
        expect(PlanWindowReanchor.blobPhase({'phase': '4'}), isNull);
        expect(PlanWindowReanchor.blobPhase({'week_plans': []}), isNull);
        expect(PlanWindowReanchor.blobPhase(null), isNull);
        expect(PlanWindowReanchor.blobPhase('x'), isNull);
      });
    });
  });
}
