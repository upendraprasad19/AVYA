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
      // Comment lines are dropped, so a commented-out call cannot satisfy it.
      final source = File(
        'lib/features/profile/screens/edit_profile_screen.dart',
      ).readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join('\n');
      // The save path runs after the screen may already be closed, so it
      // invalidates through the ProviderContainer captured at Save start
      // (`container`), never through the widget `ref` (c4b8d2).
      expect(
        source.contains('container.invalidate(aiInsightProvider)'),
        true,
        reason:
            'edit_profile_screen must invalidate aiInsightProvider (via the '
            'container captured at Save start) in the regen save path so '
            'home AI insight refreshes.',
      );
      expect(
        source.contains('ref.invalidate(aiInsightProvider)'),
        false,
        reason:
            'a widget `ref` is dead once the screen closes mid-save: '
            'invalidate through the captured container instead (c4b8d2).',
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
