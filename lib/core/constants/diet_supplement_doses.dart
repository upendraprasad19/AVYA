// lib/core/constants/diet_supplement_doses.dart
//
// Diet plan Unit 4a (docs/plans/diet-supplements.md section 4): the
// supplement card, the ONE place a dose is written in the app. The doses are
// the coach manual's SECTION 5 bands; the manual's own spelling is pinned by
// supabase/functions/_shared/testdata/supplement_card.json (read by a Deno
// test against the manual and by test/core/diet_supplement_card_test.dart
// against this file), so the app and the coach cannot drift apart.
//
// No brand, no pre-workout product, no dose outside the bands. The strings
// are ASCII only: the PDF uses its default font.
library;

import 'food_types.dart';

/// One row of the supplement card.
class SupplementRow {
  const SupplementRow(this.key, this.name, this.dose, this.note);

  /// The vector's row key (`creatine`, `vitamin_d3`, `b12`, `omega3_algal`,
  /// `omega3_fish`, `multivitamin`).
  final String key;
  final String name;
  final String dose;
  final String note;
}

const SupplementRow kCreatineRow = SupplementRow(
  'creatine',
  'Creatine monohydrate',
  '5 g daily, any time',
  'The best-evidenced one.',
);

const SupplementRow kVitaminD3Row = SupplementRow(
  'vitamin_d3',
  'Vitamin D3',
  '1000-2000 IU a day',
  'Many Indians run low. Get a 25(OH)D serum test before taking a high dose.',
);

const SupplementRow kB12Row = SupplementRow(
  'b12',
  'Vitamin B12',
  '500-1000 mcg a week, under the tongue',
  'Needed on a plant-based diet.',
);

const SupplementRow kOmega3AlgalRow = SupplementRow(
  'omega3_algal',
  'Omega-3 (EPA + DHA)',
  '2-3 g a day',
  'Choose an algal source: it is plant-based.',
);

const SupplementRow kOmega3FishRow = SupplementRow(
  'omega3_fish',
  'Omega-3 (EPA + DHA)',
  '2-3 g a day',
  'Fish oil, or oily fish through the week.',
);

const SupplementRow kMultivitaminRow = SupplementRow(
  'multivitamin',
  'Multivitamin (optional)',
  'One a day, as its label says',
  'Not a substitute for food.',
);

/// The footer lines of the card, in order.
const List<String> kSupplementCardFooter = [
  'Optional: black coffee 30-45 min before training. No pre-workout product is needed.',
  'Talk to your doctor first if you have a heart, kidney or liver condition, or if you are pregnant or breastfeeding.',
  'The plan, the protein and sleep do most of the work.',
];

/// The rows for [type], in display order. B12 and the algal omega-3 are for
/// veg, eggetarian and vegan; non-veg and pescatarian take fish oil.
List<SupplementRow> supplementCardFor(FoodType type) {
  final plantBased = switch (type) {
    FoodType.veg || FoodType.eggetarian || FoodType.vegan => true,
    FoodType.nonVeg || FoodType.pescatarian => false,
  };
  return [
    kCreatineRow,
    kVitaminD3Row,
    if (plantBased) kB12Row,
    plantBased ? kOmega3AlgalRow : kOmega3FishRow,
    kMultivitaminRow,
  ];
}
