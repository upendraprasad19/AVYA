import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/injury_vocab.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import 'package:icanbefitter/core/constants/equipment_defaults.dart';

/// Step 04 · 05 of the stepped onboarding flow — training details capture.
///
/// **APK test #2 batch (2026-04-25) — redesign Q8.**
/// All 4 sections converted to chip rows (D3-redux: selected chip was
/// faded due to opacity wiring bug in the prior `_FadeSection` approach;
/// the new uniform `_ChipSection` + `_Chip` layout fixes selection
/// visibility and unifies the visual language across the screen).
///
/// Selected chip = gold-fill + `bgDeep` w700 text + opacity 1.0.
/// Unselected chip = transparent + `textGhost` border + `textDim` text
/// + opacity 0.55, 150 ms cross-fade.
///
/// Experience: 3 inline chips (Beginner / Intermediate / Advanced).
/// Pace:       3 inline chips (Steady / Balanced / Aggressive).
/// Days/Week:  4 inline chips (3 / 4 / 5 / 6).
/// Equipment:  2 × 2 grid (labels too long for a single row at 360 dp).
///
/// Description line below each section updates on selection — user sees
/// context for the chosen option without per-chip clutter.
///
/// Defaults pre-selected (Intermediate / Balanced / 4 / Basic Gym) so
/// CONTINUE always works with zero interactions.
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
  late List<String> _injuries;

  // ── Experience ────────────────────────────────────────────────────────
  static const _experiences = <_ChipOption<String>>[
    _ChipOption(value: 'beginner',     label: 'Beginner'),
    _ChipOption(value: 'intermediate', label: 'Intermediate'),
    _ChipOption(value: 'advanced',     label: 'Advanced'),
  ];

  static const _experienceDescriptions = <String, String>{
    'beginner':     'First 6 months of structured training.',
    'intermediate': '6 – 24 months of consistent training.',
    'advanced':     '24 + months of serious training.',
  };

  // ── Pace ──────────────────────────────────────────────────────────────
  static const _paces = <_ChipOption<String>>[
    _ChipOption(value: 'slow',       label: 'Steady'),
    _ChipOption(value: 'balanced',   label: 'Balanced'),
    _ChipOption(value: 'aggressive', label: 'Aggressive'),
  ];

  static const _paceDescriptions = <String, String>{
    'slow':       'Slow, sustainable — easiest to stick with.',
    'balanced':   'Evidence-based standard transformation rate.',
    'aggressive': 'Fast pace, high commitment, upper safe limit.',
  };

  // ── Days / week ───────────────────────────────────────────────────────
  static const _days = <_ChipOption<int>>[
    _ChipOption(value: 3, label: '3'),
    _ChipOption(value: 4, label: '4'),
    _ChipOption(value: 5, label: '5'),
    _ChipOption(value: 6, label: '6'),
  ];

  String _daysDescription() => switch (_daysPerWeek) {
        3 => '3 days · time-tight, efficient sessions.',
        4 => '4 days · most sustainable split.',
        5 => '5 days · serious commitment.',
        6 => '6 days · advanced high-frequency split.',
        _ => '$_daysPerWeek days per week.',
      };

  // ── Equipment ─────────────────────────────────────────────────────────
  static const _equipments = <_ChipOption<String>>[
    _ChipOption(value: 'bodyweight',    label: 'Bodyweight'),
    _ChipOption(value: 'home_dumbbells', label: 'Dumbbells'),
    _ChipOption(value: 'basic_gym',     label: 'Basic Gym'),
    _ChipOption(value: 'full_gym',      label: 'Full Gym'),
  ];

  static const _equipmentDescriptions = <String, String>{
    'bodyweight':     'No equipment needed — anywhere, anytime.',
    'home_dumbbells': 'Adjustable dumbbells at home.',
    'basic_gym':      'Standard gym setup, barbells + machines.',
    'full_gym':       'Full commercial gym access.',
  };

  @override
  void initState() {
    super.initState();
    _experience  = (widget.data['fitness_experience'] as String?) ?? 'intermediate';
    _pace        = (widget.data['pace_preference']    as String?) ?? 'balanced';
    _daysPerWeek = (widget.data['days_per_week']      as int?)    ?? 4;
    _equipment   = equipmentAccessOf(widget.data);
    // Seed injuries from the incoming extras (GROWABLE — the toggle mutates it in
    // place). MUST seed here or the plan→details "ADJUST PLAN" round-trip resets
    // a real selection to ['none'] before generation (×2 review P1-A). Type-check
    // (not `as List`) survives a legacy String value; a fresh list (not a cast
    // view) avoids mutating the shared extras map (P1-B).
    final rawInjuries = widget.data['injuries'];
    _injuries = rawInjuries is List
        ? rawInjuries.map((e) => e.toString()).toList()
        : <String>['none'];
    if (_injuries.isEmpty) _injuries = <String>['none'];
  }

  /// Shared none-toggle (pinned by injury_chip_vocab_contract_test.dart) — same
  /// logic Edit Profile uses, so the two chips can't diverge.
  void _toggleInjury(String token) {
    setState(() => _injuries = InjuryVocab.toggleChip(_injuries, token));
  }

  // ── Navigation ────────────────────────────────────────────────────────

  void _onContinue() {
    final enriched = <String, dynamic>{
      ...widget.data,
      'fitness_experience': _experience,
      'pace_preference':    _pace,
      'days_per_week':      _daysPerWeek,
      'equipment_access':   _equipment,
      'injuries':           _injuries,
    };
    context.go('/onboarding/plan', extra: enriched);
  }

  // ── Build ─────────────────────────────────────────────────────────────

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
                    // Safety net for small-viewport devices; content is tuned
                    // to fit 360×640 dp without scrolling.
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ChipSection<String>(
                          label: 'EXPERIENCE',
                          options: _experiences,
                          selected: _experience,
                          description: _experienceDescriptions[_experience] ?? '',
                          onSelect: (v) => setState(() => _experience = v),
                        ),
                        const SizedBox(height: 18),
                        _ChipSection<String>(
                          label: 'PACE',
                          options: _paces,
                          selected: _pace,
                          description: _paceDescriptions[_pace] ?? '',
                          onSelect: (v) => setState(() => _pace = v),
                        ),
                        const SizedBox(height: 18),
                        _ChipSection<int>(
                          label: 'DAYS / WEEK',
                          options: _days,
                          selected: _daysPerWeek,
                          description: _daysDescription(),
                          onSelect: (v) => setState(() => _daysPerWeek = v),
                        ),
                        const SizedBox(height: 18),
                        _EquipmentSection(
                          options: _equipments,
                          selected: _equipment,
                          description: _equipmentDescriptions[_equipment] ?? '',
                          onSelect: (v) => setState(() => _equipment = v),
                        ),
                        const SizedBox(height: 18),
                        _InjuriesSection(
                          selected: _injuries,
                          onToggle: _toggleInjury,
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
          '04 · 05',
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
                'CONTINUE →',
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

// ── Chip section (single row of chips + description) ──────────────────────

/// A labelled row of equal-width chips with a description line below.
/// Used for Experience (3), Pace (3), and Days/Week (4).
class _ChipSection<T> extends StatelessWidget {
  const _ChipSection({
    required this.label,
    required this.options,
    required this.selected,
    required this.description,
    required this.onSelect,
  });

  final String label;
  final List<_ChipOption<T>> options;
  final T selected;
  final String description;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(
            label,
            style: AppTypography.monoXs.copyWith(
              color: AppColors.accent,
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
        const SizedBox(height: 6),
        Text(
          description,
          style: AppTypography.bodyS.copyWith(color: AppColors.textDim),
        ),
      ],
    );
  }
}

