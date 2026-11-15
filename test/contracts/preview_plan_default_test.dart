import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// APK Test #3 — phase exercise count fix.
///
/// previewPlanProvider's fallback for `fitness_experience` MUST match
/// onboarding's pre-selected default ('intermediate'). Otherwise the
/// roadmap preview generates with a beginner profile and shows 4
/// exercises while the user's actual plan (built from intermediate)
/// shows 6 — the count mismatch users surfaced in APK Test #2.
void main() {
  test('fitness_experience fallback is intermediate, not beginner', () {
    final src = File('lib/features/train/providers/preview_plan_provider.dart')
        .readAsStringSync();

    // Find the fallback line.
    final fallbackPattern = RegExp(
      r"\(profile\['fitness_experience'\] as String\?\)\s*\?\?\s*'(\w+)'",
    );
    final match = fallbackPattern.firstMatch(src);

    expect(match, isNotNull,
        reason: 'previewPlanProvider must read fitness_experience '
            'with a string fallback (NEVER null-pass to PlanGenerator).');
    expect(
      match!.group(1),
      'intermediate',
      reason: 'Fallback MUST be "intermediate" to match onboarding\'s '
          'pre-selected default. APK Test #2 / F6 lesson — using '
          '"beginner" generates a different exercise count than the '
          'user\'s actual plan (4 vs 6 ex/day for 5-day plans).',
    );
  });
}
