// Nutrition History v2 sections (plan docs/plans/nutrition-history-v2.md):
// protein by meal, protein by weekday, on-target vs low-protein days and the
// monthly report. Each hides itself below its own minimum sample.

import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart'
    show WeightEntryData;

import '../../services/nutrition_history.dart';
import '../../services/nutrition_history_views.dart';
import 'history_common.dart';

TextStyle get _dim => AppTypography.bodySm.copyWith(color: AppColors.textDim);
TextStyle get _mute => AppTypography.bodySm.copyWith(color: AppColors.textMute);
TextStyle get _body =>
    AppTypography.bodyM.copyWith(color: AppColors.textPrimary);

const Map<String, String> _slotNames = {
  'breakfast': 'Breakfast',
  'lunch': 'Lunch',
  'dinner': 'Dinner',
  'snacks': 'Snacks',
};

Widget _barRow(String label, String value, double fraction, Color color) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: _dim)),
              Text(value, style: _body),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              minHeight: 4,
              color: color,
              backgroundColor: AppColors.input,
            ),
          ),
        ],
      ),
    );

// ── Protein by meal ──────────────────────────────────────────────

class HistoryProteinByMeal extends StatelessWidget {
  const HistoryProteinByMeal({super.key, required this.days});
  final List<JudgedDay> days;

