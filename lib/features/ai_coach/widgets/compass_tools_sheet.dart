// Test #10 obs 5 — AI coach Compass tools sheet.
//
// Naval-themed shortcut palette opened from the compass-rose button on
// the LEFT of the AI coach composer. Commands grouped into 4 families
// matching the AI tool inventory in CLAUDE.md §11:
//   DRILL   · WORKOUT      → 5 cmds (8 workout tools subset)
//   GALLEY  · NUTRITION    → 3 cmds (4 nutrition tools subset)
//   ORDERS  · PLAN         → 4 cmds (5 plan tools subset)
//   INTEL   · PROGRESS     → 3 cmds (3 progress tools)
// 15 commands total. Tap a command → caller's `onSelect` fires with
// the prefill string, sheet pops itself. The AI coach screen sets the
// composer text + focuses the input. NO auto-fire — user always edits
// before sending so the LLM gets specific intent.

import 'package:flutter/material.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// One command in a family.
class _Cmd {
  final String slash; // e.g. '/SWAP'
  final String desc;
  final String prefill;
  const _Cmd(this.slash, this.desc, this.prefill);
}

/// One family group inside the sheet.
class _Family {
  final String label; // e.g. 'DRILL · WORKOUT'
  final List<_Cmd> commands;
  const _Family(this.label, this.commands);
}

const List<_Family> _families = [
  _Family('DRILL · WORKOUT', [
    _Cmd('/LOG', 'Log workout', 'Log my workout: '),
    _Cmd('/SWAP', 'Swap exercise', 'Swap [exercise] for '),
    _Cmd('/SHORTEN', 'Shorten today', 'Cut today\'s workout to 30 min'),
    _Cmd('/HOTEL', 'Travel workout',
        'I\'m travelling — give me a hotel-room workout'),
    _Cmd('/INJURY', 'Modify for injury',
        'Modify my plan — my [body part] hurts'),
  ]),
  _Family('GALLEY · NUTRITION', [
    _Cmd('/LOG MEAL', 'Log a meal', 'Log meal: '),
    _Cmd('/SUGGEST', 'Meal idea', 'Suggest a 600 kcal high-protein meal'),
    _Cmd('/TARGET', 'Adjust calorie target',
        'Adjust my calorie target to '),
  ]),
  _Family('ORDERS · PLAN', [
    _Cmd('/SHUFFLE', 'Regenerate plan', 'Regenerate this week\'s plan'),
    _Cmd('/SCHEDULE', 'Reschedule day', 'Reschedule [day] to '),
    _Cmd('/PAUSE', 'Pause plan', 'Pause my plan for '),
    _Cmd('/SWITCH', 'Change goal', 'Switch my goal to '),
  ]),
  _Family('INTEL · PROGRESS', [
    _Cmd('/PROGRESS', 'Progress summary', 'Show my progress this month'),
    _Cmd('/HISTORY', 'Exercise history', 'Show my [exercise] history'),
    _Cmd('/PR', 'Log a PR', 'Log a PR: '),
  ]),
];

class CompassToolsSheet extends StatelessWidget {
  const CompassToolsSheet({super.key, required this.onSelect});

  /// Caller receives the prefill string. The sheet pops itself before
  /// the callback fires so the caller can immediately request focus on
  /// the composer without a double-frame race.
  final ValueChanged<String> onSelect;

  static Future<void> show(
    BuildContext context, {
    required ValueChanged<String> onSelect,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => CompassToolsSheet(onSelect: onSelect),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.85,
      minChildSize: 0.4,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            14,
            AppSpacing.gutter,
            18,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '⊕ COMPASS · TOOLS',
                style: AppTypography.mono.copyWith(
                  fontSize: 11,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 14),
              ..._families.map((fam) => _FamilyBlock(
                    family: fam,
                    onSelect: (prefill) {
                      Navigator.of(ctx).pop();
                      onSelect(prefill);
                    },
                  )),
              const SizedBox(height: 6),
              Container(height: 1, color: AppColors.line2),
              const SizedBox(height: 10),
              Text(
                'Or just type to ask anything · the coach handles freeform text too',
                style: AppTypography.bodyS.copyWith(
                  color: AppColors.textMute,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FamilyBlock extends StatelessWidget {
  const _FamilyBlock({
    required this.family,
    required this.onSelect,
  });

  final _Family family;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              family.label,
              style: AppTypography.mono.copyWith(
                fontSize: 10,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
                color: AppColors.textDim,
              ),
            ),
          ),
          Container(height: 1, color: AppColors.line2),
          ...family.commands.map((cmd) => _CommandRow(
                cmd: cmd,
                onTap: () => onSelect(cmd.prefill),
              )),
        ],
      ),
    );
  }
}

class _CommandRow extends StatelessWidget {
  const _CommandRow({required this.cmd, required this.onTap});

  final _Cmd cmd;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            SizedBox(
              width: 92,
              child: Text(
                cmd.slash,
                style: AppTypography.mono.copyWith(
                  fontSize: 11,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                cmd.desc,
                style: AppTypography.body.copyWith(
                  fontSize: 12,
                  color: AppColors.textDim,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
