// test/contracts/diet_serving_view_writer_to_reader_test.dart
//
// OI-517 (docs/plans/diet-grams-toggle.md): the profile key `diet_serving_view`
// ('portions' | 'grams'). Writer: `setDietServingView (diet_serving_view_actions.dart)`
// (the toggle) and the profile map `completeOnboarding` saves (new users =
// 'grams'). Reader: `dietServingViewProvider`. Absent key = Portions, so every
// account that finished onboarding before this shipped is unchanged without a
// write. Local only: the profile push is a column whitelist.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/nutrition/providers/diet_serving_view_provider.dart';
import 'package:icanbefitter/features/nutrition/services/diet_serving_label.dart';
import 'package:icanbefitter/features/nutrition/services/diet_serving_view_actions.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/profile/services/profile_write_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import 'package:icanbefitter/core/services/hive_service.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;
  setUp(() async => tempDir = await setUpHiveForTests());
  tearDown(() async => tearDownHiveForTests(tempDir));

  test('an existing profile without the key reads as Portions', () async {
    await ProfileWriteService.instance
        .updateProfile(<String, dynamic>{'full_name': 'Old User'});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(dietServingViewProvider), DietServingView.portions);
  });

  test('the toggle writes the key and the provider follows', () async {
    await ProfileWriteService.instance
        .updateProfile(<String, dynamic>{'full_name': 'User'});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(dietServingViewProvider), DietServingView.portions);

    await setDietServingView(
        c.read(userProfileProvider.notifier), DietServingView.grams);
    expect(UserRepository.instance.getProfile()!['diet_serving_view'], 'grams');
    expect(c.read(dietServingViewProvider), DietServingView.grams);

    await setDietServingView(
        c.read(userProfileProvider.notifier), DietServingView.portions);
    expect(c.read(dietServingViewProvider), DietServingView.portions);
  });

  test('writing the stored value again changes nothing else in the profile',
      () async {
    await ProfileWriteService.instance.updateProfile(
        <String, dynamic>{'full_name': 'User', 'diet_serving_view': 'grams'});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await setDietServingView(
        c.read(userProfileProvider.notifier), DietServingView.grams);
    final p = UserRepository.instance.getProfile()!;
    expect(p['diet_serving_view'], 'grams');
    expect(p['full_name'], 'User');
  });

  test('a restore-style write (cloud fields onto the local map) keeps the key',
      () async {
    await ProfileWriteService.instance.updateProfile(
        <String, dynamic>{'full_name': 'User', 'diet_serving_view': 'grams'});
    final existing = UserRepository.instance.getProfile()!;
    // `_restoreUserProfile` merges `{...existing, ...cloud non-null}`; the
    // cloud row has no such column, so the local key survives.
    await ProfileWriteService.instance.updateProfile(
        <String, dynamic>{...existing, 'full_name': 'User (cloud)'},
        skipSync: true);
    expect(UserRepository.instance.getProfile()!['diet_serving_view'], 'grams');
  });

  test('onboarding completion writes grams for a new user (presence pin)', () {
    final src = File('lib/features/onboarding/providers/onboarding_provider.dart')
        .readAsStringSync();
    expect(src, contains("'diet_serving_view': 'grams',"));
  });

  test('isLiquidFood: an audited liquid is true; a solid, a missing id and an '
      'empty id are false', () async {
    final box = HiveService.instance.foodBox;
    await box.put('F0031',
        {'id': 'F0031', 'name': 'Milk (Toned)', 'weight_unit': 'ml'});
    await box.put('F0001', {'id': 'F0001', 'name': 'White Rice (cooked)'});
    expect(isLiquidFood('F0031'), isTrue);
    expect(isLiquidFood('F0001'), isFalse);
    expect(isLiquidFood('F9999'), isFalse); // retired id in an old saved plan
    expect(isLiquidFood(''), isFalse);
  });
}
