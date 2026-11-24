// OI-348 B9 (diagnose e9a6c1): SoT concept `unit_preference_sync`.
//
// The units setting (`units_system`) and the measurement sheet's last unit
// (`measurement_unit`) are per-user PROFILE fields, synced by the profile push.
// Before: `configBox['units_metric']` (one value per DEVICE, never pushed) and
// a per-user Hive key (never pushed).
//
// Behavioural, real Hive:
//   - writers put the profile keys; `getUnitsMetric` / `preferredInches` read
//     them; bad values read as the defaults; a throwing read answers metric
//     and logs `units_pref_read_failed`;
//   - no profile -> the setter writes nothing (no stub); no owner -> nothing;
//   - the legacy device key is a fallback only while the profile has no
//     `units_system`; the profile wins over it;
//   - two users on one device see only their own profile value; AFTER the
//     adopter ran, a second account reads metric (the device key is gone);
//     BEFORE it, the second account reads the device value (the bounded
//     pre-adopter window, stated in the plan);
//   - `UnitsPrefAdopter.runIfNeeded` over every outcome.
// PRESENCE (stated): the adopter's two call sites (both heal paths, each in
// its own try with its own reason, the background one before the reckon) and
// its absence from `_ensureLocalUser`.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/units_pref_adopter.dart';
import 'package:icanbefitter/core/utils/unit_prefs_rule.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/features/profile/providers/body_measurements_provider.dart';
import 'package:icanbefitter/features/profile/services/profile_write_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../helpers/hive_test_setup.dart';

const _otherUser = '9e9e9e9e-aaaa-bbbb-cccc-dddddddddddd';

String _noComments(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

String _src(String path) => _noComments(File(path).readAsStringSync());

/// The body of the top-level or member function whose declaration contains
/// [signature], from its first `{` to the matching `}`.
String _body(String src, String signature) {
  final at = src.indexOf(signature);
  expect(at, isNonNegative, reason: 'declaration "$signature" not found');
  // The body brace follows the parameter list's `)` (a `{` inside the list
  // opens named parameters, not the body).
  final head = RegExp(r'\)\s*(async\s*)?\{').firstMatch(src.substring(at));
  expect(head, isNotNull, reason: 'no body for "$signature"');
  final open = at + head!.end - 1;
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) return src.substring(open, i + 1);
    }
  }
  fail('unbalanced body for "$signature"');
}

