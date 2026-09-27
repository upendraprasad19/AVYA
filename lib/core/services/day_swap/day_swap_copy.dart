// lib/core/services/day_swap/day_swap_copy.dart
//
// Every user-facing day-swap string (spec §6.4) in ONE place, shared by the
// Train week list, the shared picker, the confirm sheet, Home and the coach
// card. `// NEW` marks a string the approved mockup does not contain
// (plan deviation D15). Pure Dart: no Flutter imports.

import 'day_swap_result.dart';
import 'day_swap_rules.dart';

class DaySwapCopy {
  DaySwapCopy._();

  static const _long = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _short = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static int _weekdayIndex(String date) =>
      DaySwapRules.utcDate(date).weekday - 1;

  static String weekdayLong(String date) => _long[_weekdayIndex(date)];
  static String weekdayShort(String date) => _short[_weekdayIndex(date)];

  /// "Fri 25"
  static String dayShort(String date) =>
      '${weekdayShort(date)} ${DaySwapRules.utcDate(date).day}';

  /// "FRI 25"
  static String dayUpper(String date) => dayShort(date).toUpperCase();

  /// "1 swap" / "2 swaps" — pluralised by the number in front (D15).
  static String swaps(int n) => n == 1 ? '1 swap' : '$n swaps';

  static (String, String) _ordered(String a, String b) =>
      a.compareTo(b) <= 0 ? (a, b) : (b, a);

  static String _join(List<String> parts) {
    if (parts.length <= 1) return parts.join();
    return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  }

  /// "Sep 28 – Oct 4"
  static String weekRange(String weekStart) {
    final s = DaySwapRules.utcDate(weekStart);
    final e = s.add(const Duration(days: 6));
    return '${_months[s.month - 1]} ${s.day} – ${_months[e.month - 1]} ${e.day}';
  }

  /// "this week" or "for Sep 28 – Oct 4".
  static String weekPhrase(String weekStart, String currentWeekStart) =>
      weekStart == currentWeekStart ? 'this week' : 'for ${weekRange(weekStart)}';

  /// "today", "tomorrow", or the weekday name.
  static String relativeDay(String date, String today) {
    if (date == today) return 'today';
    if (date == DaySwapRules.addDays(today, 1)) return 'tomorrow';
    return weekdayLong(date);
  }

  // ── Titles ──────────────────────────────────────────────────────
  static const restDay = 'Rest day';
  static const workoutFallback = 'Workout'; // NEW

  static String titleOf(Map<String, dynamic>? row) {
    if (row == null) return '';
    if (DaySwapRules.isRest(row)) return restDay;
    final name = row['workout_name'];
    return name is String && name.trim().isNotEmpty
        ? name.trim()
        : workoutFallback;
  }

  // ── Confirm sheet (drag path) ───────────────────────────────────
  static const confirmEyebrow = 'Swap workout days';
  static const confirmBody =
      'Each workout keeps its exercises, sets and weights. Only the day changes.';
  static const confirmSwap = 'Swap days';
  static const cancel = 'Cancel';

  static String confirmTitle(String dateA, String dateB) {
    final (first, second) = _ordered(dateA, dateB);
    return 'Swap ${weekdayLong(first)} and ${weekdayLong(second)}?';
  }

  /// "FRI 25 · Pull + Core → SAT 26"
  static String confirmMove({
    required String from,
    required String title,
    required String to,
  }) =>
      '${dayUpper(from)} · $title → ${dayUpper(to)}';

  /// "Uses 1 of your 3 swaps this week. 2 left after this."
  static String confirmAllowance(DayAllowance a,
          {required String currentWeekStart}) =>
      'Uses 1 of your ${swaps(a.limit)} '
      '${weekPhrase(a.weekStart, currentWeekStart)}. '
      '${a.left > 0 ? a.left - 1 : 0} left after this.';

  /// NEW: "Heads-up: this leaves Wed, Thu and Fri as rest days in a row."
  static String restRunWarningLine(RestRunWarning w) =>
      'Heads-up: this leaves '
      '${_join(w.runDates.map(weekdayShort).toList())} as rest days in a row.';

  // ── After a swap (toast) ────────────────────────────────────────
  static const movedTag = '⇄ MOVED';

  static String toastTitle(String dateA, String dateB) {
    final (first, second) = _ordered(dateA, dateB);
    return '${weekdayLong(first)} and ${weekdayLong(second)} swapped.';
  }

  /// The workout the toast names: the content now on the EARLIER date,
  /// unless that is a rest day (then the other); null when both are rest.
  /// [a] and [b] are the two days' states from BEFORE the swap.
  static ({String title, String date})? toastSubject(
      DaySwapDayState a, DaySwapDayState b) {
    final (early, late) = a.date.compareTo(b.date) <= 0 ? (a, b) : (b, a);
    if (!DaySwapRules.isRest(late.row)) {
      return (title: late.title, date: early.date);
    }
    if (!DaySwapRules.isRest(early.row)) {
      return (title: early.title, date: late.date);
    }
    return null;
  }

