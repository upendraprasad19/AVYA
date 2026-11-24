@Timeout(Duration(minutes: 3))
library;

// a2d9f4 - BEHAVIOURAL. Crashlytics (build 50, 2026-11-22): `Bad state:
// HiveUserSession not opened - cannot wrap user-scoped box "healthBox"` thrown
// from BiometricNotifier.build while a tester signed out of one account and into
// another. A Notifier that watches `authUserIdTokenProvider` is REBUILT the
// moment the session closes, and its build() read a raw user-scoped box
// (`HiveService.instance.healthBox`, which is `GuardedBox.rawBox`) that throws in
// both windows of a sign-out: (A) Hive torn down while the auth user is still
// set (the empty-serve stub, whose rawBox throws), (B) both gone
// (guarded_box.dart's loud throw). The measured set that threw was ten providers,
// not one; each now returns its empty value on the `'<anon>'` token (the
// pattern body_measurements_provider.dart already used) and rebuilds with the
// real data once the token flips back.
//
// Real Hive, the real token provider, the real notifiers. Only the auth-state
// stream and the live auth uid (the seam guarded_box shares) are stood in for.
//
// Diagnose: docs/diagnoses/2026-11-24-signed-out-provider-rebuild-a2d9f4.md

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';

import '../helpers/hive_test_setup.dart';

/// One provider under test: how to read it, what its signed-out value is, and
/// (where a one-line seed makes it cheap) a real value to prove it comes back.
class _Case {
  _Case(
    this.name,
    this.provider, {
    required this.isEmpty,
    this.seed,
    this.isSeeded,
  });
  final String name;
  // Typed loosely on purpose: ProviderListenable is not exported by Riverpod 3,
  // and the container accepts the concrete provider at run time.
  final dynamic provider;
  final bool Function(Object? value) isEmpty;
  final Future<void> Function()? seed;
  final bool Function(Object? value)? isSeeded;
}

