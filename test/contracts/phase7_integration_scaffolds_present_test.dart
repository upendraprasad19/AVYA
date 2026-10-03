// audit-2026-05-11 Phase 7 — guardrail asserting the 10 integration
// test scaffolds exist on disk. Each scaffold is currently `skip:`d
// because it needs device + Supabase/Razorpay test-mode + (in some
// cases) admin JWT / fixture-user provisioning. The scaffolds are
// the contract; the bodies are Phase 8 / future-batch work.
//
// If a scaffold vanishes, this test fails — preventing silent loss
// of the documented invariant set.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 7 integration test scaffolds present', () {
    const scaffolds = <String>[
      'integration_test/flows/razorpay_purchase_flow_test.dart',
      'integration_test/flows/signup_onboarding_traverse_test.dart',
      'integration_test/flows/delete_account_e2e_test.dart',
      'integration_test/flows/cross_account_isolation_e2e_test.dart',
      'integration_test/flows/cross_device_restore_e2e_test.dart',
      'integration_test/flows/workout_completion_receipt_share_test.dart',
      'integration_test/flows/streak_freeze_concurrency_test.dart',
      'integration_test/flows/plan_generator_to_first_workout_test.dart',
      'integration_test/flows/custom_exercise_submission_test.dart',
      'integration_test/flows/promo_code_apply_test.dart',
      'integration_test/flows/ai_coach_tools_e2e_test.dart',
    ];

    for (final path in scaffolds) {
      test('scaffold present: $path', () {
        final f = File(path);
        expect(f.existsSync(), isTrue,
            reason: 'Phase 7 integration scaffold must exist: $path');
        final src = f.readAsStringSync();
        expect(src.contains('IntegrationTestWidgetsFlutterBinding'), isTrue,
            reason: '$path must call IntegrationTestWidgetsFlutterBinding.ensureInitialized().');
        // Body is Phase 8 work; for now every test should be skip:'d
        // so the scaffold doesn't fail CI when run by accident.
        expect(
          src.contains("skip: 'Phase 7 scaffold"),
          isTrue,
          reason: '$path tests must be marked `skip: \'Phase 7 scaffold...\'` '
              'until the device-CI harness is in place.',
        );
      });
    }
  });
}
