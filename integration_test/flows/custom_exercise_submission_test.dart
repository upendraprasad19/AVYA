// audit-2026-05-11 Phase 7 — custom exercise submission flow.
//
// Critical untested flow: Train → + CREATE → CreateCustomExerciseSheet
// → save with "Share with community" → custom_exercise_<ts> row in
// Hive + user_custom_exercises cloud row + appears in YOUR EXERCISES.
// Admin reviews via promote-community-item → approved_for_library →
// next syncCommunityItems run pulls it into the global exercise_library.
//
// H-13 fix (audit-2026-05-11): _restoreCustomExercises now writes
// per-key entries so restored items remain visible. The H-14 fix
// paginates syncCommunityItems. Both need end-to-end coverage.
//
// Run:
//   flutter test --dart-define-from-file=.env \
//     integration_test/flows/custom_exercise_submission_test.dart \
//     --flavor dev

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Custom exercise submission flow', () {
    test('T1 — submit custom exercise writes `custom_exercise_*` per-key entry',
        () {
      // Per docs/architecture/sync.md SoT contract. Verify Hive key shape +
      // cloud user_custom_exercises row.
    }, skip: 'Phase 7 scaffold — needs Supabase test mode.');

    test('T2 — YOUR EXERCISES chip appears immediately (ValueListenableBuilder)',
        () {
      // D6 fix from Test #1: ValueListenableBuilder<customBox>
      // renders the new exercise instantly with DRAFT badge.
    }, skip: 'Phase 7 scaffold — needs Supabase test mode.');

    test('T3 — H-13: restore from cloud writes per-key entries (not legacy list)',
        () {
      // Sign out + sign in on same device → custom_exercise_<cloud_id>
      // entries appear; legacy `custom_exercises` list key absent.
    }, skip: 'Phase 7 scaffold — needs Supabase test mode.');

    test('T4 — promote-community-item admin gate rejects non-admin', () {
      // 7ad0c5 C-5 fix: anon JWT + non-admin JWT → 403. Service-role
      // OR ADMIN_USER_IDS contains caller → success.
    }, skip: 'Phase 7 scaffold — needs Supabase test mode + admin JWT.');

    test('T5 — H-14: syncCommunityItems paginates (500/page, 10-page ceiling)',
        () {
      // Seed > 500 approved community exercises; verify the next
      // sync downloads exactly 500 per request + stops at 5000.
    }, skip: 'Phase 7 scaffold — needs Supabase test mode + seed harness.');
  });
}
