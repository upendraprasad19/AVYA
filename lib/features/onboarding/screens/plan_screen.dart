import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import '../providers/onboarding_provider.dart';

/// Final step (3/3) of the handoff onboarding flow — plan preview +
/// commit (`design_handoff_wardroom/src/screens/onboarding.jsx`
/// PlanScreen, lines 285–382).
///
/// Shows the three-phase campaign outline plus a 4-stat Phase I
/// targets card. "REPORT FOR DUTY" reuses the existing
/// [OnboardingNotifier.completeOnboarding] pipeline — maps the
/// collected step data onto its `answers` schema with sensible
/// defaults, then calls `completeOnboarding()` which saves profile,
/// generates Phase 1, schedules workouts, sets onboarded flag, and
/// pushes the AI snapshot. On success we route to `/home`; on failure
/// we surface the pipeline's error message.
class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key, required this.data});

  /// Accumulated extras from GoalScreen + StatsScreen.
  final Map<String, dynamic> data;

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  bool _submitting = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final goal = widget.data['goal'] as String? ?? 'recomp';
    final goalLabel = _goalLabel(goal);
    final targets = _computeTargets();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: WardFrame(
        grain: true,
        padBottom: 0,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _progress(),
                const SizedBox(height: 18),
                _hero(goalLabel),
                const SizedBox(height: 18),
                _phaseBlocks(),
                const SizedBox(height: 14),
                _targetsCard(targets),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _errorBanner(_error!),
                ],
                const SizedBox(height: 28),
                _cta(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _progress() {
    return Row(
      children: [
        Text(
          '04 \u00B7 04',
          style: AppTypography.mono.copyWith(
            color: AppColors.accent,
            letterSpacing: 2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: AppColors.accent)),
        const SizedBox(width: 10),
        Text(
          'READY',
          style: AppTypography.mono.copyWith(
            color: AppColors.accent,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _hero(String goalLabel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const AnchorGlyph(size: 13),
            const SizedBox(width: 8),
            Text(
              'YOUR CAMPAIGN',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.accent,
                letterSpacing: 3,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        RichText(
          text: TextSpan(
            style: AppTypography.h1.copyWith(
              fontSize: 30,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
              height: 1.08,
            ),
            children: [
              const TextSpan(text: '12-week '),
              TextSpan(
                text: goalLabel,
                style: const TextStyle(
                  fontStyle: FontStyle.italic,
                  color: AppColors.accent,
                ),
              ),
              const TextSpan(text: '\nprotocol.'),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "Drawn up for your baseline. Here's the shape of it.",
          style: AppTypography.bodySm.copyWith(
            color: AppColors.textDim,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _phaseBlocks() {
    const phases = [
      ('I', 'FOUNDATION', 'WEEKS 1–4',
          'Technique, baselines, 4 days/week.', true),
      ('II', 'CAPACITY', 'WEEKS 5–8',
          'Volume push, 5 days/week, mid-deload.', false),
      ('III', 'CONVERGE', 'WEEKS 9–12',
          'Peak strength, lean targets, taper.', false),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < phases.length; i++) ...[
          WardPhaseBlock(
            roman: phases[i].$1,
            title: phases[i].$2,
            weeksLabel: phases[i].$3,
            description: phases[i].$4,
            active: phases[i].$5,
          ),
          if (i < phases.length - 1)
            Container(
              height: 1,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.line2,
                    width: 1,
                    style: BorderStyle.solid,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _targetsCard(_Targets t) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line2),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'TARGETS \u00B7 PHASE I',
            style: AppTypography.monoXs.copyWith(
              color: AppColors.textMute,
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _targetTile('${t.calories}', 'KCAL'),
              ),
              Expanded(
                child: _targetTile('${t.protein}g', 'PROT'),
              ),
              Expanded(
                child: _targetTile('${t.daysPerWeek}\u00D7', 'LIFTS'),
              ),
              Expanded(
                child: _targetTile(t.weightDelta, 'TGT'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _targetTile(String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: AppTypography.h2.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.accent,
            height: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTypography.monoXs.copyWith(
            fontSize: 8,
            color: AppColors.textMute,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _errorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bad.withValues(alpha: 0.12),
        border: Border(
          left: BorderSide(color: AppColors.bad, width: 3),
          top: BorderSide(color: AppColors.bad.withValues(alpha: 0.33)),
          right: BorderSide(color: AppColors.bad.withValues(alpha: 0.33)),
          bottom: BorderSide(color: AppColors.bad.withValues(alpha: 0.33)),
        ),
        borderRadius: BorderRadius.circular(AppRadius.sharp),
      ),
      child: Text(
        message,
        style: AppTypography.bodySm.copyWith(
          color: AppColors.bad,
        ),
      ),
    );
  }

  Widget _cta(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: _submitting ? null : _onReportForDuty,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: _submitting
                  ? AppColors.accent.withValues(alpha: 0.6)
                  : AppColors.accent,
              borderRadius: BorderRadius.circular(AppRadius.sharp),
            ),
            alignment: Alignment.center,
            child: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.bgDeep,
                    ),
                  )
                : Text(
                    'REPORT FOR DUTY \u2192',
                    style: AppTypography.mono.copyWith(
                      fontSize: 13,
                      color: AppColors.bgDeep,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => context.go(
            '/onboarding/stats',
            extra: widget.data,
          ),
          child: Text(
            'ADJUST PLAN',
            style: AppTypography.monoXs.copyWith(
              fontSize: 10,
              color: AppColors.textDim,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _onReportForDuty() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final email =
          SupabaseService.instance.client.auth.currentUser?.email ?? '';

      // Map collected data onto OnboardingNotifier's answers schema.
      //
      // The JSX handoff deliberately collects only 6 fields (sex, weight,
      // height, age, body-fat, activity) + goal — everything else is
      // derived server-side or refined later through the AI coach. This
      // block does that derivation: rather than hardcoding everyone as a
      // "beginner at a basic gym who sits all day", it infers sensible
      // values from the signals the user already gave us.
      //
      // Fields still defaulted (no signal in the stepped flow):
      //   equipment_access → 'basic_gym' (most common for young pros in IN)
      //   diet_preference  → 'balanced'
      //   injuries         → [] (refined via coach later)
      //   start_date       → 'this_monday' (most-picked option in legacy flow)
      final goal = widget.data['goal'] as String? ?? 'recomp';
      final weight = (widget.data['weight_kg'] as num?)?.toDouble() ?? 75.0;
      final activityLevel =
          (widget.data['activity_level'] as String?) ?? 'moderate';

      // Target weight — 12-week delta sized to the goal. Conservative on
      // both ends so the calorie maths don't land in unsafe territory for
      // edge-case starting weights.
      final targetDelta = switch (goal) {
        'lose_fat' => -5.0,
        'recomp' => -2.0,
        'build_muscle' => 3.0,
        _ => 0.0,
      };
      final targetWeight = (weight + targetDelta).clamp(40, 250);
      final now = DateTime.now();
      final age = (widget.data['age'] as int?) ?? 30;
      final dob = DateTime(now.year - age, now.month, now.day);

      // Infer fitness_experience from activity_level. A "heavy activity"
      // person is moving enough outside the gym that a beginner-tier plan
      // would feel insulting; a sedentary user usually needs foundation
      // work before higher volumes are safe.
      final fitnessExperience = switch (activityLevel) {
        'sedentary' || 'light' => 'beginner',
        'moderate' => 'intermediate',
        'heavy' => 'advanced',
        _ => 'beginner',
      };

      // Days per week by goal intensity. More honest than "everyone gets
      // 4/week": Build/Strength programs need more sessions for the SV
      // split to work; Maintain barely needs 3.
      final daysPerWeek = switch (goal) {
        'build_muscle' || 'strength' => 5,
        'recomp' || 'lose_fat' => 4,
        'maintain' => 3,
        _ => 4,
      };

      // lifestyle_activity — stats-screen collects activity_level with 4
      // pills (sedentary/light/moderate/heavy); plan_engine expects 3
      // buckets (desk_job/lightly_active/very_active_job). Fold the
      // top end into very_active_job so users with heavy day jobs don't
      // get TDEE under-estimated.
      final lifestyleActivity = switch (activityLevel) {
        'sedentary' || 'light' => 'desk_job',
        'moderate' => 'lightly_active',
        'heavy' => 'very_active_job',
        _ => 'desk_job',
      };

      // Pace preference follows goal aggression. Cut/Build users picked
      // an aggressive goal; Recomp/Strength users want steady progress;
      // Maintain users explicitly don't want acceleration.
      final pacePreference = switch (goal) {
        'lose_fat' || 'build_muscle' => 'aggressive',
        'recomp' || 'strength' => 'balanced',
        'maintain' => 'slow',
        _ => 'balanced',
      };

      final notifier = ref.read(onboardingProvider.notifier);
      notifier.setAnswer('full_name', email.split('@').first);
      notifier.setAnswer('email', email);
      notifier.setAnswer('date_of_birth', dob.toIso8601String());
      notifier.setAnswer(
          'gender', widget.data['sex'] as String? ?? 'male');
      notifier.setAnswer(
          'height_cm', (widget.data['height_cm'] as num?)?.toDouble() ?? 175.0);
      notifier.setAnswer('current_weight_kg', weight);
      notifier.setAnswer('target_weight_kg', targetWeight);
      notifier.setAnswer('primary_goal', _mapGoal(goal));
      notifier.setAnswer('fitness_experience', fitnessExperience);
      notifier.setAnswer('days_per_week', daysPerWeek);
      notifier.setAnswer('equipment_access', 'basic_gym');
      notifier.setAnswer('activity_level', activityLevel);
      notifier.setAnswer('lifestyle_activity', lifestyleActivity);
      notifier.setAnswer('pace_preference', pacePreference);
      notifier.setAnswer('diet_preference', 'balanced');
      notifier.setAnswer(
          'body_fat_percent',
          (widget.data['body_fat_pct'] as num?)?.toDouble() ?? 18.0);
      notifier.setAnswer('injuries', <String>[]);
      notifier.setAnswer('start_date', 'this_monday');

      final phase = await notifier.completeOnboarding();
      if (!mounted) return;
      if (phase == null) {
        final err = ref.read(onboardingProvider).error ??
            'Failed to generate plan. Please try again.';
        setState(() {
          _submitting = false;
          _error = err;
        });
        return;
      }
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Something went wrong: ${e.runtimeType}. Try again.';
      });
    }
  }

  _Targets _computeTargets() {
    final weight = (widget.data['weight_kg'] as num?)?.toDouble() ?? 75.0;
    final goal = widget.data['goal'] as String? ?? 'recomp';
    final calories = switch (goal) {
      'lose_fat' || 'recomp' => (weight * 30 - 400).round(),
      'build_muscle' => (weight * 32 + 250).round(),
      'strength' => (weight * 32).round(),
      _ => (weight * 30).round(),
    };
    final protein = (weight * 2).round();
    // Must mirror the daysPerWeek inference in _onReportForDuty so the
    // targets card the user sees matches what the plan generator will
    // actually produce. Change both together or the "4× LIFTS" on the
    // card lies about "5× LIFTS" programs.
    final daysPerWeek = switch (goal) {
      'build_muscle' || 'strength' => 5,
      'recomp' || 'lose_fat' => 4,
      'maintain' => 3,
      _ => 4,
    };
    // Weight-delta label follows the same 12-week target math used at
    // submit time. Keep aligned with the `targetDelta` switch above.
    final delta = switch (goal) {
      'lose_fat' => '-5kg',
      'recomp' => '-2kg',
      'build_muscle' => '+3kg',
      _ => 'HOLD',
    };
    return _Targets(
      calories: calories,
      protein: protein,
      daysPerWeek: daysPerWeek,
      weightDelta: delta,
    );
  }

  String _goalLabel(String goal) => switch (goal) {
        'lose_fat' => 'Cut',
        'build_muscle' => 'Build',
        'recomp' => 'Recomp',
        'strength' => 'Perform',
        _ => 'Maintain',
      };

  /// Map our onboarding-step goal key onto the value
  /// [OnboardingNotifier.completeOnboarding] expects
  /// (`primary_goal` column on user_profile).
  String _mapGoal(String goal) => switch (goal) {
        'recomp' => 'recompose',
        'build_muscle' => 'build_muscle',
        'lose_fat' => 'lose_fat',
        'strength' => 'strength',
        _ => 'general_fitness',
      };
}

class _Targets {
  const _Targets({
    required this.calories,
    required this.protein,
    required this.daysPerWeek,
    required this.weightDelta,
  });
  final int calories;
  final int protein;
  final int daysPerWeek;
  final String weightDelta;
}
