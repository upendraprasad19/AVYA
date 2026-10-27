import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Regression contract for diagnose c4d8a2 — `onboarding_completed_at` durable
/// writer + IST-as-UTC fix.
///
/// Pre-fix: `_syncUserProfile` (the canonical recurring profile->cloud sync)
/// OMITTED onboarding_completed_at, so the column had no durable writer and the
/// restoring-screen self-heal (which pushes via syncProfileNow -> _syncUserProfile)
/// silently dropped it. A missed one-shot onboarding write then stayed NULL
/// forever -> forced re-onboard on a new device. last_active_at +
/// onboarding_completed_at were also written naive-local into timestamptz columns.
///
/// Source-contract (comment-stripped per feedback_source_grep_strip_comments_first)
/// so a refactor that re-drops the field or reverts to a naive write fails here.
String _strip(String s) {
  s = s.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  s = s.replaceAll(RegExp(r'(?<!:)//.*'), ''); // keep https:// intact
  return s;
}

void main() {
  group('onboarding_completed_at durable writer (c4d8a2)', () {
    test('_syncUserProfile syncs onboarding_completed_at (durable writer)', () {
      final src =
          _strip(File('lib/core/services/sync/sync_profile.dart').readAsStringSync());
      expect(
        src.contains("'onboarding_completed_at': p['onboarding_completed_at']"),
        isTrue,
        reason:
            'sync_profile _syncUserProfile MUST sync onboarding_completed_at so the '
            'column has a durable recurring writer (and the self-heal reaches cloud).',
      );
    });

    test('completeOnboarding stamps onboarding_completed_at into the Hive profile (UTC)',
        () {
      final src = _strip(
          File('lib/features/onboarding/providers/onboarding_provider.dart')
              .readAsStringSync());
      expect(
        src.contains(
            "'onboarding_completed_at': DateTime.now().toUtc().toIso8601String()"),
        isTrue,
        reason:
            'completeOnboarding MUST stamp onboarding_completed_at (UTC) into the '
            'Hive profile map so local readers + _syncUserProfile have a value.',
      );
    });

    test('last_active_at cloud writes use UTC (no naive timestamptz write)', () {
      final ob = _strip(
          File('lib/features/onboarding/providers/onboarding_provider.dart')
              .readAsStringSync());
      final ss =
          _strip(File('lib/core/services/sync_service.dart').readAsStringSync());
      expect(
        ob.contains("'last_active_at': DateTime.now().toIso8601String()"),
        isFalse,
        reason: 'last_active_at -> users (timestamptz) must use .toUtc().',
      );
      expect(
        ss.contains("'last_active_at': DateTime.now().toIso8601String()"),
        isFalse,
        reason: 'last_active_at -> users (timestamptz) must use .toUtc().',
      );
    });
  });
}
