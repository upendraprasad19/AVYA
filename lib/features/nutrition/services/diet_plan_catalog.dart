// lib/features/nutrition/services/diet_plan_catalog.dart
//
// The curated diet-plan catalog (diet plan Unit 1, 2026-11-14,
// docs/plans/diet-food-quality.md §3.1): the ONLY foods the curated generator
// (curated_diet_plan_generator.dart) and the swap sheet (diet_plan_swap.dart)
// may offer. Every id is a row of assets/data/food_database.json; the catalog
// holds NO nutrition numbers — macros always come from that row.
//
// This file must import NOTHING (not even package:icanbefitter): the asset
// patch script scripts/patch_food_database_v4.dart imports it under
// `dart run`, where package:flutter is unavailable. Pinned by a source test.
//
// Editing rules:
//   * a role decides which meal slot can use the food (it replaces the DB's
//     meal_fit for the curated path);
//   * a family is capped per day (dietFamilyDailyCap), which is how "soy at
//     every meal" is prevented;
//   * portions are multipliers of the row's standard serving; countable
//     servings ("1 roti", "2 idli") must stay whole numbers (T7 sweep);
//   * after adding an id, re-run the asset script so its is_everyday flag
//     mirrors this list (T1 fails otherwise).

/// Which part of a meal a catalog food can play.
enum DietRole {
  breakfastMain,
  breakfastProtein,
  mainProtein,
  grain,
  sabzi,
  side,
  fruit,
  snack,
  /// Unit 3b: a cooking fat or coconut added to a low-carb / keto meal.
  fat,
}

/// Day-level variety groups. Caps live in [dietFamilyDailyCap].
enum DietFamily {
  bfgrain,
  grain,
  chilla,
  egg,
  dairy,
  sprouts,
  paneer,
  plantmilk,
  soy,
  dal,
  chicken,
  fish,
  mutton,
  veg,
  side,
  fruit,
  nut,
  roast,
  dried,
  /// Unit 3b: ghee, butter, coconut, coconut milk.
  fat,
}

/// Unit 3b: Low carb / Keto days lean on paneer, dairy and added fat, so
/// those caps are higher there (every other cap is the Balanced one in
/// [dietFamilyDailyCap]).
const Map<DietFamily, int> dietFamilyLowCarbCapOverride = {
  DietFamily.paneer: 2,
  DietFamily.dairy: 3,
  DietFamily.fat: 4,
  DietFamily.soy: 2,
};

/// Max items of a family in one day. A family absent from this map is
/// uncapped (only per-day id uniqueness applies).
const Map<DietFamily, int> dietFamilyDailyCap = {
  DietFamily.soy: 1,
  DietFamily.paneer: 1,
  DietFamily.egg: 1,
  DietFamily.chicken: 1,
  DietFamily.fish: 1,
  DietFamily.mutton: 1,
  DietFamily.nut: 1,
  DietFamily.chilla: 1,
  DietFamily.roast: 1,
  DietFamily.dried: 1,
  DietFamily.plantmilk: 1,
  DietFamily.sprouts: 1,
  DietFamily.dal: 2,
  DietFamily.dairy: 2,
  DietFamily.fat: 3,
};

/// Key-ingredient words: no two items in one meal may share one
/// (palak paneer + aloo palak, matar paneer + aloo matar, two egg dishes…).
const Set<String> dietCoherenceTokens = {
  'palak',
  'matar',
  'sambar',
  'methi',
  'baingan',
  'mushroom',
  'chana',
  'moong',
  'rajma',
  'paneer',
  'egg',
  'anda',
  'soy',
  'soya',
  'tofu',
  'curd',
  'dahi',
};

/// One curated food.
class CatalogEntry {
  final String foodId;
  final List<DietRole> roles;
  final DietFamily family;
  final List<double> portions;

  /// Unit 3b: true for a food offered ONLY in Low carb / Keto plans (plain
  /// vegetables, ghee, full-fat paneer...). Balanced plans never see it, so
  /// their candidate pool, and with it every Balanced plan, is unchanged.
  final bool lowCarbOnly;
  const CatalogEntry(this.foodId, this.roles, this.family, this.portions,
      {this.lowCarbOnly = false});
}

