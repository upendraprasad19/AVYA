// B4 (ai-coach-ux-tool-integrity spec 2026-09-18) — light forms for the
// Compass commands that CANNOT be a plain one-line prefill because a
// placeholder ("[exercise]", "[body part]") used to reach the model
// unfilled. Each form composes a COMPLETE sentence, then hands it to the
// composer via onCompose — the model still owns the conversation; only the
// placeholder-class tokens are eliminated.
//
//   injuryForm  — canonical InjuryVocab token picker (the tokens the injury
//                 tools actually normalize against, NOT free text)
//   scheduleForm— day picker + target date → a complete reschedule ask
//   switchForm  — FitnessGoals token picker (enum parity with switchGoal)
//   historyForm — exercise-name field
import 'package:flutter/material.dart';

import '../../../core/constants/fitness_goals.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/utils/injury_vocab.dart';
import '../../../core/utils/ist_date.dart';
import '../../../shared/widgets/wardroom/ward_button.dart';

import 'compass_tools_sheet.dart';

Future<void> showCompassFormSheet(
  BuildContext context,
  CompassAction action, {
  required ValueChanged<String> onCompose,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.bg,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => CompassFormSheet(action: action, onCompose: onCompose),
  );
}

class CompassFormSheet extends StatefulWidget {
  final CompassAction action;
  final ValueChanged<String> onCompose;

  const CompassFormSheet({
    super.key,
    required this.action,
    required this.onCompose,
  });

  @override
  State<CompassFormSheet> createState() => _CompassFormSheetState();
}

class _CompassFormSheetState extends State<CompassFormSheet> {
  String? _choice;
  DateTime? _targetDate;
  final _textCtrl = TextEditingController();

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  bool get _ready {
    switch (widget.action) {
      case CompassAction.injuryForm:
        return _choice != null;
      case CompassAction.scheduleForm:
        return _choice != null && _targetDate != null;
      case CompassAction.switchForm:
        return _choice != null;
      case CompassAction.historyForm:
        return _textCtrl.text.trim().isNotEmpty;
      case CompassAction.logWorkout:
      case CompassAction.swap:
      case CompassAction.logMeal:
      case CompassAction.prefill:
        return false; // not forms — launcher/prefill actions only
    }
  }

  void _compose() {
    if (!_ready) return;
    final String message;
    switch (widget.action) {
      case CompassAction.injuryForm:
        message = 'Modify my plan — my $_choice hurts';
        break;
      case CompassAction.scheduleForm:
        message = 'Reschedule my $_choice workout to '
            '${istDateStr(_targetDate!)}';
        break;
      case CompassAction.switchForm:
        message = 'Switch my goal to ${_choice!.replaceAll('_', ' ')}';
        break;
      case CompassAction.historyForm:
        message = 'Show my ${_textCtrl.text.trim()} history';
        break;
      default:
        return;
    }
    widget.onCompose(message);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(AppSpacing.gutter, 14, AppSpacing.gutter,
            18 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 12),
            Flexible(child: SingleChildScrollView(child: _buildFields())),
            const SizedBox(height: 14),
            WardButton(
              label: 'USE THIS',
              onPressed: _ready ? _compose : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final (title, subtitle) = switch (widget.action) {
      CompassAction.injuryForm => (
          'MODIFY FOR INJURY',
          'Pick the body part — the coach adjusts the plan around it.'
        ),
      CompassAction.scheduleForm => (
          'RESCHEDULE A DAY',
          'Which session, and to when?'
        ),
      CompassAction.switchForm => (
          'CHANGE GOAL',
          'Your plan regenerates around the new goal.'
        ),
      CompassAction.historyForm => (
          'EXERCISE HISTORY',
          'Which exercise?'
        ),
      _ => ('COMPASS', null),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
        const SizedBox(height: 12),
        Text(title,
            style: AppTypography.mono.copyWith(
              fontSize: 11,
              letterSpacing: 2,
              fontWeight: FontWeight.w800,
              color: AppColors.accent,
            )),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle,
              style: AppTypography.bodyS.copyWith(color: AppColors.textMute)),
        ],
      ],
    );
  }

  Widget _buildFields() {
    switch (widget.action) {
      case CompassAction.injuryForm:
        return _wrapChips(InjuryVocab.chipTokens
            .where((t) => t != 'none')
            .map((t) => (value: t, label: InjuryVocab.chipLabel(t)))
            .toList());
      case CompassAction.scheduleForm:
        final days = <(String, DateTime)>[];
        final today = nowWall();
        const weekdayNames = [
          'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
          'Sunday',
        ];
        for (var i = 0; i < 7; i++) {
          final d = today.add(Duration(days: i));
          days.add((weekdayNames[d.weekday - 1], d));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _wrapChips(days
                .map((d) => (value: d.$1, label: d.$1))
                .toList(growable: false)),
            const SizedBox(height: 12),
            Text('MOVE IT TO',
                style: AppTypography.bodyS
                    .copyWith(fontSize: 10, color: AppColors.textMute)),
            const SizedBox(height: 6),
            _wrapChips(days
                .map((d) => (
                      value: istDateStr(d.$2),
                      label: d.$1 == _choice ? 'TOMORROW' : d.$1
                    ))
                .toList(growable: false))
          ],
        );
      case CompassAction.switchForm:
        return _wrapChips(FitnessGoals.tokens
            .map((t) => (value: t, label: t.replaceAll('_', ' ')))
            .toList(growable: false));
      case CompassAction.historyForm:
        return TextField(
          controller: _textCtrl,
          onChanged: (_) => setState(() {}),
          style: AppTypography.body.copyWith(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'e.g. Bench Press',
            hintStyle:
                AppTypography.bodyS.copyWith(color: AppColors.textMute),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.line2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.accent),
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _wrapChips(List<({String value, String label})> chips) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: chips.map((c) {
        final selected = _choice == c.value ||
            (widget.action == CompassAction.scheduleForm &&
                _targetDate != null &&
                _targetDate == _parseDate(c.value));
        return InkWell(
          onTap: () => setState(() {
            if (widget.action == CompassAction.scheduleForm &&
                _isWeekday(c.value)) {
              _choice = c.value;
            } else if (widget.action == CompassAction.scheduleForm) {
              _targetDate = _parseDate(c.value);
            } else {
              _choice = c.value;
            }
          }),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? AppColors.input : AppColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? AppColors.accent : AppColors.line2,
              ),
            ),
            child: Text(
              selected ? '✓ ${c.label}' : c.label,
              style: AppTypography.body.copyWith(
                fontSize: 12,
                color: selected ? AppColors.accent : AppColors.textDim,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  bool _isWeekday(String value) =>
      const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
          .contains(value);

  DateTime? _parseDate(String iso) => DateTime.tryParse(iso);
}
