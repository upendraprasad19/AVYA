import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

import '../providers/diet_plan_provider.dart';

/// Today's meals, rendered as **4 fixed slots** (BREAKFAST / LUNCH / DINNER
/// / SNACK) per the Wardroom handoff
/// (`design_handoff_wardroom/src/screens/nutrition.jsx` lines 115–141).
///
/// * Populated slots — solid [AppColors.line2] border, gold eyebrow +
///   earliest time, total kcal on the right, items joined by ` · ` below.
/// * Empty slots — [WardDashedBorder] (accent @ 27% alpha), greyed eyebrow,
///   `+ LOG` CTA in accent mono. When a matching entry is present in
///   [plannedSlots] (saved diet plan), a "FROM YOUR DIET PLAN" hint row is
///   rendered between the eyebrow and the CTA with planned kcal + item
///   summary. Tapping invokes [onLogSlot] so the parent can open
///   `showFoodSearchSheet` pre-filled with the planned food name.
///
/// The slot order is fixed — DINNER still renders as a dashed empty slot
/// even when SNACK is populated (do NOT collapse empties). This matches the
/// handoff sample where all 4 slots are always visible.
class TodaysMealsCard extends StatelessWidget {
  final List<Map<String, dynamic>> meals;
  final void Function(Map<String, dynamic> meal)? onEdit;
  final void Function(String logId)? onDelete;

  /// Invoked on long-press of any populated meal item (Plan C-14).
  /// Receives the full meal map so the parent can show the
  /// Edit / Delete / Save-as-template action menu.
  final void Function(Map<String, dynamic> meal)? onLongPressMeal;

  /// Invoked when the `+ LOG` CTA on an empty slot is tapped. The string is
  /// the slot key in lowercase (`breakfast` / `lunch` / `dinner` / `snack`),
  /// safe to pass directly as `mealType:` to `showFoodSearchSheet`.
  final void Function(String slot)? onLogSlot;

  /// Optional planned-meal hints keyed by slot (`breakfast` / `lunch` /
  /// `dinner` / `snack`). When an entry is present and the slot is empty,
  /// the empty-slot card renders a "FROM YOUR DIET PLAN" subline.
  final Map<String, PlannedSlot>? plannedSlots;

  const TodaysMealsCard({
    super.key,
    required this.meals,
    this.onEdit,
    this.onDelete,
    this.onLongPressMeal,
    this.onLogSlot,
    this.plannedSlots,
  });

  static const _slotOrder = <String>['breakfast', 'lunch', 'dinner', 'snack'];
  static const _slotLabel = <String, String>{
    'breakfast': 'BREAKFAST',
    'lunch': 'LUNCH',
    'dinner': 'DINNER',
    'snack': 'SNACK',
  };

  @override
  Widget build(BuildContext context) {
    // Group incoming meals by normalized slot key. Unknown meal_type falls
    // back to 'snack' so the log always shows up somewhere rather than
    // silently disappearing.
    final grouped = <String, List<Map<String, dynamic>>>{
      for (final k in _slotOrder) k: <Map<String, dynamic>>[],
    };
    for (final meal in meals) {
      final raw = (meal['meal_type_label'] as String? ??
              meal['meal_type'] as String? ??
              '')
          .toLowerCase();
      final key = switch (raw) {
        'breakfast' => 'breakfast',
        'lunch' => 'lunch',
        'dinner' => 'dinner',
        'snack' || 'snacks' => 'snack',
        _ => 'snack',
      };
      grouped[key]!.add(meal);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final slot in _slotOrder) ...[
          if (grouped[slot]!.isEmpty)
            _EmptySlotCard(
              slot: slot,
              label: _slotLabel[slot]!,
              planned: plannedSlots?[slot],
              onTap: onLogSlot == null ? null : () => onLogSlot!(slot),
            )
          else
            _PopulatedSlotCard(
              slot: slot,
              label: _slotLabel[slot]!,
              items: grouped[slot]!,
              onEdit: onEdit,
              onDelete: onDelete,
              onLongPressMeal: onLongPressMeal,
            ),
          if (slot != _slotOrder.last) const SizedBox(height: 6),
        ],
      ],
    );
  }
}

// ── Populated slot ──────────────────────────────────────────────────

class _PopulatedSlotCard extends StatelessWidget {
  const _PopulatedSlotCard({
    required this.slot,
    required this.label,
    required this.items,
    required this.onEdit,
    required this.onDelete,
    required this.onLongPressMeal,
  });

  final String slot;
  final String label;
  final List<Map<String, dynamic>> items;
  final void Function(Map<String, dynamic> meal)? onEdit;
  final void Function(String logId)? onDelete;
  final void Function(Map<String, dynamic> meal)? onLongPressMeal;

