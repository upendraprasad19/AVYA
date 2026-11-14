// audit-2026-05-11 Phase 7 — streak freeze refill ↔ consume.
//
// Critical untested flow: C-15 StreakProgressService is the sole
// writer for streak_freezes_*. Concurrent paths (weekly refill from
// home_provider + missed-day consume from train_provider.completeWorkout)
// must produce deterministic state. Migration 056 adds an
// optimistic-lock RPC for the cross-device case; this flow covers
// the same-process + cross-device interleave end-to-end.
//
// Run:
//   flutter test --dart-define-from-file=.env \
//     integration_test/flows/streak_freeze_concurrency_test.dart \
//     --flavor dev

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Streak freeze refill ↔ consume', () {
    test('T1 — Monday refill bumps available 0→1 (free) and 0→1 (PRO ladder)',
        () {
      // PRO refills at +1/week capped at 3. Free caps at 1.
    }, skip: 'Phase 7 scaffold — needs device + monotonic-clock harness.');

    test('T2 — missed-day consume burns 1 freeze + preserves streak count',
        () {
      // Walk-back encounters missed scheduled-workout day; freeze
      // available; consume → streak count unchanged.
    }, skip: 'Phase 7 scaffold — needs device + monotonic-clock harness.');

    test('T3 — three rapid currentStreak() reads do NOT consume freezes (C-14)',
        () {
      // CQRS split: pure read must not mutate state. Sibling of the
      // streak_currentstreak_is_pure_test contract test.
    }, skip: 'Phase 7 scaffold — needs device + monotonic-clock harness.');

    test('T4 — optimistic-lock RPC retries on version mismatch (C-15)', () {
      // Manually bump streak_progress_version cloud-side then trigger
      // a client write. Verify the client read-modify-write loop
      // retries with the latest version.
    }, skip: 'Phase 7 scaffold — needs device + monotonic-clock harness.');
  });
}
