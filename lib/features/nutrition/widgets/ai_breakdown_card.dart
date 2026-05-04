import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import '../providers/nutrition_provider.dart';
import '../services/meal_slot_inference.dart';

/// Shows the AI-analysed food breakdown card with items, macros, and save/cancel.
class AiBreakdownCard extends ConsumerStatefulWidget {
  const AiBreakdownCard({super.key});

  @override
  ConsumerState<AiBreakdownCard> createState() => _AiBreakdownCardState();
}

class _AiBreakdownCardState extends ConsumerState<AiBreakdownCard> {
  /// Guards against double-tap while the first [saveMeal] await is in flight.
  /// On success the card vanishes (state cleared), so the second tap would
  /// fall through harmlessly — but on failure the card stays visible (correct:
  /// user can retry), and without this flag a second tap fires a second
  /// [NutritionWriteService.logMeal] call. Pattern mirrors scan_meal_section.dart.
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
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

    // Slot chip — time-inferred default, user can override via popup menu.
    // Writing through `mealTypeProvider` so the SCAN flow (or any other
    // consumer) can pick the same slot if they share the card.
    final slot = ref.watch(mealTypeProvider);

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

            // Slot chip row — Logging to: 🍱 LUNCH ▾
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Row(
                children: [
                  Text(
                    'LOGGING TO',
                    style: AppTypography.monoXs.copyWith(
                      color: AppColors.textMute,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  MealSlotChip(
                    slot: slot,
                    onSelected: (s) =>
                        ref.read(mealTypeProvider.notifier).select(s),
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
                      onTap: _saving
                          ? null
                          : () async {
                              setState(() => _saving = true);
                              final messenger = ScaffoldMessenger.of(context);
                              final result = await ref
                                  .read(aiBreakdownProvider.notifier)
                                  .saveMeal(mealType: slot);
                              if (!context.mounted) return;
                              if (result.success) {
                                HapticFeedback.lightImpact();
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Meal saved ✓',
                                      style: AppTypography.body,
                                    ),
                                    backgroundColor: AppColors.ok,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                                // State cleared by notifier on success; widget
                                // will unmount — no need to reset _saving.
                              } else {
                                setState(() => _saving = false);
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      result.isNoState
                                          ? 'Already saved.'
                                          : 'Could not save — try again.',
                                      style: AppTypography.body,
                                    ),
                                    backgroundColor: AppColors.bad,
                                    duration: const Duration(seconds: 3),
                                  ),
                                );
                              }
                            },
                      child: AnimatedOpacity(
                        opacity: _saving ? 0.45 : 1.0,
                        duration: const Duration(milliseconds: 150),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius:
                                BorderRadius.circular(AppRadius.sharp),
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

/// Inline chip that shows the inferred meal slot with a dropdown caret.
/// Tap opens a 4-option `PopupMenuButton` so the user can override the
/// inference (e.g. logging yesterday's dinner at noon).
///
/// Reused across the AI-breakdown card and the scan-meal editor to keep
/// the affordance consistent.
class MealSlotChip extends StatelessWidget {
  const MealSlotChip({
    super.key,
    required this.slot,
    required this.onSelected,
  });

  final String slot;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final emoji = mealSlotEmoji(slot);
    final label = mealSlotLabel(slot);

    return PopupMenuButton<String>(
      onSelected: onSelected,
      tooltip: 'Change meal slot',
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sharp),
        side: const BorderSide(color: AppColors.line2),
      ),
      itemBuilder: (ctx) => [
        for (final s in mealSlotKeys)
          PopupMenuItem<String>(
            value: s,
            child: Row(
              children: [
                Text(mealSlotEmoji(s)),
                const SizedBox(width: 8),
                Text(
                  mealSlotLabel(s),
                  style: AppTypography.mono.copyWith(
                    color: s == slot
                        ? AppColors.accent
                        : AppColors.textPrimary,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          border: Border.all(
            color: AppColors.accent.withValues(alpha: 0.30),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTypography.mono.copyWith(
                color: AppColors.accent,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.arrow_drop_down,
              color: AppColors.accent,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}
