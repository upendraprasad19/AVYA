// The smaller sections of the Nutrition History screen (plan
// docs/plans/nutrition-history.md 6.2). Each takes plain data and hides itself
// (SizedBox.shrink) below its own minimum sample, stated on the widget.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart'
    show WeightEntryData;
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

import '../../providers/nutrition_history_provider.dart';
import '../../services/nutrition_history.dart';
import 'history_common.dart';

TextStyle get _value => AppTypography.titleS.copyWith(color: AppColors.textPrimary);
TextStyle get _dim => AppTypography.bodySm.copyWith(color: AppColors.textDim);
TextStyle get _mute => AppTypography.bodySm.copyWith(color: AppColors.textMute);

// ── 1. Journey header ────────────────────────────────────────────

/// Protein eaten in the calendar month of [todayKey] (every logged day).
double proteinThisMonth(List<JudgedDay> days, String todayKey) {
  final month = todayKey.substring(0, 7);
  var sum = 0.0;
  for (final j in days) {
    if (j.date.startsWith(month)) sum += j.day.protein;
  }
  return sum;
}

class HistoryJourneyHeader extends StatelessWidget {
  const HistoryJourneyHeader({super.key, required this.data});

  final NutritionHistoryData data;

  @override
  Widget build(BuildContext context) {
    final protein = proteinThisMonth(data.days, data.todayKey);
    return WardCard(
      variant: WardCardVariant.standard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TRACKING SINCE ${historyDayLabel(data.fromDay).toUpperCase()}',
            key: const Key('history_since'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.mono
                .copyWith(color: AppColors.accent, letterSpacing: 2),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Stat('Day', '${data.days.length}', key: const Key('history_day_n')),
              _Stat('Days logged', '${data.daysLogged}',
                  key: const Key('history_days_logged')),
              _Stat('Protein this month', '${groupedInt(protein.round())} g'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {super.key});
  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: AppTypography.h3.copyWith(color: AppColors.textPrimary)),
          ),
          const SizedBox(height: 2),
          Text(label, style: _mute),
        ],
      ),
    );
  }
}

// ── 4. Macro split over time ─────────────────────────────────────

/// Hidden with no complete week. Shows at most the last 16 weeks of the range.
class HistoryMacroSplit extends StatelessWidget {
  const HistoryMacroSplit({super.key, required this.days});

  final List<JudgedDay> days;

  @override
  Widget build(BuildContext context) {
    var weeks = [
      for (final w in weeklyBuckets(days))
        if (w.proteinShare + w.carbShare + w.fatShare > 0) w,
    ];
    if (weeks.isEmpty) return const SizedBox.shrink();
    if (weeks.length > 16) weeks = weeks.sublist(weeks.length - 16);
    final last = weeks.last;
    String pct(double s) => '${(s * 100).round()}%';
    return HistorySection(
      key: const Key('history_macro_split'),
      title: 'MACRO SPLIT BY WEEK',
      note: 'Share of calories from protein, carbs and fat.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 90,
            width: double.infinity,
            child: CustomPaint(painter: _SplitPainter(weeks)),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('w/c ${historyDayLabel(weeks.first.monday)}',
                  style: AppTypography.monoXs
                      .copyWith(color: AppColors.textMute)),
              const Spacer(),
              Text('w/c ${historyDayLabel(last.monday)}',
                  style: AppTypography.monoXs
                      .copyWith(color: AppColors.textMute)),
            ],
          ),
          const SizedBox(height: 10),
          HistoryLegend([
            (metricColor(NutritionMetric.protein),
                'Protein ${pct(last.proteinShare)}'),
            (metricColor(NutritionMetric.carbs), 'Carbs ${pct(last.carbShare)}'),
            (metricColor(NutritionMetric.fat), 'Fat ${pct(last.fatShare)}'),
          ]),
          const SizedBox(height: 4),
          Text('Latest week, ${last.completeDays} '
              '${last.completeDays == 1 ? 'day' : 'days'}.', style: _mute),
        ],
      ),
    );
  }
}

class _SplitPainter extends CustomPainter {
  _SplitPainter(this.weeks);
  final List<WeekBucket> weeks;

  @override
  void paint(Canvas canvas, Size size) {
    final slot = size.width / weeks.length;
    final w = math.min(28.0, slot * 0.72);
    final paint = Paint();
    for (var i = 0; i < weeks.length; i++) {
      final left = i * slot + (slot - w) / 2;
      var top = 0.0;
      for (final part in [
        (weeks[i].fatShare, metricColor(NutritionMetric.fat)),
        (weeks[i].carbShare, metricColor(NutritionMetric.carbs)),
        (weeks[i].proteinShare, metricColor(NutritionMetric.protein)),
      ]) {
        final h = part.$1 * size.height;
        paint.color = part.$2;
        canvas.drawRect(Rect.fromLTWH(left, top, w, math.max(0, h - 1)), paint);
        top += h;
      }
    }
  }

