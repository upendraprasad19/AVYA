import 'package:flutter/material.dart';
import '../../../../core/theme/colors.dart';
import '../../models/tool_intent.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Diff preview for a `create_custom_template` intent (Phase D.6).
///
/// Renders a gold-bordered header card with the template name, optional
/// description, totals (days × exercises), and any suggested weekday
/// assignments. Each day below is a collapsible `ExpansionTile` — the first
/// day expands by default for instant scan, subsequent days collapse to keep
/// the bottom sheet readable when the AI proposes a 5- or 6-day split.
///
/// Pure presentation: no Hive reads, no async — the intent payload carries
/// the full template structure (name + days[] with per-exercise rows).
class CustomTemplateDiff extends StatelessWidget {
  final ToolIntent intent;
  const CustomTemplateDiff({super.key, required this.intent});

  @override
  Widget build(BuildContext context) {
    final p = intent.payload;
    final name = p['name'] as String? ?? 'Custom Template';
    final description = p['description'] as String?;
    final days = ((p['days'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    final assignedDays = ((p['assigned_days'] as List?) ?? const [])
        .whereType<num>()
        .map((n) => n.toInt())
        .where((n) => n >= 1 && n <= 7)
        .toList();

    if (days.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Empty template — no days to save.',
          style: AppTypography.bodyM.copyWith(color: AppColors.red),
        ),
      );
    }

    final totalExercises = days.fold<int>(
      0,
      (s, d) => s + ((d['exercises'] as List?)?.length ?? 0),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header card — gold accent so the "new template" intent reads as
        // important without competing with destructive-class red.
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.proGold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.proGold.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: AppTypography.body.copyWith(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              if (description != null && description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  description,
                  style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                '${days.length} day${days.length == 1 ? "" : "s"} \u2022 '
                '$totalExercises exercises total',
                style: AppTypography.body.copyWith(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.proGold),
              ),
              if (assignedDays.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Suggested weekdays: ${_formatAssignedDays(assignedDays)}',
                  style: AppTypography.body.copyWith(fontSize: 11, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                'Saved to your templates library — not auto-scheduled.',
                style: AppTypography.body.copyWith(fontSize: 10, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        // Each day collapsible.
        ...days.asMap().entries.map(
              (e) => _DayExpansionTile(
                index: e.key,
                day: e.value,
                initiallyExpanded: e.key == 0,
              ),
            ),
      ],
    );
  }

  static String _formatAssignedDays(List<int> days) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days.map((d) => names[d - 1]).join(', ');
  }
}

/// One day's collapsible card. Extracted to its own widget so each tile gets
/// a clean Theme override (transparent divider) without relying on
/// `Theme.of(context)` from a parent's build closure.
class _DayExpansionTile extends StatelessWidget {
  final int index;
  final Map<String, dynamic> day;
  final bool initiallyExpanded;

  const _DayExpansionTile({
    required this.index,
    required this.day,
    required this.initiallyExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final dayName = (day['dayName'] as String?) ?? 'Day ${index + 1}';
    final exercises = ((day['exercises'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          initiallyExpanded: initiallyExpanded,
          title: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'DAY ${index + 1}',
                  style: AppTypography.body.copyWith(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accent),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  dayName,
                  style: AppTypography.body.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
              ),
              Text(
                '${exercises.length} ex',
                style: AppTypography.body.copyWith(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
          children: exercises.map(_buildExerciseRow).toList(),
        ),
      ),
    );
  }

  Widget _buildExerciseRow(Map<String, dynamic> ex) {
    final name = (ex['exerciseName'] ?? ex['exercise_name'] ?? 'Exercise')
        .toString();
    final sets = ex['sets']?.toString() ?? '?';
    final reps = ex['reps']?.toString();
    final duration = (ex['durationSeconds'] as num?)?.toInt();
    final rest = (ex['restSeconds'] as num?)?.toInt();

    final volumeLabel = reps != null && reps.isNotEmpty
        ? '$sets \u00d7 $reps'
        : (duration != null
            ? '$sets \u00d7 ${duration}s'
            : '$sets sets');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5),
            width: 4,
            height: 4,
            decoration: const BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: AppTypography.bodySm.copyWith(color: AppColors.textPrimary, height: 1.3),
                children: [
                  TextSpan(
                    text: name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: '  $volumeLabel',
                    style: AppTypography.body.copyWith(fontSize: 11, color: AppColors.textSecondary),
                  ),
                  if (rest != null)
                    TextSpan(
                      text: '  \u2022 ${rest}s rest',
                      style: AppTypography.body.copyWith(fontSize: 10, color: AppColors.textSecondary),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
