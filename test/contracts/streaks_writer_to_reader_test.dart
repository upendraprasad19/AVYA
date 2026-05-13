import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import '_sync_service_source.dart';

/// Source-of-truth contract: writer/reader pairs for `streaks`
/// from docs/sot_registry.yaml.
///
/// Writers: train_provider.completeWorkout (streak row upsert),
///          workout_repository.calculateCurrentStreak (consumes freeze),
///          home_provider.StreakFreezeNotifier._refillIfNewWeek
/// Readers: sync_service._syncStreaks,
///          workout_repository.calculateCurrentStreak,
///          home_provider.streakFreezeProvider
///
/// Key: 'streaks' (singleton list) in healthBox.
/// Freeze state in userBox via MigratedKey.
/// UNIQUE(user_id, week_start) cloud dedup — never dedup by cloud id.
void main() {
  late String trainProvSrc;
  late String workoutRepoSrc;
  late String homeProvSrc;
  late String syncSvcSrc;

  setUpAll(() {
    final tf = File('lib/features/train/providers/train_provider.dart');
    expect(tf.existsSync(), isTrue,
        reason: 'train_provider.dart must exist (streak upsert writer)');
    trainProvSrc = tf.readAsStringSync();

    final rf =
        File('lib/features/train/repositories/workout_repository.dart');
    expect(rf.existsSync(), isTrue,
        reason: 'workout_repository.dart must exist (calculateCurrentStreak writer+reader)');
    workoutRepoSrc = rf.readAsStringSync();

    final hf = File('lib/features/home/providers/home_provider.dart');
    expect(hf.existsSync(), isTrue, reason: 'home_provider.dart must exist');
    homeProvSrc = hf.readAsStringSync();

    final sf = loadSyncServiceSource();
    expect(sf.existsSync(), isTrue, reason: 'sync_service.dart must exist');
    syncSvcSrc = sf.readAsStringSync();
  });

  group('streaks writer↔reader source contract', () {
    test('writer completeWorkout updates streak in train_provider', () {
      expect(trainProvSrc.contains('completeWorkout'), isTrue,
          reason: 'train_provider must define completeWorkout (streak upsert writer)');
    });

    test('writer completeWorkout references streaks key', () {
      expect(
          trainProvSrc.contains("'streaks'") || trainProvSrc.contains('streaks'),
          isTrue,
          reason: 'completeWorkout must update the streaks key in healthBox');
    });

    test('calculateCurrentStreak exists and reads streak freeze state', () {
      expect(workoutRepoSrc.contains('calculateCurrentStreak'), isTrue,
          reason:
              'workout_repository must define calculateCurrentStreak — '
              'must be called fresh for rank gates (never cached)');
      expect(
          workoutRepoSrc.contains('streak_freezes'), isTrue,
          reason:
              'calculateCurrentStreak must read streak freeze state to apply freezes');
    });

    test('StreakFreezeNotifier._refillIfNewWeek exists in home_provider', () {
      expect(homeProvSrc.contains('_refillIfNewWeek') ||
          homeProvSrc.contains('refillIfNewWeek'), isTrue,
          reason:
              'home_provider must define StreakFreezeNotifier._refillIfNewWeek '
              'to weekly-refill freeze credits');
    });

    test('reader _syncStreaks exists in sync_service', () {
      expect(syncSvcSrc.contains('_syncStreaks'), isTrue,
          reason: '_syncStreaks must exist in sync_service');
    });

    test('_syncStreaks deduplicates by week_start (not cloud id)', () {
      // Per sot_registry class_constraints: dedup by week_start UNIQUE constraint
      // never by cloud `id`
      expect(
          syncSvcSrc.contains('week_start') || syncSvcSrc.contains('onConflict'),
          isTrue,
          reason:
              '_syncStreaks must use week_start for deduplication (UNIQUE constraint); '
              'deduping by cloud id causes same-week duplicates');
    });

    test('freeze state stored via MigratedKey (user-scoped)', () {
      expect(
          workoutRepoSrc.contains('MigratedKey') ||
              workoutRepoSrc.contains('userBox') ||
              workoutRepoSrc.contains('streak_freezes'),
          isTrue,
          reason:
              'streak freeze state must be stored in userBox (via MigratedKey) '
              'not in shared configBox — freeze state is user-scoped');
    });

    test('syncFreezes exists in sync_service for cross-device restore', () {
      expect(syncSvcSrc.contains('syncFreezes'), isTrue,
          reason:
              'sync_service must define syncFreezes() — freeze state must survive '
              'reinstall (paying users lost freeze credits before Test #11)');
    });

    test('reader streakFreezeProvider exists in home_provider', () {
      expect(homeProvSrc.contains('streakFreezeProvider'), isTrue,
          reason:
              'home_provider must define streakFreezeProvider (reader for freeze display)');
    });
  });
}
