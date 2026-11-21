// Diet plan Unit 4a (2026-11-15, docs/plans/diet-supplements.md sections 2, 3,
// 7): SoT concept `diet_supplements`. ONE writer door (setDietSupplements),
// ONE rule (dietSupplementsActive), and the readers that follow it.
//
// Behavioural, real Hive + a real ProviderContainer:
//   - setDietSupplements: writes the bool, pushes the snapshot once, is a
//     no-op on the stored value, drops a call queued across an account
//     change, is serialised, pushes nothing when signed out.
//   - dietSupplementsActiveProvider: reactive to the switch, the date of
//     birth and PRO; false with the kill switch off whatever the profile
//     holds.
//   - AiSnapshotBuilder.buildAiContext (the coach): `profile.diet_supplements`
//     is `true` only while ACTIVE, absent otherwise.
// PRESENCE (stated): the sync push entry sits inside the payload map of
// sync_profile.dart (the upsert is not run here: it needs Supabase).
//
// Mutations (diagnose table): drop the active clause for PRO from the
// snapshot; drop the adult clause; emit `false` instead of omitting the key;
// remove the no-op check; remove the account check; drop the push entry;
// push only `true`.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart'
    show restoreCompletedTickProvider;
import 'package:icanbefitter/features/ai_coach/services/ai_snapshot_builder.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/nutrition/providers/diet_plan_provider.dart';
import 'package:icanbefitter/features/nutrition/providers/diet_supplements_active_provider.dart';
import 'package:icanbefitter/features/nutrition/services/diet_supplements_flags.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../helpers/hive_test_setup.dart';

/// A test restore tick: the real provider listens to SyncService, which unit
/// tests do not start.
class _Tick extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final _tickProvider = NotifierProvider<_Tick, int>(_Tick.new);

class _Fx {
  String? uid = 'user-a';
  String? uidAfterFirstRead;
  int _reads = 0;
  int pushes = 0;

  FoodTypeWriteEffects get effects => FoodTypeWriteEffects(
        currentUserId: () {
          _reads++;
          if (uidAfterFirstRead != null && _reads > 1) return uidAfterFirstRead;
          return uid;
        },
        pushSnapshot: () => pushes++,
        lockFields: (_) async {},
      );
}

String _src(String path) => File(path).readAsStringSync();

