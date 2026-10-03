// audit-2026-05-11 Phase 7 — cross-account isolation E2E.
//
// Critical untested flow: sign in as User A → log a workout → sign
// out → sign in as User B (different email) → User A's workout MUST
// NOT appear in B's home/train/receipts/AI snapshot. This is the
// canonical regression test for the namespaced-Hive Plan A landing
// (Test #5) + C-6 cross-account guard fix (audit-2026-05-11) +
// _performSignOut → AuthNotifier.signOut routing (C-10).
//
// Run:
//   flutter test --dart-define-from-file=.env \
//     integration_test/flows/cross_account_isolation_e2e_test.dart \
//     --flavor dev

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Cross-account isolation E2E', () {
    test('T1 — User A logs workout, signs out → on-disk namespaced files for A only',
        () {
      // HiveUserSession.deleteAllFilesForCurrentUser is called on
      // signOut. After sign-out, A's `workoutBox_<hashA>` is deleted
      // from disk.
    }, skip: 'Phase 7 scaffold — needs 2 test user accounts.');

    test('T2 — User B sign-in opens NEW namespaced files, sees zero of A\'s data',
        () {
      // openForUser(B) opens `workoutBox_<hashB>` (different file).
      // No exlog_* rows, no schedule_* rows, no streak data.
    }, skip: 'Phase 7 scaffold — needs 2 test user accounts.');

    test('T3 — C-6 cross-account guard fires on Android Auto Backup restore', () {
      // Simulate AAB restore: copy A\'s files into B\'s namespaced
      // box pre-openForUser. Verify openForUser detects the
      // mismatched profile.id and clears.
    }, skip: 'Phase 7 scaffold — needs simulated AAB restore harness.');

    test('T4 — C-10: _performSignOut path runs through AuthNotifier.signOut', () {
      // Profile → Sign Out tap → verify the deleteAllFilesForCurrentUser
      // call AND state reset to AuthStatus.idle.
    }, skip: 'Phase 7 scaffold — needs 2 test user accounts.');

    test('T5 — re-sign-in as A restores from cloud (cold-start scenario)', () {
      // After sign-out, sign back in as A on the same device.
      // Restore path pulls cloud workout_logs back into Hive.
    }, skip: 'Phase 7 scaffold — needs 2 test user accounts.');
  });
}
