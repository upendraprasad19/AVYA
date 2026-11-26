// Nutrition History v2 views (plan docs/plans/nutrition-history-v2.md §9-§12).
// Pure: no Hive, no Riverpod; every input is already in NutritionHistoryData.
// Calendar maths on IST day KEYS only (parseDayKey), never a local DateTime.

import 'dart:math' as math;

import 'nutrition_history.dart';

// ── Header (U1) ──────────────────────────────────────────────────

const int kHeaderWindowDays = 30;

/// Header numbers over ALL days (never the range chip). [logged30] is the
/// days logged among the last 30 calendar days INCLUDING today, null when the
/// whole history is 30 days or shorter (it would repeat [logged]).
/// [avgProtein30] is the mean protein of full days in that window.
({int logged, int? logged30, double? avgProtein30}) journeyStats(
  List<JudgedDay> days,
) {
  final logged = days.where((j) => j.day.logged).length;
  final window = days.length <= kHeaderWindowDays
      ? days
      : days.sublist(days.length - kHeaderWindowDays);
  final full = [
    for (final j in window)
      if (j.isComplete) j.day.protein,
  ];
  return (
    logged: logged,
    logged30: days.length <= kHeaderWindowDays
        ? null
        : window.where((j) => j.day.logged).length,
    avgProtein30: full.isEmpty
        ? null
        : full.reduce((a, b) => a + b) / full.length,
  );
}

// ── Logging run (U3, §11) ────────────────────────────────────────

/// Consecutive logged days. [current] counts back from today when today is
/// logged, else from yesterday (today in progress never ends it). [best] is
/// the longest run anywhere. A day with no log ends a run.
({int current, int best, bool todayLogged}) loggingRun(
  List<JudgedDay> days,
  String todayKey,
) {
  var best = 0, run = 0;
  for (final j in days) {
    if (j.day.logged) {
      run++;
      if (run > best) best = run;
    } else if (j.date != todayKey) {
      run = 0;
    }
  }
  var current = 0;
  var todayLogged = false;
  for (var i = days.length - 1; i >= 0; i--) {
    final j = days[i];
    if (j.date == todayKey) {
      todayLogged = j.day.logged;
      if (!j.day.logged) continue;
    }
    if (!j.day.logged) break;
    current++;
  }
  return (current: current, best: best, todayLogged: todayLogged);
}

/// The one line under the header stats (§11, §12 plurals).
String loggingRunLine(({int current, int best, bool todayLogged}) r) {
  String days(int n) => n == 1 ? '1 day' : '$n days';
  final String base;
  if (r.current == 0) {
    base = 'Log a meal today to start a logging run.';
  } else if (r.todayLogged) {
    base = r.current == 1
        ? 'Logged 1 day, today included.'
        : 'Logged ${r.current} days in a row, today included.';
  } else {
    base =
        'Logged ${days(r.current)} in a row. '
        'Log today to make it ${r.current + 1}.';
  }
  return (r.best > r.current && r.best >= 3) ? '$base Best: ${r.best}.' : base;
}

// ── Zero-state reason (U4, §9) ───────────────────────────────────

const int kZeroReasonMinDays = 3;

/// The latest known target among [days], or null.
DayTarget? latestTarget(List<JudgedDay> days) {
  for (var i = days.length - 1; i >= 0; i--) {
    if (days[i].target != null) return days[i].target;
  }
  return null;
}

/// Why a calories or protein row shows 0 hits, and one next step; null when
/// there are hits, fewer than [kZeroReasonMinDays] counted days, no target, or
/// [kind] is water.
String? hitZeroReason(List<JudgedDay> days, HitKind kind, String todayKey) {
  if (kind == HitKind.water) return null;
  final s = hitStats(days, kind, todayKey);
  if (s.hits > 0 || s.counted < kZeroReasonMinDays) return null;
  final t = latestTarget(days);
  if (t == null) return null;
  final counted = [
    for (final j in days)
      if (j.date != todayKey && hitOf(j, kind, todayKey, 0) != null) j,
  ];
  if (kind == HitKind.calories) {
    var under = 0, over = 0;
    for (final j in counted) {
      if (j.day.calories < j.target!.calories) {
        under++;
      } else {
        over++;
      }
    }
    final band = (t.calories * kOnTargetCalorieBand).round();
    final why = under > over
        ? 'Most of your full days were under your calorie target.'
        : over > under
        ? 'Most of your full days were over your calorie target.'
        : 'Your full days landed both under and over your calorie target.';
    return '$why Land within $band kcal of ${t.calories.round()} tomorrow '
        'to start a run.';
  }
  final avg = counted.fold(0.0, (s, j) => s + j.day.protein) / counted.length;
  final need = (t.protein * kOnTargetProteinShare).round();
  return 'Your full days averaged ${avg.round()} g; 90% of your current '
      'target is $need g. Hit $need g tomorrow to start a run.';
}

