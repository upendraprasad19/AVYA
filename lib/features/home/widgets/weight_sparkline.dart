import 'dart:math';
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Weight entry with date for axis labels.
class WeightEntry {
  final String date; // YYYY-MM-DD
  final double weight;
  const WeightEntry({required this.date, required this.weight});
}

/// Weight trend card with duration selector, Y-axis labels, date axis,
/// and a Wardroom [WardSpark] sparkline.
class WeightSparkline extends StatefulWidget {
  final List<WeightEntry> entries;

  const WeightSparkline({super.key, required this.entries});

  @override
  State<WeightSparkline> createState() => _WeightSparklineState();
}

class _WeightSparklineState extends State<WeightSparkline> {
  // Handoff (`daily.jsx`): chip set is 7D / 30D / 90D only.
  // Legacy 1y / All chips removed to match the spec; historical data
  // is still reachable via the Weekly Report and the weight log screen.
  String _selectedRange = '7d';
  static const _ranges = ['7d', '30d', '90d'];

  List<WeightEntry> get _filteredEntries {
    if (widget.entries.isEmpty) return [];
    final now = DateTime.now();
    final cutoff = switch (_selectedRange) {
      '7d' => now.subtract(const Duration(days: 7)),
      '30d' => now.subtract(const Duration(days: 30)),
      '90d' => now.subtract(const Duration(days: 90)),
      _ => now.subtract(const Duration(days: 7)),
    };
    // audit-2026-05-16 reader-side — entry `date` field is IST-formatted
    // (HealthWriteService writes `istDateStr(date)`). Cutoff must also
    // be in IST or we get an off-by-one at the IST midnight boundary
    // (UTC-local cutoff could exclude a weigh-in that's still inside
    // the window in IST). Mirrors `WorkoutWriteService.istDateStr` —
    // not imported here to avoid widget→service back-dep; inlined.
    final cutoffIst = cutoff.toUtc().add(const Duration(hours: 5, minutes: 30));
    final cutoffStr =
        '${cutoffIst.year}-${cutoffIst.month.toString().padLeft(2, '0')}-${cutoffIst.day.toString().padLeft(2, '0')}';
    final filtered =
        widget.entries.where((e) => e.date.compareTo(cutoffStr) >= 0).toList();
    return filtered.isEmpty ? widget.entries : filtered;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) {
      return WardCard(
        variant: WardCardVariant.standard,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.monitor_weight_outlined,
                size: 16, color: AppColors.textDim),
            const SizedBox(width: 8),
            Text(
              'Log your weight to see trends here',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.textDim,
              ),
            ),
          ],
        ),
      );
    }

    final entries = _filteredEntries;
    final weights = entries.map((e) => e.weight).toList();
    final latest = weights.last;
    final change =
        weights.length >= 2 ? weights.last - weights[weights.length - 2] : 0.0;
    final changeStr =
        change >= 0 ? '+${change.toStringAsFixed(1)}' : change.toStringAsFixed(1);
    // Semantic: weight loss = good (ok). Weight gain = warn. No change = neutral.
    final WardChipTone deltaTone = change < 0
        ? WardChipTone.ok
        : (change > 0 ? WardChipTone.warn : WardChipTone.neutral);

    final minW = weights.reduce(min);
    final maxW = weights.reduce(max);
    // APK Test #12 / Task W-1 — dynamic decimal precision on Y-axis ticks.
    // Pre-fix: tick formatter used `.toStringAsFixed(0)` unconditionally, so
    // a 77.0 / 77.5 / 78.0 series rendered ticks "78 / 78 / 77" — two ticks
    // collapsed to identical labels. Range-based decimals fix that:
    //   range < 0.5  → 2 decimals (77.00 / 77.25 / 77.50)
    //   range < 2.0  → 1 decimal  (78.0 / 77.5 / 77.0)
    //   range >= 2.0 → integer    (85 / 80 / 75)
    final yRange = (maxW - minW).abs();
    final yTickDecimals = yRange < 0.5 ? 2 : (yRange < 2.0 ? 1 : 0);

    return WardCard(
      variant: WardCardVariant.standard,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              const Icon(Icons.monitor_weight_outlined,
                  size: 12, color: AppColors.textDim),
              const SizedBox(width: 6),
              Text(
                'WEIGHT TREND',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              Text(
                latest.toStringAsFixed(1),
                style: AppTypography.h3.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                'KG',
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(width: 8),
              WardChip(
                label: '$changeStr KG',
                tone: deltaTone,
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Duration selector — sharp 2-px chip tiles
          Row(
            children: _ranges.map((range) {
              final isSelected = range == _selectedRange;
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedRange = range),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.accentSoft
                          : Colors.transparent,
                      border: Border.all(
                        color: isSelected
                            ? AppColors.accent.withValues(alpha: 0.33)
                            : AppColors.line2,
                      ),
                    ),
                    child: Text(
                      range.toUpperCase(),
                      style: AppTypography.monoXs.copyWith(
                        color: isSelected
                            ? AppColors.accent
                            : AppColors.textMute,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),

          // Chart with Y-axis labels
          SizedBox(
            height: 70,
            child: Row(
              children: [
                // Y-axis labels
                Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      maxW.toStringAsFixed(yTickDecimals),
                      style: AppTypography.monoXs
                          .copyWith(color: AppColors.textMute),
                    ),
                    if (maxW != minW)
                      Text(
                        ((maxW + minW) / 2).toStringAsFixed(yTickDecimals),
                        style: AppTypography.monoXs
                            .copyWith(color: AppColors.textMute),
                      ),
                    Text(
                      minW.toStringAsFixed(yTickDecimals),
                      style: AppTypography.monoXs
                          .copyWith(color: AppColors.textMute),
                    ),
                  ],
                ),
                const SizedBox(width: 6),
                // Chart area — WardSpark with fill
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      if (weights.length < 2) {
                        return SizedBox(
                          width: c.maxWidth,
                          height: 70,
                          child: Center(
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        );
                      }
                      return WardSpark(
                        data: weights,
                        width: c.maxWidth,
                        height: 70,
                        strokeWidth: 1.5,
                        fillAlpha: 0.2,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // X-axis date labels
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 26), // align with chart area
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDateShort(entries.first.date),
                  style: AppTypography.monoXs
                      .copyWith(color: AppColors.textMute),
                ),
                if (entries.length > 2)
                  Text(
                    _formatDateShort(entries[entries.length ~/ 2].date),
                    style: AppTypography.monoXs
                        .copyWith(color: AppColors.textMute),
                  ),
                Text(
                  _formatDateShort(entries.last.date),
                  style: AppTypography.monoXs
                      .copyWith(color: AppColors.textMute),
                ),
              ],
            ),
          ),

          // Min/Max summary
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'LOW ${minW.toStringAsFixed(1)}',
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.ok,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'HIGH ${maxW.toStringAsFixed(1)}',
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.warn,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${entries.length} ENTRIES',
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDateShort(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length != 3) return dateStr;
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC'
    ];
    final month = int.tryParse(parts[1]) ?? 1;
    final day = int.tryParse(parts[2]) ?? 1;
    return '${months[month - 1]} $day';
  }
}
