import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Step 03 · 04 of the handoff onboarding flow — training details
/// capture.
///
/// Added in PR AI to close the field-coverage gap the Wardroom stepped
/// flow left open: the original Welcome → Goal → Stats → Plan sequence
/// silently defaulted / inferred `fitness_experience`, `pace_preference`,
/// `days_per_week`, and `equipment_access` from `activity_level` +
/// `goal`. Two users with identical goal+activity answers would get the
/// same plan even with wildly different equipment and experience — a
/// regression from the legacy chat flow's accuracy.
///
/// Layout mirrors [GoalScreen] — same `WardFrame` + progress indicator
/// + eyebrow + italic-gold headline — but with four stacked
/// `WardRadioRow` sections instead of one list. Scrolls vertically
/// because the 14 rows don't fit in one viewport on most devices.
///
/// Not collected here (by explicit user decision during PR AI planning):
///   * `diet_preference` — defaults to `'veg'` in `plan_screen`.
///   * `injuries` — defaults to `['none']` in `plan_screen`.
///
/// Users who want to override those defaults do so in Profile → Edit
/// Profile, which already has both fields wired up.
class DetailsScreen extends StatefulWidget {
  const DetailsScreen({super.key, required this.data});

  /// Accumulated onboarding map from Stats:
  /// `{goal, sex, weight_kg, target_weight_kg, height_cm, age,
  /// body_fat_pct, activity_level}`.
  final Map<String, dynamic> data;

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  // Defaults mirror the pre-PR-AI inference + hardcoding so no user is
  // worse off if they tap CONTINUE without changing anything.
  late String _experience;
  late String _pace;
  late int _daysPerWeek;
  late String _equipment;

  @override
  void initState() {
    super.initState();
    _experience =
        (widget.data['fitness_experience'] as String?) ?? 'beginner';
    _pace = (widget.data['pace_preference'] as String?) ?? 'balanced';
    _daysPerWeek = (widget.data['days_per_week'] as int?) ?? 4;
    _equipment =
        (widget.data['equipment_access'] as String?) ?? 'basic_gym';
  }

  static const _experiences = <_Option<String>>[
    _Option(
      value: 'beginner',
      code: 'NEW',
      title: 'Beginner',
      subtitle: 'New to lifting \u00B7 under 6 months',
    ),
    _Option(
      value: 'intermediate',
      code: 'STEADY',
      title: 'Intermediate',
      subtitle: 'Consistent lifter \u00B7 6 mo\u20132 yrs',
    ),
    _Option(
      value: 'advanced',
      code: 'SEASONED',
      title: 'Advanced',
      subtitle: 'Experienced \u00B7 2+ years',
    ),
  ];

  static const _paces = <_Option<String>>[
    _Option(
      value: 'slow',
      code: 'EASY',
      title: 'Steady',
      subtitle: 'Easiest to stick with',
    ),
    _Option(
      value: 'balanced',
      code: 'STANDARD',
      title: 'Balanced',
      subtitle: 'Evidence-based standard',
    ),
    _Option(
      value: 'aggressive',
      code: 'PUSH',
      title: 'Aggressive',
      subtitle: 'Near the upper safe limit',
    ),
  ];

  static const _days = <_Option<int>>[
    _Option(value: 3, code: '3', title: '3 days / week', subtitle: 'Tight schedule'),
    _Option(value: 4, code: '4', title: '4 days / week', subtitle: 'Balanced cadence'),
    _Option(value: 5, code: '5', title: '5 days / week', subtitle: 'Serious build'),
    _Option(value: 6, code: '6', title: '6 days / week', subtitle: 'Advanced split'),
  ];

  static const _equipments = <_Option<String>>[
    _Option(
      value: 'bodyweight',
      code: 'BW',
      title: 'Bodyweight',
      subtitle: 'No gear \u00B7 home / travel',
    ),
    _Option(
      value: 'home_dumbbells',
      code: 'DB',
      title: 'Home dumbbells',
      subtitle: 'Pair of dumbbells / bands',
    ),
    _Option(
      value: 'basic_gym',
      code: 'BASIC',
      title: 'Basic gym',
      subtitle: 'Barbell \u00B7 rack \u00B7 cables',
    ),
    _Option(
      value: 'full_gym',
      code: 'FULL',
      title: 'Full gym',
      subtitle: 'Machines \u00B7 free weights \u00B7 all',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: WardFrame(
        grain: true,
        padBottom: 0,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 32, 22, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _progress(),
                    const SizedBox(height: 24),
                    _header(),
                    const SizedBox(height: 22),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionLabel('EXPERIENCE'),
                      ..._optionList<String>(
                        options: _experiences,
                        selected: _experience,
                        onSelect: (v) => setState(() => _experience = v),
                      ),
                      const SizedBox(height: 18),
                      _sectionLabel('PACE'),
                      ..._optionList<String>(
                        options: _paces,
                        selected: _pace,
                        onSelect: (v) => setState(() => _pace = v),
                      ),
                      const SizedBox(height: 18),
                      _sectionLabel('DAYS PER WEEK'),
                      ..._optionList<int>(
                        options: _days,
                        selected: _daysPerWeek,
                        onSelect: (v) => setState(() => _daysPerWeek = v),
                      ),
                      const SizedBox(height: 18),
                      _sectionLabel('EQUIPMENT'),
                      ..._optionList<String>(
                        options: _equipments,
                        selected: _equipment,
                        onSelect: (v) => setState(() => _equipment = v),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
                child: _cta(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _progress() {
    return Row(
      children: [
        Text(
          '03 \u00B7 04',
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
                widthFactor: 3 / 4,
                child: Container(height: 1, color: AppColors.accent),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'DETAILS',
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
          'QUESTION III',
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
              TextSpan(text: 'The '),
              TextSpan(
                text: 'details.',
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
          'Four quick picks so the plan fits your equipment and schedule.',
          style: AppTypography.bodySm.copyWith(
            color: AppColors.textDim,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: AppTypography.monoXs.copyWith(
          color: AppColors.textMute,
          letterSpacing: 2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  List<Widget> _optionList<T>({
    required List<_Option<T>> options,
    required T selected,
    required ValueChanged<T> onSelect,
  }) {
    final widgets = <Widget>[];
    for (var i = 0; i < options.length; i++) {
      final o = options[i];
      widgets.add(
        WardRadioRow(
          rowKey: o.code,
          title: o.title,
          subtitle: o.subtitle,
          selected: selected == o.value,
          onTap: () => onSelect(o.value),
        ),
      );
      if (i < options.length - 1) {
        widgets.add(const SizedBox(height: 6));
      }
    }
    return widgets;
  }

  Widget _cta(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => context.go(
            '/onboarding/stats',
            extra: widget.data,
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
            onTap: _onContinue,
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

  void _onContinue() {
    final enriched = <String, dynamic>{
      ...widget.data,
      'fitness_experience': _experience,
      'pace_preference': _pace,
      'days_per_week': _daysPerWeek,
      'equipment_access': _equipment,
    };
    context.go('/onboarding/plan', extra: enriched);
  }
}

class _Option<T> {
  const _Option({
    required this.value,
    required this.code,
    required this.title,
    required this.subtitle,
  });

  /// Canonical key written to `user_profile` (e.g. `'beginner'`, `4`).
  final T value;

  /// Short mono-caps leading code shown in the 44-px WardRadioRow gutter.
  final String code;

  final String title;
  final String subtitle;
}
