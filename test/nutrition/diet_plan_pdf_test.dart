// Diet plan Unit 2a: the PDF export document moved out of the screen
// (diet_plan_pdf.dart); this pins that it still builds a PDF.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/diet_supplement_doses.dart';
import 'package:icanbefitter/core/constants/food_types.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_pdf.dart';

void main() {
  test('buildDietPlanPdf returns a PDF document', () async {
    final bytes = await buildDietPlanPdf(
      meals: [
        (
          name: 'Lunch',
          items: [
            (
              name: 'Moong Dal',
              servingDesc: '1 katori',
              calories: 180,
              protein: 12,
              carbs: 28,
              fat: 2,
            ),
          ],
        ),
      ],
      foodTypeLabel: 'Eggetarian',
      calorieTarget: 2000,
      proteinTarget: 144,
      carbTarget: 200,
      fatTarget: 60,
      fiberTarget: 30,
      now: DateTime(2026, 11, 14),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(500));
  });

  // 3b-1b B-pass seat C finding 2: the builder renders the header through
  // dietPlanPdfHeaderLines WITH the plan note, so the note cannot silently
  // drop out of the PDF while the helper's own tests stay green.
  test('PRESENCE: the builder renders the header lines with the plan note',
      () {
    final src =
        File('lib/features/nutrition/services/diet_plan_pdf.dart').readAsStringSync();
    expect(src, contains('for (final line in dietPlanPdfHeaderLines('));
    final call = src.substring(src.indexOf('for (final line in dietPlanPdfHeaderLines('));
    expect(call.substring(0, call.indexOf(')')), contains('planNote: planNote'));
  });

  // Diet plan Unit 3a (B-pass seat C finding 3): the header names the
  // strategy only when one applies; null keeps the pre-3a line exactly.
  test('sub-header: the strategy is named only when one applies', () {
    expect(
        dietPlanPdfSubheader(date: '14 Nov 2026', foodTypeLabel: 'Non-veg'),
        'Generated on 14 Nov 2026  |  Food type: Non-veg');
    expect(
        dietPlanPdfSubheader(
            date: '14 Nov 2026',
            foodTypeLabel: 'Non-veg',
            strategyLabel: 'Keto'),
        'Generated on 14 Nov 2026  |  Food type: Non-veg  |  Strategy: Keto');
  });

  // Unit 3b round 3 finding 1: the PDF names the strategy the PLAN was built
  // for (3a named the targets'), plus the note when they differ. The
  // behaviour of both helpers is in diet_plan_strategy_screen_test.dart.
  test('PRESENCE: the screen passes the PLAN strategy and the plan note', () {
    final src = File('lib/features/nutrition/screens/diet_plan_screen.dart')
        .readAsStringSync();
    expect(src,
        contains('strategyLabel: dietPlanPdfStrategyLabel(_planStrategy),'));
    expect(src, contains('planNote: _planNote(targets),'));
    // The header tag over the same map the numbers come from.
    expect(
        RegExp(r'withDietStrategyTag\(\s*_foodType\.shortLabel,\s*dietStrategyOfTargets\(targets\)\)')
            .hasMatch(src),
        isTrue);
  });

  // Diet plan Unit 4a: the supplement card in the PDF.
  group('supplement card', () {
    Future<List<int>> build({List<SupplementRow>? supplements, bool omit = false}) {
      const meals = [
        (
          name: 'Lunch',
          items: [
            (
              name: 'Moong Dal',
              servingDesc: '1 katori',
              calories: 180,
              protein: 12,
              carbs: 28,
              fat: 2,
            ),
          ],
        ),
      ];
      return omit
          ? buildDietPlanPdf(
              meals: meals,
              foodTypeLabel: 'Veg',
              calorieTarget: 2000,
              proteinTarget: 144,
              carbTarget: 200,
              fatTarget: 60,
              fiberTarget: 30,
              now: DateTime(2026, 11, 15))
          : buildDietPlanPdf(
              meals: meals,
              foodTypeLabel: 'Veg',
              calorieTarget: 2000,
              proteinTarget: 144,
              carbTarget: 200,
              fatTarget: 60,
              fiberTarget: 30,
              now: DateTime(2026, 11, 15),
              supplements: supplements);
    }

    test('null adds nothing: the document is the one without the parameter',
        () async {
      final without = await build(omit: true);
      final withNull = await build(supplements: null);
      expect(withNull.length, without.length);
    });

    test('a card makes the document larger and still a PDF', () async {
      final without = await build(omit: true);
      final withCard = await build(supplements: supplementCardFor(FoodType.veg));
      expect(String.fromCharCodes(withCard.take(5)), '%PDF-');
      expect(withCard.length, greaterThan(without.length));
    });

    test('PRESENCE: the card is appended only behind a null check', () {
      final src = File('lib/features/nutrition/services/diet_plan_pdf.dart')
          .readAsStringSync();
      expect(src, contains('if (supplements != null)'));
      expect(src, contains('..._supplementCardWidgets('));
    });
  });
}
