// lib/features/nutrition/services/curated_diet_plan_generator.dart
//
// Curated, template-based diet plan generator (diet plan Unit 1, 2026-11-14,
// docs/plans/diet-food-quality.md §3.2; closes OI-214, recurrence of d3c7a9).
//
// Why it exists: the legacy anchor-protein generator (diet_plan_generator.dart)
// drew fillers from WHOLE database categories, so plans carried Brie, kimchi,
// Thums Up, jam, three soy rows a day and two staples per meal. This one only
// picks from the hand-curated catalog (diet_plan_catalog.dart) and fills a
// fixed meal template per slot:
//
//   Breakfast         breakfastMain + breakfastProtein   (+ fruit)
//   Mid-Morning Snack fruit                              (+ snack)
//   Lunch             mainProtein + grain + sabzi + side
//   Evening Snack     snack                              (+ fruit)
//   Dinner            mainProtein + grain + sabzi        (+ side)
//
// Algorithm (deterministic for a seed):
//   1. sample a day: per slot and role, a uniform pick among catalog entries
//      that pass the diet preference, are not used yet today, keep their
//      family under its daily cap and share no key-ingredient word with the
//      meal's other items;
//   2. size each slot: try every combination of the entries' allowed portions
//      (an optional item may be 0) and keep the best slot score;
//   3. keep the best of [_samples] sampled days by the day score (calories,
//      protein band, and a fiber floor at 70 % of the profile target);
//   4. if no sample is valid, fall back to the legacy generator.
//
// Runtime reads: the catalog + FoodRepository rows + passesDiet ONLY. It never
// filters on is_ultra_processed / is_everyday, so a device whose v4 food
// re-seed failed (a v3 box) still generates; catalog ids missing from the box
// are skipped.

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/shared/repositories/food_repository.dart';

import 'diet_plan_catalog.dart';
import 'diet_plan_generator.dart';

/// Template of one meal slot.
class CuratedSlotTemplate {
  final String name;
  final String slotKey;
  final double share; // of the daily calorie AND protein target
  final List<DietRole> required;
  final List<DietRole> optional;
  const CuratedSlotTemplate(
    this.name,
    this.slotKey,
    this.share,
    this.required,
    this.optional,
  );

  /// Every role this slot can hold, required first (item order in the plan).
  List<DietRole> get roles => [...required, ...optional];
}

/// The five slots — names, keys and shares identical to the legacy generator
/// (diet_plan_generator.dart `_slotDefs`), so the saved plan and every reader
/// keep working unchanged.
const List<CuratedSlotTemplate> kCuratedSlotTemplates = [
  CuratedSlotTemplate(
    'Breakfast',
    'breakfast',
    0.25,
    [DietRole.breakfastMain, DietRole.breakfastProtein],
    [DietRole.fruit],
  ),
  CuratedSlotTemplate(
    'Mid-Morning Snack',
    'mid_morning',
    0.10,
    [DietRole.fruit],
    [DietRole.snack],
  ),
  CuratedSlotTemplate('Lunch', 'lunch', 0.30, [
    DietRole.mainProtein,
    DietRole.grain,
    DietRole.sabzi,
    DietRole.side,
  ], []),
  CuratedSlotTemplate(
    'Evening Snack',
    'evening',
    0.10,
    [DietRole.snack],
    [DietRole.fruit],
  ),
  CuratedSlotTemplate(
    'Dinner',
    'dinner',
    0.25,
    [DietRole.mainProtein, DietRole.grain, DietRole.sabzi],
    [DietRole.side],
  ),
];

/// Template for a slot key, or null.
CuratedSlotTemplate? curatedTemplateForSlot(String slotKey) {
  for (final t in kCuratedSlotTemplates) {
    if (t.slotKey == slotKey) return t;
  }
  return null;
}

/// The key-ingredient words of a food name (see [dietCoherenceTokens]).
Set<String> coherenceTokensOf(String name) => RegExp(r'[a-z]+')
    .allMatches(name.toLowerCase())
    .map((m) => m.group(0)!)
    .where(dietCoherenceTokens.contains)
    .toSet();

/// A catalog entry joined with its food row.
class CuratedCandidate {
  final CatalogEntry entry;
  final Map<String, dynamic> row;
  final int catalogIndex;
  CuratedCandidate(this.entry, this.row, this.catalogIndex);

