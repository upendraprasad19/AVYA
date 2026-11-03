// test/plan_generator/edit_profile_regen_test.dart
//
// Regression test for F6 — when the user has fitness_experience=advanced in their
// profile, the regen path through edit_profile_screen must read that key (not a
// never-written `detected_experience_level`, which fell back to beginner). The
// `VolumeFilter.targetCount` sanity group was deleted with the function (flip
// 2026-11-02): the experience now sets the budget's weekly band and session cap.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('edit_profile_screen experience key (F6)', () {
    test('reads fitness_experience, not detected_experience_level', () {
      final source =
          File('lib/features/profile/screens/edit_profile_screen.dart')
              .readAsStringSync();

      expect(
        source.contains("profile['detected_experience_level']") ||
            source.contains('profile["detected_experience_level"]'),
        false,
        reason:
            'detected_experience_level is never written by onboarding or '
            'profile updates. Reading it always returns null and falls back '
            'to beginner.',
      );

      expect(
        source.contains("profile['fitness_experience']") ||
            source.contains('profile["fitness_experience"]'),
        true,
        reason:
            'edit_profile must read fitness_experience (the canonical key '
            'written by onboarding step 04 and edit_profile itself).',
      );
    });
  });
}
