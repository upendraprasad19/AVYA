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
import '../../services/nutrition_history_views.dart';
import 'history_common.dart';
import 'history_trend_chart.dart' show YAxisLabels, yAxisWidth;

TextStyle get _value => AppTypography.titleS.copyWith(color: AppColors.textPrimary);
TextStyle get _dim => AppTypography.bodySm.copyWith(color: AppColors.textDim);
TextStyle get _mute => AppTypography.bodySm.copyWith(color: AppColors.textMute);

// ── 1. Journey header ────────────────────────────────────────────

/// The header eyebrow: `SUPPLY LOG · SINCE 1 MAY`, with the year when it is
/// not the current year.
String historySinceLabel(String fromDay, String todayKey) {
  final base = historyDayLabel(fromDay).toUpperCase();
  final year = fromDay.substring(0, 4);
  return year == todayKey.substring(0, 4)
      ? 'SUPPLY LOG · SINCE $base'
      : 'SUPPLY LOG · SINCE $base $year';
}

/// Header over ALL days, never the range chip (plan §11).
class HistoryJourneyHeader extends StatelessWidget {
  const HistoryJourneyHeader({super.key, required this.data});

  final NutritionHistoryData data;

  @override
  Widget build(BuildContext context) {
    final s = journeyStats(data.days);
    final run = loggingRun(data.days, data.todayKey);
    return WardCard(
      variant: WardCardVariant.standard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            historySinceLabel(data.fromDay, data.todayKey),
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
              _Stat('Days logged', '${s.logged}',
                  key: const Key('history_days_logged')),
              if (s.logged30 != null)
                _Stat('Of the last 30 days', '${s.logged30}',
                    key: const Key('history_logged_30')),
              _Stat(
                  'Avg protein, full days, last 30',
                  s.avgProtein30 == null
                      ? '—'
                      : '${s.avgProtein30!.round()} g',
                  key: const Key('history_avg_protein_30')),
            ],
          ),
          const SizedBox(height: 10),
          Text(loggingRunLine(run),
              key: const Key('history_logging_run'), style: _dim),
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
      note: 'Share of calories (%) from protein, carbs and fat.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 90,
                  child: CustomPaint(painter: _SplitPainter(weeks)),
                ),
              ),
              const SizedBox(width: 6),
              const YAxisLabels(
                  labels: ['100', '50', '0'], height: 90, width: 24),
            ],
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
    final grid = Paint()..color = AppColors.border;
    for (final gy in [0.5, size.height / 2, size.height - 0.5]) {
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), grid);
    }
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

// ── 5. Hit-rate and runs ─────────────────────────────────────────

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
    void add(String label, String rule, String runWord, HitStats s,
        Color color, Key key, String? reason) {
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
                Text('${s.hits} of ${s.counted}',
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
              '$rule · ${(s.rate! * 100).round()}% · best run ${s.bestRun} · '
              'current ${s.currentRun} ($runWord)',
              style: _dim,
            ),
            if (reason != null) ...[
              const SizedBox(height: 6),
              Text(reason, key: Key('${(key as ValueKey).value}_reason'),
                  style: AppTypography.bodySm
                      .copyWith(color: AppColors.textPrimary)),
            ],
          ],
        ),
      ));
    }

    add(
        'Calories',
        'full days within 10% of target',
        'full days in a row',
        hitStats(days, HitKind.calories, todayKey),
        metricColor(NutritionMetric.calories),
        const Key('history_hit_calories'),
        hitZeroReason(days, HitKind.calories, todayKey));
    add(
        'Protein',
        'full days at 90% of target or more',
        'full days in a row',
        hitStats(days, HitKind.protein, todayKey),
        metricColor(NutritionMetric.protein),
        const Key('history_hit_protein'),
        hitZeroReason(days, HitKind.protein, todayKey));
    add(
        'Water',
        "days at today's water target",
        'days in a row at your water target',
        hitStats(days, HitKind.water, todayKey, waterTargetMl: waterTargetMl),
        metricColor(NutritionMetric.water),
        const Key('history_hit_water'),
        null);
    if (rows.isEmpty) return const SizedBox.shrink();
    return HistorySection(
      key: const Key('history_hit_rates'),
      title: 'HIT RATE & RUNS',
      note: 'Calories and protein count full days only; days you did not log '
          'are skipped. Today is not counted.',
      child: Column(children: rows),
    );
  }
}

// ── 6. Calories vs weight ────────────────────────────────────────

