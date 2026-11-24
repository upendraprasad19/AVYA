// OI-348 B9 (diagnose e9a6c1): the unit preferences reach the cloud through
// the profile push and come back through the profile restore.
//
//   1. `unitPrefsPushEntries` (pure): both keys / neither / invalid values
//      dropped; the kill switch `disable_unit_pref_sync` gives `{}`, so the
//      payload is byte-identical to before.
//   2. The REAL profile push (`pushUserProfileForSyncDomain`) through the stub
//      server: the `user_profile` upsert row carries the two fields; with the
//      switch on, the row equals the row of a profile without them.
//   3. The REAL restore merge (`restoreUserProfileForTest`): cloud imperial +
//      `in` into a local profile -> the readers say imperial / inches; a cloud
//      NULL keeps the local value; the switch does not stop a restore.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/unit_pref_flags.dart';
import 'package:icanbefitter/core/utils/unit_prefs_rule.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/profile/providers/body_measurements_provider.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../helpers/hive_test_setup.dart' show kTestUserId;
import 'sync_domain_skip_harness.dart';

void main() {
  group('unitPrefsPushEntries (pure)', () {
    test('both keys, valid values', () {
      expect(
        unitPrefsPushEntries(
            {'units_system': 'imperial', 'measurement_unit': 'in'},
            enabled: true),
        {'units_system': 'imperial', 'measurement_unit': 'in'},
      );
    });

    test('neither key -> empty (absent stays absent, never NULL)', () {
      expect(unitPrefsPushEntries({'full_name': 'T'}, enabled: true), isEmpty);
    });

    test('an invalid value is not sent (a CHECK would refuse the whole row)',
        () {
      expect(
        unitPrefsPushEntries(
            {'units_system': 'feet', 'measurement_unit': 'xx'},
            enabled: true),
        isEmpty,
      );
      expect(
        unitPrefsPushEntries({'units_system': 'metric', 'measurement_unit': 3},
            enabled: true),
        {'units_system': 'metric'},
      );
    });

    test('the kill switch gives nothing', () {
      expect(
        unitPrefsPushEntries(
            {'units_system': 'imperial', 'measurement_unit': 'in'},
            enabled: false),
        isEmpty,
      );
    });
  });

  group('the real profile push and restore', () {
    final h = SyncHarness();

    setUp(() async {
      await h.setUp();
      SyncService.pausedForSimulation = true;
      h.server.clear();
    });

    tearDown(() async {
      UnitPrefFlags.debugPushEnabledOverride = null;
      SyncService.pausedForSimulation = false;
      await h.tearDown();
    });

    Future<void> seed(Map<String, dynamic> extra) =>
        HiveService.instance.userBox.put('profile', <String, dynamic>{
          'full_name': 'T',
          'goal': 'build_muscle',
          'current_weight_kg': 75.0,
          ...extra,
        });

    Future<Map<String, dynamic>> pushedRow() async {
      h.server.clear();
      SyncService.pausedForSimulation = false;
      try {
        await SyncService.instance
            .pushUserProfileForSyncDomain()
            .timeout(const Duration(minutes: 2));
      } finally {
        SyncService.pausedForSimulation = true;
      }
      final rows = [
        for (final r in h.server.writesTo('user_profile')) ...r.rows,
      ];
      expect(rows, hasLength(1), reason: 'one user_profile upsert row');
      return rows.single;
    }

    test('the upsert row carries both fields', () async {
      await seed({'units_system': 'imperial', 'measurement_unit': 'in'});
      final row = await pushedRow();
      expect(row['user_id'], kTestUserId);
      expect(row['units_system'], 'imperial');
      expect(row['measurement_unit'], 'in');
    });

    test('a profile without them sends neither key (never NULL)', () async {
      await seed({});
      final row = await pushedRow();
      expect(row.containsKey('units_system'), isFalse);
      expect(row.containsKey('measurement_unit'), isFalse);
    });

    test('switch on: the row is byte-identical to a profile without the '
        'fields', () async {
      await seed({});
      final without = await pushedRow();
      UnitPrefFlags.debugPushEnabledOverride = false;
      await seed({'units_system': 'imperial', 'measurement_unit': 'in'});
      final switched = await pushedRow();
      // The stamps that differ between two pushes by construction.
      for (final m in [without, switched]) {
        m.remove('updated_at');
      }
      expect(switched, without);
    });

    Future<void> restore(Map<String, dynamic> cloud) async {
      HiveUserSession.debugCurrentUidResolverForTests = () => kTestUserId;
      await SyncService.instance.restoreUserProfileForTest(kTestUserId,
          preFetched: [
            {'full_name': 'T', 'user_id': kTestUserId, ...cloud}
          ],
          preFetchedUsers: null);
    }

    bool preferredInches() {
      final c = ProviderContainer(overrides: [
        authUserIdTokenProvider.overrideWithValue(kTestUserId),
      ]);
      addTearDown(c.dispose);
      return c.read(measurementWriteProvider.notifier).preferredInches();
    }

    test('cloud imperial + in lands in a local profile: the readers follow',
        () async {
      await seed({});
      expect(UserRepository.instance.getUnitsMetric(), isTrue);
      await restore({'units_system': 'imperial', 'measurement_unit': 'in'});
      expect(UserRepository.instance.getUnitsMetric(), isFalse);
      expect(preferredInches(), isTrue);
    });

    test('a cloud NULL keeps the local value', () async {
      await seed({'units_system': 'imperial', 'measurement_unit': 'in'});
      await restore({'units_system': null, 'measurement_unit': null});
      expect(UserRepository.instance.getUnitsMetric(), isFalse);
      expect(preferredInches(), isTrue);
    });

    test('a cloud value replaces a different local value (the last pushed '
        'change wins)', () async {
      await seed({'units_system': 'imperial', 'measurement_unit': 'in'});
      await restore({'units_system': 'metric', 'measurement_unit': 'cm'});
      expect(UserRepository.instance.getUnitsMetric(), isTrue);
      expect(preferredInches(), isFalse);
    });

    test('the push switch does not stop a restore', () async {
      UnitPrefFlags.debugPushEnabledOverride = false;
      await seed({});
      await restore({'units_system': 'imperial'});
      expect(UserRepository.instance.getUnitsMetric(), isFalse);
    });
  });
}
