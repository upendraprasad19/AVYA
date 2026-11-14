// Diet plan Unit 3a (2026-11-14, docs/plans/diet-strategy.md §4 tests 2b, 3,
// 4, 5, 9): SoT concept `diet_strategy_targets`.
//
// Behavioural, real Hive + a real ProviderContainer + the real
// subscriptionInfoProvider (PRO comes from the Hive entitlement keys, read by
// the pure proStateSnapshot):
//   2b ship-dark identity: with the flag at its 3a default (off) a profile
//      holding `diet_strategy: keto` reads exactly like before 3a in every
//      reader (macroTargetsProvider, DailyNutritionData, Home summary, the
//      coach snapshot: no new keys), and a PRO flip does not even rebuild
//      the providers (no new watches).
//   3  writer to reader: setDietStrategy(keto) writes ONE field; every reader
//      shows keto carbs/fat, calories and protein unchanged; the stored
//      four-pack is byte-identical; unchanged = no write; an account change
//      returns false.
//   4  lapse and renewal, and the kill switch.
//   5  restore: a cloud row with diet_strategy restores the field; the
//      providers follow the restore tick.
//   9  an incomplete pack is never strategy-shaped.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/diet_strategies.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';
import 'package:icanbefitter/features/ai_coach/services/ai_snapshot_builder.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/features/nutrition/services/diet_strategy_flags.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/profile/services/profile_target_recompute.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../helpers/hive_test_setup.dart';

class _Fx {
  String? uid = 'user-a';
  String? uidAfterFirstRead;
  int _reads = 0;
  int pushes = 0;
  final locks = <List<String>>[];

  FoodTypeWriteEffects get effects => FoodTypeWriteEffects(
        currentUserId: () {
          _reads++;
          if (uidAfterFirstRead != null && _reads > 1) return uidAfterFirstRead;
          return uid;
        },
        pushSnapshot: () => pushes++,
        lockFields: (f) async => locks.add(List.of(f)),
      );
}

/// A test restore tick: the real provider listens to SyncService, which unit
/// tests do not start.
class _Tick extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final _tickProvider = NotifierProvider<_Tick, int>(_Tick.new);

typedef _Reads = ({
  double macroCarbs,
  double macroFat,
  double macroCalories,
  double macroProtein,
  DietStrategy macroStrategy,
  double dailyCarbs,
  double dailyFat,
  DietStrategy dailyStrategy,
  double homeCarbs,
  double homeFat,
  Map<String, dynamic> snapshot,
});

const _stored = <String, dynamic>{
  'full_name': 'T',
  'daily_calories': 2400,
  'protein_grams': 150,
  'carb_grams': 280,
  'carbs_grams': 280,
  'fat_grams': 80,
};

Future<void> _setPro(bool on) async {
  await MigratedKey.write('isPro', on);
  await MigratedKey.write(
      'expiresAt', DateTime.now().add(const Duration(days: 30)).toIso8601String());
}