/// Needs at least two weigh-ins and two days with a 7-day average in range.
/// Two stacked charts on one date axis, each with its own labelled scale.
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
    final kg = <(int, double)>[
      for (final (day, w) in weighIns([for (final e in weights) (e.date, e.weight)]))
        if (day.compareTo(from) >= 0 &&
            day.compareTo(to) <= 0 &&
            index[day] != null)
          (index[day]!, w),
    ];
    if (kcal.length < 2 || kg.length < 2) return const SizedBox.shrink();

    final target = latestTarget(days)?.calories;
    final kb = chartBounds([for (final p in kcal) p.$2],
        target: target, step: 100);
    final wb = chartBounds([for (final p in kg) p.$2], step: 0.5);
    String kgL(double v) => v.toStringAsFixed(1);
    final kLabels = [groupedInt(kb.hi.round()), groupedInt(kb.lo.round())];
    final wLabels = [kgL(wb.hi), kgL(wb.lo)];
    final axis = yAxisWidth(context, [...kLabels, ...wLabels]);

    final firstW = kg.first, lastW = kg.last;
    final spanDays = parseDayKey(days[lastW.$1].date)!
        .difference(parseDayKey(days[firstW.$1].date)!)
        .inDays;
    final between = [
      for (var i = firstW.$1; i <= lastW.$1; i++)
        if (days[i].isComplete) days[i].day.calories,
    ];
    final avgK = between.isEmpty
        ? null
        : between.reduce((a, b) => a + b) / between.length;
    final span = spanDays < 14 ? '$spanDays days' : '${spanDays ~/ 7} weeks';
    final summary = '${kgL(firstW.$2)} kg to ${kgL(lastW.$2)} kg over $span'
        '${avgK == null ? '' : ' while averaging ${groupedInt(avgK.round())} kcal'}.';

    Widget chart(String title, List<String> labels, Widget plot) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: _mute),
            const SizedBox(height: 4),
            Row(children: [
              YAxisLabels(labels: labels, height: 70, width: axis),
              Expanded(child: SizedBox(height: 70, child: plot)),
            ]),
          ],
        );

    return HistorySection(
      key: const Key('history_weight_overlay'),
      title: 'CALORIES VS WEIGHT',
      child: Semantics(
        label: 'Calories, 7-day average, and weight. $summary',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            chart(
                'Calories, 7-day average (kcal)',
                kLabels,
                CustomPaint(
                    painter: _LinePainter(kcal, days.length, kb.lo, kb.hi,
                        metricColor(NutritionMetric.calories),
                        target: target))),
            const SizedBox(height: 10),
            chart(
                'Weight (kg)',
                wLabels,
                CustomPaint(
                    painter: _LinePainter(
                        kg, days.length, wb.lo, wb.hi, AppColors.info,
                        endDot: true))),
            const SizedBox(height: 6),
            Padding(
              padding: EdgeInsets.only(left: axis),
              child: Row(children: [
                Expanded(child: Text(historyDayLabel(from), style: _mute)),
                Expanded(
                    child: Text(historyDayLabel(days[days.length ~/ 2].date),
                        textAlign: TextAlign.center, style: _mute)),
                Expanded(
                    child: Text(historyDayLabel(to),
                        textAlign: TextAlign.right, style: _mute)),
              ]),
            ),
            const SizedBox(height: 8),
            Text(summary,
                key: const Key('history_weight_summary'), style: _dim),
          ],
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.pts, this.n, this.lo, this.hi, this.color,
      {this.target, this.endDot = false});

  final List<(int, double)> pts;
  final int n;
  final double lo, hi;
  final Color color;
  final double? target;
  final bool endDot;

  @override
  void paint(Canvas canvas, Size size) {
    double x(int i) => n <= 1 ? 0.0 : i / (n - 1) * size.width;
    double y(double v) => size.height - (v - lo) / (hi - lo) * size.height;
    final grid = Paint()..color = AppColors.border;
    canvas.drawLine(const Offset(0, 0.5), Offset(size.width, 0.5), grid);
    canvas.drawLine(Offset(0, size.height - 0.5),
        Offset(size.width, size.height - 0.5), grid);
    if (target != null) {
      final ty = y(target!);
      final tp = Paint()
        ..color = AppColors.textDim
        ..strokeWidth = 1;
      for (var dx = 0.0; dx < size.width; dx += 6) {
        canvas.drawLine(Offset(dx, ty), Offset(math.min(dx + 3, size.width), ty), tp);
      }
    }
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final o = Offset(x(pts[i].$1), y(pts[i].$2));
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    if (endDot) {
      canvas.drawCircle(Offset(x(pts.last.$1), y(pts.last.$2)), 3,
          Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.pts != pts || old.lo != lo || old.hi != hi || old.target != target;
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
                      child: Text(
                          f.isFamily && f.kinds >= 2
                              ? '${f.name} · ${f.kinds} kinds'
                              : f.name,
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
      note: 'Counted from the items of your logged meals. Similar foods '
          '(whey, eggs, dal...) are grouped; % = share of the protein in your '
          'itemised meals.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          list('Most logged', foods.mostLogged, (f) => '${f.count}x'),
          if (foods.topProtein.isNotEmpty) ...[
            const SizedBox(height: 8),
            list('Top protein sources', foods.topProtein,
                (f) => '${groupedInt(f.protein.round())} g · '
                    '${(f.proteinShare * 100).round()}%'),
            if (foods.concentration != null) ...[
              const SizedBox(height: 4),
              Text(
                '${foods.concentration!.foods} '
                '${foods.concentration!.foods == 1 ? 'food gives' : 'foods give'} '
                '${(foods.concentration!.share * 100).round()}% of the protein '
                'in your itemised meals.',
                key: const Key('history_food_concentration'),
                style: _dim,
              ),
            ],
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
