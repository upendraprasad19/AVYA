// test/subscription/high_value_features_test.dart
//
// Locks the contents of SubscriptionService._highValueFeatures.
// active_workout_mode was removed in Q6 (always-free decision); test
// guards against accidental re-addition.
//
// audit-2026-05-16 E.8 — `featureActiveWorkoutMode` constant DELETED from
// AppConstants (had 0 callsites for 3 weeks since Test #9; founder approved
// Phase D NEEDS_DECISION 4 Option A). Tests updated to assert the string
// literal `'active_workout_mode'` no longer appears in the high-value set
// (constant is gone; can't reference it).

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SubscriptionService._highValueFeatures (Q6)', () {
    test('contains exactly 3 features (no active_workout_mode)', () {
      final source = File(
        'lib/core/services/subscription_service.dart',
      ).readAsStringSync();

      // Confirm canonical 3 are present
      expect(source.contains('featurePhases2To12'), true);
      expect(source.contains('featureAiCoachUnlimited'), true);
      expect(source.contains('featureProgressPhotos'), true);

      // Locate the _highValueFeatures literal
      final highValueBlock = RegExp(
        r'_highValueFeatures\s*=\s*\{[^}]*\}',
        dotAll: true,
      ).firstMatch(source);
      expect(highValueBlock, isNotNull,
          reason: 'Could not locate _highValueFeatures set in source.');

      // Reference by string literal — the symbol `featureActiveWorkoutMode`
      // was deleted in audit-2026-05-16 E.8.
      expect(
        highValueBlock!.group(0)!.contains('active_workout_mode'),
        false,
        reason:
            '_highValueFeatures must not contain "active_workout_mode" '
            '— Q6 made active workout always free; the constant was '
            'deleted entirely in audit-2026-05-16 E.8.',
      );
    });

    test('train_screen has no gate against active_workout_mode', () {
      final source = File(
        'lib/features/train/screens/train_screen.dart',
      ).readAsStringSync();
      // Pre-fix the gate was `gate(AppConstants.featureActiveWorkoutMode, ...)`.
      // Post-deletion, no callsite can reference the symbol AND no callsite
      // should hardcode the string. Match the string literal form for
      // future-proofing.
      expect(
        source.contains("'active_workout_mode'") ||
            source.contains('featureActiveWorkoutMode'),
        false,
        reason:
            'train_screen must not gate START WORKOUT entry points behind '
            'active_workout_mode (Q6 + audit-2026-05-16 E.8).',
      );
    });
  });
}
