import 'package:flutter_test/flutter_test.dart';
import 'v4_diagnostic/library_loader.dart';
import 'v4_diagnostic/query_v4_mirror.dart';
import 'v4_diagnostic/library_integrity.dart';

void main() {
  group('V4 Diagnostic Harness', () {
    test('library_loader loads all exercises from assets/data/exercise_library.json', () {
      final exercises = LibraryLoader.loadFromAssets();
      expect(exercises, isNotEmpty);
      expect(exercises.length, greaterThan(100),
          reason: 'Library should have at least 100 exercises');
      final first = exercises.first;
      expect(first['id'], isNotNull);
      expect(first['movement_pattern'], isNotNull);
      expect(first['equipment_tier'], isA<List>());
    });
  });

  group('queryV4Mirror parity', () {
    final library = LibraryLoader.loadFromAssets();

    test('horizontal_push + basic_gym + compound returns > 0 results', () {
      final results = QueryV4Mirror.query(
        library,
        movementPattern: 'horizontal_push',
        equipmentTier: 'basic_gym',
        exerciseType: 'compound',
      );
      expect(results, isNotEmpty);
      // Barbell Bench Press is the canonical entry (id E001) — it must be present
      final names = results.map((e) => e['name']).toList();
      expect(names, contains('Barbell Bench Press'));
    });

    test('compound-first sort: first result is compound when mixed', () {
      final results = QueryV4Mirror.query(
        library,
        movementPattern: 'horizontal_push',
        equipmentTier: 'full_gym',
      );
      expect(results.first['exercise_type'], 'compound');
    });

    test('excludeNames removes matching exercises', () {
      final all = QueryV4Mirror.query(
        library,
        movementPattern: 'horizontal_push',
        equipmentTier: 'basic_gym',
      );
      final excluded = QueryV4Mirror.query(
        library,
        movementPattern: 'horizontal_push',
        equipmentTier: 'basic_gym',
        excludeNames: {'Barbell Bench Press'},
      );
      expect(excluded.length, all.length - 1);
      expect(
        excluded.any((e) => e['name'] == 'Barbell Bench Press'),
        isFalse,
      );
    });

    test('suitableFor="beginner" filters correctly', () {
      final results = QueryV4Mirror.query(
        library,
        movementPattern: 'horizontal_push',
        suitableFor: 'beginner',
      );
      for (final ex in results) {
        final suitable = (ex['suitable_for'] as List)
            .map((s) => s.toString().toLowerCase())
            .toList();
        expect(suitable.contains('beginner'), isTrue);
      }
    });
  });

    group('Library integrity pre-check', () {
      final library = LibraryLoader.loadFromAssets();

      test('emits unique equipment_tier string values', () {
        final tiers = LibraryIntegrity.uniqueEquipmentTiers(library);
        expect(tiers, isNotEmpty);
        // Basic sanity: the canonical four tiers should be present
        expect(tiers, contains('full_gym'));
        expect(tiers, contains('basic_gym'));
      });

      test('produces triplet counts covering all 11 movement patterns', () {
        final rows = LibraryIntegrity.tripletCounts(library);
        final patterns = rows.map((r) => r.movementPattern).toSet();
        // The 11 V4 patterns
        expect(patterns.length, greaterThanOrEqualTo(11));
      });

      test('renders a Markdown table', () {
        final md = LibraryIntegrity.renderMarkdown(library);
        expect(md, contains('## Library integrity pre-check'));
        expect(md, contains('| movement_pattern |'));
        expect(md, contains('Equipment tier unique values:'));
      });
    });
}
