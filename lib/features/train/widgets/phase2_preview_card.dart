import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/repositories/plan_generator.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// The graduation screen's "what you're about to unlock" cards.
///
/// **Unit B / OI-84.** Extracted verbatim from `graduation_screen.dart`, where
/// these two builders plus their three file-private helpers were ~250 lines of
/// a 909-line file that survived Gate 43's 800-line ceiling only on an
/// allow-list entry. The rendered OUTPUT is identical: both builders already
/// took no `ref`, no `BuildContext` and touched no widget state.
///
/// **One thing genuinely did change, and it is not "nothing"** (round-1 review
/// caught the overclaim). Previously these were METHOD CALLS evaluated inside
/// `ListView(children: [...])`, so `generateV4` ran eagerly during every
/// `GraduationScreen.build()`. They are now `const` widgets, so `build()` runs
/// when the element mounts — lazily, per `SliverChildListDelegate`'s
/// viewport + `cacheExtent` — and a `const` instance is canonicalized, so the
/// card does not rebuild when the parent does. Two consequences, both accepted
/// deliberately:
///   - A full plan generation no longer runs on every unrelated parent
///     rebuild. That is strictly better; running `generateV4` on each
///     `graduationStatsProvider` tick was waste.
///   - `graduation_phase2_preview_failed` now fires roughly ONCE PER MOUNT
///     (~per screen-open) instead of on every parent rebuild — the const
///     instance is identity-equal, so `Element.updateChild` short-circuits it.
///     This does not lose failure signal — a generation that never
///     runs cannot fail — but it does change the metric's denominator, so
///     rate comparisons against samples from before 2026-08-03 are not
///     like-for-like.
///
/// The inputs (profile, `current_phase`) cannot change while this screen is
/// displayed, so pinning them at mount costs nothing.
///
/// They live in `widgets/` rather than as `part` files because they are
/// genuinely reusable, self-contained cards — the reference `part`-style layout
/// (`screens/active_workout/`) is for splitting one screen's own stateful guts,
/// which these are not.

