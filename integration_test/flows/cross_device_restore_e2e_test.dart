// audit-2026-05-11 Phase 7 — cross-device restore E2E.
//
// Critical untested flow: User A trains on Device 1 → all data
// syncs to cloud → User A signs into Device 2 (fresh install) →
// RestoringScreen → restoreFromCloud → home shows yesterday's
// workout + streak + saved meals + diet plan + freezes + ranks.
//
// Per docs/architecture/sync.md "Restore-completeness sync" (Theme A from Test
// #11) and audit-2026-05-11 H-13 fix: the restore must cover every
// Hive-only surface a paying user expects on a new device.
//
// Run:
//   flutter test --dart-define-from-file=.env \
//     integration_test/flows/cross_device_restore_e2e_test.dart \
//     --flavor dev

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Cross-device restore E2E', () {
    test('T1 — workout logs (exlog_* + wlog_*) restored', () {
      // Verify restored exlog_*/wlog_* match the cloud rows by
      // deterministic key (post-H-16 v5 UUID formula).
    }, skip: 'Phase 7 scaffold — needs 2-device harness.');

    test('T2 — nutrition logs (nlog_*) + items[] restored', () {
      // H-17 deterministic v5 hash means cloud → Hive lands at the
      // same nlog_<date>_<meal>_<v5hash> key as the original write.
    }, skip: 'Phase 7 scaffold — needs 2-device harness.');

    test('T3 — saved meals (saved_meal_*) restored', () {
      // Theme A1 of Test #11 covers this; ensure paying users
      // don\'t lose their meal templates on reinstall.
    }, skip: 'Phase 7 scaffold — needs 2-device harness.');

    test('T4 — custom exercises restored as per-key (H-13 fix)', () {
      // _restoreCustomExercises now writes `custom_exercise_<cloud_id>`
      // entries. Verify they appear in YOUR EXERCISES section + sync
      // back to cloud on next launch (no infinite drift).
    }, skip: 'Phase 7 scaffold — needs 2-device harness.');

    test('T5 — streak freezes + used_dates + last_refill restored', () {
      // Theme A2 + C-15 StreakProgressService. Verify Hive freeze
      // state matches cloud after restore.
    }, skip: 'Phase 7 scaffold — needs 2-device harness.');

    test('T6 — saved diet plan restored', () {
      // Theme A5 + saved_diet_plans cloud table.
    }, skip: 'Phase 7 scaffold — needs 2-device harness.');

    test('T7 — rank_promotions history restored (last 20)', () {
      // Theme A4 + rank_promotions cloud table.
    }, skip: 'Phase 7 scaffold — needs 2-device harness.');

    test('T8 — notifications_inbox restored', () {
      // Theme A3 + notifications_inbox cloud table.
    }, skip: 'Phase 7 scaffold — needs 2-device harness.');

    test('T9 — PRO subscription re-verified via verifyFromServer(force: true)',
        () {
      // Final step of restoreFromCloudForUser. Pre-fix this was a
      // separate post-auth hook and could race the restore.
    }, skip: 'Phase 7 scaffold — needs 2-device harness.');
  });
}
