// test/plan_generator/edit_profile_regen_test.dart
//
// Regression test for F6 — when user has fitness_experience=advanced
// + days_per_week=5 in their profile, the regen path through
// edit_profile_screen must produce 8 exercises/day (advanced × 5),
// not 4 (beginner × 5 fallback).

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/volume_filter.dart';

void main() {
  group('VolumeFilter.targetCount sanity', () {
    test('advanced + 5 days = 8 exercises', () {
      expect(VolumeFilter.targetCount('advanced', 5), 8);
    });

    test('beginner + 5 days = 4 exercises', () {
      expect(VolumeFilter.targetCount('beginner', 5), 4);
    });

    test('intermediate + 5 days = 6 exercises', () {
      expect(VolumeFilter.targetCount('intermediate', 5), 6);
    });
  });

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