/// The catalog. Order matters only as the swap sheet's tie-break.
const List<CatalogEntry> kDietPlanCatalog = [
  CatalogEntry(
    'F0005',
    [DietRole.breakfastMain],
    DietFamily.bfgrain,
    [1.0, 1.5, 2.0],
  ), // Idli
  CatalogEntry(
    'F0149',
    [DietRole.breakfastMain],
    DietFamily.bfgrain,
    [1.0, 1.5, 2.0],
  ), // Set Dosa
  CatalogEntry(
    'F0158',
    [DietRole.breakfastMain],
    DietFamily.bfgrain,
    [1.0, 1.5, 2.0],
  ), // Rava Idli
  CatalogEntry(
    'F0167',
    [DietRole.breakfastMain],
    DietFamily.bfgrain,
    [1.0, 1.5, 2.0],
  ), // Idiyappam
  CatalogEntry(
    'F0009',
    [DietRole.breakfastMain],
    DietFamily.bfgrain,
    [1.0, 1.5, 2.0],
  ), // Oats (Dry)
  CatalogEntry(
    'F0006',
    [DietRole.breakfastMain],
    DietFamily.bfgrain,
    [1.0, 2.0],
  ), // Dosa (Plain)
  CatalogEntry(
    'F0147',
    [DietRole.breakfastMain],
    DietFamily.bfgrain,
    [1.0, 2.0],
  ), // Onion Dosa
  CatalogEntry(
    'F0146',
    [DietRole.breakfastMain],
    DietFamily.bfgrain,
    [1.0, 2.0],
  ), // Masala Dosa
  CatalogEntry(
    'F0152',
    [DietRole.breakfastMain],
    DietFamily.bfgrain,
    [1.0, 2.0],
  ), // Pesarattu
  CatalogEntry(
    'F0153',
    [DietRole.breakfastMain],
    DietFamily.bfgrain,
    [1.0, 2.0],
  ), // Adai
  CatalogEntry(
    'F0154',
    [DietRole.breakfastMain],
    DietFamily.bfgrain,
    [1.0, 2.0],
  ), // Uttapam
  CatalogEntry(
    'F0156',
    [DietRole.breakfastMain],
    DietFamily.bfgrain,
    [1.0, 2.0],
  ), // Tomato Uttapam
  CatalogEntry(
    'F0155',
    [DietRole.breakfastMain],
    DietFamily.bfgrain,
    [1.0, 2.0],
  ), // Onion Uttapam
  CatalogEntry(
    'F0129',
    [DietRole.breakfastMain],
    DietFamily.bfgrain,
    [1.0, 2.0],
  ), // Aloo Paratha
  CatalogEntry(
    'F0130',
    [DietRole.breakfastMain],
    DietFamily.bfgrain,
    [1.0, 2.0],
  ), // Gobi Paratha
  CatalogEntry(
    'F0131',
    [DietRole.breakfastMain],
    DietFamily.bfgrain,
    [1.0, 2.0],
  ), // Mooli Paratha
  CatalogEntry(
    'F0133',
    [DietRole.breakfastMain],
    DietFamily.bfgrain,
    [1.0, 2.0],
  ), // Methi Paratha
  CatalogEntry(
    'F0143',
    [DietRole.breakfastMain],
    DietFamily.bfgrain,
    [1.0, 2.0],
  ), // Thalipeeth
  CatalogEntry(
    'F0166',
    [DietRole.breakfastMain],
    DietFamily.bfgrain,
    [1.0, 2.0],
  ), // Puttu
  CatalogEntry(
    'F0164',
    [DietRole.breakfastMain],
    DietFamily.bfgrain,
    [1.0, 2.0, 3.0],
  ), // Appam (Plain)
  CatalogEntry(
    'F0008',
    [DietRole.breakfastMain],
    DietFamily.bfgrain,
    [0.5, 1.0, 1.5],
  ), // Upma (Rava)
  CatalogEntry(
    'F0168',
    [DietRole.breakfastMain],
    DietFamily.bfgrain,
    [0.5, 1.0, 1.5],
  ), // Upma (Vermicelli)
  CatalogEntry(
    'F0170',
    [DietRole.breakfastMain],
    DietFamily.bfgrain,
    [0.5, 1.0, 1.5],
  ), // Sevai
  CatalogEntry(
    'F1442',
    [DietRole.breakfastMain],
    DietFamily.bfgrain,
    [0.5, 1.0, 1.5],
  ), // Kanda Poha
  CatalogEntry(
    'F1443',
    [DietRole.breakfastMain],
    DietFamily.bfgrain,
    [0.5, 1.0, 1.5],
  ), // Vegetable Dalia
  CatalogEntry(
    'F1444',
    [DietRole.breakfastMain],
    DietFamily.bfgrain,
    [1.0, 1.5, 2.0],
  ), // Khaman Dhokla
  CatalogEntry(
    'F0132',
    [DietRole.breakfastMain],
    DietFamily.paneer,
    [1.0, 2.0],
  ), // Paneer Paratha
  CatalogEntry(
    'F1445',
    [DietRole.breakfastMain],
    DietFamily.chilla,
    [1.0, 2.0, 3.0],
  ), // Besan Chilla
  CatalogEntry(
    'F1446',
    [DietRole.breakfastMain],
    DietFamily.chilla,
    [1.0, 2.0, 3.0],
  ), // Moong Dal Chilla
  CatalogEntry(
    'F0021',
    [DietRole.breakfastProtein, DietRole.snack],
    DietFamily.egg,
    [2.0, 3.0, 4.0],
  ), // Egg (Whole, boiled)
  CatalogEntry(
    'F0344',
    [DietRole.breakfastProtein],
    DietFamily.egg,
    [1.0, 2.0],
  ), // Egg Omelette (Indian)
  CatalogEntry(
    'F0789',
    [DietRole.breakfastProtein],
    DietFamily.egg,
    [1.0, 2.0],
  ), // Egg White Omelette
  CatalogEntry(
    'F0341',
    [DietRole.breakfastProtein],
    DietFamily.egg,
    [1.0, 2.0],
  ), // Egg Bhurji
  CatalogEntry(
    'F0370',
    [DietRole.breakfastProtein],
    DietFamily.egg,
    [1.0, 1.5, 2.0],
  ), // Egg (Scrambled)
  CatalogEntry(
    'F0372',
    [DietRole.breakfastProtein],
    DietFamily.egg,
    [1.0, 1.5, 2.0],
  ), // Egg (Poached)
  CatalogEntry(
    'F0029',
    [DietRole.breakfastProtein, DietRole.side, DietRole.snack],
    DietFamily.dairy,
    [0.5, 1.0, 1.5],
  ), // Curd (Dahi)
  CatalogEntry(
    'F0384',
    [DietRole.breakfastProtein],
    DietFamily.dairy,
    [1.0, 2.0],
  ), // Hung Curd
  CatalogEntry(
    'F0030',
    [DietRole.breakfastProtein],
    DietFamily.dairy,
    [1.0, 1.5],
  ), // Greek Yogurt
  CatalogEntry(
    'F0031',
    [DietRole.breakfastProtein],
    DietFamily.dairy,
    [1.0, 1.5],
  ), // Milk (Toned)
  CatalogEntry(
    'F0017',
    [DietRole.breakfastProtein, DietRole.snack],
    DietFamily.sprouts,
    [1.0, 1.5, 2.0],
  ), // Sprouts (Mixed)
  CatalogEntry(
    'F0229',
    [DietRole.breakfastProtein, DietRole.mainProtein],
    DietFamily.paneer,
    [1.0, 1.5],
  ), // Paneer Bhurji
  CatalogEntry(
    'F0381',
    [DietRole.breakfastProtein],
    DietFamily.plantmilk,
    [1.0, 2.0],
  ), // Soy Milk (Unsweetened)
  CatalogEntry(
    'F1014',
    [DietRole.breakfastProtein, DietRole.mainProtein],
    DietFamily.soy,
    [1.0, 1.5, 2.0],
  ), // Tofu (Firm)
  CatalogEntry(
    'F0011',
    [DietRole.mainProtein],
    DietFamily.dal,
    [0.5, 1.0, 1.5, 2.0],
  ), // Toor Dal (cooked)
  CatalogEntry(
    'F0012',
    [DietRole.mainProtein],
    DietFamily.dal,
    [0.5, 1.0, 1.5, 2.0],
  ), // Moong Dal (cooked)
  CatalogEntry(
    'F0016',
    [DietRole.mainProtein],
    DietFamily.dal,
    [0.5, 1.0, 1.5, 2.0],
  ), // Masoor Dal (cooked)
  CatalogEntry(
    'F0013',
    [DietRole.mainProtein],
    DietFamily.dal,
    [0.5, 1.0, 1.5, 2.0],
  ), // Chana Dal (cooked)
  CatalogEntry(
    'F0171',
    [DietRole.mainProtein],
    DietFamily.dal,
    [0.5, 1.0, 1.5, 2.0],
  ), // Urad Dal (cooked)
  CatalogEntry(
    'F0172',
    [DietRole.mainProtein],
    DietFamily.dal,
    [0.5, 1.0, 1.5, 2.0],
  ), // Black Urad Dal (cooked)
  CatalogEntry(
    'F0173',
    [DietRole.mainProtein],
    DietFamily.dal,
    [0.5, 1.0, 1.5, 2.0],
  ), // Whole Moong Dal (cooked)
  CatalogEntry(
    'F0177',
    [DietRole.mainProtein],
    DietFamily.dal,
    [0.5, 1.0, 1.5, 2.0],
  ), // Black Chana (cooked)
  CatalogEntry(
    'F0179',
    [DietRole.mainProtein],
    DietFamily.dal,
    [0.5, 1.0, 1.5, 2.0],
  ), // Lobia (Black Eyed Peas, cooked)
  CatalogEntry(
    'F0182',
    [DietRole.mainProtein],
    DietFamily.dal,
    [0.5, 1.0, 1.5, 2.0],
  ), // Dal Tadka
  CatalogEntry(
    'F0183',
    [DietRole.mainProtein],
    DietFamily.dal,
    [0.5, 1.0, 1.5, 2.0],
  ), // Dal Fry
  CatalogEntry(
    'F0185',
    [DietRole.mainProtein],
    DietFamily.dal,
    [0.5, 1.0, 1.5, 2.0],
  ), // Chana Masala
  CatalogEntry(
    'F0186',
    [DietRole.mainProtein],
    DietFamily.dal,
    [0.5, 1.0, 1.5, 2.0],
  ), // Rajma Masala
  CatalogEntry(
    'F0226',
    [DietRole.mainProtein],
    DietFamily.paneer,
    [0.5, 1.0, 1.5, 2.0],
  ), // Palak Paneer
  CatalogEntry(
    'F0228',
    [DietRole.mainProtein],
    DietFamily.paneer,
    [0.5, 1.0, 1.5, 2.0],
  ), // Matar Paneer
  CatalogEntry(
    'F0393',
    [DietRole.mainProtein],
    DietFamily.paneer,
    [1.0, 2.0],
  ), // Paneer (Low Fat)
  CatalogEntry(
    'F0373',
    [DietRole.mainProtein],
    DietFamily.soy,
    [0.5, 1.0, 1.5, 2.0],
  ), // Soy Chunks (cooked)
  CatalogEntry(
    'F0018',
    [DietRole.mainProtein],
    DietFamily.soy,
    [0.5, 1.0, 1.5, 2.0],
  ), // Soybean (boiled)
  CatalogEntry(
    'F0019',
    [DietRole.mainProtein],
    DietFamily.chicken,
    [0.5, 1.0, 1.5, 2.0],
  ), // Chicken Breast (grilled)
  CatalogEntry(
    'F0020',
    [DietRole.mainProtein],
    DietFamily.chicken,
    [0.5, 1.0, 1.5, 2.0],
  ), // Chicken Curry
  CatalogEntry(
    'F0026',
    [DietRole.mainProtein],
    DietFamily.chicken,
    [1.0, 2.0],
  ), // Tandoori Chicken
  CatalogEntry(
    'F0303',
    [DietRole.mainProtein],
    DietFamily.chicken,
    [0.5, 1.0, 1.5, 2.0],
  ), // Chicken Tikka
  CatalogEntry(
    'F0349',
    [DietRole.mainProtein],
    DietFamily.chicken,
    [1.0, 2.0],
  ), // Chicken Drumstick (grilled)
  CatalogEntry(
    'F0024',
    [DietRole.mainProtein],
    DietFamily.fish,
    [0.5, 1.0, 1.5, 2.0],
  ), // Fish Curry
  CatalogEntry(
    'F0358',
    [DietRole.mainProtein],
    DietFamily.fish,
    [0.5, 1.0, 1.5, 2.0],
  ), // Rohu (cooked)
  CatalogEntry(
    'F0362',
    [DietRole.mainProtein],
    DietFamily.fish,
    [0.5, 1.0, 1.5, 2.0],
  ), // Surmai (cooked)
  CatalogEntry(
    'F0357',
    [DietRole.mainProtein],
    DietFamily.fish,
    [0.5, 1.0, 1.5, 2.0],
  ), // Pomfret (cooked)
  CatalogEntry(
    'F0367',
    [DietRole.mainProtein],
    DietFamily.fish,
    [0.5, 1.0, 1.5, 2.0],
  ), // Prawn (cooked)
  CatalogEntry(
    'F0327',
    [DietRole.mainProtein],
    DietFamily.fish,
    [1.0, 2.0],
  ), // Fish Tikka
  CatalogEntry(
    'F0025',
    [DietRole.mainProtein],
    DietFamily.mutton,
    [0.5, 1.0, 1.5],
  ), // Mutton Curry
  CatalogEntry(
    'F0354',
    [DietRole.mainProtein],
    DietFamily.mutton,
    [0.5, 1.0, 1.5],
  ), // Lean Mutton (cooked)
  CatalogEntry(
    'F0342',
    [DietRole.mainProtein],
    DietFamily.egg,
    [1.0, 2.0],
  ), // Anda Masala
  CatalogEntry(
    'F0003',
    [DietRole.grain],
    DietFamily.grain,
    [1.0, 2.0, 3.0, 4.0],
  ), // Roti (Whole Wheat)
  CatalogEntry(
    'F0120',
    [DietRole.grain],
    DietFamily.grain,
    [2.0, 3.0, 4.0, 5.0],
  ), // Phulka
  CatalogEntry(
    'F0139',
    [DietRole.grain],
    DietFamily.grain,
    [1.0, 2.0, 3.0],
  ), // Bajra Roti
  CatalogEntry(
    'F0140',
    [DietRole.grain],
    DietFamily.grain,
    [1.0, 2.0, 3.0],
  ), // Jowar Roti
  CatalogEntry(
    'F0141',
    [DietRole.grain],
    DietFamily.grain,
    [1.0, 2.0, 3.0],
  ), // Ragi Roti
  CatalogEntry(
    'F0142',
    [DietRole.grain],
    DietFamily.grain,
    [1.0, 2.0],
  ), // Makki Ki Roti
  CatalogEntry(
    'F0001',
    [DietRole.grain],
    DietFamily.grain,
    [0.5, 1.0, 1.5, 2.0],
  ), // White Rice (cooked)
  CatalogEntry(
    'F0002',
    [DietRole.grain],
    DietFamily.grain,
    [0.5, 1.0, 1.5, 2.0],
  ), // Brown Rice (cooked)
  CatalogEntry(
    'F0094',
    [DietRole.grain],
    DietFamily.grain,
    [0.5, 1.0, 1.5, 2.0],
  ), // Basmati Rice (cooked)
  CatalogEntry(
    'F0099',
    [DietRole.grain],
    DietFamily.grain,
    [0.5, 1.0, 1.5, 2.0],
  ), // Red Rice (cooked)
  CatalogEntry(
    'F0101',
    [DietRole.grain],
    DietFamily.grain,
    [0.5, 1.0, 1.5],
  ), // Jeera Rice
  CatalogEntry(
    'F0039',
    [DietRole.sabzi],
    DietFamily.veg,
    [0.5, 1.0, 1.5],
  ), // Mixed Sabzi
  CatalogEntry(
    'F0206',
    [DietRole.sabzi],
    DietFamily.veg,
    [0.5, 1.0, 1.5],
  ), // Aloo Gobi
  CatalogEntry(
    'F0207',
    [DietRole.sabzi],
    DietFamily.veg,
    [0.5, 1.0, 1.5],
  ), // Aloo Matar
  CatalogEntry(
    'F0208',
    [DietRole.sabzi],
    DietFamily.veg,
    [0.5, 1.0, 1.5],
  ), // Aloo Methi
  CatalogEntry(
    'F0209',
    [DietRole.sabzi],
    DietFamily.veg,
    [0.5, 1.0, 1.5],
  ), // Aloo Palak
  CatalogEntry(
    'F0210',
    [DietRole.sabzi],
    DietFamily.veg,
    [0.5, 1.0, 1.5],
  ), // Aloo Baingan
  CatalogEntry(
    'F0211',
    [DietRole.sabzi],
    DietFamily.veg,
    [0.5, 1.0, 1.5],
  ), // Aloo Jeera
  CatalogEntry(
    'F0213',
    [DietRole.sabzi],
    DietFamily.veg,
    [0.5, 1.0, 1.5],
  ), // Bhindi Masala
  CatalogEntry(
    'F0215',
    [DietRole.sabzi],
    DietFamily.veg,
    [0.5, 1.0, 1.5],
  ), // Karela Sabzi
  CatalogEntry(
    'F0217',
    [DietRole.sabzi],
    DietFamily.veg,
    [0.5, 1.0, 1.5],
  ), // Tinda Sabzi
  CatalogEntry(
    'F0218',
    [DietRole.sabzi],
    DietFamily.veg,
    [0.5, 1.0, 1.5],
  ), // Lauki Sabzi
  CatalogEntry(
    'F0219',
    [DietRole.sabzi],
    DietFamily.veg,
    [0.5, 1.0, 1.5],
  ), // Tori Sabzi
  CatalogEntry(
    'F0220',
    [DietRole.sabzi],
    DietFamily.veg,
    [0.5, 1.0, 1.5],
  ), // Kaddu Sabzi
  CatalogEntry(
    'F0223',
    [DietRole.sabzi],
    DietFamily.veg,
    [0.5, 1.0, 1.5],
  ), // Methi Sabzi
  CatalogEntry(
    'F0237',
    [DietRole.sabzi],
    DietFamily.veg,
    [0.5, 1.0, 1.5],
  ), // Mixed Veg Curry
  CatalogEntry(
    'F0244',
    [DietRole.sabzi],
    DietFamily.veg,
    [0.5, 1.0, 1.5],
  ), // Cabbage Sabzi
  CatalogEntry(
    'F0245',
    [DietRole.sabzi],
    DietFamily.veg,
    [0.5, 1.0, 1.5],
  ), // Carrot Sabzi
  CatalogEntry(
    'F0246',
    [DietRole.sabzi],
    DietFamily.veg,
    [0.5, 1.0, 1.5],
  ), // Beans Poriyal
  CatalogEntry(
    'F0247',
    [DietRole.sabzi],
    DietFamily.veg,
    [0.5, 1.0, 1.5],
  ), // Beetroot Poriyal
  CatalogEntry(
    'F0251',
    [DietRole.sabzi],
    DietFamily.veg,
    [0.5, 1.0, 1.5],
  ), // Thoran
  CatalogEntry(
    'F0249',
    [DietRole.sabzi],
    DietFamily.veg,
    [0.5, 1.0, 1.5],
  ), // Avial
  CatalogEntry(
    'F0250',
    [DietRole.sabzi],
    DietFamily.veg,
    [0.5, 1.0, 1.5],
  ), // Olan
  CatalogEntry(
    'F0041',
    [DietRole.sabzi],
    DietFamily.veg,
    [0.5, 1.0, 1.5],
  ), // Baingan Bharta
  CatalogEntry(
    'F0036',
    [DietRole.sabzi],
    DietFamily.veg,
    [0.5, 1.0, 1.5],
  ), // Palak (Spinach, cooked)
  CatalogEntry(
    'F0038',
    [DietRole.sabzi],
    DietFamily.veg,
    [0.5, 1.0, 1.5],
  ), // Broccoli (steamed)
  CatalogEntry(
    'F0256',
    [DietRole.sabzi],
    DietFamily.veg,
    [0.5, 1.0, 1.5],
  ), // Mushroom Curry
  CatalogEntry(
    'F0224',
    [DietRole.sabzi],
    DietFamily.veg,
    [0.5, 1.0, 1.5],
  ), // Sarson Ka Saag
  CatalogEntry(
    'F0253',
    [DietRole.sabzi],
    DietFamily.veg,
    [0.5, 1.0, 1.5],
  ), // Undhiyu
  CatalogEntry(
    'F0252',
    [DietRole.sabzi],
    DietFamily.veg,
    [0.5, 1.0, 1.5],
  ), // Erissery
  CatalogEntry(
    'F1447',
    [DietRole.side],
    DietFamily.side,
    [0.5, 1.0],
  ), // Vegetable Raita
  CatalogEntry(
    'F1448',
    [DietRole.side],
    DietFamily.side,
    [0.5, 1.0],
  ), // Kachumber Salad
  CatalogEntry('F0042', [DietRole.side], DietFamily.side, [1.0]), // Cucumber
  CatalogEntry(
    'F0033',
    [DietRole.side, DietRole.snack],
    DietFamily.dairy,
    [0.5, 1.0],
  ), // Buttermilk (Chaas)
  CatalogEntry(
    'F0047',
    [DietRole.fruit],
    DietFamily.fruit,
    [1.0, 2.0],
  ), // Apple
  CatalogEntry(
    'F0048',
    [DietRole.fruit],
    DietFamily.fruit,
    [0.5, 1.0, 1.5, 2.0],
  ), // Mango
  CatalogEntry(
    'F0049',
    [DietRole.fruit],
    DietFamily.fruit,
    [0.5, 1.0, 1.5, 2.0],
  ), // Papaya
  CatalogEntry(
    'F0050',
    [DietRole.fruit],
    DietFamily.fruit,
    [0.5, 1.0, 1.5, 2.0],
  ), // Watermelon
  CatalogEntry(
    'F0051',
    [DietRole.fruit],
    DietFamily.fruit,
    [0.5, 1.0, 1.5, 2.0],
  ), // Pomegranate
  CatalogEntry(
    'F0414',
    [DietRole.fruit],
    DietFamily.fruit,
    [0.5, 1.0, 1.5, 2.0],
  ), // Pineapple
  CatalogEntry(
    'F0416',
    [DietRole.fruit],
    DietFamily.fruit,
    [0.5, 1.0, 1.5, 2.0],
  ), // Grapes (Green)
  CatalogEntry('F0418', [DietRole.fruit], DietFamily.fruit, [1.0, 2.0]), // Pear
  CatalogEntry(
    'F0422',
    [DietRole.fruit],
    DietFamily.fruit,
    [0.5, 1.0, 1.5, 2.0],
  ), // Lychee
  CatalogEntry(
    'F0426',
    [DietRole.fruit],
    DietFamily.fruit,
    [0.5, 1.0, 1.5, 2.0],
  ), // Jamun (Black Plum)
  CatalogEntry(
    'F0046',
    [DietRole.fruit],
    DietFamily.fruit,
    [1.0, 2.0],
  ), // Banana
  CatalogEntry(
    'F0052',
    [DietRole.fruit],
    DietFamily.fruit,
    [1.0, 2.0],
  ), // Orange
  CatalogEntry(
    'F0053',
    [DietRole.fruit],
    DietFamily.fruit,
    [1.0, 2.0],
  ), // Chikoo (Sapota)
  CatalogEntry(
    'F0424',
    [DietRole.fruit],
    DietFamily.fruit,
    [1.0, 2.0],
  ), // Guava
  CatalogEntry(
    'F0433',
    [DietRole.fruit],
    DietFamily.fruit,
    [1.0, 2.0],
  ), // Mosambi (Sweet Lime)
  CatalogEntry(
    'F0423',
    [DietRole.fruit],
    DietFamily.fruit,
    [1.0, 2.0],
  ), // Custard Apple (Sitaphal)
  CatalogEntry(
    'F0077',
    [DietRole.snack],
    DietFamily.nut,
    [1.0, 2.0],
  ), // Almonds
  CatalogEntry(
    'F0079',
    [DietRole.snack],
    DietFamily.nut,
    [1.0, 2.0],
  ), // Cashews
  CatalogEntry(
    'F0080',
    [DietRole.snack],
    DietFamily.nut,
    [1.0, 2.0],
  ), // Walnuts
  CatalogEntry(
    'F0078',
    [DietRole.snack],
    DietFamily.nut,
    [1.0],
  ), // Peanuts (Roasted)
  CatalogEntry(
    'F0464',
    [DietRole.snack],
    DietFamily.nut,
    [1.0],
  ), // Pistachio (Roasted)
  CatalogEntry(
    'F0473',
    [DietRole.snack],
    DietFamily.nut,
    [1.0],
  ), // Pumpkin Seeds (Raw)
  CatalogEntry(
    'F0708',
    [DietRole.snack],
    DietFamily.roast,
    [1.0],
  ), // Roasted Chana
  CatalogEntry(
    'F0710',
    [DietRole.snack],
    DietFamily.roast,
    [1.0, 1.5],
  ), // Plain Makhana (Roasted)
  CatalogEntry(
    'F0449',
    [DietRole.snack],
    DietFamily.dried,
    [1.0],
  ), // Dates (Khajoor)
  CatalogEntry(
    'F0451',
    [DietRole.snack],
    DietFamily.dried,
    [1.0],
  ), // Dried Figs (Anjeer)
  CatalogEntry('F0415', [DietRole.fruit], DietFamily.fruit, [1.0, 2.0]), // Kiwi
  CatalogEntry(
    'F0410',
    [DietRole.fruit],
    DietFamily.fruit,
    [1.0, 1.5],
  ), // Strawberry
  CatalogEntry(
    'F0427',
    [DietRole.fruit],
    DietFamily.fruit,
    [0.5, 1.0, 1.5, 2.0],
  ), // Ber (Indian Jujube)
  CatalogEntry(
    'F0032',
    [DietRole.breakfastProtein],
    DietFamily.dairy,
    [1.0, 1.5],
  ), // Milk (Full Cream)
  CatalogEntry(
    'F0151',
    [DietRole.breakfastMain],
    DietFamily.bfgrain,
    [1.0, 2.0],
  ), // Paper Dosa
  CatalogEntry(
    'F0103',
    [DietRole.grain],
    DietFamily.grain,
    [0.5, 1.0, 1.5],
  ), // Lemon Rice
  // ── Unit 3b: Low carb / Keto only (docs/plans/diet-strategy-3b.md) ──
  CatalogEntry('F0402', [DietRole.fat], DietFamily.fat, [1.0, 2.0, 3.0, 4.0, 5.0],
      lowCarbOnly: true), // Ghee (1 tsp)
  CatalogEntry('F0403', [DietRole.fat], DietFamily.fat, [0.5, 1.0, 1.5, 2.0],
      lowCarbOnly: true), // Butter (1 tbsp)
  CatalogEntry('F0483', [DietRole.fat, DietRole.snack], DietFamily.fat,
      [0.5, 1.0, 1.5], lowCarbOnly: true), // Coconut (Fresh, Grated)
  CatalogEntry('F0383', [DietRole.fat], DietFamily.fat, [1.0, 2.0],
      lowCarbOnly: true), // Coconut Milk (1/4 cup)
  CatalogEntry('F0371', [DietRole.breakfastProtein], DietFamily.egg,
      [1.0, 1.5], lowCarbOnly: true), // Egg (Fried), 2 eggs
  CatalogEntry('F0790', [DietRole.breakfastProtein], DietFamily.egg, [1.0],
      lowCarbOnly: true), // Cheese Omelette
  CatalogEntry('F0023',
      [DietRole.breakfastProtein, DietRole.mainProtein, DietRole.snack],
      DietFamily.paneer, [0.5, 1.0, 1.5, 2.0], lowCarbOnly: true), // Paneer
  CatalogEntry('F0398', [DietRole.breakfastProtein, DietRole.snack],
      DietFamily.dairy, [1.0, 2.0], lowCarbOnly: true), // Cheddar Cheese (1 oz)
  CatalogEntry('F0394', [DietRole.mainProtein], DietFamily.paneer,
      [1.0, 1.5, 2.0], lowCarbOnly: true), // Paneer (Full Fat)
  CatalogEntry('F0348', [DietRole.mainProtein], DietFamily.chicken,
      [1.0, 1.5, 2.0], lowCarbOnly: true), // Chicken Thigh (grilled)
  CatalogEntry('F1022', [DietRole.sabzi], DietFamily.veg, [1.0, 1.5, 2.0],
      lowCarbOnly: true), // Cauliflower (cooked)
  CatalogEntry('F1024', [DietRole.sabzi], DietFamily.veg, [0.5, 1.0, 1.5],
      lowCarbOnly: true), // Spinach (cooked)
  CatalogEntry('F0040', [DietRole.sabzi], DietFamily.veg, [0.5, 1.0, 1.5],
      lowCarbOnly: true), // Bhindi (Okra)
  CatalogEntry('F0264', [DietRole.sabzi], DietFamily.veg, [1.0],
      lowCarbOnly: true), // Capsicum (Green)
];

final Map<String, DietFamily> _familyById = {
  for (final e in kDietPlanCatalog) e.foodId: e.family,
};

/// The catalog family of [foodId], or null for a food outside the catalog
/// (diet plan Unit 2a: the egg / fish exception of `passesDiet` needs it to
/// judge a saved plan's items).
DietFamily? dietCatalogFamily(String foodId) => _familyById[foodId];