void main() {
  late Directory tempDir;
  late _Fx fx;
  late ProviderContainer c;

  setUp(() async {
    tempDir = await setUpHiveForTests();
    fx = _Fx();
    UserProfileNotifier.debugFoodTypeEffects = fx.effects;
    DietStrategyFlags.debugEnabledOverride = null;
    c = ProviderContainer(overrides: [
      authUserIdTokenProvider.overrideWithValue(kTestUserId),
      restoreCompletedTickProvider
          .overrideWith((ref) => ref.watch(_tickProvider)),
    ]);
  });

  tearDown(() async {
    c.dispose();
    UserProfileNotifier.debugFoodTypeEffects = null;
    DietStrategyFlags.debugEnabledOverride = null;
    await tearDownHiveForTests(tempDir);
  });

  Future<void> seed([Map<String, dynamic> extra = const {}]) =>
      UserRepository.instance.updateProfileFields({..._stored, ...extra});

  Map<String, dynamic> storedPack() {
    final p = UserRepository.instance.getProfile()!;
    return {
      for (final k in [
        'daily_calories',
        'protein_grams',
        'carb_grams',
        'carbs_grams',
        'fat_grams'
      ])
        k: p[k],
    };
  }

  final keto = BmrCalculator.macroSplit(
      dailyCalories: 2400,
      proteinGrams: 150,
      balancedCarbs: 280,
      strategy: DietStrategy.keto);

  /// Every reader's carb/fat/strategy, read fresh.
  _Reads readAll() {
    final m = c.read(macroTargetsProvider);
    final d = c.read(dailyNutritionProvider);
    final h = c.read(nutritionSummaryProvider);
    return (
      macroCarbs: m['carbs']!,
      macroFat: m['fat']!,
      macroCalories: m['calories']!,
      macroProtein: m['protein']!,
      macroStrategy: dietStrategyOfTargets(m),
      dailyCarbs: d.carbTarget,
      dailyFat: d.fatTarget,
      dailyStrategy: d.strategy,
      homeCarbs: h.carbTarget,
      homeFat: h.fatTarget,
      snapshot: AiSnapshotBuilder.instance.buildAiContext(),
    );
  }

  void expectBalanced(_Reads r) {
    expect(r.macroCarbs, 280.0);
    expect(r.macroFat, 80.0);
    expect(r.macroStrategy, DietStrategy.balanced);
    expect(r.dailyCarbs, 280.0);
    expect(r.dailyFat, 80.0);
    expect(r.dailyStrategy, DietStrategy.balanced);
    expect(r.homeCarbs, 280.0);
    expect(r.homeFat, 80.0);
    final dt = r.snapshot['daily_targets'] as Map;
    expect(dt['carbs'], 280.0);
    expect(dt['fat'], 80.0);
  }

  void expectKeto(_Reads r) {
    expect(r.macroCalories, 2400.0);
    expect(r.macroProtein, 150.0);
    expect(r.macroCarbs, keto.carbGrams.toDouble());
    expect(r.macroFat, keto.fatGrams.toDouble());
    expect(r.macroStrategy, DietStrategy.keto);
    expect(r.dailyCarbs, keto.carbGrams.toDouble());
    expect(r.dailyFat, keto.fatGrams.toDouble());
    expect(r.dailyStrategy, DietStrategy.keto);
    expect(r.homeCarbs, keto.carbGrams.toDouble());
    expect(r.homeFat, keto.fatGrams.toDouble());
    final snap = r.snapshot;
    final dt = snap['daily_targets'] as Map;
    expect(dt['calories'], 2400.0);
    expect(dt['protein'], 150.0);
    expect(dt['carbs'], keto.carbGrams.toDouble());
    expect(dt['fat'], keto.fatGrams.toDouble());
    expect((snap['profile'] as Map)['diet_strategy'], 'keto');
    expect((snap['profile'] as Map)['diet_strategy_label'], 'Keto');
  }

  group('2b ship-dark identity (flag at its 3a default)', () {
    test('kDietStrategyDefaultOn is false and enabled reads false', () {
      expect(kDietStrategyDefaultOn, isFalse);
      expect(DietStrategyFlags.enabled, isFalse);
    });

    for (final extra in <Map<String, dynamic>>[
      const {},
      const {'diet_strategy': 'keto'},
    ]) {
      test('PRO, profile $extra: every reader shows the stored Balanced pack, '
          'the snapshot has no new key', () async {
        await _setPro(true);
        await seed(extra);
        final r = readAll();
        expectBalanced(r);
        final profile = r.snapshot['profile'] as Map;
        expect(profile.containsKey('diet_strategy'), isFalse);
        expect(profile.containsKey('diet_strategy_label'), isFalse);
        expect(c.read(macroTargetsProvider).containsKey('strategy_index'),
            isFalse);
      });
    }

    test('a fractional stored pack is passed through exactly', () async {
      await _setPro(true);
      await UserRepository.instance.updateProfileFields({
        'daily_calories': 2399.6,
        'protein_grams': 150.4,
        'carb_grams': 279.5,
        'fat_grams': 79.7,
        'diet_strategy': 'keto',
      });
      final m = c.read(macroTargetsProvider);
      expect(m['calories'], 2399.6);
      expect(m['protein'], 150.4);
      expect(m['carbs'], 279.5);
      expect(m['fat'], 79.7);
    });

    test('no new watches: a PRO flip or a restore tick rebuilds nothing',
        () async {
      await _setPro(false);
      await seed(const {'diet_strategy': 'keto'});
      c.read(subscriptionInfoProvider);
      final m0 = c.read(macroTargetsProvider);
      final d0 = c.read(dailyNutritionProvider);
      final h0 = c.read(nutritionSummaryProvider);
      await _setPro(true);
      c.invalidate(subscriptionInfoProvider);
      c.read(_tickProvider.notifier).bump();
      expect(identical(c.read(macroTargetsProvider), m0), isTrue);
      expect(identical(c.read(dailyNutritionProvider), d0), isTrue);
      expect(identical(c.read(nutritionSummaryProvider), h0), isTrue);
    });
  });

  group('flag on (test seam)', () {
    setUp(() => DietStrategyFlags.debugEnabledOverride = true);

    test('3: setDietStrategy(keto) -> every reader shows keto; calories, '
        'protein and the stored pack never change', () async {
      await _setPro(true);
      await seed();
      final before = storedPack();
      expectBalanced(readAll());

      expect(await c
          .read(userProfileProvider.notifier)
          .setDietStrategy(DietStrategy.keto), isTrue);
      expect(UserRepository.instance.getProfile()!['diet_strategy'], 'keto');
      expect(storedPack(), before, reason: 'no target is ever written');
      expect(fx.pushes, 1);
      expect(fx.locks, isEmpty, reason: 'no extraction lock for a strategy');
      expectKeto(readAll());
    });

    test('3: unchanged = no write; account change = false and no write',
        () async {
      await _setPro(true);
      await seed(const {'diet_strategy': 'keto'});
      final n = c.read(userProfileProvider.notifier);
      expect(await n.setDietStrategy(DietStrategy.keto), isTrue);
      expect(fx.pushes, 0);
      // A fresh fake: its FIRST read is this call's capture, every later
      // read answers the switched account.
      fx = _Fx()..uidAfterFirstRead = 'user-b';
      UserProfileNotifier.debugFoodTypeEffects = fx.effects;
      expect(await n.setDietStrategy(DietStrategy.lowCarb), isFalse);
      expect(fx.pushes, 0);
      expect(UserRepository.instance.getProfile()!['diet_strategy'], 'keto');
    });

    test('3: two quick taps are serialised, the second wins', () async {
      await _setPro(true);
      await seed();
      final n = c.read(userProfileProvider.notifier);
      await Future.wait([
        n.setDietStrategy(DietStrategy.keto),
        n.setDietStrategy(DietStrategy.lowCarb),
      ]);
      expect(UserRepository.instance.getProfile()!['diet_strategy'],
          'low_carb');
    });

    test('4: lapse shows Balanced everywhere, the stored choice is kept; '
        'renewal brings keto back (providers follow the PRO state)', () async {
      await _setPro(true);
      await seed(const {'diet_strategy': 'keto'});
      expectKeto(readAll());

      await _setPro(false);
      c.invalidate(subscriptionInfoProvider);
      final lapsed = readAll();
      expectBalanced(lapsed);
      expect((lapsed.snapshot['profile'] as Map)['diet_strategy'], 'balanced');
      expect(UserRepository.instance.getProfile()!['diet_strategy'], 'keto');

      await _setPro(true);
      c.invalidate(subscriptionInfoProvider);
      expectKeto(readAll());
    });

    test('4: the kill switch reverts every reader at once', () async {
      await _setPro(true);
      await seed(const {'diet_strategy': 'keto'});
      expectKeto(readAll());
      DietStrategyFlags.debugEnabledOverride = false;
      c.invalidate(macroTargetsProvider);
      c.invalidate(dailyNutritionProvider);
      c.invalidate(nutritionSummaryProvider);
      final r = readAll();
      expectBalanced(r);
      expect((r.snapshot['profile'] as Map).containsKey('diet_strategy'),
          isFalse);
    });

    test('5: providers follow a restore tick that brings a new strategy',
        () async {
      await _setPro(true);
      await seed();
      final m0 = c.read(macroTargetsProvider);
      c.read(dailyNutritionProvider);
      c.read(nutritionSummaryProvider);
      expect(dietStrategyOfTargets(m0), DietStrategy.balanced);
      // A restore writes Hive without touching Riverpod.
      final p = Map<String, dynamic>.from(
          HiveService.instance.userBox.get('profile') as Map);
      p['diet_strategy'] = 'keto';
      await HiveService.instance.userBox.put('profile', p);
      c.read(_tickProvider.notifier).bump();
      expectKeto(readAll());
    });

    test('5: a cloud row with diet_strategy restores the field', () async {
      await _setPro(true);
      await seed();
      SyncService.pausedForSimulation = true;
      HiveUserSession.debugCurrentUidResolverForTests = () => kTestUserId;
      try {
        await SyncService.instance.restoreUserProfileForTest(kTestUserId,
            preFetched: [
              {..._stored, 'user_id': kTestUserId, 'diet_strategy': 'keto'}
            ],
            preFetchedUsers: null);
      } finally {
        HiveUserSession.debugCurrentUidResolverForTests = null;
        SyncService.pausedForSimulation = false;
      }
      expect(UserRepository.instance.getProfile()!['diet_strategy'], 'keto');
      expect(derivedTargetInputKeys, isNot(contains('diet_strategy')),
          reason: 'the strategy never triggers the full recompute');
    });

    test('9: an incomplete stored pack is never strategy-shaped', () async {
      await _setPro(true);
      await UserRepository.instance.updateProfileFields({
        'full_name': 'T',
        'daily_calories': 2400,
        'protein_grams': 150,
        'diet_strategy': 'keto',
      });
      final m = c.read(macroTargetsProvider);
      expect(dietStrategyOfTargets(m), DietStrategy.balanced);
      expect(m['carbs'], 280, reason: 'the hard-coded Balanced default');
      final h = c.read(nutritionSummaryProvider);
      expect(h.carbTarget, 250, reason: "Home's own Balanced default");
      final dt = AiSnapshotBuilder.instance.buildAiContext()['daily_targets']
          as Map;
      expect(dt['carbs'], 0, reason: "the snapshot's own 0 default");
    });

    test('9: a stored carb value of 0 never caps keto carbs at 0', () async {
      await _setPro(true);
      await seed(const {'carb_grams': 0, 'carbs_grams': 0, 'diet_strategy': 'keto'});
      final m = c.read(macroTargetsProvider);
      expect(dietStrategyOfTargets(m), DietStrategy.balanced);
      expect(m['carbs'], 0);
    });
  });
}
