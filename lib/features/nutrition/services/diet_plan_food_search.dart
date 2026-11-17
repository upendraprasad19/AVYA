// lib/features/nutrition/services/diet_plan_food_search.dart
//
// Diet chart v3 (2026-11-17, docs/plans/diet-chart-v3.md §4.3): the swap
// sheet's "Search any food". Pure: the caller hands in the rows. A pick is the
// USER's choice, so family caps and the carb cap do not filter here (the
// strategy shift and the totals row show the effect).
//
// Rules, in order:
//   * the foodBox copy of a custom food is skipped (`is_custom`); the customBox
//     copy is the one returned, tagged `yours`, never diet-filtered, newest
//     `created_at` winning when two rows share an id;
//   * a row with `meal_fit == []` is never returned (the editorial "never
//     generated" rows, alcohol);
//   * category `supplements` is returned ONLY as a protein powder (kcal and
//     protein bounds, not UPF) and only when powders are allowed (an adult,
//     Supplements kill switch on); the two generated-shake ids are excluded;
//   * a user who is not an adult never gets whey / gainer / pre-workout /
//     protein bar rows;
//   * the diet filter is `passesDiet` with a family inferred for free egg and
//     fish rows, so eggetarian and pescatarian users can find boiled eggs and
//     fish;
//   * a processed row stays, tagged.
import 'package:icanbefitter/features/nutrition/services/diet_plan_catalog.dart';

import 'diet_plan_generator.dart';
import 'diet_plan_shake.dart';

/// One search result.
class DietPlanSearchHit {
  const DietPlanSearchHit({
    required this.row,
    required this.processed,
    required this.yours,
    required this.powder,
  });

  final Map<String, dynamic> row;
  final bool processed;
  final bool yours;
  final bool powder;

  String get id => row['id'] as String? ?? '';
  String get name => row['name'] as String? ?? id;
}

final RegExp _eggWords =
    RegExp(r'\b(?:egg|eggs|omelette|omelet|bhurji|anda)\b');

final RegExp _fishWords = RegExp(
    r'fish|prawn|shrimp|salmon|tuna|\bcod\b|tilapia|scallop|mussel|anchov|'
    r'sea bass|halibut|trout|snapper|mahi|macher|\bcrab|lobster|squid|'
    r'sardine|pomfret|rohu|hilsa|surmai|mackerel|oyster|swordfish');

final RegExp _meatWords = RegExp(
    r'chicken|mutton|lamb|beef|pork|keema|veal|goose|quail|lard|bacon|'
    r'\bham\b|sausage|salami|goat|turkey|pepperoni|kebab|duck');

final RegExp _otherBirdEgg = RegExp(r'\b(?:duck|quail|goose)\s+eggs?\b');

/// The family a FREE row (outside the catalog) counts as for `passesDiet`'s
/// egg and fish exceptions: egg for an egg dish, fish for a fish dish, each
/// only when the name holds no meat word; null otherwise (and when the name
/// holds both egg and fish words).
DietFamily? searchFamilyOf(Map<String, dynamic> row) {
  final id = row['id'] as String?;
  final known = id == null ? null : dietCatalogFamily(id);
  if (known != null) return known;
  final name = (row['name'] as String? ?? '').toLowerCase();
  final meatCheck = name.replaceAll(_otherBirdEgg, 'egg');
  if (_meatWords.hasMatch(meatCheck)) return null;
  final egg = _eggWords.hasMatch(name);
  final fish = _fishWords.hasMatch(name);
  if (egg && fish) return null;
  if (egg) return DietFamily.egg;
  if (fish) return DietFamily.fish;
  return null;
}

final RegExp _minorHidden = RegExp(
    r'whey|protein (?:shake|smoothie|bar|pudding|powder|wafer|waffle|\()|'
    r'max protein|sneaky protein|gainer|pre-?workout|kodiak');

num _n(Object? v) => v is num ? v : 0;

