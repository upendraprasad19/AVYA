// goal-change-targets B2 (behavioural): the REAL WeightLogNotifier on real Hive. One weigh-in is
// ONE profile patch under the profile lock: the raw weigh-in always lands as `current_weight_kg`,
// and the 7-day mean may refresh the targets and the basis in the same write.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/legacy_goal_healer.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/features/profile/services/profile_target_recompute.dart';
import 'package:icanbefitter/features/profile/services/profile_write_service.dart';
import 'package:icanbefitter/features/profile/services/weigh_in_target_refresh.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const first = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  const second = 'dddddddd-0000-0000-0000-000000000000';
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_weigh_in_refresh');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    for (final name in [
      HiveService.configBoxName,
      HiveService.migrationBoxName,
      for (final id in ['aaaaaaaa', 'dddddddd'])
        for (final b in ['userBox', 'workoutBox', 'nutritionBox', 'healthBox', 'coachBox'])
          '${b}_$id',
    ]) {
      if (Hive.isBoxOpen(name)) await Hive.box(name).close();
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(first);
    SyncService.pausedForSimulation = true;
  });

  tearDown(() async {
    WeightLogNotifier.debugBeforeProfileWrite = null;
    WeightLogNotifier.debugOnPushSnapshot = null;
    ProfileWriteService.debugOnFireSync = null;
    SyncService.pausedForSimulation = false;
    await HiveUserSession.closeAll();
  });

  Map<String, dynamic> baseProfile({
    double weight = 80,
    double? basis,
    Object height = 178.0,
  }) {
    final p = <String, dynamic>{
      'current_weight_kg': weight,
      'height_cm': 178.0,
      'date_of_birth': '1995-06-15',
      'gender': 'male',
      'primary_goal': 'lose_fat',
      'lifestyle_activity': 'moderately_active',
      'days_per_week': 4,
      'pace_preference': 'balanced',
      'target_weight_kg': 70.0,
    };
    p.addAll(recomputeDerivedTargets(p, now: DateTime.now())!);
    p.remove(kTargetsBasisWeightKey);
    if (basis != null) p[kTargetsBasisWeightKey] = basis;
    p['height_cm'] = height;
    return p;
  }

  Future<void> seed(Map<String, dynamic> p) async =>
      HiveService.instance.userBox.put('profile', p);

  Map<String, dynamic> stored() =>
      Map<String, dynamic>.from(HiveService.instance.userBox.get('profile') as Map);

  ProviderContainer makeContainer() {
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => const Stream.empty()),
      authUserIdTokenProvider.overrideWithValue(first),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  Future<WeightLogResult> log(ProviderContainer c, double kg) =>
      c.read(weightLogNotifierProvider.notifier).logWeight(kg);

  test('an in-band weigh-in writes the raw weight and seeds the basis; calories stay', () async {
    final p = baseProfile(weight: 80);
    await seed(p);
    final r = await log(makeContainer(), 81.2);
    final after = stored();
    expect(r.wrote, isTrue);
    expect(r.targetsMoved, isFalse);
    expect(after['current_weight_kg'], 81.2);
    expect(after[kTargetsBasisWeightKey], 80.0);
    expect(after['daily_calories'], p['daily_calories']);
    expect(after['protein_grams'], p['protein_grams']);
  });

  test('a drift weigh-in moves calories, protein and the basis in ONE profile write', () async {
    final p = baseProfile(weight: 80, basis: 80);
    await seed(p);
    var syncs = 0;
    ProfileWriteService.debugOnFireSync = () => syncs++;
    final r = await log(makeContainer(), 76);
    final after = stored();
    expect(syncs, 1);
    expect(r.wrote, isTrue);
    expect(r.targetsMoved, isTrue);
    expect(r.caloriesFrom, p['daily_calories']);
    expect(r.caloriesTo, after['daily_calories']);
    expect(after['current_weight_kg'], 76);
    expect(after[kTargetsBasisWeightKey], 76.0);
    expect(after['daily_calories'], isNot(p['daily_calories']));
  });

  test('a drift weigh-in refreshes the derived readers and pushes the snapshot once; an in-band one does neither',
      () async {
    final p = baseProfile(weight: 80, basis: 80);
    await seed(p);
    var pushes = 0;
    WeightLogNotifier.debugOnPushSnapshot = () => pushes++;
    final c = makeContainer();
    final sub = c.listen(macroTargetsProvider, (_, __) {});
    addTearDown(sub.close);
    expect(c.read(macroTargetsProvider)['calories'], (p['daily_calories'] as num).toDouble());
    await log(c, 80.5); // in band: the plain raw-weight write
    expect(pushes, 0);
    expect(c.read(macroTargetsProvider)['calories'], (p['daily_calories'] as num).toDouble());
    final r = await log(c, 76); // over the band
    expect(pushes, 1);
    expect(r.targetsMoved, isTrue);
    expect(c.read(macroTargetsProvider)['calories'], (stored()['daily_calories'] as num).toDouble(),
        reason: 'macroTargetsProvider was invalidated and rebuilt from the new targets');
    expect(stored()['daily_calories'], isNot(p['daily_calories']));
  });

  test('the body-fat switch reaches the weigh-in recompute', () async {
    Future<num> calories(bool fatOff) async {
      final p = baseProfile(weight: 80, basis: 80)..['body_fat_percent'] = 24.0;
      await seed(p);
      await HiveService.instance.configBox.put('disable_bodyfat_calc', fatOff);
      await log(makeContainer(), 76);
      return stored()['daily_calories'] as num;
    }

    final withFat = await calories(false);
    final withoutFat = await calories(true);
    expect(withFat, isNot(withoutFat));
  });

  test('an owner change before the profile write: nothing is written', () async {
    await seed(baseProfile(weight: 80, basis: 80));
    WeightLogNotifier.debugBeforeProfileWrite =
        () => HiveUserSession.openForUser(second);
    final r = await log(makeContainer(), 70);
    expect(r.wrote, isFalse);
    expect(r.targetsMoved, isFalse);
    expect(HiveService.instance.userBox.get('profile'), isNull);
  });

  test('a failed health write skips the refresh and keeps the raw weight write', () async {
    final p = baseProfile(weight: 80, basis: 80);
    await seed(p);
    final r = await log(makeContainer(), 600); // out of range: the health write refuses it
    final after = stored();
    expect(r.targetsMoved, isFalse);
    expect(after['current_weight_kg'], 600);
    expect(after['daily_calories'], p['daily_calories']);
    expect(after[kTargetsBasisWeightKey], 80.0);
  });

  test('a corrupt stored height makes the refresh throw; the raw weight is STILL written', () async {
    await seed(baseProfile(weight: 80, basis: 80, height: '178'));
    final r = await log(makeContainer(), 70);
    final after = stored();
    expect(r.wrote, isTrue);
    expect(r.targetsMoved, isFalse);
    expect(after['current_weight_kg'], 70);
    expect(after[kTargetsBasisWeightKey], 80.0);
  });

  test('with disable_profile_target_recompute set the write equals the old updateField write', () async {
    final p = baseProfile(weight: 80, basis: 80);
    await seed(p);
    await HiveService.instance.configBox.put(LegacyGoalHealer.recomputeKillSwitch, true);
    final r = await log(makeContainer(), 70);
    final after = stored()..remove('updated_at');
    final expected = {...p, 'current_weight_kg': 70}..remove('updated_at');
    expect(r.targetsMoved, isFalse);
    expect(after, expected);
  });

  test('the 7-day mean smooths: a heavy morning after steady days stays inside the band', () async {
    final p = baseProfile(weight: 80, basis: 80);
    await seed(p);
    final c = makeContainer();
    final health = HiveService.instance.healthBox;
    final now = DateTime.now();
    for (var d = 1; d <= 5; d++) {
      final day = now.subtract(Duration(days: d));
      final key =
          'weight_${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      await health.put(key, {'type': 'weight_log', 'date': key.substring(7), 'weight_kg': 80.0});
    }
    // One 83.5 kg morning: the raw drift is 3.5 kg, the mean of six readings is 80.58.
    final r = await log(c, 83.5);
    expect(r.targetsMoved, isFalse);
    expect(stored()['current_weight_kg'], 83.5);
    expect(stored()['daily_calories'], p['daily_calories']);
  });
}
