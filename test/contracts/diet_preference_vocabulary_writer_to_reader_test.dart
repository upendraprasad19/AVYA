// Diet plan Unit 2a (2026-11-14, docs/plans/diet-food-type.md T2, T5):
// SoT concept `diet_preference_vocabulary`. Every writer of the food type
// stores a FoodType.storageKey, and every reader reads through foodTypeOf.
//
// Behavioural, real Hive + a real ProviderContainer:
//   - UserProfileNotifier.setFoodType (the Diet Plan selector's write door):
//     writes the canonical key, locks only on a real change, rewrites a legacy
//     spelling without a lock, no-op on equal, serialised (two quick taps end
//     with the second), a failed link does not block the next, a call queued
//     across an account change writes nothing, no push/lock when signed out.
//   - DietPlanNotifier (the Nutrition hints): rebuilds after a food-type write
//     from EITHER door and hides a saved plan of another food type.
//   - resolveOnboardingDietPreference (onboarding's default).
//   - AiSnapshotBuilder.buildAiContext (the coach): the canonical key and label.
// PRESENCE (stated): plan_screen.dart's setAnswer literal and Edit Profile's
// wiring (the screens are not pumped here).
//
// Mutations (diagnose table): lock on a spelling-only change; never lock;
// drop the serialisation; drop the account check; stop watching the food
// type in DietPlanNotifier; onboarding default back to 'veg'.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/food_types.dart';
import 'package:icanbefitter/features/ai_coach/services/ai_snapshot_builder.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/nutrition/providers/diet_plan_provider.dart';
import 'package:icanbefitter/features/nutrition/services/diet_plan_catalog.dart';
import 'package:icanbefitter/features/onboarding/providers/onboarding_provider.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../helpers/hive_test_setup.dart';

class _Fx {
  String? uid = 'user-a';

  /// When set, currentUserId answers this from its SECOND read on (the
  /// first read is setFoodType's capture): an account switch while queued.
  String? uidAfterFirstRead;
  int _uidReads = 0;
  int pushes = 0;
  final locks = <List<String>>[];
  final events = <String>[];
  bool throwOnNextPush = false;

  /// When set, the lock call does not finish until this completes.
  Completer<void>? lockGate;

  FoodTypeWriteEffects get effects => FoodTypeWriteEffects(
        currentUserId: () {
          _uidReads++;
          if (uidAfterFirstRead != null && _uidReads > 1) return uidAfterFirstRead;
          return uid;
        },
        pushSnapshot: () {
          pushes++;
          events.add('push');
          if (throwOnNextPush) {
            throwOnNextPush = false;
            throw StateError('push failed');
          }
        },
        lockFields: (f) {
          locks.add(List.of(f));
          events.add('lock');
          return lockGate?.future ?? Future<void>.value();
        },
      );
}

/// Lets the chained lock -> push (fire-and-forget) run.
Future<void> settle() => Future<void>.delayed(Duration.zero);

Map<String, dynamic> _plan(String? foodType) => {
      'id': 'diet_plan_1',
      'created_at': '2026-11-14T08:00:00.000',
      'food_type': ?foodType,
      'meals': [
        {
          'name': 'Lunch',
          'items': [
            {
              'food_id': 'F0019',
              'name': 'Chicken Breast (grilled)',
              'serving_desc': '1 piece',
              'serving_g': 120.0,
              'calories': 198,
              'protein': 37,
              'carbs': 0,
              'fat': 4,
              'category': 'protein',
            },
          ],
        },
      ],
    };

