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
      // OI-36 (audit-2026-05-17 Hermes C1) — deleteFoodLog now delegates to
      // NutritionWriteService.deleteLog. The WriteService's onStateChanged
      // hook (wired in app.dart) fires the canonical invalidation batch
      // including `nutritionSummaryProvider`. We assert the delegation in
      // the provider AND the invalidation in app.dart so the contract is
      // preserved end-to-end.
      final providerSrc = _src(
          'lib/features/nutrition/providers/nutrition_provider.dart');
      final appSrc = _src('lib/app.dart');

      final deleteStart =
          providerSrc.indexOf('Future<void> deleteFoodLog(');
      expect(deleteStart, greaterThan(0),
          reason: 'deleteFoodLog method must exist');
      final deleteEnd = providerSrc.indexOf('\n  }', deleteStart);
      final deleteBody = providerSrc.substring(deleteStart, deleteEnd);

      expect(
        deleteBody,
        contains('NutritionWriteService.instance.deleteLog'),
        reason:
            'deleteFoodLog must delegate to NutritionWriteService.instance.deleteLog '
            'so the canonical writer owns the mutation.',
      );

      expect(
        appSrc,
        contains('ref.invalidate(nutritionSummaryProvider)'),
        reason:
            'NutritionWriteService.onStateChanged in app.dart must invalidate '
            'nutritionSummaryProvider so deleteFoodLog (via the WriteService) '
            'triggers UI rebuild.',
      );
    });

    test('restoreFoodLog invalidates nutritionSummaryProvider', () {
      // C-12 (audit-2026-05-11) — restoreFoodLog now delegates to
      // NutritionWriteService.restoreFoodLog, which fires the canonical
      // _invalidateNutritionProviders helper (including
      // `nutritionSummaryProvider`). The literal `ref.invalidate(...)`
      // call moved out of the notifier; the contract is preserved by
      // the WriteService.
      final notifierSrc = _src(
          'lib/features/nutrition/providers/nutrition_provider.dart');

      final restoreStart = notifierSrc.indexOf('Future<void> restoreFoodLog(');
      expect(restoreStart, greaterThan(0),
          reason: 'restoreFoodLog method must exist');

      final restoreEnd = notifierSrc.indexOf('\n  }', restoreStart);
      final restoreBody =
          notifierSrc.substring(restoreStart, restoreEnd);

      final delegatesToService = restoreBody.contains(
          'NutritionWriteService.instance.restoreFoodLog(');
      final invalidatesInline =
          restoreBody.contains('ref.invalidate(nutritionSummaryProvider)');

      expect(delegatesToService || invalidatesInline, isTrue,
          reason:
              'restoreFoodLog must either invalidate nutritionSummaryProvider '
              'inline OR delegate to NutritionWriteService (which does).');

      if (delegatesToService) {
        // Verify the downstream still invalidates the provider.
        final svcSrc =
            _src('lib/core/services/nutrition_write_service.dart');
        expect(
          svcSrc,
          contains('c.invalidate(nutritionSummaryProvider)'),
          reason:
              'NutritionWriteService._invalidateNutritionProviders must '
              'invalidate nutritionSummaryProvider — else the delegation '
              'drops the contract.',
        );
      }
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
      // audit-fixwave 2026-07-02 / F15 — terms_modal.dart deleted (dead code).
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
