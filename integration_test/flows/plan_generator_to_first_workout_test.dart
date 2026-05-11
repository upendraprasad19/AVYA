// audit-2026-05-11 Phase 7 — plan generator → first workout.
//
// Critical untested flow: onboarding completion → PlanGenerator.generateV4
// → 4-week schedule → today's first workout shows on home → tap
// Start Workout → active workout opens with correct logging types.
//
// Plan generator is the "untouchable" subsystem per CLAUDE.md rule 14
// (never modify without explicit approval). The integration test
// guards against silent regressions in the cascade depth, target-count
// targeting, and logging-type resolution.
//
// Run:
//   flutter test --dart-define-from-file=.env \
//     integration_test/flows/plan_generator_to_first_workout_test.dart \
//     --flavor dev

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Plan generator → first workout', () {
    test('T1 — intermediate / 4 days / full_gym → 28 schedule entries (4 weeks × 7)',
        () {
      // Phase 1 is always 4 weeks. Each day has either a workout or
      // rest day entry.
    }, skip: 'Phase 7 scaffold — needs onboarding fixture user.');

    test('T2 — workout days have exercise count matching VolumeFilter.targetCount(intermediate, 4) = 7',
        () {
      // Per CLAUDE.md §12 table: intermediate × 4-day = 7 exercises/day.
    }, skip: 'Phase 7 scaffold — needs onboarding fixture user.');

    test('T3 — cascade attempts stay within attempt1 / 2 for build_muscle / full_gym',
        () {
      // Use sample_plans_report-style diagnostics. Target: 0
      // attempt3/universalPool/(none) for the canonical combos.
    }, skip: 'Phase 7 scaffold — needs onboarding fixture user.');

    test('T4 — Start Workout opens correct logging_type per exercise', () {
      // F7 (Test #2) LoggingTypeResolver: bench_press → weight_reps,
      // plank → timed, run → cardio. Verify each renders correct
      // input columns.
    }, skip: 'Phase 7 scaffold — needs onboarding fixture user.');

    test('T5 — beginner foundational pool: Phase 1 only beginner-foundational exercises',
        () {
      // queryV4 requires `suitable_for` contains "Beginner" AND
      // `is_foundational: true` for Phase 1.
    }, skip: 'Phase 7 scaffold — needs onboarding fixture user.');
  });
}