String get _today => istDateStr(DateTime.now());

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  final cases = <_Case>[
    _Case(
      'biometricProvider (the Crashlytics crash)',
      biometricProvider,
      isEmpty: (v) =>
          v is BiometricData && v.stepsToday == null && !v.isSyncEnabled,
      seed: () async {
        await HiveService.instance.configBox.put('health_sync_enabled', true);
        await HiveService.instance.healthBox.put('steps_log_x', {
          'date': _today,
          'type': 'step_log',
          'steps': 4321,
        });
      },
      isSeeded: (v) =>
          v is BiometricData && v.isSyncEnabled && v.stepsToday == 4321,
    ),
    _Case(
      'todayWeightLoggedProvider',
      todayWeightLoggedProvider,
      isEmpty: (v) => v == false,
      seed: () => HiveService.instance.healthBox
          .put('weight_$_today', {'date': _today, 'weight_kg': 70.0}),
      isSeeded: (v) => v == true,
    ),
    _Case(
      'waterIntakeProvider',
      waterIntakeProvider,
      isEmpty: (v) => v == 0,
      seed: () => HiveService.instance.healthBox.put('water_ml_$_today', 500),
      isSeeded: (v) => v == 500,
    ),
    _Case(
      'urineColorProvider',
      urineColorProvider,
      isEmpty: (v) => v == -1,
      seed: () => HiveService.instance.healthBox
          .put('urine_color_$_today', {'index': 3}),
      isSeeded: (v) => v == 3,
    ),
    _Case(
      'dailyNutritionProvider',
      dailyNutritionProvider,
      isEmpty: (v) =>
          v is DailyNutritionData &&
          v.calories == 0 &&
          v.meals.values.every((m) => m.isEmpty),
      seed: () => HiveService.instance.nutritionBox.put('nlog_seed', {
        'date': _today,
        'meal_type': 'lunch',
        'total_calories': 500.0,
        'total_protein': 30.0,
      }),
      isSeeded: (v) =>
          v is DailyNutritionData && v.meals['lunch']!.isNotEmpty,
    ),
    _Case(
      'weeklyNutritionProvider',
      weeklyNutritionProvider,
      isEmpty: (v) => v is WeeklyNutritionData && v.avgCalories == 0,
      seed: () => HiveService.instance.nutritionBox.put('nlog_seed', {
        'date': _today,
        'meal_type': 'lunch',
        'total_calories': 600.0,
        'total_protein': 40.0,
      }),
      isSeeded: (v) => v is WeeklyNutritionData && v.avgCalories > 0,
    ),
    _Case(
      'savedMealsProvider',
      savedMealsProvider,
      isEmpty: (v) => v is List && v.isEmpty,
      seed: () => HiveService.instance.nutritionBox
          .put('meal_seed', {'is_template': true, 'name': 'Seed meal'}),
      isSeeded: (v) => v is List && v.length == 1,
    ),
    _Case(
      'chatHistoryProvider',
      chatHistoryProvider,
      isEmpty: (v) => v is List && v.isEmpty,
      seed: () => HiveService.instance.coachBox.put('coach_seed', {
        'user_message': 'hello coach',
        'ai_response': 'hello',
        'created_at': DateTime.now().toIso8601String(),
      }),
      isSeeded: (v) => v is List && v.isNotEmpty,
    ),
    _Case(
      'messageLimitProvider',
      messageLimitProvider,
      isEmpty: (v) => v == 0,
      seed: () => HiveService.instance.userBox.put('msg_count_$_today', 3),
      isSeeded: (v) => v == 3,
    ),
    _Case(
      'templatesProvider',
      templatesProvider,
      isEmpty: (v) => v is List && v.isEmpty,
      seed: () => HiveService.instance.workoutBox
          .put('tmpl_seed', {'type': 'template', 'name': 'Seed template'}),
      isSeeded: (v) => v is List && v.length == 1,
    ),
  ];

  ProviderContainer makeContainer() {
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => const Stream.empty()),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('the test seam gives a signed-in session a real token (not <anon>)', () {
    final c = makeContainer();
    expect(c.read(authUserIdTokenProvider), kTestUserId);
  });

  for (final k in cases) {
    for (final window in const ['A: Hive closed, auth user still set',
        'B: Hive closed and auth user gone']) {
      test('${k.name} - sign-out window $window', () async {
        if (k.seed != null) await k.seed!();
        final c = makeContainer();
        final errors = <Object>[];
        // A listener is what makes Riverpod rebuild the provider (the screens
        // that watch it); onError is where the unguarded build() threw.
        c.listen(k.provider, (_, _) {}, onError: (e, _) => errors.add(e));

        // Signed in: the real value (or, with no seed, no error).
        final signedIn = c.read(k.provider);
        if (k.isSeeded != null) {
          expect(k.isSeeded!(signedIn), isTrue,
              reason: 'signed in, the provider must read the real data');
        }

        // Sign-out, in the app's own order (auth_provider.dart signOut): Hive
        // teardown FIRST, the auth user LAST.
        final authStillSet = window.startsWith('A');
        debugAuthUidResolverForTests = authStillSet ? () => kTestUserId : () => null;
        await HiveUserSession.closeAll();
        await Future<void>.delayed(Duration.zero);

        expect(errors, isEmpty,
            reason: 'build() must not throw while the session is closed '
                '(this is the Crashlytics crash)');
        final signedOut = c.read(k.provider);
        expect(k.isEmpty(signedOut), isTrue,
            reason: 'signed out, the provider serves its empty value');

        // Sign back in as the same user: Layer B must re-run build() with data.
        debugAuthUidResolverForTests = () => HiveUserSession.currentOwnerFullId;
        await HiveUserSession.openForUser(kTestUserId);
        await Future<void>.delayed(Duration.zero);

        expect(errors, isEmpty);
        final again = c.read(k.provider);
        if (k.isSeeded != null) {
          expect(k.isSeeded!(again), isTrue,
              reason: 'once the token flips back the real data returns');
        }
      });
    }
  }
}
