// audit-2026-05-11 Phase 7 — workout completion → receipt → share.
//
// Critical untested flow: Active Workout → log sets → COMPLETE
// WORKOUT → WorkoutReceiptCard → SHARE → native share sheet. The
// receipt-rendering bug class (Test #7 ship — receipt rendered
// "0 sets" because reader filtered on missing field) lives in this
// flow; we now have field-contract tests but the actual cross-
// surface integration is uncovered.
//
// Run:
//   flutter test --dart-define-from-file=.env \
//     integration_test/flows/workout_completion_receipt_share_test.dart \
//     --flavor dev

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Workout completion → receipt → share', () {
    test('T1 — log 3 sets on Bench Press, complete → receipt shows 3 sets',
        () {
      // The C-8 / C-14 / contract-test combo guards against the
      // "0 sets" regression. Run end-to-end on a real device.
    }, skip: 'Phase 7 scaffold — needs device harness.');

    test('T2 — receipt shows correct total volume + per-set chips', () {
      // WardSetChips primitive (Test #12 Theme E) renders both
      // total volume + the per-set chip Wrap.
    }, skip: 'Phase 7 scaffold — needs device harness.');

    test('T3 — SHARE button opens native share sheet with PNG', () {
      // QR code at the bottom should encode www.icanbefitter.com.
    }, skip: 'Phase 7 scaffold — needs device harness.');

    test('T4 — multi-session same day → receipt scoped by workout_log_id (T12 Theme A)',
        () {
      // C-8 + receipt scoping fix: two sessions same IST day each get
      // their own receipt, NOT a combined receipt.
    }, skip: 'Phase 7 scaffold — needs device harness.');

    test('T5 — home "View Card" reopens the same receipt', () {
      // Single source of truth: WorkoutReceiptData.fromExerciseLogs
      // reads Hive exlog_* index; same data should render whether
      // from active-workout completion or home View Card.
    }, skip: 'Phase 7 scaffold — needs device harness.');
  });
}