  String get id => entry.foodId;
  String get name => row['name'] as String? ?? entry.foodId;
  double get kcal => _num(row['calories_std']);
  double get protein => _num(row['protein_std']);
  double get carbs => _num(row['carbs_std']);
  double get fat => _num(row['fat_std']);
  double get servingG => _num(row['standard_serving_g'], fallback: 100);
  double get fiberPer100 => _num(row['fiber_per_100g']);
  double get fiber => fiberPer100 * servingG / 100;
  String get servingDesc =>
      row['standard_serving_desc'] as String? ?? '1 serving';
  String get category => row['category'] as String? ?? '';
  Set<String> get tokens => coherenceTokensOf(name);

  static double _num(Object? v, {double fallback = 0}) =>
      v is num ? v.toDouble() : fallback;

  /// The plan item for this food at portion [m] in [role].
  DietPlanFoodItem toItem(double m, DietRole role) {
    final g = servingG * m;
    return DietPlanFoodItem(
      foodId: id,
      name: name,
      servingDesc: scaleServingDesc(servingDesc, m),
      servingG: g,
      calories: (kcal * m).round(),
      protein: (protein * m).round(),
      carbs: (carbs * m).round(),
      fat: (fat * m).round(),
      fiber: (fiberPer100 * g / 100).round(),
      category: category,
      isAnchor:
          role == DietRole.breakfastProtein || role == DietRole.mainProtein,
      role: role.name,
    );
  }
}

class _Pick {
  final CuratedCandidate cand;
  final DietRole role;
  final bool optional;
  _Pick(this.cand, this.role, this.optional);
}

class _SizedSlot {
  final CuratedSlotTemplate template;
  final List<_Pick> picks;
  final List<double> mults; // 0 = optional item dropped
  final double kcal;
  final double protein;
  final double fiber;
  _SizedSlot(this.template, this.picks, this.mults, this.kcal, this.protein,
      this.fiber);
}

class CuratedDietPlanGenerator {
  CuratedDietPlanGenerator._(this._repo, this._catalog, this._legacy);

  /// Production singleton (Hive-backed FoodRepository + the real catalog).
  static final CuratedDietPlanGenerator instance = CuratedDietPlanGenerator._(
    FoodRepository.instance,
    kDietPlanCatalog,
    DietPlanGenerator.instance,
  );

  /// Test constructor: inject a repository and, optionally, a catalog.
  factory CuratedDietPlanGenerator.forTest(
    FoodRepository repo, {
    List<CatalogEntry>? catalog,
  }) => CuratedDietPlanGenerator._(
    repo,
    catalog ?? kDietPlanCatalog,
    DietPlanGenerator.forTest(repo),
  );

  final FoodRepository _repo;
  final List<CatalogEntry> _catalog;
  final DietPlanGenerator _legacy;

  static const int _samples = 40;

  /// How many generate() calls fell back to the legacy generator (test seam;
  /// the archetype matrix asserts it stays 0).
  int lastFallbackCount = 0;

  List<DietMealPlan> generate(DietPlanInputs inputs) {
    final rng = Random(inputs.seed ?? DateTime.now().day);
    final pool = _candidates(inputs.dietPreference);

    List<_SizedSlot>? best;
    var bestScore = double.infinity;
    for (var i = 0; i < _samples; i++) {
      final day = _sampleDay(pool, inputs, rng);
      if (day == null) continue;
      final score = _dayScore(day, inputs);
      if (score < bestScore) {
        bestScore = score;
        best = day;
      }
    }
    if (best == null) {
      lastFallbackCount++;
      debugPrint('[CuratedDietPlanGenerator] no valid sample, legacy fallback');
      return _legacy.generate(inputs);
    }
    return best.map((s) => _toPlan(s, inputs)).toList();
  }

  /// Catalog entries whose row exists and passes the diet preference.
  List<CuratedCandidate> _candidates(String dietPreference) {
    final out = <CuratedCandidate>[];
    for (var i = 0; i < _catalog.length; i++) {
      final e = _catalog[i];
      final row = _repo.getById(e.foodId);
      if (row == null || row.isEmpty) continue; // stale box: skip, never throw
      if (!DietPlanGenerator.passesDiet(row, dietPreference,
          family: e.family)) {
        continue;
      }
      out.add(CuratedCandidate(e, row, i));
    }
    return out;
  }

