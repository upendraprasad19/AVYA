@Timeout(Duration(minutes: 3))
library;

// L2b Landing B (B3/B5) - BEHAVIOURAL. The three per-user keys this landing
// adds (the two prompt-snooze dates and the sheet's unit) and the dev flag
// must not survive a sign-out: UserRepository.clearAllData() is the real
// clearing path, and the keys are listed in UserConfigMigrator.userScopedKeys
// (so they live in the user's box, never in the shared configBox).
//
// The precondition is a write-and-read-back, so a key that never landed (a
// wrong box, a no-op write) cannot make the "absent after clear" assertions
// vacuous.
//
// Plan: docs/plans/coach-measurement-sheet-ui.md (B3, B5, section 4)

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/user_config_migrator.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/profile/providers/measurement_prompt_provider.dart';
import 'package:icanbefitter/features/profile/services/measurement_prompt_rules.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../helpers/hive_test_setup.dart';

const _keys = <String>[
  'body_measurement_prompt_dismissed_at',
  'body_measurement_prompt_baseline_skipped_at',
  'body_measurement_sheet_unit',
];

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
    setTestClockTo(DateTime.utc(2026, 10, 12, 6));
  });

  tearDown(() async {
    resetTestClock();
    await tearDownHiveForTests(tempDir);
  });

  test('the three keys are registered as user-scoped', () {
    for (final k in _keys) {
      expect(UserConfigMigrator.userScopedKeys, contains(k), reason: k);
    }
  });

  test('written through MigratedKey they land in the USER box, are readable, '
      'and are gone after clearAllData()', () async {
    await MigratedKey.write(_keys[0], '2026-10-10');
    await MigratedKey.write(_keys[1], '2026-10-01');
    await MigratedKey.write(_keys[2], 'in');
    await HiveService.instance.configBox.put('enable_body_measurements', true);

    // Precondition: every write is observable where it should be.
    for (final k in _keys) {
      expect(HiveService.instance.userBox.containsKey(k), isTrue, reason: k);
      expect(HiveService.instance.configBox.containsKey(k), isFalse,
          reason: '$k must not be in the shared box');
      expect(MigratedKey.read<dynamic>(k), isNotNull, reason: k);
    }
    expect(HiveService.instance.configBox.get('enable_body_measurements'), true);

    final result = await UserRepository.instance.clearAllData();
    expect(result.isClean, isTrue, reason: '$result');

    for (final k in _keys) {
      expect(HiveService.instance.userBox.containsKey(k), isFalse, reason: k);
      expect(HiveService.instance.configBox.containsKey(k), isFalse, reason: k);
      expect(MigratedKey.read<dynamic>(k), isNull, reason: k);
      expect(HiveService.instance.migrationBox.keys.map((e) => '$e'),
          isNot(contains(k)),
          reason: 'no device-lifetime copy of $k may survive a sign-out');
    }
    expect(HiveService.instance.configBox.containsKey('enable_body_measurements'),
        isFalse);
  });

  // The previous version asserted `none` after the clear, which is also what a
  // missing history and a missing stamp give: a surviving dismissal changed
  // nothing it could see. This one plants a history that is DUE and shows that
  // the dismissal is the only thing silencing it before the clear and is gone
  // after it.
  test('a dismissal silences a due prompt; after the clear (and a history '
      'that is due again) nothing silences it', () async {
    Future<void> plantDueHistoryAndProfile() async {
      await HiveService.instance.healthBox.put('measurement_2026-09-01', {
        'id': 'meas_1',
        'date': '2026-09-01',
        'waist': 80.0,
        'created_at': '2026-09-01T01:00:00.000Z',
        'updated_at_ms': 1,
      });
      await HiveService.instance.userBox.put('profile', <String, dynamic>{
        'full_name': 'Test',
        'onboarding_completed_at': '2026-08-01T00:00:00Z',
      });
    }

    MeasurementPrompt promptNow() {
      final c = ProviderContainer(overrides: [
        authUserIdTokenProvider.overrideWithValue(kTestUserId),
      ]);
      addTearDown(c.dispose);
      final sub = c.listen(measurementPromptProvider, (_, _) {});
      addTearDown(sub.close);
      return c.read(measurementPromptProvider);
    }

    await plantDueHistoryAndProfile();
    await HiveService.instance.configBox.put('enable_body_measurements', true);
    expect(promptNow(), MeasurementPrompt.due, reason: 'control: nothing silences it');

    await MigratedKey.write(_keys[0], '2026-10-10'); // dismissed 2 days ago
    expect(promptNow(), MeasurementPrompt.none,
        reason: 'precondition: the dismissal alone silences the due prompt');

    final result = await UserRepository.instance.clearAllData();
    expect(result.isClean, isTrue, reason: '$result');

    // What a sign-in brings back: the flag and a due history. The dismissal is
    // per user and device-local, so it does not come back.
    await plantDueHistoryAndProfile();
    await HiveService.instance.configBox.put('enable_body_measurements', true);
    expect(promptNow(), MeasurementPrompt.due,
        reason: 'a dismissal that survived the sign-out would still say none');
  });
}
