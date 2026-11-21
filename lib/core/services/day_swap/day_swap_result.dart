// lib/core/services/day_swap/day_swap_result.dart
//
// Value types of the day-swap engine (spec §5.1). Pure: no Hive, no I/O.

/// Where a swap request came from. Telemetry only: the rules are the same
/// for every origin (spec §2, one engine).
enum DaySwapOrigin { trainDrag, trainPicker, homePicker, coach }

/// Why a day cannot take part in a swap (spec §5.2).
enum DaySwapRefusal {
  sameDay,
  differentWeek,
  past,
  noRow,
  completed,
  started,
  paused,
  travel,
  rescheduled,
  skipped,
  allowanceSpent;

  /// Picker label (spec §5.2 table); null where the picker shows none.
  String? get label => switch (this) {
        DaySwapRefusal.completed => 'DONE',
        DaySwapRefusal.started => 'STARTED',
        DaySwapRefusal.paused => 'PAUSED',
        DaySwapRefusal.past => 'PAST',
        DaySwapRefusal.travel => 'TRAVEL',
        DaySwapRefusal.rescheduled => 'RESCHEDULED',
        DaySwapRefusal.skipped => 'SKIPPED',
        DaySwapRefusal.sameDay ||
        DaySwapRefusal.differentWeek ||
        DaySwapRefusal.noRow ||
        DaySwapRefusal.allowanceSpent =>
          null,
      };

  /// Stable snake_case code for telemetry and the coach snapshot's
  /// `swap_block` (Task 28).
  String get code => switch (this) {
        DaySwapRefusal.sameDay => 'same_day',
        DaySwapRefusal.differentWeek => 'different_week',
        DaySwapRefusal.past => 'past',
        DaySwapRefusal.noRow => 'no_row',
        DaySwapRefusal.completed => 'completed',
        DaySwapRefusal.started => 'started',
        DaySwapRefusal.paused => 'paused',
        DaySwapRefusal.travel => 'travel',
        DaySwapRefusal.rescheduled => 'rescheduled',
        DaySwapRefusal.skipped => 'skipped',
        DaySwapRefusal.allowanceSpent => 'allowance_spent',
      };
}

/// Swaps used and allowed in one IST Mon–Sun week (spec §5.3).
class DayAllowance {
  const DayAllowance({
    required this.weekStart,
    required this.used,
    required this.limit,
  });

  /// IST Monday, `YYYY-MM-DD`.
  final String weekStart;
  final int used;
  final int limit;

  /// Never negative: an offline overage (used > limit) reads as 0 left.
  int get left => used >= limit ? 0 : limit - used;
  bool get spent => used >= limit;

  @override
  bool operator ==(Object other) =>
      other is DayAllowance &&
      other.weekStart == weekStart &&
      other.used == used &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(weekStart, used, limit);

  @override
  String toString() => 'DayAllowance($weekStart $used/$limit)';
}

/// The 3+ rest-day run a swap creates or extends (spec §5.6), ascending.
class RestRunWarning {
  const RestRunWarning({required this.runDates});
  final List<String> runDates;

  @override
  bool operator ==(Object other) =>
      other is RestRunWarning && _listEq(other.runDates, runDates);

  @override
  int get hashCode => Object.hashAll(runDates);

  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// What a swap did (spec §5.1).
sealed class DaySwapResult {
  const DaySwapResult();
}

/// Both rows were written and the swap was counted.
class DaySwapDone extends DaySwapResult {
  const DaySwapDone({
    required this.dateA,
    required this.dateB,
    required this.allowanceAfter,
    this.warning,
  });
  final String dateA;
  final String dateB;
  final DayAllowance allowanceAfter;
  final RestRunWarning? warning;
}

/// A rule said no. Nothing was written and nothing was counted.
class DaySwapRefused extends DaySwapResult {
  const DaySwapRefused({required this.reason, required this.date});
  final DaySwapRefusal reason;

  /// The locked day, or dateA for pair / allowance refusals.
  final String date;
}

/// The write failed. Nothing was written and nothing was counted.
class DaySwapFailed extends DaySwapResult {
  const DaySwapFailed();
}

/// One day of a Mon–Sun week, as the picker and the Train list show it.
class DaySwapDayState {
  const DaySwapDayState({
    required this.date,
    required this.row,
    required this.lock,
    required this.isMoved,
    required this.title,
  });
  final String date;
  final Map<String, dynamic>? row;
  final DaySwapRefusal? lock;

  /// "⇄ MOVED": swapped content not yet completed (spec §6.1).
  final bool isMoved;
  final String title;
  bool get movable => lock == null;
}

/// Display-only look at a prospective swap. The engine re-checks
/// everything at confirm time.
class DaySwapPreview {
  const DaySwapPreview({
    required this.allowance,
    this.warning,
    this.refusal,
  });
  final DayAllowance allowance;
  final RestRunWarning? warning;
  final DaySwapRefusal? refusal;
}
