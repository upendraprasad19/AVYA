// Diet plan Unit 2a: the PDF export document moved out of the screen
// (diet_plan_pdf.dart); this pins that it still builds a PDF.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

  test('PRESENCE: the screen passes the strategy carried with the targets', () {
    final src = File('lib/features/nutrition/screens/diet_plan_screen.dart')
        .readAsStringSync();
    expect(src, contains('strategyLabel: _pdfStrategyLabel(targets),'));
    expect(src, contains('final s = dietStrategyOfTargets(targets);'));
    expect(src, contains('return s == DietStrategy.balanced ? null : s.label;'));
    // The header tag over the same map the numbers come from.
    expect(
        RegExp(r'withDietStrategyTag\(\s*_foodType\.shortLabel,\s*dietStrategyOfTargets\(targets\)\)')
            .hasMatch(src),
        isTrue);
  });
}
