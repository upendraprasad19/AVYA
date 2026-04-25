// test/sync/custom_exercise_sync_test.dart
//
// Regression test for F1 — the syntax error in _projectCustomExercise
// caused silent sync failures for custom exercises with default_duration_secs
// set (timed exercises like "Plank", "Handstand Hold").

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sync_service custom exercise projection', () {
    test('source has no invalid ?defaultDur syntax (regression for F1)', () {
      final source =
          File('lib/core/services/sync_service.dart').readAsStringSync();
      expect(
        source.contains('?defaultDur'),
        false,
        reason:
            'sync_service must not contain `?defaultDur` — that is invalid '
            'Dart map-value syntax that caused silent custom exercise sync '
            'failures (F1 from APK Test #2 batch).',
      );
    });

    test('source uses conditional spread for default_duration_secs', () {
      final source =
          File('lib/core/services/sync_service.dart').readAsStringSync();
      expect(
        source.contains("if (defaultDur != null) 'default_duration_secs'") ||
            source.contains('if (defaultDur != null) "default_duration_secs"'),
        true,
        reason:
            'sync_service should guard the default_duration_secs entry with '
            'the conditional-spread pattern.',
      );
    });
  });
}
