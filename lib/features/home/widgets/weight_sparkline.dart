import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';

/// Weight entry with date for axis labels.
class WeightEntry {
  final String date; // YYYY-MM-DD
  final double weight;
  const WeightEntry({required this.date, required this.weight});
}

/// Weight trend card with duration selector, Y-axis labels, and date axis.
class WeightSparkline extends StatefulWidget {
  final List<WeightEntry> entries;

  const WeightSparkline({super.key, required this.entries});

  @override
  State<WeightSparkline> createState() => _WeightSparklineState();
}

class _WeightSparklineState extends State<WeightSparkline> {
  String _selectedRange = '7d'; // 7d, 30d, 3m, 1y, All
  static const _ranges = ['7d', '30d', '3m', '1y', 'All'];

  List<WeightEntry> get _filteredEntries {
    if (widget.entries.isEmpty) return [];
    final now = DateTime.now();
    final cutoff = switch (_selectedRange) {
      '7d' => now.subtract(const Duration(days: 7)),
      '30d' => now.subtract(const Duration(days: 30)),
      '3m' => now.subtract(const Duration(days: 90)),
      '1y' => now.subtract(const Duration(days: 365)),
      _ => DateTime(2000), // All
    };
    final cutoffStr = '${cutoff.year}-${cutoff.month.toString().padLeft(2, '0')}-${cutoff.day.toString().padLeft(2, '0')}';
    final filtered = widget.entries.where((e) => e.date.compareTo(cutoffStr) >= 0).toList();
    return filtered.isEmpty ? widget.entries : filtered;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.cardM),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.monitor_weight_outlined,
                size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Text(
              'Log your weight to see trends here',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    final entries = _filteredEntries;
    final weights = entries.map((e) => e.weight).toList();
    final latest = weights.last;
    final change = weights.length >= 2 ? weights.last - weights[weights.length - 2] : 0.0;
    final changeStr = change >= 0 ? '+${change.toStringAsFixed(1)}' : change.toStringAsFixed(1);
    final changeColor = change < 0 ? AppColors.green : (change > 0 ? AppColors.orange : AppColors.textSecondary);

    final minW = weights.reduce(min);
    final maxW = weights.reduce(max);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              const Icon(Icons.monitor_weight_outlined,
                  size: 12, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                'WEIGHT TREND',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                '${latest.toStringAsFixed(1)} kg',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$changeStr kg',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: changeColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Duration selector
          Row(
            children: _ranges.map((range) {
              final isSelected = range == _selectedRange;
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedRange = range),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.accent.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.accent.withValues(alpha: 0.3)
                            : AppColors.border,
                      ),
                    ),
                    child: Text(
                      range,
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? AppColors.accent : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),

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
                      maxW.toStringAsFixed(0),
                      style: GoogleFonts.getFont('DM Sans',
                          fontSize: 8, color: AppColors.textSecondary),
                    ),
                    if (maxW != minW)
                      Text(
                        ((maxW + minW) / 2).toStringAsFixed(0),
                        style: GoogleFonts.getFont('DM Sans',
                            fontSize: 8, color: AppColors.textSecondary),
                      ),
                    Text(
                      minW.toStringAsFixed(0),
                      style: GoogleFonts.getFont('DM Sans',
                          fontSize: 8, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(width: 6),
                // Chart area
                Expanded(
                  child: CustomPaint(
                    size: const Size(double.infinity, 70),
                    painter: _SparklinePainter(values: weights),
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
                  style: GoogleFonts.getFont('DM Sans',
                      fontSize: 8, color: AppColors.textSecondary),
                ),
                if (entries.length > 2)
                  Text(
                    _formatDateShort(entries[entries.length ~/ 2].date),
                    style: GoogleFonts.getFont('DM Sans',
                        fontSize: 8, color: AppColors.textSecondary),
                  ),
                Text(
                  _formatDateShort(entries.last.date),
                  style: GoogleFonts.getFont('DM Sans',
                      fontSize: 8, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),

          // Min/Max summary
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Low: ${minW.toStringAsFixed(1)} kg',
                style: GoogleFonts.getFont('DM Sans',
                    fontSize: 9, fontWeight: FontWeight.w600,
                    color: AppColors.green),
              ),
              const SizedBox(width: 12),
              Text(
                'High: ${maxW.toStringAsFixed(1)} kg',
                style: GoogleFonts.getFont('DM Sans',
                    fontSize: 9, fontWeight: FontWeight.w600,
                    color: AppColors.orange),
              ),
              const SizedBox(width: 12),
              Text(
                '${entries.length} entries',
                style: GoogleFonts.getFont('DM Sans',
                    fontSize: 9, color: AppColors.textSecondary),
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
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final month = int.tryParse(parts[1]) ?? 1;
    final day = int.tryParse(parts[2]) ?? 1;
    return '${months[month - 1]} $day';
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;

  _SparklinePainter({required this.values});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final minVal = values.reduce(min) - 0.5;
    final maxVal = values.reduce(max) + 0.5;
    final range = maxVal - minVal;
    if (range == 0) return;

    final stepX = size.width / (values.length - 1);

    final path = Path();
    final points = <Offset>[];
    for (int i = 0; i < values.length; i++) {
      final x = i * stepX;
      final y = size.height - ((values[i] - minVal) / range) * size.height;
      points.add(Offset(x, y));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Gradient fill
    final fillPath = Path.from(path);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0x3300D4FF),
          Color(0x0000D4FF),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // Line
    final linePaint = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    // Current point dot
    if (points.isNotEmpty) {
      final lastPoint = points.last;
      canvas.drawCircle(
        lastPoint,
        3.5,
        Paint()..color = AppColors.accent,
      );
      canvas.drawCircle(
        lastPoint,
        2,
        Paint()..color = AppColors.bg,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.values != values;
}