  List<_SizedSlot>? _sampleDay(
    List<CuratedCandidate> pool,
    DietPlanInputs inputs,
    Random rng,
  ) {
    final used = <String>{};
    final familyCount = <DietFamily, int>{};
    final day = <_SizedSlot>[];

    bool fits(CuratedCandidate c, DietRole role, Set<String> mealTokens) {
      if (!c.entry.roles.contains(role)) return false;
      if (used.contains(c.id)) return false;
      final cap = dietFamilyDailyCap[c.entry.family];
      if (cap != null && (familyCount[c.entry.family] ?? 0) >= cap) {
        return false;
      }
      return c.tokens.intersection(mealTokens).isEmpty;
    }

    void take(CuratedCandidate c, Set<String> mealTokens) {
      used.add(c.id);
      familyCount[c.entry.family] = (familyCount[c.entry.family] ?? 0) + 1;
      mealTokens.addAll(c.tokens);
    }

    for (final t in kCuratedSlotTemplates) {
      final picks = <_Pick>[];
      final mealTokens = <String>{};
      for (final role in t.required) {
        final options = pool.where((c) => fits(c, role, mealTokens)).toList();
        if (options.isEmpty) return null; // a required role is exhausted
        final c = options[rng.nextInt(options.length)];
        take(c, mealTokens);
        picks.add(_Pick(c, role, false));
      }
      for (final role in t.optional) {
        final options = pool.where((c) => fits(c, role, mealTokens)).toList();
        if (options.isEmpty) continue;
        final c = options[rng.nextInt(options.length)];
        take(c, mealTokens);
        picks.add(_Pick(c, role, true));
      }
      day.add(_sizeSlot(t, picks, inputs));
    }
    return day;
  }

  _SizedSlot _sizeSlot(
    CuratedSlotTemplate t,
    List<_Pick> picks,
    DietPlanInputs inputs,
  ) {
    // max(1.0, …): a stored daily_calories of 0 reaches here as 0 and every
    // score would be NaN, leaving bestMults null (B-pass finding 1).
    final slotKcal = max(1.0, inputs.calorieTarget * t.share);
    final slotProt = max(1.0, inputs.proteinTarget * t.share);
    final options = [
      for (final p in picks)
        p.optional ? [0.0, ...p.cand.entry.portions] : p.cand.entry.portions,
    ];

    List<double>? bestMults;
    var bestScore = double.infinity;
    var bestK = 0.0, bestP = 0.0;
    final current = List<double>.filled(picks.length, 0);

    void walk(int i, double k, double p) {
      if (i == picks.length) {
        final s =
            3 * (k - slotKcal).abs() / slotKcal +
            max(0.0, slotProt - p) / slotProt +
            0.3 * max(0.0, p - 1.3 * slotProt) / slotProt;
        if (s < bestScore) {
          bestScore = s;
          bestMults = List.of(current);
          bestK = k;
          bestP = p;
        }
        return;
      }
      for (final m in options[i]) {
        current[i] = m;
        walk(i + 1, k + picks[i].cand.kcal * m, p + picks[i].cand.protein * m);
      }
    }

    walk(0, 0, 0);
    var fiber = 0.0;
    for (var i = 0; i < picks.length; i++) {
      fiber += picks[i].cand.fiber * bestMults![i];
    }
    return _SizedSlot(t, picks, bestMults!, bestK, bestP, fiber);
  }

  double _dayScore(List<_SizedSlot> day, DietPlanInputs inputs) {
    final t = max(1, inputs.calorieTarget).toDouble();
    final p = max(1, inputs.proteinTarget).toDouble();
    final k = day.fold(0.0, (a, s) => a + s.kcal);
    final pr = day.fold(0.0, (a, s) => a + s.protein);
    // Fiber: aim at 80 % of the profile target; the tests floor it at 70 %,
    // the floor the legacy generator's Pass 5 enforced (d3c7a9). A meat +
    // white-rice day measured 17 g against 30 g before this term.
    final f = max(1, inputs.fiberTarget).toDouble();
    final fib = day.fold(0.0, (a, s) => a + s.fiber);
    // Calorie band (Unit 2a): beyond +/-8 % of target a day pays a steep
    // extra cost, so protein can never buy a day outside the tests' band
    // (a 1500 kcal pescatarian day measured 1.11 x target without it).
    final kErr = (k - t).abs() / t;
    return 3 * kErr +
        20 * max(0.0, kErr - 0.08) +
        2 * max(0.0, 0.95 * p - pr) / p +
        max(0.0, pr - 1.15 * p) / p +
        3 * max(0.0, 0.8 * f - fib) / f;
  }

  DietMealPlan _toPlan(_SizedSlot s, DietPlanInputs inputs) {
    final items = <DietPlanFoodItem>[];
    for (var i = 0; i < s.picks.length; i++) {
      final m = s.mults[i];
      if (m <= 0) continue;
      items.add(s.picks[i].cand.toItem(m, s.picks[i].role));
    }
    return DietMealPlan(
      name: s.template.name,
      slotKey: s.template.slotKey,
      items: items,
      targetCalories: (inputs.calorieTarget * s.template.share).round(),
      targetProtein: (inputs.proteinTarget * s.template.share).round(),
    );
  }
}

