// test/contracts/serving_qty_format_test.dart
//
// Diagnose 2d9f4b (2026-11-18): `formatServingQty` printed "1." for a quantity
// that rounds to a whole number at two decimals (0.667 cup x 1.5 = 1.0005 gave
// "1. cups (255 g)" in the Diet chart's Portions text, the Amul Dahi row and any
// non-quarter quantity). The Grams view's bracket reuses this text, so it is
// fixed at the source.
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/nutrition/services/curated_diet_plan_generator.dart';

void main() {
  test('a non-quarter quantity prints without a trailing dot or zeros', () {
    expect(formatServingQty(1.0005), '1');
    expect(formatServingQty(2.004), '2');
    expect(formatServingQty(0.333), '0.33');
    expect(formatServingQty(1.33), '1.33');
    expect(formatServingQty(1.4), '1.4');
  });

  test('whole numbers and quarters are unchanged', () {
    expect(formatServingQty(1), '1');
    expect(formatServingQty(0.5), '1/2');
    expect(formatServingQty(1.5), '1 1/2');
    expect(formatServingQty(2.75), '2 3/4');
  });

  test('the row that showed it: 0.667 cup (170 g) scaled', () {
    expect(scaleServingDesc('0.667 cup (170 g)', 1.5), '1 cup (255 g)');
    expect(scaleServingDesc('0.667 cup (170 g)', 3), '2 cups (510 g)');
    expect(scaleServingDesc('0.667 cup (170 g)', 2), '1.33 cups (340 g)');
  });
}
