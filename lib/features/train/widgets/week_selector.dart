import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/core/services/workout_read_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'hold_chip_group.dart';

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
  /// The user's REAL current phase (`user_progress.current_phase`, surfaced as
  /// `CurrentPlanData.phase`). Drives the phase labels so the strip never shows
  /// a hardcoded "PHASE I" that collides with a completed past phase. Fix
  /// 2026-06-02 (two-Phase-1 bug) — previously the forward groups were
  /// hardcoded `PHASE I/II/III` and `_loadPastPhases` renumbered from 1, so a
  /// completed phase was always labelled "PHASE I (DONE)" next to a current
  /// "PHASE I". Both readers now derive from this single SoT.
  final int currentPhase;
  final ValueChanged<int> onSelect;

  const WeekSelector({
    super.key,
    required this.totalWeeks,
    required this.selectedWeek,
    required this.currentPhase,
    required this.onSelect,
  });

  @override
  ConsumerState<WeekSelector> createState() => _WeekSelectorState();
}

class _WeekSelectorState extends ConsumerState<WeekSelector> {
  // Obs 3b (2026-06-05): auto-scroll the strip to the current phase on open +
  // a contextual "TODAY →" pill that fades in only when the current phase is
  // scrolled out of view (so the user never hunts for the live week).
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _currentPhaseKey = GlobalKey();
  bool _showTodayPill = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrent(animate: false); // open already positioned at "now"
    });
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToCurrent({bool animate = true}) {
    final keyCtx = _currentPhaseKey.currentContext;
    if (keyCtx == null) return;
    Scrollable.ensureVisible(
      keyCtx,
      alignment: 0.0, // current phase's leading edge → viewport's leading edge
      duration: animate ? const Duration(milliseconds: 350) : Duration.zero,
      curve: Curves.easeOut,
    );
  }

  void _onScroll() {
    if (!mounted) return;
    final keyCtx = _currentPhaseKey.currentContext;
    final selfObj = context.findRenderObject();
    if (keyCtx == null || selfObj is! RenderBox) return;
    final groupObj = keyCtx.findRenderObject();
    if (groupObj is! RenderBox) return;
    final left = groupObj.localToGlobal(Offset.zero, ancestor: selfObj).dx;
    final right = left + groupObj.size.width;
    // Current phase "visible" if a meaningful part sits inside the viewport.
    final visible = right > 24 && left < selfObj.size.width - 24;
    final shouldShow = !visible;
    if (shouldShow != _showTodayPill) {
      setState(() => _showTodayPill = shouldShow);
    }
  }

  @override
  Widget build(BuildContext context) {
    // APK Test #12 / Task C-2 — watch subscriptionInfoProvider so the
    // PHASE II / III lock chips re-render the moment payment confirms.
    final isPro = ref.watch(subscriptionInfoProvider).isPro;
    final service = ref.read(workoutScheduleReadServiceProvider);
    final planStart = service.getPlanStartDate();
    // Obs 3a (2026-06-05): current/forward week chips that have a completed day
    // — same "any completed day that week" rule as the past-phase chips.
    final completedWeeks = service.completedWeekNumbers();

    // Theme K — render completed past phases LEFT of the current phase.
    // Source: the shared `pastPhaseBlocks()` SoT (the SAME bucketing the phase
    // reconciler uses — no parallel reader to drift). currentPhase drives the
    // numbering AND the gate (no past groups on Phase 1 — you can't have
    // completed a phase yet).
    final pastPhases =
        _toPastPhases(service.pastPhaseBlocks(), widget.currentPhase);

    // Free-tier hold weeks (ship-dark `enable_hold_weeks`). Always
    // HoldStatusData.empty while the flag is OFF, so everything below this line
    // is inert — the strip renders exactly as it did pre-hold-display.
    final holdStatus = ref.watch(holdStatusProvider);
    final isHolding = holdStatus.holds.isNotEmpty;
    // Two groups would otherwise both read "PHASE I"; the phase NAME
    // disambiguates the training block from the holding block (locked mockup).
    // Suffix only — the label itself is built at the _PhaseGroup call site so
    // the first `_phaseRoman(widget.currentPhase)` in this file stays INSIDE
    // the current-phase group, after the past-phase loop
    // (`week_selector_past_phases_test.dart` pins that source order as its
    // proxy for "past groups render LEFT of the current group").
    final holdingNameSuffix = isHolding
        ? ' · ${service.phaseName(widget.currentPhase).toUpperCase()}'
        : '';

    final strip = SingleChildScrollView(
      controller: _scrollCtrl,
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
          // Current phase (always accessible — you're on it). Label derived
          // from the real current_phase, not a hardcoded "PHASE I".
          _PhaseGroup(
            key: _currentPhaseKey,
            label: 'PHASE ${_phaseRoman(widget.currentPhase)}'
                '$holdingNameSuffix',
            isPaywalled: false,
            weekStart: 1,
            weekEnd: 4,
            selectedWeek: widget.selectedWeek,
            planStart: planStart,
            completedWeeks: completedWeeks,
            onTap: widget.onSelect,
          ),
          // Hold weeks sit between the phase they extend and the next phase.
          // Tapping one opens a read-only sheet — never `onSelect`, which is
          // week-index-keyed and cannot address a hold (see HoldChipGroup).
          if (isHolding) ...[
            const SizedBox(width: 16),
            HoldChipGroup(
              phaseLabel: 'PHASE ${_phaseRoman(widget.currentPhase)}',
              holds: holdStatus.holds,
              todayHoldOrdinal: holdStatus.todayHoldOrdinal,
              onTapHold: (hold) => _showHoldWeekSheet(context, hold),
            ),
          ],
          const SizedBox(width: 16),
          // Next phase preview (PRO-locked for free users).
          _PhaseGroup(
            label: 'PHASE ${_phaseRoman(widget.currentPhase + 1)}',
            isPaywalled: !isPro,
            weekStart: 5,
            weekEnd: 8,
            selectedWeek: widget.selectedWeek,
            planStart: planStart,
            completedWeeks: completedWeeks,
            onTap: widget.onSelect,
          ),
          const SizedBox(width: 16),
          _PhaseGroup(
            label: 'PHASE ${_phaseRoman(widget.currentPhase + 2)}',
            isPaywalled: !isPro,
            weekStart: 9,
            weekEnd: 12,
            selectedWeek: widget.selectedWeek,
            planStart: planStart,
            completedWeeks: completedWeeks,
            onTap: widget.onSelect,
          ),
        ],
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        strip,
        Positioned(
          right: 8,
          bottom: 2,
          child: IgnorePointer(
            ignoring: !_showTodayPill,
            child: AnimatedOpacity(
              opacity: _showTodayPill ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: GestureDetector(
                onTap: _scrollToCurrent,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(AppRadius.sharp),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'TODAY',
                        style: AppTypography.monoXs.copyWith(
                          fontSize: 9,
                          color: AppColors.bgDeep,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(Icons.arrow_forward,
                          size: 11, color: AppColors.bgDeep),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
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

  void _showHoldWeekSheet(BuildContext context, HoldWeekInfo hold) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => HoldWeekSheet(hold: hold),
    );
  }
}

/// Maps the shared [PastPhaseBlock] list (the single bucketing SoT — see
/// `WorkoutScheduleReadService.pastPhaseBlocks`) into the display model,
/// numbering past phases by their REAL phase number ending at currentPhase-1.
///
/// You have completed exactly currentPhase-1 phases, so show at most that many
/// (the most recent blocks) and number them up to currentPhase-1. When
/// currentPhase == 1 there are no completed phases → render none, killing the
/// phantom duplicate even before the data-heal advances the counter. Showing
/// fewer than the raw block count also gracefully tolerates stale / duplicate
/// schedule data without deleting anything. Fix 2026-06-02 (two-Phase-1 bug;
/// previously numbered idx+1, always labelling the oldest block "PHASE I" and
/// colliding with the hardcoded forward "PHASE I").
List<_PastPhase> _toPastPhases(List<PastPhaseBlock> blocks, int currentPhase) {
  final showCount = (currentPhase - 1).clamp(0, blocks.length);
  if (showCount == 0) return const [];
  final shown = blocks.sublist(blocks.length - showCount);
  final firstNumber = currentPhase - showCount; // e.g. cp=2,count=1 → 1
  final result = <_PastPhase>[];
  for (var i = 0; i < shown.length; i++) {
    final entries = <_ScheduleEntry>[];
    for (final map in shown[i].rows) {
      final dateStr = map['date'] as String?;
      if (dateStr == null) continue;
      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;
      entries.add(_ScheduleEntry(
        key: 'schedule_$dateStr', // canonical key format ('schedule_' + dateStr)
        date: date,
        week: (map['week'] as int?) ?? 0,
        type: (map['type'] as String?) ?? 'rest',
        workoutName: (map['workout_name'] as String?) ?? '',
        status: (map['status'] as String?) ?? 'planned',
        completedAt: map['completed_at'] as String?,
      ));
    }
    if (entries.isEmpty) continue;
    entries.sort((a, b) => a.date.compareTo(b.date));
    result.add(_PastPhase(
      phaseNumber: firstNumber + i,
      startDate: entries.first.date,
      endDate: entries.last.date,
      entries: entries,
    ));
  }
  return result;
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
      child: ConstrainedBox(
        // Cap the sheet so a full 7-row week (with expanded rows) scrolls
        // instead of overflowing the screen. Header stays pinned.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
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
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final e in entries) _PastDayRow(entry: e),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Derives a past day's display name + the exercises actually logged that
/// day from the canonical log rows, rather than the (often name-less)
/// restored schedule row. Visible for testing.
///
/// [scheduleKey] is the `schedule_<dateStr>` Hive key; [fallbackName] is the
/// schedule row's own `workout_name` (used only when the `wlog_<dateStr>`
/// session row carries none — e.g. a planned-but-skipped day). The name
/// precedence is: wlog session name → schedule name → 'Workout'. Exercises
/// come from the canonical [WorkoutReadService.exerciseLogsForIstDate]
/// reader. See diagnose f4e1d9.
({String name, List<Map<String, dynamic>> exercises}) derivePastDayLog(
  String scheduleKey,
  String fallbackName,
) {
  final dateStr = scheduleKey.startsWith('schedule_')
      ? scheduleKey.substring('schedule_'.length)
      : '';
  if (dateStr.isEmpty) {
    return (
      name: fallbackName.isNotEmpty ? fallbackName : 'Workout',
      exercises: const <Map<String, dynamic>>[],
    );
  }
  final wlog = HiveService.instance.workoutBox.get('wlog_$dateStr');
  final wlogName = (wlog is Map) ? wlog['workout_name'] as String? : null;
  final name = (wlogName != null && wlogName.isNotEmpty)
      ? wlogName
      : (fallbackName.isNotEmpty ? fallbackName : 'Workout');
  final exercises =
      WorkoutReadService.instance.exerciseLogsForIstDate(dateStr);
  return (name: name, exercises: exercises);
}

/// Theme K v2 (2026-06-01 / diagnose f4e1d9) — a past-day row that
/// DERIVES its content from the actual logs, then expands (drop-down) to
/// show the exercises the user really did.
///
/// Why derive: cloud `scheduled_workouts` has no `workout_name`/exercises
/// column, and the schedule-row restore only hydrates a name when a
/// `template_id` is set — plan-generator days (`template_id IS NULL`) come
/// back name-less, so the bare schedule row rendered a generic "Workout".
/// The restored `wlog_<date>` session row DOES carry the name (Push/Pull/
/// Legs), and the `exlog_*` rows carry the exercises. We read both via the
/// canonical [WorkoutReadService.exerciseLogsForIstDate] (same path the
/// receipt + Train screen use) so there is no parallel reader to drift.
class _PastDayRow extends StatefulWidget {
  const _PastDayRow({required this.entry});
  final _ScheduleEntry entry;

  @override
  State<_PastDayRow> createState() => _PastDayRowState();
}

class _PastDayRowState extends State<_PastDayRow> {
  static const _weekdayLabels = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  bool _expanded = false;
  late final String _displayName;
  late final List<Map<String, dynamic>> _exercises;

  @override
  void initState() {
    super.initState();
    final derived =
        derivePastDayLog(widget.entry.key, widget.entry.workoutName);
    _displayName = derived.name;
    _exercises = derived.exercises;
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final weekday = _weekdayLabels[(entry.date.weekday - 1) % 7];
    final isCompleted = entry.status == 'completed';
    final isRest = entry.type == 'rest';
    final exerciseCount = _exercises.length;
    final canExpand = !isRest && exerciseCount > 0;

    final subtitle = isCompleted
        ? '${exerciseCount > 0 ? "$exerciseCount exercise${exerciseCount == 1 ? "" : "s"} · " : ""}'
            'Completed${entry.completedAt != null ? " · ${_formatTime(entry.completedAt!)}" : ""}'
        : 'Not completed';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: BorderRadius.circular(AppRadius.sharp),
        border: Border.all(color: AppColors.line2),
      ),
      child: Column(
        children: [
          InkWell(
            onTap:
                canExpand ? () => setState(() => _expanded = !_expanded) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.bgRaise,
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
                          isRest ? 'Rest day' : _displayName,
                          style: AppTypography.h3.copyWith(fontSize: 13),
                        ),
                        if (!isRest) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
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
                    const Icon(Icons.remove_circle_outline,
                        size: 16, color: AppColors.textMute),
                  if (canExpand) ...[
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: const Icon(Icons.expand_more,
                          size: 18, color: AppColors.textDim),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_expanded && canExpand)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final ex in _exercises) _ExerciseLine(log: ex),
                ],
              ),
            ),
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

/// One logged exercise inside an expanded past-day row: name + a compact
/// "N sets · W kg" summary built from the exlog top-level fields, with a
/// PR marker. Time/distance exercises show their duration/distance instead.
class _ExerciseLine extends StatelessWidget {
  const _ExerciseLine({required this.log});
  final Map<String, dynamic> log;

  @override
  Widget build(BuildContext context) {
    final name = (log['exercise_name'] as String?) ?? 'Exercise';
    final sets = (log['set_number'] as num?)?.toInt() ?? 0;
    final weight = (log['weight_kg'] as num?)?.toDouble() ?? 0;
    // Canonical per-set duration read — WriteService never emits a
    // top-level `duration_seconds` on modern rows (lives at
    // `sets[].duration_sec`). See no_top_level_duration_seconds_reads_test.
    final durationSec = WorkoutReadService.bestPerSetDuration(log);
    final distanceKm = (log['distance_km'] as num?)?.toDouble() ?? 0;
    final isPr = log['is_pr'] == true;

    final parts = <String>[];
    if (sets > 0) parts.add('$sets ${sets == 1 ? "set" : "sets"}');
    if (weight > 0) {
      parts.add('${weight % 1 == 0 ? weight.toInt() : weight} kg');
    }
    if (durationSec > 0) parts.add('${(durationSec / 60).round()} min');
    if (distanceKm > 0) parts.add('$distanceKm km');
    final detail = parts.join(' · ');

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 3,
            decoration: const BoxDecoration(
              color: AppColors.textGhost,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              style: AppTypography.bodySm.copyWith(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isPr) ...[
            const Icon(Icons.star, size: 12, color: AppColors.accent),
            const SizedBox(width: 6),
          ],
          if (detail.isNotEmpty)
            Text(
              detail,
              style: AppTypography.monoXs.copyWith(
                color: AppColors.textDim,
                fontSize: 10,
              ),
            ),
        ],
      ),
    );
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
    super.key,
    required this.label,
    required this.isPaywalled,
    required this.weekStart,
    required this.weekEnd,
    required this.selectedWeek,
    required this.planStart,
    required this.completedWeeks,
    required this.onTap,
  });

  final String label;
  final bool isPaywalled;
  final int weekStart;
  final int weekEnd;
  final int selectedWeek;
  final DateTime? planStart;
  final Set<int> completedWeeks;
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
                  hasCompletedDay: completedWeeks.contains(w),
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
    this.hasCompletedDay = false,
    required this.planStart,
    required this.onTap,
  });

  final int week;
  final bool isSelected;
  final bool isLocked;
  final bool hasCompletedDay;
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
            // Obs 3a (2026-06-05): ✓ on a current/forward week with ≥1 completed
            // day (mirrors _PastWeekChip). Never on a locked/preview week.
            if (hasCompletedDay && !isLocked)
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
