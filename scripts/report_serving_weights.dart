// scripts/report_serving_weights.dart
//
// On-demand, READ-ONLY report for OI-517 (Portions / Grams view). Prints how
// every food_database.json row's serving description is classified for the
// Grams label (docs/plans/diet-grams-toggle.md section 3), which rows are
// liquid candidates (the `weight_unit: "ml"` audit) and which gram figures
// look implausible for their description (FLAGGED to the founder, never
// edited: `standard_serving_g` feeds every macro, plan item and golden).
//
// Named `report_*` on purpose: Gate 33 (`check_gate_scripts_wired.dart`)
// requires every `audit_*` / `validate_*` script to be wired; this is not a
// gate and writes nothing.
//
// Usage: dart run scripts/report_serving_weights.dart [--rows] [path/to/food_database.json]
import 'dart:convert';
import 'dart:io';

/// The serving grammar of `lib/features/nutrition/services/
/// curated_diet_plan_generator.dart` (`_servingRe`), copied verbatim.
final RegExp servingRe = RegExp(
  r'^(\d+/\d+|\d+(?:\.\d+)?)( ?)([A-Za-z][A-Za-z ]*?)(?: \((\d+/\d+|\d+(?:\.\d+)?) ([^)]*)\))?$',
);
final RegExp leadingGram =
    RegExp(r'^\s*(\d+(?:\.\d+)?)\s*(g|gm|grams?|ml|mL)\b', caseSensitive: false);
final RegExp bareNumber = RegExp(r'^\s*\d+(?:\.\d+)?\s*$');
final RegExp trailingParen = RegExp(r'\((\d+(?:\.\d+)?)\s*(g|ml|mL)\)\s*$');
final RegExp anyParen = RegExp(r'\(([^)]*)\)\s*$');

/// Plausible gram ranges for common volume / count units (a FLAG, not a rule).
const Map<String, List<double>> plausible = {
  'cup': [60, 320],
  'bowl': [80, 400],
  'glass': [100, 350],
  'katori': [60, 250],
  'tbsp': [5, 30],
  'tsp': [2, 12],
  'roti': [20, 80],
  'egg': [30, 70],
  'slice': [10, 80],
};

String shape(String desc) {
  if (bareNumber.hasMatch(desc)) return 'bare_number';
  if (leadingGram.hasMatch(desc)) {
    return anyParen.hasMatch(desc) &&
            !trailingParen.hasMatch(desc)
        ? 'leading_gram_nongram_paren'
        : 'leading_gram';
  }
  final p = anyParen.firstMatch(desc);
  if (p != null) {
    return trailingParen.hasMatch(desc)
        ? (servingRe.hasMatch(desc)
            ? 'gram_paren_parses'
            : 'gram_paren_unparsed')
        : 'nongram_paren';
  }
  if (!servingRe.hasMatch(desc)) return 'unparseable';
  if (RegExp(r'\boz\b').hasMatch(desc)) return 'oz';
  return 'plain';
}

bool mlInDesc(String desc) => RegExp(r'\d\s*ml\b', caseSensitive: false).hasMatch(desc);

void main(List<String> args) {
  final showRows = args.contains('--rows');
  final path = args.firstWhere((a) => a.endsWith('.json'),
      orElse: () => 'assets/data/food_database.json');
  final rows = (jsonDecode(File(path).readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final shapes = <String, int>{};
  final liquid = <String>[];
  final flags = <String>[];
  for (final r in rows) {
    final name = r['name'] as String? ?? '';
    final desc = (r['standard_serving_desc'] as String? ?? '').trim();
    final g = (r['standard_serving_g'] as num?)?.toDouble() ?? 0;
    final cat = r['category'] as String? ?? '';
    final s = shape(desc);
    shapes[s] = (shapes[s] ?? 0) + 1;
    final isMl = mlInDesc(desc);
    final liquidish = isMl ||
        (RegExp(r'^\s*\d+(\.\d+)?\s*(glass|cup|bottle|can|mug)\b',
                    caseSensitive: false)
                .hasMatch(desc) &&
            (cat == 'beverages' || cat == 'dairy'));
    if (liquidish) liquid.add('$cat | $name | $desc | ${g.toStringAsFixed(0)} g');
    if (g <= 0 || g > 1500) flags.add('RANGE | $name | $desc | $g');
    final unit = RegExp(r'^[\d/. ]+\s*([A-Za-z]+)').firstMatch(desc)?.group(1);
    final range = unit == null ? null : plausible[unit.toLowerCase()];
    if (range != null) {
      final qty = double.tryParse(
              RegExp(r'^(\d+(?:\.\d+)?)').firstMatch(desc)?.group(1) ?? '') ??
          1;
      final per = g / (qty == 0 ? 1 : qty);
      if (per < range[0] || per > range[1]) {
        flags.add('PLAUSIBILITY | $name | $desc | ${g.toStringAsFixed(0)} g '
            '(${per.toStringAsFixed(0)} g per $unit, expected ${range[0].toInt()}-${range[1].toInt()})');
      }
    }
    if (showRows) stdout.writeln('$s | $cat | $name | $desc | $g');
  }
  stdout.writeln('rows: ${rows.length}');
  for (final e in (shapes.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value)))) {
    stdout.writeln('  ${e.key}: ${e.value}');
  }
  stdout.writeln('\nliquid candidates (${liquid.length}) [category | name | desc | grams]:');
  liquid.forEach(stdout.writeln);
  stdout.writeln('\nflagged gram figures (${flags.length}) [founder decision, never auto-edited]:');
  flags.forEach(stdout.writeln);
}
