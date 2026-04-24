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
          '05 \u00B7 05',
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
            '/onboarding/details',
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
      // As of PR AI, the stepped flow actively collects 11 of the 13
      // fields the profile cares about:
      //   Goal screen       → goal
      //   Stats screen      → sex, weight_kg, target_weight_kg,
      //                       height_cm, age, body_fat_pct,
      //                       activity_level
      //   Details screen    → fitness_experience, pace_preference,
      //                       days_per_week, equipment_access
      //
      // Two fields stay as onboarding defaults by explicit product
      // decision during PR AI planning:
      //   diet_preference → 'veg'  (Indian-first target audience)
      //   injuries        → ['none']  (matches edit_profile's convention)
      // Users override both via Profile → Edit Profile, which has both
      // fields wired.
      //
      // `lifestyle_activity` stays inferred from `activity_level`
      // because the mapping is 1:1 and no extra user question would
      // improve fidelity.
      //   start_date → 'this_monday' (most-picked option in legacy flow).
      final goal = widget.data['goal'] as String? ?? 'recomp';
      final weight = (widget.data['weight_kg'] as num?)?.toDouble() ?? 75.0;
      final activityLevel =
          (widget.data['activity_level'] as String?) ?? 'moderate';

      // Target weight — Stats screen now collects this directly. Fall
      // back to the old goal-delta rule if (somehow) absent — covers
      // legacy chat users or direct deep-links to /plan.
      final suppliedTarget =
          (widget.data['target_weight_kg'] as num?)?.toDouble();
      final targetWeight = suppliedTarget != null
          ? suppliedTarget.clamp(40.0, 250.0)
          : () {
              final targetDelta = switch (goal) {
                'lose_fat' => -5.0,
                'recomp' => -2.0,
                'build_muscle' => 3.0,
                _ => 0.0,
              };
              return (weight + targetDelta).clamp(40.0, 250.0);
            }();
      // Date of birth is now collected on Identity (step 01·05). Pull
      // it directly; fall back to the legacy `age`-derived DOB only for
      // deep-linked legacy-chat users who never hit the stepped flow.
      DateTime dob;
      final dobString = widget.data['date_of_birth'];
      if (dobString is String) {
        dob = DateTime.tryParse(dobString) ?? DateTime(2000, 1, 1);
      } else if (dobString is DateTime) {
        dob = dobString;
      } else {
        final now = DateTime.now();
        final age = (widget.data['age'] as int?) ?? 30;
        dob = DateTime(now.year - age, now.month, now.day);
      }

      // fitness_experience, days_per_week, equipment_access,
      // pace_preference now come directly from the Details screen.
      // Fall back to the previous inference rules only when the field
      // is absent (legacy chat users, deep-links, or a user who
      // skipped the stepped flow somehow).
      final fitnessExperience =
          (widget.data['fitness_experience'] as String?) ??
              switch (activityLevel) {
                'sedentary' || 'light' => 'beginner',
                'moderate' => 'intermediate',
                'heavy' => 'advanced',
                _ => 'beginner',
              };
      final daysPerWeek = (widget.data['days_per_week'] as int?) ??
          switch (goal) {
            'build_muscle' || 'strength' => 5,
            'recomp' || 'lose_fat' => 4,
            'maintain' => 3,
            _ => 4,
          };
      final pacePreference =
          (widget.data['pace_preference'] as String?) ??
              switch (goal) {
                'lose_fat' || 'build_muscle' => 'aggressive',
                'recomp' || 'strength' => 'balanced',
                'maintain' => 'slow',
                _ => 'balanced',
              };
      final equipmentAccess =
          (widget.data['equipment_access'] as String?) ?? 'basic_gym';

      // lifestyle_activity — stats-screen collects activity_level with 4
      // pills (sedentary/light/moderate/heavy); plan_engine expects 3
      // buckets (desk_job/lightly_active/very_active_job). 1:1 mapping,
      // so no user-facing question needed.
      final lifestyleActivity = switch (activityLevel) {
        'sedentary' || 'light' => 'desk_job',
        'moderate' => 'lightly_active',
        'heavy' => 'very_active_job',
        _ => 'desk_job',
      };

      // Full name now comes from Identity step (collected pre-Goal).
      // Fallback to email prefix for legacy chat-flow users.
      final identityName = (widget.data['full_name'] as String?)?.trim();
      final fullName = (identityName != null && identityName.isNotEmpty)
          ? identityName
          : email.split('@').first;

      final notifier = ref.read(onboardingProvider.notifier);
      notifier.setAnswer('full_name', fullName);
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
      notifier.setAnswer('equipment_access', equipmentAccess);
      notifier.setAnswer('activity_level', activityLevel);
      notifier.setAnswer('lifestyle_activity', lifestyleActivity);
      notifier.setAnswer('pace_preference', pacePreference);
      // AI.3 — defaults updated per user decision:
      //   diet_preference: 'balanced' → 'veg' (Indian-first default)
      //   injuries: []  → ['none']  (matches edit_profile convention)
      notifier.setAnswer('diet_preference', 'veg');
      notifier.setAnswer(
          'body_fat_percent',
          (widget.data['body_fat_pct'] as num?)?.toDouble() ?? 18.0);
      notifier.setAnswer('injuries', <String>['none']);
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
    // Read the real days_per_week the user picked on the Details screen.
    // Fall back to goal-derived defaults only when the field is absent
    // (legacy chat users, deep-links, corrupted route extras) so the
    // "4× LIFTS" label on the card always matches what the plan
    // generator will actually produce.
    final daysPerWeek = (widget.data['days_per_week'] as int?) ??
        switch (goal) {
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
