@Timeout(Duration(minutes: 3))
library;

// The first-use ⇄/⇅ hint flag (docs/plans/active-workout-swap-move.md Task 3)
// is per ACCOUNT and device-local: registered in
// UserConfigMigrator.userScopedKeys, written through MigratedKey into the
// user's box (never the shared configBox), and gone after
// UserRepository.clearAllData() — so a second account on the same phone, and
// the same account after a sign-out/in, sees the hint again.
//
// The precondition is a write-and-read-back, so a write that never landed
// cannot make the "absent" assertions vacuous.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/user_config_migrator.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/services/swap_move_hint.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../helpers/hive_test_setup.dart';

ExerciseData ex(String name) => ExerciseData(
    name: name, sets: '3', reps: '8', weight: '0kg', rest: '90s',
    loggingType: 'weight_reps');

void main() {
  group('storage', () {
    late Directory tempDir;
    setUp(() async => tempDir = await setUpHiveForTests());
    tearDown(() => tearDownHiveForTests(tempDir));

    test('the key is registered as user-scoped', () {
      expect(kSwapMoveHintSeenKey, 'has_seen_swap_move_hint');
      expect(UserConfigMigrator.userScopedKeys, contains(kSwapMoveHintSeenKey));
    });

    test('marked: lands in the USER box, not configBox; gone after clear',
        () async {
      expect(swapMoveHintSeen(), isFalse);
      await markSwapMoveHintSeen();

      // Precondition: the write is observable where it should be.
      expect(HiveService.instance.userBox.get(kSwapMoveHintSeenKey), isTrue);
      expect(HiveService.instance.configBox.containsKey(kSwapMoveHintSeenKey),
          isFalse);
      expect(swapMoveHintSeen(), isTrue);

      final result = await UserRepository.instance.clearAllData();
      expect(result.isClean, isTrue, reason: '$result');
      expect(HiveService.instance.userBox.containsKey(kSwapMoveHintSeenKey),
          isFalse);
      expect(swapMoveHintSeen(), isFalse,
          reason: 'the next account (or a re-login) sees the hint again');
    });
  });

  group('shouldShowSwapMoveHint (truth table)', () {
    final two = ActiveWorkoutData(exercises: [ex('A'), ex('B')]);

    bool show(ActiveWorkoutData d,
            {bool seen = false, bool dismissed = false}) =>
        shouldShowSwapMoveHint(
            seen: seen, dismissedThisSession: dismissed, data: d);

    test('two not-done, nothing checked: shown', () {
      expect(show(two), isTrue);
    });
    test('seen or dismissed this session: hidden', () {
      expect(show(two, seen: true), isFalse);
      expect(show(two, dismissed: true), isFalse);
    });
    test('a single exercise has nowhere to move: hidden', () {
      expect(show(ActiveWorkoutData(exercises: [ex('A')])), isFalse);
    });
    test('any checked set, a warm-up included: hidden', () {
      expect(
          show(two.copyWith(
              checkedSets: const {'0-0': true},
              warmUpSets: const {'0-0': true})),
          isFalse,
          reason: 'completedSets ignores warm-ups; the hint must not');
    });
    test('superset-grouping mode or review mode (⇅ hidden): hidden', () {
      expect(show(two.copyWith(isSupersetGroupMode: true)), isFalse);
      expect(show(two.copyWith(isSaved: true)), isFalse);
    });
  });
}
