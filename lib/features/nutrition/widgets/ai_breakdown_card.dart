import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import '../providers/nutrition_provider.dart';

/// Shows the AI-analysed food breakdown card with items, macros, and save/cancel.
class AiBreakdownCard extends ConsumerWidget {
  const AiBreakdownCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final breakdown = ref.watch(aiBreakdownProvider);
    if (breakdown == null) return const SizedBox.shrink();

    // Show error state if AI analysis failed
    if (breakdown.error != null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.cardS),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                breakdown.error!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.cardS),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.05),
              border: Border(
                bottom: BorderSide(
                  color: AppColors.accent.withValues(alpha: 0.1),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  breakdown.mealName,
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '${breakdown.totalKcal} kcal total',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
          ),

          // Food items
          ...breakdown.items.asMap().entries.map(
            (e) => _buildItemRow(context, ref, e.value, e.key),
          ),

          // Footer buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: const BoxDecoration(
              color: AppColors.card,
              border: Border(
                top: BorderSide(color: AppColors.border),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () =>
                        ref.read(aiBreakdownProvider.notifier).saveMeal(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '\u2713 Save Meal',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () =>
                      ref.read(aiBreakdownProvider.notifier).clear(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(BuildContext context, WidgetRef ref, AiFoodItem item, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Name & quantity
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  item.quantity,
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Macros
          _macroCol(item.protein, 'PRO', AppColors.orange),
          const SizedBox(width: 8),
          _macroCol(item.carbs, 'CARB', AppColors.blue),
          const SizedBox(width: 8),
          _macroCol('${item.calories}', 'KCAL', AppColors.accent),
          const SizedBox(width: 10),

          // Edit button — tappable
          GestureDetector(
            onTap: () => _showEditItemSheet(context, ref, item, index),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.input,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
              ),
              child: const Icon(
                Icons.edit,
                size: 12,
                color: AppColors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditItemSheet(BuildContext context, WidgetRef ref, AiFoodItem item, int index) {
    final calCtrl = TextEditingController(text: '${item.calories}');
    final proteinCtrl = TextEditingController(text: item.protein.replaceAll('g', ''));
    final carbsCtrl = TextEditingController(text: item.carbs.replaceAll('g', ''));
    final fatCtrl = TextEditingController(text: item.fat.replaceAll('g', ''));
    final fiberCtrl = TextEditingController(text: '${item.fiber}');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 12),
              Text('EDIT — ${item.name}',
                style: GoogleFonts.getFont('DM Sans', fontSize: 10, fontWeight: FontWeight.w700,
                  letterSpacing: 1.0, color: AppColors.textSecondary)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _editField('Calories', calCtrl, AppColors.accent)),
                  const SizedBox(width: 6),
                  Expanded(child: _editField('Protein (g)', proteinCtrl, AppColors.orange)),
                  const SizedBox(width: 6),
                  Expanded(child: _editField('Carbs (g)', carbsCtrl, AppColors.blue)),
                  const SizedBox(width: 6),
                  Expanded(child: _editField('Fat (g)', fatCtrl, AppColors.textSecondary)),
                  const SizedBox(width: 6),
                  Expanded(child: _editField('Fiber (g)', fiberCtrl, AppColors.green)),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: () {
                    ref.read(aiBreakdownProvider.notifier).updateItem(
                      index,
                      calories: int.tryParse(calCtrl.text) ?? item.calories,
                      protein: int.tryParse(proteinCtrl.text) ?? 0,
                      carbs: int.tryParse(carbsCtrl.text) ?? 0,
                      fat: int.tryParse(fatCtrl.text) ?? 0,
                      fiber: int.tryParse(fiberCtrl.text) ?? item.fiber,
                    );
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    alignment: Alignment.center,
                    child: Text('Save',
                      style: GoogleFonts.getFont('DM Sans',
                        fontSize: 13, fontWeight: FontWeight.w900, color: Colors.black)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _editField(String label, TextEditingController ctrl, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.getFont('DM Sans', fontSize: 9,
            fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: AppColors.input,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            style: GoogleFonts.getFont('DM Sans', fontSize: 13,
                fontWeight: FontWeight.w700, color: color),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _macroCol(String value, String label, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 8,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
