// test/sync/merge_rpc_params_preferring_non_null_test.dart
//
// BEHAVIORAL test for `SyncService.mergeRpcParamsPreferringNonNull` (B-pass
// round-3, 2026-07-30, Finding 1). This is the silent-data-loss guard for
// `_retrySyncUserProgressOnceAfterConflict` (sync_profile.dart): on a
// version-conflict retry, the helper rebuilds RPC params from a fresh Hive
// read and merges them with the original caller-supplied params. The FIRST
// version of that fix was all-or-nothing (fresh Hive present -> use ONLY
// its fields) and silently dropped `p_detected_experience_level` for the
// onboarding-time caller, whose progressData carries that field but whose
// Hive `progress` map never does (onboarding_provider.dart:471-478's
// saveProgress writes only 6 fields, none of them detected_experience_level).
//
// This is the behavioral_test_path for that merge contract — it fails if
// the per-field-preference regresses back to an all-or-nothing swap, even
// though the source text would still look plausible on a grep
// (feedback_source_grep_false_confidence).
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

void main() {
  group('mergeRpcParamsPreferringNonNull — per-field merge contract', () {
    test('non-null preferred value wins over a non-null fallback value', () {
      final merged = SyncService.mergeRpcParamsPreferringNonNull(
        {'p_current_phase': 3},
        {'p_current_phase': 1},
      );
      expect(merged['p_current_phase'], 3);
    });

    test('null preferred value falls back to the fallback value', () {
      final merged = SyncService.mergeRpcParamsPreferringNonNull(
        {'p_detected_experience_level': null},
        {'p_detected_experience_level': 'intermediate'},
      );
      expect(merged['p_detected_experience_level'], 'intermediate',
          reason: 'Finding-1 regression: a fresh-Hive rebuild that does not '
              'carry this field (null) must fall back to the ORIGINAL '
              'caller-supplied value, never silently resend null for a '
              'field the retry source simply does not track.');
    });

    test(
        'onboarding retry scenario: fresh-Hive map missing '
        'detected_experience_level does not drop the original answer', () {
      // Mirrors the real shapes: _buildUserProgressRpcParams(freshHiveMap)
      // omits p_detected_experience_level (null) because Hive's onboarding
      // write never populated it; the ORIGINAL rpcParams (from
      // pushOnboardingProgressSnapshot's caller-supplied progressData) has
      // the real answer captured at onboarding time.
      final freshFromHive = <String, dynamic>{
        'p_current_phase': 1,
        'p_current_week': 1,
        'p_detected_experience_level': null,
        'p_total_workouts_done': 0,
      };
      final originalRpcParams = <String, dynamic>{
        'p_current_phase': 1,
        'p_current_week': 1,
        'p_detected_experience_level': 'beginner',
        'p_total_workouts_done': 0,
      };

      final merged = SyncService.mergeRpcParamsPreferringNonNull(
        freshFromHive,
        originalRpcParams,
      );

      expect(merged['p_detected_experience_level'], 'beginner',
          reason: 'must not silently regress the onboarding answer to null');
      expect(merged['p_current_phase'], 1);
      expect(merged['p_total_workouts_done'], 0);
    });

    test('both null → result stays null for that key (no fabricated value)',
        () {
      final merged = SyncService.mergeRpcParamsPreferringNonNull(
        {'p_last_workout_date': null},
        {'p_last_workout_date': null},
      );
      expect(merged['p_last_workout_date'], isNull);
    });

    test('output key set is driven by fallback, not preferred', () {
      // _syncUserProgress's own retry always builds both maps from the same
      // helper (_buildUserProgressRpcParams), so key sets match in
      // practice — but the merge's actual contract (documented here so it
      // can't silently change) is: iterate fallback's keys, so a key
      // present ONLY in preferred is dropped, and a key present ONLY in
      // fallback survives with fallback's value.
      final merged = SyncService.mergeRpcParamsPreferringNonNull(
        {'only_in_preferred': 'x', 'shared': 'preferred-value'},
        {'only_in_fallback': 'y', 'shared': null},
      );
      expect(merged.containsKey('only_in_preferred'), isFalse);
      expect(merged['only_in_fallback'], 'y');
      expect(merged['shared'], 'preferred-value');
    });

    test('empty fallback → empty result regardless of preferred contents',
        () {
      final merged = SyncService.mergeRpcParamsPreferringNonNull(
        {'p_current_phase': 5},
        <String, dynamic>{},
      );
      expect(merged, isEmpty);
    });
  });
}
