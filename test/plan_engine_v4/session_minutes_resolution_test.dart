// B2 Task 0 (docs/plans/2026-10-22-session-set-budget.md): the
// `enable_session_set_budget` flag, the session-minutes resolution and the Edit
// Profile default.
//
// The FIRST test runs before any Hive.init so the getter's catch branch (no Hive
// -> OFF) is what answers; the Hive group opens boxes afterwards. Same ordering
// rule as test/plan_engine_v4/thin_day_topup_flag_test.dart.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/training_history_analyzer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the flag defaults FALSE when Hive is unavailable (catch branch)', () {
    expect(PlanEngineFlags.sessionSetBudgetEnabled, isFalse);
  });

  group('SessionBudget.resolveMinutes', () {
    // (param, profileValue) -> expected, the plan's Task 0 table.
    final cases = <(int?, Object?, int)>[
      (45, 90, 45), // a caller's value wins
      (null, 75, 75), // else the profile's
      (null, null, 60), // else the default
      (null, 'abc', 60), // a non-number profile value is ignored
      (5, null, 60), // a param under 15 is ignored
      (5, 75, 75), // ... and falls through to the profile
      (null, double.nan, 60), // NaN is not a number of minutes
    ];
    for (final (param, profile, expected) in cases) {
      test('param $param, profile $profile -> $expected', () {
        expect(
          SessionBudget.resolveMinutes(param: param, profileValue: profile),
          expected,
        );
      });
    }

    test('the range is inclusive: 15 and 180 are kept, 14 and 181 are not', () {
      expect(SessionBudget.resolveMinutes(param: 15), 15);
      expect(SessionBudget.resolveMinutes(param: 180), 180);
      expect(SessionBudget.resolveMinutes(param: 14), 60);
      expect(SessionBudget.resolveMinutes(param: 181), 60);
      expect(SessionBudget.resolveMinutes(profileValue: 14.4), 60);
      expect(SessionBudget.resolveMinutes(profileValue: 14.6), 15);
      // The same edges through the profile path, which rounds first.
      expect(SessionBudget.resolveMinutes(profileValue: 180), 180);
      expect(SessionBudget.resolveMinutes(profileValue: 180.4), 180);
      expect(SessionBudget.resolveMinutes(profileValue: 180.6), 60);
      expect(SessionBudget.resolveMinutes(profileValue: 15), 15);
    });

    test('an infinite or negative profile value falls to the default', () {
      expect(SessionBudget.resolveMinutes(profileValue: double.infinity), 60);
      expect(SessionBudget.resolveMinutes(profileValue: -30), 60);
    });
  });

  group('SessionBudget.initialSessionDuration (the Edit Profile default)', () {
    test('an empty profile -> 60', () {
      expect(SessionBudget.initialSessionDuration(const {}), 60);
      expect(SessionBudget.defaultMinutes, 60);
    });

    test('a saved 90.0 (a JSON double) -> 90, not a cast error', () {
      expect(
        SessionBudget.initialSessionDuration({'session_duration_minutes': 90.0}),
        90,
      );
    });

    test('a saved 45 -> 45; a saved null -> 60', () {
      expect(
        SessionBudget.initialSessionDuration({'session_duration_minutes': 45}),
        45,
      );
      expect(
        SessionBudget.initialSessionDuration({'session_duration_minutes': null}),
        60,
      );
    });
  });

  group('edit_profile_screen.dart (presence only)', () {
    // Source-grep: proves the call is wired, not that it behaves. The behaviour
    // is the group above. Comments are stripped first so an explanatory comment
    // that still names the old default cannot satisfy or break the check.
    final code = File('lib/features/profile/screens/edit_profile_screen.dart')
        .readAsLinesSync()
        .map((l) {
          final i = l.indexOf('//');
          return i < 0 ? l : l.substring(0, i);
        })
        .join('\n');

    test('the initial value comes from SessionBudget.initialSessionDuration', () {
      expect(code, contains('SessionBudget.initialSessionDuration('));
    });

    test('no "?? 90" default is left in code', () {
      expect(code, isNot(contains('?? 90')));
    });
  });

  group('with Hive', () {
    const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('test_session_minutes');
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
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    setUp(() async {
      for (final name in [
        HiveService.configBoxName,
        HiveService.migrationBoxName,
        'userBox_aaaaaaaa',
        'workoutBox_aaaaaaaa',
        'nutritionBox_aaaaaaaa',
        'healthBox_aaaaaaaa',
        'coachBox_aaaaaaaa',
      ]) {
        if (Hive.isBoxOpen(name)) await Hive.box(name).close();
        try {
          await Hive.deleteBoxFromDisk(name);
        } catch (_) {}
      }
      await Hive.openBox(HiveService.configBoxName);
      await Hive.openBox(HiveService.migrationBoxName);
      HiveService.instance.markInitializedForTests();
      await HiveUserSession.openForUser(testUser);
      TrainingHistoryAnalyzer.debugReadCount = 0;
    });

    tearDown(() async {
      await HiveUserSession.closeAll();
    });

    test('unset -> OFF', () {
      expect(PlanEngineFlags.sessionSetBudgetEnabled, isFalse);
    });

    test('enable_session_set_budget: true -> ON', () async {
      await HiveService.instance.configBox.put('enable_session_set_budget', true);
      expect(PlanEngineFlags.sessionSetBudgetEnabled, isTrue);
    });

    test('false, and a non-bool "true", stay OFF (the check is == true)',
        () async {
      await HiveService.instance.configBox
          .put('enable_session_set_budget', false);
      expect(PlanEngineFlags.sessionSetBudgetEnabled, isFalse);
      await HiveService.instance.configBox
          .put('enable_session_set_budget', 'true');
      expect(PlanEngineFlags.sessionSetBudgetEnabled, isFalse);
    });

    test('sessionMinutesFromProfile: no profile -> null', () {
      expect(TrainingHistoryAnalyzer.sessionMinutesFromProfile(), isNull);
    });

    test('sessionMinutesFromProfile: returns the stored value untouched',
        () async {
      await HiveService.instance.userBox
          .put('profile', {'session_duration_minutes': 75});
      expect(TrainingHistoryAnalyzer.sessionMinutesFromProfile(), 75);
      await HiveService.instance.userBox
          .put('profile', {'session_duration_minutes': 'abc'});
      expect(TrainingHistoryAnalyzer.sessionMinutesFromProfile(), 'abc');
      await HiveService.instance.userBox.put('profile', {'name': 'x'});
      expect(TrainingHistoryAnalyzer.sessionMinutesFromProfile(), isNull);
    });

    test('debugReadCount counts every call, hit or miss', () async {
      expect(TrainingHistoryAnalyzer.debugReadCount, 0);
      TrainingHistoryAnalyzer.sessionMinutesFromProfile();
      await HiveService.instance.userBox
          .put('profile', {'session_duration_minutes': 60});
      TrainingHistoryAnalyzer.sessionMinutesFromProfile();
      expect(TrainingHistoryAnalyzer.debugReadCount, 2);
    });

    test('the end-to-end chain: stored 30 -> resolveMinutes 30', () async {
      await HiveService.instance.userBox
          .put('profile', {'session_duration_minutes': 30});
      expect(
        SessionBudget.resolveMinutes(
          profileValue: TrainingHistoryAnalyzer.sessionMinutesFromProfile(),
        ),
        30,
      );
    });
  });
}
