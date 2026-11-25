// Nutrition History: the since-day-one daily series and everything the
// History screen derives from it (plan docs/plans/nutrition-history.md).
//
// Pure: no Hive, no Riverpod. Day totals use the SAME row predicate as
// `NutritionReadService.totalMacrosForDate`, so a day here always equals the
// day the rest of the app shows. All calendar maths runs on IST date KEYS
// parsed as UTC calendar dates, never on a device-local `DateTime`.

/// `yyyy-MM-dd` -> a UTC calendar date, or null.
DateTime? parseDayKey(String key) {
  if (key.length < 10) return null;
  final y = int.tryParse(key.substring(0, 4));
  final m = int.tryParse(key.substring(5, 7));
  final d = int.tryParse(key.substring(8, 10));
  if (y == null || m == null || d == null) return null;
  return DateTime.utc(y, m, d);
}

String dayKeyOf(DateTime utcDate) {
  String p(int n) => n.toString().padLeft(2, '0');
  return '${utcDate.year}-${p(utcDate.month)}-${p(utcDate.day)}';
}

/// The Monday (as a day key) of the week holding [dayKey].
String mondayOfDayKey(String dayKey) {
  final d = parseDayKey(dayKey)!;
  return dayKeyOf(d.subtract(Duration(days: d.weekday - 1)));
}

/// 0 (Monday) .. 6 (Sunday) when [dateKey] is in the week of [todayKey], else
/// null. Calendar-day difference between two keys (diagnose d7b3f1: a
/// difference taken from a `DateTime` that kept its time of day put every day
/// after Monday one bar early).
int? weekIndexOfDateKey(String dateKey, String todayKey) {
  final date = parseDayKey(dateKey);
  final today = parseDayKey(todayKey);
  if (date == null || today == null) return null;
  final monday = today.subtract(Duration(days: today.weekday - 1));
  final idx = date.difference(monday).inDays;
  if (idx < 0 || idx > 6) return null;
  return idx;
}

// ── Daily series ─────────────────────────────────────────────────

const kMealSlots = <String>['breakfast', 'lunch', 'dinner', 'snacks'];

/// The slot a `meal_type` belongs to: breakfast / lunch / dinner, everything
/// else (incl. `snack` and a missing value) is snacks.
String mealSlotOf(Object? mealType) {
  final s = mealType is String ? mealType.toLowerCase() : '';
  if (s == 'breakfast' || s == 'lunch' || s == 'dinner') return s;
  return 'snacks';
}

class NutritionDay {
  /// IST `yyyy-MM-dd`.
  final String date;

  /// At least one meal row (a counted row with a `meal_type`), or calories.
  final bool logged;
  final double calories, protein, carbs, fat, fiber;

  /// 0 = none logged.
  final int waterMl;

  /// Calories per slot of [kMealSlots]; sums to [calories].
  final Map<String, double> caloriesBySlot;

  const NutritionDay({
    required this.date,
    this.logged = false,
    this.calories = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.fiber = 0,
    this.waterMl = 0,
    this.caloriesBySlot = const {},
  });
}

/// [raw] as a counted row, or null: the same predicate as
/// `totalMacrosForDate` (a Map with a String `date`, not a saved meal). Read
/// its day with [rowDay].
Map<dynamic, dynamic>? countedRow(Object? raw) {
  if (raw is! Map) return null;
  if (raw['is_saved_meal'] == true) return null;
  return raw['date'] is String ? raw : null;
}

String rowDay(Map<dynamic, dynamic> countedRow) => countedRow['date'] as String;

double _n(Object? v) => v is num ? v.toDouble() : 0.0;

class _Acc {
  double cal = 0, pro = 0, carb = 0, fat = 0, fib = 0;
  bool meal = false;
  final slots = <String, double>{};
}

/// The first day with a meal row in [nutritionRows], or null.
String? firstMealDay(Iterable<Object?> nutritionRows) {
  String? first;
  for (final raw in nutritionRows) {
    final row = countedRow(raw);
    if (row == null) continue;
    final day = rowDay(row);
    if (parseDayKey(day) == null) continue;
    if (row['meal_type'] is! String) continue;
    if (first == null || day.compareTo(first) < 0) first = day;
  }
  return first;
}

