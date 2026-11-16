// Unit 3B (OI-487, founder d4 / d69 / d71 / d72, 2026-11-16): the stored legacy goal is moved.
//
// SoT concept `legacy_goal_heal`. Plan `docs/plans/2026-11-16-generator-step3b-goal-list.md` §2.2.
//
// Behavioural, real Hive:
//   - `legacyGoalPatch`: the d71 focus table (strength x every focus), recompose x every focus, every other goal ->
//     null.
//   - `legacyGoalHealPatch`: the targets are the NEW goal's (Build's surplus, Cut's deficit), computed by the same
//     `recomputeDerivedTargets` the restore and Edit Profile use; `carb_grams` (Hive-only) included; the recompute
//     switch leaves them out; an incomplete profile heals the goal alone.
//   - `LegacyGoalHealer.run`: one write of goal + focus + targets; the kill switch, a null uid, a foreign live uid, a
//     foreign Hive owner and an owner change between the call and the lock each write nothing; a goal saved as a
//     selectable goal before the lock is left alone; a second run writes nothing; a legacy value merged back by a later
//     restore (a failed push) is healed again; the telemetry event.
// PRESENCE (stated): the wrapper wiring in `SyncService.restoreFromCloudForUser` (the core needs Supabase): healed only
// on `result.succeeded`, with the captured uid and `_liveUserId`, NOT behind the title heal's `shouldHealAfterRestore`,
// before the restore marker settles.
//
// Mutations (diagnose table): the focus rule overwrites a chosen focus; recompose -> build_muscle; the owner re-check
// inside the lock removed; the targets left out of the patch; the call site moved behind `shouldHealAfterRestore`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/fitness_goals.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/legacy_goal_healer.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/features/profile/services/profile_target_recompute.dart';
import 'package:icanbefitter/features/profile/services/profile_write_service.dart';

import '../helpers/hive_test_setup.dart';

/// A profile complete enough for `recomputeDerivedTargets`.
Map<String, dynamic> _profile(String goal, {Object? focus = 'balanced', bool withFocus = true}) => {
      'primary_goal': goal,
      if (withFocus) 'physique_focus': focus,
      'current_weight_kg': 80.0,
      'height_cm': 178.0,
      'date_of_birth': '1995-06-15',
      'gender': 'male',
      'lifestyle_activity': 'desk_job',
      'days_per_week': 4,
      'pace_preference': 'balanced',
      'fitness_experience': 'intermediate',
      'daily_calories': 1111, // a stale target the heal must replace
    };

final _now = DateTime(2026, 11, 16, 9);

