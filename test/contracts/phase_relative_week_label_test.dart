import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';

/// Regression for the phase/week label drift (diagnose 2026-06-06).
///
/// `getCurrentWeekNumber()` correctly returns the week WITHIN the 4-week phase
/// (1-4, clamped). Pre-fix three readers printed it as the 12-week program week
/// ("WEEK n OF 12" / `n/12 %`), so the counter stuck ≤4 / ≤33% and the banner
/// hardcoded "FOUNDATION" regardless of phase. The founder chose phase-relative
/// labels: headline "PHASE 2 · STRENGTH · WK 3 OF 4"; the Roadmap keeps the
/// 12-week map but uses the true program week.
String _strip(String s) => s
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  group('phaseNameFor (canonical phase name from the number)', () {
    test('1→Foundation, 2→Strength, 3→Hypertrophy', () {
      expect(WorkoutScheduleReadService.phaseNameFor(1), 'Foundation');
      expect(WorkoutScheduleReadService.phaseNameFor(2), 'Strength');
      expect(WorkoutScheduleReadService.phaseNameFor(3), 'Hypertrophy');
    });

    test('cycles each deployment (phase 4 → Foundation) + guards phase < 1',
        () {
      expect(WorkoutScheduleReadService.phaseNameFor(4), 'Foundation');
      expect(WorkoutScheduleReadService.phaseNameFor(5), 'Strength');
      expect(WorkoutScheduleReadService.phaseNameFor(0), 'Foundation');
    });
  });

  group('programWeekFor (12-week deployment week)', () {
    test('Phase 1 wk 3 → 3; Phase 2 wk 3 → 7; Phase 3 wk 1 → 9', () {
      expect(WorkoutScheduleReadService.programWeekFor(1, 3), 3);
      expect(WorkoutScheduleReadService.programWeekFor(2, 3), 7);
      expect(WorkoutScheduleReadService.programWeekFor(3, 1), 9);
    });

    test('cycles per deployment (phase 4 wk 2 → 2)', () {
      expect(WorkoutScheduleReadService.programWeekFor(4, 2), 2);
    });
  });

  group('wiring', () {
    final banner = _strip(
        File('lib/features/train/screens/train/screen.dart')
            .readAsStringSync());
    final roadmap = _strip(
        File('lib/features/train/screens/phase_roadmap_screen.dart')
            .readAsStringSync());
    final plannedExpansion = File(
            'lib/features/train/screens/train/planned_expansion.dart')
        .readAsStringSync();
    final hero = File('lib/features/train/screens/train/hero_cards.dart')
        .readAsStringSync();

    test('Train deployment banner is phase-relative (no hardcoded FOUNDATION '
        'or "OF 12")', () {
      // UPDATED 2026-08-30 (diagnose b7f1c8): the banner's inline ternary was
      // extracted into the pure formatter `deploymentEyebrowLabel`
      // (lib/core/utils/hold_week_labels.dart), so the phase name and the
      // "WK n OF 4" literal now live there. The banner's job is to pass the
      // real per-account values IN — which is the half this test exists to
      // pin, and which the extraction made checkable rather than weaker:
      // the deployment NUMBER was a hardcoded '01' for every account at every
      // phase until this batch, and no test here could see it because the
      // grep only ever looked at the phase name and week.
      final labels = _strip(
          File('lib/core/utils/hold_week_labels.dart').readAsStringSync());

      expect(banner.contains('deploymentEyebrowLabel('), isTrue,
          reason: 'the eyebrow must route through the extracted formatter');
      expect(banner.contains('phase: plan.phase'), isTrue,
          reason: 'the DEPLOYMENT number must come from the real phase — it '
              'was a hardcoded "01" for every account until diagnose b7f1c8');
      expect(banner.contains('phaseName: plan.phaseName'), isTrue);
      expect(banner.contains('currentWeek: plan.currentWeek'), isTrue);

      expect(labels.contains(r'WK $currentWeek OF 4'), isTrue,
          reason: 'the week-within-phase counter must still be 1-4, not a '
              '12-week program week');
      expect(labels.contains('DEPLOYMENT 01 — FOUNDATION'), isFalse,
          reason: 'the hardcoded FOUNDATION / OF 12 banner must be gone');
      expect(banner.contains('DEPLOYMENT 01'), isFalse,
          reason: 'no hardcoded deployment number may survive in the screen');
      expect(banner.contains('OF 12)'), isFalse);
    });

    test('Roadmap header uses the program week (not the 1-4 phase week)', () {
      expect(roadmap.contains('getProgramWeek('), isTrue,
          reason: 'Roadmap must compute % + active phase from the 12-week '
              'program week, not getCurrentWeekNumber (1-4)');
    });

    test('START WORKOUT is gated on a non-empty plan (not in the empty branch)',
        () {
      // The button must NOT live in the `day.exercises.isEmpty` branch — that
      // branch only shows "No exercises scheduled". Pre-fix START rendered
      // unconditionally and called startWorkout(day) with nothing to log.
      final emptyIdx = plannedExpansion.indexOf('day.exercises.isEmpty');
      final elseIdx = plannedExpansion.indexOf('else ...[', emptyIdx);
      expect(emptyIdx, greaterThan(-1));
      expect(elseIdx, greaterThan(emptyIdx));
      final emptyBranch = plannedExpansion.substring(emptyIdx, elseIdx);
      expect(emptyBranch.contains('START WORKOUT'), isFalse,
          reason: 'START must not render when the day has no exercises');
      expect(plannedExpansion.contains('START WORKOUT'), isTrue,
          reason: 'START must still exist for days that DO have a plan');
    });

    test('hero Today card gates START on a non-empty plan (primary surface)',
        () {
      // The expanded view is not the only START surface — the hero card is the
      // primary one. A content-less day must render _buildEmptyWorkoutHeroCard,
      // never a dead START (review P1 2026-06-06).
      expect(hero.contains('todayWorkout.exercises.isNotEmpty'), isTrue,
          reason: 'hero Today card must gate START on non-empty exercises');
      expect(hero.contains('_buildEmptyWorkoutHeroCard'), isTrue);
    });
  });
}