/// One pass over [nutritionRows]; a continuous list from [fromDay] to [toDay]
/// (IST keys, inclusive). A day with no row has `logged == false` and zeros.
List<NutritionDay> buildNutritionDays(
  Iterable<Object?> nutritionRows,
  Map<String, int> waterByDay, {
  required String fromDay,
  required String toDay,
}) {
  final from = parseDayKey(fromDay);
  final to = parseDayKey(toDay);
  if (from == null || to == null || to.isBefore(from)) return const [];

  final acc = <String, _Acc>{};
  for (final raw in nutritionRows) {
    final row = countedRow(raw);
    if (row == null) continue;
    final day = rowDay(row);
    if (day.compareTo(fromDay) < 0 || day.compareTo(toDay) > 0) continue;
    final a = acc[day] ??= _Acc();
    final kcal = _n(row['total_calories']);
    a.cal += kcal;
    a.pro += _n(row['total_protein']);
    a.carb += _n(row['total_carbs']);
    a.fat += _n(row['total_fat']);
    a.fib += _n(row['total_fiber']);
    if (row['meal_type'] is String) a.meal = true;
    final slot = mealSlotOf(row['meal_type']);
    a.slots[slot] = (a.slots[slot] ?? 0) + kcal;
  }

  final out = <NutritionDay>[];
  for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1))) {
    final key = dayKeyOf(d);
    final a = acc[key];
    final water = waterByDay[key] ?? 0;
    if (a == null) {
      out.add(NutritionDay(date: key, waterMl: water));
      continue;
    }
    out.add(NutritionDay(
      date: key,
      logged: a.meal || a.cal > 0,
      calories: a.cal,
      protein: a.pro,
      carbs: a.carb,
      fat: a.fat,
      fiber: a.fib,
      waterMl: water,
      caloriesBySlot: Map.unmodifiable(a.slots),
    ));
  }
  return out;
}

// ── Day status ───────────────────────────────────────────────────

/// The target in force on a day. [assumed] = the day precedes the first
/// recorded target, so the earliest known one is used.
typedef DayTarget = ({
  double calories,
  double protein,
  double carbs,
  double fat,
  bool assumed,
});

typedef DayTargetOf = DayTarget? Function(String day);

enum DayStatus {
  notLogged,

  /// Today with at least one meal: never judged.
  inProgress,

  /// Logged, but under [kPartialDayShare] of the target: never judged.
  partial,

  /// A complete day with no known target.
  logged,
  onTarget,
  under,
  over;

  /// A full day of eating: the only days averages, hit-rates, runs, patterns
  /// and insights use.
  bool get isComplete =>
      this == logged || this == onTarget || this == under || this == over;
}

const double kPartialDayShare = 0.25;

/// Partial-day floor when no target is known.
const double kPartialDayFloorKcal = 300;
const double kOnTargetCalorieBand = 0.10;
const double kOnTargetProteinShare = 0.90;

/// On target = calories within 10 % of the target AND protein at least 90 %
/// of its target (founder rule 2026-11-25).
DayStatus dayStatusOf(NutritionDay day, DayTarget? target, String todayKey) {
  if (!day.logged) return DayStatus.notLogged;
  if (day.date == todayKey) return DayStatus.inProgress;
  final floor = target == null
      ? kPartialDayFloorKcal
      : target.calories * kPartialDayShare;
  if (day.calories < floor) return DayStatus.partial;
  if (target == null) return DayStatus.logged;
  final band = target.calories * kOnTargetCalorieBand;
  final diff = day.calories - target.calories;
  if (diff > band) return DayStatus.over;
  if (diff < -band) return DayStatus.under;
  if (day.protein >= target.protein * kOnTargetProteinShare) {
    return DayStatus.onTarget;
  }
  return DayStatus.under;
}

/// A day with its target and status.
class JudgedDay {
  final NutritionDay day;
  final DayTarget? target;
  final DayStatus status;
  const JudgedDay(this.day, this.target, this.status);

  String get date => day.date;
  bool get isComplete => status.isComplete;
}

