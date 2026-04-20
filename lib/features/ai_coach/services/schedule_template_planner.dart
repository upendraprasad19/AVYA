import '../../../core/services/hive_service.dart';

/// One date in a `scheduleTemplate` plan (display row).
///
/// `willSkip` is true ONLY when the existing schedule entry on that date is
/// already `completed` — history is sacred and is never overwritten.
/// `willReplace` is true when there's an existing non-completed entry that
/// will be displaced by the new template assignment.
class ScheduleTemplateAssignment {
  /// YYYY-MM-DD calendar date.
  final String date;
  /// The Hive `tmpl_*` ID that will land on this date (for multi-day groups
  /// this is the resolved per-day id, NOT necessarily the seed id the AI
  /// supplied).
  final String templateId;
  /// Top-level group name (the user-facing "Hypertrophy Split").
  final String templateName;
  /// Per-day name shown in the diff row (e.g. "Push Day", "Lower Body A").
  /// For single-day templates this equals [templateName].
  final String dayName;
  /// Existing schedule entry's name, if any (used in the "was: …" line).
  final String? currentWorkoutName;
  /// True when displacing an existing non-completed entry.
  final bool willReplace;
  /// True when the existing entry is `completed` and we WON'T touch it.
  final bool willSkip;
  /// 'completed' when [willSkip] is true. Reserved for future categories.
  final String? skipReason;

  const ScheduleTemplateAssignment({
    required this.date,
    required this.templateId,
    required this.templateName,
    required this.dayName,
    this.currentWorkoutName,
    required this.willReplace,
    required this.willSkip,
    this.skipReason,
  });
}

/// Aggregate result returned by [ScheduleTemplatePlanner.plan].
class ScheduleTemplateResult {
  /// One row per date the AI asked to schedule (skipped + assigned both).
  final List<ScheduleTemplateAssignment> assignments;
  /// Top-level template group name (or single template name).
  final String groupName;
  /// 1 for single-day templates; N for a multi-day group.
  final int totalDaysInGroup;
  /// How many dates will actually receive a write.
  final int willScheduleCount;
  /// How many dates were skipped because they're completed.
  final int skipCompletedCount;

  const ScheduleTemplateResult({
    required this.assignments,
    required this.groupName,
    required this.totalDaysInGroup,
    required this.willScheduleCount,
    required this.skipCompletedCount,
  });
}

/// Plans calendar-date assignments for the AI coach `scheduleTemplate` tool
/// (Phase D.7).
///
/// Two-phase contract (mirrors D.3 [RegeneratePlanPlanner]):
///   1. Diff widget calls [plan] in `initState`. The returned record carries
///      both the display rows AND the resolved (date, templateId) pairs the
///      dispatcher needs to execute the writes — they're cached together
///      atomically via [cache] keyed on `intent.id`.
///   2. On Confirm, dispatcher reads [getCachedAssignments] and writes
///      schedule entries via [WorkoutScheduleService.assignTemplateToDate]
///      (the canonical single-template-to-single-date path — handles
///      displaced backups, warm-up/cool-down injection, completed guard).
///   3. [clearCache] runs after execution.
///
/// Multi-day group fan-out:
///   - If the seed templateId carries a `group_id`, ALL templates with that
///     group_id are loaded and sorted by `group_day_index` (1..N).
///   - For each target date `dates[i]`, the planner picks the day at index
///     `i % totalDays` so a 3-day template scheduled across [Mon, Wed, Fri,
///     MonNext, WedNext] cycles as Day1, Day2, Day3, Day1, Day2.
///   - For single-day templates (no group_id) the same template lands on
///     every supplied date.
class ScheduleTemplatePlanner {
  ScheduleTemplatePlanner._();
  static final ScheduleTemplatePlanner instance = ScheduleTemplatePlanner._();

  final Map<String, ScheduleTemplateResult> _cache = {};
  /// Per-intent cache of (date, templateId) pairs the dispatcher executes.
  /// Records (Dart 3) keep the pair tightly bound — no positional drift risk.
  final Map<String, List<({String date, String templateId})>> _assignmentCache =
      {};

