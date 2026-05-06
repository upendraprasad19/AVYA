import 'package:flutter/material.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';

/// Per-set bracketed chip Wrap — the single source of truth for "what
/// was logged for this exercise" rendering.
///
/// APK Test #12 / Theme E (extracted from
/// `workout_receipt_card._SetChip` 2026-05-06). Used by:
///   - WorkoutReceiptCard (the shareable artifact)
///   - Train screen expanded view (per-day exercise breakdown)
///   - any future surface that shows a logged exercise's per-set detail
///
/// Per-set logging-type rules (single source of truth):
///   weight_reps         : "20 kg × 10 reps"
///   bodyweight_reps     : "× 10 reps"
///   weighted_bodyweight : "+10 kg × 8 reps"
///   timed               : "60 secs"
///   cardio              : "15s · 2 km"
///   distance            : "2 km · 10 kg"
///
/// Single-chip fallback: when [perSetBreakdown] is empty (legacy logs
/// or train-screen aggregate), the [fallbackLabel] is rendered as a
/// single chip — preserves visual continuity even when per-set data is
/// missing.
class WardSetChip {
  final double? weightKg;
  final int? reps;
  final int? durationSeconds;
  final double? distanceKm;

  const WardSetChip({
    this.weightKg,
    this.reps,
    this.durationSeconds,
    this.distanceKm,
  });
}

class WardSetChips extends StatelessWidget {
  const WardSetChips({
    super.key,
    required this.loggingType,
    required this.perSetBreakdown,
    this.fallbackLabel,
  });

  final String loggingType;
  final List<WardSetChip> perSetBreakdown;

  /// Used as the chip text when [perSetBreakdown] is empty (legacy
  /// pre-Test-#6 exlogs, Train aggregate cumulative summary, etc.).
  final String? fallbackLabel;

  @override
  Widget build(BuildContext context) {
    final chips = perSetBreakdown.isNotEmpty
        ? perSetBreakdown.map(_perSetLabel).toList()
        : (fallbackLabel != null ? [fallbackLabel!] : const <String>[]);

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: chips.map((label) => _Chip(label: label)).toList(),
    );
  }

  String _perSetLabel(WardSetChip s) {
    final w = s.weightKg;
    final r = s.reps;
    final d = s.durationSeconds;
    final dist = s.distanceKm;

    String fmtKg(double v) =>
        '${v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1)} kg';

    switch (loggingType) {
      case 'weight_reps':
        final wTxt = (w != null && w > 0) ? fmtKg(w) : '0 kg';
        return '$wTxt × ${r ?? 0} reps';
      case 'bodyweight_reps':
        return '× ${r ?? 0} reps';
      case 'weighted_bodyweight':
        final wTxt = (w != null && w > 0) ? '+${fmtKg(w)}' : '+0 kg';
        return '$wTxt × ${r ?? 0} reps';
      case 'timed':
        return '${d ?? 0} secs';
      case 'cardio':
        final parts = <String>[];
        if (d != null && d > 0) parts.add('${d}s');
        if (dist != null && dist > 0) parts.add('${dist.toStringAsFixed(1)} km');
        return parts.isNotEmpty ? parts.join(' · ') : '—';
      case 'distance':
        final parts = <String>[];
        if (dist != null && dist > 0) parts.add('${dist.toStringAsFixed(1)} km');
        if (w != null && w > 0) parts.add(fmtKg(w));
        return parts.isNotEmpty ? parts.join(' · ') : '—';
      default:
        return r != null && r > 0 ? '$r reps' : '—';
    }
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.line2, width: 1),
        color: Colors.transparent,
      ),
      child: Text(
        label,
        style: AppTypography.bodyS.copyWith(
          color: AppColors.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