List<JudgedDay> judgeDays(
  List<NutritionDay> days,
  DayTargetOf targetOf,
  String todayKey,
) =>
    [
      for (final d in days)
        () {
          final t = targetOf(d.date);
          return JudgedDay(d, t, dayStatusOf(d, t, todayKey));
        }(),
    ];

// ── Metrics ──────────────────────────────────────────────────────

enum NutritionMetric { calories, protein, carbs, fat, fiber, water }

double metricValue(NutritionDay d, NutritionMetric m) {
  switch (m) {
    case NutritionMetric.calories:
      return d.calories;
    case NutritionMetric.protein:
      return d.protein;
    case NutritionMetric.carbs:
      return d.carbs;
    case NutritionMetric.fat:
      return d.fat;
    case NutritionMetric.fiber:
      return d.fiber;
    case NutritionMetric.water:
      return d.waterMl.toDouble();
  }
}

/// The target of [m] on a day; null for fibre (no target), water (judged
/// against the current water target by the caller) and an unknown target.
double? metricTarget(DayTarget? t, NutritionMetric m) {
  if (t == null) return null;
  switch (m) {
    case NutritionMetric.calories:
      return t.calories;
    case NutritionMetric.protein:
      return t.protein;
    case NutritionMetric.carbs:
      return t.carbs;
    case NutritionMetric.fat:
      return t.fat;
    case NutritionMetric.fiber:
    case NutritionMetric.water:
      return null;
  }
}

/// Whether [j] enters the aggregates of [m]: a complete day for food
/// metrics; for water a past day with any water logged.
bool countsFor(JudgedDay j, NutritionMetric m, String todayKey) {
  if (m == NutritionMetric.water) {
    return j.day.waterMl > 0 && j.date != todayKey;
  }
  return j.isComplete;
}

/// Per day, the average of [m] over the counting days among it and the
/// [window] - 1 days before it; null where no day in the window counts.
List<double?> rollingAverage(
  List<JudgedDay> days,
  NutritionMetric m,
  String todayKey, {
  int window = 7,
}) {
  final out = List<double?>.filled(days.length, null);
  for (var i = 0; i < days.length; i++) {
    var sum = 0.0;
    var n = 0;
    for (var k = i; k >= 0 && k > i - window; k--) {
      if (!countsFor(days[k], m, todayKey)) continue;
      sum += metricValue(days[k].day, m);
      n++;
    }
    if (n > 0) out[i] = sum / n;
  }
  return out;
}

double? _avg(Iterable<double> xs) {
  var sum = 0.0;
  var n = 0;
  for (final x in xs) {
    sum += x;
    n++;
  }
  return n == 0 ? null : sum / n;
}

/// Average of [m] over the counting days of [days], with the sample size.
({double? avg, int n}) averageOf(
  List<JudgedDay> days,
  NutritionMetric m,
  String todayKey,
) {
  final xs = [
    for (final j in days)
      if (countsFor(j, m, todayKey)) metricValue(j.day, m),
  ];
  return (avg: _avg(xs), n: xs.length);
}

// ── Weekly buckets (IST Monday weeks, complete days only) ────────

class WeekBucket {
  final String monday;

  /// Complete days in the week (the sample behind every average here).
  final int completeDays;
  final double avgCalories, avgProtein, avgCarbs, avgFat;

  /// Share of macro calories (protein 4, carbs 4, fat 9 kcal/g); they sum to
  /// 1, or are all 0 when the week has no macro grams.
  final double proteinShare, carbShare, fatShare;

  const WeekBucket({
    required this.monday,
    required this.completeDays,
    required this.avgCalories,
    required this.avgProtein,
    required this.avgCarbs,
    required this.avgFat,
    required this.proteinShare,
    required this.carbShare,
    required this.fatShare,
  });
}