// ── Chart bounds (U5, U7) ────────────────────────────────────────

/// Rounded y bounds that include every value and [target]. [step] rounds
/// outward; a flat series is widened by one step each side.
({double lo, double hi}) chartBounds(
  Iterable<double> values, {
  double? target,
  required double step,
}) {
  var lo = double.infinity, hi = -double.infinity;
  for (final v in values) {
    lo = math.min(lo, v);
    hi = math.max(hi, v);
  }
  if (target != null) {
    lo = math.min(lo, target);
    hi = math.max(hi, target);
  }
  if (lo == double.infinity) return (lo: 0, hi: step);
  lo = (lo / step).floorToDouble() * step;
  hi = (hi / step).ceilToDouble() * step;
  if (hi <= lo) {
    lo -= step;
    hi += step;
  }
  return (lo: lo, hi: hi);
}

// ── Protein by meal (U10) ────────────────────────────────────────

const int kSlotMinDays = 3;
const int kSlotGapCapG = 30;

/// Average protein per meal slot over full days; empty below [kSlotMinDays].
Map<String, double> slotProteinAverages(List<JudgedDay> days) {
  final full = [
    for (final j in days)
      if (j.isComplete) j.day,
  ];
  if (full.length < kSlotMinDays) return const {};
  return {
    for (final slot in kMealSlots)
      slot:
          full.fold(0.0, (s, d) => s + (d.proteinBySlot[slot] ?? 0)) /
          full.length,
  };
}

/// The suggestion line, or null: the lowest of breakfast / lunch / dinner,
/// when the average full day is under 90 % of the current protein target.
String? slotProteinLine(List<JudgedDay> days) {
  final avgs = slotProteinAverages(days);
  if (avgs.isEmpty) return null;
  final t = latestTarget(days);
  if (t == null || t.protein <= 0) return null;
  final total = avgs.values.fold(0.0, (a, b) => a + b);
  final need = t.protein * kOnTargetProteinShare;
  if (total >= need) return null;
  var low = 'breakfast';
  for (final s in const ['lunch', 'dinner']) {
    if (avgs[s]! < avgs[low]!) low = s;
  }
  final gap = ((need - total) / 5).ceil() * 5;
  final capped = math.min(gap, kSlotGapCapG);
  final tail = gap > kSlotGapCapG
      ? 'closes part of the gap to 90% of your current ${t.protein.round()} g target.'
      : 'gets you to 90% of your current ${t.protein.round()} g target.';
  return '${_cap(low)} is your lowest-protein meal. Adding $capped g there $tail';
}

String _cap(String s) => s[0].toUpperCase() + s.substring(1);

// ── Protein by weekday (U11) ─────────────────────────────────────

const int kWeekdayMinDays = 4;
const double kWeekdayMinGap = 0.30;
const List<String> kWeekdayNames = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

/// Per weekday (Monday 0): protein hits / counted full days with a target.
List<({int counted, int hits})> weekdayProtein(
  List<JudgedDay> days,
  String todayKey,
) {
  final out = List.generate(7, (_) => (counted: 0, hits: 0));
  for (final j in days) {
    if (j.date == todayKey) continue;
    final hit = hitOf(j, HitKind.protein, todayKey, 0);
    if (hit == null) continue;
    final wd = parseDayKey(j.date)!.weekday - 1;
    final o = out[wd];
    out[wd] = (counted: o.counted + 1, hits: o.hits + (hit ? 1 : 0));
  }
  return out;
}

