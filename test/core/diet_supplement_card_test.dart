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
    expect(kOmega3AlgalRow.dose, contains(' g '));
    expect(kOmega3FishRow.dose, contains(' g '));
  });

  test('each dose carries the period of its manual token (B12 is WEEKLY)', () {
    final tokens = (v['manualTokens'] as Map).cast<String, String>();
    // The manual spells the period as a suffix: /wk, /day, or "daily".
    String period(String token) =>
        token.contains('/wk') ? 'week' : 'day'; // daily and /day
    for (final e in {
      'creatine': kCreatineRow,
      'vitamin_d3': kVitaminD3Row,
      'b12': kB12Row,
      'omega3': kOmega3AlgalRow,
    }.entries) {
      final p = period(tokens[e.key]!);
      expect(
          p == 'week'
              ? e.value.dose.contains('week')
              : (e.value.dose.contains('day') || e.value.dose.contains('daily')),
          isTrue,
          reason: '${e.key}: the manual says per $p');
      if (p == 'day') {
        expect(e.value.dose, isNot(contains('week')), reason: e.key);
      }
    }
    expect(kOmega3FishRow.dose, kOmega3AlgalRow.dose,
        reason: 'one omega-3 dose, two sources');
  });

  test('the footer: the doctor line first (it covers the coffee after it), '
      'the founder\'s coffee line, the one-scoop rule', () {
    expect(kSupplementCardFooter.first, startsWith('Talk to your doctor first'));
    expect(kSupplementCardFooter[1],
        'Optional: black coffee 30-45 min before training. '
        'No pre-workout product is needed.');
    expect(kSupplementCardFooter.join(' '), contains('One scoop of protein powder a day in total'));
  });

  test('the table the PDF prints is the rows, then nothing else', () {
    final rows = supplementCardFor(FoodType.veg);
    final data = supplementTableData(rows);
    expect(kSupplementTableHeaders, ['Supplement', 'Dose', 'Note']);
    expect(data.length, rows.length);
    for (var i = 0; i < rows.length; i++) {
      expect(data[i], [rows[i].name, rows[i].dose, rows[i].note]);
    }
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
