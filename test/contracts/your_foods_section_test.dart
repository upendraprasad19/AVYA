import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('YourFoodsSection mirrors Train YOUR EXERCISES pattern', () {
    final source = File(
      'lib/features/nutrition/widgets/your_foods_section.dart',
    ).readAsStringSync();

    expect(source.contains('class YourFoodsSection'), isTrue,
        reason: 'YourFoodsSection widget must exist');

    // Reactive Hive read
    expect(source.contains('ValueListenableBuilder'), isTrue,
        reason: 'Must use ValueListenableBuilder<customBox> so a newly '
            'created custom food appears immediately as a chip.');
    expect(source.contains('customBox.listenable()'), isTrue,
        reason: 'Listenable must come from HiveService.instance.customBox');
    expect(source.contains("'custom_food_'"), isTrue,
        reason: 'Must filter customBox keys by the custom_food_ prefix');

    // Three status states required
    expect(source.contains("'DRAFT'"), isTrue,
        reason: 'DRAFT pill required for non-submitted entries');
    expect(source.contains("'PENDING'"), isTrue,
        reason: 'PENDING pill required for submitted-but-not-approved');
    expect(source.contains("'APPROVED'"), isTrue,
        reason: 'APPROVED pill required for community-approved entries');

    // Empty-state hint + + ADD CUSTOM affordance
    expect(source.contains('No custom foods yet'), isTrue,
        reason: 'Empty state copy must read "No custom foods yet"');
    expect(source.contains('+ ADD CUSTOM'), isTrue,
        reason: '+ ADD CUSTOM pill must be present in both header and '
            'empty-state.');

    // Tap chip → CustomFoodSheet
    expect(source.contains('showCustomFoodSheet'), isTrue,
        reason: 'Tap on chip / + ADD CUSTOM must call '
            'showCustomFoodSheet(context) — the existing sheet is the '
            'single edit/create surface.');
  });
}
