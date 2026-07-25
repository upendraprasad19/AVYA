import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_dashed_border.dart';

/// The "PHASE _n_ · HOLDING" chip group — the free-tier hold weeks rendered to
/// the RIGHT of the current phase's W1-W4 group in the Train week strip.
///
/// Built to the founder-locked mockup `docs/design/holdweek_train_mockup.html`.
/// Lives in its own file rather than inside `week_selector.dart` (already 1040
/// lines) — the hold strip is a self-contained visual unit with its own tap
/// semantics.
///
/// **Why these chips do not drive `selectedWeekProvider`** — hold rows are
/// stamped `week = 4 + ordinal`, but `CurrentPlanData.weeks` only ever holds 4
/// entries for phase 1, so selecting "week 5" would send the Train screen down
/// the `plan.getWeek(5) == []` path and render "Week 5 hasn't started yet" over
/// a week the user is actively training. Holds are addressed by ORDINAL and
/// DATE instead: the current hold's content is the Train screen's today card,
/// and any hold chip opens a read-only [HoldWeekSheet] breakdown.
class HoldChipGroup extends StatelessWidget {
  const HoldChipGroup({
    super.key,
    required this.phaseLabel,
    required this.holds,
    required this.todayHoldOrdinal,
    required this.onTapHold,
  });

  /// e.g. `'PHASE I'` — passed in so the roman-numeral mapping stays owned by
  /// `week_selector.dart` (one converter, no drift).
  final String phaseLabel;

  /// Materialized hold weeks, ordinal-ascending.
  final List<HoldWeekInfo> holds;

  /// The hold covering today, or null when today is outside every hold week.
  final int? todayHoldOrdinal;

  final ValueChanged<HoldWeekInfo> onTapHold;

