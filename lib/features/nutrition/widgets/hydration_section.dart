import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import '../providers/nutrition_provider.dart';
import 'hydration_ring_painter.dart';

/// Urine color data model.
class UrineColorData {
  final Color color;
  final String status;
  final String tip;
  final Color statusColor;

  const UrineColorData({
    required this.color,
    required this.status,
    required this.tip,
    required this.statusColor,
  });
}

const _urineColors = [
  UrineColorData(
    color: Color(0xFFFFF9C4),
    status: 'Excellent',
    tip: 'Pale straw \u2014 optimal hydration',
    statusColor: Color(0xFF4ade80),
  ),
  UrineColorData(
    color: Color(0xFFFFF176),
    status: 'Good',
    tip: 'Clear yellow \u2014 well hydrated',
    statusColor: Color(0xFF4ade80),
  ),
  UrineColorData(
    color: Color(0xFFFFD600),
    status: 'Adequate',
    tip: 'Yellow \u2014 drink more soon',
    statusColor: Color(0xFFF59E0B),
  ),
  UrineColorData(
    color: Color(0xFFFFB300),
    status: 'Low',
    tip: 'Dark yellow \u2014 drink now',
    statusColor: Color(0xFFF59E0B),
  ),
  UrineColorData(
    color: Color(0xFFE65100),
    status: 'Very low',
    tip: 'Amber \u2014 significantly dehydrated',
    statusColor: Color(0xFFef4444),
  ),
  UrineColorData(
    color: Color(0xFFBF360C),
    status: 'Critical',
    tip: 'Brown \u2014 consult a doctor',
    statusColor: Color(0xFFef4444),
  ),
  UrineColorData(
    color: Color(0xFF4E342E),
    status: 'Doctor!',
    tip: 'Dark brown \u2014 medical attention',
    statusColor: Color(0xFFef4444),
  ),
];

/// Full hydration section: water ring, unit toggle, quick add buttons,
/// urine color tracker, and save button.
class HydrationSection extends ConsumerWidget {
  const HydrationSection({super.key});

  static const int _waterGoalMl = 3000;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waterMl = ref.watch(waterIntakeProvider);
    final waterUnit = ref.watch(waterUnitProvider);
    final selectedUrine = ref.watch(urineColorProvider);
    final saved = ref.watch(hydrationSaveProvider);

    final waterProgress = (waterMl / _waterGoalMl).clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top: Ring + Info ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Water ring
                SizedBox(
                  width: 80,
                  height: 80,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(80, 80),
                        painter: HydrationRingPainter(
                          progress: waterProgress,
                          trackColor: AppColors.input,
                          fillColor: AppColors.blue,
                          strokeWidth: 8,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            waterUnit == 'ml'
                                ? '${waterMl}ml'
                                : '${(waterMl / 250).toStringAsFixed(1)}\uD83E\uDD5B',
                            style: GoogleFonts.getFont(
                              'DM Sans',
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: AppColors.blue,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            waterUnit == 'ml' ? 'of 3000' : 'glasses',
                            style: GoogleFonts.getFont(
                              'DM Sans',
                              fontSize: 8,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                // Info column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '\uD83D\uDCA7 Daily Water',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Unit toggle
                      _UnitToggle(
                        selected: waterUnit,
                        onChanged: (unit) =>
                            ref.read(waterUnitProvider.notifier).toggle(unit),
                      ),
                      const SizedBox(height: 8),
                      // Quick add buttons
                      Row(
                        children: [
                          _QuickAddButton(
                            label: waterUnit == 'ml' ? '+250ml' : '\u00BD\uD83E\uDD5B',
                            onTap: () => ref
                                .read(waterIntakeProvider.notifier)
                                .addWater(250),
                          ),
                          const SizedBox(width: 5),
                          _QuickAddButton(
                            label: waterUnit == 'ml' ? '+500ml' : '1\uD83E\uDD5B',
                            onTap: () => ref
                                .read(waterIntakeProvider.notifier)
                                .addWater(500),
                          ),
                          const SizedBox(width: 5),
                          _QuickAddButton(
                            label: waterUnit == 'ml' ? '+750ml' : '1.5\uD83E\uDD5B',
                            onTap: () => ref
                                .read(waterIntakeProvider.notifier)
                                .addWater(750),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Divider ──
            Container(height: 1, color: AppColors.input),
            const SizedBox(height: 10),

            // ── Urine Color Tracker ──
            Text(
              'URINE COLOUR \u2014 TAP TO LOG',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),

            // Color swatches row
            Row(
              children: List.generate(_urineColors.length, (index) {
                final isSelected = index == selectedUrine;
                return Expanded(
                  child: GestureDetector(
                    onTap: () =>
                        ref.read(urineColorProvider.notifier).select(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: EdgeInsets.only(
                        left: index == 0 ? 0 : 1.5,
                        right: index == _urineColors.length - 1 ? 0 : 1.5,
                      ),
                      height: 13,
                      decoration: BoxDecoration(
                        color: _urineColors[index].color,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      transform: isSelected
                          // ignore: deprecated_member_use
                          ? (Matrix4.identity()..scale(1.15, 1.15, 1.0))
                          : Matrix4.identity(),
                      transformAlignment: Alignment.center,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 5),

            // Status text
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: selectedUrine >= 0 && selectedUrine < _urineColors.length
                  ? Text(
                      '${_urineColors[selectedUrine].status} \u00B7 ${_urineColors[selectedUrine].tip}',
                      key: ValueKey(selectedUrine),
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _urineColors[selectedUrine].statusColor,
                      ),
                    )
                  : const SizedBox(height: 14),
            ),
            const SizedBox(height: 8),

            // Save button
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () =>
                    ref.read(hydrationSaveProvider.notifier).save(),
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.blue.withValues(alpha: 0.08),
                  foregroundColor: AppColors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    side: BorderSide(
                      color: AppColors.blue.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                child: Text(
                  'Save Hydration Log',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.blue,
                  ),
                ),
              ),
            ),

            // Saved message
            AnimatedOpacity(
              opacity: saved ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Center(
                  child: Text(
                    '\u2713 Saved to your daily log',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.green,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Unit Toggle ──────────────────────────────────────────────────

class _UnitToggle extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _UnitToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        children: [
          _tab('ml', selected == 'ml'),
          _tab('\uD83E\uDD5B glasses', selected == 'glasses',
              value: 'glasses'),
        ],
      ),
    );
  }

  Widget _tab(String label, bool isOn, {String? value}) {
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value ?? label),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: isOn ? AppColors.card : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isOn ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Quick Add Button ─────────────────────────────────────────────

class _QuickAddButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickAddButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.input,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: AppColors.border),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
