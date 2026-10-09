// Beginner full-body split tests for Plan Engine V4.
//
// Relocated from `test/plan_engine_v3_test.dart` on 2026-05-21 (tech-debt
// audit B5 / T7 split). Test bodies are byte-identical to the V3 file; only
// the helper symbols were made public (`_exercise` → `exercise`, etc.) and
// extracted to `_helpers.dart`.
//
// Scope: SplitResolver behavior for the beginner full-body archetype
// (3-day / 4-day full-body and 5-day non-full-body fallback).

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/split_resolver.dart';

void main() {
  group('SplitResolver', () {
    group('Beginner routing', () {
      test('beginner 3-day → 3 full body days', () {
        final slots = SplitResolver.select(
          'build_muscle', 3, experienceLevel: 'beginner',
        );
        expect(slots.length, 3);
        for (final slot in slots) {
          expect(slot.dayType, 'full_body');
          expect(slot.name.toLowerCase(), contains('full body'));
        }
      });

      test('beginner 4-day → 4 full body days', () {
        final slots = SplitResolver.select(
          'build_muscle', 4, experienceLevel: 'beginner',
        );
        expect(slots.length, 4);
        for (final slot in slots) {
          expect(slot.dayType, 'full_body');
          expect(slot.name.toLowerCase(), contains('full body'));
        }
      });

      test('beginner 5-day → NOT full body (uses regular split)', () {
        final slots = SplitResolver.select(
          'build_muscle', 5, experienceLevel: 'beginner',
        );
        expect(slots.length, 5);
        // 5-day beginner uses intermediate splits, not all full_body
        final dayTypes = slots.map((s) => s.dayType).toSet();
        expect(dayTypes.contains('push') || dayTypes.contains('pull') ||
               dayTypes.contains('legs'), isTrue,
            reason: 'Beginner 5-day should use PPL-style split, not all full body');
      });

      test('beginner 3-day has Push/Pull/Legs specs across days', () {
        final slots = SplitResolver.select(
          'build_muscle', 3, experienceLevel: 'beginner',
        );
        // Each day should have a mix of categories
        for (final slot in slots) {
          final categories = slot.specsA.map((s) => s.category).toSet();
          expect(categories.length, greaterThanOrEqualTo(2),
              reason: '${slot.name} should have at least 2 categories');
        }
      });

      test('beginner 4-day adds a D day with core emphasis', () {
        final slots = SplitResolver.select(
          'lose_fat', 4, experienceLevel: 'beginner',
        );
        expect(slots.length, 4);
        final dayD = slots.last;
        expect(dayD.name, contains('Full Body D'));
        // Day D has a CSpec('Core', 2) meaning 2 core exercises to be picked
        final coreSpecs = dayD.specsA.where((s) => s.category == 'Core');
        expect(coreSpecs, isNotEmpty);
        final totalCoreCount = coreSpecs.fold<int>(0, (sum, s) => sum + s.count);
        expect(totalCoreCount, 2,
            reason: 'Day D should request 2 core exercises total');
      });
    });
  });
}