  @override
  Widget build(BuildContext context) {
    // Sum kcal across every entry in this slot; earliest logged time
    // becomes the slot time label (matches the handoff sample — breakfast
    // shows 08:14, the earliest eaten item).
    int totalKcal = 0;
    DateTime? earliest;
    for (final item in items) {
      totalKcal += (item['total_calories'] as num?)?.round() ?? 0;
      final createdAt = item['created_at'] as String?;
      if (createdAt != null && createdAt.isNotEmpty) {
        final parsed = DateTime.tryParse(createdAt);
        if (parsed != null &&
            (earliest == null || parsed.isBefore(earliest))) {
          earliest = parsed;
        }
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line2),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: eyebrow · time · kcal
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                label,
                style: AppTypography.mono.copyWith(
                  fontSize: 10,
                  color: AppColors.accent,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (earliest != null) ...[
                const SizedBox(width: 10),
                Text(
                  '\u00B7 ${_formatTime(earliest)}',
                  style: AppTypography.monoXs.copyWith(
                    fontSize: 9,
                    color: AppColors.textGhost,
                  ),
                ),
              ],
              const Spacer(),
              Text(
                '$totalKcal kcal',
                style: AppTypography.mono.copyWith(
                  fontSize: 12,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Items joined by ` · ` — tap any item for edit, swipe for delete.
          // To preserve per-item edit/delete affordances the list is stacked
          // as one tappable row per item; handoff rendering remains (dim
          // DM Sans 12 joined by separator) via the separator widget.
          ..._buildItemRows(context),
        ],
      ),
    );
  }

  List<Widget> _buildItemRows(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final name = item['food_name'] as String? ?? 'Unknown';
      final logId = item['id'] as String?;

      Widget row = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onEdit == null ? null : () => onEdit!(item),
        onLongPress:
            onLongPressMeal == null ? null : () => onLongPressMeal!(item),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                name,
                style: AppTypography.body.copyWith(
                  fontSize: 12,
                  color: AppColors.textDim,
                  height: 1.4,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onEdit != null) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.edit_outlined,
                size: 12,
                color: AppColors.textDim.withValues(alpha: 0.6),
              ),
            ],
          ],
        ),
      );

      if (onDelete != null && logId != null) {
        row = Dismissible(
          key: ValueKey('meal_item_$logId'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 12),
            color: AppColors.bad.withValues(alpha: 0.15),
            child: Icon(Icons.delete_outline, color: AppColors.bad, size: 16),
          ),
          onDismissed: (_) => onDelete!(logId),
          child: row,
        );
      }

      rows.add(row);
      if (i < items.length - 1) {
        // Subtle separator between items — dim ` · ` matches the JSX
        // `items.join(' · ')` pattern but keeps each item independently
        // tappable/swipeable.
        rows.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '\u00B7',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.textGhost,
                fontSize: 10,
              ),
            ),
          ),
        );
      }
    }
    return rows;
  }

  static String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final period = hour >= 12 ? 'PM' : 'AM';
    return '$h12:$minute $period';
  }
}

// ── Empty slot ──────────────────────────────────────────────────────

class _EmptySlotCard extends StatelessWidget {
  const _EmptySlotCard({
    required this.slot,
    required this.label,
    required this.onTap,
    this.planned,
  });

  final String slot;
  final String label;
  final VoidCallback? onTap;

  /// Optional planned-meal hint. When present, a "FROM YOUR DIET PLAN"
  /// subline with kcal + joined item names is rendered below the eyebrow
  /// row. Tapping the card still invokes [onTap] — the parent uses the
  /// `PlannedSlot.firstFoodName` to pre-fill the food search.
  final PlannedSlot? planned;

  @override
  Widget build(BuildContext context) {
    final hasPlan = planned != null && planned!.summary.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: WardDashedBorder(
        color: AppColors.accent.withValues(alpha: 0.27),
        strokeWidth: 1,
        dashLength: 4,
        gapLength: 3,
        radius: AppRadius.card.toDouble(),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top row: eyebrow (+ planned kcal) · + LOG
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    label,
                    style: AppTypography.mono.copyWith(
                      fontSize: 10,
                      color: AppColors.textMute,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (hasPlan) ...[
                    const SizedBox(width: 10),
                    Text(
                      '\u00B7 ~${planned!.calories.round()} kcal',
                      style: AppTypography.monoXs.copyWith(
                        fontSize: 9,
                        color: AppColors.textGhost,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    '+ LOG',
                    style: AppTypography.mono.copyWith(
                      fontSize: 10,
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
              if (hasPlan) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FROM YOUR DIET PLAN',
                      style: AppTypography.monoXs.copyWith(
                        fontSize: 9,
                        color: AppColors.accent.withValues(alpha: 0.75),
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        planned!.summary,
                        style: AppTypography.body.copyWith(
                          fontSize: 12,
                          color: AppColors.textDim,
                          height: 1.4,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