String _noComments(String s) => s.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '').replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  group('legacyGoalPatch (pure, d4 / d71 / d72)', () {
    test('strength -> Build, Strength focus only when the focus is unset or Balanced', () {
      for (final unset in <Object?>[null, '', '  ', 'balanced']) {
        expect(legacyGoalPatch(_profile('strength', focus: unset)),
            {'primary_goal': 'build_muscle', 'physique_focus': 'strength'},
            reason: 'focus ${unset == null ? 'null' : "'$unset'"}');
      }
      expect(legacyGoalPatch(_profile('strength', withFocus: false)),
          {'primary_goal': 'build_muscle', 'physique_focus': 'strength'},
          reason: 'focus absent');
      for (final chosen in ['glutes_legs', 'chest_shoulders_arms', 'strength']) {
        expect(legacyGoalPatch(_profile('strength', focus: chosen)), {'primary_goal': 'build_muscle'},
            reason: 'a chosen focus ($chosen) is kept (d71)');
      }
    });

    test('recompose -> Cut, focus never touched', () {
      for (final focus in <Object?>[null, 'balanced', 'glutes_legs', 'chest_shoulders_arms', 'strength']) {
        expect(legacyGoalPatch(_profile('recompose', focus: focus)), {'primary_goal': 'lose_fat'}, reason: '$focus');
      }
    });

    test('a selectable goal, a missing goal, a non-string and an unknown token -> null', () {
      for (final g in [...FitnessGoals.selectableTokens, 'powerlifting', '']) {
        expect(legacyGoalPatch(_profile(g)), isNull, reason: g);
      }
      expect(legacyGoalPatch({'physique_focus': 'balanced'}), isNull);
      expect(legacyGoalPatch({'primary_goal': 7}), isNull);
    });

    test('every legacy target is selectable, and the legacy set is FitnessGoals.tokens minus the selectable list', () {
      expect(FitnessGoals.legacyTargets.keys.toSet(),
          FitnessGoals.tokens.toSet().difference(FitnessGoals.selectableTokens.toSet()));
      for (final t in FitnessGoals.legacyTargets.values) {
        expect(FitnessGoals.isSelectable(t), isTrue, reason: t);
      }
    });
  });

  group('legacyGoalHealPatch (targets)', () {
    test('strength heals to Build\'s targets, recompose to Cut\'s, in the same patch', () {
      for (final (legacy, target) in [('strength', 'build_muscle'), ('recompose', 'lose_fat')]) {
        final patch = legacyGoalHealPatch(_profile(legacy), now: _now, recomputeTargets: true, bodyFatCalcDisabled: false)!;
        final expected = recomputeDerivedTargets(_profile(target), now: _now)!;
        expect(patch['primary_goal'], target);
        expect(patch['daily_calories'], expected['daily_calories'], reason: legacy);
        expect(patch['protein_grams'], expected['protein_grams'], reason: legacy);
        expect(patch.containsKey('carb_grams'), isTrue, reason: 'the Hive-only key the nutrition reader uses');
        // The new goal's calories differ from the legacy goal's (the d71 / d72 change is real).
        final legacyTargets = recomputeDerivedTargets(_profile(legacy), now: _now)!;
        expect(patch['daily_calories'], isNot(legacyTargets['daily_calories']), reason: legacy);
      }
      // Build is a surplus, Cut a deficit, against the same body.
      final build = legacyGoalHealPatch(_profile('strength'), now: _now, recomputeTargets: true, bodyFatCalcDisabled: false)!;
      final cut = legacyGoalHealPatch(_profile('recompose'), now: _now, recomputeTargets: true, bodyFatCalcDisabled: false)!;
      expect((build['daily_calories'] as num) > (cut['daily_calories'] as num), isTrue);
    });

    test('the recompute switch leaves the targets out; an incomplete profile heals the goal alone', () {
      expect(legacyGoalHealPatch(_profile('strength'), now: _now, recomputeTargets: false, bodyFatCalcDisabled: false),
          {'primary_goal': 'build_muscle', 'physique_focus': 'strength'});
      expect(
          legacyGoalHealPatch({'primary_goal': 'recompose'}, now: _now, recomputeTargets: true, bodyFatCalcDisabled: false),
          {'primary_goal': 'lose_fat'});
      expect(legacyGoalHealPatch(_profile('lose_fat'), now: _now, recomputeTargets: true, bodyFatCalcDisabled: false),
          isNull);
    });
  });

  group('LegacyGoalHealer.run (real Hive)', () {
    late Directory tempDir;
    final events = <String>[];

    setUp(() async {
      tempDir = await setUpHiveForTests();
      events.clear();
      ErrorTelemetry.debugOnLogEventForTests = (op, {message}) => events.add('$op $message');
    });

    tearDown(() async {
      ErrorTelemetry.debugOnLogEventForTests = null;
      await tearDownHiveForTests(tempDir);
    });

    Map<String, dynamic> stored() => Map<String, dynamic>.from(HiveService.instance.userBox.get('profile') as Map);
    Future<void> put(Map<String, dynamic> p) => HiveService.instance.userBox.put('profile', p);
    Future<bool> run({String? uid = kTestUserId, String? Function()? live}) =>
        LegacyGoalHealer.run(uid, liveUid: live ?? () => kTestUserId, now: () => _now);

    test('one write: goal, focus and the new goal\'s targets; telemetry; a second run writes nothing', () async {
      await put(_profile('strength'));
      expect(await run(), isTrue);
      final p = stored();
      expect(p['primary_goal'], 'build_muscle');
      expect(p['physique_focus'], 'strength');
      expect(p['daily_calories'], recomputeDerivedTargets(_profile('build_muscle'), now: _now)!['daily_calories']);
      expect(p['carb_grams'], isNotNull);
      expect(p['updated_at'], isNotNull);
      expect(events, ['${LegacyGoalHealer.healedEvent} strength->build_muscle focus_set']);
      final again = stored();
      expect(await run(), isFalse);
      expect(stored(), again);
    });

    test('recompose heals to Cut and keeps a chosen focus', () async {
      await put(_profile('recompose', focus: 'chest_shoulders_arms'));
      expect(await run(), isTrue);
      expect(stored()['primary_goal'], 'lose_fat');
      expect(stored()['physique_focus'], 'chest_shoulders_arms');
      expect(events.single, endsWith('recompose->lose_fat focus_kept'));
    });

    test('the kill switch, a null uid, a foreign live uid and a foreign Hive owner each write nothing', () async {
      await put(_profile('strength'));
      final before = stored();
      await HiveService.instance.configBox.put(LegacyGoalHealer.killSwitch, true);
      expect(await run(), isFalse);
      await HiveService.instance.configBox.delete(LegacyGoalHealer.killSwitch);
      expect(await run(uid: null), isFalse);
      expect(await run(live: () => 'someone-else'), isFalse);
      expect(await run(uid: 'someone-else', live: () => 'someone-else'), isFalse,
          reason: 'the open Hive owner is kTestUserId');
      expect(stored(), before);
      expect(events, isEmpty);
    });

    test('an owner change between the call and the lock writes nothing (the re-check inside patchProfileWith)', () async {
      await put(_profile('strength'));
      final before = stored();
      var calls = 0;
      // First check (outside the lock) sees the user; the re-check under the lock sees another account.
      expect(await run(live: () => ++calls == 1 ? kTestUserId : 'someone-else'), isFalse);
      expect(calls, greaterThanOrEqualTo(2), reason: 'the owner is re-checked inside the lock');
      expect(stored(), before);
    });

    test('a goal saved selectable before the lock is left alone (decided under the lock)', () async {
      await put(_profile('strength'));
      // Writer 1 holds the profile lock (awaiting its disk write); the user's save (Cut) is QUEUED behind it; then the
      // heal starts. Hive updates its in-memory value synchronously, so the only window is a writer still waiting
      // for the lock: a heal that read the profile before taking the lock would see strength and overwrite the
      // queued save with Build. Decided under the lock, it finds Cut and writes nothing.
      final first = ProfileWriteService.instance.patchProfile({'city': 'Pune'});
      final save = ProfileWriteService.instance.patchProfile({'primary_goal': 'lose_fat', 'physique_focus': 'balanced'});
      expect(stored()['primary_goal'], 'strength', reason: 'the save is queued, not yet written');
      final heal = run();
      await first;
      await save;
      expect(await heal, isFalse);
      expect(stored()['city'], 'Pune');
      expect(stored()['primary_goal'], 'lose_fat');
      expect(stored()['physique_focus'], 'balanced');
    });

    test('a legacy value merged back by a later restore (a failed push) is healed again', () async {
      await put(_profile('strength'));
      expect(await run(), isTrue);
      // The next restore merges cloud's legacy goal and its targets back (cloud non-null wins).
      final merged = stored()
        ..['primary_goal'] = 'strength'
        ..['physique_focus'] = 'balanced'
        ..addAll(recomputeDerivedTargets(_profile('strength'), now: _now)!);
      await put(merged);
      expect(await run(), isTrue);
      expect(stored()['primary_goal'], 'build_muscle');
      expect(stored()['daily_calories'], recomputeDerivedTargets(_profile('build_muscle'), now: _now)!['daily_calories']);
    });

    test('the heal fires the profile push exactly once when it writes, never when it writes nothing', () async {
      // The plan's "the normal profile push carries it to the cloud" (ProfileWriteService.patchProfileWith ->
      // _fireSync). No Supabase user in tests, so the seam counts the push decision itself.
      var pushes = 0;
      ProfileWriteService.debugOnFireSync = () => pushes++;
      addTearDown(() => ProfileWriteService.debugOnFireSync = null);
      await put(_profile('strength'));
      expect(await run(), isTrue);
      expect(pushes, 1, reason: 'one write, one push');
      expect(await run(), isFalse);
      expect(pushes, 1, reason: 'a null patch (already healed) pushes nothing');
      await put(_profile('recompose'));
      expect(await run(live: () => 'someone-else'), isFalse);
      var calls = 0;
      expect(await run(live: () => ++calls == 1 ? kTestUserId : 'someone-else'), isFalse);
      expect(pushes, 1, reason: 'a failed owner check (before or under the lock) pushes nothing');
    });

    test('the body-fat switch reaches the target recompute', () async {
      // With a body fat on file the targets come from Katch-McArdle; disable_bodyfat_calc makes them Mifflin's.
      final withFat = {..._profile('strength'), 'body_fat_percent': 12.0};
      final healedFat = {...withFat, 'primary_goal': 'build_muscle', 'physique_focus': 'strength'};
      final katch = recomputeDerivedTargets(healedFat, now: _now)!['daily_calories'];
      final mifflin = recomputeDerivedTargets(healedFat, now: _now, bodyFatCalcDisabled: true)!['daily_calories'];
      expect(katch, isNot(mifflin), reason: 'fixture precondition: the switch changes the calories');
      await put(withFat);
      expect(await run(), isTrue);
      expect(stored()['daily_calories'], katch);
      await put(withFat);
      await HiveService.instance.configBox.put('disable_bodyfat_calc', true);
      addTearDown(() => HiveService.instance.configBox.delete('disable_bodyfat_calc'));
      expect(await run(), isTrue);
      expect(stored()['daily_calories'], mifflin);
    });

    test('the recompute kill switch (the restore\'s) moves the goal without the targets', () async {
      expect(LegacyGoalHealer.recomputeKillSwitch,
          SyncService.kDisableProfileTargetRecomputeKey); // ignore: invalid_use_of_visible_for_testing_member
      await put(_profile('strength'));
      await HiveService.instance.configBox.put(LegacyGoalHealer.recomputeKillSwitch, true);
      expect(await run(), isTrue);
      expect(stored()['primary_goal'], 'build_muscle');
      expect(stored()['daily_calories'], 1111);
      await HiveService.instance.configBox.delete(LegacyGoalHealer.recomputeKillSwitch);
    });
  });

  test('PRESENCE: the restore wrapper heals on every succeeded restore, outside the title heal\'s switch', () {
    final src = _noComments(File('lib/core/services/sync_service.dart').readAsStringSync());
    final start = src.indexOf('Future<RestoreResult> restoreFromCloudForUser()');
    expect(start, greaterThanOrEqualTo(0));
    final body = src.substring(start, src.indexOf('static bool shouldHealAfterRestore', start));
    final call = RegExp(r'if \(result\.succeeded\)\s*\{\s*await LegacyGoalHealer\.run\(uid, liveUid: \(\) => _liveUserId\);\s*\}');
    expect(call.hasMatch(body), isTrue, reason: 'healed exactly under if (result.succeeded) { ... }');
    final titleBlock = RegExp(r'if \(shouldHealAfterRestore\(result\)\)\s*\{[^}]*\}').firstMatch(body)!;
    expect(titleBlock.group(0)!.contains('LegacyGoalHealer'), isFalse, reason: 'not behind the title heal switch');
    expect(body.indexOf('LegacyGoalHealer.run'), lessThan(body.indexOf('_settleRestoreMarker(')));
    expect(body.indexOf('LegacyGoalHealer.run'), greaterThan(body.indexOf('_restoreFromCloudForUserCore()')));
    // Two call sites: this wrapper and the launch path (_restoreIfNeeded, the next test).
    expect(RegExp(r'LegacyGoalHealer\.run\(').allMatches(src).length, 2);
  });

  test('PRESENCE (B-pass): the launch-path restore (both branches of _restoreIfNeeded) heals too', () {
    // checkAndSync merges the cloud profile on every launch with local data (restoreLightweightAlways) or on an empty
    // device (restoreFromCloud), neither of which passes through /restoring; a legacy value the cloud still holds
    // comes back there. The heal follows BOTH branches (after the if / else, not inside one of them).
    final src = _noComments(File('lib/core/services/sync_service.dart').readAsStringSync());
    final start = src.indexOf('Future<void> _restoreIfNeeded(String userId)');
    expect(start, greaterThanOrEqualTo(0));
    final body = src.substring(start, src.indexOf('\n  }\n', start) + 4);
    final tail = RegExp(r'await restoreLightweightAlways\(userId\);\s*\}\s*'
        r'await LegacyGoalHealer\.run\(userId, liveUid: \(\) => _liveUserId\);\s*\}$');
    expect(tail.hasMatch(body.trimRight()), isTrue, reason: body);
  });
}