/// Theme J (diagnose 2026-05-23 14e8a5) — dry-runs the REAL plan generator with
/// the user's actual profile and renders the returned day split, day names
/// visible and exercise names blurred.
///
/// Pre-fix this was hardcoded to '5 DAYS/WEEK · WEEKS 5-8 · POWER + HYPERTROPHY'
/// plus a static 5-day template. For a 4-day-per-week user that misrepresents
/// what they are about to unlock, because the actual `generateAndSchedule` on
/// unlock uses their real `days_per_week` and produces a different split.
///
/// Pure: no Hive writes, no side effects — the same code path
/// `previewPlanProvider` uses.
class Phase2PreviewCard extends StatelessWidget {
  const Phase2PreviewCard({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = UserRepository.instance.getProfile() ?? {};
    final progress = UserRepository.instance.getProgress() ?? {};
    final currentPhase = (progress['current_phase'] as int?) ?? 1;
    // 2026-05-31 (post-12 deployment cycles): phase number is MONOTONIC so
    // deployments_complete keeps counting. The plan engine recycles the
    // advanced phase-9-12 CONTENT internally (PlanGenerator._getPhaseMeta +
    // periodization) — the number itself never cycles back.
    final nextPhase = currentPhase + 1;
    final daysPerWeek = (profile['days_per_week'] as num?)?.toInt() ?? 4;
    final goal = profile['primary_goal'] as String? ?? 'general_fitness';
    final equipment = profile['equipment_access'] as String? ?? 'basic_gym';
    final experienceLevel =
        profile['fitness_experience'] as String? ?? 'intermediate';
    final injuries = (profile['injuries'] as List?)
            ?.whereType<String>()
            .where((s) => s != 'none')
            .toList() ??
        const <String>[];

    // Phase title + focus line. Phase 2 (Progressive Overload) was the
    // canonical pre-fix copy; later phases extend the same pattern.
    final phaseLabel = 'PHASE $nextPhase';
    final weekRange = 'WEEKS ${(nextPhase - 1) * 4 + 1}-${nextPhase * 4}';

    // Try the real plan generator; fall back to a single summary line
    // if the call throws (defensive — never block graduation render).
    List<_PreviewDay>? previewDays;
    String? phaseTitle;
    String? focus;
    try {
      final phase = PlanGenerator.instance.generateV4(
        goal: goal,
        equipment: equipment,
        daysPerWeek: daysPerWeek,
        phase: nextPhase,
        experienceLevel: experienceLevel,
        injuries: injuries,
      );
      phaseTitle = _phaseDisplayName(nextPhase);
      focus = _phaseFocus(nextPhase);
      final firstWeek =
          phase.weekPlans.isNotEmpty ? phase.weekPlans.first : null;
      final days = firstWeek?.workoutDays ?? phase.workouts;
      previewDays = days
          .take(5)
          .map((d) => _PreviewDay(
                title: d.name,
                exercises:
                    d.exercises.take(3).map((e) => e.exerciseName).join(', '),
              ))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase2PreviewCard] $e\n$st');
      unawaited(ErrorTelemetry.logEvent('graduation_phase2_preview_failed',
          message:
              'phase=$nextPhase err=${e.toString().substring(0, e.toString().length.clamp(0, 200))}'));
    }

    return WardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              WardChip(label: phaseLabel, tone: WardChipTone.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  phaseTitle ?? 'Progressive Overload',
                  style: AppTypography.h3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$daysPerWeek DAYS/WEEK · $weekRange · '
            '${focus ?? "Power + Hypertrophy".toUpperCase()}',
            style: AppTypography.monoXs.copyWith(
              color: AppColors.textDim,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 14),

          // Day names visible (actual generator output), exercise names blurred.
          // Local non-nullable alias so List.generate closure captures a
          // promoted type (Dart flow analysis doesn't promote across
          // closure boundaries).
          if (previewDays != null && previewDays.isNotEmpty) ...[
            for (final entry in previewDays.asMap().entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Day ${entry.key + 1}: ${entry.value.title}',
                      style: AppTypography.h3.copyWith(fontSize: 13),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                        child: Text(
                          entry.value.exercises.isNotEmpty
                              ? entry.value.exercises
                              : 'Exercises personalised to you...',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.textDim,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ]
          else
            // Defensive fallback when generateV4 throws — single
            // descriptive line keeps the surface meaningful.
            Text(
              '$daysPerWeek workout days personalised to your goal + equipment',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.textDim,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }
}

/// Static "WHAT PHASE 2 UNLOCKS" benefit list shown under the preview.
class Phase2BenefitsCard extends StatelessWidget {
  const Phase2BenefitsCard({super.key});

  @override
  Widget build(BuildContext context) {
    const benefits = [
      'New exercises with progressive overload',
      'Power + hypertrophy split for faster gains',
      'AI-personalised workout adjustments',
      'Advanced coaching cues and PRO tips',
      'Phases 2-12 unlock full 48-week journey',
    ];

    return WardCard(
      variant: WardCardVariant.inset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHAT PHASE 2 UNLOCKS',
            style: AppTypography.mono.copyWith(
              color: AppColors.textMute,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 10),
          ...benefits.map((benefit) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.accent,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        benefit,
                        style: AppTypography.body,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

/// Theme J — preview day cell used by graduation phase 2 card. Holds the
/// generated workout-day name + a comma-joined string of the first 3
/// exercises (rendered behind a blur to tease without revealing).
class _PreviewDay {
  final String title;
  final String exercises;
  const _PreviewDay({required this.title, required this.exercises});
}

/// Display name per phase. Mirrors the canonical plan-generator copy.
/// Falls back to `'Phase $n'` if the phase number is outside 1-12.
String _phaseDisplayName(int phase) {
  const names = {
    1: 'Foundation',
    2: 'Progressive Overload',
    3: 'Intensification',
    4: 'Power Build',
    5: 'Hypertrophy Peak',
    6: 'Strength Cycle',
    7: 'Conditioning Push',
    8: 'Power Hypertrophy',
    9: 'Specialisation',
    10: 'Strength Peak',
    11: 'Conditioning Peak',
    12: 'Mastery',
  };
  return names[phase] ?? 'Phase $phase';
}

/// Per-phase focus subtitle. Used in the meta line. Uppercased at the
/// callsite.
String _phaseFocus(int phase) {
  const focus = {
    1: 'Foundation + technique',
    2: 'Power + hypertrophy',
    3: 'Volume + intensification',
    4: 'Power build',
    5: 'Hypertrophy peak',
    6: 'Strength cycle',
    7: 'Conditioning + power',
    8: 'Power + hypertrophy',
    9: 'Specialisation',
    10: 'Strength peak',
    11: 'Conditioning peak',
    12: 'Mastery',
  };
  return (focus[phase] ?? 'Progressive overload').toUpperCase();
}
