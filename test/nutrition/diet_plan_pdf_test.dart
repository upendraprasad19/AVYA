// Diet plan Unit 2a: the PDF export document moved out of the screen
// (diet_plan_pdf.dart); this pins that it still builds a PDF.
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
}