  /// "Legs + Core is now tomorrow. 2 swaps left this week."
  static String toastBody({
    required ({String title, String date})? subject,
    required String today,
    required DayAllowance after,
    required String currentWeekStart,
  }) {
    final left =
        '${swaps(after.left)} left ${weekPhrase(after.weekStart, currentWeekStart)}.';
    if (subject == null) return left;
    return '${subject.title} is now ${relativeDay(subject.date, today)}. $left';
  }

  // ── Allowance line (Train week list) ────────────────────────────
  static const allowanceHint = 'Hold a day and drag it onto another, or tap ⇅';

  /// "3 swaps left this week." / "3 swaps left for Sep 28 – Oct 4."
  static String allowanceLine(DayAllowance a,
          {required String currentWeekStart}) =>
      '${swaps(a.left)} left ${weekPhrase(a.weekStart, currentWeekStart)}.';

  // ── Picker ──────────────────────────────────────────────────────
  static const pickerTodayTag = 'today';
  static const pickerFooter = 'DONE, STARTED, PAUSED AND PAST DAYS STAY PUT';
  static const spentTitleFree = "This week's swap is spent.";
  static const spentBodyFree =
      'Your allowance resets Monday. PRO gets 3 swaps a week, from the Train tab, Home, or by asking the coach.';
  static const seePro = 'See PRO';
  static const close = 'Close';

  static String pickerTitle(String date) => 'Swap ${weekdayLong(date)} with…';

  /// "Pull + Core · 3 swaps left this week" /
  /// "Pull + Core · 0 of 1 swaps left this week" (spent).
  static String pickerSubtitle({
    required String title,
    required DayAllowance a,
    required String currentWeekStart,
  }) {
    final week = weekPhrase(a.weekStart, currentWeekStart);
    return a.spent
        ? '$title · 0 of ${a.limit} swaps left $week'
        : '$title · ${swaps(a.left)} left $week';
  }

  /// "Swap Fri and Sat"
  static String pickerButton(String dateA, String dateB) {
    final (first, second) = _ordered(dateA, dateB);
    return 'Swap ${weekdayShort(first)} and ${weekdayShort(second)}';
  }

  // ── Errors ──────────────────────────────────────────────────────
  static const writeFailed = "Couldn't swap. Nothing was changed.";
  static const sameDayLine =
      'Pick two different days. Nothing was changed.'; // NEW
  static const differentWeekLine =
      'Swaps stay inside one Mon–Sun week. Nothing was changed.'; // NEW

  /// "All 3 swaps used. Resets Monday."
  static String proSpent(int limit) => 'All $limit swaps used. Resets Monday.';

  /// "Friday is already done. Nothing was changed." — every other reason
  /// is NEW.
  static String staleLine(DaySwapRefusal reason, String date) {
    final phrase = switch (reason) {
      DaySwapRefusal.completed => 'is already done',
      DaySwapRefusal.started => 'is already started',
      DaySwapRefusal.paused => 'is paused',
      DaySwapRefusal.past => 'has already passed',
      DaySwapRefusal.travel => 'is a travel day',
      DaySwapRefusal.rescheduled => 'was rescheduled',
      DaySwapRefusal.skipped => 'was skipped',
      DaySwapRefusal.noRow => 'has no workout planned',
      DaySwapRefusal.sameDay ||
      DaySwapRefusal.differentWeek ||
      DaySwapRefusal.allowanceSpent =>
        'cannot be swapped',
    };
    return '${weekdayLong(date)} $phrase. Nothing was changed.';
  }

  /// The line a result should show, or null on success. "No signal /
  /// server down: nothing shown" (spec §6.4) needs no entry: the allowance
  /// call never blocks or fails a swap.
  static String? errorFor(DaySwapResult result,
      {required bool isPro, required int limit}) {
    switch (result) {
      case DaySwapDone():
        return null;
      case DaySwapFailed():
        return writeFailed;
      case DaySwapRefused(:final reason, :final date):
        return switch (reason) {
          DaySwapRefusal.allowanceSpent =>
            isPro ? proSpent(limit) : spentTitleFree,
          DaySwapRefusal.sameDay => sameDayLine,
          DaySwapRefusal.differentWeek => differentWeekLine,
          _ => staleLine(reason, date),
        };
    }
  }

  // ── Coach card (client, PRO) ────────────────────────────────────
  /// "Swap Fri 25 and Sat 26"
  static String coachCardTitle(String dateA, String dateB) {
    final (first, second) = _ordered(dateA, dateB);
    return 'Swap ${dayShort(first)} and ${dayShort(second)}';
  }

  /// "Pull + Core FRI → SAT"
  static String coachCardMove({
    required String title,
    required String from,
    required String to,
  }) =>
      '$title ${weekdayShort(from).toUpperCase()} → ${weekdayShort(to).toUpperCase()}';

  /// "Uses 1 of your 3 swaps this week."
  static String coachCardAllowance(DayAllowance a,
          {required String currentWeekStart}) =>
      'Uses 1 of your ${swaps(a.limit)} '
      '${weekPhrase(a.weekStart, currentWeekStart)}.';
}
