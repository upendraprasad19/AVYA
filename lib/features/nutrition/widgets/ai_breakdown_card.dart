import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
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
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
        child: WardCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: AppColors.bad, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  breakdown.error!,
                  style: AppTypography.bodySm.copyWith(color: AppColors.bad),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: WardCard(
        variant: WardCardVariant.hero,
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      breakdown.mealName,
                      style: AppTypography.h3,
                    ),
                  ),
                  WardChip(
                    label: '${breakdown.totalKcal} KCAL',
                    tone: WardChipTone.gold,
                  ),
                ],
              ),
            ),
            const WardRule(gold: true, margin: EdgeInsets.zero),

            // Food items
            ...breakdown.items.asMap().entries.map(
                  (e) => _buildItemRow(context, ref, e.value, e.key),
                ),

            const WardRule(margin: EdgeInsets.zero),
            // Footer buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () =>
                          ref.read(aiBreakdownProvider.notifier).saveMeal(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(AppRadius.sharp),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'SAVE MEAL',
                          style: AppTypography.mono.copyWith(
                            color: AppColors.bgDeep,
                            letterSpacing: 2,
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
                          horizontal: 18, vertical: 11),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.line2),
                        borderRadius: BorderRadius.circular(AppRadius.sharp),
                      ),
                      child: Text(
                        'CANCEL',
                        style: AppTypography.mono.copyWith(
                          color: AppColors.textDim,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemRow(
      BuildContext context, WidgetRef ref, AiFoodItem item, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line2)),
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
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.quantity,
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.textDim,
                  ),
                ),
              ],
            ),
          ),

          // Macros — PRO / CARB / FAT / FIBER / KCAL. Colors:
          // protein=gold, carb=parchment, fat=ghee-amber, fiber=teal, kcal=parchment.
          _macroCol(item.protein, 'PRO', AppColors.accent),
          const SizedBox(width: 6),
          _macroCol(item.carbs, 'CARB', AppColors.textPrimary),
          const SizedBox(width: 6),
          _macroCol(item.fat, 'FAT', AppColors.warn),
          const SizedBox(width: 6),
          _macroCol('${item.fiber}g', 'FIBER', AppColors.ok),
          const SizedBox(width: 6),
          _macroCol('${item.calories}', 'KCAL', AppColors.textPrimary),
          const SizedBox(width: 8),

          // Edit button — tappable
          GestureDetector(
            onTap: () => _showEditItemSheet(context, ref, item, index),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.input,
                borderRadius: BorderRadius.circular(AppRadius.sharp),
                border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.3)),
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

  void _showEditItemSheet(
      BuildContext context, WidgetRef ref, AiFoodItem item, int index) {
    final calCtrl = TextEditingController(text: '${item.calories}');
    final proteinCtrl =
        TextEditingController(text: item.protein.replaceAll('g', ''));
    final carbsCtrl =
        TextEditingController(text: item.carbs.replaceAll('g', ''));
    final fatCtrl = TextEditingController(text: item.fat.replaceAll('g', ''));
    final fiberCtrl = TextEditingController(text: '${item.fiber}');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppRadius.card)),
          ),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                        color: AppColors.line2,
                        borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 12),
              Text(
                'EDIT — ${item.name}'.toUpperCase(),
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                      child: _editField(
                          'Calories', calCtrl, AppColors.accent)),
                  const SizedBox(width: 6),
                  Expanded(
                      child: _editField(
                          'Protein (g)', proteinCtrl, AppColors.accent)),
                  const SizedBox(width: 6),
                  Expanded(
                      child:
                          _editField('Carbs (g)', carbsCtrl, AppColors.warn)),
                  const SizedBox(width: 6),
                  Expanded(
                      child: _editField(
                          'Fat (g)', fatCtrl, AppColors.bad)),
                  const SizedBox(width: 6),
                  Expanded(
                      child:
                          _editField('Fiber (g)', fiberCtrl, AppColors.ok)),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: () {
                    ref.read(aiBreakdownProvider.notifier).updateItem(
                          index,
                          calories:
                              int.tryParse(calCtrl.text) ?? item.calories,
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
                      borderRadius:
                          BorderRadius.circular(AppRadius.sharp),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'SAVE',
                      style: AppTypography.mono.copyWith(
                        color: AppColors.bgDeep,
                        letterSpacing: 2,
                      ),
                    ),
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
        Text(
          label.toUpperCase(),
          style: AppTypography.monoXs.copyWith(
            color: AppColors.textMute,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: AppColors.input,
            borderRadius: BorderRadius.circular(AppRadius.sharp),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: TextField(
            controller: ctrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: false),
            style: AppTypography.body.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
          style: AppTypography.body.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          label,
          style: AppTypography.monoXs.copyWith(
            color: AppColors.textMute,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}