  @override
  bool shouldRepaint(_SplitPainter old) => old.weeks != weeks;
}

// ── 5. Hit-rate and streaks ──────────────────────────────────────

/// Calories and protein rows need a known target and at least one judged day;
/// the water row at least one day with water. Hidden when no row shows.
class HistoryHitRates extends StatelessWidget {
  const HistoryHitRates({
    super.key,
    required this.days,
    required this.todayKey,
    required this.waterTargetMl,
  });

  final List<JudgedDay> days;
  final String todayKey;
  final int waterTargetMl;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    void add(String label, String rule, HitStats s, Color color, Key key) {
      if (s.counted == 0) return;
      rows.add(Padding(
        key: key,
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: _value)),
                Text('${(s.rate! * 100).round()}%',
                    style: _value.copyWith(color: color)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: s.rate,
                minHeight: 5,
                color: color,
                backgroundColor: AppColors.input,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${s.hits} of ${s.counted} days $rule · best run ${s.bestRun} · '
              'current ${s.currentRun}',
              style: _dim,
            ),
          ],
        ),
      ));
    }

    add('Calories', 'within 10% of target',
        hitStats(days, HitKind.calories, todayKey),
        metricColor(NutritionMetric.calories), const Key('history_hit_calories'));
    add('Protein', 'at 90% of target or more',
        hitStats(days, HitKind.protein, todayKey),
        metricColor(NutritionMetric.protein), const Key('history_hit_protein'));
    add('Water', "at today's water target",
        hitStats(days, HitKind.water, todayKey, waterTargetMl: waterTargetMl),
        metricColor(NutritionMetric.water), const Key('history_hit_water'));
    if (rows.isEmpty) return const SizedBox.shrink();
    return HistorySection(
      key: const Key('history_hit_rates'),
      title: 'HIT RATE & STREAKS',
      note: 'Full days only. Today and half-logged days are not counted.',
      child: Column(children: rows),
    );
  }
}

// ── 6. Calories vs weight ────────────────────────────────────────

/// Needs at least two weigh-ins and two days with a 7-day average in range.
class HistoryWeightOverlay extends StatelessWidget {
  const HistoryWeightOverlay({
    super.key,
    required this.days,
    required this.weights,
    required this.todayKey,
  });

  final List<JudgedDay> days;
  final List<WeightEntryData> weights;
  final String todayKey;

  @override
  Widget build(BuildContext context) {
    if (days.length < 2) return const SizedBox.shrink();
    final from = days.first.date, to = days.last.date;
    final index = {for (var i = 0; i < days.length; i++) days[i].date: i};
    final roll = rollingAverage(days, NutritionMetric.calories, todayKey);
    final kcal = <(int, double)>[
      for (var i = 0; i < roll.length; i++)
        if (roll[i] != null) (i, roll[i]!),
    ];
    final byDay = <String, double>{};
    for (final w in weights) {
      if (w.date.length < 10) continue;
      final day = w.date.substring(0, 10);
      if (day.compareTo(from) < 0 || day.compareTo(to) > 0) continue;
      byDay[day] = w.weight; // the list is oldest first: the last one wins
    }
    final kg = <(int, double)>[
      for (final e in byDay.entries)
        if (index[e.key] != null) (index[e.key]!, e.value),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    if (kcal.length < 2 || kg.length < 2) return const SizedBox.shrink();

    String kgText(double v) => '${v.toStringAsFixed(1)} kg';
    return HistorySection(
      key: const Key('history_weight_overlay'),
      title: 'CALORIES VS WEIGHT',
      note: 'Each line is drawn on its own scale.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 120,
            width: double.infinity,
            child: CustomPaint(painter: _OverlayPainter(kcal, kg, days.length)),
          ),
          const SizedBox(height: 10),
          HistoryLegend([
            (metricColor(NutritionMetric.calories),
                'Calories, 7-day average: ${groupedInt(kcal.first.$2.round())} '
                    'to ${groupedInt(kcal.last.$2.round())} kcal'),
            (AppColors.info,
                'Weight: ${kgText(kg.first.$2)} to ${kgText(kg.last.$2)}'),
          ]),
        ],
      ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter(this.kcal, this.kg, this.n);
  final List<(int, double)> kcal, kg;
  final int n;

  void _line(Canvas canvas, Size size, List<(int, double)> pts, Color color) {
    var lo = pts.first.$2, hi = pts.first.$2;
    for (final p in pts) {
      lo = math.min(lo, p.$2);
      hi = math.max(hi, p.$2);
    }
    final span = hi - lo;
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final x = n <= 1 ? 0.0 : pts[i].$1 / (n - 1) * size.width;
      final t = span == 0 ? 0.5 : (pts[i].$2 - lo) / span;
      final y = size.height - 6 - t * (size.height - 12);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    _line(canvas, size, kcal, metricColor(NutritionMetric.calories));
    _line(canvas, size, kg, AppColors.info);
  }

  @override
  bool shouldRepaint(_OverlayPainter old) =>
      old.kcal != kcal || old.kg != kg || old.n != n;
}

// ── 7. Top foods ─────────────────────────────────────────────────

/// Hidden when no logged meal has item detail.
class HistoryTopFoods extends StatelessWidget {
  const HistoryTopFoods({super.key, required this.foods});

