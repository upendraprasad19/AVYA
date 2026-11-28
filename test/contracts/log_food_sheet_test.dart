import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LogFoodSheet hosts 5 modes with AI default', () {
    final source = File(
      'lib/features/nutrition/widgets/log_food_sheet.dart',
    ).readAsStringSync();

    expect(source.contains('class LogFoodSheet'), isTrue,
        reason: 'LogFoodSheet widget must exist');
    expect(source.contains('void showLogFoodSheet'), isTrue,
        reason: 'showLogFoodSheet entry-point function must exist '
            'so nutrition_screen and any other caller can open it.');

    // 5 mode names — keep these exact strings, the test is a contract
    for (final name in ['ai', 'scan', 'cart', 'barcode', 'search']) {
      expect(source.contains('LogFoodMode.$name'),
          isTrue,
          reason: 'LogFoodMode.$name must be a member of the enum');
    }

    // AI is default
    final defaultLine = source.indexOf('_active = LogFoodMode.');
    expect(defaultLine, isNot(-1),
        reason: 'A field initial assignment _active = LogFoodMode.<x> '
            'must exist');
    expect(
      source.substring(defaultLine, defaultLine + 60).contains('LogFoodMode.ai'),
      isTrue,
      reason: 'Default active mode must be LogFoodMode.ai',
    );

    // Sheet height ~75% of screen
    expect(
      source.contains('initialChildSize:') ||
          source.contains('heightFactor: 0.75') ||
          source.contains('* 0.75'),
      isTrue,
      reason: 'Sheet must size to ~75% of the screen height (per spec).',
    );

    // Segmented WardChip tabs
    expect(source.contains('WardChip'), isTrue,
        reason: 'Tabs must render as WardChip (selected = gold).');
  });
}
