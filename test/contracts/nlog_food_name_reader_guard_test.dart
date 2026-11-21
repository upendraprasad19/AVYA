// OI-493 Landing A (plan D9, P10): no new reader of a top-level `food_name`
// on an `nlog_` row.
//
// NutritionWriteService.logMeal writes every meal's names into items[] and
// never a top-level `food_name`, yet six readers took the name from that key
// and so showed "Unknown"/fallback text (or nothing) for every meal: the coach
// snapshot meals_today, the delete title, the template default name, the
// Search tab recent list, the recent_deletes audit (never written) and the
// dead MealSection. They now read items[] through NutritionReadService.
//
// This guard counts the `food_name` token, in any quote style, in every
// lib/**/*.dart file with comments removed (the shared OI-494 scanner), and
// compares the per-file count to an EXACT allowlist. A new `food_name` token
// anywhere, an extra one in an allowed file, or a dropped allowed one fails:
// a changed count means re-reading that site and re-taking the count here.
//
// Token-level by design: a key built at run time ('food_' + 'name', an
// interpolation, a const imported from another file) is not seen. Such a
// read would be deliberate and visible in review; this guard catches the
// accidental `row['food_name']` that 8b3d4e and OI-493 were both made of.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_source_scan.dart';

final RegExp _token = RegExp(r'(?<![\w$])food_name(?![\w$])');

int _count(String src) => _token.allMatches(stripDartComments(src)).length;

/// file -> exact count, with why each token is not an nlog_ row read.
const Map<String, (int, String)> _allowed = {
  'lib/core/services/nutrition_write_service.dart': (
    3,
    'deleteLog audit: the legacy flat-row test (hasFoodMeta), the legacy '
        'fallback read, and the audit entry key (its reader passes it on)',
  ),
  'lib/core/services/sync/sync_nutrition.dart': (
    5,
    'cloud nutrition_log_items column food_name: push maps item name to it, '
        'restore maps it back to the item name, the push hash key tolerates it',
  ),
  'lib/core/services/sync_service.dart': (
    1,
    'restore fingerprint over cloud item rows (name or food_name column)',
  ),
  'lib/features/ai_coach/services/coach_meal_log.dart': (
    2,
    'coach payloads: the tool intent food_name (fallback item name) and the '
        'log_food tag food_name, never an nlog_ row',
  ),
  'lib/features/ai_coach/services/tool_dispatcher.dart': (
    2,
    'the log_meal_by_text intent payload and its result map to the model',
  ),
  'lib/features/ai_coach/widgets/tool_confirm_card.dart': (
    1,
    'the log_meal_by_text intent payload shown on the card',
  ),
};

void main() {
  test('every lib/ food_name token is in an allowed file, at the exact count',
      () {
    final found = <String, int>{};
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final f in files) {
      final n = _count(f.readAsStringSync());
      if (n > 0) found[f.path.replaceAll(r'\', '/')] = n;
    }
    final expected = {
      for (final e in _allowed.entries) e.key: e.value.$1,
    };
    expect(found, expected,
        reason: 'A food_name token appeared, moved or vanished. An nlog_ row '
            'has no top-level food_name: read the name from items[] via '
            'NutritionReadService.deriveMealDisplayName / '
            'shortMealDisplayName. If the new token is not an nlog_ row read, '
            're-take the count and give the reason in _allowed.');
  });

  test('the scanner counts every quote style and ignores comments', () {
    expect(_count("final n = row['food_name'];"), 1);
    expect(_count('final n = row["food_name"];'), 1);
    expect(_count("const k = 'food_name'; final n = row[k];"), 1);
    expect(_count("final n = row['''food_name'''];"), 1);
    expect(_count(r"final n = row[r'food_name'];"), 1);
    expect(_count("// row['food_name']\nfinal a = 1;"), 0);
    expect(_count("/* row['food_name'] */ final a = 1;"), 0);
    expect(_count("/// reads `food_name`\nfinal a = 1;"), 0);
    expect(_count("final n = row['food_name_v2'] ?? row['my_food_name'];"), 0);
  });
}
