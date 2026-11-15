import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HydrationCard is a single WardCard with two rows', () {
    final source = File(
      'lib/features/nutrition/widgets/hydration_card.dart',
    ).readAsStringSync();

    expect(source.contains('class HydrationCard'), isTrue,
        reason: 'HydrationCard widget must exist');

    // Single card surface
    final cardOpens = 'WardCard('.allMatches(source).length;
    expect(cardOpens, 1,
        reason: 'HydrationCard must render exactly ONE WardCard '
            '(both rows share one surface per Q8.1=A).');

    // Water row primitives
    expect(source.contains('WardGlassGrid'), isTrue,
        reason: 'Water row must include WardGlassGrid (8-cell)');
    expect(source.contains("'+ 250ML'") || source.contains('+ 250ML'),
        isTrue,
        reason: 'Water row must show the +250ML quick-add button');
    expect(source.contains("'+ 500ML'") || source.contains('+ 500ML'),
        isTrue,
        reason: 'Water row must show the +500ML quick-add button');

    // Urine row primitives
    expect(source.contains('URINE STATUS') || source.contains('URINE'),
        isTrue,
        reason: 'Urine row must show the URINE STATUS pill label');
    expect(source.contains('change'), isTrue,
        reason: 'Urine row must show the [change ▾] toggle');
    expect(source.contains('AnimatedSize') || source.contains('AnimatedCrossFade'),
        isTrue,
        reason: 'Color picker must expand inline, not push to a new sheet');

    // Hive integration via existing providers
    expect(source.contains('waterIntakeProvider'), isTrue,
        reason: 'Water row must read waterIntakeProvider (existing)');
    expect(source.contains('urineColorProvider'), isTrue,
        reason: 'Urine row must read urineColorProvider (existing)');
  });
}