/// One bucket per week that has at least one complete day, oldest first.
List<WeekBucket> weeklyBuckets(List<JudgedDay> days) {
  final byWeek = <String, List<NutritionDay>>{};
  for (final j in days) {
    if (!j.isComplete) continue;
    (byWeek[mondayOfDayKey(j.date)] ??= []).add(j.day);
  }
  final mondays = byWeek.keys.toList()..sort();
  return [
    for (final monday in mondays)
      () {
        final ds = byWeek[monday]!;
        final n = ds.length;
        final p = ds.fold(0.0, (s, d) => s + d.protein) / n;
        final c = ds.fold(0.0, (s, d) => s + d.carbs) / n;
        final f = ds.fold(0.0, (s, d) => s + d.fat) / n;
        final macroKcal = p * 4 + c * 4 + f * 9;
        return WeekBucket(
          monday: monday,
          completeDays: n,
          avgCalories: ds.fold(0.0, (s, d) => s + d.calories) / n,
          avgProtein: p,
          avgCarbs: c,
          avgFat: f,
          proteinShare: macroKcal > 0 ? p * 4 / macroKcal : 0,
          carbShare: macroKcal > 0 ? c * 4 / macroKcal : 0,
          fatShare: macroKcal > 0 ? f * 9 / macroKcal : 0,
        );
      }(),
  ];
}

// ── Hit-rates and runs ───────────────────────────────────────────

enum HitKind { calories, protein, water }

/// Whether [j] is a hit, a miss, or does not count (null) for [kind].
/// Calories: within 10 % of the target. Protein: at least 90 %. Water: at
/// least [waterTargetMl] (the CURRENT water target; the history holds none).
bool? hitOf(JudgedDay j, HitKind kind, String todayKey, int waterTargetMl) {
  switch (kind) {
    case HitKind.calories:
      final t = j.target;
      if (!j.isComplete || t == null) return null;
      return (j.day.calories - t.calories).abs() <=
          t.calories * kOnTargetCalorieBand;
    case HitKind.protein:
      final t = j.target;
      if (!j.isComplete || t == null) return null;
      return j.day.protein >= t.protein * kOnTargetProteinShare;
    case HitKind.water:
      if (j.date == todayKey || j.day.waterMl <= 0 || waterTargetMl <= 0) {
        return null;
      }
      return j.day.waterMl >= waterTargetMl;
  }
}

class HitStats {
  /// Days that counted, and how many of them hit.
  final int counted, hits;

  /// Longest run of consecutive calendar days that hit.
  final int bestRun;

  /// The run ending on the last past day (today never breaks it).
  final int currentRun;

  const HitStats({
    this.counted = 0,
    this.hits = 0,
    this.bestRun = 0,
    this.currentRun = 0,
  });

  double? get rate => counted == 0 ? null : hits / counted;
}

/// [days] must be continuous and oldest first (as [buildNutritionDays]
/// returns them). A day that does not count breaks a run, except today.
HitStats hitStats(
  List<JudgedDay> days,
  HitKind kind,
  String todayKey, {
  int waterTargetMl = 0,
}) {
  var counted = 0, hits = 0, best = 0, run = 0;
  for (final j in days) {
    if (j.date == todayKey) continue; // in progress: neither hit nor break
    final hit = hitOf(j, kind, todayKey, waterTargetMl);
    if (hit != null) {
      counted++;
      if (hit) hits++;
    }
    if (hit == true) {
      run++;
      if (run > best) best = run;
    } else {
      run = 0;
    }
  }
  return HitStats(counted: counted, hits: hits, bestRun: best, currentRun: run);
}

// ── Patterns ─────────────────────────────────────────────────────

bool isWeekendDayKey(String dayKey) {
  final wd = parseDayKey(dayKey)!.weekday;
  return wd == DateTime.saturday || wd == DateTime.sunday;
}

typedef SplitAverage = ({double? a, int aDays, double? b, int bDays});

/// a = weekdays, b = weekend; average calories over complete days.
SplitAverage weekdayWeekend(List<JudgedDay> days) {
  final wk = <double>[], we = <double>[];
  for (final j in days) {
    if (!j.isComplete) continue;
    (isWeekendDayKey(j.date) ? we : wk).add(j.day.calories);
  }
  return (a: _avg(wk), aDays: wk.length, b: _avg(we), bDays: we.length);
}

/// a = training days, b = rest days; average calories over complete days.
SplitAverage trainingVsRest(List<JudgedDay> days, Set<String> trainingDays) {
  final tr = <double>[], rest = <double>[];
  for (final j in days) {
    if (!j.isComplete) continue;
    (trainingDays.contains(j.date) ? tr : rest).add(j.day.calories);
  }
  return (a: _avg(tr), aDays: tr.length, b: _avg(rest), bDays: rest.length);
}

