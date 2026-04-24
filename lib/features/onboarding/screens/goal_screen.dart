import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Step 2/3 of the handoff onboarding flow — goal selection
/// (`design_handoff_wardroom/src/screens/onboarding.jsx` GoalScreen,
/// lines 75–162).
///
/// Layout:
/// * Progress indicator — mono "01 · 03" + thin `line2` track with
///   33% gold fill + right-aligned "GOAL" caption.
/// * Question header — mono "QUESTION I" eyebrow + Fraunces 30 w500
///   headline with italic-gold "do?" + DM Sans 13 dim helper copy.
/// * 5 goal cards (WardRadioRow) — Recompose / Build / Cut / Maintain
///   / Perform. Selected: `cardTop` bg + gold border + 3-px gold
///   left border + solid gold dot inside the radio circle.
/// * CTA row — "BACK" outline + "CONTINUE →" gold primary.
///
/// Goal passes to `/onboarding/stats` via `state.extra` as a String.
/// The final profile write happens in PR AB (PlanScreen) — this screen
/// only stages the selection in the route extra.
class GoalScreen extends StatefulWidget {
  const GoalScreen({
    super.key,
    this.initialGoal,
    this.identity,
  });

  final String? initialGoal;

  /// Route-extras carrying forward Identity's `full_name`, `date_of_birth`,
  /// and `sex`. Forwarded verbatim to Stats / Details / Plan so the final
  /// profile write at REPORT FOR DUTY has every field it needs.
  final Map<String, dynamic>? identity;

  @override
  State<GoalScreen> createState() => _GoalScreenState();
}

class _GoalScreenState extends State<GoalScreen> {
  static const _goals = [
    _GoalOption(
      key: 'recomp',
      code: 'RECOMP',
      title: 'Recompose',
      subtitle: 'Drop body fat \u00B7 hold strength',
    ),
    _GoalOption(
      key: 'build_muscle',
      code: 'BUILD',
      title: 'Build',
      subtitle: 'Put on clean muscle',
    ),
    _GoalOption(
      key: 'lose_fat',
      code: 'CUT',
      title: 'Cut',
      subtitle: 'Strip fat \u00B7 protect lean mass',
    ),
    _GoalOption(
      key: 'general_fitness',
      code: 'MAINT',
      title: 'Maintain',
      subtitle: 'Hold the line \u00B7 feel your best',
    ),
    _GoalOption(
      key: 'strength',
      code: 'PERFORM',
      title: 'Perform',
      subtitle: 'Sport \u00B7 power \u00B7 output',
    ),
  ];

  late String _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialGoal ?? _goals.first.key;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: WardFrame(
        grain: true,
        padBottom: 0,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 32, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _progress(),
                const SizedBox(height: 24),
                _header(),
                const SizedBox(height: 22),
                Expanded(child: _options()),
                const SizedBox(height: 16),
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
          '02 \u00B7 05',
          style: AppTypography.mono.copyWith(
            color: AppColors.accent,
            letterSpacing: 2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Stack(
            children: [
              Container(height: 1, color: AppColors.line2),
              FractionallySizedBox(
                widthFactor: 2 / 5,
                child: Container(height: 1, color: AppColors.accent),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'GOAL',
          style: AppTypography.mono.copyWith(
            color: AppColors.textDim,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _header() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'QUESTION I',
          style: AppTypography.monoXs.copyWith(
            color: AppColors.textMute,
            letterSpacing: 2.5,
            fontWeight: FontWeight.w600,
          ),
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
            children: const [
              TextSpan(text: 'What are you\nhere to '),
              TextSpan(
                text: 'do?',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "Pick one. You can change it later \u2014 we'll recalibrate.",
          style: AppTypography.bodySm.copyWith(
            color: AppColors.textDim,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _options() {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _goals.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final g = _goals[i];
        return WardRadioRow(
          rowKey: g.code,
          title: g.title,
          subtitle: g.subtitle,
          selected: _selected == g.key,
          onTap: () => setState(() => _selected = g.key),
        );
      },
    );
  }

  Widget _cta(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => context.go(
            '/onboarding/identity',
            extra: widget.identity ?? const {},
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.line2),
              borderRadius: BorderRadius.circular(AppRadius.sharp),
            ),
            child: Text(
              'BACK',
              style: AppTypography.mono.copyWith(
                fontSize: 12,
                color: AppColors.textDim,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () => context.go(
              '/onboarding/stats',
              extra: {
                ...?widget.identity,
                'goal': _selected,
              },
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(AppRadius.sharp),
              ),
              alignment: Alignment.center,
              child: Text(
                'CONTINUE \u2192',
                style: AppTypography.mono.copyWith(
                  fontSize: 12,
                  color: AppColors.bgDeep,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GoalOption {
  const _GoalOption({
    required this.key,
    required this.code,
    required this.title,
    required this.subtitle,
  });

  /// Maps to `user_profile.fitness_goal` key used by the plan generator
  /// (`build_muscle`, `lose_fat`, `general_fitness`, `strength`,
  /// `recomp`).
  final String key;

  /// Short mono-caps leading code ("RECOMP", "BUILD", etc.).
  final String code;

  final String title;
  final String subtitle;
}
