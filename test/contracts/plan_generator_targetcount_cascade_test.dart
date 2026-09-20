// Source-grep contract for plan generator targetCount + cascade depth.
//
// Originally landed as T-10 of `audit_2026_05_11_t1_t11_contracts_test.dart`.
// Split per concept per tech-debt audit 2026-05-20 T12.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String relPath) => File(relPath).readAsStringSync();

void main() {
  group('T-10 plan generator targetCount + cascade depth', () {
    test('VolumeFilter.targetCount exists', () {
      final src =
          _src('lib/shared/repositories/plan_engine/volume_filter.dart');
      expect(src.contains('targetCount'), isTrue);
      // The table per lib/shared/repositories/plan_engine/CLAUDE.md: beginner / intermediate / advanced
      // × 3/4/5/6 days. Source must reference the experience tiers.
      expect(
        src.contains('beginner') &&
            src.contains('intermediate') &&
            src.contains('advanced'),
        isTrue,
        reason: 'VolumeFilter.targetCount must branch on '
            'experience level (beginner / intermediate / advanced) per '
            'lib/shared/repositories/plan_engine/CLAUDE.md.',
      );
    });

    test('exercise_selector cascade has the 5-attempt pattern', () {
      final src = _src(
          'lib/shared/repositories/plan_engine/exercise_selector.dart');
      // Per lib/shared/repositories/plan_engine/CLAUDE.md the cascade has 5 attempts ending in
      // universalPool. The canonical entry point is `_cascadeFill`
      // and the comment "5-attempt cascade" / "5 attempts" pins the
      // shape.
      expect(src.contains('_cascadeFill'), isTrue,
          reason: '_cascadeFill cascade entry point must exist.');
      expect(
        src.contains('5-attempt') ||
            src.contains('5 attempt') ||
            src.contains('5 attempts'),
        isTrue,
        reason: 'cascade must be documented as 5-attempt per lib/shared/repositories/plan_engine/CLAUDE.md.',
      );
      expect(src.contains('universalPool'), isTrue,
          reason: 'universalPool fallback must exist (terminal attempt).');
    });
  });
}