/// A protein powder: a supplements row with the kcal and protein of a scoop of
/// protein (gainers, pre-workouts, creatine, fish oil and processed bars fall
/// out of the bounds).
bool isProteinPowderRow(Map<String, dynamic> row) =>
    row['category'] == 'supplements' &&
    _n(row['calories_std']) <= 210 &&
    _n(row['protein_std']) >= 14 &&
    row['is_ultra_processed'] != true;

/// Search [foods] (the foodBox rows) and [customFoods] (the customBox rows).
///
/// [adult] is the age test alone (`dietSupplementsEligible` with the switch
/// forced on); [powdersAllowed] is [adult] AND the Supplements kill switch on.
/// [excludeIds] are foods already in the plan (the replaced item is NOT in
/// it).
List<DietPlanSearchHit> searchDietPlanFoods({
  required String query,
  required List<Map<String, dynamic>> foods,
  required List<Map<String, dynamic>> customFoods,
  required String dietPreference,
  required bool adult,
  required bool powdersAllowed,
  Set<String> excludeIds = const {},
  int limit = 40,
}) {
  final tokens = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();

  bool nameMatches(String name) {
    final n = name.toLowerCase();
    return tokens.every(n.contains);
  }

  // Own foods: newest created_at wins per id.
  final ownById = <String, Map<String, dynamic>>{};
  for (final c in customFoods) {
    final id = c['id'] as String?;
    if (id == null) continue;
    final prev = ownById[id];
    if (prev == null ||
        ((c['created_at'] as String?) ?? '')
                .compareTo((prev['created_at'] as String?) ?? '') >
            0) {
      ownById[id] = c;
    }
  }
  final out = <DietPlanSearchHit>[];
  for (final c in ownById.values) {
    final id = c['id'] as String;
    if (excludeIds.contains(id)) continue;
    final name = c['name'] as String? ?? '';
    if (name.isEmpty || !nameMatches(name)) continue;
    out.add(DietPlanSearchHit(
      row: c,
      processed: false,
      yours: true,
      powder: false,
    ));
  }

  final ranked = <({int rank, DietPlanSearchHit hit})>[];
  for (final r in foods) {
    if (r['is_custom'] == true) continue; // the customBox copy is returned
    final id = r['id'] as String?;
    if (id == null || excludeIds.contains(id) || ownById.containsKey(id)) {
      continue;
    }
    final name = r['name'] as String? ?? '';
    if (name.isEmpty) continue;
    final fit = r['meal_fit'];
    if (fit is List && fit.isEmpty) continue; // editorial: never offered
    var powder = false;
    if (r['category'] == 'supplements') {
      if (!powdersAllowed || !isProteinPowderRow(r)) continue;
      if (isSupplementShake(id)) continue; // would read as the generated shake
      powder = true;
    } else if (!adult && _minorHidden.hasMatch(name.toLowerCase())) {
      continue;
    }
    if (tokens.isNotEmpty && !nameMatches(name)) continue;
    if (tokens.isEmpty && !powder) continue; // an empty query lists only powders
    if (!DietPlanGenerator.passesDiet(r, dietPreference,
        family: searchFamilyOf(r))) {
      continue;
    }
    final lower = name.toLowerCase();
    final first = tokens.isEmpty ? '' : tokens.first;
    final rank = tokens.isEmpty
        ? 0
        : lower.startsWith(first)
            ? 0
            : lower.split(RegExp(r'[\s(]+')).any((w) => w.startsWith(first))
                ? 1
                : 2;
    ranked.add((
      rank: rank,
      hit: DietPlanSearchHit(
        row: r,
        processed: r['is_ultra_processed'] == true,
        yours: false,
        powder: powder,
      ),
    ));
  }
  ranked.sort((a, b) {
    final c = a.rank.compareTo(b.rank);
    if (c != 0) return c;
    final l = a.hit.name.length.compareTo(b.hit.name.length);
    return l != 0 ? l : a.hit.id.compareTo(b.hit.id);
  });
  out.addAll(ranked.map((e) => e.hit));
  return out.length > limit ? out.sublist(0, limit) : out;
}