/// The Diet Plan screen's generator seed: stable for a calendar day (the
/// plan you open is the plan you saw this morning) and different for each
/// Regenerate tap that day.
int dietPlanSeed(DateTime now, int regenerations) =>
    DateTime(now.year, now.month, now.day).hashCode + 7919 * regenerations;

// ── Serving descriptions ──────────────────────────────────────────────────

const Map<String, String> _plurals = {
  'cup': 'cups',
  'bowl': 'bowls',
  'glass': 'glasses',
  'plate': 'plates',
  'piece': 'pieces',
  'handful': 'handfuls',
  'roti': 'rotis',
  'chilla': 'chillas',
  'dosa': 'dosas',
  'paratha': 'parathas',
  'uttapam': 'uttapams',
  'appam': 'appams',
  'drumstick': 'drumsticks',
  'egg': 'eggs',
  'slice': 'slices',
  'phulka': 'phulkas',
  'adai': 'adais',
  'thalipeeth': 'thalipeeths',
  'pesarattu': 'pesarattus',
  'puttu': 'puttus',
  'omelette': 'omelettes',
};

/// Units whose scaled count must be a whole number (T7 sweep).
const Set<String> kCountableServingUnits = {
  ..._pluralKeys,
  'idli',
  'idiyappam',
  'dates',
  'figs',
  'almonds',
  'cashews',
  'halves',
  'pieces',
  'eggs',
  'whites',
  'dosas',
};
const Set<String> _pluralKeys = {
  'roti',
  'chilla',
  'dosa',
  'paratha',
  'uttapam',
  'appam',
  'drumstick',
  'egg',
  'slice',
  'phulka',
  'adai',
  'thalipeeth',
  'pesarattu',
  'puttu',
  'omelette',
  'piece',
};

final RegExp _servingRe = RegExp(
  r'^(\d+/\d+|\d+(?:\.\d+)?)( ?)([A-Za-z][A-Za-z ]*?)(?: \((\d+/\d+|\d+(?:\.\d+)?) ([^)]*)\))?$',
);

double _parseQty(String s) {
  if (s.contains('/')) {
    final parts = s.split('/');
    return double.parse(parts[0]) / double.parse(parts[1]);
  }
  return double.parse(s);
}

/// Formats a quantity: whole numbers plainly, quarters as fractions
/// (`1/2`, `3/4`, `1 1/2`), anything else to two decimals.
String formatServingQty(double v) {
  final quarters = v * 4;
  if ((quarters - quarters.round()).abs() > 1e-9) {
    return v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  }
  final q = quarters.round();
  final whole = q ~/ 4;
  final rem = q % 4;
  if (rem == 0) return '$whole';
  final frac = const {1: '1/4', 2: '1/2', 3: '3/4'}[rem]!;
  return whole == 0 ? frac : '$whole $frac';
}

/// True when [desc] parses under the serving grammar (catalog descriptors
/// must; pinned by the T7 sweep).
bool servingDescParses(String desc) => _servingRe.hasMatch(desc);

/// Scales a standard serving description by multiplier [m]:
/// `1 roti`×3 → `3 rotis`, `1/2 cup`×1.5 → `3/4 cup`,
/// `1 cup (2 eggs)`×2 → `2 cups (4 eggs)`, `100g`×1.5 → `150g`.
/// The unit is pluralised only when the original quantity is ≤ 1 (so
/// `3 egg whites`×2 → `6 egg whites`). An unparseable description is
/// returned with a `× m` prefix (never reached by catalog rows — T7).
String scaleServingDesc(String desc, double m) {
  if ((m - 1).abs() < 1e-9) return desc;
  final match = _servingRe.firstMatch(desc);
  if (match == null) return '${formatServingQty(m)} × $desc';
  final qty = _parseQty(match.group(1)!);
  final sep = match.group(2)!;
  var unit = match.group(3)!.trim();
  final newQty = qty * m;
  if (qty <= 1 && newQty > 1) {
    final words = unit.split(' ');
    final last = words.length - 1;
    if (_plurals.containsKey(words[last])) {
      words[last] = _plurals[words[last]]!;
    } else if (_plurals.containsKey(words[0])) {
      words[0] = _plurals[words[0]]!;
    }
    unit = words.join(' ');
  }
  final out = StringBuffer('${formatServingQty(newQty)}$sep$unit');
  if (match.group(4) != null) {
    out.write(
      ' (${formatServingQty(_parseQty(match.group(4)!) * m)} '
      '${match.group(5)})',
    );
  }
  return out.toString();
}
