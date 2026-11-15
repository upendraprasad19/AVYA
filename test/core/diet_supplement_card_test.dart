// test/core/diet_supplement_card_test.dart
//
// Diet plan Unit 4a (docs/plans/diet-supplements.md section 6): the app's
// supplement card equals the shared vector the coach manual's Deno test also
// reads (supabase/functions/_shared/testdata/supplement_card.json), so the
// card in the app and SECTION 5 of the manual cannot drift apart.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/diet_supplement_doses.dart';
import 'package:icanbefitter/core/constants/food_types.dart';

Map<String, dynamic> _vector() => jsonDecode(File(
        'supabase/functions/_shared/testdata/supplement_card.json')
    .readAsStringSync()) as Map<String, dynamic>;

void main() {
  final v = _vector();
  final cardRows = (v['cardRows'] as Map).cast<String, dynamic>();

  test('every food type has a vector entry and a card', () {
    expect(cardRows.keys.toSet(), {for (final t in FoodType.values) t.storageKey});
  });

  for (final t in FoodType.values) {
    test('the ${t.storageKey} card has the vector\'s rows, in order', () {
      expect([for (final r in supplementCardFor(t)) r.key],
          (cardRows[t.storageKey] as List).cast<String>());
    });
  }

  test('each dose carries its manual token (the manual\'s own spelling)', () {
    final tokens = (v['manualTokens'] as Map).cast<String, String>();
    // The app spells doses for reading; the manual's compact token must
    // reduce to the same numbers. Compare the digits and the unit.
    String digits(String s) =>
        RegExp(r'\d[\d,]*(?:-\d[\d,]*)?').firstMatch(s)!.group(0)!;
    expect(digits(kCreatineRow.dose), digits(tokens['creatine']!));
    expect(digits(kVitaminD3Row.dose), digits(tokens['vitamin_d3']!));
    expect(digits(kB12Row.dose), digits(tokens['b12']!));
    expect(digits(kOmega3AlgalRow.dose), digits(tokens['omega3']!));
    expect(digits(kOmega3FishRow.dose), digits(tokens['omega3']!));
    expect(kVitaminD3Row.dose, contains('IU'));
    expect(kB12Row.dose, contains('mcg'));
    expect(kCreatineRow.dose, contains(' g '));
  });

  test('no brand and no pre-workout product anywhere on the card', () {
    final all = [
      for (final t in FoodType.values)
        for (final r in supplementCardFor(t)) '${r.name} ${r.dose} ${r.note}',
      ...kSupplementCardFooter,
    ].join('\n').toLowerCase();
    for (final banned in [
      'optimum',
      'myprotein',
      'muscleblaze',
      'cellucor',
      'c4 ',
      'bcaa',
      'nitric',
      'fat burner',
    ]) {
      expect(all.contains(banned), isFalse, reason: banned);
    }
    // The coffee line is the only pre-training advice, and says no product.
    expect(
        kSupplementCardFooter.where((l) => l.contains('black coffee')).length, 1);
    expect(kSupplementCardFooter.join(' '), contains('No pre-workout product'));
  });

  test('the card text is ASCII (the PDF uses its default font)', () {
    final all = [
      for (final t in FoodType.values)
        for (final r in supplementCardFor(t)) '${r.name}${r.dose}${r.note}',
      ...kSupplementCardFooter,
    ].join();
    expect(all.runes.every((c) => c < 128), isTrue);
  });
}
