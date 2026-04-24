import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Step 2/3 of the handoff onboarding flow — baseline stats capture
/// (`design_handoff_wardroom/src/screens/onboarding.jsx` StatsScreen,
/// lines 165–282).
///
/// Collects sex, weight, height, age, body-fat estimate, and activity
/// level outside lifting. Writes via the route extra to PR AB's
/// PlanScreen, which triggers the actual UserRepository.updateProfile
/// + PlanGenerator.generatePhase1 call on "REPORT FOR DUTY".
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, required this.goal, this.initial});

  final String goal;
  final Map<String, dynamic>? initial;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  late final TextEditingController _weight;
  late final TextEditingController _targetWeight;
  late final TextEditingController _height;
  late final TextEditingController _bodyFat;
  late String _activity;

  @override
  void initState() {
    super.initState();
    final init = widget.initial ?? const <String, dynamic>{};
    _weight = TextEditingController(
      text: (init['weight_kg'] as num?)?.toStringAsFixed(1) ?? '75.0',
    );
    // AI.1 — target weight seed mirrors the goal-derived delta that
    // plan_screen.dart previously computed silently (lose_fat -5,
    // recomp -2, build_muscle +3, otherwise current weight). User can
    // overwrite freely; the BMR calculator uses this for protein
    // targeting when goal == 'lose_fat' and for projection elsewhere.
    final seedWeight =
        (init['weight_kg'] as num?)?.toDouble() ?? 75.0;
    final goalDelta = switch (widget.goal) {
      'lose_fat' => -5.0,
      'recomp' => -2.0,
      'build_muscle' => 3.0,
      _ => 0.0,
    };
    final seedTarget = (init['target_weight_kg'] as num?)?.toDouble() ??
        (seedWeight + goalDelta).clamp(40.0, 250.0);
    _targetWeight = TextEditingController(
      text: seedTarget.toStringAsFixed(1),
    );
    _height = TextEditingController(
      text: (init['height_cm'] as num?)?.toStringAsFixed(0) ?? '175',
    );
    _bodyFat = TextEditingController(
      text: (init['body_fat_pct'] as num?)?.toStringAsFixed(0) ?? '18',
    );
    _activity = (init['activity_level'] as String?) ?? 'moderate';
  }

  @override
  void dispose() {
    _weight.dispose();
    _targetWeight.dispose();
    _height.dispose();
    _bodyFat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: WardFrame(
        grain: true,
        padBottom: 0,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 32, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _progress(),
                const SizedBox(height: 24),
                _header(),
                const SizedBox(height: 22),
                _statGrid(),
                const SizedBox(height: 14),
                _activitySelector(),
                const SizedBox(height: 24),
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
          '03 \u00B7 05',
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
                widthFactor: 3 / 5,
                child: Container(height: 1, color: AppColors.accent),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'STATS',
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
          'QUESTION II',
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
                text: 'baseline.',
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
          'We need the starting coordinates. Estimates are fine \u2014 we refine as you log.',
          style: AppTypography.bodySm.copyWith(
            color: AppColors.textDim,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  // Sex + age inputs removed 2026-04-24. Sex now lives on the new
  // Identity screen (step 01·05). Age is derived from date_of_birth
  // (also collected on Identity) at plan-commit time, so it's not
  // captured directly here anymore.

  Widget _statGrid() {
    return LayoutBuilder(
      builder: (context, c) {
        final gap = 6.0;
        final tileWidth = (c.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            SizedBox(
              width: tileWidth,
              child: _StatField(
                label: 'WEIGHT',
                unit: 'KG',
                controller: _weight,
                highlight: true,
                decimal: true,
              ),
            ),
            // AI.1 — target weight lives next to current weight so the
            // pairing reads visually. Same gold border treatment.
            SizedBox(
              width: tileWidth,
              child: _StatField(
                label: 'TARGET',
                unit: 'KG',
                controller: _targetWeight,
                highlight: true,
                decimal: true,
              ),
            ),
            SizedBox(
              width: tileWidth,
              child: _StatField(
                label: 'HEIGHT',
                unit: 'CM',
                controller: _height,
                decimal: false,
              ),
            ),
            SizedBox(
              width: tileWidth,
              child: _StatField(
                label: 'BODY FAT',
                unit: '% \u00B7 EST',
                controller: _bodyFat,
                decimal: false,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _activitySelector() {
    const options = [
      ('SEDENTARY', 'sedentary'),
      ('LIGHT', 'light'),
      ('MODERATE', 'moderate'),
      ('HEAVY', 'heavy'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'ACTIVITY \u00B7 OUTSIDE LIFTING',
          style: AppTypography.monoXs.copyWith(
            color: AppColors.textMute,
            letterSpacing: 2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final opt in options)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: GestureDetector(
                    onTap: () => setState(() => _activity = opt.$2),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _activity == opt.$2
                            ? AppColors.accent
                            : AppColors.card,
                        border: Border.all(
                          color: _activity == opt.$2
                              ? AppColors.accent
                              : AppColors.line2,
                        ),
                        borderRadius:
                            BorderRadius.circular(AppRadius.sharp),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        opt.$1,
                        style: AppTypography.monoXs.copyWith(
                          fontSize: 8.5,
                          color: _activity == opt.$2
                              ? AppColors.bgDeep
                              : AppColors.textDim,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _cta(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => context.go(
            '/onboarding/goal',
            extra: {
              ...widget.initial ?? const <String, dynamic>{},
              'goal': widget.goal,
            },
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
            onTap: _onCalibrate,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(AppRadius.sharp),
              ),
              alignment: Alignment.center,
              child: Text(
                'CALIBRATE PLAN \u2192',
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

  void _onCalibrate() {
    final weight = double.tryParse(_weight.text);
    final height = double.tryParse(_height.text);
    final bodyFat = double.tryParse(_bodyFat.text);
    final targetWeight = double.tryParse(_targetWeight.text);
    if (weight == null || height == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Check weight and height — those need numbers.',
            style: AppTypography.bodySm.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          backgroundColor: AppColors.bad,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    // AI.1 — target_weight_kg rides along in the route extras. AI.3
    // wires plan_screen to consume it instead of inferring from goal
    // + weight.
    final resolvedTarget = (targetWeight ?? weight).clamp(40.0, 250.0);
    // Carry forward everything that came in (full_name, date_of_birth,
    // sex from Identity) plus this screen's captures. Details screen
    // forwards the same into Plan.
    context.go(
      '/onboarding/details',
      extra: {
        ...widget.initial ?? const <String, dynamic>{},
        'goal': widget.goal,
        'weight_kg': weight,
        'target_weight_kg': resolvedTarget,
        'height_cm': height,
        'body_fat_pct': bodyFat ?? 18.0,
        'activity_level': _activity,
      },
    );
  }
}

class _StatField extends StatelessWidget {
  const _StatField({
    required this.label,
    required this.unit,
    required this.controller,
    this.highlight = false,
    this.decimal = false,
  });

  final String label;
  final String unit;
  final TextEditingController controller;
  final bool highlight;
  final bool decimal;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(
          color: highlight
              ? AppColors.accent.withValues(alpha: 0.53)
              : AppColors.line2,
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: AppTypography.monoXs.copyWith(
              fontSize: 8,
              color: AppColors.textMute,
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: TextField(
                  controller: controller,
                  keyboardType: decimal
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : TextInputType.number,
                  inputFormatters: decimal
                      ? [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9.]'),
                          ),
                        ]
                      : [FilteringTextInputFormatter.digitsOnly],
                  style: AppTypography.numeric.copyWith(
                    fontSize: 26,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: AppTypography.monoXs.copyWith(
                  fontSize: 9,
                  color: AppColors.textMute,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
