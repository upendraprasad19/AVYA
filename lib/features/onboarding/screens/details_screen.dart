import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Step 04 · 05 of the stepped onboarding flow — training details capture.
///
/// **APK test #1 batch (2026-04-24) — redesign D3.**
/// Previously this screen stacked four full-height `WardRadioRow`
/// sections, requiring a tall vertical scroll (14 rows + 4 labels on
/// every device). The user feedback: "less intense, easier". The
/// redesign holds four equal-weight sections with a fade-on-unselected
/// treatment — the selected option carries full parchment text + gold
/// left-border, unselected options sit at `textGhost` and 45% opacity
/// so the section stays scannable without shouting. Defaults are
/// pre-selected (Intermediate · Balanced · 4 days · Basic gym) so
/// tapping CONTINUE with zero changes never produces a broken profile.
///
/// Data in: `{goal, sex, weight_kg, target_weight_kg, height_cm,
/// date_of_birth, body_fat_pct, activity_level}` (from Stats).
/// Data out: original map + `{fitness_experience, pace_preference,
/// days_per_week, equipment_access}` passed to `/onboarding/plan` via
/// route extras.
class DetailsScreen extends StatefulWidget {
  const DetailsScreen({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  late String _experience;
  late String _pace;
  late int _daysPerWeek;
  late String _equipment;

  @override
  void initState() {
    super.initState();
    _experience =
        (widget.data['fitness_experience'] as String?) ?? 'intermediate';
    _pace = (widget.data['pace_preference'] as String?) ?? 'balanced';
    _daysPerWeek = (widget.data['days_per_week'] as int?) ?? 4;
    _equipment =
        (widget.data['equipment_access'] as String?) ?? 'basic_gym';
  }

  static const _experiences = <_Option<String>>[
    _Option(value: 'beginner', code: 'NEW', title: 'Beginner', subtitle: 'under 6 months'),
    _Option(value: 'intermediate', code: 'STEADY', title: 'Intermediate', subtitle: '6 mo \u2013 2 yrs'),
    _Option(value: 'advanced', code: 'SEASONED', title: 'Advanced', subtitle: '2+ years'),
  ];

  static const _paces = <_Option<String>>[
    _Option(value: 'slow', code: 'EASY', title: 'Steady', subtitle: 'easiest to stick with'),
    _Option(value: 'balanced', code: 'STANDARD', title: 'Balanced', subtitle: 'evidence-based'),
    _Option(value: 'aggressive', code: 'PUSH', title: 'Aggressive', subtitle: 'upper safe limit'),
  ];

  static const _days = <_ChipOption<int>>[
    _ChipOption(value: 3, label: '3'),
    _ChipOption(value: 4, label: '4'),
    _ChipOption(value: 5, label: '5'),
    _ChipOption(value: 6, label: '6'),
  ];

  static const _equipments = <_ChipOption<String>>[
    _ChipOption(value: 'bodyweight', label: 'BW'),
    _ChipOption(value: 'home_dumbbells', label: 'DB'),
    _ChipOption(value: 'basic_gym', label: 'BASIC'),
    _ChipOption(value: 'full_gym', label: 'FULL'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: WardFrame(
        grain: true,
        padBottom: 0,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _progress(),
                const SizedBox(height: 18),
                _header(),
                const SizedBox(height: 18),
                Expanded(
                  child: SingleChildScrollView(
                    // Physics hint: the content is tuned to fit a
                    // 360x640 viewport without scrolling. The scroll
                    // view is a safety net for smaller devices so the
                    // CTA never disappears off-screen; healthy defaults
                    // ensure almost every user sees no scroll.
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _FadeSection<String>(
                          label: 'EXPERIENCE',
                          options: _experiences,
                          selected: _experience,
                          onSelect: (v) =>
                              setState(() => _experience = v),
                        ),
                        const SizedBox(height: 14),
                        _FadeSection<String>(
                          label: 'PACE',
                          options: _paces,
                          selected: _pace,
                          onSelect: (v) => setState(() => _pace = v),
                        ),
                        const SizedBox(height: 14),
                        _ChipRow<int>(
                          label: 'DAYS PER WEEK',
                          options: _days,
                          selected: _daysPerWeek,
                          onSelect: (v) =>
                              setState(() => _daysPerWeek = v),
                        ),
                        const SizedBox(height: 14),
                        _ChipRow<String>(
                          label: 'EQUIPMENT',
                          options: _equipments,
                          selected: _equipment,
                          onSelect: (v) =>
                              setState(() => _equipment = v),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
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
          '04 \u00B7 05',
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
                widthFactor: 4 / 5,
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
        const SizedBox(height: 4),
        RichText(
          text: TextSpan(
            style: AppTypography.h1.copyWith(
              fontSize: 26,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
              height: 1.05,
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
      ],
    );
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

/// 3-option section with in-section fade. Each row has a 44dp mono code
/// gutter, title, and optional subtitle. Selected row: full parchment +
/// gold left-bar + accent code. Unselected: 45% opacity + textGhost
/// code + textDim title so it visually recedes without disappearing.
class _FadeSection<T> extends StatelessWidget {
  const _FadeSection({
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final String label;
  final List<_Option<T>> options;
  final T selected;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(
            label,
            style: AppTypography.monoXs.copyWith(
              color: AppColors.textMute,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        for (var i = 0; i < options.length; i++) ...[
          _FadeRow<T>(
            option: options[i],
            selected: selected == options[i].value,
            onTap: () => onSelect(options[i].value),
          ),
          if (i < options.length - 1) const SizedBox(height: 4),
        ],
      ],
    );
  }
}

class _FadeRow<T> extends StatelessWidget {
  const _FadeRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _Option<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: selected ? 1.0 : 0.45,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.cardTop : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: selected ? AppColors.accent : Colors.transparent,
                width: selected ? 2 : 0,
              ),
              top: BorderSide(
                color: selected ? AppColors.accent : AppColors.line2,
              ),
              right: BorderSide(
                color: selected ? AppColors.accent : AppColors.line2,
              ),
              bottom: BorderSide(
                color: selected ? AppColors.accent : AppColors.line2,
              ),
            ),
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 56,
                child: Text(
                  option.code,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                  style: AppTypography.mono.copyWith(
                    color: selected
                        ? AppColors.accent
                        : AppColors.textGhost,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      option.title,
                      style: AppTypography.body.copyWith(
                        fontSize: 15,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w400,
                        color: selected
                            ? AppColors.textPrimary
                            : AppColors.textDim,
                      ),
                    ),
                    if (option.subtitle.isNotEmpty)
                      Text(
                        option.subtitle,
                        style: AppTypography.micro.copyWith(
                          color: AppColors.textMute,
                          letterSpacing: 0.3,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact 4-chip row used for Days / Equipment. Single horizontal line
/// with a mono eyebrow label above. Chip widths are proportional
/// (Expanded) so the row always fills the available width.
class _ChipRow<T> extends StatelessWidget {
  const _ChipRow({
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final String label;
  final List<_ChipOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(
            label,
            style: AppTypography.monoXs.copyWith(
              color: AppColors.textMute,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Row(
          children: [
            for (var i = 0; i < options.length; i++) ...[
              Expanded(
                child: _Chip<T>(
                  option: options[i],
                  selected: selected == options[i].value,
                  onTap: () => onSelect(options[i].value),
                ),
              ),
              if (i < options.length - 1) const SizedBox(width: 6),
            ],
          ],
        ),
      ],
    );
  }
}

class _Chip<T> extends StatelessWidget {
  const _Chip({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _ChipOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: selected ? 1.0 : 0.55,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : AppColors.card,
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.line2,
            ),
            borderRadius: BorderRadius.circular(AppRadius.sharp),
          ),
          alignment: Alignment.center,
          child: Text(
            option.label,
            style: AppTypography.mono.copyWith(
              fontSize: 11,
              color: selected ? AppColors.bgDeep : AppColors.textDim,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ),
      ),
    );
  }
}

class _Option<T> {
  const _Option({
    required this.value,
    required this.code,
    required this.title,
    required this.subtitle,
  });

  final T value;
  final String code;
  final String title;
  final String subtitle;
}

class _ChipOption<T> {
  const _ChipOption({required this.value, required this.label});

  final T value;
  final String label;
}