/// [s] with `//` line comments and block comments removed (a source pin must
/// not be satisfied by a comment).
String _noComments(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  late Directory tempDir;
  late _Fx fx;
  late ProviderContainer c;

  setUp(() async {
    tempDir = await setUpHiveForTests();
    fx = _Fx();
    UserProfileNotifier.debugFoodTypeEffects = fx.effects;
    DietSupplementsFlags.debugEnabledOverride = true;
    c = ProviderContainer(overrides: [
      authUserIdTokenProvider.overrideWithValue(kTestUserId),
      restoreCompletedTickProvider
          .overrideWith((ref) => ref.watch(_tickProvider)),
    ]);
  });

  tearDown(() async {
    c.dispose();
    UserProfileNotifier.debugFoodTypeEffects = null;
    DietSupplementsFlags.debugEnabledOverride = null;
    await tearDownHiveForTests(tempDir);
  });

  Future<void> seed({
    Object? sw,
    Object? dob = '1998-01-01',
    bool pro = true,
  }) async {
    await UserRepository.instance.updateProfileFields({
      'full_name': 'T',
      'date_of_birth': dob,
      'diet_supplements': sw,
    });
    await MigratedKey.write('isPro', pro);
    await MigratedKey.write('expiresAt',
        DateTime.now().add(const Duration(days: 30)).toIso8601String());
  }

  Object? stored() => UserRepository.instance.getProfile()?['diet_supplements'];
  UserProfileNotifier notifier() => c.read(userProfileProvider.notifier);

  group('the write door: setDietSupplements', () {
    test('a real change writes the bool and pushes the snapshot once',
        () async {
      await seed();
      expect(await notifier().setDietSupplements(true), isTrue);
      expect(stored(), true);
      expect(fx.pushes, 1);
      expect(c.read(userProfileProvider)['diet_supplements'], true);
    });

    test('false is written as false (not removed)', () async {
      await seed(sw: true);
      expect(await notifier().setDietSupplements(false), isTrue);
      expect(stored(), false);
      expect(UserRepository.instance.getProfile()!.containsKey('diet_supplements'),
          isTrue);
    });

    test('the stored value again is a no-op: no write, no push', () async {
      await seed(sw: true);
      expect(await notifier().setDietSupplements(true), isTrue);
      expect(fx.pushes, 0);
    });

    test('absent -> false IS a write (absent is not stored false)', () async {
      await seed();
      await notifier().setDietSupplements(false);
      expect(stored(), false);
      expect(fx.pushes, 1);
    });

    test('a call queued across an account change writes nothing', () async {
      await seed();
      fx.uidAfterFirstRead = 'user-b';
      expect(await notifier().setDietSupplements(true), isFalse);
      expect(stored(), isNull);
      expect(fx.pushes, 0);
    });

    test('two quick taps end with the second', () async {
      await seed();
      final a = notifier().setDietSupplements(true);
      final b = notifier().setDietSupplements(false);
      await Future.wait([a, b]);
      expect(stored(), false);
    });

    test('signed out: the value is written, nothing is pushed', () async {
      await seed();
      fx.uid = null;
      await notifier().setDietSupplements(true);
      expect(stored(), true);
      expect(fx.pushes, 0);
    });
  });

  group('the reactive rule: dietSupplementsActiveProvider', () {
    test('follows the switch, the date of birth and PRO', () async {
      await seed(sw: true);
      final sub = c.listen(dietSupplementsActiveProvider, (_, _) {});
      expect(c.read(dietSupplementsActiveProvider), isTrue);
      await notifier().updateProfile({'diet_supplements': false});
      expect(c.read(dietSupplementsActiveProvider), isFalse);
      await notifier().updateProfile({'diet_supplements': true});
      expect(c.read(dietSupplementsActiveProvider), isTrue);
      await notifier()
          .updateProfile({'date_of_birth': '${DateTime.now().year - 12}-01-01'});
      expect(c.read(dietSupplementsActiveProvider), isFalse,
          reason: 'a minor');
      await notifier().updateProfile({'date_of_birth': '1998-01-01'});
      expect(c.read(dietSupplementsActiveProvider), isTrue);
      sub.close();
    });

    test('a PRO lapse and a renewal flip it mid-session', () async {
      await seed(sw: true);
      c.read(subscriptionInfoProvider);
      final sub = c.listen(dietSupplementsActiveProvider, (_, _) {});
      expect(c.read(dietSupplementsActiveProvider), isTrue);
      await MigratedKey.write('isPro', false);
      c.invalidate(subscriptionInfoProvider);
      expect(c.read(dietSupplementsActiveProvider), isFalse, reason: 'lapsed');
      await MigratedKey.write('isPro', true);
      c.invalidate(subscriptionInfoProvider);
      expect(c.read(dietSupplementsActiveProvider), isTrue, reason: 'renewed');
      sub.close();
    });

    test('a restore tick that brings a new value flips it', () async {
      await seed(sw: false);
      final sub = c.listen(dietSupplementsActiveProvider, (_, _) {});
      expect(c.read(dietSupplementsActiveProvider), isFalse);
      // A restore writes Hive without touching Riverpod (see the strategy
      // writer-to-reader test); the tick is what tells the readers.
      final p = Map<String, dynamic>.from(
          HiveService.instance.userBox.get('profile') as Map);
      p['diet_supplements'] = true;
      await HiveService.instance.userBox.put('profile', p);
      c.read(_tickProvider.notifier).bump();
      expect(c.read(dietSupplementsActiveProvider), isTrue);
      sub.close();
    });

    test('the kill switch off: false whatever the profile holds', () async {
      DietSupplementsFlags.debugEnabledOverride = false;
      await seed(sw: true);
      expect(c.read(dietSupplementsActiveProvider), isFalse);
      expect(c.read(dietSupplementsEligibleProvider), isFalse);
    });

    test('PRO off: false', () async {
      await seed(sw: true, pro: false);
      expect(c.read(dietSupplementsActiveProvider), isFalse);
      expect(c.read(dietSupplementsEligibleProvider), isTrue,
          reason: 'a free adult sees the section');
    });

    test('PRESENCE: the kill switch returns before the first watch', () {
      final src = _noComments(_src(
          'lib/features/nutrition/providers/diet_supplements_active_provider.dart'));
      final body = src.substring(src.indexOf('dietSupplementsActiveProvider = '));
      final guard = body.indexOf('if (!DietSupplementsFlags.enabled) return false;');
      final firstWatch = body.indexOf('ref.watch(');
      expect(guard, greaterThanOrEqualTo(0));
      expect(guard, lessThan(firstWatch),
          reason: 'a flag-off reader keeps its pre-Unit-4 dependency set');
    });
  });

  group('the Nutrition hints (DietPlanNotifier) follow the Supplements state',
      () {
    Map<String, dynamic> plan({bool? stamp}) => {
          'id': 'p',
          'created_at': '2026-11-15T08:00:00.000',
          'food_type': 'veg',
          if (stamp != null) 'diet_supplements': stamp,
          'meals': [
            {
              'name': 'Lunch',
              'items': [
                {
                  'food_id': 'F0019',
                  'name': 'Dal',
                  'serving_desc': '1 bowl',
                  'calories': 180,
                  'protein': 12,
                },
              ],
            },
          ],
        };

    Future<void> seedVeg({Object? sw, bool pro = true}) async {
      await seed(sw: sw, pro: pro);
      await UserRepository.instance.updateProfileFields({'diet_preference': 'veg'});
    }

    test('a stamped plan gives hints only while Supplements are active',
        () async {
      await seedVeg(sw: true);
      await UserRepository.instance.saveDietPlan(plan(stamp: true));
      final sub = c.listen(dietPlanProvider, (_, _) {});
      expect(c.read(dietPlanProvider).keys, contains('lunch'));
      await notifier().updateProfile({'diet_supplements': false});
      expect(c.read(dietPlanProvider), isEmpty,
          reason: 'switched off: the stamped plan is for the other state');
      await notifier().updateProfile({'diet_supplements': true});
      expect(c.read(dietPlanProvider).keys, contains('lunch'));
      sub.close();
    });

    test('an unstamped plan gives no hints while active, and does while not',
        () async {
      await seedVeg(sw: true);
      await UserRepository.instance.saveDietPlan(plan());
      final sub = c.listen(dietPlanProvider, (_, _) {});
      expect(c.read(dietPlanProvider), isEmpty);
      await notifier().updateProfile({'diet_supplements': false});
      expect(c.read(dietPlanProvider).keys, contains('lunch'));
      sub.close();
    });

    test('the kill switch off: a stamped plan gives no hints, an unstamped '
        'one is unchanged', () async {
      DietSupplementsFlags.debugEnabledOverride = false;
      await seedVeg(sw: true);
      await UserRepository.instance.saveDietPlan(plan(stamp: true));
      expect(c.read(dietPlanProvider), isEmpty,
          reason: 'nothing is active: the shake would outlive the switch');
      await UserRepository.instance.saveDietPlan(plan());
      c.invalidate(dietPlanProvider);
      expect(c.read(dietPlanProvider).keys, contains('lunch'));
    });
  });

  group('restore and Edit Profile keep the key', () {
    Future<void> restore(Map<String, dynamic> cloud) async {
      SyncService.pausedForSimulation = true;
      HiveUserSession.debugCurrentUidResolverForTests = () => kTestUserId;
      try {
        await SyncService.instance.restoreUserProfileForTest(kTestUserId,
            preFetched: [
              {'full_name': 'T', 'user_id': kTestUserId, ...cloud}
            ],
            preFetchedUsers: null);
      } finally {
        HiveUserSession.debugCurrentUidResolverForTests = null;
        SyncService.pausedForSimulation = false;
      }
    }

    test('a cloud true and a cloud false both land over the local value',
        () async {
      await seed(sw: false);
      await restore({'diet_supplements': true});
      expect(stored(), isTrue);
      await restore({'diet_supplements': false});
      expect(stored(), isFalse, reason: 'false is a value, not "absent"');
    });

    test('a cloud NULL leaves the local choice alone', () async {
      await seed(sw: true);
      await restore({'diet_supplements': null});
      expect(stored(), isTrue);
    });

    test('an Edit Profile-shaped patch (other fields only) keeps the key',
        () async {
      await seed(sw: true);
      await notifier().updateProfile({'full_name': 'T2', 'city': 'Pune'});
      expect(stored(), isTrue);
    });
  });

  group('the coach snapshot: profile.diet_supplements', () {
    Map<String, dynamic> profile() =>
        AiSnapshotBuilder.instance.buildAiContext()['profile']
            as Map<String, dynamic>;

    test('present and true only while ACTIVE', () async {
      await seed(sw: true);
      expect(profile()['diet_supplements'], true);
    });

    test('every missing clause omits the key (never false)', () async {
      for (final (label, sw, dob, pro, flag) in <(String, Object?, Object?, bool, bool)>[
        ('switch off', false, '1998-01-01', true, true),
        ('switch absent', null, '1998-01-01', true, true),
        ('not PRO', true, '1998-01-01', false, true),
        ('a minor', true, '${DateTime.now().year - 15}-01-01', true, true),
        ('no date of birth', true, null, true, true),
        ('flag off', true, '1998-01-01', true, false),
      ]) {
        DietSupplementsFlags.debugEnabledOverride = flag;
        await seed(sw: sw, dob: dob, pro: pro);
        expect(profile().containsKey('diet_supplements'), isFalse,
            reason: label);
      }
    });
  });

  group('the cloud push', () {
    test('PRESENCE: the entry is inside the payload map, with the flag', () {
      final src = _noComments(_src('lib/core/services/sync/sync_profile.dart'));
      expect(
          src,
          contains(
              '...dietSupplementsPushEntry(p, enabled: DietSupplementsFlags.enabled),'));
      // Bounded to the upsert payload: after the diet_strategy entry, before
      // the injuries entry.
      final at = src.indexOf('...dietSupplementsPushEntry(');
      final strategy = src.indexOf('...dietStrategyPushEntry(');
      final injuries = src.indexOf("'injuries':");
      expect(at, greaterThan(strategy));
      expect(at, lessThan(injuries));
    });

    test('the migration adds exactly the nullable boolean column', () {
      final files = Directory('supabase/migrations')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('_diet_supplements.sql'))
          .toList();
      expect(files.length, 1);
      final sql = files.single
          .readAsStringSync()
          .replaceAll(RegExp(r'--[^\n]*'), '');
      expect(
          RegExp(r'ADD COLUMN IF NOT EXISTS diet_supplements boolean\s*;')
              .hasMatch(sql),
          isTrue);
      expect(sql.toUpperCase(), isNot(contains('NOT NULL')));
      expect(sql.toUpperCase(), isNot(contains('DEFAULT')));
    });
  });
}