  @override
  Widget build(BuildContext context) {
    final avgs = slotProteinAverages(days);
    if (avgs.isEmpty) return const SizedBox.shrink();
    final hi = avgs.values.fold(0.0, (a, b) => a > b ? a : b);
    final line = slotProteinLine(days);
    final color = metricColor(NutritionMetric.protein);
    return HistorySection(
      key: const Key('history_protein_by_meal'),
      title: 'PROTEIN BY MEAL',
      note: 'Average grams per meal on full days in this range.',
      child: Semantics(
        label:
            'Protein by meal: ${[for (final s in kMealSlots) '${_slotNames[s]} ${avgs[s]!.round()} g'].join(', ')}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final s in kMealSlots)
              _barRow(
                _slotNames[s]!,
                '${avgs[s]!.round()} g',
                hi <= 0 ? 0 : avgs[s]! / hi,
                color,
              ),
            if (line != null) ...[
              const SizedBox(height: 4),
              Text(
                line,
                key: const Key('history_protein_by_meal_line'),
                style: _body,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Protein by weekday ───────────────────────────────────────────

class HistoryWeekdayProtein extends StatelessWidget {
  const HistoryWeekdayProtein({
    super.key,
    required this.days,
    required this.todayKey,
  });
  final List<JudgedDay> days;
  final String todayKey;

  @override
  Widget build(BuildContext context) {
    final rates = weekdayProtein(days, todayKey);
    if (!rates.any((r) => r.counted >= kWeekdayMinDays)) {
      return const SizedBox.shrink();
    }
    final line = weekdayLine(rates);
    final color = metricColor(NutritionMetric.protein);
    String pct(({int counted, int hits}) r) => r.counted >= kWeekdayMinDays
        ? '${(r.hits * 100 / r.counted).round()}%'
        : '—';
    return HistorySection(
      key: const Key('history_weekday_protein'),
      title: 'PROTEIN BY WEEKDAY',
      note:
          'Share of full days at 90% of your protein target. A weekday '
          'shows once it has $kWeekdayMinDays full days.',
      child: Semantics(
        label:
            'Protein hit rate by weekday: ${[for (var i = 0; i < 7; i++) '${kWeekdayNames[i]} ${pct(rates[i])}'].join(', ')}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < 7; i++)
              _barRow(
                kWeekdayNames[i],
                pct(rates[i]),
                rates[i].counted >= kWeekdayMinDays
                    ? rates[i].hits / rates[i].counted
                    : 0,
                color,
              ),
            if (line != null)
              Text(line, key: const Key('history_weekday_line'), style: _body),
          ],
        ),
      ),
    );
  }
}

// ── On-target vs low-protein days ────────────────────────────────

class HistoryOnTargetCompare extends StatelessWidget {
  const HistoryOnTargetCompare({super.key, required this.days});
  final List<JudgedDay> days;

  @override
  Widget build(BuildContext context) {
    final c = onTargetVsLowProtein(days);
    if (c == null) return const SizedBox.shrink();
    Widget cell(String t, {bool head = false, TextAlign? align}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Text(
        t,
        textAlign: align ?? TextAlign.right,
        style: head ? _mute : _body,
      ),
    );
    return HistorySection(
      key: const Key('history_on_target_compare'),
      title: 'ON-TARGET VS LOW-PROTEIN DAYS',
      note: 'Average protein per meal on each kind of full day.',
      child: Table(
        columnWidths: const {0: FlexColumnWidth(1.4)},
        children: [
          TableRow(
            children: [
              cell('', head: true, align: TextAlign.left),
              cell('On target (${c.nOn})', head: true),
              cell('Low protein (${c.nLow})', head: true),
            ],
          ),
          for (final s in kMealSlots)
            TableRow(
              children: [
                cell(_slotNames[s]!, align: TextAlign.left),
                cell('${c.onTarget[s]!.round()} g'),
                cell('${c.low[s]!.round()} g'),
              ],
            ),
        ],
      ),
    );
  }
}

// ── Monthly report ───────────────────────────────────────────────

class HistoryMonthlyReport extends StatefulWidget {
  const HistoryMonthlyReport({
    super.key,
    required this.days,
    required this.weights,
    required this.todayKey,
  });
  final List<JudgedDay> days;
  final List<WeightEntryData> weights;
  final String todayKey;

  @override
  State<HistoryMonthlyReport> createState() => _HistoryMonthlyReportState();
}

class _HistoryMonthlyReportState extends State<HistoryMonthlyReport> {
  final _open = <String>{};

  @override
  Widget build(BuildContext context) {
    final rows = monthlyRows(widget.days, [
      for (final w in widget.weights) (w.date, w.weight),
    ], widget.todayKey);
    if (rows.isEmpty) return const SizedBox.shrink();
    final children = <Widget>[_header()];
    for (final r in rows) {
      children.add(_row(r, indent: false));
      if (r.isYear && _open.contains(r.key)) {
        for (final m in r.months) {
          children.add(_row(m, indent: true));
        }
      }
    }
    return HistorySection(
      key: const Key('history_monthly_report'),
      title: 'MONTHLY REPORT · ALL TIME',
      note:
          'Averages over full days. Weight: change since the last weigh-in '
          'before the month. Tap a year to see its months.',
      child: Column(children: children),
    );
  }

  Widget _header() => Row(
    children: [
      Expanded(flex: 3, child: Text('Month', style: _mute)),
      Expanded(
        flex: 2,
        child: Text('Logged', style: _mute, textAlign: TextAlign.right),
      ),
      Expanded(
        flex: 2,
        child: Text('Avg kcal', style: _mute, textAlign: TextAlign.right),
      ),
      Expanded(
        flex: 3,
        child: Text('Protein', style: _mute, textAlign: TextAlign.right),
      ),
      Expanded(
        flex: 3,
        child: Text('Weight', style: _mute, textAlign: TextAlign.right),
      ),
    ],
  );

  Widget _row(MonthRow r, {required bool indent}) {
    String n(double? v, String unit) =>
        v == null ? '—' : '${groupedInt(v.round())}$unit';
    final arrow = r.arrow > 0
        ? ' ▲'
        : r.arrow < 0
        ? ' ▼'
        : '';
    final w = r.weightChange;
    final wText = w == null
        ? '—'
        : '${w > 0
                  ? '+'
                  : w < 0
                  ? '−'
                  : ''}${w.abs().toStringAsFixed(1)} kg'
              '${r.weightNote == null ? '' : '\n${r.weightNote}'}';
    final label = r.isYear
        ? '${_open.contains(r.key) ? '▾' : '▸'} ${r.label}'
        : '${indent ? '   ' : ''}${r.label}';
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: r.empty && !r.isYear
          ? Row(
              children: [
                Expanded(flex: 3, child: Text(label, style: _body)),
                Expanded(
                  flex: 10,
                  child: Text(
                    'No logs',
                    style: _mute,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: Text(label, style: _body)),
                Expanded(
                  flex: 2,
                  child: Text(
                    '${r.logged}',
                    style: _body,
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    n(r.avgKcal, ''),
                    style: _body,
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    '${n(r.avgProtein, ' g')}$arrow',
                    style: _body,
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(wText, style: _body, textAlign: TextAlign.right),
                ),
              ],
            ),
    );
    if (!r.isYear)
      return KeyedSubtree(key: Key('history_month_${r.key}'), child: row);
    return InkWell(
      key: Key('history_year_${r.key}'),
      onTap: () => setState(
        () => _open.contains(r.key) ? _open.remove(r.key) : _open.add(r.key),
      ),
      child: row,
    );
  }
}
