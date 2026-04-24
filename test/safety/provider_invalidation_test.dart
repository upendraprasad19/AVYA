import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Verifies that the provider invalidation paths introduced/confirmed in
/// fix/crash-safety are present in the source files.
///
/// Task 9 of the PR review noted two gaps:
///  a) nutritionSummaryProvider not invalidated after food delete/restore
///  b) workoutStatsProvider not invalidated after template delete
///
/// Both turned out to already be present in the notifier methods. These tests
/// confirm the invariant won't silently regress.
void main() {
  group(
      'Task 9a – nutritionSummaryProvider invalidated in FoodLogNotifier', () {
    test('deleteFoodLog invalidates nutritionSummaryProvider', () {
      final src = _src(
          'lib/features/nutrition/providers/nutrition_provider.dart');

      // Find the deleteFoodLog method body and confirm the invalidation is
      // present within it (not just anywhere in the file).
      final deleteStart = src.indexOf('Future<void> deleteFoodLog(');
      expect(deleteStart, greaterThan(0),
          reason: 'deleteFoodLog method must exist');

      final deleteEnd = src.indexOf('\n  }', deleteStart);
      final deleteBody = src.substring(deleteStart, deleteEnd);

      expect(deleteBody, contains('ref.invalidate(nutritionSummaryProvider)'),
          reason: 'deleteFoodLog must invalidate nutritionSummaryProvider');
    });

    test('restoreFoodLog invalidates nutritionSummaryProvider', () {
      final src = _src(
          'lib/features/nutrition/providers/nutrition_provider.dart');

      final restoreStart = src.indexOf('Future<void> restoreFoodLog(');
      expect(restoreStart, greaterThan(0),
          reason: 'restoreFoodLog method must exist');

      final restoreEnd = src.indexOf('\n  }', restoreStart);
      final restoreBody = src.substring(restoreStart, restoreEnd);

      expect(restoreBody, contains('ref.invalidate(nutritionSummaryProvider)'),
          reason: 'restoreFoodLog must invalidate nutritionSummaryProvider');
    });
  });

  group('Task 9b – workoutStatsProvider invalidated in TemplatesNotifier', () {
    test('deleteTemplate invalidates workoutStatsProvider', () {
      final src = _src(
          'lib/features/train/providers/train_provider.dart');

      final deleteStart = src.indexOf('Future<void> deleteTemplate(');
      expect(deleteStart, greaterThan(0),
          reason: 'deleteTemplate method must exist');

      // Find end of the method (next closing brace at indentation level 2)
      final deleteEnd = src.indexOf('\n  }', deleteStart);
      final deleteBody = src.substring(deleteStart, deleteEnd);

      expect(deleteBody, contains('ref.invalidate(workoutStatsProvider)'),
          reason: 'deleteTemplate must invalidate workoutStatsProvider');
    });

    test('deleteTemplate invalidates currentPlanProvider', () {
      final src = _src('lib/features/train/providers/train_provider.dart');
      final deleteStart = src.indexOf('Future<void> deleteTemplate(');
      final deleteEnd = src.indexOf('\n  }', deleteStart);
      final deleteBody = src.substring(deleteStart, deleteEnd);

      expect(deleteBody, contains('ref.invalidate(currentPlanProvider)'),
          reason: 'deleteTemplate must also invalidate currentPlanProvider');
    });

    test('deleteTemplate invalidates todayWorkoutProvider', () {
      final src = _src('lib/features/train/providers/train_provider.dart');
      final deleteStart = src.indexOf('Future<void> deleteTemplate(');
      final deleteEnd = src.indexOf('\n  }', deleteStart);
      final deleteBody = src.substring(deleteStart, deleteEnd);

      expect(deleteBody, contains('ref.invalidate(todayWorkoutProvider)'),
          reason: 'deleteTemplate must also invalidate todayWorkoutProvider');
    });
  });

  group('Regression – no new raw Hive.box() calls introduced', () {
    // Quick regression sweep over the four files that were patched.
    for (final filePath in const [
      'lib/features/auth/screens/sign_in_screen.dart',
      'lib/features/ai_coach/repositories/ai_coach_repository.dart',
      'lib/shared/repositories/plan_engine/progression_resolver.dart',
      'lib/features/auth/widgets/terms_modal.dart',
    ]) {
      test('$filePath has no raw Hive.box() calls', () {
        final src = _src(filePath);
        expect(src, isNot(contains('Hive.box(')));
      });
    }
  });
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _src(String relativePath) {
  final file = File(relativePath);
  if (!file.existsSync()) {
    fail('Source file not found: $relativePath');
  }
  return file.readAsStringSync();
}