void main() {
  late Directory tempDir;
  late List<String> events;

  Map<dynamic, dynamic>? profile() =>
      HiveService.instance.userBox.get('profile') as Map?;

  Future<void> seedProfile([Map<String, dynamic> extra = const {}]) =>
      HiveService.instance.userBox.put(
        'profile',
        <String, dynamic>{'full_name': 'T', 'primary_goal': 'build_muscle', ...extra},
      );

  setUp(() async {
    tempDir = await setUpHiveForTests();
    SyncService.pausedForSimulation = true;
    events = <String>[];
    ErrorTelemetry.debugOnLogEventForTests =
        (op, {message}) => events.add('$op ${message ?? ''}'.trim());
    ErrorTelemetry.debugOnRecordNonFatalForTests =
        (error, stack, {required reason, extra}) => events.add('nf $reason');
    UnitsPrefAdopter.debugRestoreSettledOverride = () => true;
  });

  tearDown(() async {
    UnitsPrefAdopter.debugRestoreSettledOverride = null;
    ErrorTelemetry.debugOnLogEventForTests = null;
    ErrorTelemetry.debugOnRecordNonFatalForTests = null;
    SyncService.pausedForSimulation = false;
    await tearDownHiveForTests(tempDir);
  });

  group('the pure rule', () {
    test('values written are exactly the column vocabulary', () {
      expect(unitsSystemValue(metric: true), 'metric');
      expect(unitsSystemValue(metric: false), 'imperial');
      expect(measurementUnitValue(inches: true), 'in');
      expect(measurementUnitValue(inches: false), 'cm');
    });

    test('readers: absent is null (fall back); a bad value is the default', () {
      expect(metricFromProfileValue(null), isNull);
      expect(metricFromProfileValue('imperial'), isFalse);
      expect(metricFromProfileValue('metric'), isTrue);
      expect(metricFromProfileValue('feet'), isTrue);
      expect(metricFromProfileValue(false), isTrue);
      expect(inchesFromProfileValue(null), isNull);
      expect(inchesFromProfileValue('in'), isTrue);
      expect(inchesFromProfileValue('cm'), isFalse);
      expect(inchesFromProfileValue('xx'), isFalse);
    });
  });

  group('setUnitsMetric -> getUnitsMetric', () {
    test('writes the profile field and the reader follows it, both ways',
        () async {
      await seedProfile();
      expect(await UserRepository.instance.setUnitsMetric(false), isTrue);
      expect(profile()!['units_system'], 'imperial');
      expect(UserRepository.instance.getUnitsMetric(), isFalse);
      expect(await UserRepository.instance.setUnitsMetric(true), isTrue);
      expect(profile()!['units_system'], 'metric');
      expect(UserRepository.instance.getUnitsMetric(), isTrue);
      expect(HiveService.instance.configBox.containsKey('units_metric'),
          isFalse, reason: 'the shared device key is never written');
    });

    test('no profile: nothing is written and no stub is created', () async {
      expect(await UserRepository.instance.setUnitsMetric(false), isFalse);
      expect(HiveService.instance.userBox.containsKey('profile'), isFalse);
      expect(HiveService.instance.configBox.containsKey('units_metric'),
          isFalse);
    });

    test('no owner: nothing is written', () async {
      await seedProfile();
      await HiveUserSession.closeAll();
      expect(HiveUserSession.currentOwnerFullId, isNull);
      expect(await UserRepository.instance.setUnitsMetric(false), isFalse);
      await HiveUserSession.openForUser(kTestUserId);
      expect(profile()!.containsKey('units_system'), isFalse);
    });

    test('a bad stored value reads as metric', () async {
      await seedProfile({'units_system': 'feet'});
      expect(UserRepository.instance.getUnitsMetric(), isTrue);
    });

    test('a throwing read answers metric and logs units_pref_read_failed',
        () async {
      // An IMPERIAL device: a catch that fell back to the device key would
      // answer imperial, so only metric proves the throw path.
      await HiveService.instance.configBox.put('units_metric', false);
      await HiveUserSession.closeAll();
      expect(UserRepository.instance.getUnitsMetric(), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(events, contains('units_pref_read_failed stage=units_system'));
    });
  });

  group('the legacy device key is a fallback only', () {
    test('profile without units_system + device false -> imperial', () async {
      await seedProfile();
      await HiveService.instance.configBox.put('units_metric', false);
      expect(UserRepository.instance.getUnitsMetric(), isFalse);
    });

    test('profile metric + device false -> metric (the profile wins)',
        () async {
      await seedProfile({'units_system': 'metric'});
      await HiveService.instance.configBox.put('units_metric', false);
      expect(UserRepository.instance.getUnitsMetric(), isTrue);
    });

    test('a non-bool device value does not throw (reads metric)', () async {
      await seedProfile();
      await HiveService.instance.configBox.put('units_metric', 'garbage');
      expect(UserRepository.instance.getUnitsMetric(), isTrue);
      expect(events, isEmpty);
    });
  });

  group('the measurement unit', () {
    ProviderContainer container() {
      final c = ProviderContainer(overrides: [
        authUserIdTokenProvider.overrideWithValue(kTestUserId),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('preferredInches reads measurement_unit before the units setting',
        () async {
      await seedProfile({'units_system': 'metric', 'measurement_unit': 'in'});
      expect(container().read(measurementWriteProvider.notifier)
          .preferredInches(), isTrue);
    });

    test('a bad measurement_unit reads as centimetres (not the setting)',
        () async {
      await seedProfile(
          {'units_system': 'imperial', 'measurement_unit': 'xx'});
      expect(container().read(measurementWriteProvider.notifier)
          .preferredInches(), isFalse);
    });

    test('absent measurement_unit falls back to the legacy per-user key',
        () async {
      await seedProfile({'units_system': 'metric'});
      await HiveService.instance.userBox
          .put('body_measurement_sheet_unit', 'in');
      expect(container().read(measurementWriteProvider.notifier)
          .lastUnitInches(), isTrue);
    });
  });

  group('two accounts on one device', () {
    Future<void> switchTo(String uid) async {
      await HiveUserSession.closeAll();
      await HiveUserSession.openForUser(uid);
    }

    test('each account reads only its own profile value', () async {
      await seedProfile({'units_system': 'imperial'});
      await switchTo(_otherUser);
      await seedProfile({'units_system': 'metric'});
      expect(UserRepository.instance.getUnitsMetric(), isTrue);
      await switchTo(kTestUserId);
      expect(UserRepository.instance.getUnitsMetric(), isFalse);
    });

    test('BEFORE the adopter, a second account reads the device value '
        '(the bounded pre-adopter window); AFTER it, metric', () async {
      await HiveService.instance.configBox.put('units_metric', false);
      await seedProfile();
      await switchTo(_otherUser);
      await seedProfile();
      expect(UserRepository.instance.getUnitsMetric(), isFalse,
          reason: 'pre-adopter: the one device-wide value');
      await switchTo(kTestUserId);
      expect(await UnitsPrefAdopter.runIfNeeded(), UnitsAdoptOutcome.copied);
      await switchTo(_otherUser);
      expect(UserRepository.instance.getUnitsMetric(), isTrue,
          reason: 'the device key is gone; this account never set one');
      expect(await UnitsPrefAdopter.runIfNeeded(),
          UnitsAdoptOutcome.alreadyDone);
      expect(profile()!.containsKey('units_system'), isFalse,
          reason: 'the second account is not written');
    });
  });

  group('B-pass F2: the owner changes while the write waits on the lock', () {
    Future<void> switchTo(String uid) async {
      await HiveUserSession.closeAll();
      await HiveUserSession.openForUser(uid);
    }

    // Holds the profile lock, starts [write], swaps to the other account,
    // releases, and returns what [write] answered. Neither profile may change.
    Future<T> raceOwnerSwap<T>(Future<T> Function() write) async {
      await seedProfile();
      final release = Completer<void>();
      final held = ProfileWriteService.instance.debugHoldLockUntil(release.future);
      final pending = write();
      await Future<void>.delayed(Duration.zero);
      await switchTo(_otherUser);
      await seedProfile();
      release.complete();
      await held;
      final answer = await pending;
      expect(profile()!.containsKey('units_system'), isFalse,
          reason: 'the account that took over is never written');
      expect(profile()!.containsKey('measurement_unit'), isFalse);
      await switchTo(kTestUserId);
      expect(profile()!.containsKey('units_system'), isFalse,
          reason: 'the write was refused, not redirected');
      expect(profile()!.containsKey('measurement_unit'), isFalse);
      return answer;
    }

    test('setUnitsMetric', () async {
      expect(await raceOwnerSwap(() => UserRepository.instance.setUnitsMetric(false)),
          isFalse);
    });

    test('UnitsPrefAdopter.runIfNeeded: no flag, key kept (retried later)',
        () async {
      await HiveService.instance.configBox.put('units_metric', false);
      expect(await raceOwnerSwap(UnitsPrefAdopter.runIfNeeded),
          UnitsAdoptOutcome.noProfile);
      expect(HiveService.instance.configBox.containsKey('units_metric'), isTrue);
      expect(HiveService.instance.migrationBox.get(UnitsPrefAdopter.flagKey),
          isNot(true));
    });

    test('MeasurementWriteNotifier.save (the measurement unit)', () async {
      final c = ProviderContainer(overrides: [
        authUserIdTokenProvider.overrideWithValue(kTestUserId),
      ]);
      addTearDown(c.dispose);
      final res = await raceOwnerSwap(() => c
          .read(measurementWriteProvider.notifier)
          .save(sites: {'waist': 80.0}, source: WriteSource.manual, inchesUsed: true));
      expect(res.success, isTrue);
    });
  });

  group('UnitsPrefAdopter.runIfNeeded', () {
    bool flag() =>
        HiveService.instance.migrationBox.get(UnitsPrefAdopter.flagKey) == true;
    bool deviceKey() =>
        HiveService.instance.configBox.containsKey('units_metric');

    test('device imperial, profile without the field: copied once, key gone, '
        'flag set', () async {
      await seedProfile();
      await HiveService.instance.configBox.put('units_metric', false);
      expect(await UnitsPrefAdopter.runIfNeeded(), UnitsAdoptOutcome.copied);
      expect(profile()!['units_system'], 'imperial');
      expect(deviceKey(), isFalse);
      expect(flag(), isTrue);
      expect(events, contains('units_pref_adopted outcome=copied'));
      expect(UserRepository.instance.getUnitsMetric(), isFalse);
    });

    test('a profile value already present is NOT overwritten (only if '
        'absent); key dropped, flag set', () async {
      await seedProfile({'units_system': 'metric'});
      await HiveService.instance.configBox.put('units_metric', false);
      expect(await UnitsPrefAdopter.runIfNeeded(),
          UnitsAdoptOutcome.profileAlreadySet);
      expect(profile()!['units_system'], 'metric');
      expect(deviceKey(), isFalse);
      expect(flag(), isTrue);
    });

    test('device key absent: no write, flag set', () async {
      await seedProfile();
      expect(await UnitsPrefAdopter.runIfNeeded(),
          UnitsAdoptOutcome.noDeviceKey);
      expect(profile()!.containsKey('units_system'), isFalse);
      expect(flag(), isTrue);
    });

    test('no profile: nothing written, no flag, key kept (a later settled '
        'restore retries)', () async {
      await HiveService.instance.configBox.put('units_metric', false);
      expect(await UnitsPrefAdopter.runIfNeeded(), UnitsAdoptOutcome.noProfile);
      expect(HiveService.instance.userBox.containsKey('profile'), isFalse);
      expect(deviceKey(), isTrue);
      expect(flag(), isFalse);
    });

    test('B-pass F4: a sign-up STUB profile ({id, email, created_at}) is '
        'not a profile: nothing written, no flag, key kept', () async {
      await HiveService.instance.userBox.put('profile', <String, dynamic>{
        'id': kTestUserId,
        'email': 't@x.test',
        'created_at': '2026-11-24T00:00:00.000',
      });
      await HiveService.instance.configBox.put('units_metric', false);
      expect(await UnitsPrefAdopter.runIfNeeded(), UnitsAdoptOutcome.noProfile);
      expect(profile()!.containsKey('units_system'), isFalse);
      expect(deviceKey(), isTrue);
      expect(flag(), isFalse);
      // MIRROR: a height alone (no goal yet) is real data.
      await HiveService.instance.userBox.put('profile',
          <String, dynamic>{'id': kTestUserId, 'height_cm': 175.0});
      expect(await UnitsPrefAdopter.runIfNeeded(), UnitsAdoptOutcome.copied);
      expect(profile()!['units_system'], 'imperial');
    });

    test('profileHasRealData: a goal or a height; empty and stub are not', () {
      expect(UnitsPrefAdopter.profileHasRealData(const {}), isFalse);
      expect(UnitsPrefAdopter.profileHasRealData(const {'id': 'x', 'email': 'e'}),
          isFalse);
      expect(UnitsPrefAdopter.profileHasRealData(const {'primary_goal': 'cut'}),
          isTrue);
      expect(UnitsPrefAdopter.profileHasRealData(const {'height_cm': 170}), isTrue);
    });

    test('restore not settled: no write, no flag', () async {
      UnitsPrefAdopter.debugRestoreSettledOverride = () => false;
      await seedProfile();
      await HiveService.instance.configBox.put('units_metric', false);
      expect(await UnitsPrefAdopter.runIfNeeded(), UnitsAdoptOutcome.notReady);
      expect(profile()!.containsKey('units_system'), isFalse);
      expect(deviceKey(), isTrue);
      expect(flag(), isFalse);
    });

    test('no owner: no write, no flag', () async {
      await seedProfile();
      await HiveService.instance.configBox.put('units_metric', false);
      await HiveUserSession.closeAll();
      expect(await UnitsPrefAdopter.runIfNeeded(), UnitsAdoptOutcome.notReady);
      expect(deviceKey(), isTrue);
      expect(flag(), isFalse);
      await HiveUserSession.openForUser(kTestUserId);
      expect(profile()!.containsKey('units_system'), isFalse);
    });

    test('device true (metric) is copied as metric', () async {
      await seedProfile();
      await HiveService.instance.configBox.put('units_metric', true);
      expect(await UnitsPrefAdopter.runIfNeeded(), UnitsAdoptOutcome.copied);
      expect(profile()!['units_system'], 'metric');
    });

    test('the real gate is SyncService.restoreSettledForCurrentUser', () {
      final src = _src('lib/core/services/units_pref_adopter.dart');
      expect(src, contains('SyncService.instance.restoreSettledForCurrentUser'));
      final run = _body(src, 'static Future<UnitsAdoptOutcome> runIfNeeded()');
      expect(run.indexOf('_restoreSettled()'),
          lessThan(run.indexOf('patchProfileWith(')));
    });
  });

  group('PRESENCE: the adopter call sites', () {
    const healFile = 'lib/features/auth/screens/restoring/heal_after_restore.dart';
    const screenFile = 'lib/features/auth/screens/restoring_screen.dart';

    test('the helper wraps the adopter in its own try with the caller reason',
        () {
      final helper = _body(
          _src(healFile), 'Future<void> _runUnitsPrefAdopter(');
      expect(helper, contains('try {'));
      expect(helper, contains('await UnitsPrefAdopter.runIfNeeded();'));
      expect(helper, contains('recordNonFatal(e, st, reason: reason)'));
    });

    test('the background heal runs it BEFORE the reckon (whose tick is last)',
        () {
      final bg = _body(
          _src(healFile), 'Future<void> _healAfterRestoreInBackground()');
      const call =
          "await _runUnitsPrefAdopter(reason: 'bg_heal_units_pref_adopter');";
      expect(call.allMatches(bg).length, 1);
      expect(bg.indexOf(call),
          lessThan(bg.indexOf('reckonAndNotifyAfterRestore()')));
    });

    test('the foreground heal runs it with a distinct reason', () {
      final fg = _body(_src(screenFile),
          'Future<void> _ensureOwnershipBeforeHome(String sessionUserId)');
      const call =
          "await _runUnitsPrefAdopter(reason: 'restoring_units_pref_adopter');";
      expect(call.allMatches(fg).length, 1);
      expect(fg.indexOf(call), greaterThan(fg.indexOf('openForUser(')));
    });

    test('NOT from _ensureLocalUser (it never runs at a persisted-session '
        'launch)', () {
      final auth =
          _src('lib/features/auth/providers/auth_provider.dart');
      expect(auth, isNot(contains('UnitsPrefAdopter')));
      // Exactly the two heal paths call it anywhere in lib/.
      final callers = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => _noComments(f.readAsStringSync())
              .contains('UnitsPrefAdopter.runIfNeeded()'))
          .map((f) => f.path.replaceAll(r'\', '/'))
          .toList();
      expect(callers, [healFile]);
    });
  });
}
