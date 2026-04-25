// test/subscription/high_value_features_test.dart
//
// Locks the contents of SubscriptionService._highValueFeatures.
// active_workout_mode was removed in Q6 (always-free decision); test
// guards against accidental re-addition.

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

      expect(
        highValueBlock!.group(0)!.contains('featureActiveWorkoutMode'),
        false,
        reason:
            '_highValueFeatures must not contain featureActiveWorkoutMode '
            '— Q6 made active workout always free.',
      );
    });

    test('train_screen has no gate(featureActiveWorkoutMode) call', () {
      final source = File(
        'lib/features/train/screens/train_screen.dart',
      ).readAsStringSync();
      expect(
        RegExp(r'\.gate\([^)]*featureActiveWorkoutMode').hasMatch(source),
        false,
        reason:
            'train_screen must not gate START WORKOUT entry points behind '
            'featureActiveWorkoutMode (Q6).',
      );
    });
  });
}