/// Average calories per slot over complete days (every slot of [kMealSlots]
/// present; they sum to the average day). Empty when no day is complete.
Map<String, double> slotAverages(List<JudgedDay> days) {
  final complete = [
    for (final j in days)
      if (j.isComplete) j.day,
  ];
  if (complete.isEmpty) return const {};
  return {
    for (final slot in kMealSlots)
      slot: complete.fold(0.0, (s, d) => s + (d.caloriesBySlot[slot] ?? 0)) /
          complete.length,
  };
}

// ── Top foods ────────────────────────────────────────────────────

class FoodStat {
  /// The most frequent original spelling.
  final String name;
  final int count;

  /// Sums of the logged ITEMS (not day totals).
  final double protein, calories;

  const FoodStat({
    required this.name,
    required this.count,
    required this.protein,
    required this.calories,
  });
}

class TopFoods {
  final List<FoodStat> mostLogged;
  final List<FoodStat> topProtein;

  /// Meal rows in range that carry no item detail (older logs).
  final int mealsWithoutItems;

  const TopFoods({
    this.mostLogged = const [],
    this.topProtein = const [],
    this.mealsWithoutItems = 0,
  });
}

final _trailingParen = RegExp(r'\s*\([^)]*\)\s*$');
final _trailingTimes = RegExp(r'\s+x\s*\d+\s*$');
final _spaces = RegExp(r'\s+');

/// Grouping key of a food name: lower-case, trimmed, inner spaces collapsed,
/// a trailing parenthetical and a trailing ` x<n>` removed. A leading number
/// is kept ("7 up", "5 star").
String foodNameKey(String name) {
  var s = name.toLowerCase().trim();
  s = s.replaceAll(_trailingParen, '');
  s = s.replaceAll(_trailingTimes, '');
  return s.replaceAll(_spaces, ' ').trim();
}

class _FoodAcc {
  int count = 0;
  double protein = 0, calories = 0;
  final spellings = <String, int>{};
}

TopFoods topFoods(
  Iterable<Object?> nutritionRows, {
  required String fromDay,
  required String toDay,
  int limit = 8,
}) {
  final acc = <String, _FoodAcc>{};
  var withoutItems = 0;
  for (final raw in nutritionRows) {
    final row = countedRow(raw);
    if (row == null) continue;
    final day = rowDay(row);
    if (day.compareTo(fromDay) < 0 || day.compareTo(toDay) > 0) continue;
    if (row['meal_type'] is! String) continue;
    final items = row['items'];
    if (items is! List || items.isEmpty) {
      withoutItems++;
      continue;
    }
    for (final it in items) {
      if (it is! Map) continue;
      final name = it['name'];
      if (name is! String) continue;
      final key = foodNameKey(name);
      if (key.isEmpty) continue;
      final a = acc[key] ??= _FoodAcc();
      a.count++;
      a.protein += _n(it['protein']);
      a.calories += _n(it['calories']);
      final shown = name.trim();
      a.spellings[shown] = (a.spellings[shown] ?? 0) + 1;
    }
  }

  // Fold a plural into its singular when both occur ("eggs" -> "egg").
  for (final key in acc.keys.toList()) {
    if (!key.endsWith('s') || key.length < 3) continue;
    final singular = acc[key.substring(0, key.length - 1)];
    if (singular == null) continue;
    final plural = acc.remove(key)!;
    singular.count += plural.count;
    singular.protein += plural.protein;
    singular.calories += plural.calories;
    plural.spellings.forEach(
        (s, n) => singular.spellings[s] = (singular.spellings[s] ?? 0) + n);
  }

  String display(_FoodAcc a) {
    final entries = a.spellings.entries.toList()
      ..sort((x, y) {
        final byCount = y.value.compareTo(x.value);
        return byCount != 0 ? byCount : x.key.compareTo(y.key);
      });
    return entries.first.key;
  }

  final stats = [
    for (final a in acc.values)
      FoodStat(
        name: display(a),
        count: a.count,
        protein: a.protein,
        calories: a.calories,
      ),
  ];
  int byName(FoodStat x, FoodStat y) => x.name.compareTo(y.name);
  final most = [...stats]..sort((x, y) {
      final c = y.count.compareTo(x.count);
      return c != 0 ? c : byName(x, y);
    });
  final protein = [
    for (final s in stats)
      if (s.protein > 0) s,
  ]..sort((x, y) {
      final c = y.protein.compareTo(x.protein);
      return c != 0 ? c : byName(x, y);
    });
  return TopFoods(
    mostLogged: most.take(limit).toList(),
    topProtein: protein.take(limit).toList(),
    mealsWithoutItems: withoutItems,
  );
}