/// "Wed is your strongest protein day (78%); Sat drops to 17%.", or null.
String? weekdayLine(List<({int counted, int hits})> rates) {
  int? best, worst;
  for (var i = 0; i < 7; i++) {
    if (rates[i].counted < kWeekdayMinDays) continue;
    final r = rates[i].hits / rates[i].counted;
    if (best == null || r > rates[best].hits / rates[best].counted) best = i;
    if (worst == null || r < rates[worst].hits / rates[worst].counted) {
      worst = i;
    }
  }
  if (best == null || worst == null || best == worst) return null;
  final b = rates[best].hits / rates[best].counted;
  final w = rates[worst].hits / rates[worst].counted;
  if (b - w < kWeekdayMinGap) return null;
  return '${kWeekdayNames[best]} is your strongest protein day '
      '(${(b * 100).round()}%); ${kWeekdayNames[worst]} drops to '
      '${(w * 100).round()}%.';
}

// ── On-target vs low-protein (U12) ───────────────────────────────

const int kCompareMinDays = 3;

/// Average protein per slot on on-target days and on low-protein days; null
/// unless each side has [kCompareMinDays] days.
({Map<String, double> onTarget, Map<String, double> low, int nOn, int nLow})?
onTargetVsLowProtein(List<JudgedDay> days) {
  final on = [
    for (final j in days)
      if (j.status == DayStatus.onTarget) j.day,
  ];
  final low = [
    for (final j in days)
      if (j.status == DayStatus.lowProtein) j.day,
  ];
  if (on.length < kCompareMinDays || low.length < kCompareMinDays) return null;
  Map<String, double> avg(List<NutritionDay> ds) => {
    for (final s in kMealSlots)
      s: ds.fold(0.0, (a, d) => a + (d.proteinBySlot[s] ?? 0)) / ds.length,
  };
  return (onTarget: avg(on), low: avg(low), nOn: on.length, nLow: low.length);
}

// ── Monthly report (U13, §11, §12) ───────────────────────────────

