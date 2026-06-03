import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/phase_progress_reconciler.dart';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

/// Behavioral test for the two-Phase-1 heal (diagnose a3f8c1): the reconciler's
/// monotonic decision advances a stuck counter to (completed blocks)+1 and NEVER
/// demotes / touches an already-consistent or free user.
void main() {
  group('reconciledPhase (monotonic heal decision)', () {
    test('stuck user: current_phase 1 + 1 completed block → advance to 2', () {
      expect(PhaseProgressReconciler.reconciledPhase(1, 1), 2);
    });

    test('consistent user: current_phase 2 + 1 block → no-op', () {
      expect(PhaseProgressReconciler.reconciledPhase(2, 1), isNull);
    });

    test('never demotes: current_phase 3 + 1 block → no-op (current ahead)', () {
      expect(PhaseProgressReconciler.reconciledPhase(3, 1), isNull);
    });

    test('free / new user: current_phase 1 + 0 blocks → no-op', () {
      expect(PhaseProgressReconciler.reconciledPhase(1, 0), isNull);
    });

    test('multi-block advance: current_phase 5 + 6 blocks → 7', () {
      expect(PhaseProgressReconciler.reconciledPhase(5, 6), 7);
    });

    test('implausible jump (>12 phases) is refused — corrupted-data guard', () {
      // current_phase 1 + 20 "blocks" (overlapping/corrupted schedule data) →
      // would advance to 21; monotonic over-advance is unrecoverable, so refuse.
      expect(PhaseProgressReconciler.reconciledPhase(1, 20), isNull);
      // boundary: +12 still advances, +13 refused.
      expect(PhaseProgressReconciler.reconciledPhase(1, 12), 13);
      expect(PhaseProgressReconciler.reconciledPhase(1, 13), isNull);
    });
  });

  group('wiring', () {
    final src = _strip(File(
            'lib/core/services/phase_progress_reconciler.dart')
        .readAsStringSync());
    final boot = _strip(File(
            'lib/features/auth/screens/restoring_screen.dart')
        .readAsStringSync());

    test('reconcile() uses the monotonic decision + kill-switch + plan_start guard',
        () {
      expect(src.contains('reconciledPhase('), isTrue);
      expect(src.contains('killSwitchKey'), isTrue);
      expect(src.contains('getPlanStartDate() == null'), isTrue);
    });

    test('runs on boot in restoring_screen (after restore + key migrators)', () {
      expect(boot.contains('PhaseProgressReconciler.reconcile('), isTrue);
    });
  });
}