// ── Insight lines (computed on the phone; no AI call) ────────────

const int kInsightMinWeekendDays = 4;
const int kInsightMinWeekdayDays = 8;
const double kInsightMinKcalGap = 150;
const int kInsightMinProteinDays = 14;
const double kInsightMinProteinGap = 10;
const int kInsightMinSplitDays = 5;
const int kInsightMinLoggingGapPoints = 10;
const int kInsightMinProteinRun = 5;
const int kMaxInsights = 4;

/// At most [kMaxInsights] plain sentences. Each appears only above its own
/// minimum sample and minimum effect.
List<String> nutritionInsights(
  List<JudgedDay> days,
  Set<String> trainingDays,
  String todayKey,
) {
  final out = <String>[];
  String kcal(double v) => v.round().toString();

  // 1. Weekend vs weekday calories.
  final ww = weekdayWeekend(days);
  if (ww.a != null &&
      ww.b != null &&
      ww.bDays >= kInsightMinWeekendDays &&
      ww.aDays >= kInsightMinWeekdayDays) {
    final gap = ww.b! - ww.a!;
    if (gap.abs() >= kInsightMinKcalGap) {
      out.add(gap > 0
          ? 'You eat about ${kcal(gap)} kcal more on weekends.'
          : 'You eat about ${kcal(-gap)} kcal less on weekends.');
    }
  }

  // 2. Protein now (last 30 days) vs the first 30 days.
  if (days.length >= 60) {
    List<double> proteinOf(Iterable<JudgedDay> ds) => [
          for (final j in ds)
            if (j.isComplete) j.day.protein,
        ];
    final first = proteinOf(days.take(30));
    final last = proteinOf(days.skip(days.length - 30));
    if (first.length >= kInsightMinProteinDays &&
        last.length >= kInsightMinProteinDays) {
      final gap = _avg(last)! - _avg(first)!;
      if (gap.abs() >= kInsightMinProteinGap) {
        out.add(gap > 0
            ? 'Your protein is up about ${gap.round()} g a day since your first month.'
            : 'Your protein is down about ${(-gap).round()} g a day since your first month.');
      }
    }
  }

  // 3. Training vs rest day calories.
  final tr = trainingVsRest(days, trainingDays);
  if (tr.a != null &&
      tr.b != null &&
      tr.aDays >= kInsightMinSplitDays &&
      tr.bDays >= kInsightMinSplitDays) {
    final gap = tr.a! - tr.b!;
    if (gap.abs() >= kInsightMinKcalGap) {
      out.add(gap > 0
          ? 'You eat about ${kcal(gap)} kcal more on training days.'
          : 'You eat about ${kcal(-gap)} kcal less on training days.');
    }
  }

  // 4. Logging consistency: the last 30 past days vs the 30 before them.
  final past = [
    for (final j in days)
      if (j.date != todayKey) j,
  ];
  if (past.length >= 60) {
    int pct(Iterable<JudgedDay> ds) =>
        (ds.where((j) => j.day.logged).length * 100 / 30).round();
    final recent = pct(past.skip(past.length - 30));
    final before = pct(past.skip(past.length - 60).take(30));
    final gap = recent - before;
    if (gap.abs() >= kInsightMinLoggingGapPoints) {
      out.add(gap > 0
          ? 'You logged $recent% of the last 30 days, up from $before%.'
          : 'You logged $recent% of the last 30 days, down from $before%.');
    }
  }

  // 5. Best protein run.
  final run = hitStats(days, HitKind.protein, todayKey).bestRun;
  if (run >= kInsightMinProteinRun) {
    out.add('Your best protein run is $run days in a row.');
  }

  return out.take(kMaxInsights).toList();
}
