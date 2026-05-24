import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
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
/// Theme K (2026-05-23 / diagnose b9d2a8) — extends the strip LEFT
/// with one _PhaseGroup per COMPLETED PAST phase. Past chips:
///   - visually distinct (textDim border vs accent),
///   - carry a `✓` glyph on the chip top-right when ≥1 day in that
///     week has status='completed',
///   - tappable → opens [_PastWeekSheet] showing the 7-day breakdown
///     from `schedule_*` Hive entries for that historical week.
///
/// Past-phase detection: walks `workoutBox.toMap()` for keys starting
/// with `schedule_`, groups entries by date range (4 calendar weeks
/// each), filters to date ranges strictly BEFORE the current plan's
/// `plan_start_date`. The current phase (and locked previews of
/// future phases II/III) keep the pre-fix behaviour.
///
/// The widget accepts the same public signature as before
/// (`totalWeeks`, `selectedWeek`, `onSelect`) so all existing call-sites
/// compile without change.
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

    // Theme K — derive past-phase groups by walking schedule_* Hive
    // entries. Cheap (≤200 keys typical); runs once per build.
    final pastPhases = _loadPastPhases(planStart);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Past phases LEFT of the current phase, oldest first.
          for (final past in pastPhases) ...[
            _PastPhaseGroup(
              past: past,
              onTap: (week) => _showPastWeekSheet(context, past, week),
            ),
            const SizedBox(width: 16),
          ],
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

  void _showPastWeekSheet(
      BuildContext context, _PastPhase past, int weekInPhase) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PastWeekSheet(past: past, weekInPhase: weekInPhase),
    );
  }
}

/// Walks workoutBox for `schedule_*` entries, groups them into past
/// phases of 4 calendar weeks each (each phase = 28 days from its
/// earliest date). Skips entries falling within the current plan's
/// active window (>= planStart).
List<_PastPhase> _loadPastPhases(DateTime? planStart) {
  final box = HiveService.instance.workoutBox;
  final entries = <_ScheduleEntry>[];
  for (final raw in box.toMap().entries) {
    final keyStr = raw.key.toString();
    if (!keyStr.startsWith('schedule_')) continue;
    final v = raw.value;
    if (v is! Map) continue;
    final map = Map<String, dynamic>.from(v);
    final dateStr = map['date'] as String?;
    if (dateStr == null) continue;
    final date = DateTime.tryParse(dateStr);
    if (date == null) continue;
    // Skip current plan's active window.
    if (planStart != null && !date.isBefore(planStart)) continue;
    entries.add(_ScheduleEntry(
      key: keyStr,
      date: date,
      week: (map['week'] as int?) ?? 0,
      type: (map['type'] as String?) ?? 'rest',
      workoutName: (map['workout_name'] as String?) ?? '',
      status: (map['status'] as String?) ?? 'planned',
      completedAt: map['completed_at'] as String?,
    ));
  }
  if (entries.isEmpty) return const [];
  entries.sort((a, b) => a.date.compareTo(b.date));

  // Bucket into 28-day phases starting from the earliest date.
  final earliest = entries.first.date;
  final byPhase = <int, List<_ScheduleEntry>>{};
  for (final e in entries) {
    final daysSinceEarliest = e.date.difference(earliest).inDays;
    final phaseIdx = daysSinceEarliest ~/ 28; // 0-indexed
    (byPhase[phaseIdx] ??= []).add(e);
  }

  // Sort phase indices ascending so PHASE I renders left of PHASE II,
  // then materialise to _PastPhase records. Cascade `..sort()` returns
  // the receiver (List<int>), so we can't chain `.map().toList()` on the
  // cascade — bind to a local first.
  final sortedIdxs = byPhase.keys.toList()..sort();
  return sortedIdxs.map((idx) {
    final phaseEntries = byPhase[idx]!;
    final phaseNumber = idx + 1;
    return _PastPhase(
      phaseNumber: phaseNumber,
      startDate: phaseEntries.first.date,
      endDate: phaseEntries.last.date,
      entries: phaseEntries,
    );
  }).toList();
}

class _ScheduleEntry {
  final String key;
  final DateTime date;
  final int week; // 1-4 within the past phase
  final String type; // workout | rest
  final String workoutName;
  final String status;
  final String? completedAt;
  const _ScheduleEntry({
    required this.key,
    required this.date,
    required this.week,
    required this.type,
    required this.workoutName,
    required this.status,
    this.completedAt,
  });
}

class _PastPhase {
  final int phaseNumber;
  final DateTime startDate;
  final DateTime endDate;
  final List<_ScheduleEntry> entries;
  const _PastPhase({
    required this.phaseNumber,
    required this.startDate,
    required this.endDate,
    required this.entries,
  });

  bool hasCompletedDayInWeek(int weekInPhase) {
    final weekStart =
        startDate.add(Duration(days: (weekInPhase - 1) * 7));
    final weekEnd = weekStart.add(const Duration(days: 7));
    return entries.any((e) =>
        e.status == 'completed' &&
        !e.date.isBefore(weekStart) &&
        e.date.isBefore(weekEnd));
  }

  List<_ScheduleEntry> entriesForWeek(int weekInPhase) {
    final weekStart =
        startDate.add(Duration(days: (weekInPhase - 1) * 7));
    final weekEnd = weekStart.add(const Duration(days: 7));
    return entries
        .where((e) =>
            !e.date.isBefore(weekStart) && e.date.isBefore(weekEnd))
        .toList();
  }
}

// ── Past phase group (label + 4 chips, visually muted) ────────────────────