void main() {
  group('resolveOnboardingDietPreference', () {
    test('absent -> non_veg; legacy spellings -> canonical keys', () {
      expect(resolveOnboardingDietPreference({}), 'non_veg');
      expect(resolveOnboardingDietPreference({'diet_preference': null}), 'non_veg');
      expect(resolveOnboardingDietPreference({'diet_preference': 'veg'}), 'veg');
      expect(resolveOnboardingDietPreference({'diet_preference': 'vegetarian'}), 'veg');
      expect(resolveOnboardingDietPreference({'diet_preference': 'non_veg'}), 'non_veg');
    });

    test('PRESENCE: onboarding sets non_veg and calls the resolver', () {
      final plan = File('lib/features/onboarding/screens/plan_screen.dart')
          .readAsStringSync();
      expect(plan, contains("notifier.setAnswer('diet_preference', 'non_veg');"));
      expect(plan, isNot(contains("setAnswer('diet_preference', 'veg')")));
      final prov =
          File('lib/features/onboarding/providers/onboarding_provider.dart')
              .readAsStringSync();
      expect(prov, contains('final dietPreference = resolveOnboardingDietPreference(a);'));
    });
  });

  test('PRESENCE: Edit Profile reads, shows and saves through the vocabulary', () {
    final src = File('lib/features/profile/screens/edit_profile_screen.dart')
        .readAsStringSync();
    expect(src, contains('_foodType = foodTypeOfProfile(profile);'));
    expect(src, contains("'diet_preference': _foodType.storageKey,"));
    expect(src, contains('dietPreference: _foodType.storageKey,'));
    expect(src, contains('originalDietPreference: _originalFoodType.storageKey,'));
    expect(src, contains('FoodTypeChips('));
    expect(src, isNot(contains("'keto'")));
    expect(src, isNot(contains('_dietPreference')));
  });

  group('with Hive', () {
    late Directory tempDir;
    late _Fx fx;
    late ProviderContainer c;

    setUp(() async {
      tempDir = await setUpHiveForTests();
      fx = _Fx();
      UserProfileNotifier.debugFoodTypeEffects = fx.effects;
      c = ProviderContainer(overrides: [
        authUserIdTokenProvider.overrideWithValue(kTestUserId),
      ]);
    });

    tearDown(() async {
      c.dispose();
      UserProfileNotifier.debugFoodTypeEffects = null;
      await tearDownHiveForTests(tempDir);
    });

    Future<void> seed(Object? diet) async {
      await UserRepository.instance.updateProfileFields({
        'full_name': 'T',
        'diet_preference': diet,
      });
    }

    String? stored() =>
        UserRepository.instance.getProfile()?['diet_preference'] as String?;
    UserProfileNotifier notifier() => c.read(userProfileProvider.notifier);

    test('a real change writes the key, pushes the snapshot and locks', () async {
      await seed('non_veg');
      expect(await notifier().setFoodType(FoodType.pescatarian), isTrue);
      await settle();
      expect(stored(), 'pescatarian');
      expect(fx.pushes, 1);
      expect(fx.locks, [
        ['diet_preference']
      ]);
      expect(foodTypeOfProfile(c.read(userProfileProvider)), FoodType.pescatarian);
    });

    test('null (never chosen) -> Non-veg writes non_veg without a lock', () async {
      await seed(null);
      await notifier().setFoodType(FoodType.nonVeg);
      expect(stored(), 'non_veg');
      expect(fx.locks, isEmpty);
    });

    test('a legacy spelling of the same type is rewritten without a lock', () async {
      await seed('vegetarian');
      await notifier().setFoodType(FoodType.veg);
      await settle();
      expect(stored(), 'veg');
      expect(fx.pushes, 1);
      expect(fx.locks, isEmpty);
    });

    test('the same key is a no-op', () async {
      await seed('eggetarian');
      await notifier().setFoodType(FoodType.eggetarian);
      expect(stored(), 'eggetarian');
      expect(fx.pushes, 0);
      expect(fx.locks, isEmpty);
    });

    test('two quick taps are serialised: the second wins, each compares '
        'against what the first wrote', () async {
      await seed('non_veg');
      final a = notifier().setFoodType(FoodType.veg);
      final b = notifier().setFoodType(FoodType.nonVeg);
      await Future.wait([a, b]);
      await settle();
      expect(stored(), 'non_veg');
      // non_veg -> veg (a change) then veg -> non_veg (a change).
      expect(fx.locks.length, 2);
    });

    test('a failed link does not block the next', () async {
      // A spelling-only rewrite pushes synchronously inside the link, so a
      // throwing push fails that link.
      await seed('vegetarian');
      fx.throwOnNextPush = true;
      final a = notifier().setFoodType(FoodType.veg);
      final b = notifier().setFoodType(FoodType.vegan);
      await expectLater(a, throwsStateError);
      expect(await b, isTrue);
      expect(stored(), 'vegan');
    });

    test('a call queued across an account change writes nothing and says so',
        () async {
      await seed('non_veg');
      fx.uidAfterFirstRead = 'user-b'; // switched before the call ran
      expect(await notifier().setFoodType(FoodType.veg), isFalse);
      await settle();
      expect(stored(), 'non_veg');
      expect(fx.pushes, 0);
      expect(fx.locks, isEmpty);
    });

    test('B-pass 5: the snapshot push waits for the lock call to finish', () async {
      await seed('non_veg');
      fx.lockGate = Completer<void>();
      expect(await notifier().setFoodType(FoodType.veg), isTrue,
          reason: 'the write door does not wait on the network');
      await settle();
      expect(fx.events, ['lock'], reason: 'no push before the lock lands');
      fx.lockGate!.complete();
      await settle();
      expect(fx.events, ['lock', 'push']);
    });

    test('B-pass 5: a failed lock call still lets the push go out', () async {
      await seed('non_veg');
      fx.lockGate = Completer<void>();
      final done = notifier().setFoodType(FoodType.vegan);
      await done;
      fx.lockGate!.completeError(StateError('rpc down'));
      await settle();
      expect(fx.events, ['lock', 'push']);
    });

    test('signed out: the value is written, no push and no lock', () async {
      fx.uid = null;
      await seed('non_veg');
      await notifier().setFoodType(FoodType.veg);
      expect(stored(), 'veg');
      expect(fx.pushes, 0);
      expect(fx.locks, isEmpty);
    });

    test('the coach snapshot carries the canonical key and its label',
        () async {
      for (final (stored, key, label) in [
        ('vegetarian', 'veg', 'Veg'),
        (null, 'non_veg', 'Non-veg'),
        ('keto', 'non_veg', 'Non-veg'),
        ('Pescetarian', 'pescatarian', 'Pescatarian'),
        ('eggetarian', 'eggetarian', 'Eggetarian'),
      ]) {
        await seed(stored);
        final profile = AiSnapshotBuilder.instance.buildAiContext()['profile']
            as Map<String, dynamic>;
        expect(profile['diet_preference'], key, reason: '$stored');
        expect(profile['diet_preference_label'], label, reason: '$stored');
      }
    });

    group('DietPlanNotifier (Nutrition hints)', () {
      test('a saved plan of another food type gives no hints; the hints '
          'come back when the food type matches', () async {
        await seed('non_veg');
        await UserRepository.instance.saveDietPlan(_plan('non_veg'));
        final sub = c.listen(dietPlanProvider, (_, _) {});
        expect(c.read(dietPlanProvider).keys, contains('lunch'));

        // The Diet Plan selector's door.
        await notifier().setFoodType(FoodType.veg);
        expect(c.read(dietPlanProvider), isEmpty);

        // Edit Profile's door (a plain profile write through the notifier).
        await notifier().updateProfile({'diet_preference': 'non_veg'});
        expect(c.read(dietPlanProvider).keys, contains('lunch'));
        sub.close();
      });

      test('a plan saved before Unit 2a (no food_type) gives hints only when '
          'its foods fit (B-pass 3)', () async {
        // Chicken, no food_type: fine for Non-veg ...
        await seed('non_veg');
        await UserRepository.instance.saveDietPlan(_plan(null));
        final sub = c.listen(dietPlanProvider, (_, _) {});
        expect(c.read(dietPlanProvider).keys, contains('lunch'));
        // ... not for Vegan (the food box has no row for it here, so it
        // cannot be shown to fit either).
        await notifier().updateProfile({'diet_preference': 'vegan'});
        expect(c.read(dietPlanProvider), isEmpty);
        sub.close();
      });
    });
  });

  test('savedPlanMatchesFoodType', () {
    // A legacy plan (no food_type) is judged by its foods (B-pass 3).
    Map<String, dynamic>? chicken(String _) =>
        {'id': 'F0019', 'name': 'Chicken Breast (grilled)', 'is_veg': false, 'is_vegan': false};
    Map<String, dynamic>? dal(String _) =>
        {'id': 'F0019', 'name': 'Moong Dal', 'is_veg': true, 'is_vegan': true};
    expect(savedPlanMatchesFoodType(_plan(null), FoodType.nonVeg), isTrue);
    expect(savedPlanMatchesFoodType(_plan(null), FoodType.veg, rowOf: chicken), isFalse);
    expect(savedPlanMatchesFoodType(_plan(null), FoodType.pescatarian, rowOf: chicken), isFalse);
    expect(savedPlanMatchesFoodType(_plan(null), FoodType.veg, rowOf: dal), isTrue);
    expect(savedPlanMatchesFoodType(_plan(null), FoodType.vegan, rowOf: dal), isTrue);
    expect(savedPlanMatchesFoodType(_plan(null), FoodType.veg, rowOf: (_) => null), isFalse,
        reason: 'a food the box does not hold cannot be shown to fit');
    expect(savedPlanMatchesFoodType(_plan('veg'), FoodType.veg), isTrue);
    expect(savedPlanMatchesFoodType(_plan('vegetarian'), FoodType.veg), isTrue);
    expect(savedPlanMatchesFoodType(_plan('non_veg'), FoodType.veg), isFalse);
    expect(savedPlanMatchesFoodType(_plan('eggetarian'), FoodType.pescatarian),
        isFalse);
  });

  test('savedPlanMatchesFoodType judges a legacy item by its catalog family',
      () {
    // F0021 is the catalog's boiled egg (DietFamily.egg), F0024 a fish row
    // (DietFamily.fish). Both rows are is_veg false, so only the family
    // admits them: without it every egg or fish item fails the Veg rule.
    Map<String, dynamic> legacy(String id) => {
          'id': 'diet_plan_legacy',
          'meals': [
            {
              'name': 'Breakfast',
              'items': [
                {'food_id': id, 'name': id},
              ],
            },
          ],
        };
    Map<String, dynamic>? nonVegRow(String id) =>
        {'id': id, 'name': id, 'is_veg': false, 'is_vegan': false};
    expect(dietCatalogFamily('F0021'), DietFamily.egg);
    expect(dietCatalogFamily('F0024'), DietFamily.fish);
    expect(savedPlanMatchesFoodType(legacy('F0021'), FoodType.eggetarian,
        rowOf: nonVegRow), isTrue);
    expect(savedPlanMatchesFoodType(legacy('F0021'), FoodType.pescatarian,
        rowOf: nonVegRow), isTrue);
    expect(savedPlanMatchesFoodType(legacy('F0024'), FoodType.pescatarian,
        rowOf: nonVegRow), isTrue);
    expect(savedPlanMatchesFoodType(legacy('F0024'), FoodType.eggetarian,
        rowOf: nonVegRow), isFalse);
    expect(savedPlanMatchesFoodType(legacy('F0021'), FoodType.veg,
        rowOf: nonVegRow), isFalse);
  });
}
