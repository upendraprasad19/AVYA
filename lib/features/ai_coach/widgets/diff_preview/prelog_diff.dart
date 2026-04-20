import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/colors.dart';
import '../../models/tool_intent.dart';

/// Diff preview for a `prelog` intent (Phase C.4).
///
/// The intent payload already carries fully pre-parsed meals (the server-side
/// intentBuilder ran `parseFoodText` over each meal in parallel). This widget
/// is pure presentation — it groups meals by date and renders per-day
/// kcal/protein totals plus per-meal rows. Failed meals (parse failures from
/// the intentBuilder) are surfaced in a separate footer block so the user
/// knows what won't be logged.
class PrelogDiff extends StatelessWidget {
  final ToolIntent intent;
  const PrelogDiff({super.key, required this.intent});

  @override
  Widget build(BuildContext context) {
    final parsed = (intent.payload['parsed_meals'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        const <Map<String, dynamic>>[];
    final failed = (intent.payload['failed_meals'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        const <Map<String, dynamic>>[];

    if (parsed.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          failed.isEmpty
              ? 'No meals to pre-log.'
              : 'All ${failed.length} meals failed to parse. Try simpler descriptions.',
          style: GoogleFonts.getFont(
            'DM Sans',
            color: AppColors.textSecondary,
            fontSize: 13,
          ),
        ),
      );
    }

    // Group by date (sorted ascending so days read top-to-bottom in order).
    final byDate = <String, List<Map<String, dynamic>>>{};
    for (final m in parsed) {
      final d = m['date'] as String? ?? '';
      if (d.isEmpty) continue;
      byDate.putIfAbsent(d, () => []).add(m);
    }
    final sortedDates = byDate.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...sortedDates.map((date) => _buildDayCard(date, byDate[date]!)),
        if (failed.isNotEmpty) _buildFailedSection(failed),
      ],
    );
  }

  Widget _buildDayCard(String date, List<Map<String, dynamic>> meals) {
    final dayTotal =
        meals.fold<num>(0, (s, m) => s + ((m['total_calories'] as num?) ?? 0));
    final dayProtein =
        meals.fold<num>(0, (s, m) => s + ((m['total_protein_g'] as num?) ?? 0));
    final d = DateTime.tryParse(date);
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final dayLabel =
        d != null ? '${dayNames[d.weekday - 1]} ${d.day}' : date;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                dayLabel,
                style: GoogleFonts.getFont(
                  'DM Sans',
                  color: AppColors.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${dayTotal.toInt()} kcal \u00b7 ${dayProtein.toStringAsFixed(0)}g P',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    color: AppColors.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...meals.map(_buildMealRow),
        ],
      ),
    );
  }

  Widget _buildMealRow(Map<String, dynamic> m) {
    final mealType = m['meal_type'] as String?;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
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
                style: GoogleFonts.getFont(
                  'DM Sans',
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  height: 1.4,
                ),
                children: [
                  TextSpan(
                    text: m['food_name'] as String? ?? 'Meal',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (mealType != null && mealType.isNotEmpty)
                    TextSpan(
                      text: ' ($mealType)',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  TextSpan(
                    text:
                        '\n${m['total_calories'] ?? 0} kcal \u00b7 P${m['total_protein_g'] ?? 0}g C${m['total_carbs_g'] ?? 0}g F${m['total_fat_g'] ?? 0}g',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFailedSection(List<Map<String, dynamic>> failed) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, size: 14, color: AppColors.red),
              const SizedBox(width: 6),
              Text(
                '${failed.length} failed to parse',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  color: AppColors.red,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...failed.map((f) => Padding(
                padding: const EdgeInsets.only(top: 2, left: 20),
                child: Text(
                  '\u2022 "${f['original_description']}"',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    color: AppColors.textSecondary,
                    fontSize: 10,
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
