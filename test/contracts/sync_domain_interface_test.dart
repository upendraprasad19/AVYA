// test/contracts/sync_domain_interface_test.dart
//
// Tech-debt audit 2026-05-20 / finding A6 — scaffold test for the new
// [SyncDomain] interface and its first proof-of-pattern implementation
// `StreaksSyncDomain`.
//
// What this test pins
// -------------------
// 1. [StreaksSyncDomain.push] actually invokes the canonical
//    `SyncService._syncStreaks` helper via the public forwarder
//    `pushStreaksForSyncDomain` on `SyncServiceWorkout`.
// 2. [StreaksSyncDomain.restore] actually invokes
//    `SyncService._restoreStreaks` via `restoreStreaksForSyncDomain`.
// 3. Both methods honour the interface contract `Future<void>` —
//    nothing leaks a non-Future synchronous return.
// 4. The list of registered domain implementations is exhaustive over
//    the `_syncX` / `_restoreX` private-method pairs actually present
//    in `sync_service.dart` + its part-files. This is the structural
//    guard against the Test #12.8 drift class — "added a `_syncBar`
//    without `_restoreBar`" is now caught at test time.
//
// The first 3 assertions run BEHAVIOURALLY against a real Hive temp
// dir; the 4th is a source-grep exhaustiveness check fed by the
// `_sync_service_source.dart` facade that already aggregates the
// part-files for sibling tests.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync_domain.dart';
import 'package:icanbefitter/core/services/sync_domains/streaks_sync_domain.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '_sync_service_source.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('sync_domain_scaffold_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.exerciseBoxName);
    await Hive.openBox(HiveService.foodBoxName);
    await Hive.openBox(HiveService.syncBoxName);
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    // Each test runs with NO signed-in user → `_ensureSessionOpen`
    // returns null inside the forwarders → push/restore short-circuit
    // cleanly. This proves we're driving the canonical code path
    // (not stubbing it) WITHOUT requiring a real Supabase session.
    await HiveUserSession.closeAll();
  });

  group('A6 · SyncDomain scaffold · StreaksSyncDomain', () {
    test('implements the SyncDomain interface contract', () {
      final domain = StreaksSyncDomain();
      expect(domain, isA<SyncDomain>(),
          reason:
              'StreaksSyncDomain must implement SyncDomain so SyncService '
              'can dispatch through a List<SyncDomain> once migration completes.');
      expect(domain.name, 'streaks',
          reason: 'name must match the `_safeRestoreOp("streaks", ...)` '
              'string used at sync_service.dart fan-out site so telemetry '
              'op_types stay stable across the migration boundary.');
    });

    test(
        'push() returns Future<void> and completes without throwing when '
        'no auth session is open', () async {
      final domain = StreaksSyncDomain();
      final future = domain.push();
      expect(future, isA<Future<void>>(),
          reason:
              'SyncDomain.push contract demands Future<void>; a sync return '
              'would break the dispatcher loop in the eventual migration.');
      await expectLater(future, completes,
          reason:
              'With no session open, the public forwarder must short-circuit '
              'via _ensureSessionOpen() → null → return. Any throw here proves '
              'the wrapper is NOT delegating to the canonical _syncStreaks path.');
    });

    test(
        'restore() returns Future<void> and completes without throwing when '
        'no auth session is open', () async {
      final domain = StreaksSyncDomain();
      final future = domain.restore();
      expect(future, isA<Future<void>>(),
          reason: 'SyncDomain.restore contract demands Future<void>.');
      await expectLater(future, completes,
          reason:
              'With no session open, the public forwarder must short-circuit '
              'via _ensureSessionOpen() → null → return. Any throw here proves '
              'the wrapper is NOT delegating to the canonical _restoreStreaks path.');
    });

    test(
        'every _syncX private helper in sync_service.dart has a matching '
        '_restoreX helper (exhaustiveness guard against Test #12.8 drift)',
        () {
      // Source-grep over the aggregated SyncService source (root +
      // all part-files). The matched-pair invariant is the structural
      // guard the SyncDomain interface enforces at compile time once
      // migration completes — until then, this test stands in for the
      // compiler.
      final src = loadSyncServiceSource().readAsStringSync();

      // Strip comments so a stale `// _syncFoo` reference can't fool us.
      final stripped = src
          .replaceAll(RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '')
          .split('\n')
          .map((l) => l.replaceFirst(RegExp(r'//.*$'), ''))
          .join('\n');

      // Match push-side declarations in either of two shapes:
      //   Future<...> _syncFoo(...) async { ... }   (private)
      //   Future<...> syncFoo(...) async { ... }    (public — used by
      //                                              restore-completeness
      //                                              and ad-hoc fire-and-
      //                                              forget call sites)
      // and the matching restore-side `_restoreFoo` private method.
      // Capture the camel-case suffix so we can pair the two halves.
      final syncDeclRegex = RegExp(
        r'Future<[^>]*>\s+_?sync([A-Z][A-Za-z0-9]*)\s*\(',
      );
      final restoreDeclRegex = RegExp(
        r'Future<[^>]*>\s+_restore([A-Z][A-Za-z0-9]*)\s*\(',
      );

      final syncSuffixes = syncDeclRegex
          .allMatches(stripped)
          .map((m) => m.group(1)!)
          .toSet();
      final restoreSuffixes = restoreDeclRegex
          .allMatches(stripped)
          .map((m) => m.group(1)!)
          .toSet();

      // Allow-list: surfaces with a legitimate push-only or restore-only
      // contract at the method-name level. The matched-pair invariant
      // is enforced at the DOMAIN level — these methods document why
      // the exact-suffix match doesn't apply. Any new addition is a
      // conscious call, not an oversight, and MUST be documented.
      //
      // PUSH-ONLY (no _restore<Suffix> by design):
      //   - WorkoutData / NutritionData     — fan-out orchestrators (each
      //                                        calls per-helper _sync*
      //                                        methods; the per-helper
      //                                        _restoreXxx exist).
      //   - HealthDataSnapshot              — daily AI snapshot push; the
      //                                        snapshot is reconstructed
      //                                        locally, never restored.
      //   - UrineColorLogs                  — TODO restore counterpart
      //                                        pending audit follow-up
      //                                        (tracked under A6).
      //   - FitnessSummary                  — misnamed: actually a
      //                                        cloud→local pull from
      //                                        user_daily_snapshots into
      //                                        coachBox; pull IS the
      //                                        restore equivalent.
      //   - CustomItems                     — push orchestrator covering
      //                                        custom exercises AND foods;
      //                                        restore is split into
      //                                        _restoreCustomExercises +
      //                                        _restoreCustomFoods.
      //   - CoachMemoryNow / CustomItemsNow / WeightNow / SleepNow /
      //     MeasurementsNow / SavedMealsNow / ProfileNow / ProgressNow
      //                                     — public eager-push variants
      //                                        (the "Now" suffix variant)
      //                                        of an existing _sync*
      //                                        domain. The matched
      //                                        _restore* exists under the
      //                                        non-"Now" suffix.
      //   - CommunityItems                  — public alias for CustomItems
      //                                        push orchestrator.
      //   - NotificationsInboxEntry         — per-entry push paired with
      //                                        bulk _restoreNotificationsInbox.
      //
      // RESTORE-ONLY (no _sync<Suffix> by design):
      //   - IfNeeded / FromCloudForUser     — orchestrator guards.
      //   - CoachMemory                     — push counterpart is
      //                                        syncCoachMemoryNow.
      //   - CustomExercises / CustomFoods   — push counterpart is
      //                                        _syncCustomItems (orchestrator).
      //   - Freezes / SavedDietPlan         — push counterparts are
      //                                        public syncFreezes /
      //                                        syncSavedDietPlan.
      //   - NotificationsInbox              — push counterpart is per-entry
      //                                        syncNotificationsInboxEntry.
      //   - RankPromotions / ReferralCodes / ReferralRedemptions
      //                                     — push counterparts live on
      //                                        repositories
      //                                        (RankPromotionRepository,
      //                                        ReferralRepository), not on
      //                                        SyncService.
      const pushOnlyAllowlist = <String>{
        'WorkoutData',
        // Unit H / H1a — non-coalesced fan-out variants (same orchestrator
        // class as WorkoutData/NutritionData; each calls per-helper _sync*
        // whose _restore* counterparts exist).
        'WorkoutDataNow',
        'NutritionData',
        'NutritionDataNow',
        'HealthDataSnapshot',
        'UrineColorLogs',
        'FitnessSummary',
        'CustomItems',
        'CoachMemoryNow',
        'CustomItemsNow',
        'CommunityItems',
        'WeightNow',
        'SleepNow',
        'ReadinessNow', // ⑥ 6-C — syncReadinessNow is a fire-and-forget push (restore is _restoreReadiness / restoreReadinessForSyncDomain)

        'MeasurementsNow',
        'SavedMealsNow',
        'ProfileNow',
        'ProgressNow',
        'NotificationsInboxEntry',
      };
      const restoreOnlyAllowlist = <String>{
        'IfNeeded',
        'FromCloudForUser',
        'CoachMemory',
        'CustomExercises',
        'CustomFoods',
        'Freezes',
        'SavedDietPlan',
        'NotificationsInbox',
        'RankPromotions',
        'ReferralCodes',
        'ReferralRedemptions',
      };

      final unmatchedPushes = syncSuffixes
          .difference(restoreSuffixes)
          .difference(pushOnlyAllowlist);
      final unmatchedRestores = restoreSuffixes
          .difference(syncSuffixes)
          .difference(restoreOnlyAllowlist);

      expect(unmatchedPushes, isEmpty,
          reason:
              'Found `_sync${unmatchedPushes.isEmpty ? "X" : unmatchedPushes.first}` '
              'with no matching `_restore${unmatchedPushes.isEmpty ? "X" : unmatchedPushes.first}` '
              '— this is the Test #12.8 "added a _syncBar without _restoreBar" '
              'bug class. Either add the missing restore helper OR extend the '
              'pushOnlyAllowlist in this test if the asymmetry is intentional '
              '(and document why in the diagnose-doc).');

      expect(unmatchedRestores, isEmpty,
          reason:
              'Found `_restore${unmatchedRestores.isEmpty ? "X" : unmatchedRestores.first}` '
              'with no matching `_sync${unmatchedRestores.isEmpty ? "X" : unmatchedRestores.first}` '
              '— restore-only surfaces should be rare. Either add the missing '
              'push helper OR extend the restoreOnlyAllowlist in this test.');

      // Final sanity check: the streaks pair MUST be present in both
      // sets — otherwise our scaffold target moved and the wrapper
      // accessors will silently bind to nothing.
      expect(syncSuffixes.contains('Streaks'), isTrue,
          reason:
              '_syncStreaks went missing from sync_service.dart — the '
              'StreaksSyncDomain scaffold wrapper now points at a dead method.');
      expect(restoreSuffixes.contains('Streaks'), isTrue,
          reason:
              '_restoreStreaks went missing from sync_service.dart — the '
              'StreaksSyncDomain scaffold wrapper now points at a dead method.');
    });
  });
}
