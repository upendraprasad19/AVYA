// Diet plan Unit 2a (2026-11-14, docs/plans/diet-food-type.md T6). Founder:
// "workout generation has no effect with the diet selected". PRESENCE ONLY
// (a source sweep, stated): no workout-side source reads the food type. A
// rename would evade it; the founder's rule is also stated in the plan and in
// lib/features/nutrition/CLAUDE.md.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('plan engine, Train and Home never read the food type', () {
    final pattern = RegExp(r"diet_preference|profile\['diet|foodType|FoodType|food_types\.dart");
    final hits = <String>[];
    var files = 0;
    for (final dir in [
      'lib/shared/repositories/plan_engine',
      'lib/features/train',
      'lib/features/home',
    ]) {
      for (final f in Directory(dir).listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        files++;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (pattern.hasMatch(lines[i])) hits.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(files, greaterThan(50), reason: 'precondition: the sweep saw the tree');
    expect(hits, isEmpty);
  });
}
