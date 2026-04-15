import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'v4_diagnostic/library_loader.dart';
import 'v4_diagnostic/query_v4_mirror.dart';
import 'v4_diagnostic/library_integrity.dart';
import 'v4_diagnostic/cascade_tracer.dart';
import 'v4_diagnostic/combos.dart';
import 'v4_diagnostic/markdown_writer.dart';

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

    group('CascadeTracer', () {
      final library = LibraryLoader.loadFromAssets();

      test('Quads/knee_dominant/compound/P1 + full_gym + advanced picks a real library entry', () {
        const slot = MuscleSlot(
          targetMuscle: 'Quads',
          movementPattern: 'knee_dominant',
          exerciseType: 'compound',
          priority: 1,
        );
        final trace = CascadeTracer.trace(
          library,
          slot: slot,
          equipmentTier: 'full_gym',
          effectiveExp: 'advanced',
          phase: 1,
          injuries: const [],
          pickedNames: <String>{},
        );
        expect(trace.attempts.length, greaterThanOrEqualTo(1));
        expect(trace.finalPick, isNotNull);
        expect(trace.finalPick!.source, isNot(CascadePickSource.universalPool));
      });

      test('Hamstrings/hip_dominant/compound/P1 + full_gym + advanced: records all 5 attempts if exhausted', () {
        // This slot is the exact one we suspect is failing in production.
        // We don't assert WHICH stage picks it — we just assert the trace
        // walked through attempts in order and did not short-circuit wrongly.
        const slot = MuscleSlot(
          targetMuscle: 'Hamstrings',
          movementPattern: 'hip_dominant',
          exerciseType: 'compound',
          priority: 1,
        );
        final trace = CascadeTracer.trace(
          library,
          slot: slot,
          equipmentTier: 'full_gym',
          effectiveExp: 'advanced',
          phase: 1,
          injuries: const [],
          pickedNames: <String>{},
        );
        // Every attempt records a signature even if count=0
        for (final a in trace.attempts) {
          expect(a.signature, isNotEmpty);
        }
        // trace MUST yield either a library pick OR explicit universal-pool fallback
        expect(trace.finalPick, isNotNull);
      });
    });

    group('Combos', () {
      test('combos list has exactly 10 entries', () {
        expect(DiagnosticCombos.all.length, 10);
      });

      test('combo #1 is the bug-repro baseline', () {
        final c = DiagnosticCombos.all.first;
        expect(c.label, contains('bug-repro'));
        expect(c.goal, 'build_muscle');
        expect(c.equipment, 'full_gym');
        expect(c.daysPerWeek, 5);
        expect(c.experience, 'advanced');
        expect(c.phase, 1);
        expect(c.sessionDuration, isNull);
        expect(c.injuries, isEmpty);
        expect(c.weekCharacters, ['baseline']);
      });

      test('combo #10 exercises all 4 week characters', () {
        final c = DiagnosticCombos.all[9];
        expect(c.weekCharacters, ['baseline', 'overreach', 'peak', 'deload']);
      });
    });

    group('DiagnosticMarkdownWriter', () {
      final library = LibraryLoader.loadFromAssets();

      test('renders a full report for combo #1 (bug-repro)', () {
        final combo = DiagnosticCombos.all.first;
        final md = DiagnosticMarkdownWriter.renderCombo(combo, library);
        // Required section headers
        expect(md, contains('## Combo: '));
        expect(md, contains('### Day '));
        expect(md, contains('PRE-VolumeFilter:'));
        expect(md, contains('POST-VolumeFilter:'));
        expect(md, contains('excludeNames-in ('));
        // Attempts logged
        expect(md, contains('A1 ('));
        expect(md, contains('A5'));
        // Input echo
        expect(md, contains('effectiveExp='));
        expect(md, contains('equipmentTier=full_gym'));
      });

      test('renders all 4 week characters for combo #10', () {
        final combo = DiagnosticCombos.all[9];
        final md = DiagnosticMarkdownWriter.renderCombo(combo, library);
        expect(md, contains('Week baseline'));
        expect(md, contains('Week overreach'));
        expect(md, contains('Week peak'));
        expect(md, contains('Week deload'));
      });
    });
}
