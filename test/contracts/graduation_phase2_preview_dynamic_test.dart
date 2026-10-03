// test/contracts/graduation_phase2_preview_dynamic_test.dart
//
// Contract — Theme J (closes-diagnose 14e8a5).
//
// Pins the dynamic Phase 2 preview, extracted 2026-08-03 (Unit B / OI-84)
// from graduation_screen.dart into phase2_preview_card.dart. Pre-fix
// the card hardcoded `5 DAYS/WEEK · WEEKS 5-8 · POWER + HYPERTROPHY`
// + 5 day-name rows (`Day 1: Upper Power`, `Day 2: Lower Power`, …).
// For a 4-day-per-week user, the preview misrepresented their actual
// next phase (the real generateAndSchedule at line 533 uses
// profile.days_per_week dynamically — only the preview was wrong).
//
// Fix: dry-run PlanGenerator.generateV4 with the user's actual profile
// + next phase number. Reuses the SAME PURE call used by
// previewPlanProvider (lib/features/train/providers/preview_plan_provider.dart:94)
// and workout_schedule_read_service.generateAndSchedule.
//
// Source-grep with comment-stripping per
// `feedback_source_grep_strip_comments_first.md`.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _strip(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');

void main() {
  late String src;

  setUpAll(() {
    // Unit B / OI-84 (2026-08-03): the preview card moved OUT of
    // graduation_screen.dart into its own widget file. Re-pointed rather than
    // deleted — every assertion below is about the preview's DATA FLOW, which
    // the move did not touch. Reading the old path would have made all of them
    // vacuously true against a file that no longer contains the code.
    src = _strip(
        File('lib/features/train/widgets/phase2_preview_card.dart')
            .readAsStringSync());
  });

  test('graduation_screen actually RENDERS the extracted card', () {
    // The guard that keeps this whole file honest after the extraction. Every
    // other test here reads phase2_preview_card.dart, so they would all still
    // pass if the widget were perfect but ORPHANED — never rendered by the
    // screen it exists for. This is the only assertion that can catch that,
    // and it is why the extraction did not simply re-point the greps.
    final screen = _strip(
        File('lib/features/train/screens/graduation_screen.dart')
            .readAsStringSync());
    expect(screen.contains('const Phase2PreviewCard()'), isTrue,
        reason: 'graduation_screen must render Phase2PreviewCard');
    expect(screen.contains('const Phase2BenefitsCard()'), isTrue,
        reason: 'graduation_screen must render Phase2BenefitsCard');
    expect(
      screen.contains(
          "import 'package:icanbefitter/features/train/widgets/phase2_preview_card.dart'"),
      isTrue,
      reason: 'and must import them — a render without the import will not '
          'compile, but pinning both makes the failure legible.',
    );
  });

  test('Phase2PreviewCard reads UserRepository.getProfile + getProgress',
      () {
    final idx = src.indexOf('class Phase2PreviewCard');
    expect(idx, greaterThan(-1));
    // Take a window for the method body.
    final body = src.substring(idx, idx + 5000);
    expect(
      body.contains('UserRepository.instance.getProfile()'),
      isTrue,
      reason: 'preview must read profile via UserRepository so the '
          'rendered preview reflects the user\'s actual days_per_week, '
          'goal, equipment, experience.',
    );
    expect(
      body.contains('UserRepository.instance.getProgress()'),
      isTrue,
      reason: 'preview must read progress to derive nextPhase from '
          'current_phase (matches the unlock CTA logic).',
    );
  });

  test('Phase2PreviewCard calls PlanGenerator.generateV4 (pure, no Hive)',
      () {
    final idx = src.indexOf('class Phase2PreviewCard');
    final body = src.substring(idx, idx + 5000);
    expect(
      body.contains('PlanGenerator.instance.generateV4'),
      isTrue,
      reason: 'preview must dry-run PlanGenerator.generateV4 — the same '
          'pure call previewPlanProvider + workout_schedule_read_service'
          '.generateAndSchedule already use. NO Hive writes from this '
          'preview path.',
    );
  });

  test('hardcoded "5 DAYS/WEEK · WEEKS 5-8 · POWER + HYPERTROPHY" is GONE',
      () {
    expect(
      src.contains("'5 DAYS/WEEK · WEEKS 5-8 · POWER + HYPERTROPHY'"),
      isFalse,
      reason: 'the pre-fix literal must be removed — the meta line is '
          'now computed from `daysPerWeek`, `(nextPhase-1)*4+1`, '
          '`nextPhase*4`, and the phase focus.',
    );
  });

  test('hardcoded day-label rows are GONE', () {
    // Pre-fix five string literals. All must be absent.
    const banned = [
      "'Day 1: Upper Power'",
      "'Day 2: Lower Power'",
      "'Day 3: Rest & Mobility'",
      "'Day 4: Upper Hypertrophy'",
      "'Day 5: Lower Hypertrophy'",
    ];
    for (final lit in banned) {
      expect(
        src.contains(lit),
        isFalse,
        reason: '$lit must be removed — day labels now come from '
            'phase.weekPlans[0].workoutDays[i].name (real plan output).',
      );
    }
  });

  test('day rows render WorkoutDay.name from the generator output', () {
    // The new render uses `previewDays[i].title` which is populated from
    // `d.name` of the WorkoutDay. Pin the data-flow shape.
    final idx = src.indexOf('class Phase2PreviewCard');
    final body = src.substring(idx, idx + 5000);
    expect(
      body.contains('.workoutDays'),
      isTrue,
      reason: 'must read .workoutDays from the generated Phase '
          'weekPlans — that\'s the canonical shape exposed by '
          'PlanGenerator.generateV4.',
    );
    expect(
      RegExp(r'd\.name|workoutDay\.name|\.title').hasMatch(body),
      isTrue,
      reason: 'must surface each workout day\'s name (e.g. '
          '"Upper Power", "Lower Hypertrophy") as the day-row label.',
    );
  });

  test('meta line uses dynamic daysPerWeek + nextPhase week range', () {
    final idx = src.indexOf('class Phase2PreviewCard');
    final body = src.substring(idx, idx + 5000);
    expect(
      body.contains('\$daysPerWeek DAYS/WEEK'),
      isTrue,
      reason: 'meta line must interpolate `daysPerWeek` — pre-fix was '
          'literal "5 DAYS/WEEK".',
    );
    // Week range computed from nextPhase (e.g. Phase 2 → WEEKS 5-8,
    // Phase 3 → WEEKS 9-12).
    expect(
      body.contains('(nextPhase - 1) * 4 + 1') ||
          body.contains('weekRange'),
      isTrue,
      reason: 'meta line must compute the week range from nextPhase '
          '(Phase 2 → 5-8, Phase 3 → 9-12, etc.) — not hardcoded "5-8".',
    );
  });

  test('phase chip label + phase title come from the next phase number',
      () {
    final idx = src.indexOf('class Phase2PreviewCard');
    final body = src.substring(idx, idx + 5000);
    expect(
      body.contains('phaseLabel'),
      isTrue,
      reason: 'chip label must derive from nextPhase (e.g. PHASE 2, '
          'PHASE 3, …) — pre-fix was hardcoded "PHASE 2".',
    );
    expect(
      body.contains('_phaseDisplayName') ||
          body.contains('phaseTitle'),
      isTrue,
      reason: 'phase title must come from the canonical per-phase '
          'display-name map, not hardcoded "Progressive Overload".',
    );
  });

  test('failure path emits telemetry + falls back gracefully', () {
    expect(
      src.contains("'graduation_phase2_preview_failed'"),
      isTrue,
      reason: 'if generateV4 throws, must emit '
          'graduation_phase2_preview_failed telemetry so we get a '
          'signal in client_errors.',
    );
    // Fallback render: a single descriptive line so the surface
    // remains useful even on plan-generator failure.
    expect(
      src.contains('workout days personalised'),
      isTrue,
      reason: 'fallback copy must keep the surface meaningful when the '
          'plan-generator throws.',
    );
  });
}
