/// ICANBEFITTER — Integration Test Runner
///
/// Runs all 5 critical user flow tests against the dev flavor
/// (local Supabase + Razorpay test key).
///
/// How to run:
///   flutter test integration_test/ --flavor dev -t lib/main_dev.dart -d <device-id>
///
/// Prerequisites:
///   1. Local Supabase running: `supabase start`
///   2. Android emulator running: `flutter emulators --launch <emulator-id>`
///   3. OR physical device connected: `flutter devices`
///
/// Test user: qa@icanbefitter.com / QA_Test_2024!  (local Supabase only)
///
/// Supabase local URL used by dev flavor: http://10.0.2.2:54321
/// (10.0.2.2 = host machine from Android emulator perspective)

// Individual flow test files — run together or separately.
// Each file is self-contained and can be run independently:
//   flutter test integration_test/flows/auth_flow_test.dart --flavor dev -t lib/main_dev.dart -d <device>

export 'flows/auth_flow_test.dart';
export 'flows/workout_log_flow_test.dart';
export 'flows/meal_log_flow_test.dart';
export 'flows/ai_coach_flow_test.dart';
export 'flows/pro_gate_flow_test.dart';
