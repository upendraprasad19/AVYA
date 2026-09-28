import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Locks the public API surface of `SyncService` during the part-file
/// refactor (refactor/sync-service-part-split, 2026-05-13).
///
/// Scans `lib/core/services/sync_service.dart` AND every file under
/// `lib/core/services/sync/` for `Future<...>` / `Stream<...>` / `void`
/// methods on either `class SyncService` or `extension X on SyncService`
/// that DO NOT start with an underscore. The sorted set of names must
/// exactly match `expectedPublicApi`.
///
/// If a method is renamed or accidentally privatised during the refactor,
/// this test fails. If a new public method is added (e.g. by a parallel
/// bug-fix batch landing mid-refactor), update `expectedPublicApi` after
/// confirming the addition is intentional.
void main() {
  group('SyncService public API snapshot (refactor lock)', () {
    test('public method list is unchanged', () {
      const expectedPublicApi = <String>{
        'cancelInflightRestore',
        // Obs 4 (2026-06-05) — bg-restore home-refresh tick bump (intentional).
        'bumpRestoreCompleted',
        'checkAndSync',
        'drainTelemetryQueue',
        // H1a (Unit H, 2026-06-27) — app-pause best-effort flush.
        'flushPendingSyncs',
        'initQueue',
        'pullRecentCrossChannelLogs',
        'pushSnapshot',
        // H1b Part B1 (Unit H, 2026-06-27) — non-coalesced variant for the
        // eager/durable callers (onboarding first-context, checkAndSync backstop).
        'pushSnapshotNow',
        // Unit 3b round-1-review P1 fix (2026-07-30, diagnose e6b9c4) —
        // UserRepository.syncOnboardingToSupabase's onboarding-time explicit-
        // params path into update_user_progress_snapshot, replacing a THIRD
        // unprotected raw-upsert writer to user_progress found by review.
        'pushOnboardingProgressSnapshot',
        'reportSyncFailure',
        'restoreFromCloud',
        'restoreFromCloudForUser',
        'restoreLightweightAlways',
        'subscribeToRealtimeSync',
        'syncCoachMemoryNow',
        'syncCommunityItems',
        'syncCustomItemsNow',
        'syncFreezes',
        'syncMeasurementsNow',
        'syncNotificationsInboxEntry',
        'syncNutritionData',
        // H1a (Unit H) — non-coalesced variant for awaited callers.
        'syncNutritionDataNow',
        'syncProfileNow',
        'syncProgressNow',
        'syncSavedDietPlan',
        'syncSavedMealsNow',
        'syncSleepNow',
        'syncReadinessNow', // ⑥ 6-C
        'pushReadinessForSyncDomain', // ⑥ 6-C
        'restoreReadinessForSyncDomain', // ⑥ 6-C
        'syncWeightNow',
        'syncWorkoutData',
        // H1a (Unit H) — non-coalesced variant for awaited callers.
        'syncWorkoutDataNow',
        'unsubscribeRealtime',
        'weeklyFullSync',
        // Getters that look like methods (counted as public API surface):
        'healthSyncDone',
        'onRestoreComplete',
        // Tech-debt audit 2026-05-20 / A6 added SyncDomain wrappers
        // (per-domain push + restore atomic entrypoints) so feature
        // owners can fire single-domain sync without going through
        // checkAndSync. Each `pushXForSyncDomain` / `restoreXForSyncDomain`
        // mirrors an internal _syncX / _restoreX helper with the
        // SyncFlags guard wrapped. Plus 2 test-only dispatchers used
        // by the SyncDomain integration tests.
        'dispatchDomainPushesForTests',
        'dispatchDomainRestoresForTests',
        // Push wrappers — one per domain (28 currently).
        'pushCoachInteractionsForSyncDomain',
        'pushCoachMemoryForSyncDomain',
        'pushCustomItemsForSyncDomain',
        'pushExerciseLogsForSyncDomain',
        'pushMeasurementsForSyncDomain',
        'pushNutritionLogsForSyncDomain',
        'pushSavedMealsForSyncDomain',
        'pushScheduleCompletionsForSyncDomain',
        'pushScheduledWorkoutsForSyncDomain',
        'pushSleepLogsForSyncDomain',
        'pushStepsLogsForSyncDomain',
        'pushStreaksForSyncDomain',
        'pushUrineColorLogsForSyncDomain',
        'pushUserPreferencesForSyncDomain',
        'pushUserProfileForSyncDomain',
        'pushUserProgressForSyncDomain',
        'pushWaterLogsForSyncDomain',
        'pushWeightLogsForSyncDomain',
        'pushWorkoutLogsForSyncDomain',
        'pushWorkoutPlanForSyncDomain',
        'pushWorkoutTemplatesForSyncDomain',
        // Restore wrappers — one per domain.
        'restoreCoachInteractionsForSyncDomain',
        'restoreCoachMemoryForSyncDomain',
        'restoreCustomItemsForSyncDomain',
        'restoreExerciseLogsForSyncDomain',
        'restoreFreezesForSyncDomain',
        'restoreMeasurementsForSyncDomain',
        'restoreNotificationsInboxForSyncDomain',
        'restoreNutritionLogsForSyncDomain',
        'restoreRankPromotionsForSyncDomain',
        'restoreReferralCodesForSyncDomain',
        'restoreReferralRedemptionsForSyncDomain',
        'restoreSavedDietPlanForSyncDomain',
        'restoreSavedMealsForSyncDomain',
        'restoreScheduleCompletionsForSyncDomain',
        'restoreScheduledWorkoutsForSyncDomain',
        // e8f4a3 round-1 fix (2026-09-18) — @visibleForTesting seam for the
        // terminal-row restore-merge arm (preFetched injection sentinel);
        // delegates to _restoreScheduledWorkouts, production path unchanged.
        'restoreScheduledWorkoutsForTest',
        'restoreSleepLogsForSyncDomain',
        'restoreStepsLogsForSyncDomain',
        'restoreStreaksForSyncDomain',
        'restoreUserPreferencesForSyncDomain',
        'restoreUserProfileForSyncDomain',
        'restoreUserProgressForSyncDomain',
        'restoreWaterLogsForSyncDomain',
        'restoreWeightLogsForSyncDomain',
        'restoreWorkoutLogsForSyncDomain',
        'restoreWorkoutPlanForSyncDomain',
        // T21 (day-swapper-sync-load) + OI-252 — test seam: injects
        // preFetched user_progress rows (+ an optional pre-resolved
        // deleted-template-id set) so the L1/L3 restore-merge (spec sec 5.7)
        // and the ghost-day filter are behaviorally testable without a live
        // Supabase query; delegates to _restoreWorkoutPlan, production path
        // unchanged.
        'restoreWorkoutPlanForTest',
        'restoreWorkoutTemplatesForSyncDomain',
        // OI-252 B-pass finding 2 (2026-09-27) — test seam: injects
        // preFetched workout_templates rows so the legacy-key-migrator gate
        // added to _restoreWorkoutTemplates is behaviorally testable without
        // a live Supabase query for the row read itself; delegates to
        // _restoreWorkoutTemplates, production path unchanged.
        'restoreWorkoutTemplatesForTest',
        // Hermes h7F2 (diagnose f1c6b4) — test seams injecting
        // user_progress / user_profile+users rows so the per-launch
        // write-if-changed skip is behaviorally testable; delegate to the
        // private restores, production path unchanged.
        'restoreUserProgressForTest',
        'restoreUserProfileForTest',
        // Day-swapper + sync-load Task 19 — test-only wrapper for the
        // onboarding-replay now()-fallback fix (no existing SyncDomain entry
        // point for this one-shot migration replay).
        'replayPendingOnboardingSyncForTest',
      };

      final files = <File>[
        File('lib/core/services/sync_service.dart'),
        ...Directory('lib/core/services/sync')
            .let((dir) => dir.existsSync() ? dir.listSync() : <FileSystemEntity>[])
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            // Only the `part of` files ARE the SyncService library. A standalone
            // library in the same directory (sync_skip_index.dart — the
            // SyncSkipIndex helper, day-swapper + sync-load Task 4) has its own
            // public API, and counting it here would read pushIfChanged/commit
            // as SyncService methods.
            .where((f) => RegExp(r'^part of ', multiLine: true)
                .hasMatch(f.readAsStringSync())),
      ];
      // The filter must never drop the SyncService library itself: every file
      // in sync/ except the standalone helper is a part file.
      expect(files.length, greaterThanOrEqualTo(8),
          reason: 'sync_service.dart + its 7 part files must all be scanned');

      // Match instance method signatures at exactly 2-space indent
      // (class instance methods + extension methods). The pattern requires the
      // RETURN TYPE immediately after the 2-space indent, so it excludes two
      // classes by construction (NOT by indent):
      //   (a) `static `-prefixed members — the `^  static …` text never matches
      //       `^  (Future|Stream|void)` (e.g. the H1b @visibleForTesting static
      //       schedPayloadFingerprint);
      //   (b) non-Future/Stream/void return types (String/bool/Map/int).
      // (Known blind spot, acceptable for now: a future PUBLIC `static Future<…>`
      // would also be excluded — add an explicit static branch here if one is
      // ever introduced as tracked public API.) Also excludes nested helper
      // functions (4+ space indent).
      // Matches: `Future<...>` / `Stream<...>` / `void` returns +
      //          optional `get ` for getters + name + ( or = .
      final methodPattern = RegExp(
        r'^  (?:Future<[^>]*>|Stream<[^>]*>|void)\s+(?:get\s+)?([a-zA-Z]\w*)\s*[\(\=]',
        multiLine: true,
      );

      final found = <String>{};
      for (final f in files) {
        final src = f.readAsStringSync();
        for (final m in methodPattern.allMatches(src)) {
          final name = m.group(1)!;
          if (name.startsWith('_')) continue;
          found.add(name);
        }
      }

      expect(found, equals(expectedPublicApi),
          reason:
              'SyncService public API surface changed. If this is '
              'intentional (new public method added), update '
              'expectedPublicApi in this test after confirming the '
              'change is reviewed. If this is unintentional (method '
              'accidentally renamed/privatised during refactor), '
              'revert the rename.');
    });
  });
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