class _PastPhaseGroup extends StatelessWidget {
  const _PastPhaseGroup({required this.past, required this.onTap});
  final _PastPhase past;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final romanLabel = _phaseRoman(past.phaseNumber);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Row(
            children: [
              Text(
                'PHASE $romanLabel',
                style: AppTypography.monoXs.copyWith(
                  fontSize: 9,
                  letterSpacing: 1.2,
                  color: AppColors.textDim,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '(DONE)',
                style: AppTypography.monoXs.copyWith(
                  fontSize: 9,
                  letterSpacing: 1.0,
                  color: AppColors.ok,
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            for (var w = 1; w <= 4; w++)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _PastWeekChip(
                  key: ValueKey('past-${past.phaseNumber}-w$w'),
                  weekInPhase: w,
                  hasCompletedDay: past.hasCompletedDayInWeek(w),
                  startDate: past.startDate,
                  onTap: () => onTap(w),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _PastWeekChip extends StatelessWidget {
  const _PastWeekChip({
    super.key,
    required this.weekInPhase,
    required this.hasCompletedDay,
    required this.startDate,
    required this.onTap,
  });

  final int weekInPhase;
  final bool hasCompletedDay;
  final DateTime startDate;
  final VoidCallback onTap;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _dateRange() {
    final weekStart =
        startDate.add(Duration(days: (weekInPhase - 1) * 7));
    final weekEnd = weekStart.add(const Duration(days: 6));
    if (weekStart.month == weekEnd.month) {
      return '${_months[weekStart.month - 1]} ${weekStart.day}–${weekEnd.day}';
    }
    return '${_months[weekStart.month - 1]} ${weekStart.day}–'
        '${_months[weekEnd.month - 1]} ${weekEnd.day}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 58,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.sharp),
          border: Border.all(color: AppColors.textDim.withValues(alpha: 0.4)),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'W$weekInPhase',
                  style: AppTypography.monoXs.copyWith(
                    fontSize: 10,
                    color: AppColors.textDim,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _dateRange().toUpperCase(),
                  style: AppTypography.monoXs.copyWith(
                    color: AppColors.textDim.withValues(alpha: 0.85),
                    fontSize: 7,
                    letterSpacing: 1,
                    height: 1.1,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            if (hasCompletedDay)
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

/// Theme K — modal bottom sheet rendering the 7-day breakdown of a
/// past-phase week from `schedule_*` Hive entries. Read-only — tapping
/// a day does NOT navigate (the historical workout's exercises live in
/// the exlog_* logs, which would need a separate detail screen; v1
/// keeps this scope tight).
class _PastWeekSheet extends StatelessWidget {
  const _PastWeekSheet({required this.past, required this.weekInPhase});

  final _PastPhase past;
  final int weekInPhase;

  @override
  Widget build(BuildContext context) {
    final entries = past.entriesForWeek(weekInPhase)
      ..sort((a, b) => a.date.compareTo(b.date));
    final romanLabel = _phaseRoman(past.phaseNumber);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.textGhost,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'PHASE $romanLabel · WEEK $weekInPhase',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.accent,
                letterSpacing: 1.5,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Completed history',
              style: AppTypography.h3,
            ),
            const SizedBox(height: 14),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No workouts logged for this week.',
                    style: AppTypography.bodySm
                        .copyWith(color: AppColors.textDim),
                  ),
                ),
              )
            else
              ...entries.map((e) => _PastDayRow(entry: e)),
          ],
        ),
      ),
    );
  }
}

class _PastDayRow extends StatelessWidget {
  const _PastDayRow({required this.entry});
  final _ScheduleEntry entry;

  static const _weekdayLabels = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  @override
  Widget build(BuildContext context) {
    final weekday = _weekdayLabels[(entry.date.weekday - 1) % 7];
    final isCompleted = entry.status == 'completed';
    final isRest = entry.type == 'rest';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.input,
              borderRadius: BorderRadius.circular(AppRadius.sharp),
              border: Border.all(color: AppColors.line2),
            ),
            child: Text(
              weekday.toUpperCase(),
              style: AppTypography.monoXs.copyWith(
                color: AppColors.textDim,
                fontSize: 9,
                letterSpacing: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isRest
                      ? 'Rest day'
                      : entry.workoutName.isNotEmpty
                          ? entry.workoutName
                          : 'Workout',
                  style: AppTypography.h3.copyWith(fontSize: 13),
                ),
                if (!isRest) ...[
                  const SizedBox(height: 2),
                  Text(
                    isCompleted
                        ? 'Completed${entry.completedAt != null ? " · ${_formatTime(entry.completedAt!)}" : ""}'
                        : 'Not completed',
                    style: AppTypography.bodySm.copyWith(
                      color: isCompleted
                          ? AppColors.ok
                          : AppColors.textMute,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isCompleted)
            const Icon(Icons.check_circle, size: 16, color: AppColors.ok)
          else if (!isRest)
            Icon(Icons.remove_circle_outline,
                size: 16, color: AppColors.textMute),
        ],
      ),
    );
  }

  String _formatTime(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// Roman numeral for phase 1-12. Matches the existing PHASE I/II/III
/// label convention used by the forward-phase groups.
String _phaseRoman(int phase) {
  const map = {
    1: 'I', 2: 'II', 3: 'III', 4: 'IV', 5: 'V', 6: 'VI',
    7: 'VII', 8: 'VIII', 9: 'IX', 10: 'X', 11: 'XI', 12: 'XII',
  };
  return map[phase] ?? '$phase';
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
