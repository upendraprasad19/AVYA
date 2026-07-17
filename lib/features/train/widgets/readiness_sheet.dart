// ⑥ Batch 6 (W2.3) — the skippable 3×3 readiness check-in sheet + the
// callsite orchestration helper. The sheet CANNOT live on the notifier (no
// BuildContext) — it is shown here, at the widget layer, from the two START
// buttons (hero_cards + planned_expansion) via `beginWorkoutWithReadiness`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:icanbefitter/core/services/health_read_service.dart';
import 'package:icanbefitter/core/services/health_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/core/utils/readiness.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

import '../providers/train_provider.dart';

/// Resolve today's readiness (flag-gated), then start the workout. Flag OFF →
/// straight through (byte-identical to today). Flag ON: re-apply today's STORED
/// check-in if present (app-kill re-entry → NEVER re-prompt / re-derive — the
/// healthBox row is the single source), else show the skippable 3×3 sheet. The
/// chosen/stored level flows into `startWorkout`. Callers navigate AFTER this.
Future<void> beginWorkoutWithReadiness(
    BuildContext context, WidgetRef ref, WorkoutDayData day) async {
  final notifier = ref.read(activeWorkoutProvider.notifier);
  if (!PlanEngineFlags.readinessEnabled) {
    notifier.startWorkout(day);
    return;
  }
  ReadinessLevel? level =
      HealthReadService.instance.readinessForDate(nowWall())?.level;
  if (level == null && context.mounted) {
    level = await showReadinessSheet(context);
  }
  notifier.startWorkout(day, readiness: level);
}

/// Shows the skippable 3×3 sheet. On START writes `readiness_<today>` via
/// `HealthWriteService.logReadiness` + returns the computed level. On SKIP or
/// dismiss → null (no adjustment).
Future<ReadinessLevel?> showReadinessSheet(BuildContext context) {
  return showModalBottomSheet<ReadinessLevel>(
    context: context,
    backgroundColor: AppColors.card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => const _ReadinessSheet(),
  );
}

class _ReadinessSheet extends StatefulWidget {
  const _ReadinessSheet();
  @override
  State<_ReadinessSheet> createState() => _ReadinessSheetState();
}

class _ReadinessSheetState extends State<_ReadinessSheet> {
  // 0 = best, 1 = mid, 2 = worst. Default mid (a neutral starting point).
  int _sleep = 1, _soreness = 1, _energy = 1;

  static const _sleepLabels = ['Solid', 'Okay', 'Rough'];
  static const _soreLabels = ['Fresh', 'A little', 'Beat up'];
  static const _energyLabels = ['Charged', 'Normal', 'Running low'];

  Future<void> _start() async {
    await HealthWriteService.instance.logReadiness(
      date: nowWall(),
      sleep: _sleep,
      soreness: _soreness,
      energy: _energy,
      source: WriteSource.manual,
    );
    final level =
        readinessLevelFor(sleep: _sleep, soreness: _soreness, energy: _energy);
    if (mounted) Navigator.of(context).pop(level);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'READINESS CHECK',
              style: AppTypography.mono
                  .copyWith(color: AppColors.accent, letterSpacing: 2),
            ),
            const SizedBox(height: 6),
            Text(
              'A quick read so today fits how you feel. Skippable.',
              style:
                  AppTypography.monoXs.copyWith(color: AppColors.textDim, height: 1.4),
            ),
            const SizedBox(height: 18),
            _Row(
              label: 'SLEEP',
              options: _sleepLabels,
              selected: _sleep,
              onSelect: (i) => setState(() => _sleep = i),
            ),
            const SizedBox(height: 14),
            _Row(
              label: 'SORENESS',
              options: _soreLabels,
              selected: _soreness,
              onSelect: (i) => setState(() => _soreness = i),
            ),
            const SizedBox(height: 14),
            _Row(
              label: 'ENERGY',
              options: _energyLabels,
              selected: _energy,
              onSelect: (i) => setState(() => _energy = i),
            ),
            const SizedBox(height: 22),
            WardButton(
              label: 'START WORKOUT',
              variant: WardButtonVariant.primary,
              onPressed: () => _start(),
            ),
            const SizedBox(height: 8),
            WardButton(
              label: 'SKIP',
              variant: WardButtonVariant.ghost,
              onPressed: () => Navigator.of(context).pop(null),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final String label;
  final List<String> options;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.monoXs
              .copyWith(color: AppColors.textDim, letterSpacing: 1.5),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _OptionChip(
                  label: options[i],
                  selected: selected == i,
                  onTap: () => onSelect(i),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
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
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : AppColors.input,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label.toUpperCase(),
          textAlign: TextAlign.center,
          style: AppTypography.monoXs.copyWith(
            color: selected ? AppColors.accent : AppColors.textDim,
            letterSpacing: 0.8,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}
