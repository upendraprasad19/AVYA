// Test #10 obs 5 — AI coach Compass tools sheet.
//
// Naval-themed shortcut palette opened from the compass-rose button on
// the LEFT of the AI coach composer. C6/B4 (spec 2026-09-18): the sheet is
// now a LAUNCHER, not a text-prefill palette. Structured commands open
// native capture sheets (log workout / swap) or light forms (injury /
// reschedule / switch goal / history); the remaining commands keep
// one-line prefills. /PR and /TARGET are REMOVED — they advertised logPR /
// adjustCaloricTarget, both deleted 2026-05-31 by ADR-0012 (derive-only
// surface); tapping them could only produce a dead-end conversation.
// NO prefill contains a [placeholder] token — placeholder commands became
// forms precisely so an unfilled "[exercise]" can never reach the model.

import 'package:flutter/material.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// What tapping a command does. Exported because the AI coach screen's
/// input bar routes on it (structured capture lives there — it needs the
/// composer's WidgetRef for pending intents).
enum CompassAction {
  logWorkout, // B1 — opens the structured log-workout sheet
  swap, // B2 — opens the structured swap sheet
  logMeal, // B3 — conversational prefill (canonical logMealByText writer)
  injuryForm, // B4 — light form (InjuryVocab picker)
  scheduleForm, // B4 — light form (day + date picker)
  switchForm, // B4 — light form (FitnessGoals picker)
  historyForm, // B4 — light form (exercise name)
  prefill, // plain one-line composer prefill
}

/// One command in a family.
class _Cmd {
  final String slash; // e.g. '/SWAP'
  final String desc;
  final String prefill;
  final CompassAction action;
  const _Cmd(this.slash, this.desc, this.prefill,
      {this.action = CompassAction.prefill});
}

/// One family group inside the sheet.
class _Family {
  final String label; // e.g. 'DRILL · WORKOUT'
  final List<_Cmd> commands;
  const _Family(this.label, this.commands);
}

const List<_Family> _families = [
  _Family('DRILL · WORKOUT', [
    _Cmd('/LOG', 'Log workout', '', action: CompassAction.logWorkout),
    _Cmd('/SWAP', 'Swap exercise', '', action: CompassAction.swap),
    _Cmd('/SHORTEN', 'Shorten today', 'Cut today\'s workout to 30 min'),
    _Cmd('/HOTEL', 'Travel workout',
        'I\'m travelling — give me a hotel-room workout'),
    _Cmd('/INJURY', 'Modify for injury', '', action: CompassAction.injuryForm),
  ]),
  _Family('GALLEY · NUTRITION', [
    _Cmd('/LOG MEAL', 'Log a meal', 'Log meal: ',
        action: CompassAction.logMeal),
    _Cmd('/SUGGEST', 'Meal idea', 'Suggest a 600 kcal high-protein meal'),
  ]),
  _Family('ORDERS · PLAN', [
    _Cmd('/SHUFFLE', 'Regenerate plan', 'Regenerate this week\'s plan'),
    _Cmd('/SCHEDULE', 'Reschedule day', '', action: CompassAction.scheduleForm),
    _Cmd('/PAUSE', 'Pause plan', 'Pause my plan for '),
    _Cmd('/SWITCH', 'Change goal', '', action: CompassAction.switchForm),
  ]),
  _Family('INTEL · PROGRESS', [
    _Cmd('/PROGRESS', 'Progress summary', 'Show my progress this month'),
    _Cmd('/HISTORY', 'Exercise history', '', action: CompassAction.historyForm),
  ]),
];

class CompassToolsSheet extends StatelessWidget {
  const CompassToolsSheet({super.key, required this.onSelect});

  /// Caller receives the command's action + prefill. The sheet pops itself
  /// before the callback fires so the caller can immediately act (open a
  /// capture sheet, or prefill + focus the composer).
  final void Function(String prefill, CompassAction action) onSelect;

  static Future<void> show(
    BuildContext context, {
    required void Function(String prefill, CompassAction action) onSelect,
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
                    onSelect: (cmd) {
                      Navigator.of(ctx).pop();
                      onSelect(cmd.prefill, cmd.action);
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
  final ValueChanged<_Cmd> onSelect;

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
                onTap: () => onSelect(cmd),
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
