// APK Test #12.7 — pin home streak pill data source.
//
// Founder install of APK 12.6 surfaced a UX bug: home screen streak pill
// showed "0 DAYS" while the rank-chip bottom sheet showed "5 DAYS" for
// the same user, same Hive, same moment.
//
// Root cause:
//   - Home `StreakNotifier.build()` read `progress['current_streak_days']`
//     from `user_progress` Hive — a CACHED value only refreshed inside
//     `train_provider.completeWorkout`.
//   - Rank chip and `RankService` both call
//     `WorkoutRepository.calculateCurrentStreak()` directly — a LIVE
//     walk-back through `schedule_<date>` keys.
// On a cold start, before the user finishes a workout, the cached field
// is stale → the two surfaces drift.
//
// Fix: home `StreakNotifier.build()` now calls
// `WorkoutRepository.instance.calculateCurrentStreak()` so home and rank
// chip use the SAME source. This test source-greps to keep it that way.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('home streak pill — same source as rank chip (APK Test #12.7)', () {
    late final String homeProvider;

    setUpAll(() {
      final f = File('lib/features/home/providers/home_provider.dart');
      expect(f.existsSync(), isTrue);
      homeProvider = f.readAsStringSync();
    });

    test('StreakNotifier.build uses WorkoutRepository.calculateCurrentStreak',
        () {
      // Find the StreakNotifier class body. We look at everything from
      // "class StreakNotifier" up to the next blank line followed by a
      // top-level declaration — sufficient for a single-class file slice.
      final start = homeProvider.indexOf('class StreakNotifier');
      expect(start, greaterThan(-1), reason: 'StreakNotifier must exist');
      // Take the next ~1500 chars — enough to capture the build() body.
      final end = (start + 1500).clamp(0, homeProvider.length);
      final slice = homeProvider.substring(start, end);

      expect(
        slice.contains('currentStreak()') ||
            slice.contains('calculateCurrentStreak'),
        isTrue,
        reason:
            'StreakNotifier.build() MUST call '
            'WorkoutRepository.instance.currentStreak() (the pure-read '
            'half of the C-14 audit-2026-05-11 CQRS split) so the home '
            'pill agrees with the rank-chip bottom sheet. The legacy '
            'name `calculateCurrentStreak` is still accepted via the '
            'deprecation shim. See feedback_source_of_truth_audit.md.',
      );
    });

    test('StreakNotifier.build does not read cached current_streak_days', () {
      final start = homeProvider.indexOf('class StreakNotifier');
      expect(start, greaterThan(-1));
      final end = (start + 1500).clamp(0, homeProvider.length);
      final slice = homeProvider.substring(start, end);
      // Strip comments — commentary about the old behavior is fine.
      final stripped = slice
          .replaceAll(RegExp(r'//.*'), '')
          .replaceAll(RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '');

      expect(
        stripped.contains("'current_streak_days'"),
        isFalse,
        reason:
            'StreakNotifier.build() must not read the cached '
            '`current_streak_days` field — that value is only refreshed by '
            '`completeWorkout` and drifts on cold start. Use '
            'WorkoutRepository.calculateCurrentStreak() instead.',
      );
    });

    test('rank chip surfaces use the same canonical helper as home', () {
      // C-14 audit-2026-05-11 — the CQRS split renamed the canonical
      // helper to `currentStreak()` (pure read). Pre-fix this asserted
      // the legacy `calculateCurrentStreak` literal in
      // rank_service_record_sheet — keep the spirit (both surfaces use
      // the same canonical helper) under the new name.
      final f = File(
        'lib/features/profile/widgets/rank_service_record_sheet.dart',
      );
      expect(f.existsSync(), isTrue);
      final src = f.readAsStringSync();
      expect(
        src.contains('currentStreak()') ||
            src.contains('calculateCurrentStreak'),
        isTrue,
        reason:
            'rank_service_record_sheet must call '
            'WorkoutRepository.instance.currentStreak() — the canonical '
            'pure-read helper home now uses too. The legacy name is '
            'still accepted via the deprecation shim.',
      );
    });
  });
}