  final TopFoods foods;

  @override
  Widget build(BuildContext context) {
    if (foods.mostLogged.isEmpty) return const SizedBox.shrink();
    Widget list(String title, List<FoodStat> items, String Function(FoodStat) v) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: _mute),
            const SizedBox(height: 6),
            for (final f in items.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(f.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodyM
                              .copyWith(color: AppColors.textPrimary)),
                    ),
                    const SizedBox(width: 8),
                    Text(v(f), style: _dim),
                  ],
                ),
              ),
          ],
        );
    return HistorySection(
      key: const Key('history_top_foods'),
      title: 'TOP FOODS · ALL TIME',
      note: 'Counted from the items of your logged meals.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          list('Most logged', foods.mostLogged, (f) => '${f.count}x'),
          if (foods.topProtein.isNotEmpty) ...[
            const SizedBox(height: 8),
            list('Top protein sources', foods.topProtein,
                (f) => '${groupedInt(f.protein.round())} g'),
          ],
          if (foods.mealsWithoutItems > 0) ...[
            const SizedBox(height: 4),
            Text(
              '${foods.mealsWithoutItems} older '
              '${foods.mealsWithoutItems == 1 ? 'meal has' : 'meals have'} '
              'no item detail and are not counted here.',
              style: _mute,
            ),
          ],
        ],
      ),
    );
  }
}

// ── 8. Patterns ──────────────────────────────────────────────────

/// Each row needs at least [kPatternMinDays] days on BOTH sides; the meal-slot
/// row at least [kPatternMinDays] complete days. Hidden when no row shows.
const int kPatternMinDays = 3;

class HistoryPatterns extends StatelessWidget {
  const HistoryPatterns({
    super.key,
    required this.days,
    required this.trainingDays,
  });

  final List<JudgedDay> days;
  final Set<String> trainingDays;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    void split(String a, String b, SplitAverage s, Key key) {
      if (s.a == null || s.b == null) return;
      if (s.aDays < kPatternMinDays || s.bDays < kPatternMinDays) return;
      final hi = math.max(s.a!, s.b!);
      rows.add(Padding(
        key: key,
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          children: [
            _PatternBar(a, s.a!, s.aDays, hi),
            const SizedBox(height: 6),
            _PatternBar(b, s.b!, s.bDays, hi),
          ],
        ),
      ));
    }

    split('Weekdays', 'Weekends', weekdayWeekend(days),
        const Key('history_pattern_weekend'));
    split('Training days', 'Rest days', trainingVsRest(days, trainingDays),
        const Key('history_pattern_training'));

    final complete = days.where((j) => j.isComplete).length;
    final slots = slotAverages(days);
    if (complete >= kPatternMinDays && slots.isNotEmpty) {
      final hi = slots.values.fold(0.0, math.max);
      const names = {
        'breakfast': 'Breakfast',
        'lunch': 'Lunch',
        'dinner': 'Dinner',
        'snacks': 'Snacks',
      };
      rows.add(Column(
        key: const Key('history_pattern_slots'),
        children: [
          for (final slot in kMealSlots)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _PatternBar(names[slot]!, slots[slot]!, null, hi),
            ),
        ],
      ));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return HistorySection(
      key: const Key('history_patterns'),
      title: 'PATTERNS',
      note: 'Average calories on full days.',
      child: Column(children: rows),
    );
  }
}

class _PatternBar extends StatelessWidget {
  const _PatternBar(this.label, this.value, this.n, this.max);
  final String label;
  final double value, max;
  final int? n;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(n == null ? label : '$label · $n days',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: _dim),
            ),
            Text('${groupedInt(value.round())} kcal',
                style: AppTypography.bodyM
                    .copyWith(color: AppColors.textPrimary)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: max <= 0 ? 0 : (value / max).clamp(0.0, 1.0),
            minHeight: 4,
            color: AppColors.accent,
            backgroundColor: AppColors.input,
          ),
        ),
      ],
    );
  }
}

// ── 9. Insight lines ─────────────────────────────────────────────

/// Hidden with no line.
class HistoryInsights extends StatelessWidget {
  const HistoryInsights({super.key, required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const SizedBox.shrink();
    return HistorySection(
      key: const Key('history_insights'),
      title: 'WHAT YOUR LOGS SHOW',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6, right: 8),
                    child: SizedBox(
                      width: 5,
                      height: 5,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: AppColors.accent, shape: BoxShape.circle),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(line,
                        style: AppTypography.bodyM
                            .copyWith(color: AppColors.textPrimary)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
