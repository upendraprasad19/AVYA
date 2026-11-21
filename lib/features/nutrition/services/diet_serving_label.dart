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
//   bare number / scaled "N x desc"         -> grams only
//   free text ("handful"), a weight with words after it ("1 gram scoop"),
//   a bracket that restates a weight ("1 cup (about 150 g)") -> the text stays
//   in the bracket, the restated weight is dropped, never doubled or nested
// A description whose own unit is ml (leading or bracketed) forces `ml`.
library;

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
// A weight at the start of a description, with the words after it: "100g",
// "250 ml", "1 gram scoop", and the scaled "6 1/2g (3 biscuits)". Spellings
// people type (g, gm, gms, gr, grm, gram, grams, ml). Group 1 = what follows.
final RegExp _leadingGram = RegExp(
  r'^\s*\d[\d/. ]*?\s*(?:g|gms?|gr|grm|grams?|ml)\b\s*(.*)$',
  caseSensitive: false,
);
final RegExp _bareNumber = RegExp(r'^\s*\d+(?:\.\d+)?\s*$');
final RegExp _scaledUnparseable = RegExp(r'^[\d/. ]+ \u00D7 ');
final RegExp _trailingParen = RegExp(r'\s*\(([^)]*)\)\s*$');
// A weight anywhere inside a bracket ("150 g", "200 g, 2 eggs", "about 150 g",
// "5 1/2 g"): that bracket restates the weight and is dropped.
final RegExp _hasWeight = RegExp(
  r'\d\s*(?:g|gms?|gr|grm|grams?|ml)\b',
  caseSensitive: false,
);
final RegExp _mlFigure = RegExp(r'\d\s*ml\b', caseSensitive: false);

/// The text to show for one serving.
///
/// [desc] is the item's portion text, [grams] its (scaled) grams, [isLiquid]
/// the audited `weight_unit == 'ml'` flag. Falls back to [desc] when the view
/// is Portions or the grams would print as less than one (zero, negative, not
/// a number, or a positive value that rounds to 0).
String servingLabel(
  String desc,
  double grams,
  DietServingView view, {
  bool isLiquid = false,
}) {
  if (view == DietServingView.portions) return desc;
  if (!grams.isFinite || grams.round() < 1) return desc;
  final text = desc.trim();
  final unit = (isLiquid || _mlFigure.hasMatch(text)) ? 'ml' : 'g';
  final figure = '${grams.round()} $unit';
  if (text.isEmpty ||
      _bareNumber.hasMatch(text) ||
      _scaledUnparseable.hasMatch(text)) {
    return figure;
  }
  // Peel trailing brackets from the end. A bracket that restates a weight is
  // dropped; any other bracket moves inside the one bracket we write.
  final extras = <String>[];
  var base = text;
  for (
    var m = _trailingParen.firstMatch(base);
    m != null;
    m = _trailingParen.firstMatch(base)
  ) {
    final inner = (m.group(1) ?? '').trim();
    base = base.substring(0, m.start).trim();
    if (inner.isNotEmpty && !_hasWeight.hasMatch(inner))
      extras.insert(0, inner);
  }
  final parts = <String>[];
  final lead = _leadingGram.firstMatch(base);
  if (lead != null) {
    // "100g" shows once; words after the weight ("1 gram scoop") stay.
    final rest = (lead.group(1) ?? '').trim();
    if (rest.isNotEmpty) parts.add(rest);
  } else if (base.isNotEmpty) {
    parts.add(base);
  }
  parts.addAll(extras);
  return parts.isEmpty ? figure : '$figure (${parts.join(', ')})';
}
