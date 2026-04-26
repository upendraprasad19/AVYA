import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import '../providers/nutrition_provider.dart';

/// Hydration & Urine combined card (Q8.1=A, APK Test #3 redesign).
///
/// Replaces both `hydration_section.dart` and the inline
/// `_buildInlineWaterTracker` from `nutrition_screen.dart`. Single
/// `WardCard`, two rows:
///
///   Row 1 — water progress (`1.7 / 3.0 L`), 8-cell glass grid,
///           `[+ 250ML]` `[+ 500ML]` quick-add buttons.
///   Row 2 — `URINE STATUS · <LABEL>` pill + `[change ▾]` toggle that
///           expands an 8-color picker inline. One-line tip below.
///
/// All state delegated to existing providers — no new Hive writes.
class HydrationCard extends ConsumerStatefulWidget {
  const HydrationCard({super.key});

  @override
  ConsumerState<HydrationCard> createState() => _HydrationCardState();
}

class _HydrationCardState extends ConsumerState<HydrationCard> {
  bool _showColorPicker = false;

  // Same 7-step ladder used in the legacy widget. Kept verbatim so saved
  // urine indices remain semantically identical.
  static const _urineColors = [
    (color: Color(0xFFFFF9C4), status: 'Excellent',
        tip: 'Pale straw — optimal', tone: WardChipTone.ok),
    (color: Color(0xFFFFF176), status: 'Well hydrated',
        tip: 'Clear yellow — well hydrated', tone: WardChipTone.ok),
    (color: Color(0xFFFFD600), status: 'Adequate',
        tip: 'Yellow — drink more soon', tone: WardChipTone.warn),
    (color: Color(0xFFFFB300), status: 'Low',
        tip: 'Dark yellow — drink now', tone: WardChipTone.warn),
    (color: Color(0xFFE65100), status: 'Very low',
        tip: 'Amber — significantly dehydrated', tone: WardChipTone.bad),
    (color: Color(0xFFBF360C), status: 'Critical',
        tip: 'Brown — consult a doctor', tone: WardChipTone.bad),
    (color: Color(0xFF4E342E), status: 'See doctor',
        tip: 'Dark brown — medical attention', tone: WardChipTone.bad),
  ];

  @override
  Widget build(BuildContext context) {
    final waterMl = ref.watch(waterIntakeProvider);
    const waterTarget = 3000;
    final progress = (waterMl / waterTarget).clamp(0.0, 1.0);
    final selectedUrine = ref.watch(urineColorProvider);

    return WardCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Row 1: Water ──────────────────────────────────────
          _buildWaterRow(waterMl, waterTarget, progress),

          const SizedBox(height: 12),
          const WardRule(margin: EdgeInsets.zero),
          const SizedBox(height: 12),

          // ── Row 2: Urine status ───────────────────────────────
          _buildUrineRow(selectedUrine),
        ],
      ),
    );
  }

  // ── Row 1: water progress + glass grid + quick-add buttons ──
  Widget _buildWaterRow(int waterMl, int waterTarget, double progress) {
    final litres = (waterMl / 1000).toStringAsFixed(1);
    final targetLitres = (waterTarget / 1000).toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'HYDRATION & STATUS',
              style: AppTypography.mono.copyWith(
                color: AppColors.textMute,
                letterSpacing: 2,
              ),
            ),
            const Spacer(),
            Text(
              '$litres / $targetLitres L',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Builder(builder: (_) {
          const glassMl = 375;
          final filled = (waterMl / glassMl).floor().clamp(0, 8);
          return WardGlassGrid(
            filled: filled,
            slots: 8,
            onAdd: () => ref
                .read(waterIntakeProvider.notifier)
                .addWater(glassMl),
            onDecrement: () => ref
                .read(waterIntakeProvider.notifier)
                .addWater(-glassMl),
          );
        }),
        const SizedBox(height: 10),
        WardBar(pct: progress, color: AppColors.info, height: 4),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _quickAddButton('+ 250ML', 250)),
            const SizedBox(width: 8),
            Expanded(child: _quickAddButton('+ 500ML', 500)),
          ],
        ),
      ],
    );
  }

  Widget _quickAddButton(String label, int amount) {
    return GestureDetector(
      onTap: () =>
          ref.read(waterIntakeProvider.notifier).addWater(amount),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: AppColors.input,
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          border: Border.all(
              color: AppColors.info.withValues(alpha: 0.3)),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: AppTypography.mono.copyWith(
            color: AppColors.info,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }

  // ── Row 2: urine status pill + change toggle + inline picker ──
  Widget _buildUrineRow(int selectedUrine) {
    final hasSelection =
        selectedUrine >= 0 && selectedUrine < _urineColors.length;
    final entry = hasSelection ? _urineColors[selectedUrine] : null;
    final pillLabel = hasSelection
        ? 'URINE STATUS · ${entry!.status.toUpperCase()}'
        : 'URINE STATUS · NOT LOGGED';
    final pillTone = hasSelection ? entry!.tone : WardChipTone.neutral;
    final tipLine = hasSelection
        ? entry!.tip
        : 'Tap change ▾ to log how your urine looks today.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            WardChip(label: pillLabel, tone: pillTone),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(
                  () => _showColorPicker = !_showColorPicker),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'change',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.accent,
                    ),
                  ),
                  Icon(
                    _showColorPicker
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppColors.accent,
                    size: 16,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          tipLine,
          style: AppTypography.bodySm.copyWith(
            color: AppColors.textDim,
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: _showColorPicker
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(_urineColors.length, (i) {
                      final isSelected = selectedUrine == i;
                      return GestureDetector(
                        onTap: () {
                          ref
                              .read(urineColorProvider.notifier)
                              .select(i);
                          // Auto-collapse after selection.
                          setState(() => _showColorPicker = false);
                        },
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: _urineColors[i].color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.accent
                                  : AppColors.line2,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
