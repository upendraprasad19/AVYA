// lib/features/nutrition/services/diet_serving_label.dart
//
// OI-517 (docs/plans/diet-grams-toggle.md section 3): the pure label function
// behind the Diet chart's Portions / Grams view. DISPLAY ONLY: it reads the
// portion text a plan item already carries (`servingDesc`, scaled by the
// multiplier) and its grams (`servingG`) and returns the text to show. It
// never changes a stored value, a macro or the saved-plan JSON.
//
// Portions view returns the description UNCHANGED (byte-identical to today).
// Grams view returns `"{grams} g ({portion})"`, `ml` for a liquid, with the
// label table of the plan (every shape measured on the 1444-row asset):
//   plain ("1 cup", "2 idli", "1 oz")        -> 158 g (1 cup)
//   leading gram / ml figure ("100g")        -> 100 g
//   trailing gram / ml bracket               -> bracket stripped: 52 g (1 packet)
//   non-gram bracket ("1 cup (2 eggs)")      -> moved inside: 200 g (1 cup, 2 eggs)
//   leading gram + non-gram bracket          -> 13 g (6 biscuits)
//   bare number / unparseable / "N x desc"   -> grams only
// A description whose own unit is ml (leading or bracketed) forces `ml`.
library;

import 'curated_diet_plan_generator.dart' show servingDescParses;

/// The user's choice. Stored as the profile key `diet_serving_view`.
enum DietServingView {
  portions('portions'),
  grams('grams');

  const DietServingView(this.storageKey);
  final String storageKey;

  /// A stored value to a view. Absent or unknown = Portions (every existing
  /// account is unchanged without a write; new users get `grams` written at
  /// the end of onboarding).
  static DietServingView fromStorage(Object? v) =>
      v == 'grams' ? DietServingView.grams : DietServingView.portions;
}

// Mixed fractions too: a scaled "13g (6 biscuits)" reads "6 1/2g (3 biscuits)".
final RegExp _leadingGram = RegExp(
    r'^\s*\d[\d/. ]*?\s*(g|gm|grams?|ml)\b',
    caseSensitive: false);
final RegExp _bareNumber = RegExp(r'^\s*\d+(?:\.\d+)?\s*$');
final RegExp _scaledUnparseable = RegExp(r'^[\d/. ]+ × ');
final RegExp _trailingParen = RegExp(r'\s*\(([^)]*)\)\s*$');
// A bracketed weight, including the mixed fractions `scaleServingDesc` writes
// ("5 1/2 g", "1/2 ml"), so a scaled "1 mini (11 g)" never shows the figure twice.
final RegExp _gramFigure = RegExp(
    r'^\s*\d[\d/. ]*\s*(g|gm|grams?|ml)\s*$',
    caseSensitive: false);
final RegExp _mlFigure = RegExp(r'\d\s*ml\b', caseSensitive: false);

/// The text to show for one serving.
///
/// [desc] is the item's portion text, [grams] its (scaled) grams, [isLiquid]
/// the audited `weight_unit == 'ml'` flag. Falls back to [desc] when the view
/// is Portions or the grams are not a positive number.
String servingLabel(
  String desc,
  double grams,
  DietServingView view, {
  bool isLiquid = false,
}) {
  if (view == DietServingView.portions) return desc;
  if (!grams.isFinite || grams <= 0) return desc;
  final text = desc.trim();
  final unit = (isLiquid || _mlFigure.hasMatch(text)) ? 'ml' : 'g';
  final figure = '${grams.round()} $unit';
  if (text.isEmpty ||
      _bareNumber.hasMatch(text) ||
      _scaledUnparseable.hasMatch(text)) {
    return figure;
  }
  final paren = _trailingParen.firstMatch(text);
  final base = paren == null ? text : text.substring(0, paren.start).trim();
  final inner = paren?.group(1)?.trim();
  final innerIsWeight = inner != null && _gramFigure.hasMatch(inner);
  if (_leadingGram.hasMatch(base)) {
    // "100g", "250 ml", "13g (6 biscuits)".
    return (inner == null || innerIsWeight) ? figure : '$figure ($inner)';
  }
  if (inner != null && !servingDescParses(text) && !innerIsWeight) {
    // An unparseable shape with a non-weight bracket: keep it readable.
    return '$figure ($base, $inner)';
  }
  if (paren != null) {
    if (innerIsWeight) return base.isEmpty ? figure : '$figure ($base)';
    return '$figure ($base, $inner)';
  }
  if (!servingDescParses(text)) return figure;
  return '$figure ($text)';
}
