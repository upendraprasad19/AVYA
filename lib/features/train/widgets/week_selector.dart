import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';

/// Horizontal scrollable week tab bar — extended to 12 weeks (3 phases).
///
/// Phases II and III (weeks 5-12) are locked behind a PRO badge for
/// free-tier users. Phase headers sit above each group of 4 chips.
///
/// The widget accepts the same public signature as before
/// (`totalWeeks`, `selectedWeek`, `onSelect`) so all existing call-sites
/// compile without change. When `totalWeeks < 12` the widget still renders
/// 12 chips so the full roadmap is always visible; weeks beyond
/// `totalWeeks` are treated as "future / not yet generated".
class WeekSelector extends ConsumerStatefulWidget {
  final int totalWeeks;
  final int selectedWeek; // 1-indexed
  final ValueChanged<int> onSelect;

  const WeekSelector({
    super.key,
    required this.totalWeeks,
    required this.selectedWeek,
    required this.onSelect,
  });

  @override
  ConsumerState<WeekSelector> createState() => _WeekSelectorState();
}

class _WeekSelectorState extends ConsumerState<WeekSelector> {
  @override
  Widget build(BuildContext context) {
    // APK Test #12 / Task C-2 — watch subscriptionInfoProvider so the
    // PHASE II / III lock chips re-render the moment payment confirms.
    final isPro = ref.watch(subscriptionInfoProvider).isPro;
    final planStart =
        ref.read(workoutScheduleReadServiceProvider).getPlanStartDate();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PhaseGroup(
            label: 'PHASE I',
            isPaywalled: false,
            weekStart: 1,
            weekEnd: 4,
            selectedWeek: widget.selectedWeek,
            planStart: planStart,
            onTap: widget.onSelect,
          ),
          const SizedBox(width: 16),
          _PhaseGroup(
            label: 'PHASE II',
            isPaywalled: !isPro,
            weekStart: 5,
            weekEnd: 8,
            selectedWeek: widget.selectedWeek,
            planStart: planStart,
            onTap: widget.onSelect,
          ),
          const SizedBox(width: 16),
          _PhaseGroup(
            label: 'PHASE III',
            isPaywalled: !isPro,
            weekStart: 9,
            weekEnd: 12,
            selectedWeek: widget.selectedWeek,
            planStart: planStart,
            onTap: widget.onSelect,
          ),
        ],
      ),
    );
  }
}

// ── Phase group (label + 4 chips) ───────────────────────────────────────────

class _PhaseGroup extends StatelessWidget {
  const _PhaseGroup({
    required this.label,
    required this.isPaywalled,
    required this.weekStart,
    required this.weekEnd,
    required this.selectedWeek,
    required this.planStart,
    required this.onTap,
  });

  final String label;
  final bool isPaywalled;
  final int weekStart;
  final int weekEnd;
  final int selectedWeek;
  final DateTime? planStart;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Phase header row: label + optional PRO badge
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Row(
            children: [
              Text(
                label,
                style: AppTypography.monoXs.copyWith(
                  fontSize: 9,
                  letterSpacing: 1.2,
                  color: isPaywalled ? AppColors.textGhost : AppColors.accent,
                ),
              ),
              if (isPaywalled) ...[
                const SizedBox(width: 4),
                Text(
                  '(PRO)',
                  style: AppTypography.monoXs.copyWith(
                    fontSize: 9,
                    letterSpacing: 1.0,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ],
          ),
        ),

        // Week chips
        Row(
          children: [
            for (var w = weekStart; w <= weekEnd; w++)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _WeekChip(
                  key: ValueKey('week-$w'),
                  week: w,
                  isSelected: w == selectedWeek,
                  isLocked: isPaywalled,
                  planStart: planStart,
                  onTap: () => onTap(w),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ── Single week chip ─────────────────────────────────────────────────────────

class _WeekChip extends StatelessWidget {
  const _WeekChip({
    super.key,
    required this.week,
    required this.isSelected,
    required this.isLocked,
    required this.planStart,
    required this.onTap,
  });

  final int week;
  final bool isSelected;
  final bool isLocked;
  final DateTime? planStart;
  final VoidCallback onTap;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String? _dateRange() {
    if (planStart == null) return null;
    final weekStart = planStart!.add(Duration(days: (week - 1) * 7));
    final weekEnd = weekStart.add(const Duration(days: 6));
    if (weekStart.month == weekEnd.month) {
      return '${_months[weekStart.month - 1]} ${weekStart.day}–${weekEnd.day}';
    }
    return '${_months[weekStart.month - 1]} ${weekStart.day}–'
        '${_months[weekEnd.month - 1]} ${weekEnd.day}';
  }

  @override
  Widget build(BuildContext context) {
    final fg = isLocked
        ? AppColors.textGhost
        : (isSelected ? AppColors.bgDeep : AppColors.textDim);
    final bg = isLocked
        ? AppColors.input
        : (isSelected ? AppColors.accent : AppColors.card);

    final sub = isSelected ? _dateRange() : null;
    final chipHeight = sub != null ? 58.0 : 48.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: chipHeight,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          border: isSelected
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
                  'W$week',
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
            if (isLocked)
              Positioned(
                top: 4,
                right: 4,
                child: Icon(
                  Icons.lock,
                  size: 10,
                  color: AppColors.accent,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