  @override
  Widget build(BuildContext context) {
    if (holds.isEmpty) return const SizedBox.shrink();

    // Preview the NEXT hold only when it would be a deload — that chip carries
    // real information ("hold again and you get a recovery week"), which a bare
    // "H5" placeholder would not. Mirrors the mockup's dashed "H4 · DELOAD".
    final nextOrdinal = holds.last.ordinal + 1;
    final showDeloadPreview =
        WorkoutScheduleReadService.isDeloadHold(nextOrdinal);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            '$phaseLabel · HOLDING',
            style: AppTypography.monoXs.copyWith(
              fontSize: 9,
              letterSpacing: 1.2,
              color: AppColors.accent,
            ),
          ),
        ),
        Row(
          children: [
            for (final hold in holds)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _HoldChip(
                  key: ValueKey('hold-${hold.ordinal}'),
                  hold: hold,
                  isCurrent: hold.ordinal == todayHoldOrdinal,
                  onTap: () => onTapHold(hold),
                ),
              ),
            if (showDeloadPreview)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _DeloadPreviewChip(
                  key: ValueKey('hold-preview-$nextOrdinal'),
                  ordinal: nextOrdinal,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ── Single hold chip ─────────────────────────────────────────────────────────

class _HoldChip extends StatelessWidget {
  const _HoldChip({
    super.key,
    required this.hold,
    required this.isCurrent,
    required this.onTap,
  });

  final HoldWeekInfo hold;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = isCurrent ? AppColors.bgDeep : AppColors.textDim;
    final bg = isCurrent ? AppColors.accent : AppColors.card;

    // Date range only on the selected chip — it is the one thing distinguishing
    // H1 from H5 at a glance (founder decision, free-tier-hold-findings.md §3).
    final sub = isCurrent ? formatHoldWeekRange(hold.weekStart) : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: sub != null ? 58.0 : 48.0,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          border: isCurrent
              ? Border.all(color: AppColors.accent, width: 1.5)
              : Border.all(color: AppColors.line2),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'H${hold.ordinal}',
                  style: AppTypography.monoXs.copyWith(
                    fontSize: 10,
                    color: fg,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    height: 1.1,
                  ),
                ),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    sub.toUpperCase(),
                    style: AppTypography.monoXs.copyWith(
                      color: fg.withValues(alpha: 0.85),
                      fontSize: 7,
                      letterSpacing: 1,
                      height: 1.1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
            // Same ✓ affordance and rule as the W chips (≥1 completed day).
            if (hold.isCompleted)
              Positioned(
                top: 4,
                right: 4,
                child: Icon(
                  Icons.check_circle,
                  size: 10,
                  color: AppColors.ok,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Upcoming-deload preview chip ─────────────────────────────────────────────

/// Non-interactive dashed chip announcing that the NEXT hold will be a deload.
/// Nothing is materialized for it yet, so it is deliberately not tappable.
class _DeloadPreviewChip extends StatelessWidget {
  const _DeloadPreviewChip({super.key, required this.ordinal});

  final int ordinal;

  @override
  Widget build(BuildContext context) {
    return WardDashedBorder(
      color: AppColors.accent,
      radius: AppRadius.sharp,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'H$ordinal',
              style: AppTypography.monoXs.copyWith(
                fontSize: 10,
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'DELOAD',
              style: AppTypography.monoXs.copyWith(
                fontSize: 6.5,
                color: AppColors.accent.withValues(alpha: 0.85),
                letterSpacing: 0.5,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Read-only hold-week breakdown sheet ──────────────────────────────────────

/// The 7-day breakdown for one hold week, mirroring the past-phase week sheet's
/// read-only intent. Opened by tapping any hold chip.
class HoldWeekSheet extends ConsumerWidget {
  const HoldWeekSheet({super.key, required this.hold});

  final HoldWeekInfo hold;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readService = ref.read(workoutScheduleReadServiceProvider);
    final days = [
      for (var offset = 0; offset < 7; offset++)
        hold.weekStart.add(Duration(days: offset)),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'HOLD ${hold.ordinal}',
                  style: AppTypography.monoXs.copyWith(
                    fontSize: 11,
                    letterSpacing: 1.4,
                    color: AppColors.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (hold.isDeload) ...[
                  const SizedBox(width: 8),
                  Text(
                    '· DELOAD',
                    style: AppTypography.monoXs.copyWith(
                      fontSize: 11,
                      letterSpacing: 1.4,
                      color: AppColors.accent.withValues(alpha: 0.8),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  formatHoldWeekRange(hold.weekStart).toUpperCase(),
                  style: AppTypography.monoXs.copyWith(
                    fontSize: 10,
                    letterSpacing: 1,
                    color: AppColors.textMute,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final day in days) _HoldDayRow(
              date: day,
              row: readService.getScheduleForDate(day),
            ),
          ],
        ),
      ),
    );
  }
}

class _HoldDayRow extends StatelessWidget {
  const _HoldDayRow({required this.date, required this.row});

  final DateTime date;
  final Map<String, dynamic>? row;

  static const _weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  @override
  Widget build(BuildContext context) {
    final type = (row?['type'] ?? '').toString();
    final isRest = row == null || type == 'rest' || type == 'off';
    final isDone = row?['status'] == 'completed';
    final name = isRest
        ? 'Rest'
        : (row?['workout_name'] as String?)?.trim().isNotEmpty == true
            ? (row!['workout_name'] as String)
            : 'Workout';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Text(
              _weekdays[date.weekday - 1],
              style: AppTypography.monoXs.copyWith(
                fontSize: 9,
                letterSpacing: 1,
                color: AppColors.textMute,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.body.copyWith(
                fontSize: 13,
                fontWeight: isRest ? FontWeight.w500 : FontWeight.w700,
                color: isRest ? AppColors.textMute : AppColors.textPrimary,
              ),
            ),
          ),
          if (isDone)
            Icon(Icons.check_circle, size: 14, color: AppColors.ok)
          else if (!isRest)
            Text(
              'PLANNED',
              style: AppTypography.monoXs.copyWith(
                fontSize: 8,
                letterSpacing: 1,
                color: AppColors.textGhost,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Shared date formatting ───────────────────────────────────────────────────

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `'Jul 21–27'` / `'Jul 28–Aug 3'` — matches the W-chip date-range format so a
/// selected H chip reads identically to a selected W chip.
String formatHoldWeekRange(DateTime weekStart) {
  final weekEnd = weekStart.add(const Duration(days: 6));
  if (weekStart.month == weekEnd.month) {
    return '${_months[weekStart.month - 1]} ${weekStart.day}–${weekEnd.day}';
  }
  return '${_months[weekStart.month - 1]} ${weekStart.day}–'
      '${_months[weekEnd.month - 1]} ${weekEnd.day}';
}