const int kMonthRows = 6;
const int kMonthArrowMinDays = 3;
const double kMonthArrowMinGapG = 5;
const List<String> kMonthNames = [
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

/// A weigh-in as (IST-ish day key as stored, kg). The day key is the stored
/// date's first ten characters (pre-existing convention); unparseable dates are
/// dropped. Same-day duplicates: the last one wins (input is oldest first).
List<(String, double)> weighIns(Iterable<(String, double)> raw) {
  final byDay = <String, double>{};
  for (final (date, kg) in raw) {
    if (date.length < 10) continue;
    final day = date.substring(0, 10);
    if (parseDayKey(day) == null) continue;
    byDay[day] = kg;
  }
  final keys = byDay.keys.toList()..sort();
  return [for (final k in keys) (k, byDay[k]!)];
}

/// "+1.2 kg", "−0.4 kg", "0.0 kg" (never a signed zero), or "—".
String weightChangeText(double? w) {
  if (w == null) return '—';
  final r = (w * 10).round() / 10;
  if (r == 0) return '0.0 kg';
  return '${r > 0 ? '+' : '−'}${r.abs().toStringAsFixed(1)} kg';
}

class MonthRow {
  /// `yyyy-MM` for a month, `yyyy` for a folded year.
  final String key;
  final String label;
  final bool isYear, soFar;
  final int logged, fullDays;
  final double? avgKcal, avgProtein;

  /// +1 up, -1 down, 0 none (month rows only).
  final int arrow;
  final double? weightChange;

  /// "since Jan", "within May" or null (the previous month).
  final String? weightNote;
  final List<MonthRow> months;

  const MonthRow({
    required this.key,
    required this.label,
    this.isYear = false,
    this.soFar = false,
    this.logged = 0,
    this.fullDays = 0,
    this.avgKcal,
    this.avgProtein,
    this.arrow = 0,
    this.weightChange,
    this.weightNote,
    this.months = const [],
  });

  bool get empty => logged == 0;
}

String _monthLabel(String ym, bool withYear) {
  final m = int.parse(ym.substring(5, 7));
  return withYear
      ? '${kMonthNames[m - 1]} ${ym.substring(0, 4)}'
      : kMonthNames[m - 1];
}

String _prevMonth(String ym) {
  var y = int.parse(ym.substring(0, 4)), m = int.parse(ym.substring(5, 7)) - 1;
  if (m == 0) {
    m = 12;
    y--;
  }
  return '$y-${m.toString().padLeft(2, '0')}';
}

/// The monthly report over ALL [days] (continuous, oldest first) and
/// [weights]: the last [kMonthRows] calendar months ending this month (never
/// before the first day), newest first, then one row per earlier calendar
/// year, newest first, each holding its months newest first.
List<MonthRow> monthlyRows(
  List<JudgedDay> days,
  List<(String, double)> weights,
  String todayKey,
) {
  if (days.isEmpty) return const [];
  final byMonth = <String, List<JudgedDay>>{};
  for (final j in days) {
    (byMonth[j.date.substring(0, 7)] ??= []).add(j);
  }
  final months = byMonth.keys.toList()..sort(); // oldest first, continuous
  final w = weighIns(weights);
  final thisMonth = todayKey.substring(0, 7);

  ({int logged, int full, double? kcal, double? protein}) agg(
    Iterable<JudgedDay> ds,
  ) {
    var logged = 0;
    final kcal = <double>[], protein = <double>[];
    for (final j in ds) {
      if (j.day.logged) logged++;
      if (j.isComplete) {
        kcal.add(j.day.calories);
        protein.add(j.day.protein);
      }
    }
    double? mean(List<double> xs) =>
        xs.isEmpty ? null : xs.reduce((a, b) => a + b) / xs.length;
    return (
      logged: logged,
      full: kcal.length,
      kcal: mean(kcal),
      protein: mean(protein),
    );
  }

  /// Change for the weigh-ins inside [from]..[to] (yyyy-MM, inclusive).
  (double?, String?) weightFor(String from, String to, String label) {
    final inside = [
      for (final e in w)
        if (e.$1.substring(0, 7).compareTo(from) >= 0 &&
            e.$1.substring(0, 7).compareTo(to) <= 0)
          e,
    ];
    if (inside.isEmpty) return (null, null);
    (String, double)? anchor;
    for (final e in w) {
      if (e.$1.substring(0, 7).compareTo(from) < 0) anchor = e;
    }
    if (anchor == null) {
      if (inside.length >= 2) {
        return (inside.last.$2 - inside.first.$2, 'within $label');
      }
      return (null, null);
    }
    final am = anchor.$1.substring(0, 7);
    final note = am == _prevMonth(from)
        ? null
        : 'since ${_monthLabel(am, am.substring(0, 4) != from.substring(0, 4))}';
    return (inside.last.$2 - anchor.$2, note);
  }

  final spanYears = months.first.substring(0, 4) != months.last.substring(0, 4);
  MonthRow monthRow(String ym, {required bool withYear}) {
    final a = agg(byMonth[ym]!);
    final label = _monthLabel(ym, withYear);
    final soFar = ym == thisMonth;
    var arrow = 0;
    final prev = byMonth[_prevMonth(ym)];
    if (!soFar && prev != null) {
      final p = agg(prev);
      if (a.full >= kMonthArrowMinDays &&
          p.full >= kMonthArrowMinDays &&
          (a.protein! - p.protein!).abs() >= kMonthArrowMinGapG) {
        arrow = a.protein! > p.protein! ? 1 : -1;
      }
    }
    final (change, note) = weightFor(ym, ym, label);
    return MonthRow(
      key: ym,
      label: soFar ? '$label (so far)' : label,
      soFar: soFar,
      logged: a.logged,
      fullDays: a.full,
      avgKcal: a.kcal,
      avgProtein: a.protein,
      arrow: arrow,
      weightChange: change,
      weightNote: note,
    );
  }

  final recent = months.length <= kMonthRows
      ? months
      : months.sublist(months.length - kMonthRows);
  final older = months.sublist(0, months.length - recent.length);
  final out = <MonthRow>[
    for (final ym in recent.reversed) monthRow(ym, withYear: spanYears),
  ];
  final years = <String, List<String>>{};
  for (final ym in older) {
    (years[ym.substring(0, 4)] ??= []).add(ym);
  }
  for (final y in (years.keys.toList()..sort()).reversed) {
    final ms = years[y]!;
    final a = agg([for (final m in ms) ...byMonth[m]!]);
    final full = ms.length == 12;
    final label = full
        ? y
        : ms.length == 1
        ? '${_monthLabel(ms.first, false)} $y'
        : '${_monthLabel(ms.first, false)}-${_monthLabel(ms.last, false)} $y';
    final (change, note) = weightFor(ms.first, ms.last, label);
    out.add(
      MonthRow(
        key: y,
        label: label,
        isYear: true,
        logged: a.logged,
        fullDays: a.full,
        avgKcal: a.kcal,
        avgProtein: a.protein,
        weightChange: change,
        weightNote: note,
        months: [for (final m in ms.reversed) monthRow(m, withYear: true)],
      ),
    );
  }
  return out;
}
