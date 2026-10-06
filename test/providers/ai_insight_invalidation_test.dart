// test/providers/ai_insight_invalidation_test.dart
//
// Regression test for F5 — aiInsightProvider must be invalidated after:
//   1. Plan regenerate (edit_profile_screen._save → generateAndScheduleFromDate)
//   2. Workout completion (train_provider.completeWorkout)
//
// Strategy: source-grep tests against the source files to ensure invalidation
// calls exist where they need to. The provider rebuild is automatically
// covered by Riverpod's invalidate() semantics.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('aiInsightProvider invalidation call sites (F5)', () {
    test('edit_profile_screen invalidates aiInsightProvider after regen', () {
      final source = File(
        'lib/features/profile/screens/edit_profile_screen.dart',
      ).readAsStringSync();
      expect(
        source.contains('ref.invalidate(aiInsightProvider)'),
        true,
        reason:
            'edit_profile_screen must invalidate aiInsightProvider in the '
            'regen save path so home AI insight refreshes.',
      );
    });

    test('train_provider invalidates aiInsightProvider in completeWorkout', () {
      final source = File(
        'lib/features/train/providers/train_provider.dart',
      ).readAsStringSync();
      expect(
        source.contains('ref.invalidate(aiInsightProvider)'),
        true,
        reason:
            'train_provider.completeWorkout must invalidate '
            'aiInsightProvider so the home insight reflects the completed '
            'workout instead of the pre-completion "scheduled" state.',
      );
    });
  });
}