  /// Returns a `(plan, assignments)` record. The diff widget caches both via
  /// [cache] keyed on `intent.id`, and the dispatcher reads the assignments
  /// from [getCachedAssignments] when applying the change.
  Future<
      ({
        ScheduleTemplateResult plan,
        List<({String date, String templateId})> assignments
      })> plan({
    required String templateId,
    required List<String> dates,
  }) async {
    final box = HiveService.instance.workoutBox;

    // 1. Resolve the seed template.
    final seedTemplate = _findTemplateById(box, templateId);
    if (seedTemplate == null) {
      throw StateError('Template $templateId not found in user library.');
    }

    // 2. Build the day list — single template OR full group sorted by index.
    final groupId = seedTemplate['group_id']?.toString();
    final groupName =
        (seedTemplate['group_name'] ?? seedTemplate['name'] ?? 'Workout')
            .toString();
    final List<Map<String, dynamic>> groupDays;

    if (groupId != null && groupId.isNotEmpty) {
      groupDays = box.keys
          .where((k) => k.toString().startsWith('tmpl_'))
          .map((k) => box.get(k))
          .where((t) =>
              t is Map &&
              (t['group_id']?.toString() ?? '') == groupId)
          .map((t) => Map<String, dynamic>.from(t as Map))
          .toList()
        ..sort((a, b) {
          final ai = (a['group_day_index'] as num?)?.toInt() ?? 0;
          final bi = (b['group_day_index'] as num?)?.toInt() ?? 0;
          return ai.compareTo(bi);
        });
    } else {
      groupDays = [seedTemplate];
    }

    if (groupDays.isEmpty) {
      throw StateError(
          'Template group $groupId resolved to zero days — library is corrupted.');
    }
    final totalDays = groupDays.length;

    // 3. Walk dates, resolve which day lands on each, classify.
    final displayRows = <ScheduleTemplateAssignment>[];
    final assignments = <({String date, String templateId})>[];
    var willScheduleCount = 0;
    var skipCompletedCount = 0;

    for (var i = 0; i < dates.length; i++) {
      final date = dates[i];
      final dayTemplate = groupDays[i % totalDays];
      final assignedId =
          dayTemplate['id']?.toString() ?? templateId;
      final dayName = (dayTemplate['day_name'] ??
              dayTemplate['name'] ??
              'Workout')
          .toString();

      final existing = box.get('schedule_$date');
      final existingMap = existing is Map
          ? Map<String, dynamic>.from(existing)
          : null;
      final isCompleted = existingMap != null &&
          existingMap['status'] == 'completed';
      final existingName = existingMap == null
          ? null
          : (existingMap['workout_name'] ??
                  existingMap['name'] ??
                  'Workout')
              .toString();

      displayRows.add(ScheduleTemplateAssignment(
        date: date,
        templateId: assignedId,
        templateName: groupName,
        dayName: dayName,
        currentWorkoutName: existingName,
        willReplace: existingMap != null && !isCompleted,
        willSkip: isCompleted,
        skipReason: isCompleted ? 'completed' : null,
      ));

      if (isCompleted) {
        skipCompletedCount++;
      } else {
        assignments.add((date: date, templateId: assignedId));
        willScheduleCount++;
      }
    }

    final result = ScheduleTemplateResult(
      assignments: displayRows,
      groupName: groupName,
      totalDaysInGroup: totalDays,
      willScheduleCount: willScheduleCount,
      skipCompletedCount: skipCompletedCount,
    );

    return (plan: result, assignments: assignments);
  }

  void cache(
    String intentId,
    ScheduleTemplateResult plan,
    List<({String date, String templateId})> assignments,
  ) {
    _cache[intentId] = plan;
    _assignmentCache[intentId] = assignments;
  }

  ScheduleTemplateResult? getCachedPlan(String intentId) => _cache[intentId];

  List<({String date, String templateId})>? getCachedAssignments(
          String intentId) =>
      _assignmentCache[intentId];

  void clearCache(String intentId) {
    _cache.remove(intentId);
    _assignmentCache.remove(intentId);
  }

  Map<String, dynamic>? _findTemplateById(dynamic box, String templateId) {
    // Fast path — direct key lookup.
    final raw = box.get(templateId);
    if (raw is Map) return Map<String, dynamic>.from(raw);
    // Fallback: scan tmpl_* keys for nested id match (defensive — Template
    // Builder writes the same id to both the Hive key AND the map's id
    // field, but a future writer might diverge).
    for (final k in box.keys.where((k) => k.toString().startsWith('tmpl_'))) {
      final v = box.get(k);
      if (v is Map && v['id']?.toString() == templateId) {
        return Map<String, dynamic>.from(v);
      }
    }
    return null;
  }
}