// ── Equipment section (2 × 2 grid + description) ──────────────────────────

/// 2 × 2 chip grid for Equipment. Labels are too long to fit 4 in a
/// single row at 360 dp so we break into two rows of two.
class _EquipmentSection extends StatelessWidget {
  const _EquipmentSection({
    required this.options,
    required this.selected,
    required this.description,
    required this.onSelect,
  });

  final List<_ChipOption<String>> options;
  final String selected;
  final String description;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(
            'EQUIPMENT',
            style: AppTypography.monoXs.copyWith(
              color: AppColors.accent,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        for (var row = 0; row < 2; row++) ...[
          Row(
            children: [
              for (var col = 0; col < 2; col++) ...[
                Expanded(
                  child: _Chip<String>(
                    option: options[row * 2 + col],
                    selected: options[row * 2 + col].value == selected,
                    onTap: () => onSelect(options[row * 2 + col].value),
                  ),
                ),
                if (col == 0) const SizedBox(width: 6),
              ],
            ],
          ),
          if (row == 0) const SizedBox(height: 6),
        ],
        const SizedBox(height: 6),
        Text(
          description,
          style: AppTypography.bodyS.copyWith(color: AppColors.textDim),
        ),
      ],
    );
  }
}

// ── Injuries section (multi-select Wrap) ──────────────────────────────────

/// MULTI-select injury chips (Ship 3 / U5). Unlike the single-select rows above
/// a user can have several injuries, so this is a Wrap of toggle chips built
/// from the SHARED `InjuryVocab.chipTokens` + `chipLabel` (one vocab with Edit
/// Profile, pinned to the library — no drift). Pre-selected "No injuries" keeps
/// CONTINUE frictionless (founder Option B). Same visual as [_Chip].
class _InjuriesSection extends StatelessWidget {
  const _InjuriesSection({required this.selected, required this.onToggle});

  final List<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(
            'INJURIES / AREAS TO AVOID',
            style: AppTypography.monoXs.copyWith(
              color: AppColors.accent,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final token in InjuryVocab.chipTokens)
              _InjuryChip(
                label: InjuryVocab.chipLabel(token),
                selected: selected.contains(token),
                onTap: () => onToggle(token),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Tap any that apply — your plan avoids loading them.',
          style: AppTypography.bodyS.copyWith(color: AppColors.textDim),
        ),
      ],
    );
  }
}

/// Content-sized toggle chip for the injuries Wrap. Mirrors [_Chip]'s visual
/// (gold-fill selected / ghost-border unselected, 150 ms cross-fade) but sizes
/// to its label instead of Expanded.
class _InjuryChip extends StatelessWidget {
  const _InjuryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : Colors.transparent,
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.textGhost,
            ),
            borderRadius: BorderRadius.circular(AppRadius.sharp),
          ),
          child: Text(
            label,
            style: AppTypography.body.copyWith(
              fontSize: 13,
              color: selected ? AppColors.bgDeep : AppColors.textDim,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Chip ──────────────────────────────────────────────────────────────────

/// Single selectable chip.
/// Selected  → gold-fill + `bgDeep` w700 text + opacity 1.0.
/// Unselected → transparent + `textGhost` border + `textDim` text
///              + opacity 0.55. Both states cross-fade at 150 ms.
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
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : Colors.transparent,
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.textGhost,
            ),
            borderRadius: BorderRadius.circular(AppRadius.sharp),
          ),
          alignment: Alignment.center,
          child: Text(
            option.label,
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(
              fontSize: 13,
              color: selected ? AppColors.bgDeep : AppColors.textDim,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Data class ────────────────────────────────────────────────────────────

class _ChipOption<T> {
  const _ChipOption({required this.value, required this.label});

  final T value;
  final String label;
}
